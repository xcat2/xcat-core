package xCAT::FreeBSDPackagePlan;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Encode qw(encode decode FB_CROAK LEAVE_SRC);
use Fcntl qw(O_RDONLY O_RDWR O_WRONLY O_CREAT O_EXCL O_NOFOLLOW O_NONBLOCK LOCK_EX S_ISREG S_ISDIR);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;

my $MAX_BYTES = 8388608;
my $MAX_LINE = 32768;
my @IDENTITY = qw(name version origin abi);
my @PACKAGE = (qw(id repository), @IDENTITY, qw(repopath path size sha256 native_sum));
my @REPOSITORY = qw(id publication role trust_type trust_digest);
my @FILE = qw(kind path size sha256);

sub _fail { die "FreeBSD package plan: $_[0]\n"; }

sub _text {
    my ($value, $limit) = @_;
    return defined($value) && !ref($value) && length($value)
      && length($value) <= $limit && $value !~ /[\x00-\x1f\x7f]/x;
}

sub _diagnostic_destination {
    my $destination = shift;
    _fail('Invalid diagnostic destination') if ref($destination) ne 'SCALAR'
      || defined($$destination);
    return;
}

sub _diagnostic_json {
    return JSON->new->ascii->canonical->encode(shift);
}

sub _diagnostic_report {
    my ($scope, $status) = @_;
    return { format => 'xcat-freebsd-package-diagnostics-1', scope => $scope,
        status => $status, records => [] };
}

sub _diagnostic_append {
    my ($report, $diagnostic) = @_;
    if (@{$report->{records}} >= 64 || length(_diagnostic_json($diagnostic)) > 65536) {
        $report->{status} = 'truncated';
        return 0;
    }
    push @{$report->{records}}, $diagnostic;
    # Reserve one byte for the longer truncated status.
    if (length(_diagnostic_json($report)) + 1 > 262144) {
        pop @{$report->{records}};
        $report->{status} = 'truncated';
        return 0;
    }
    return 1;
}

sub _missing_selection {
    my ($message, $destination, $kind, $index, $name) = @_;
    if (defined($destination)) {
        my $bytes = eval {
            my $report = _diagnostic_report('requested-selection', 'complete');
            _diagnostic_append($report, { kind => $kind, selection => $index, name => $name });
            _diagnostic_json($report);
        };
        $$destination = defined($bytes) ? $bytes
          : _diagnostic_json(_diagnostic_report('requested-selection', 'unavailable'));
    }
    return _fail($message);
}

sub _catalogue_diagnostics {
    my ($repositories, $sources, $base_names, $application_names) = @_;
    my $report = _diagnostic_report('imported-catalogue-name-references', 'complete');
    for my $index (0 .. $#$sources) {
        for my $identity (sort keys %{$sources->[$index]{packages}}) {
            my $package = $sources->[$index]{packages}{$identity};
            next unless exists($package->{deps});
            _fail('Invalid diagnostic dependency metadata') unless ref($package->{deps}) eq 'HASH';
            for my $name (sort keys %{$package->{deps}}) {
                _fail('Invalid diagnostic dependency metadata') unless _text($name, 1024)
                  && ref($package->{deps}{$name}) eq 'HASH';
                next if exists($base_names->{$name}) || exists($application_names->{$name});
                my $diagnostic = { kind => 'unavailable-dependency-name', dependency => $name,
                    repository => { map { $_ => $repositories->[$index]{$_} } qw(id publication role) },
                    package => { map { $_ => $package->{$_} } @IDENTITY } };
                return _diagnostic_json($report) unless _diagnostic_append($report, $diagnostic);
            }
        }
    }
    return _diagnostic_json($report);
}

sub _digest {
    my $value = shift;
    return _text($value, 64) && $value =~ /\A[0-9a-f]{64}\z/x;
}

sub _count {
    my ($value, $maximum) = @_;
    return defined($value) && !ref($value) && $value =~ /\A(?:0|[1-9][0-9]{0,10})\z/x
      && $value <= $maximum;
}

sub _fields {
    my ($value, @allowed) = @_;
    my %allowed = map { $_ => 1 } @allowed;
    _fail('Invalid record fields') unless ref($value) eq 'HASH';
    _fail('Unknown record field') if grep { !$allowed{$_} } keys %$value;
    return;
}

sub _path {
    my ($path, $limit) = @_;
    _fail('Invalid package plan path') unless _text($path, $limit);
    for my $part (split(m{/}x, $path, -1)) {
        _fail('Invalid package plan path component') if !length($part) || length($part) > 255
          || $part eq '.' || $part eq '..' || $part !~ /\A[A-Za-z0-9_.,+:~@%=-]+\z/x;
    }
    return;
}

sub _array {
    my ($value, $maximum, $description) = @_;
    _fail("Invalid $description array") if ref($value) ne 'ARRAY' || @$value > $maximum;
    return;
}

sub _repository_index {
    my ($id, $repositories) = @_;
    _fail('Unknown package repository') if !_text($id, 3)
      || $id !~ /\Ar(0|[1-9][0-9]?)\z/x || $1 >= @$repositories;
    return 0 + substr($id, 1);
}

sub _encode {
    my $plan = shift;
    my @rows = (['format', exists($plan->{scope}) ? 'xcat-freebsd-package-plan-2' : 'xcat-freebsd-package-plan-1'],
        ['target', '15.1-RELEASE', 'FreeBSD:15:amd64', '1501000'],
        ['resolver', @{$plan->{resolver}}{qw(version sha256)}]);
    push @rows, ['resolver-libraries', $plan->{resolver}{library_digest}]
      if exists($plan->{resolver}{library_digest});
    push @rows, ['scope', $plan->{scope}] if exists($plan->{scope});
    push @rows, map { ['repository', @{$_}{@REPOSITORY}] } @{$plan->{repositories}};
    push @rows, map { ['prefix', $_->{id}, $_->{prefix}] }
      grep { length($_->{prefix}) } @{$plan->{repositories}};
    for my $repository (@{$plan->{repositories}}) {
        push @rows, map { ['file', $repository->{id}, @{$_}{@FILE}] }
          sort { $a->{path} cmp $b->{path} } @{$repository->{files}};
    }
    push @rows, map { ['component', $_] } @{$plan->{components}};
    push @rows, map { ['application', $_] } @{$plan->{applications}};
    push @rows, map { ['package', @{$_}{@PACKAGE}] } @{$plan->{packages}};
    return encode('UTF-8', join('', map { join("\t", @$_) . "\n" } @rows), FB_CROAK | LEAVE_SRC);
}

