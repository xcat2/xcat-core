#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Getopt::Long ();
use JSON;
use Storable qw(dclone);
use Test::More;
use Text::ParseWords qw(shellwords);
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;

BEGIN { ## no critic (Variables::RequireLocalizedPunctuationVars)
    $INC{"xCAT/$_.pm"} = 1 for qw(Table TableUtils);
}

my ($installroot, $policy_path, $install_before, @site_reads, @db_access);
my ($plan_image, %db_rows, %db_faults, @db_opened, @db_closed);

sub table_open {
    my ($class, $table, %options) = @_;
    push @db_access, ['new', $table, { %options }];
    croak 'Unexpected image/database access' unless defined($plan_image);
    croak 'Only image tables may be read' unless $table eq 'osimage' || $table eq 'freebsdimage';
    croak 'Only existing image tables may be read' if !exists($options{-create}) || $options{-create};
    return if ($db_faults{"new:$table"} || '') eq 'absent';
    die $db_faults{"new:$table"} if $db_faults{"new:$table"};
    push @db_opened, $table;
    return bless { table => $table }, $class;
}

sub table_lookup {
    my ($table, $key, $attributes) = @_;
    croak 'Image lookup must use the exact imagename key' unless ref($key) eq 'HASH'
      && keys(%$key) == 1 && ($key->{imagename} || '') eq $plan_image;
    my @allowed = $table eq 'osimage'
      ? qw(imagename osname osvers osarch imagetype provmethod disable)
      : qw(imagename bootdir pkgdir pkglist otherpkgdir otherpkglist imageversion disable);
    my %allowed = map { $_ => 1 } @allowed;
    croak 'Planning must request image attributes' unless ref($attributes) eq 'ARRAY' && @$attributes;
    croak 'Planning queried unrelated image attributes' if grep { !$allowed{$_} } @$attributes;
    return;
}

sub table_row {
    my ($row, $attributes) = @_;
    my %selected;
    for my $attribute (@$attributes) {
        $selected{$attribute} = $row->{$attribute} if exists($row->{$attribute});
    }
    return dclone(\%selected);
}

sub table_row_enabled {
    my $row = shift;
    return 1 unless defined($row->{disable});
    return $row->{disable} =~ /\A(?:0|no)\z/ix;
}

sub table_get_attribs {
    my ($self, $key, $attributes) = @_;
    my $list_context = wantarray;
    my $table = $self->{table};
    push @db_access, ['get', $table, dclone($key), dclone($attributes)];
    croak 'Image lookup must preserve duplicate rows through list context' unless $list_context;
    table_lookup($table, $key, $attributes);
    die $db_faults{"get:$table"} if $db_faults{"get:$table"};
    my @rows = grep { table_row_enabled($_) } @{$db_rows{$table} || []};
    my @selected = map { table_row($_, $attributes) } @rows;
    push @selected, undef unless @selected;
    return @selected;
}

sub table_close {
    my $self = shift;
    croak 'Table handle closed twice' if $self->{closed}++;
    push @db_closed, $self->{table};
    die $db_faults{"close:$self->{table}"} if $db_faults{"close:$self->{table}"};
    return;
}

sub site_attribute {
    my ($class, $key) = @_;
    push @site_reads, $key;
    croak "Unexpected site attribute $key" unless $key eq 'freebsdimportpolicy';
    return $policy_path;
}

{ ## no critic (Variables::ProhibitPackageVars)
    no warnings 'once'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    *xCAT::Table::new = \&table_open;
    *xCAT::Table::getAttribs = \&table_get_attribs;
    *xCAT::Table::close = \&table_close;
    *xCAT::Table::setAttribs = sub { croak 'Unexpected image table write'; };
    *xCAT::Table::delEntries = sub { croak 'Unexpected image table deletion'; };
    *xCAT::TableUtils::getInstallDir = sub { push @site_reads, 'installdir'; return $installroot; };
    *xCAT::TableUtils::get_site_attribute = \&site_attribute;
}

my $plugin = $ENV{XCAT_FREEBSD_REPO_PLUGIN}
  || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsdrepo.pm";
require $plugin;
my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => '/unavailable/pkg', sha256 => '0' x 64 };
my $solver;
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);
my $signed = $fixture->new_directory();
write_file("$signed/content", 'ordinary inspection input');
my $source_tree = xCAT::FreeBSDRepo::snapshot_tree($signed);
my ($unsigned, $nested);
my $default_policy = { format => 'xcat-freebsd-import-policy-1', tool => $tool,
    releases => {}, repositories => {} };

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    return defined($bytes) ? $bytes : '';
}

sub write_file {
    my ($path, $bytes) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub command {
    my @argv = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@argv, cwd => $tmp,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub run_pkg {
    my @arguments = @_;
    return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments);
}

sub pubkey {
    my $name = shift;
    return { type => 'pubkey', path => "$tmp/$name.pub",
        sha256 => sha256_hex(read_file("$tmp/$name.pub")) };
}

sub native_fixtures {
    $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
    $solver = defined($ENV{XCAT_FREEBSD_NATIVE_SOLVER})
      ? { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_SOLVER}) } : undef;
    if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
        $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
        $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
        $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
    }
    make_path("$tmp/empty", "$tmp/repos");
    write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
        PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
        REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
    $tool->{sha256} = sha256_hex(read_file($tool->{path}));
    $solver->{sha256} = sha256_hex(read_file($solver->{path})) if $solver;
    is(run_pkg('-v'), "2.8.2\n", 'fixtures use the pinned native pkg version');
    for my $key_name (qw(repo wrong)) {
        command('/usr/bin/openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', "$tmp/$key_name.key");
        chmod(oct('0600'), "$tmp/$key_name.key") or croak $!;
        command('/usr/bin/openssl', 'pkey', '-in', "$tmp/$key_name.key", '-pubout', '-out', "$tmp/$key_name.pub");
    }
    my @definitions = (['command-dep'], ['command-app', deps => {
        'command-dep' => { origin => 'misc/command-dep', version => '1' } }], ['command-unused']);
    $signed = $fixture->repository(1, \@definitions);
    $unsigned = $fixture->repository(0, \@definitions);
    $nested = $fixture->new_directory();
    command('/usr/bin/cp', '-a', $signed, "$nested/catalogue");
    $source_tree = xCAT::FreeBSDRepo::snapshot_tree($signed);
    $default_policy = { format => 'xcat-freebsd-import-policy-1', tool => $tool, releases => {},
        repositories => { approved => { trust => pubkey('repo') },
            unsigned => { trust => { type => 'operator-trusted-tree',
                digest => xCAT::FreeBSDRepo::snapshot_tree($unsigned)->{digest} } },
            nested => { trust => pubkey('repo'), catalogue_prefix => 'catalogue' },
            wrong => { trust => pubkey('wrong') } } };
    return;
}

sub fresh {
    my $change = shift;
    @site_reads = ();
    @db_access = ();
    @db_opened = ();
    @db_closed = ();
    %db_rows = ();
    %db_faults = ();
    undef($plan_image);
    $installroot = $fixture->new_directory();
    $install_before = xCAT::FreeBSDRepo::snapshot_tree($installroot);
    $policy_path = $fixture->new_directory() . '/policy.json';
    my $policy = dclone($default_policy);
    $change->($policy) if $change;
    write_file($policy_path, $json->encode($policy));
    chmod(oct('0600'), $policy_path) or croak $!;
    return;
}

sub request {
    my $request = shift;
    my @responses;
    xCAT_plugin::freebsdrepo::process_request($request,
        sub { push @responses, dclone($_[0]); }, sub { croak 'Unexpected subrequest'; });
    return \@responses;
}

sub run_cli {
    my @arguments = @_;
    return request({ command => ['freebsdrepo'], arg => \@arguments });
}

sub messages {
    my ($responses, $field) = @_;
    return join('', map { @{$_->{$field} || []} } @$responses);
}

sub literal_error_pattern {
    my $message = shift;
    return qr/\Q$message\E\b/x;
}

sub rejected {
    my ($responses, $pattern, $description, $expected_external) = @_;
    my $error = messages($responses, 'error');
    like($error, $pattern, $description);
    if (defined($expected_external)) {
        is($error, $expected_external, "$description preserves the original exception exactly");
    } else {
        unlike($error, qr/[ ]at[ ][^\n]+[ ]line[ ]\d+[.]$/mx, "$description omits Perl caller details");
    }
    is_deeply([map { @{$_->{errorcode} || []} } @$responses], [1], "$description returns error status");
    is(messages($responses, 'data'), '', "$description reports no success");
    return;
}

sub publications {
    my $parent = "$installroot/freebsd15.1/x86_64/repositories";
    return [] unless -d $parent;
    opendir(my $dh, $parent) or croak $!;
    my @names = sort grep { /\A[0-9a-f]{64}\z/x } readdir($dh);
    closedir($dh) or croak $!;
    return [map { "$parent/$_" } @names];
}

sub no_effect {
    my $description = shift;
    is_deeply(publications(), [], "$description makes no publication");
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($installroot), $install_before,
        "$description leaves the complete install tree unchanged");
    is_deeply(\@db_access, [], "$description leaves image/package selections untouched");
    return;
}

sub help_cases {
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n"
      . "       freebsdrepo plan osimage [--diagnostics]\n";
    for my $action (qw(inspect import plan)) {
        my $target = $action eq 'plan' ? 'image' : $signed;
        for my $flag (qw(-h --help)) {
            for my $args ([$action, $flag], [$action, $flag, $target], [$action, $target, $flag]) {
                my $description = 'subcommand help [' . join(' ', @$args) . ']';
                is_deeply(run_cli(@$args), [{ data => [$usage] }], "$description returns only successful usage");
                is_deeply(\@db_access, [], "$description does not open image tables");
                is_deeply(\@site_reads, [], "$description does not read site configuration");
            }
        }
    }
    return;
}