sub _check_repository_files {
    my $repository = shift;
    my $role = $repository->{role};
    my $prefix = xCAT::FreeBSDRepo::catalogue_prefix($repository->{prefix});
    my $directory = length($prefix) ? "$role/$prefix" : $role;
    my %expected = ("$directory/meta.conf" => 'meta', "$directory/data.pkg" => 'catalogue',
        "$directory/packagesite.pkg" => 'catalogue');
    $expected{'repository.pub'} = 'key' if $repository->{trust_type} eq 'pubkey';
    my %limits = (catalogue => 67108864, key => 1048576, meta => 65536);
    for my $file (@{$repository->{files}}) {
        my $kind = delete($expected{$file->{path}});
        _fail('Missing, duplicate or misplaced repository file')
          unless defined($kind) && $kind eq $file->{kind};
        _fail('Invalid repository file size or checksum') unless _digest($file->{sha256})
          && _count($file->{size}, $limits{$kind});
        _fail('Repository public key and trust digest disagree')
          if $kind eq 'key' && $file->{sha256} ne $repository->{trust_digest};
    }
    _fail('Missing repository metadata or catalogue') if %expected;
    return;
}

sub _check_repositories {
    my $repositories = shift;
    _array($repositories, 32, 'repository');
    _fail('A base repository is required') unless @$repositories;
    my %seen;
    for my $index (0 .. $#$repositories) {
        my $repository = $repositories->[$index];
        _fail('Repository IDs must be sequential') unless $repository->{id} eq "r$index";
        _fail('Invalid repository publication digest') unless _digest($repository->{publication});
        my $role = $repository->{role};
        _fail('Invalid repository role order') unless $index == 0 ? $role eq 'base'
          : $role eq 'applications' || $role eq 'repository';
        _fail('Duplicate repository publication and role') if $seen{"$repository->{publication}/$role"}++;
        my $trust = $repository->{trust_type};
        _fail('Invalid repository trust type') unless $role eq 'repository'
          ? ($trust eq 'pubkey' || $trust eq 'operator-trusted-tree') : $trust eq 'operator-trusted-release';
        _fail('Invalid repository trust digest') unless _digest($repository->{trust_digest});
        _check_repository_files($repository);
    }
    return;
}

sub _check_package {
    my ($package, $repository) = @_;
    my $role = $repository->{role};
    _path($package->{repopath}, 4096);
    _fail('Invalid logical package archive path') unless $package->{repopath} =~ /[.]pkg\z/x;
    _fail('Package source path has the wrong role') unless index($package->{path}, "$role/") == 0;
    _path(substr($package->{path}, length($role) + 1), 4096);
    _fail('Invalid package size or checksum') unless _count($package->{size}, 17179869184)
      && _digest($package->{sha256});
    _fail('Invalid native package checksum') unless _text($package->{native_sum}, 256)
      && $package->{native_sum} =~ /\A[A-Za-z0-9\$]+\z/x;
    return;
}

sub _check_packages {
    my $plan = shift;
    _array($plan->{packages}, 8192, 'package');
    my $empty = ($plan->{scope} || '') eq 'applications'
      && !@{$plan->{components}} && !@{$plan->{applications}};
    _fail('A package selection is required') unless @{$plan->{packages}} || $empty;
    my (%names, %packages, %paths, %logical);
    my $previous;
    for my $index (0 .. $#{$plan->{packages}}) {
        my $package = $plan->{packages}[$index];
        _fail('Package IDs must be sequential') unless $package->{id} eq "p$index";
        _fail('Invalid package identity') if grep { !_text($package->{$_}, 1024) } @IDENTITY;
        _fail('Conflicting selected package providers') if $names{$package->{name}}++;
        my $repo = _repository_index($package->{repository}, $plan->{repositories});
        my $sortkey = sprintf('%02d', $repo) . "\0" . join("\0", @{$package}{@IDENTITY});
        _fail('Noncanonical package order') if defined($previous) && $previous ge $sortkey;
        $previous = $sortkey;
        _fail('Duplicate selected archive path') if $paths{"$repo\0$package->{path}"}++
          || $logical{"$repo\0$package->{repopath}"}++;
        _check_package($package, $plan->{repositories}[$repo]);
        $packages{$package->{id}} = $package;
    }
    return \%packages;
}

sub _check {
    my $plan = shift;
    if (exists($plan->{scope})) {
        _fail('Invalid scoped package plan') if _scope($plan->{scope}) eq 'all'
          || ($plan->{scope} eq 'base' && @{$plan->{applications}})
          || ($plan->{scope} eq 'applications' && @{$plan->{components}});
    }
    _fail('Unsupported native resolver version') unless $plan->{resolver}{version} eq '2.8.2';
    _fail('Invalid native resolver checksum') unless _digest($plan->{resolver}{sha256});
    _fail('Invalid native resolver library checksum') if exists($plan->{resolver}{library_digest})
      && !_digest($plan->{resolver}{library_digest});
    _check_repositories($plan->{repositories});
    my (%components, %applications);
    for my $component (@{$plan->{components}}) {
        _fail('Invalid or duplicate base component') if $component !~ /\A[a-z][a-z0-9-]{0,63}\z/x
          || $components{$component}++;
    }
    my $packages = _check_packages($plan);
    for my $id (@{$plan->{applications}}) {
        _fail('Unknown or duplicate application root') if !exists($packages->{$id}) || $applications{$id}++;
        _fail('Application root cannot select a base package') if $packages->{$id}{repository} eq 'r0';
    }
    return;
}