sub parser_cases {
    fresh();
    my $getopt_config = Getopt::Long::Configure();
    parser_requests();
    is_deeply(Getopt::Long::Configure(), $getopt_config, 'parser fixture restores global Getopt configuration');
    no_effect('parser rejection');
    return;
}

sub parser_requests {
    my ($native_calls, $tree_reads) = (0, 0);
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Unexpected native execution'; };
    local *xCAT::FreeBSDRepo::snapshot_tree = sub { ++$tree_reads; croak 'Unexpected tree inspection'; };
    my $getopt_config = Getopt::Long::Configure(qw(auto_abbrev ignore_case require_order));
    is_deeply(xCAT_plugin::freebsdrepo::handled_commands(), { freebsdrepo => 'freebsdrepo' }, 'command dispatch is dedicated');
    is_deeply(request({ command => ['copycd'], arg => ['--help'] }), [], 'unrelated command is not claimed');
    for my $flag (qw(-h --help)) {
        my $responses = run_cli($flag);
        like(messages($responses, 'data'), qr/Usage:[ ]freebsdrepo[ ]inspect/x, "$flag prints global usage");
        is(messages($responses, 'error'), '', "$flag succeeds");
    }
    help_cases();
    my @bad = ([], ['Inspect', $signed], ['IMPORT', $signed], ['inspect'], ['import'],
        ['plan'], ['Plan', 'image'], ['plan', 'image', 'extra'],
        ['plan', 'image', '--policy', 'approved'], ['plan', 'image', '-w'],
        ['inspect', $signed, 'extra'], ['import', $signed, 'extra', '--policy', 'approved'],
        ['inspect', $signed, '--policy', 'approved'], ['inspect', $signed, '-w'],
        ['plan', '--help', 'image', 'extra'], ['inspect', '--help', $signed, 'extra'],
        ['import', '--help', $signed, 'extra'], ['plan', '--help', '--unknown'],
        ['import', $signed], ['import', $signed, '--policy'], ['import', $signed, '--policy='],
        ['import', $signed, '--policy', 'approved', '--policy', 'wrong'],
        ['import', $signed, '--policy', 'approved', '--policy', 'approved'],
        ['import', $signed, '--pol', 'approved'], ['import', $signed, '--Policy', 'approved'],
        ['import', $signed, '--policy', 'approved', '-W'], ['import', $signed, '--unknown'],
        ['--help', 'extra'], ['--HELP'], ['-h', 'inspect', $signed]);
    push @bad, map { ['plan', $_] } ('', '../image', '/image', '-image', '.image',
        'image,name', 'image name', "image\nname", 'a' x 248, []);
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n"
      . "       freebsdrepo plan osimage [--diagnostics]\n";
    my $parse_error = qr/Invalid[ ]freebsdrepo[ ]arguments:[^\0]*\n\Q$usage\E/x;
    my $inspect_error = "Repository inspection does not accept --policy or -w\n";
    my $import_error = "Repository import requires exactly one --policy profile\n";
    my $plan_error = "Package planning does not accept --policy or -w\n";
    my $name_error = "Invalid image name\n";
    my $action_error = qr/(?:\Q$inspect_error\E|\Q$import_error\E|\Q$plan_error\E|\Q$name_error\E)/x;
    my $argument_error = qr/\A(?:\Q$usage\E|$parse_error|$action_error)\z/x;
    for my $args (@bad) {
        rejected(run_cli(@$args), $argument_error,
            'invalid arguments [' . join(' ', @$args) . ']');
    }
    is($native_calls, 0, 'parser does not execute native commands');
    is($tree_reads, 0, 'parser does not inspect source paths');
    is_deeply(\@site_reads, [], 'parser and help do not read configuration');
    Getopt::Long::Configure($getopt_config);
    return;
}

sub inspect_cases {
    fresh();
    unlink($policy_path) or croak $!;
    my $before = xCAT::FreeBSDRepo::snapshot_tree($installroot);
    my $native_calls = 0;
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Unexpected native execution'; };
    my $responses = run_cli('inspect', $signed);
    is(messages($responses, 'error'), '', 'inspection succeeds without policy');
    is(messages($responses, 'data'), "TREE_DIGEST:$source_tree->{digest}\nBYTES:$source_tree->{bytes}\n",
        'inspection reports the complete original tree digest and bytes');
    for my $path ('relative/tree', "$tmp/missing") {
        rejected(run_cli('inspect', $path), qr/./sx, "invalid inspection path $path");
    }
    is($native_calls, 0, 'inspection does not execute pkg or another command');
    is_deeply(\@site_reads, [], 'inspection does not read policy or installroot');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'inspection leaves source unchanged');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($installroot), $before, 'inspection makes no output changes');
    no_effect('inspection');
    return;
}

sub policy_path_cases {
    my $native_calls = 0;
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Unexpected native execution'; };
    for my $case ([undef, 'unset'], ['', 'empty'], ['0', 'zero'], [' ', 'whitespace'],
        ['relative/policy', 'relative'], [{}, 'structured']) {
        fresh();
        ($policy_path, my $name) = @$case;
        my $pattern = $name eq 'unset' || $name eq 'empty'
          ? qr/\Asite[.]freebsdimportpolicy[ ]is[ ]not[ ]set\n\z/x
          : qr/\AInvalid[ ]FreeBSD[ ]import[ ]policy[ ]path\n\z/x;
        rejected(run_cli('import', $signed, '--policy', 'approved'), $pattern, "$name site policy");
        is_deeply(\@site_reads, ['freebsdimportpolicy'], "$name policy does not read installroot");
        no_effect("$name site policy");
    }
    is($native_calls, 0, 'invalid site policy never invokes native preparation');
    return;
}

sub import_cases {
    fresh();
    my $responses = run_cli('import', $signed, '--policy', 'approved', '-w');
    is(messages($responses, 'error'), '', 'approved signed repository imports');
    my $paths = publications();
    is(scalar(@$paths), 1, 'one immutable publication is created');
    return unless @$paths == 1;
    my $path = $paths->[0];
    is_deeply($responses,
        [{ data => ["Imported FreeBSD repository to $path", "Repository: $path/repository"] }],
        'output identifies publication and repository root');
    is_deeply(\@site_reads, [qw(freebsdimportpolicy installdir)], 'import uses configured policy and installroot');
    my $manifest = xCAT::FreeBSDRepoImport::inspect_import($path, $installroot);
    is($manifest->{kind}, 'repository', 'readback proves repository publication');
    is($manifest->{native_validated}, 1, 'publication manifest records native validation');
    is($manifest->{selection_validated}, 0, 'publication does not claim package selection');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$path/repository"), $source_tree, 'complete published tree matches source');
    my $before = xCAT::FreeBSDRepo::snapshot_tree($path);
    is_deeply(run_cli('import', '--policy=approved', $signed),
        [{ data => ["Verified existing FreeBSD repository at $path", "Repository: $path/repository"] }],
        'repeat import with permuted option reports verified reuse');
    is_deeply(publications(), [$path], 'repeat keeps the same publication identity');
    rejected(run_cli('import', $signed, '--policy', 'approved', '-w'), qr/already[ ]exists/x, '-w forbids reuse');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($path), $before, 'retry and -w leave publication unchanged');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'import leaves input bytes and links unchanged');
    is_deeply(\@db_access, [], 'import/retry never opens image or package-selection tables');
    return;
}

sub profile_cases {
    for my $case ([$unsigned, 'unsigned'], [$nested, 'nested']) {
        fresh();
        my ($source, $profile) = @$case;
        is(messages(run_cli('import', $source, '--policy', $profile), 'error'), '', "$profile profile imports");
        my $paths = publications();
        is(scalar(@$paths), 1, "$profile creates one publication");
        next unless @$paths == 1;
        my $manifest = xCAT::FreeBSDRepoImport::inspect_import($paths->[0], $installroot);
        is($manifest->{native_validated}, 1, "$profile manifest records native validation");
        is_deeply(\@db_access, [], "$profile does not attach to an image");
    }
    return;
}

sub policy_cases {
    my @cases = (
        ['missing profile', sub { return; }, $signed, 'absent', qr/(?:approved|profile)/x],
        ['wrong selected key', sub { return; }, $signed, 'wrong', qr/(?:native|signature|catalogue)/ix],
        ['unsigned under signed policy', sub { return; }, $unsigned, 'approved', qr/(?:native|signature|catalogue)/ix],
        ['wrong tool pin', sub { $_[0]{tool}{sha256} = '0' x 64; }, $signed, 'approved', qr/(?:tool|executable|SHA256|digest)/ix],
        ['wrong tree approval', sub { $_[0]{repositories}{unsigned}{trust}{digest} = '0' x 64; },
            $unsigned, 'unsigned', qr/(?:trust|digest|approval)/ix]);
    for my $case (@cases) {
        my ($name, $change, $source, $profile, $pattern) = @$case;
        fresh($change);
        rejected(run_cli('import', $source, '--policy', $profile), $pattern, $name);
        no_effect($name);
    }
    fresh();
    unlink($policy_path) or croak $!;
    rejected(run_cli('import', $signed, '--policy', 'approved'), qr/(?:policy|path)/ix, 'missing configured policy');
    no_effect('missing policy');
    fresh();
    chmod(oct('0666'), $policy_path) or croak $!;
    rejected(run_cli('import', $signed, '--policy', 'approved'), qr/(?:policy|writable|permission)/ix, 'unsafe policy permissions');
    no_effect('unsafe policy');
    return;
}

sub source_failure_cases {
    for my $kind (qw(missing corrupt)) {
        my $source = $fixture->new_directory();
        command('/usr/bin/cp', '-a', "$signed/.", $source);
        my $archive = "$source/All/command-app-1.pkg";
        if ($kind eq 'missing') {
            unlink($archive) or croak $!;
        } else {
            write_file($archive, read_file($archive) . 'corrupt');
        }
        fresh();
        rejected(run_cli('import', $source, '--policy', 'approved'),
            qr/(?:archive|package|checksum|digest)/ix, "$kind signed package archive");
        no_effect("$kind archive");
    }
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'negative fixtures leave shared signed input intact');
    return;
}

my ($planning_root, $plan_release, $plan_repository, $plan_broken, $plan_sources_before);
my $private_root = 'command-private-sentinel-75c6a83e';

sub fresh_plan {
    unless (defined($planning_root)) {
        fresh();
        $planning_root = $installroot;
        my $source = $fixture->release_tree(1);
        my @base = map { [$_, version => '15.1', origin => "base/$_",
            annotations => { FreeBSD_version => '1501000' },
            ($_ eq 'FreeBSD-set-minimal' ? (deps => {
                'FreeBSD-runtime' => { origin => 'base/FreeBSD-runtime', version => '15.1' } }) : ())] }
          qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base FreeBSD-ssh FreeBSD-bsdconfig);
        push @base, ['pkg', version => '2.6.2_1', origin => 'ports-mgmt/pkg'];
        my $base = $fixture->repository(0, \@base);
        command('/usr/bin/cp', '-a', "$base/.", "$source/usr/freebsd-packages/offline");
        $plan_release = xCAT::FreeBSDRepoImport::import_release($source, $planning_root,
            tool => $tool, trust => { type => 'operator-trusted-release',
                digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} });
        $plan_repository = xCAT::FreeBSDRepoImport::import_repository($signed, $planning_root,
            tool => $tool, trust => pubkey('repo'));
        my $broken = $fixture->repository(1, [
            ['command-broken', deps => {
                'command-unavailable' => { origin => 'misc/command-unavailable', version => '1' } }],
            [$private_root, deps => {
                'command-unavailable' => { origin => 'misc/command-unavailable', version => '1' } }],
        ]);
        $plan_broken = xCAT::FreeBSDRepoImport::import_repository($broken, $planning_root,
            tool => $tool, trust => pubkey('repo'));
        $plan_sources_before = [map { xCAT::FreeBSDRepo::snapshot_tree($_->{path}) }
            ($plan_release, $plan_repository, $plan_broken)];
    }
    fresh(sub { $_[0]{solver} = dclone($solver); });
    $installroot = $planning_root;
    $plan_image = 'freebsd15.1-x86_64-install-command';
    my $lists = $fixture->new_directory();
    write_file("$lists/base.pkglist", "# Base components\n\nbase\n");
    write_file("$lists/apps.pkglist", "# Application roots\ncommand-app\napplication\n");
    %db_rows = (
        osimage => [{ imagename => $plan_image, osname => 'FreeBSD', osvers => 'freebsd15.1',
            osarch => 'x86_64', imagetype => 'freebsd', provmethod => 'install' }],
        freebsdimage => [{ imagename => $plan_image, imageversion => '2',
            pkgdir => "$plan_release->{path}/base", pkglist => "$lists/base.pkglist",
            otherpkgdir => "$plan_release->{path}/applications,$plan_repository->{path}/repository",
            otherpkglist => "$lists/apps.pkglist" }],
    );
    return $lists;
}

sub plan_files {
    my $parent = "$installroot/freebsd15.1/x86_64/plans";
    return [] unless -d $parent;
    opendir(my $dh, $parent) or croak $!;
    my @names = sort grep { $_ ne '.' && $_ ne '..' && $_ ne '.package-plan.lock' } readdir($dh);
    closedir($dh) or croak $!;
    return [map { [$_, sha256_hex(read_file("$parent/$_"))] } @names];
}

sub tables_closed {
    my $description = shift;
    is_deeply([sort @db_closed], [sort @db_opened], "$description closes every opened table");
    return;
}

sub plan_rejected {
    my ($pattern, $description, $native_resolution, $expected_external, $options) = @_;
    $options ||= {};
    my $before = plan_files();
    my $rows = dclone(\%db_rows);
    my ($responses, @commands);
    {
        my $run = \&xCAT::FreeBSDPkg::run_command;
        no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
        local *xCAT::FreeBSDPkg::run_command = sub {
            push @commands, dclone($_[0]);
            return $run->(@_);
        };
        $responses = defined($options->{transported}) ? request($options->{transported}) : run_cli('plan', $plan_image);
    }
    my $ordinary = dclone($responses);
    delete($_->{data}) for $options->{detailed} ? @$ordinary : ();
    rejected($ordinary, $pattern, $description, $expected_external);
    if ($native_resolution) {
        ok(scalar(grep { @$_ > 3 && $_->[3] eq 'resolve' } @commands),
            "$description reaches the real native resolver");
    } else {
        is_deeply(\@commands, [], "$description is rejected before native execution");
    }
    is_deeply(plan_files(), $before, "$description leaves published plans unchanged and no staged file");
    is_deeply(\%db_rows, $rows, "$description leaves stored image rows unchanged");
    tables_closed($description);
    return $responses;
}

sub planned {
    my ($description, $transported) = @_;
    my $rows = dclone(\%db_rows);
    my $responses = defined($transported) ? request($transported) : run_cli('plan', $plan_image);
    is(messages($responses, 'error'), '', "$description succeeds");
    my @output = map { @{$_->{data} || []} } @$responses;
    my ($path) = map { /\APackage[ ]plan:[ ](.+)\z/x ? $1 : () } @output;
    my ($digest) = map { /\ASHA256:([0-9a-f]{64})\z/x ? $1 : () } @output;
    ok(defined($path) && defined($digest), "$description reports plan path and SHA256");
    tables_closed($description);
    is_deeply(\%db_rows, $rows, "$description does not change image selections");
    return unless defined($path) && defined($digest);
    is_deeply($responses, [{ data => ["Package plan: $path", "SHA256:$digest"] }],
        "$description has the documented output");
    is(sha256_hex(read_file($path)), $digest, "$description digest matches the published bytes");
    my $inspection = xCAT::FreeBSDPackagePlan::inspect($path, $installroot);
    is($inspection->{digest}, $digest, "$description passes source-bound plan inspection");
    is((stat($path))[2] & oct('7777'), oct('0444'), "$description publishes a read-only plan");
    return $inspection;
}

sub plan_applications {
    my $plan = shift;
    my %names = map { $_->{id} => $_->{name} } @{$plan->{packages}};
    return [map { $names{$_} } @{$plan->{applications}}];
}

sub plan_success_cases {
    fresh_plan();
    my $first = planned('configured image without boot, template or storage attributes');
    return unless $first;
    my $plan = $first->{plan};
    is_deeply($plan->{components}, ['base'], 'pkglist selects the base component');
    is_deeply(plan_applications($plan), [qw(command-app application)], 'application roots retain list order');
    is_deeply([sort map { $_->{name} } @{$plan->{packages}}],
        [sort qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base FreeBSD-ssh FreeBSD-bsdconfig
            pkg command-app command-dep application)], 'native plan includes transitive closure and excludes unused archives');
    is_deeply([map { $_->{role} } @{$plan->{repositories}}], [qw(base applications repository)],
        'base pkgdir precedes the configured supplemental repositories');
    is($plan->{resolver}{sha256}, $solver->{sha256}, 'published plan pins the actual native solver');
    my @before = stat($first->{path});
    my $again = planned('repeat planning');
    if ($again) {
        is($again->{path}, $first->{path}, 'repeat planning reuses the immutable plan path');
        is($again->{digest}, $first->{digest}, 'repeat planning has identical bytes');
        is_deeply([(stat($first->{path}))[0, 1, 2, 3, 4, 7, 9, 10]],
            [@before[0, 1, 2, 3, 4, 7, 9, 10]], 'repeat publication leaves the original inode and metadata intact');
    }
    my $lists = fresh_plan();
    write_file("$lists/first.pkglist", " \t\n  # comment\ncommand-dep\n");
    write_file("$lists/second.pkglist", "application\ncommand-app\n");
    $db_rows{freebsdimage}[0]{otherpkglist} = "$lists/first.pkglist,$lists/second.pkglist";
    $db_rows{freebsdimage}[0]{otherpkgdir} = "$plan_repository->{path}/repository,$plan_release->{path}/applications";
    my $ordered = planned('multiple ordered list files and repositories');
    if ($ordered) {
        is_deeply(plan_applications($ordered->{plan}), [qw(command-dep application command-app)],
            'explicit roots preserve file order and line order after blank/comment skipping');
        is_deeply([map { $_->{role} } @{$ordered->{plan}{repositories}}], [qw(base repository applications)],
            'supplemental repository order is preserved');
    }
    for my $name ('a', 'a' x 247) {
        $lists = fresh_plan();
        $plan_image = $name;
        $_->[0]{imagename} = $name for values %db_rows;
        write_file("$lists/base.pkglist", '');
        delete($db_rows{freebsdimage}[0]{otherpkglist});
        my $minimal = planned('empty protected pkglist with a valid image name length ' . length($name));
        next unless $minimal;
        is_deeply($minimal->{plan}{components}, [], 'empty component file means explicit minimal selection');
        is_deeply(plan_applications($minimal->{plan}), [], 'otherpkglist is optional');
        is_deeply([sort map { $_->{name} } @{$minimal->{plan}{packages}}],
            [sort qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-ssh FreeBSD-bsdconfig pkg)],
            'minimal selection still contains the native runtime, kernel and bootstrap closure');
    }
    return;
}