sub _decode_line {
    my $line = shift;
    my %arity = (format => 1, target => 3, resolver => 2, 'resolver-libraries' => 1, scope => 1,
        repository => 5, prefix => 2, file => 5, component => 1, application => 1, package => 11);
    _fail('Package plan record is too long') if length($line) > $MAX_LINE;
    my $text = eval { decode('UTF-8', $line, FB_CROAK | LEAVE_SRC) };
    _fail('Invalid package plan UTF-8') unless defined($text);
    my ($kind, @fields) = split(/\t/x, $text, -1);
    _fail('Invalid package plan record') if !defined($kind) || !exists($arity{$kind})
      || @fields != $arity{$kind} || grep { !_text($_, $MAX_LINE) } @fields;
    return ($kind, @fields);
}

sub _singleton {
    my ($plan, $kind, @fields) = @_;
    _fail('Unsupported package plan format') if $kind eq 'format'
      && $fields[0] !~ /\Axcat-freebsd-package-plan-[12]\z/x;
    _fail('Unsupported package plan target') if $kind eq 'target'
      && join("\t", @fields) ne "15.1-RELEASE\tFreeBSD:15:amd64\t1501000";
    @{$plan->{resolver}}{qw(version sha256)} = @fields if $kind eq 'resolver';
    $plan->{resolver}{library_digest} = $fields[0] if $kind eq 'resolver-libraries';
    $plan->{scope} = $fields[0] if $kind eq 'scope';
    return;
}

sub _record {
    my ($plan, $seen, $kind, @fields) = @_;
    if ($kind =~ /\A(?:format|target|resolver|resolver-libraries|scope)\z/x) {
        _fail('Duplicate package plan singleton') if $seen->{$kind}++;
        _singleton($plan, $kind, @fields);
        return;
    }
    if ($kind eq 'repository') {
        my %repository;
        @repository{@REPOSITORY} = @fields;
        push @{$plan->{repositories}}, { %repository, prefix => '', files => [] };
        return;
    }
    if ($kind eq 'prefix' || $kind eq 'file') {
        my $index = _repository_index(shift(@fields), $plan->{repositories});
        if ($kind eq 'prefix') {
            _fail('Duplicate repository prefix') if $seen->{"prefix-$index"}++;
            $plan->{repositories}[$index]{prefix} = $fields[0];
        } else {
            my %file;
            @file{@FILE} = @fields;
            push @{$plan->{repositories}[$index]{files}}, \%file;
        }
        return;
    }
    if ($kind eq 'component' || $kind eq 'application') {
        push @{$plan->{"${kind}s"}}, $fields[0];
        return;
    }
    my %package;
    @package{@PACKAGE} = @fields;
    push @{$plan->{packages}}, \%package;
    return;
}

sub parse {
    my ($bytes) = @_;
    _fail('Parsing requires one byte string') if @_ != 1 || !defined($bytes) || ref($bytes)
      || !utf8::downgrade($bytes, 1) || !length($bytes) || length($bytes) > $MAX_BYTES;
    _fail('Plan requires LF records and a final LF') if $bytes !~ /\n\z/x || $bytes =~ /\r/x;
    my @lines = split(/\n/x, $bytes, -1);
    pop @lines;
    _fail('Too many package plan records') if @lines > 16384;
    my $plan = { resolver => {}, repositories => [], components => [], applications => [], packages => [] };
    my %seen;
    for my $line (@lines) {
        _record($plan, \%seen, _decode_line($line));
    }
    _fail('Missing package plan singleton') unless $seen{format} && $seen{target} && $seen{resolver};
    _check($plan);
    _fail('Noncanonical package plan encoding') unless _encode($plan) eq $bytes;
    return $plan;
}

sub _imports {
    my ($references, $installroot) = @_;
    _array($references, 32, 'repository reference');
    my (@repositories, @sources, %imports);
    for my $index (0 .. $#$references) {
        my $reference = $references->[$index];
        _fields($reference, qw(publication role));
        my ($path, $role) = @{$reference}{qw(publication role)};
        _fail('Invalid repository reference') unless _text($path, 16384) && _text($role, 12)
          && $role =~ /\A(?:base|applications|repository)\z/x;
        my $import = $imports{$path} ||= xCAT::FreeBSDRepoImport::inspect_import($path, $installroot);
        my $published = $import->{repositories}{$role};
        _fail('Requested repository role is absent from publication') unless $published;
        my $source = $import->{kind} eq 'release' ? $import->{source}{repositories}{$role}{repository}
          : $import->{source};
        my $trust = $import->{source}{trust};
        my $repository = { id => "r$index", publication => $import->{digest}, role => $role,
            trust_type => $trust->{type}, trust_digest => $trust->{type} eq 'pubkey' ? $trust->{sha256} : $trust->{digest},
            prefix => $published->{catalogue_prefix}, files => [] };
        for my $name (qw(meta.conf data.pkg packagesite.pkg)) {
            my $relative = length($repository->{prefix}) ? "$repository->{prefix}/$name" : $name;
            my $entry = $published->{tree}{entries}{$relative};
            _fail('Required repository catalogue is not a regular file') unless $entry && $entry->{type} eq 'file';
            push @{$repository->{files}}, { kind => $name eq 'meta.conf' ? 'meta' : 'catalogue',
                path => "$role/$relative", size => $entry->{size}, sha256 => $entry->{sha256} };
        }
        if ($trust->{type} eq 'pubkey') {
            my $entry = $import->{trust_files}{'repository.pub'};
            _fail('Missing published repository public key') unless $entry;
            push @{$repository->{files}}, { kind => 'key', path => 'repository.pub',
                size => $entry->{size}, sha256 => $entry->{sha256} };
        }
        push @repositories, $repository;
        push @sources, $source;
    }
    return (\@repositories, \@sources);
}

sub _selection_key {
    my ($selection, $sources) = @_;
    _fields($selection, qw(repository identity));
    _fail('Invalid selected repository index') if !_count($selection->{repository}, 31)
      || $selection->{repository} >= @$sources;
    my $identity = $selection->{identity};
    _array($identity, 4, 'selected identity');
    _fail('Invalid selected package identity') if @$identity != 4 || grep { !_text($_, 1024) } @$identity;
    return ($selection->{repository}, join("\0", @$identity));
}