sub plan_table_fault_cases {
    my $table = shift;
    for my $kind (qw(absent open read close read-and-close)) {
        fresh_plan();
        $db_faults{"new:$table"} = $kind eq 'absent' ? 'absent' : "primary table open failed at fixture-table.pm line 23.\n"
          if $kind eq 'absent' || $kind eq 'open';
        $db_faults{"get:$table"} = "primary table read failed at fixture-table.pm line 41.\n"
          if $kind eq 'read' || $kind eq 'read-and-close';
        $db_faults{"close:$table"} = "secondary table close failed at fixture-table.pm line 57.\n"
          if $kind eq 'close' || $kind eq 'read-and-close';
        my $operation = $kind eq 'open' ? 'open' : 'read';
        my $pattern = $kind eq 'absent' ? qr/\ACannot[ ]open[ ]\Q$table\E[ ]for[ ]image[ ]\Q$plan_image\E/x
          : $kind eq 'close' ? qr/secondary[ ]table[ ]close[ ]failed/x : qr/primary[ ]table[ ]$operation[ ]failed/x;
        my $expected = $kind eq 'open' ? $db_faults{"new:$table"}
          : $db_faults{"get:$table"} || $db_faults{"close:$table"};
        plan_rejected($pattern, "$table $kind failure", 0, $expected);
        is_deeply(\@db_closed, \@db_opened, "$table $kind closes every handle once in acquisition order");
        is_deeply(\@site_reads, [], "$table $kind fails before reading site configuration");
    }
    return;
}

sub plan_table_cases {
    for my $table (qw(osimage freebsdimage)) {
        for my $kind (qw(missing duplicate disabled-yes disabled-1)) {
            fresh_plan();
            $db_rows{$table} = [] if $kind eq 'missing';
            push @{$db_rows{$table}}, dclone($db_rows{$table}[0]) if $kind eq 'duplicate';
            $db_rows{$table}[0]{disable} = $1 if $kind =~ /\Adisabled-(.+)\z/x;
            my $pattern = $kind eq 'duplicate'
              ? qr/\ADuplicate[ ]\Q$table\E[ ]rows[ ]for[ ]image[ ]\Q$plan_image\E/x
              : qr/\AMissing[ ]\Q$table\E[ ]row[ ]for[ ]image[ ]\Q$plan_image\E/x;
            plan_rejected($pattern, "$kind $table row");
        }
        plan_table_fault_cases($table);
    }
    for my $version (undef, '', '1', '3') {
        fresh_plan();
        $db_rows{freebsdimage}[0]{imageversion} = $version;
        plan_rejected(qr/Package[ ]planning[ ]requires[ ]imageversion=2/x,
            'planning rejects an absent or unsupported imageversion');
    }
    my $identity_error = literal_error_pattern('FreeBSD requires imagetype=freebsd, osvers=freebsd15.1, and osarch=x86_64');
    for my $case (
        ['osname', 'Linux', qr/Package[ ]planning[ ]requires[ ]osname=FreeBSD/x],
        ['osvers', 'freebsd14.3', $identity_error],
        ['osarch', 'ppc64le', $identity_error],
        ['imagetype', 'linux', $identity_error],
        ['provmethod', 'netboot', qr/FreeBSD[ ]supports[ ]only[ ]provmethod=install/x],
    ) {
        fresh_plan();
        $db_rows{osimage}[0]{$case->[0]} = $case->[1];
        plan_rejected($case->[2], "incompatible image $case->[0]");
    }
    for my $case (
        [sub { delete($_[0]{solver}) },
            qr/Package[ ]planning[ ]requires[ ]a[ ]pinned[ ]native[ ]solver/x, 'missing native solver'],
        [sub { $_[0]{solver}{sha256} = '0' x 64 },
            qr/Native[ ]pkg[ ]executable[ ]checksum[ ]mismatch/x, 'wrong native solver pin'],
        [sub { $_[0]{tool}{sha256} = '0' x 64 },
            qr/Native[ ]pkg[ ]executable[ ]checksum[ ]mismatch/x, 'wrong native tool pin'],
    ) {
        fresh_plan();
        my $policy = $json->decode(read_file($policy_path));
        $case->[0]->($policy);
        write_file($policy_path, $json->encode($policy));
        plan_rejected($case->[1], $case->[2]);
    }
    return;
}

sub plan_list_cases {
    my $line_endings = literal_error_pattern('Package lists require LF line endings and a final LF');
    my $missing_application = literal_error_pattern('Requested application is unavailable at selection 1');
    for my $case (
        ["command-app\r\n", $line_endings, 'CRLF'],
        ["command-app", $line_endings, 'missing final LF'],
        ["\xff\n", qr/Invalid[ ]package[ ]list[ ]UTF-8/x, 'malformed UTF-8'],
        ["command-app\ncommand-app\n", qr/Duplicate[ ]package[ ]list[ ]root/x, 'duplicate root'],
        ["command-unavailable\n", $missing_application, 'missing named application'],
        [" command-app\n", $missing_application, 'literal leading space'],
        ["command-app \n", $missing_application, 'literal trailing space'],
        ["command-app,command-dep\n", $missing_application, 'literal comma'],
        ["#INCLUDE:other.pkglist\n", qr/Unsupported[ ]package[ ]list[ ]directive/x, 'include directive'],
        ["  #ENV:NAME=value\n", qr/Unsupported[ ]package[ ]list[ ]directive/x, 'indented environment directive'],
        ["#NEW_INSTALL_LIST#\n", qr/Unsupported[ ]package[ ]list[ ]directive/x, 'install-list directive'],
    ) {
        my ($bytes, $pattern, $name) = @$case;
        my $lists = fresh_plan();
        write_file("$lists/apps.pkglist", $bytes);
        plan_rejected($pattern, $name);
    }
    for my $field (qw(pkglist otherpkglist)) {
        my $lists = fresh_plan();
        write_file("$lists/duplicate.pkglist", $field eq 'pkglist' ? "base\n" : "command-app\n");
        $db_rows{freebsdimage}[0]{$field} .= ",$lists/duplicate.pkglist";
        plan_rejected(qr/Duplicate[ ]package[ ]list[ ]root/x, "duplicate selection across $field files");
        fresh_plan();
        $db_rows{freebsdimage}[0]{$field} .= ',' . $db_rows{freebsdimage}[0]{$field};
        plan_rejected(qr/FreeBSD[ ]\Q$field\E[ ]contains[ ]a[ ]duplicate[ ]path/x, "duplicate $field source path");
    }
    fresh_plan();
    $db_rows{freebsdimage}[0]{otherpkglist} = $db_rows{freebsdimage}[0]{pkglist};
    plan_rejected(qr/Duplicate[ ]package[ ]list[ ]source[ ]path/x, 'shared component and application list source');
    for my $value (undef, '') {
        fresh_plan();
        $db_rows{freebsdimage}[0]{pkglist} = $value;
        plan_rejected(qr/pkglist[ ]requires[ ]a[ ]path/x, 'a component list path is required');
    }
    my $lists = fresh_plan();
    write_file("$lists/apps.pkglist", "command-broken\n");
    $db_rows{freebsdimage}[0]{otherpkgdir} = "$plan_broken->{path}/repository";
    plan_rejected(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
        'native application has an unsatisfied transitive dependency', 1);
    return;
}

sub plan_directive_cases {
    for my $field (qw(pkglist otherpkglist)) {
        for my $directive (qw(INCLUDE_PKGLIST INCLUDE_PTRNLIST INCLUDE_RMPKGLIST INCLUDE_NOP
                InClUdE_pKgLiSt InClUdE_pTrNlIsT InClUdE_rMpKgLiSt InClUdE_nOp)) {
            my $lists = fresh_plan();
            my $path = "$lists/directive.pkglist";
            write_file($path, "# ordinary comment\n\n  #$directive:missing.pkglist\n");
            $db_rows{freebsdimage}[0]{$field} = $path;
            plan_rejected(qr/Unsupported[ ]package[ ]list[ ]directive/x, "$field $directive directive");
        }
    }
    return;
}

sub redacted_plan_rejection {
    my ($pattern, $description, $native_resolution) = @_;
    my $responses = plan_rejected($pattern, $description, $native_resolution);
    unlike($json->encode($responses), qr/\Q$private_root\E/x, "$description does not disclose protected list contents");
    return $responses;
}

sub plan_redaction_cases {
    my $lists = fresh_plan();
    my $path = "$lists/private.pkglist";
    write_file($path, "# private components\n\n$private_root\n");
    chmod(oct('0600'), $path) or croak $!;
    $db_rows{freebsdimage}[0]{pkglist} .= ",$path";
    redacted_plan_rejection(literal_error_pattern('Unavailable native base component at selection 2'),
        'unavailable component in the second protected list');

    $lists = fresh_plan();
    $path = "$lists/private.pkglist";
    write_file("$lists/apps.pkglist", "# public roots\ncommand-app\n");
    write_file($path, "# private applications\n\n$private_root\n");
    chmod(oct('0600'), $path) or croak $!;
    $db_rows{freebsdimage}[0]{otherpkglist} .= ",$path";
    redacted_plan_rejection(literal_error_pattern('Requested application is unavailable at selection 2'),
        'unavailable application in the second protected list');

    for my $case (
        ["# private roots\n\n$private_root\tprivate-value\n",
            qr/Invalid[ ]package[ ]list[ ]root/x, 'invalid private list root', 3],
        ["# private roots\n\n$private_root\n$private_root\n",
            qr/Duplicate[ ]package[ ]list[ ]root/x, 'duplicate private list root', 4],
    ) {
        $lists = fresh_plan();
        $path = "$lists/apps.pkglist";
        write_file($path, $case->[0]);
        chmod(oct('0600'), $path) or croak $!;
        my $responses = redacted_plan_rejection($case->[1], $case->[2]);
        my $line_number = $case->[3];
        like(messages($responses, 'error'),
            qr/in[ ]otherpkglist[ ]file[ ]\Q$path\E[ ]line[ ]$line_number\b/x,
            "$case->[2] identifies the source file and physical line without its contents");
    }

    $lists = fresh_plan();
    write_file("$lists/apps.pkglist", "$private_root\n");
    chmod(oct('0600'), "$lists/apps.pkglist") or croak $!;
    $db_rows{freebsdimage}[0]{otherpkgdir} = "$plan_broken->{path}/repository";
    redacted_plan_rejection(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
        'private root with an unsatisfied native dependency', 1);
    return;
}

sub list_file_hazards {
    my $protected = literal_error_pattern('FreeBSD otherpkglist must be a protected bounded regular file');
    return [
        ['missing', sub { unlink($_[1]) or croak $!; return; }, $protected],
        ['symlink', sub {
            my $path = $_[1];
            rename($path, "$path.real") or croak $!;
            symlink("$path.real", $path) or croak $!;
            return;
        }, $protected],
        ['hardlink', sub {
            my $path = $_[1];
            link($path, "$path.alias") or croak $!;
            return;
        }, $protected],
        ['writable-file', sub { chmod(oct('0666'), $_[1]) or croak $!; return; }, $protected],
        ['writable-parent', sub { chmod(oct('0777'), $_[0]) or croak $!; return; },
            qr/Writable[ ]publication[ ]directory:/x],
        ['symlink-parent', sub {
            my $lists = $_[0];
            symlink($lists, "$lists.alias") or croak $!;
            $db_rows{freebsdimage}[0]{otherpkglist} = "$lists.alias/apps.pkglist";
            return;
        }, qr/Missing[ ]or[ ]symlinked[ ]publication[ ]directory:/x],
        ['directory', sub { $db_rows{freebsdimage}[0]{otherpkglist} = $_[0]; return; }, $protected],
        ['foreign-owner', sub { chown(65534, -1, $_[1]) == 1 or croak $!; return; }, $protected],
    ];
}

sub plan_list_file_cases {
    for my $case (@{list_file_hazards()}) {
        my ($kind, $change, $pattern) = @$case;
        my $lists = fresh_plan();
        $change->($lists, "$lists/apps.pkglist");
        plan_rejected($pattern, "$kind package list");
    }
    return;
}

sub plan_list_bound_cases {
    my $lists = fresh_plan();
    my @paths = map { "$lists/empty-$_.pkglist" } 1 .. 65;
    write_file($_, '') for @paths;
    delete($db_rows{freebsdimage}[0]{otherpkglist});
    $db_rows{freebsdimage}[0]{pkglist} = join(',', @paths[0 .. 63]);
    planned('exactly 64 protected list files');
    $db_rows{freebsdimage}[0]{pkglist} = join(',', @paths);
    plan_rejected(qr/pkglist[ ]exceeds[ ]the[ ]64[ ]path[ ]limit/x, '65 component list files');
    $lists = fresh_plan();
    my $comment = '#' . ('x' x (1048576 - 2)) . "\n";
    write_file("$lists/base.pkglist", $comment);
    delete($db_rows{freebsdimage}[0]{otherpkglist});
    planned('exactly one MiB protected list');
    write_file("$lists/base.pkglist", $comment . "\n");
    plan_rejected(literal_error_pattern('FreeBSD pkglist must be a protected bounded regular file'),
        'list exceeds one MiB by one byte');
    $lists = fresh_plan();
    @paths = map { "$lists/comment-$_.pkglist" } 1 .. 9;
    write_file($_, $comment) for @paths[0 .. 7];
    write_file($paths[8], "\n");
    $db_rows{freebsdimage}[0]{pkglist} = join(',', @paths[0 .. 3]);
    $db_rows{freebsdimage}[0]{otherpkglist} = join(',', @paths[4 .. 7]);
    planned('exactly eight MiB shared across both list fields');
    $db_rows{freebsdimage}[0]{otherpkglist} .= ",$paths[8]";
    plan_rejected(literal_error_pattern('Combined package list bytes exceed the 8 MiB limit'),
        'combined list bytes exceed eight MiB by one byte');
    $lists = fresh_plan();
    write_file("$lists/apps.pkglist", join('', map { "root-$_\n" } 1 .. 8192));
    plan_rejected(literal_error_pattern('Combined package list roots exceed the 8192 limit'),
        '8193 component and application roots combined');
    $lists = fresh_plan();
    write_file("$lists/apps.pkglist", join('', map { "root-$_\n" } 1 .. 8191));
    plan_rejected(qr/Expanded[ ]package[ ]roots[ ]exceed[ ]the[ ]8192[ ]limit/x,
        '8192 input roots expand beyond the native solver limit');
    fresh_plan();
    $db_rows{freebsdimage}[0]{otherpkgdir} = join(',', map { "$installroot/repository-$_" } 1 .. 32);
    plan_rejected(qr/otherpkgdir[ ]exceeds[ ]the[ ]31[ ]path[ ]limit/x,
        'base plus 32 supplemental repositories exceeds the limit');
    return;
}

sub native_plan_cases {
    plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_SOLVER to the native resolver executable') unless $solver;
    subtest 'native command planning and immutable readback' => \&plan_success_cases;
    subtest 'keyed image reads and table cleanup' => \&plan_table_cases;
    subtest 'literal ordered list parsing' => \&plan_list_cases;
    subtest 'legacy list directives are rejected explicitly' => \&plan_directive_cases;
    subtest 'protected list contents stay out of errors' => \&plan_redaction_cases;
    subtest 'authenticated package planning diagnostics' => \&plan_diagnostic_cases;
    subtest 'package list file protection' => \&plan_list_file_cases;
    subtest 'package list and repository bounds' => \&plan_list_bound_cases;
    subtest 'transported planning requests' => \&plan_transport_cases;
    is_deeply([map { xCAT::FreeBSDRepo::snapshot_tree($_->{path}) } ($plan_release, $plan_repository, $plan_broken)],
        $plan_sources_before, 'planning success and failures preserve the immutable repository inputs');
    return;
}

sub client_stub {
    return <<'CLIENT';
package xCAT::Client;
use strict;
use warnings;
use JSON;
our $EXITCODE = 0;
sub handle_response { return; }
sub submit_request {
    print JSON->new->canonical->encode($_[0]);
    return;
}
1;
CLIENT
}

sub rpm_aliases {
    my $path = shift;
    my @rpm;
    my $install_section = 0;
    my $conditional_depth = 0;
    my %sections = map { $_ => 1 } qw(install prep build check clean files pre post preun postun changelog);
    for my $line (split(/\n/x, read_file($path))) {
        ++$conditional_depth if $line =~ /\A%if(?:n?arch|n?os)?(?:\s|\z)/x;
        --$conditional_depth if $line =~ /\A%endif(?:\s|\z)/x;
        if ($line =~ /\A%(\w+)(?:\s|\z)/x && $sections{$1}) {
            $install_section = $1 eq 'install';
        }
        next unless $install_section && $line =~ /\Aln\s/x;
        my @words = shellwords($line);
        next unless @words && $words[0] eq 'ln' && $words[-1] =~ m{/sbin/freebsdrepo\z}x;
        is($conditional_depth, 0, 'RPM client alias is outside conditional sections');
        push @rpm, \@words;
    }
    return \@rpm;
}

sub alias_declarations {
    my $root = "$FindBin::Bin/../../xCAT-client";
    my $rpm = rpm_aliases("$root/xCAT-client.spec");
    is_deeply($rpm, [['ln', '-sf', '../bin/xcatclientnnr', '$RPM_BUILD_ROOT/%{prefix}/sbin/freebsdrepo']],
        'RPM installation artifact declares the supported client alias');
    my @deb = map { [split(/\s+/x, $_)] }
      grep { m{\sopt/xcat/sbin/freebsdrepo\z}x } split(/\n/x, read_file("$root/debian/xcat-client.links"));
    is_deeply(\@deb, [['opt/xcat/bin/xcatclientnnr', 'opt/xcat/sbin/freebsdrepo']],
        'Debian link artifact declares the supported client alias');
    return [] unless @$rpm == 1 && @deb == 1;
    my %targets = map { $_ => 1 } ($rpm->[0][2], '../bin/' . (split(m{/}x, $deb[0][0]))[-1]);
    return [sort keys %targets];
}