sub compose {
    my @arguments = @_;
    _fail('Composition options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fields(\%options, qw(installroot repositories components applications selected resolver scope));
    my $scope = exists($options{scope}) ? _scope($options{scope}) : _scope();
    _array($options{components}, 8192, 'component');
    _array($options{applications}, 8192, 'application');
    _array($options{selected}, 8192, 'selection');
    _fields($options{resolver}, qw(version sha256 library_digest));
    _fail('Invalid resolver identity') unless _text($options{resolver}{version}, 64)
      && _digest($options{resolver}{sha256});
    _fail('Invalid resolver library digest') if exists($options{resolver}{library_digest})
      && !_digest($options{resolver}{library_digest});
    _fail('Invalid base component') if grep { !_text($_, 64) } @{$options{components}};
    my ($repositories, $sources) = _imports($options{repositories}, $options{installroot});
    my (@packages, %selected, %archive_indexes);
    for my $selection (@{$options{selected}}) {
        my ($index, $identity) = _selection_key($selection, $sources);
        my $source = $sources->[$index];
        my $package = $source->{packages}{$identity};
        _fail('Selected package is absent from its repository') unless $package;
        _fail('Duplicate selected package identity') if $selected{"$index\0$identity"}++;
        if (!exists($archive_indexes{$index})) {
            $archive_indexes{$index} = { map { $source->{archives}{$_}{package_identity} => $_ }
                keys %{$source->{archives}} };
        }
        my $path = $archive_indexes{$index}{$identity};
        _fail('Selected package archive is absent') unless defined($path);
        my $archive = $source->{archives}{$path};
        push @packages, { repository => "r$index", map({ $_ => $package->{$_} } @IDENTITY),
            repopath => $package->{repopath}, path => "$repositories->[$index]{role}/$path",
            size => $archive->{size}, sha256 => $archive->{sha256}, native_sum => $archive->{native_sum} };
    }
    @packages = sort { substr($a->{repository}, 1) <=> substr($b->{repository}, 1)
        || join("\0", @{$a}{@IDENTITY}) cmp join("\0", @{$b}{@IDENTITY}) } @packages;
    for my $index (0 .. $#packages) {
        my $package = $packages[$index];
        $package->{id} = "p$index";
        $selected{substr($package->{repository}, 1) . "\0" . join("\0", @{$package}{@IDENTITY})} = $package->{id};
    }
    my @applications;
    for my $application (@{$options{applications}}) {
        my ($repository_index, $identity) = _selection_key($application, $sources);
        my $id = $selected{"$repository_index\0$identity"};
        _fail('Application root is absent from selection') unless defined($id);
        push @applications, $id;
    }
    my $bytes = _encode({ resolver => $options{resolver}, repositories => $repositories,
        components => $options{components}, applications => \@applications, packages => \@packages,
        $scope ne 'all' ? (scope => $scope) : () });
    parse($bytes);
    return $bytes;
}

sub _base_components {
    my $source = shift;
    my %available = (debug => []);
    my %packages;
    for my $package (values %{$source->{packages}}) {
        my $name = $package->{name};
        _fail('Base repository contains competing package names') if exists($packages{$name});
        $packages{$name} = $package;
        if ($name =~ /\AFreeBSD-set-(.+)\z/x) {
            push @{$available{$1}}, $name;
        } elsif ($name =~ /\AFreeBSD-kernel-(?:generic|generic64|generic64le)(-dbg)?\z/x) {
            push @{$available{defined($1) ? 'kernel-dbg' : 'kernel'}}, $name;
        } elsif ($name eq 'pkg') {
            $available{pkg} = [$name];
        }
    }
    for my $required (qw(minimal kernel pkg)) {
        _fail("Base repository requires one $required package")
          unless $available{$required} && @{$available{$required}} == 1;
    }
    for my $name (qw(FreeBSD-ssh FreeBSD-bsdconfig)) {
        _fail("Base repository requires the $name package") unless exists($packages{$name});
    }
    return (\%available, \%packages);
}

sub _base_roots {
    my ($components, $source, $diagnostics) = @_;
    my ($available, $packages) = _base_components($source);
    my %seen;
    my %roots = map { $_ => $packages->{$_} } qw(FreeBSD-ssh FreeBSD-bsdconfig);
    my $component_index = 0;
    for my $component (@$components) {
        ++$component_index;
        _fail('Invalid or duplicate base component') if !_text($component, 64)
          || $component !~ /\A[a-z][a-z0-9-]{0,63}\z/x || $seen{$component}++;
        _missing_selection("Unavailable native base component at selection $component_index",
            $diagnostics, 'missing-component', $component_index, $component)
          unless exists($available->{$component});
    }
    for my $component (qw(minimal pkg kernel), @$components) {
        for my $name (@{$available->{$component}}) {
            $roots{$name} = $packages->{$name};
            if ($seen{debug} && $name !~ /-dbg\z/x && $name =~ /\AFreeBSD-set-(.+)\z/x) {
                my $debug = $available->{"$1-dbg"};
                $roots{$_} = $packages->{$_} for @{$debug || []};
            }
        }
    }
    return \%roots;
}

sub _scope {
    my ($scope) = @_;
    $scope = 'all' unless @_;
    _fail('Invalid package selection scope') unless _text($scope, 16)
      && $scope =~ /\A(?:all|base|applications)\z/x;
    return $scope;
}

sub _scope_selections {
    my ($scope, $components, $applications) = @_;
    return ($scope eq 'applications' ? [] : $components, $scope eq 'base' ? [] : $applications);
}

sub _solver_references {
    my ($references, $repositories) = @_;
    my @catalogues;
    for my $index (0 .. $#$repositories) {
        my $repository = $repositories->[$index];
        my $publication = $references->[$index]{publication};
        my $directory = "$publication/$repository->{role}";
        $directory .= "/$repository->{prefix}" if length($repository->{prefix});
        my $catalogue = { directory => $directory, files => {} };
        for my $file (@{$repository->{files}}) {
            if ($file->{kind} eq 'key') {
                $catalogue->{key} = { path => "$publication/$file->{path}", sha256 => $file->{sha256} };
            } else {
                my ($name) = $file->{path} =~ m{([^/]+)\z}x;
                $catalogue->{files}{$name} = { size => $file->{size}, sha256 => $file->{sha256} };
            }
        }
        push @catalogues, $catalogue;
    }
    return \@catalogues;
}

sub _resolved_job {
    my ($job, $sources) = @_;
    _fields($job, qw(job_type repository package));
    _fail('Native resolver returned a non-install job')
      unless _text($job->{job_type}, 16) && $job->{job_type} eq 'install';
    _fail('Invalid native resolver repository') if !_text($job->{repository}, 3)
      || $job->{repository} !~ /\Ar(0|[1-9][0-9]?)\z/x || $1 >= @$sources;
    my $index = 0 + substr($job->{repository}, 1);
    my $package = $job->{package};
    _fail('Invalid native resolver package') if ref($package) ne 'HASH'
      || grep { !_text($package->{$_}, 1024) } @IDENTITY;
    my $identity = join("\0", @{$package}{@IDENTITY});
    my $source = $sources->[$index]{packages}{$identity};
    _fail('Native selection is absent from its verified repository') unless $source;
    for my $field (qw(repopath sum pkgsize)) {
        _fail("Native selected $field differs from its verified repository")
          unless _text($package->{$field}, 4096) && $package->{$field} eq $source->{$field};
    }
    return ($index, $package);
}

sub _resolved_jobs {
    my ($jobs, $sources, $roots, $applications, $diagnostics) = @_;
    my (@selected, %names);
    my %base_names = map { $_->{name} => 1 } values %{$sources->[0]{packages}};
    for my $job (@$jobs) {
        my ($index, $package) = _resolved_job($job, $sources);
        my $name = $package->{name};
        _fail('Native resolver selected conflicting package providers') if exists($names{$name});
        _fail('Native resolver selected a non-base provider for a base package') if $index != 0
          && ($base_names{$name} || $name =~ /\AFreeBSD-/x || $package->{origin} =~ m{\Abase/}x);
        my $selection = { repository => $index, identity => [@{$package}{@IDENTITY}] };
        push @selected, $selection;
        $names{$name} = $selection;
    }
    for my $name (sort keys %$roots) {
        my $selection = $names{$name};
        _fail("Required base root is absent or changed: $name") unless $selection
          && $selection->{repository} == 0
          && join("\0", @{$selection->{identity}}) eq join("\0", @{$roots->{$name}}{@IDENTITY});
    }
    my @explicit;
    my $application_index = 0;
    for my $name (@$applications) {
        ++$application_index;
        _missing_selection("Requested application is absent from native selection at selection $application_index",
            $diagnostics, 'application-not-selected', $application_index, $name) unless $names{$name};
        _fail("Requested application resolved to a base package at selection $application_index") if $names{$name}{repository} == 0;
        push @explicit, $names{$name};
    }
    return (\@selected, \@explicit);
}

sub resolve {
    my @arguments = @_;
    _fail('Resolution options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fields(\%options, qw(installroot repositories components applications tool solver diagnostics scope));
    _diagnostic_destination($options{diagnostics}) if exists($options{diagnostics});
    _array($options{components}, 8192, 'component');
    _array($options{applications}, 8192, 'application');
    my $scope = exists($options{scope}) ? _scope($options{scope}) : _scope();
    @options{qw(components applications)} = _scope_selections($scope, @options{qw(components applications)});
    my ($repositories, $sources) = _imports($options{repositories}, $options{installroot});
    _check_repositories($repositories);
    my $roots = $scope eq 'applications' ? {}
      : _base_roots($options{components}, $sources->[0], $options{diagnostics});
    _fail('Expanded package roots exceed the 8192 limit')
      if keys(%$roots) + @{$options{applications}} > 8192;
    my (%applications, %base_names, %available_applications);
    $base_names{$_->{name}} = 1 for values %{$sources->[0]{packages}};
    for my $index (1 .. $#$sources) {
        $available_applications{$_->{name}} = 1 for values %{$sources->[$index]{packages}};
    }
    my $application_index = 0;
    for my $name (@{$options{applications}}) {
        ++$application_index;
        _fail('Invalid or duplicate application name') if !_text($name, 1024) || $applications{$name}++;
        _fail("Application selection names a base package at selection $application_index")
          if $base_names{$name} || $name =~ /\AFreeBSD-/x;
        _missing_selection("Requested application is unavailable at selection $application_index",
            $options{diagnostics}, 'missing-application', $application_index, $name) unless $available_applications{$name};
    }
    my $result;
    my $resolved = eval {
        $result = xCAT::FreeBSDRepo::solve_catalogues(
            _solver_references($options{repositories}, $repositories),
            [sort(keys %$roots), @{$options{applications}}], tool => $options{tool}, solver => $options{solver});
        1;
    };
    unless ($resolved) {
        my $error = $@;
        if (defined($options{diagnostics})) {
            my $bytes = eval { _catalogue_diagnostics($repositories, $sources, \%base_names, \%available_applications) };
            ${$options{diagnostics}} = defined($bytes) ? $bytes
              : _diagnostic_json(_diagnostic_report('imported-catalogue-name-references', 'unavailable'));
        }
        # Preserve the solver exception without adding caller details.
        die $error; ## no critic (ErrorHandling::RequireCarping)
    }
    my ($selected, $applications) = _resolved_jobs($result->{jobs}, $sources, $roots,
        $options{applications}, $options{diagnostics});
    return compose(installroot => $options{installroot}, repositories => $options{repositories},
        components => $options{components}, applications => $applications,
        selected => $selected, resolver => $result->{resolver}, scope => $scope);
}

sub _image_paths {
    my ($image, $field, $required, $maximum) = @_;
    my $value = $image->{$field};
    my @paths = defined($value) && length($value) ? split(/,/x, $value, -1) : ();
    _fail("$field requires a path") if $required && !@paths;
    _fail("$field exceeds the $maximum path limit") if @paths > $maximum;
    return \@paths;
}

sub _image_repositories {
    my $image = shift;
    my $base = _image_paths($image, 'pkgdir', 1, 1);
    my $others = _image_paths($image, 'otherpkgdir', 0, 31);
    my @references;
    for my $path (@$base, @$others) {
        my ($publication, $role) = $path =~ m{\A(.+)/(base|applications|repository)\z}x;
        _fail('Image repository path must name an imported repository role') unless defined($role);
        _fail('Image repository roles require base pkgdir and supplemental otherpkgdir')
          if @references ? $role eq 'base' : $role ne 'base';
        push @references, { publication => $publication, role => $role };
    }
    return \@references;
}

sub _image_selections {
    my ($image, $observations) = @_;
    my (%files, %roots, @selections);
    my ($bytes_read, $root_count) = (0, 0);
    for my $field (qw(pkglist otherpkglist)) {
        my $paths = _image_paths($image, $field, $field eq 'pkglist', 64);
        my @selected;
        for my $path (@$paths) {
            _fail('Duplicate package list source path') if $files{$path}++;
            my $bytes = xCAT::FreeBSDRepoImport::read_protected_file($path, "FreeBSD $field");
            $bytes_read += length($bytes);
            _fail('Combined package list bytes exceed the 8 MiB limit') if $bytes_read > $MAX_BYTES;
            push @$observations, { field => $field, path => $path, bytes => $bytes,
                size => length($bytes), sha256 => sha256_hex($bytes) } if defined($observations);
            my $text = eval { decode('UTF-8', $bytes, FB_CROAK | LEAVE_SRC) };
            _fail('Invalid package list UTF-8') unless defined($text);
            _fail('Package lists require LF line endings and a final LF')
              if $text =~ /\r/x || (length($text) && $text !~ /\n\z/x);
            my $line_number = 0;
            for my $line (split(/\n/x, $text)) {
                ++$line_number;
                my $position = "$field file $path line $line_number";
                my ($directive) = $line =~ /\A[ \t]*\#([A-Z0-9_]+)/ix;
                if (defined($directive)) {
                    $directive = uc($directive);
                    _fail("Unsupported package list directive in $position") if $directive eq 'INCLUDE'
                      || index($directive, 'INCLUDE_') == 0 || $directive eq 'ENV' || $directive eq 'NEW_INSTALL_LIST';
                }
                next if $line =~ /\A[ \t]*(?:\#.*)?\z/x;
                _fail("Invalid package list root in $position") unless _text($line, 1024);
                _fail("Duplicate package list root in $position") if $roots{$line}++;
                _fail('Combined package list roots exceed the 8192 limit') if ++$root_count > 8192;
                push @selected, $line;
            }
        }
        push @selections, \@selected;
    }
    return @selections;
}

sub _image_definition {
    my $image = shift;
    _fail('Package planning requires an image definition') unless ref($image) eq 'HASH';
    require xCAT::Utils;
    my $error = xCAT::Utils->freebsd_image_error($image, 'xnba');
    _fail(defined($error) && length($error) ? $error : 'Package planning requires a FreeBSD image')
      if !defined($error) || length($error);
    _fail('Package planning requires osname=FreeBSD')
      if !defined($image->{osname}) || ref($image->{osname}) || $image->{osname} ne 'FreeBSD';
    _fail('Package planning requires imageversion=2')
      if !defined($image->{imageversion}) || ref($image->{imageversion}) || $image->{imageversion} ne '2';
    $error = xCAT::Utils->freebsd_image_definition_error($image);
    _fail($error) if defined($error) && length($error);
    return;
}

sub resolve_image {
    my @arguments = @_;
    _fail('Image resolution options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fields(\%options, qw(installroot image tool solver diagnostics scope));
    _diagnostic_destination($options{diagnostics}) if exists($options{diagnostics});
    my $image = $options{image};
    _image_definition($image);
    my $references = _image_repositories($image);
    my ($components, $applications) = _image_selections($image);
    return resolve(installroot => $options{installroot}, repositories => $references,
        components => $components, applications => $applications,
        tool => $options{tool}, solver => $options{solver},
        exists($options{scope}) ? (scope => $options{scope}) : (),
        exists($options{diagnostics}) ? (diagnostics => $options{diagnostics}) : ());
}

sub _bind {
    my ($bytes, $installroot) = @_;
    my $plan = parse($bytes);
    my %selections = map { $_->{id} => { repository => 0 + substr($_->{repository}, 1),
        identity => [@{$_}{@IDENTITY}] } } @{$plan->{packages}};
    my $expected = compose(installroot => $installroot, resolver => $plan->{resolver},
        exists($plan->{scope}) ? (scope => $plan->{scope}) : (),
        components => $plan->{components}, selected => [map { $selections{$_->{id}} } @{$plan->{packages}}],
        applications => [map { $selections{$_} } @{$plan->{applications}}],
        repositories => [map { { role => $_->{role},
            publication => "$installroot/freebsd15.1/x86_64/repositories/$_->{publication}" } } @{$plan->{repositories}}]);
    _fail('Package plan differs from verified repository sources') unless $expected eq $bytes;
    return $plan;
}

sub _file_state {
    my $file = shift;
    my @state = stat($file);
    _fail('Unsafe published plan file') if !@state || !S_ISREG($state[2]) || $state[3] != 1
      || $state[4] != $> || ($state[2] & oct('7777')) != oct('0444')
      || $state[7] <= 0 || $state[7] > $MAX_BYTES || $state[9] <= 0;
    return @state;
}

sub _read {
    my $path = shift;
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or _fail("Cannot open plan: $!");
    my @before = _file_state($file);
    binmode($file) or _fail("Cannot read plan bytes: $!");
    my $bytes = '';
    while (1) {
        my $length = $before[7] - length($bytes) + 1;
        $length = 65536 if $length > 65536;
        my $read = read($file, my $buffer, $length);
        _fail("Cannot read plan: $!") unless defined($read);
        last unless $read;
        $bytes .= $buffer;
        _fail('Plan grew while being read') if length($bytes) > $before[7];
    }
    my @after = stat($file);
    close($file) or _fail("Cannot close plan: $!");
    my @named = lstat($path);
    _fail('Published plan changed while being read') unless @after && @named
      && length($bytes) == $before[7] && join(':', @before[0, 1, 2, 3, 4, 7, 9, 10])
      eq join(':', @after[0, 1, 2, 3, 4, 7, 9, 10])
      && join(':', @after[0, 1, 2, 3, 4, 7, 9, 10]) eq join(':', @named[0, 1, 2, 3, 4, 7, 9, 10]);
    return $bytes;
}

sub inspect {
    my ($path, $installroot) = @_;
    _fail('Plan inspection requires a path and install root') unless @_ == 2 && _text($path, 16384);
    my $parent = xCAT::FreeBSDRepoImport::publication_directory($installroot, 'plans', 0);
    my ($digest) = $path =~ /\A\Q$parent\E\/([0-9a-f]{64})[.]plan\z/x;
    _fail('Invalid published plan path') unless defined($digest);
    my $bytes = _read($path);
    _fail('Plan path and checksum differ') unless sha256_hex($bytes) eq $digest;
    my $plan = _bind($bytes, $installroot);
    return { digest => $digest, relative => "freebsd15.1/x86_64/plans/$digest.plan", path => $path, plan => $plan };
}

sub _archive_destination {
    my ($destination) = @_;
    _fail('Invalid archive staging destination') unless _text($destination, 16384)
      && $destination =~ m{\A/}x;
    _fail('Invalid archive staging destination') if grep { !length($_) || $_ eq '.' || $_ eq '..' }
      split(m{/}x, substr($destination, 1), -1);
    my $path = '';
    for my $part (split(m{/}x, substr($destination, 1))) {
        $path .= "/$part";
        my @state = lstat($path);
        _fail('Unsafe archive staging ancestor') if !@state || !S_ISDIR($state[2])
          || ($state[4] != 0 && $state[4] != $>)
          || (($state[2] & oct('0022')) && ($path eq $destination || !($state[2] & oct('1000'))));
        _fail('Archive staging directory must be private') if $path eq $destination
          && ($state[4] != $> || ($state[2] & oct('7777')) != oct('0700'));
    }
    return;
}

sub stage_archives {
    my ($bytes, $installroot, $destination) = @_;
    _fail('Archive staging requires plan bytes, install root and destination') unless @_ == 3;
    _archive_destination($destination);
    opendir(my $directory, $destination) or _fail('Cannot inspect archive staging directory');
    my @members = grep { $_ ne '.' && $_ ne '..' } readdir($directory);
    closedir($directory) or _fail('Cannot close archive staging directory');
    _fail('Archive staging directory must be empty') if @members;
    my $plan = _bind($bytes, $installroot);
    my $parent = xCAT::FreeBSDRepoImport::publication_directory($installroot, 'repositories', 0);
    my $total = 0;
    for my $package (@{$plan->{packages}}) {
        $total += $package->{size};
        _fail('Package archive set exceeds its byte limit') if $total > 68719476736;
    }
    for my $package (@{$plan->{packages}}) {
        my $repository = $plan->{repositories}[_repository_index($package->{repository}, $plan->{repositories})];
        my $target = "$destination/$package->{id}.pkg";
        xCAT::FreeBSDRepoImport::copy_verified_file("$parent/$repository->{publication}/$package->{path}",
            $target, $package->{size}, $package->{sha256});
        chmod(oct('0400'), $target) == 1 or _fail('Cannot protect staged package archive');
        sysopen(my $file, $target, O_RDONLY | O_NOFOLLOW) or _fail('Cannot open staged package archive');
        $file->sync or _fail('Cannot sync staged package archive');
        close($file) or _fail('Cannot close staged package archive');
    }
    chmod(oct('0500'), $destination) == 1 or _fail('Cannot protect staged archive directory');
    sysopen(my $handle, $destination, O_RDONLY | O_NOFOLLOW) or _fail('Cannot open staged archive directory');
    $handle->sync or _fail('Cannot sync staged archive directory');
    close($handle) or _fail('Cannot close staged archive directory');
    return { packages => scalar(@{$plan->{packages}}), bytes => $total, plan_sha256 => sha256_hex($bytes) };
}

sub _write_manifest {
    my ($path, $bytes) = @_;
    sysopen(my $file, $path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, oct('0600'))
      or _fail('Cannot create package manifest');
    binmode($file) or _fail('Cannot write package manifest bytes');
    print {$file} $bytes or _fail('Cannot write package manifest');
    $file->flush or _fail('Cannot flush package manifest');
    chmod(oct('0400'), $file) == 1 or _fail('Cannot protect package manifest');
    $file->sync or _fail('Cannot sync package manifest');
    close($file) or _fail('Cannot close package manifest');
    return;
}

sub stage_manifests {
    my ($bytes, $installroot, $destination) = @_;
    _fail('Manifest staging requires plan bytes, install root and destination') unless @_ == 3;
    my $archives = stage_archives($bytes, $installroot, $destination);
    chmod(oct('0700'), $destination) == 1 or _fail('Cannot prepare manifest stage');
    my $request = "format\txcat-freebsd-local-manifests-1\nplan\t$archives->{plan_sha256}\n";
    my $total = 0;
    for my $row (grep { /\Apackage\t/x } split(/\n/x, $bytes)) {
        my (undef, $id) = split(/\t/x, $row);
        my $archive = "$destination/$id.pkg";
        # The native verifier reads the first full manifest, including file hashes.
        my $result = xCAT::FreeBSDPkg::run_command(['/usr/bin/tar', '--occurrence=1', '-xOf', $archive, '+MANIFEST'],
            cwd => $destination, environment => { PATH => '/usr/bin:/bin', LC_ALL => 'C' },
            timeout => 60, stdout_limit => 134217728);
        _fail('Cannot read full package manifest') if $result->{exitcode} || $result->{signal};
        my $manifest = $result->{stdout};
        my $size = length($manifest);
        $total += $size;
        _fail('Package manifest set exceeds its byte limit') if !$size || $total > 536870912;
        _write_manifest("$destination/$id.manifest", $manifest);
        $request .= join("\t", $row, $size, sha256_hex($manifest)) . "\n";
        _fail('Manifest request exceeds its byte limit') if length($request) > $MAX_BYTES;
        unlink($archive) or _fail('Cannot remove staged verification payload');
    }
    chmod(oct('0500'), $destination) == 1 or _fail('Cannot protect staged manifest directory');
    sysopen(my $directory, $destination, O_RDONLY | O_NOFOLLOW) or _fail('Cannot open staged manifest directory');
    $directory->sync or _fail('Cannot sync staged manifest directory');
    close($directory) or _fail('Cannot close staged manifest directory');
    return { packages => $archives->{packages}, bytes => $total, archive_bytes => $archives->{bytes},
        plan_sha256 => $archives->{plan_sha256}, request => $request };
}

sub _image_request {
    my $image = shift;
    _image_definition($image);
    my %definition = map { exists($image->{$_}) ? ($_ => $image->{$_}) : () }
      qw(imagetype osvers osarch provmethod osname imageversion bootdir pkgdir pkglist otherpkgdir otherpkglist);
    my @lists;
    my $references = _image_repositories(\%definition);
    my ($components, $applications) = _image_selections(\%definition, \@lists);
    return { image => \%definition, lists => \@lists, repositories => $references,
        components => $components, applications => $applications };
}

sub inspect_image {
    my ($path, $installroot, $image, @scope) = @_;
    _fail('Image plan inspection requires a path, install root and image') unless @_ == 3 || @_ == 4;
    my $scope = _scope(@scope);
    my $request = _image_request($image);
    my ($components, $applications) = _scope_selections($scope, @{$request}{qw(components applications)});
    my $result = inspect($path, $installroot);
    my $plan = $result->{plan};
    _fail('Image package scope differs from the published plan') unless ($plan->{scope} || 'all') eq $scope;
    my $json = JSON->new->ascii->canonical;
    my $parent = xCAT::FreeBSDRepoImport::publication_directory($installroot, 'repositories', 0);
    my @repositories = map { { role => $_->{role},
        publication => "$parent/$_->{publication}" } } @{$plan->{repositories}};
    _fail('Image repositories differ from the published plan')
      unless $json->encode($request->{repositories}) eq $json->encode(\@repositories);
    _fail('Image components differ from the published plan')
      unless $json->encode($components) eq $json->encode($plan->{components});
    my %packages = map { $_->{id} => $_ } @{$plan->{packages}};
    my @applications = map { $packages{$_}{name} } @{$plan->{applications}};
    _fail('Image application roots differ from the published plan')
      unless $json->encode($applications) eq $json->encode(\@applications);
    # Equal roots do not imply equal package-list bytes.
    my $after = _image_request($image);
    _fail('Image package request changed during plan inspection')
      unless $json->encode($request) eq $json->encode($after);
    $request->{scope} = $scope if @scope;
    return { %$result, bytes => _encode($plan), request => $request };
}

sub publish_image {
    my @arguments = @_;
    _fail('Image publication options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fields(\%options, qw(installroot image tool solver diagnostics scope));
    my $request = _image_request($options{image});
    my $bytes = resolve_image(%options);
    my $json = JSON->new->ascii->canonical;
    _fail('Image package request changed during resolution')
      unless $json->encode($request) eq $json->encode(_image_request($options{image}));
    my $published = publish($bytes, $options{installroot});
    my $result = inspect_image($published->{path}, $options{installroot}, $options{image},
        exists($options{scope}) ? ($options{scope}) : ());
    $request->{scope} = _scope($options{scope}) if exists($options{scope});
    _fail('Image package request changed during publication')
      unless $json->encode($request) eq $json->encode($result->{request});
    return { %$published, %$result };
}

sub _lock {
    my $parent = shift;
    my $path = "$parent/.package-plan.lock";
    sysopen(my $file, $path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
      or _fail("Cannot open publication lock: $!");
    my @state = stat($file);
    _fail('Unsafe plan publication lock') unless @state && S_ISREG($state[2]) && $state[3] == 1
      && $state[4] == $> && ($state[2] & oct('7777')) == oct('0600') && $state[7] == 0;
    flock($file, LOCK_EX) or _fail("Cannot lock plan publication: $!");
    my @named = lstat($path);
    _fail('Plan publication lock changed') unless @named && $named[0] == $state[0]
      && $named[1] == $state[1] && $named[3] == 1;
    return $file;
}

sub _write_stage {
    my ($file, $bytes) = @_;
    binmode($file) or _fail("Cannot write plan bytes: $!");
    print {$file} $bytes or _fail("Cannot write plan: $!");
    $file->flush or _fail("Cannot flush plan: $!");
    chmod(oct('0444'), $file) or _fail("Cannot protect plan: $!");
    $file->sync or _fail("Cannot sync plan: $!");
    close($file) or _fail("Cannot close plan: $!");
    return;
}

sub publish {
    my ($bytes, $installroot) = @_;
    _fail('Plan publication requires bytes and install root') unless @_ == 2;
    _bind($bytes, $installroot);
    my $digest = sha256_hex($bytes);
    my $parent = xCAT::FreeBSDRepoImport::publication_directory($installroot, 'plans', 1);
    my $lock = _lock($parent);
    my @parent = lstat($parent);
    my $path = "$parent/$digest.plan";
    my $relative = "freebsd15.1/x86_64/plans/$digest.plan";
    if (lstat($path)) {
        _fail('Published plan contents differ') unless _read($path) eq $bytes;
        return { digest => $digest, relative => $relative, path => $path, reused => 1 };
    }
    my ($file, $temporary) = tempfile('.plan-stage.XXXXXXXX', DIR => $parent, UNLINK => 0);
    my $ok = eval {
        _write_stage($file, $bytes);
        _fail('Staged plan contents differ') unless _read($temporary) eq $bytes;
        xCAT::FreeBSDRepoImport::publication_directory($installroot, 'plans', 0);
        my @current = lstat($parent);
        _fail('Plan publication directory changed') unless $parent[0] == $current[0] && $parent[1] == $current[1];
        _fail('Plan destination appeared during publication') if lstat($path);
        rename($temporary, $path) or _fail("Cannot publish plan: $!");
        undef($temporary);
        _fail('Published plan contents differ') unless _read($path) eq $bytes;
        1;
    };
    my $error = $@;
    close($file) if defined(fileno($file));
    $error .= "Cannot remove staged plan: $!\n" if defined($temporary) && !unlink($temporary);
    _fail($error) if !$ok || length($error);
    return { digest => $digest, relative => $relative, path => $path, reused => 0 };
}

1;