sub client_requests {
    my ($target, $arguments) = @_;
    my $client = "$FindBin::Bin/../../xCAT-client/bin/xcatclientnnr";
    my $root = $fixture->new_directory();
    make_path("$root/bin", "$root/sbin");
    copy($client, "$root/bin/xcatclientnnr") or croak $!;
    symlink($target, "$root/sbin/freebsdrepo") or croak $!;
    write_file("$root/lib/perl/xCAT/Client.pm", client_stub());
    my @requests;
    for my $argv (["$root/sbin/freebsdrepo", @$arguments],
        ["$root/bin/xcatclientnnr", 'freebsdrepo', @$arguments]) {
        my %env = (%environment, XCATROOT => $root, TERM => 'dumb', SHELL => '/bin/sh');
        my $result = xCAT::FreeBSDPkg::run_command([$^X, @$argv], cwd => $tmp,
            environment => \%env, timeout => 10, stdout_limit => 1048576);
        is($result->{exitcode}, 0, 'actual client exits successfully at submit_request boundary');
        is($result->{signal}, 0, 'client is not killed');
        my $received = $json->decode($result->{stdout});
        my @expected = @$argv;
        shift @expected;
        shift @expected if $expected[0] eq 'freebsdrepo';
        is_deeply($received->{command}, ['freebsdrepo'], 'client preserves dedicated command name');
        is_deeply($received->{arg}, \@expected, 'client preserves every argument');
        is_deeply([sort grep { /\A(?:node|noderange|range)\z/x } keys %$received], [],
            'client omits node and range fields');
        push @requests, $received;
    }
    return @requests;
}

sub client_response {
    my $responses = shift;
    my $input = $fixture->new_directory() . '/responses.json';
    write_file($input, $json->encode($responses));
    my $client = abs_path("$FindBin::Bin/../../perl-xCAT/xCAT/Client.pm");
    croak 'The actual client module is required' unless defined($client);
    my $program = <<'CLIENT_RESPONSE';
use strict;
use warnings;
use JSON;
require $ARGV[0];
open(my $input, '<', $ARGV[1]) or die $!;
binmode($input) or die $!;
my $bytes = do { local $/; <$input> };
close($input) or die $!;
my $responses = JSON->new->utf8->decode($bytes);
$xCAT::Client::EXITCODE = 0;
xCAT::Client::handle_response($_) for @$responses;
exit($xCAT::Client::EXITCODE);
CLIENT_RESPONSE
    my %env = (%environment, XCATROOT => abs_path("$FindBin::Bin/../.."), TERM => 'dumb', SHELL => '/bin/sh');
    return xCAT::FreeBSDPkg::run_command([$^X, '-e', $program, $client, $input], cwd => $tmp,
        environment => \%env, timeout => 10, stdout_limit => 1048576);
}

sub diagnostic_client_cases {
    my ($ordinary, $detailed) = @_;
    my $default = client_response($ordinary);
    my $diagnostic = client_response($detailed);
    is($default->{signal}, 0, 'ordinary actual client handler terminates normally');
    is($diagnostic->{signal}, 0, 'diagnostic actual client handler terminates normally');
    is($default->{exitcode}, 1, 'ordinary actual client handler preserves the nonzero EXITCODE');
    is($diagnostic->{exitcode}, 1, 'diagnostic actual client handler preserves the nonzero EXITCODE');
    is($default->{stdout}, '', 'ordinary actual client handler emits no diagnostic data');
    is($default->{stderr}, join('', map { "Error: $_\n" } @{$ordinary->[0]{error}}),
        'ordinary actual client handler prints the exact existing error');
    is($diagnostic->{stderr}, $default->{stderr}, 'diagnostics leave actual client stderr unchanged');
    is($diagnostic->{stdout}, "$detailed->[0]{data}[0]\n",
        'actual client handler prints the exact diagnostic line on stdout');
    return;
}

sub transport_cases {
    my $targets = alias_declarations();
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n"
      . "       freebsdrepo plan osimage [--diagnostics]\n";
    for my $target (@$targets) {
        for my $case (['inspect', $signed], ['--help']) {
            for my $received (client_requests($target, $case)) {
                fresh();
                my $data = $case->[0] eq 'inspect'
                  ? "TREE_DIGEST:$source_tree->{digest}\nBYTES:$source_tree->{bytes}\n" : $usage;
                is_deeply(request($received), [{ data => [$data] }],
                    'transported read-only request returns the exact successful response');
                is_deeply(\@site_reads, [], 'transported read-only request does not read site configuration');
                no_effect('transported read-only request');
            }
        }
    }
    return;
}

sub import_transport_cases {
    for my $target (@{alias_declarations()}) {
        for my $received (client_requests($target, ['import', $signed, '--policy', 'approved'])) {
            fresh();
            my $responses = request($received);
            my $paths = publications();
            is(scalar(@$paths), 1, 'transported import creates one immutable publication');
            next unless @$paths == 1;
            my $path = $paths->[0];
            is_deeply($responses,
                [{ data => ["Imported FreeBSD repository to $path", "Repository: $path/repository"] }],
                'transported import returns the exact successful response');
            my $manifest = xCAT::FreeBSDRepoImport::inspect_import($path, $installroot);
            is($manifest->{native_validated}, 1, 'transported publication manifest records native validation');
            is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$path/repository"), $source_tree,
                'transported import publishes the complete source snapshot');
            is_deeply(\@db_access, [], 'transported import leaves image/package selections untouched');
        }
    }
    return;
}

sub plan_transport_cases {
    for my $target (@{alias_declarations()}) {
        for my $received (client_requests($target, ['plan', 'freebsd15.1-x86_64-install-command'])) {
            fresh_plan();
            planned('transported planning request', $received);
            my @reads = grep { $_->[0] eq 'get' } @db_access;
            is(scalar(@reads), 2, 'transported planning reads both image records');
        }
    }
    return;
}

sub native_cases {
    plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG for native repository cases')
      unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
    plan(skip_all => 'Native repository cases require Linux') unless $^O eq 'linux';
    plan(skip_all => 'Native repository cases require container root') if $> != 0;
    native_fixtures();
    subtest 'native import and nonoverwrite' => \&import_cases;
    subtest 'explicit independent profiles' => \&profile_cases;
    subtest 'policy and trust failures' => \&policy_cases;
    subtest 'signed source integrity failures' => \&source_failure_cases;
    subtest 'transported imports publish complete repositories' => \&import_transport_cases;
    subtest 'image package planning through the command' => \&native_plan_cases;
    return;
}

sub diagnostic_authorization_cases {
    fresh();
    my ($native, $protected, $imports) = (0, 0, 0);
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native; croak 'Unexpected native command'; };
    local *xCAT::FreeBSDRepoImport::read_protected_file = sub { ++$protected; croak 'Unexpected protected read'; };
    local *xCAT::FreeBSDRepoImport::inspect_import = sub { ++$imports; croak 'Unexpected import read'; };
    for my $auth (undef, 'root', [], [undef], ['operator'], ['ROOT'], ['root', 'operator'], [{}]) {
        my $request = { command => ['freebsdrepo'], arg => ['plan', 'image', '--diagnostics'],
            username => ['root'] };
        $request->{_xcat_authname} = $auth if defined($auth);
        rejected(request($request), qr/\APackage[ ]diagnostics[ ]require[ ]authenticated[ ]root\n\z/x,
            'untrusted diagnostic authority is rejected');
    }
    for my $action (qw(inspect import)) {
        rejected(request({ command => ['freebsdrepo'], arg => [$action, $signed, '--diagnostics'],
            _xcat_authname => ['root'] }), qr/\ADiagnostics[ ]require[ ]the[ ]plan[ ]action\n\z/x,
            'diagnostics cannot extend another action');
    }
    is_deeply(\@db_access, [], 'diagnostic denial precedes all image-table reads');
    is_deeply(\@site_reads, [], 'diagnostic denial precedes site and policy access');
    is($protected, 0, 'diagnostic denial precedes protected file reads');
    is($imports, 0, 'diagnostic denial precedes imported repository reads');
    is($native, 0, 'diagnostic denial precedes native execution');
    return;
}

sub diagnostic_request {
    return { command => ['freebsdrepo'], arg => ['plan', $plan_image, '--diagnostics'],
        _xcat_authname => ['root'] };
}

sub diagnostic_report {
    my $responses = shift;
    is(scalar(@$responses), 1, 'diagnostic failure uses one response');
    my @items = map { @{$_->{data} || []} } @$responses;
    is(scalar(@items), 1, 'diagnostic failure has exactly one data item');
    my ($bytes) = @items && $items[0] =~ /\ADIAGNOSTICS:(.*)\z/sx;
    ok(defined($bytes), 'diagnostic item has the explicit marker');
    return unless defined($bytes);
    cmp_ok(length($bytes), '<=', 262144, 'encoded report respects its byte cap');
    unlike($bytes, qr/[^\x20-\x7e]/x, 'report is single-line ASCII JSON');
    my $report = $json->decode($bytes);
    is_deeply([sort keys %$report], [qw(format records scope status)], 'report has only declared fields');
    is($report->{format}, 'xcat-freebsd-package-diagnostics-1', 'report declares its version');
    like($report->{status}, qr/\A(?:complete|truncated|unavailable)\z/x, 'report has an explicit completion marker');
    cmp_ok(scalar(@{$report->{records}}), '<=', 64, 'report respects its record cap');
    for my $diagnostic (@{$report->{records}}) {
        cmp_ok(length(JSON->new->ascii->canonical->encode($diagnostic)), '<=', 65536,
            'encoded record respects its byte cap');
    }
    return $report;
}

sub detailed_rejection {
    my ($pattern, $description, $native) = @_;
    my $responses = plan_rejected($pattern, $description, $native, undef,
        { transported => diagnostic_request(), detailed => 1 });
    unlike($json->encode($responses), qr/native-secret-value/x, 'diagnostics never copy native stderr');
    return (diagnostic_report($responses), $responses);
}

sub direct_diagnostic_cases {
    for my $case (['pkglist', 'missing-component', 'src'],
            ['otherpkglist', 'missing-application', 'missing "quoted" \\ name-' . "\x{1f600}"] ) {
        my ($field, $kind, $name) = @$case;
        my $lists = fresh_plan();
        my $path = "$lists/diagnostic.pkglist";
        write_file($path, encode_utf8("$name\n"));
        chmod(oct('0600'), $path) or croak $!;
        $db_rows{freebsdimage}[0]{$field} = $path;
        my $pattern = $field eq 'pkglist' ? qr/Unavailable[ ]native[ ]base[ ]component/x
          : qr/Requested[ ]application[ ]is[ ]unavailable/x;
        my $ordinary = plan_rejected($pattern, 'ordinary missing selection', 0);
        for my $auth ('root', 'operator') {
            my $response = plan_rejected($pattern, 'ordinary authenticated missing selection', 0, undef,
                { transported => { command => ['freebsdrepo'], arg => ['plan', $plan_image], _xcat_authname => [$auth] } });
            is_deeply($response, $ordinary, 'ordinary root and nonroot responses preserve exact redacted output');
        }
        my ($report, $responses) = detailed_rejection($pattern, 'explicit missing-selection diagnostics', 0);
        is(messages($responses, 'error'), messages($ordinary, 'error'), 'diagnostics preserve the exact ordinary error');
        is_deeply($report, { format => 'xcat-freebsd-package-diagnostics-1', scope => 'requested-selection',
            status => 'complete', records => [{ kind => $kind, selection => 1, name => $name }] },
            'authorized diagnostics retain the exact validated missing selection');
        diagnostic_client_cases($ordinary, $responses);
    }
    return;
}

sub catalogue_diagnostic_cases {
    my $lists = fresh_plan();
    write_file("$lists/apps.pkglist", "command-broken\n");
    $db_rows{freebsdimage}[0]{otherpkgdir} = "$plan_broken->{path}/repository";
    my $failure = qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x;
    my $ordinary = plan_rejected($failure, 'ordinary native missing-dependency failure', 1);
    for my $auth ('root', 'operator') {
        my $response = plan_rejected($failure, 'ordinary authenticated native failure', 1, undef,
            { transported => { command => ['freebsdrepo'], arg => ['plan', $plan_image], _xcat_authname => [$auth] } });
        is_deeply($response, $ordinary, 'ordinary root and nonroot native failures preserve exact redacted output');
    }
    unlike($json->encode($ordinary), qr/(?:\Q$private_root\E|command-unavailable)/x,
        'ordinary native failures do not disclose catalogue names');
    my ($report, $first) = detailed_rejection($failure,
        'real missing-dependency failure', 1);
    is(messages($first, 'error'), messages($ordinary, 'error'), 'native diagnostics preserve the exact ordinary error');
    diagnostic_client_cases($ordinary, $first);
    my @expected = map { { kind => 'unavailable-dependency-name', dependency => 'command-unavailable',
        repository => { id => 'r1', publication => $plan_broken->{digest}, role => 'repository' },
        package => { name => $_, version => '1', origin => "misc/$_", abi => 'FreeBSD:15:amd64' } } }
      ('command-broken', $private_root);
    is_deeply($report, { format => 'xcat-freebsd-package-diagnostics-1',
        scope => 'imported-catalogue-name-references', status => 'complete', records => \@expected },
        'report labels requested and unselected broken records as catalogue references only');
    my (undef, $repeated) = detailed_rejection(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
        'repeated missing-dependency diagnostics', 1);
    is_deeply($repeated, $first, 'repeated diagnostics preserve exact order and encoding');
    my $outside = $fixture->repository(1, [['command-unavailable', version => '99']]);
    xCAT::FreeBSDRepoImport::import_repository($outside, $installroot, tool => $tool, trust => pubkey('repo'));
    my (undef, $unrelated) = detailed_rejection(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
        'missing reference with an unrelated publication present', 1);
    is_deeply($unrelated, $first, 'a repository outside this image cannot suppress an absence fact');
    return;
}

sub injected_diagnostic_failure {
    my ($action, $change) = @_;
    my $run = \&xCAT::FreeBSDPkg::run_command;
    my $mutations = 0;
    {
        no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
        local *xCAT::FreeBSDPkg::run_command = sub {
            my $result = $run->(@_);
            my $argv = $_[0];
            if (@$argv == 6 && $argv->[0] eq $solver->{path} && $argv->[3] eq 'resolve') {
                croak 'Native solve failed before diagnostic injection'
                  if $result->{exitcode} || $result->{signal} || length($result->{stderr});
                ++$mutations;
                return $change->($result) if $change;
                return { %$result, exitcode => 7, stderr => 'native-secret-value' };
            }
            return $result;
        };
        $action->();
    }
    is($mutations, 1, 'one real successful solve receives the failing process outcome');
    is(\&xCAT::FreeBSDPkg::run_command, $run, 'process boundary is restored');
    return;
}

sub present_name_diagnostic_cases {
    my $lists = fresh_plan();
    my $source = $fixture->repository(1, [
        ['diagnostic-unused', deps => { 'command-dep' => { origin => 'misc/command-dep', version => '99' } }],
    ]);
    my $import = xCAT::FreeBSDRepoImport::import_repository($source, $installroot, tool => $tool, trust => pubkey('repo'));
    $db_rows{freebsdimage}[0]{otherpkgdir} .= ",$import->{path}/repository";
    injected_diagnostic_failure(sub {
        my ($report) = detailed_rejection(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
            'failure with a same-name different-version provider', 1);
        is_deeply($report, { format => 'xcat-freebsd-package-diagnostics-1',
            scope => 'imported-catalogue-name-references', status => 'complete', records => [] },
            'name presence prevents a false absence fact without comparing versions or claiming successful resolution');
    });
    my $ordinary = planned('ordinary restored success with unused mismatched-version metadata');
    my $original_bytes = $ordinary ? read_file($ordinary->{path}) : undef;
    my $detailed = planned('diagnostic option on a restored success', diagnostic_request());
    if ($ordinary && $detailed) {
        is(read_file($detailed->{path}), $original_bytes, 'diagnostic success preserves exact plan bytes');
        is($detailed->{digest}, $ordinary->{digest}, 'diagnostic success preserves the plan digest');
    }
    return;
}

sub unavailable_diagnostic_cases {
    my $lists = fresh_plan();
    my $name = 'dependency-private-sentinel-' . ('x' x (1025 - length('dependency-private-sentinel-')));
    my $source = $fixture->repository(1, [
        ['diagnostic-long-reference', deps => { $name => { origin => 'misc/long-reference', version => '1' } }],
    ]);
    my $import = xCAT::FreeBSDRepoImport::import_repository($source, $installroot, tool => $tool, trust => pubkey('repo'));
    $db_rows{freebsdimage}[0]{otherpkgdir} = "$plan_broken->{path}/repository,$import->{path}/repository";
    write_file("$lists/apps.pkglist", "command-broken\n");
    my $ordinary = plan_rejected(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
        'ordinary failure with an imported long dependency reference', 1);
    my ($report, $responses) = detailed_rejection(qr/Native[ ]pkg[ ]dependency[ ]resolution[ ]failed/x,
        'collector rejects an imported dependency name outside its output contract', 1);
    is_deeply($report, { format => 'xcat-freebsd-package-diagnostics-1',
        scope => 'imported-catalogue-name-references', status => 'unavailable', records => [] },
        'unavailable collection discards partial facts without changing the native failure');
    is(messages($responses, 'error'), messages($ordinary, 'error'), 'collector failure preserves the exact native error');
    unlike($json->encode($responses), qr/dependency-private-sentinel/x, 'unavailable collection exposes no invalid dependency name');
    return;
}

sub plan_diagnostic_cases {
    subtest 'direct facts and unchanged ordinary responses' => \&direct_diagnostic_cases;
    subtest 'real native failures and unselected catalogue facts' => \&catalogue_diagnostic_cases;
    subtest 'literal name presence and restored successful output' => \&present_name_diagnostic_cases;
    subtest 'native imported dependency outside the diagnostic name contract' => \&unavailable_diagnostic_cases;
    subtest 'missing requested application in returned native jobs' => sub {
        fresh_plan();
        injected_diagnostic_failure(sub {
            my $missing_application = qr/Requested[ ]application[ ]is[ ]absent/x;
            my $native_selection = qr/[ ]from[ ]native[ ]selection/x;
            my ($report) = detailed_rejection(qr/$missing_application$native_selection/x,
                'a requested application omitted from actual native jobs', 1);
            is_deeply($report, { format => 'xcat-freebsd-package-diagnostics-1', scope => 'requested-selection',
                status => 'complete', records => [{ kind => 'application-not-selected', selection => 1,
                    name => 'command-app' }] }, 'the missing selected application is named without exposing native text');
        }, sub {
            my $result = shift;
            my $decoded = $json->decode($result->{stdout});
            $decoded->{jobs} = [grep { $_->{package}{name} ne 'command-app' } @{$decoded->{jobs}}];
            return { %$result, stdout => $json->encode($decoded) };
        });
        planned('success after restoring the returned native jobs');
    };
    subtest 'early policy failure cannot produce a catalogue report' => sub {
        fresh_plan();
        write_file($policy_path, '{');
        my $ordinary = plan_rejected(qr/Invalid[ ]FreeBSD[ ]import[ ]policy[ ]JSON/x, 'ordinary malformed-policy rejection', 0);
        my $detailed = plan_rejected(qr/Invalid[ ]FreeBSD[ ]import[ ]policy[ ]JSON/x, 'diagnostic malformed-policy rejection', 0,
            undef, { transported => diagnostic_request() });
        is_deeply($detailed, $ordinary, 'unverified imports have no diagnostic report');
    };
    return;
}

sub diagnostic_destination_cases {
    my $existing = 'previous report';
    for my $value (undef, 'text', [], {}, \$existing) {
        for my $call (\&xCAT::FreeBSDPackagePlan::resolve, \&xCAT::FreeBSDPackagePlan::resolve_image) {
            my $ok = eval { $call->(diagnostics => $value); 1; };
            my $error = $@;
            ok(!$ok, 'invalid diagnostic output parameter is rejected');
            is($error, "FreeBSD package plan: Invalid diagnostic destination\n",
                'output validation precedes missing inputs or protected reads');
        }
    }
    is($existing, 'previous report', 'a prepopulated output destination is not overwritten');
    return;
}

sub diagnostic_collector_shape_cases {
    my $repositories = [{ id => 'r0', publication => ('0' x 64), role => 'repository' }];
    my $package = { name => 'defensive-fixture', version => '1', origin => 'misc/defensive-fixture',
        abi => 'FreeBSD:15:amd64' };
    for my $deps (undef, [], 'shape-private-sentinel', { 'shape-private-sentinel' => [] },
        { "shape-private-sentinel\n" => {} }) {
        my $sources = [{ packages => { fixture => { %$package, deps => $deps } } }];
        # These defensive shape checks do not require malformed imports to be accepted.
        my $ok = eval { xCAT::FreeBSDPackagePlan::_catalogue_diagnostics($repositories, $sources, {}, {}); 1; }; ## no critic (Subroutines::ProtectPrivateSubs)
        my $error = $@;
        ok(!$ok, 'defensive collector rejects invalid dependency metadata');
        is($error, "FreeBSD package plan: Invalid diagnostic dependency metadata\n",
            'defensive collector returns no malformed metadata or secret text');
    }
    # The empty-input case is the control for the same collector boundary.
    my $bytes = xCAT::FreeBSDPackagePlan::_catalogue_diagnostics( ## no critic (Subroutines::ProtectPrivateSubs)
        $repositories, [{ packages => { fixture => $package } }], {}, {});
    is_deeply($json->decode($bytes), { format => 'xcat-freebsd-package-diagnostics-1',
        scope => 'imported-catalogue-name-references', status => 'complete', records => [] },
        'absent dependency metadata is an empty complete factual scan');
    return;
}

sub diagnostic_prefix_fixture {
    my ($count, $bytes) = @_;
    my $encoder = JSON->new->ascii->canonical;
    my @records = map { { kind => 'missing-application', selection => $_, name => '' } } 1 .. $count;
    my $report = { format => 'xcat-freebsd-package-diagnostics-1', scope => 'requested-selection',
        status => 'complete', records => \@records };
    my $remaining = $bytes - length($encoder->encode($report));
    croak 'Invalid prefix fixture size' if $remaining < 0;
    for my $diagnostic (@records) {
        my $length = $remaining > 65000 ? 65000 : $remaining;
        $diagnostic->{name} = 'x' x $length;
        $remaining -= $length;
    }
    croak 'Insufficient fixture records' if $remaining;
    is(length($encoder->encode($report)), $bytes, 'prefix fixture has the requested exact encoded size');
    return \@records;
}

sub diagnostic_limit_cases {
    my $append = sub {
        my ($report, $diagnostic) = @_;
        my $result;
        # These bounds require exact serializer inputs, independent of imported package metadata.
        my $ok = eval { $result = xCAT::FreeBSDPackagePlan::_diagnostic_append($report, $diagnostic); 1; }; ## no critic (Subroutines::ProtectPrivateSubs)
        ok($ok, 'production diagnostic bound decision completes');
        return $result;
    };
    my $report = { format => 'xcat-freebsd-package-diagnostics-1', scope => 'requested-selection',
        status => 'complete', records => [] };
    for my $index (1 .. 64) {
        is($append->($report, { kind => 'missing-application', selection => $index, name => "missing-$index" }),
            1, 'each record through the exact count boundary is admitted');
    }
    my $prefix = dclone($report->{records});
    is($append->($report, { kind => 'missing-application', selection => 65, name => 'missing-65' }),
        0, 'record 65 is excluded');
    is($report->{status}, 'truncated', 'count limit has an explicit marker');
    is_deeply($report->{records}, $prefix, 'count limit retains the exact admitted prefix');

    my $encoder = JSON->new->ascii->canonical;
    for my $extra (0, 1) {
        my $diagnostic = { kind => 'missing-application', selection => 1, name => '' };
        $diagnostic->{name} = 'x' x (65536 - length($encoder->encode($diagnostic)) + $extra);
        my $single = { %$report, status => 'complete', records => [] };
        is(length($encoder->encode($diagnostic)), 65536 + $extra, 'fixture straddles the encoded per-record boundary');
        is($append->($single, $diagnostic), $extra ? 0 : 1, 'production checks the exact encoded record size');
        is($single->{status}, $extra ? 'truncated' : 'complete', 'record byte cap has the expected marker');
        is(scalar(@{$single->{records}}), $extra ? 0 : 1, 'oversized record is not emitted');
    }

    for my $branch (qw(count record total)) {
        for my $terminal_bytes (262144, 262143) {
            my $total = { %$report, status => 'complete', records => [] };
            my $records = diagnostic_prefix_fixture($branch eq 'count' ? 64 : 5, $terminal_bytes - 1);
            my @admitted = map { $append->($total, $_) } @$records;
            is_deeply(\@admitted, [(1) x @$records], "$branch cap $terminal_bytes admits the complete prefix");
            is(length($encoder->encode($total)), $terminal_bytes - 1,
                "$branch cap $terminal_bytes has exact complete-prefix bytes");
            my $before = dclone($total->{records});
            my $next = { kind => 'missing-application', selection => 65, name => 'next' };
            if ($branch eq 'record') {
                $next->{name} = '';
                $next->{name} = 'x' x (65537 - length($encoder->encode($next)));
                is(length($encoder->encode($next)), 65537, 'record branch uses an exactly oversized encoded record');
            }
            is($append->($total, $next), 0, "$branch cap $terminal_bytes rejects the next record");
            is($total->{status}, 'truncated', "$branch cap $terminal_bytes marks truncation");
            is_deeply($total->{records}, $before, "$branch cap $terminal_bytes preserves the complete prefix");
            is(length($encoder->encode($total)), $terminal_bytes, "$branch cap $terminal_bytes reserves the terminal marker");
        }
    }

    for my $branch (qw(count record total)) {
        my $at_cap = { %$report, status => 'complete', records => [] };
        my $records = diagnostic_prefix_fixture($branch eq 'count' ? 64 : 5, 262144);
        for my $index (0 .. $#$records - 1) {
            is($append->($at_cap, $records->[$index]), 1, "$branch complete-at-cap control admits each preceding record");
        }
        my $before = dclone($at_cap->{records});
        is($append->($at_cap, $records->[-1]), 0, "$branch complete-at-cap admission reserves the terminal byte");
        is($at_cap->{status}, 'truncated', "$branch complete-at-cap admission marks truncation");
        is(sha256_hex($encoder->encode($at_cap->{records})), sha256_hex($encoder->encode($before)),
            "$branch complete-at-cap admission retains only the bounded prefix");
        my $next = { kind => 'missing-application', selection => 65, name => '' };
        $next->{name} = 'x' x (($branch eq 'record' ? 65537 : 65536) - length($encoder->encode($next)));
        is($append->($at_cap, $next), 0, "$branch complete-at-cap successor is rejected");
        cmp_ok(length($encoder->encode($at_cap)), '<=', 262144, "$branch complete-at-cap successor cannot overflow the report");
    }
    return;
}

if (defined($ENV{XCAT_FREEBSD_DIAGNOSTIC_CASE})) {
    my %cases = (authority => \&diagnostic_authorization_cases, bounds => \&diagnostic_limit_cases,
        catalogue => \&catalogue_diagnostic_cases, presence => \&present_name_diagnostic_cases);
    my $case = $ENV{XCAT_FREEBSD_DIAGNOSTIC_CASE};
    croak 'Unknown focused diagnostic case' unless exists($cases{$case});
    subtest "focused diagnostic $case" => sub {
        if ($case eq 'catalogue' || $case eq 'presence') {
            croak 'Focused native diagnostics require native pkg, solver, Linux and container root'
              unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG}) && defined($ENV{XCAT_FREEBSD_NATIVE_SOLVER})
              && $^O eq 'linux' && $> == 0;
            native_fixtures();
        }
        $cases{$case}->();
    };
} else {
    subtest 'strict parser and global help' => \&parser_cases;
    subtest 'diagnostic authority precedes protected reads' => \&diagnostic_authorization_cases;
    subtest 'diagnostic output parameters' => \&diagnostic_destination_cases;
    subtest 'defensive diagnostic collector metadata shapes' => \&diagnostic_collector_shape_cases;
    subtest 'diagnostic encoding limits' => \&diagnostic_limit_cases;
    subtest 'read-only inspection' => \&inspect_cases;
    subtest 'site policy presence and path validation' => \&policy_path_cases;
    subtest 'packaged alias and client transport' => \&transport_cases;
    subtest 'native repository operations' => \&native_cases;
}
ok(!-e "$tmp/package-script-executed", 'no package installation script executed');
ok(!-e '/var/db/pkg', 'default package database remains absent');
done_testing();
