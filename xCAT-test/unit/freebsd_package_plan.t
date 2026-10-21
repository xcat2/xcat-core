#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use Fcntl qw(O_RDWR O_CREAT LOCK_EX LOCK_NB);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Select;
use JSON;
use POSIX qw(_exit mkfifo);
use Test::More;
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
plan(skip_all => 'Native package-plan tests require Linux execution') unless $^O eq 'linux';
plan(skip_all => 'Native pkg database fixtures require container root') if $> != 0;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
    $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
    $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
    $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
}
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);

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

sub directory {
    return $fixture->new_directory();
}

sub clone_tree {
    my $source = shift;
    my $target = directory();
    command('/usr/bin/cp', '-a', "$source/.", $target);
    return $target;
}

sub rejects {
    my ($action, $description) = @_;
    my $ok = eval { $action->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    like($error, qr/(?:FreeBSD[ ]package[ ]plan|publication|import|repository)/ix,
        "$description reports a plan or source validation error");
    return;
}

sub identity {
    my ($repository, $name, $version, $origin) = @_;
    return { repository => $repository,
        identity => [$name, $version, $origin, 'FreeBSD:15:amd64'] };
}

sub base_identity {
    my $name = shift;
    return identity(0, $name, '15.1', "base/$name");
}

sub import_release {
    my ($source, $root) = @_;
    return xCAT::FreeBSDRepoImport::import_release($source, $root,
        tool => $tool, trust => { type => 'operator-trusted-release',
            digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} });
}

sub lines {
    my $bytes = shift;
    return [map { [split(/\t/x, $_, -1)] } split(/\n/x, $bytes)];
}

sub wire {
    my $records = shift;
    return join('', map { join("\t", @$_) . "\n" } @$records);
}

sub changed {
    my ($bytes, $mutate) = @_;
    my $records = lines($bytes);
    $mutate->($records);
    return wire($records);
}

sub plan_record {
    my ($records, $kind) = @_;
    my ($found) = grep { $_->[0] eq $kind } @$records;
    croak "No fixture $kind record" unless $found;
    return $found;
}

sub published_files {
    my $root = shift;
    my $path = "$root/freebsd15.1/x86_64/plans";
    return [] unless -d $path;
    opendir(my $dh, $path) or croak $!;
    my @entries = sort grep { $_ ne '.' && $_ ne '..' && $_ ne '.package-plan.lock' } readdir($dh);
    closedir($dh) or croak $!;
    return \@entries;
}

make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
$tool->{sha256} = sha256_hex(read_file($tool->{path}));
is(run_pkg('-v'), "2.8.2\n", 'fixtures use the pinned native pkg version');
ok(!-e '/var/db/pkg', 'default package database is absent before the fixture operations');
command('/usr/bin/openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', "$tmp/repo.key");
chmod(oct('0600'), "$tmp/repo.key") or croak $!;
command('/usr/bin/openssl', 'pkey', '-in', "$tmp/repo.key", '-pubout', '-out', "$tmp/repo.pub");

my $root = directory();
my $disc = import_release($fixture->release_tree(0), $root);
my $dvd = import_release($fixture->release_tree(1), $root);
my @definitions = (['test-dep'], ['test-app', deps => { 'test-dep' => { origin => 'misc/test-dep', version => '1' } }]);
my $signed_source = $fixture->repository(1, \@definitions);
make_path("$signed_source/Payloads");
rename("$signed_source/All/test-app-1.pkg", "$signed_source/Payloads/application.pkg") or croak $!;
symlink('../Payloads/application.pkg', "$signed_source/All/test-app-1.pkg") or croak $!;
my $nested_source = directory();
command('/usr/bin/cp', '-a', $signed_source, "$nested_source/FreeBSD:15:amd64");
symlink('FreeBSD:15:amd64', "$nested_source/freebsd:15:x86:64") or croak $!;
my $signed = xCAT::FreeBSDRepoImport::import_repository($nested_source, $root,
    tool => $tool, catalogue_prefix => 'FreeBSD:15:amd64',
    trust => { type => 'pubkey', path => "$tmp/repo.pub", sha256 => sha256_hex(read_file("$tmp/repo.pub")) });
my $resolver = { version => '2.8.2', sha256 => $tool->{sha256} };
$resolver->{library_digest} = $tool->{library_digest} if exists($tool->{library_digest});
my %base = (installroot => $root, resolver => $resolver,
    repositories => [{ publication => $disc->{path}, role => 'base' }], components => ['base'],
    applications => [], selected => [base_identity('FreeBSD-runtime'), base_identity('FreeBSD-kernel-generic')]);
my %dvd_options = (%base, repositories => [{ publication => $dvd->{path}, role => 'base' },
    { publication => $dvd->{path}, role => 'applications' }],
    selected => [@{$base{selected}}, identity(1, 'application', '1', 'misc/application')],
    applications => [identity(1, 'application', '1', 'misc/application')]);
my %supplement = (%base, repositories => [@{$base{repositories}},
    { publication => $signed->{path}, role => 'repository' }],
    selected => [@{$base{selected}}, identity(1, 'test-dep', '1', 'misc/test-dep'), identity(1, 'test-app', '1', 'misc/test-app')],
    applications => [identity(1, 'test-app', '1', 'misc/test-app')]);
my $base_wire = xCAT::FreeBSDPackagePlan::compose(%base);
my $dvd_wire = xCAT::FreeBSDPackagePlan::compose(%dvd_options);
my $signed_wire = xCAT::FreeBSDPackagePlan::compose(%supplement);

sub base_cases {
    my $plan = xCAT::FreeBSDPackagePlan::parse($base_wire);
    is_deeply($plan->{resolver}, $resolver, 'plan pins the exact native preparation executable and optional libraries');
    is_deeply($plan->{components}, ['base'], 'explicit native components are preserved');
    is_deeply($plan->{applications}, [], 'a base-only selection has no implicit application roots');
    is_deeply([map { $_->{name} } @{$plan->{packages}}],
        [qw(FreeBSD-kernel-generic FreeBSD-runtime)], 'package order is canonical rather than caller order');
    is_deeply([map { $_->{id} } @{$plan->{packages}}], [qw(p0 p1)], 'canonical package IDs follow native identity order');
    is(scalar(@{$plan->{packages}}), 2, 'imported but unselected packages are not added to the plan');
    is($plan->{repositories}[0]{publication}, $disc->{digest}, 'repository identity is the imported publication digest');
    is($plan->{repositories}[0]{role}, 'base', 'base role is independent of its publication identity');
    is($plan->{repositories}[0]{trust_type}, 'operator-trusted-release', 'release approval is not relabeled as signed trust');
    is(index($base_wire, $tmp), -1, 'canonical wire contains no temporary filesystem paths');
    is(xCAT::FreeBSDPackagePlan::compose(%base, selected => [reverse @{$base{selected}}]), $base_wire,
        'caller package ordering does not change the plan identity');
    my $empty = xCAT::FreeBSDPackagePlan::parse(xCAT::FreeBSDPackagePlan::compose(%base, components => []));
    is_deeply($empty->{components}, [], 'an explicit empty optional component selection remains distinct from missing input');
    my $without_libraries = xCAT::FreeBSDPackagePlan::parse(xCAT::FreeBSDPackagePlan::compose(%base,
        resolver => { version => '2.8.2', sha256 => $tool->{sha256} }));
    ok(!exists($without_libraries->{resolver}{library_digest}), 'static preparation executable has no invented library pin');
    my $files = $plan->{repositories}[0]{files};
    is_deeply([map { $_->{path} } @$files], [qw(base/data.pkg base/meta.conf base/packagesite.pkg)],
        'both catalogue views and repository metadata are pinned in path order');
    for my $file (@$files) {
        my $bytes = read_file("$disc->{path}/$file->{path}");
        is($file->{size}, length($bytes), "$file->{path} pin has the actual file size");
        is($file->{sha256}, sha256_hex($bytes), "$file->{path} pin has the actual byte digest");
    }
    for my $package (@{$plan->{packages}}) {
        my $bytes = read_file("$disc->{path}/$package->{path}");
        is($package->{size}, length($bytes), "$package->{name} pins the selected archive size");
        is($package->{sha256}, sha256_hex($bytes), "$package->{name} pins the selected archive bytes");
        is($package->{path}, "base/$package->{repopath}", "$package->{name} payload path includes the repository role");
        ok(length($package->{native_sum}), "$package->{name} retains the native catalogue checksum");
    }
    return;
}

sub application_cases {
    my $plan = xCAT::FreeBSDPackagePlan::parse($dvd_wire);
    is_deeply([map { $_->{publication} } @{$plan->{repositories}}], [$dvd->{digest}, $dvd->{digest}],
        'one DVD publication can provide two distinct repository roles');
    is_deeply([map { $_->{role} } @{$plan->{repositories}}], [qw(base applications)], 'DVD roles retain image order');
    is_deeply($plan->{applications}, ['p2'], 'application request names its selected package, not every DVD archive');
    is_deeply([map { $_->{name} } @{$plan->{packages}}], [qw(FreeBSD-kernel-generic FreeBSD-runtime application)],
        'DVD import does not install bootstrap or other unselected packages');
    is($plan->{packages}[2]{path}, 'applications/FreeBSD:15:amd64/All/Hashed/application-1.pkg',
        'DVD package points to its actual nested archive');
    my $later = xCAT::FreeBSDPackagePlan::parse(xCAT::FreeBSDPackagePlan::compose(%dvd_options,
        repositories => [@{$base{repositories}}, { publication => $dvd->{path}, role => 'applications' }]));
    is_deeply([map { $_->{publication} } @{$later->{repositories}}], [$disc->{digest}, $dvd->{digest}],
        'DVD applications attach to an independent base-only publication');
    $plan = xCAT::FreeBSDPackagePlan::parse($signed_wire);
    my $repo = $plan->{repositories}[1];
    is($repo->{prefix}, 'FreeBSD:15:amd64', 'explicit supplemental catalogue prefix is preserved');
    is($repo->{trust_type}, 'pubkey', 'supplemental repository retains native public-key trust');
    is($repo->{trust_digest}, sha256_hex(read_file("$tmp/repo.pub")), 'trust digest binds the actual public key');
    my ($key) = grep { $_->{kind} eq 'key' } @{$repo->{files}};
    is($key->{path}, 'repository.pub', 'supplemental key is anchored at the publication root');
    is($key->{sha256}, $repo->{trust_digest}, 'key file and trust record agree');
    is($key->{size}, length(read_file("$tmp/repo.pub")), 'key file byte count is pinned');
    is_deeply([map { $_->{path} } grep { $_->{kind} ne 'key' } @{$repo->{files}}],
        [qw(repository/FreeBSD:15:amd64/data.pkg repository/FreeBSD:15:amd64/meta.conf repository/FreeBSD:15:amd64/packagesite.pkg)],
        'supplemental metadata paths bind role and catalogue prefix');
    is_deeply([map { $_->{name} } @{$plan->{packages}}], [qw(FreeBSD-kernel-generic FreeBSD-runtime test-app test-dep)],
        'the caller-supplied dependency selection remains explicit');
    is_deeply($plan->{applications}, ['p2'], 'dependency does not become an explicit application root');
    is($plan->{packages}[2]{repopath}, 'All/test-app-1.pkg', 'logical archive path retains the native catalogue reference');
    is($plan->{packages}[2]{path}, 'repository/FreeBSD:15:amd64/Payloads/application.pkg',
        'physical archive path resolves the verified internal link under its role and prefix');
    my $both = xCAT::FreeBSDPackagePlan::parse(xCAT::FreeBSDPackagePlan::compose(%supplement,
        applications => [@{$supplement{selected}}[2, 3]]));
    is_deeply($both->{applications}, [qw(p3 p2)], 'explicit application order is retained after canonical package sorting');
    return;
}

sub composition_failure_cases {
    for my $field (qw(installroot repositories components applications selected resolver)) {
        my %bad = %base;
        delete($bad{$field});
        rejects(sub { xCAT::FreeBSDPackagePlan::compose(%bad) }, "missing $field is not defaulted");
    }
    for my $case (
        ['unknown option', { unexpected => 1 }],
        ['empty repository list', { repositories => [] }],
        ['non-base first role', { repositories => [{ publication => $dvd->{path}, role => 'applications' }] }],
        ['duplicate publication role', { repositories => [@{$base{repositories}}, @{$base{repositories}}] }],
        ['unavailable role', { repositories => [{ publication => $disc->{path}, role => 'base' }, { publication => $disc->{path}, role => 'applications' }] }],
        ['unimported source', { repositories => [{ publication => $signed_source, role => 'base' }] }],
        ['duplicate package identity', { selected => [$base{selected}[0], $base{selected}[0]] }],
        ['unknown selected package', { selected => [base_identity('FreeBSD-not-present')] }],
        ['wrong selected version', { selected => [identity(0, 'FreeBSD-runtime', '15.0', 'base/FreeBSD-runtime')] }],
        ['wrong selected ABI', { selected => [{ repository => 0, identity => ['FreeBSD-runtime', '15.1', 'base/FreeBSD-runtime', 'FreeBSD:16:amd64'] }] }],
        ['dangling repository index', { selected => [identity(1, 'FreeBSD-runtime', '15.1', 'base/FreeBSD-runtime')] }],
        ['noncanonical repository index', { selected => [{ identity => $base{selected}[0]{identity}, repository => '00' }] }],
        ['unselected application root', { applications => [base_identity('FreeBSD-set-base')] }],
        ['duplicate application root', { applications => [$base{selected}[0], $base{selected}[0]] }],
        ['duplicate component', { components => [qw(base base)] }],
        ['unsupported resolver', { resolver => { %$resolver, version => '2.6.2' } }],
        ['unpinned resolver', { resolver => { version => '2.8.2' } }],
        ['malformed resolver digest', { resolver => { %$resolver, sha256 => 'g' x 64 } }],
        ['malformed library digest', { resolver => { %$resolver, library_digest => '0' x 63 } }],
    ) {
        rejects(sub { xCAT::FreeBSDPackagePlan::compose(%base, %{$case->[1]}) }, $case->[0]);
    }
    rejects(sub { xCAT::FreeBSDPackagePlan::compose(%dvd_options, selected => [
        identity(0, 'pkg', '2.6.2_1', 'ports-mgmt/pkg'), identity(1, 'pkg', '2.6.2_1', 'ports-mgmt/pkg')], applications => []) },
        'two repository providers of the same package name require a prior native choice');
    rejects(sub { xCAT::FreeBSDPackagePlan::compose(%supplement,
        applications => [$supplement{applications}[0], $supplement{applications}[0]]) },
        'the same supplemental application root cannot appear twice');
    rejects(sub { xCAT::FreeBSDPackagePlan::compose(%base, applications => [$base{selected}[0]]) },
        'application selection cannot route a base package through the applications phase');
    for my $component ('', 'Base', 'a/b', 'a' x 65, [], {}) {
        rejects(sub { xCAT::FreeBSDPackagePlan::compose(%base, components => [$component]) },
            'malformed component is rejected before native component availability is considered');
    }
    return;
}

sub grammar_cases {
    for my $case (
        ['missing final newline', substr($signed_wire, 0, -1)],
        ['extra final newline', "$signed_wire\n"],
        ['CRLF records', do { my $value = $signed_wire; $value =~ s/\n/\r\n/gx; $value }],
        ['UTF-8 byte order mark', "\xef\xbb\xbf$signed_wire"],
        ['invalid UTF-8', changed($signed_wire, sub { plan_record($_[0], 'package')->[3] = "bad\xff" })],
        ['unknown record', "$signed_wire" . "unknown\tvalue\n"],
        ['duplicate format', changed($signed_wire, sub { unshift @{$_[0]}, [@{$_[0][0]}] })],
        ['unsupported target release', changed($signed_wire, sub { plan_record($_[0], 'target')->[1] = '15.0-RELEASE' })],
        ['unsupported target ABI', changed($signed_wire, sub { plan_record($_[0], 'target')->[2] = 'FreeBSD:15:arm64' })],
        ['unsupported target OSVERSION', changed($signed_wire, sub { plan_record($_[0], 'target')->[3] = '1500000' })],
        ['group reordering', changed($signed_wire, sub { my $first = shift @{$_[0]}; push @{$_[0]}, $first })],
        ['unknown repository reference', changed($signed_wire, sub { plan_record($_[0], 'package')->[2] = 'r9' })],
        ['unknown application reference', changed($signed_wire, sub { plan_record($_[0], 'application')->[1] = 'p99' })],
        ['nonsequential package ID', changed($signed_wire, sub { plan_record($_[0], 'package')->[1] = 'p01' })],
        ['nonsequential repository ID', changed($signed_wire, sub { plan_record($_[0], 'repository')->[1] = 'r01' })],
        ['duplicate package name', changed($signed_wire, sub { my @items = grep { $_->[0] eq 'package' } @{$_[0]}; $items[1][3] = $items[0][3] })],
        ['duplicate resolved archive', changed($signed_wire, sub { my @items = grep { $_->[0] eq 'package' } @{$_[0]}; $items[1][8] = $items[0][8] })],
        ['duplicate logical archive', changed($signed_wire, sub { my @items = grep { $_->[0] eq 'package' } @{$_[0]}; $items[1][7] = $items[0][7] })],
        ['incorrect package sort order', changed($signed_wire, sub { plan_record($_[0], 'package')->[3] = 'zzzz' })],
        ['missing catalogue view', changed($signed_wire, sub { @{$_[0]} = grep { !($_->[0] eq 'file' && $_->[3] eq 'base/data.pkg') } @{$_[0]} })],
        ['duplicate file', changed($signed_wire, sub { my $file = plan_record($_[0], 'file'); my $position = 0; ++$position while $_[0][$position] != $file; splice(@{$_[0]}, $position, 0, [@$file]) })],
        ['missing signed key', changed($signed_wire, sub { @{$_[0]} = grep { !($_->[0] eq 'file' && $_->[2] eq 'key') } @{$_[0]} })],
        ['key digest disagreement', changed($signed_wire, sub { my ($key) = grep { $_->[0] eq 'file' && $_->[2] eq 'key' } @{$_[0]}; $key->[5] = '0' x 64 })],
        ['unsafe payload path', changed($signed_wire, sub { plan_record($_[0], 'package')->[8] = '../outside.pkg' })],
        ['wrong payload role', changed($signed_wire, sub { plan_record($_[0], 'package')->[8] = 'applications/All/wrong.pkg' })],
        ['absolute catalogue archive', changed($signed_wire, sub { plan_record($_[0], 'package')->[7] = '/All/wrong.pkg' })],
        ['noncanonical size', changed($signed_wire, sub { plan_record($_[0], 'package')->[9] = '01' })],
        ['empty identity', changed($signed_wire, sub { plan_record($_[0], 'package')->[3] = '' })],
        ['identity control byte', changed($signed_wire, sub { plan_record($_[0], 'package')->[3] = "bad\x7f" })],
        ['oversized identity', changed($signed_wire, sub { plan_record($_[0], 'package')->[3] = 'A' x 1025 })],
        ['invalid native checksum', changed($signed_wire, sub { plan_record($_[0], 'package')->[11] = 'bad/sum' })],
    ) {
        rejects(sub { xCAT::FreeBSDPackagePlan::parse($case->[1]) }, "parse rejects $case->[0]");
    }
    for my $value (undef, [], {}) {
        rejects(sub { xCAT::FreeBSDPackagePlan::parse($value) }, 'parse rejects non-string input');
    }
    my $unicode = changed($base_wire, sub { plan_record($_[0], 'package')->[3] = encode_utf8("A\x{e9}") });
    my $decoded = xCAT::FreeBSDPackagePlan::parse($unicode);
    is($decoded->{packages}[0]{name}, "A\x{e9}", 'valid UTF-8 native identity remains opaque text');
    my $maximum = changed($base_wire, sub { plan_record($_[0], 'package')->[3] = 'A' x 1024 });
    is(length(xCAT::FreeBSDPackagePlan::parse($maximum)->{packages}[0]{name}), 1024,
        'native identity accepts its exact character bound');
    my $multibyte = changed($base_wire, sub { plan_record($_[0], 'package')->[3] = encode_utf8('A' . ("\x{e9}" x 1023)) });
    is(length(xCAT::FreeBSDPackagePlan::parse($multibyte)->{packages}[0]{name}), 1024,
        'native identity character bound does not silently become a smaller UTF-8 byte bound');
    return;
}

sub synthetic_selection {
    my $count = shift;
    my $original = lines($base_wire);
    my @records = grep { $_->[0] ne 'package' && $_->[0] ne 'component' } @$original;
    my $example = plan_record($original, 'package');
    for my $index (0 .. $count - 1) {
        my @package = @$example;
        $package[1] = "p$index";
        $package[3] = sprintf('P%05d', $index);
        $package[5] = 'A';
        $package[7] = "All/$package[3].pkg";
        $package[8] = "base/$package[7]";
        push @records, \@package;
    }
    return \@records;
}

sub synthetic_repositories {
    my $count = shift;
    my $original = lines($base_wire);
    my @header = grep { $_->[0] eq 'format' || $_->[0] eq 'target' || $_->[0] =~ /\Aresolver/x } @$original;
    my @repositories = (plan_record($original, 'repository'));
    my @files = grep { $_->[0] eq 'file' } @$original;
    my @base_files = @files;
    for my $index (1 .. $count - 1) {
        push @repositories, ['repository', "r$index", sprintf('%064x', $index), 'applications',
            'operator-trusted-release', $repositories[0][5]];
        for my $base_file (@base_files) {
            my @file = @$base_file;
            $file[1] = "r$index";
            $file[3] =~ s/\Abase\//applications\//x;
            push @files, \@file;
        }
    }
    return wire([@header, @repositories, @files,
        grep { $_->[0] eq 'component' || $_->[0] eq 'package' } @$original]);
}

sub bound_cases {
    is(scalar(@{xCAT::FreeBSDPackagePlan::parse(synthetic_repositories(32))->{repositories}}), 32,
        'parser accepts exactly 32 distinct repository roles');
    rejects(sub { xCAT::FreeBSDPackagePlan::parse(synthetic_repositories(33)) },
        'parser rejects a 33rd otherwise valid repository');
    my $records = synthetic_selection(8192);
    my $maximum_packages = wire($records);
    is(scalar(@{xCAT::FreeBSDPackagePlan::parse($maximum_packages)->{packages}}), 8192,
        'parser accepts exactly 8192 structurally valid selected packages');
    rejects(sub { xCAT::FreeBSDPackagePlan::parse(wire(synthetic_selection(8193))) },
        'parser rejects 8193 otherwise valid selected packages');
    my @header = grep { $_->[0] ne 'package' } @$records;
    my @packages = grep { $_->[0] eq 'package' } @$records;
    my $count = 16384 - @header - @packages;
    my @components = map { ['component', sprintf('c%05d', $_)] } 0 .. $count - 1;
    my $maximum_records = wire([@header, @components, @packages]);
    is(scalar(@{xCAT::FreeBSDPackagePlan::parse($maximum_records)->{components}}), $count,
        'parser accepts exactly 16384 canonical records');
    rejects(sub { xCAT::FreeBSDPackagePlan::parse(wire([@header, @components,
        ['component', 'overflow'], @packages])) }, 'parser rejects the 16385th canonical record');
    my $remaining = 8388608 - length($maximum_packages);
    for my $package (@packages) {
        my $added = $remaining < 1023 ? $remaining : 1023;
        $package->[5] .= 'A' x $added;
        $remaining -= $added;
        last unless $remaining;
    }
    is($remaining, 0, 'byte-bound fixture fits within independent identity bounds');
    my $maximum_bytes = wire([@header, @packages]);
    is(length($maximum_bytes), 8388608, 'byte-bound fixture is exactly 8 MiB');
    is(scalar(@{xCAT::FreeBSDPackagePlan::parse($maximum_bytes)->{packages}}), 8192,
        'parser accepts a canonical plan at exactly 8 MiB');
    my ($room) = grep { length($_->[5]) < 1024 } @packages;
    $room->[5] .= 'A';
    my $overflow = wire([@header, @packages]);
    is(length($overflow), 8388609, 'overflow changes only the total byte count limit');
    rejects(sub { xCAT::FreeBSDPackagePlan::parse($overflow) }, 'parser rejects the first byte beyond 8 MiB');
    for my $case (
        ['native checksum', 11, 'A' x 256, 'A' x 257],
        ['package archive size', 9, '17179869184', '17179869185'],
    ) {
        my $accepted = changed($base_wire, sub { plan_record($_[0], 'package')->[$case->[1]] = $case->[2] });
        ok(xCAT::FreeBSDPackagePlan::parse($accepted), "parser accepts the exact $case->[0] bound");
        my $rejected = changed($base_wire, sub { plan_record($_[0], 'package')->[$case->[1]] = $case->[3] });
        rejects(sub { xCAT::FreeBSDPackagePlan::parse($rejected) }, "parser rejects $case->[0] overflow");
    }
    for my $case (['meta', 65536], ['catalogue', 67108864], ['key', 1048576]) {
        my $accepted = changed($signed_wire, sub {
            my ($file) = grep { $_->[0] eq 'file' && $_->[2] eq $case->[0] } @{$_[0]};
            $file->[4] = $case->[1];
        });
        ok(xCAT::FreeBSDPackagePlan::parse($accepted), "parser accepts the exact $case->[0] byte-count bound");
        my $rejected = changed($accepted, sub {
            my ($file) = grep { $_->[0] eq 'file' && $_->[2] eq $case->[0] } @{$_[0]};
            ++$file->[4];
        });
        rejects(sub { xCAT::FreeBSDPackagePlan::parse($rejected) }, "parser rejects $case->[0] byte-count overflow");
    }
    my $long_component = changed($base_wire, sub { plan_record($_[0], 'component')->[1] = 'a' x 64 });
    ok(xCAT::FreeBSDPackagePlan::parse($long_component), 'component names accept exactly 64 characters');
    return;
}

sub relocated_references {
    my ($references, $from, $to) = @_;
    my @relocated;
    for my $reference (@$references) {
        my %entry = %$reference;
        $entry{publication} =~ s/^\Q$from\E/$to/x;
        push @relocated, \%entry;
    }
    return \@relocated;
}

sub publication_cases {
    my $published = xCAT::FreeBSDPackagePlan::publish($signed_wire, $root);
    my $digest = sha256_hex($signed_wire);
    my $relative = "freebsd15.1/x86_64/plans/$digest.plan";
    is_deeply($published, { digest => $digest, relative => $relative, path => "$root/$relative", reused => 0 },
        'publication identity hashes only the exact wire bytes');
    is(read_file($published->{path}), $signed_wire, 'published bytes equal the complete composed plan');
    my @before = stat($published->{path});
    is($before[2] & oct('7777'), oct('0444'), 'published plan is read-only');
    is($before[3], 1, 'published plan has no retained staging hard link');
    is($before[4], $>, 'published plan belongs to the caller');
    ok($before[9] > 0, 'published plan has a positive modification time');
    my $again = xCAT::FreeBSDPackagePlan::publish($signed_wire, $root);
    is($again->{reused}, 1, 'same bytes and sources reuse the publication');
    my @after = stat($published->{path});
    is_deeply([@after[0, 1, 2, 3, 4, 9, 10]], [@before[0, 1, 2, 3, 4, 9, 10]],
        'reuse preserves the original inode and operational metadata');
    my $inspected = xCAT::FreeBSDPackagePlan::inspect($published->{path}, $root);
    is_deeply($inspected, { digest => $digest, relative => $relative, path => $published->{path},
        plan => xCAT::FreeBSDPackagePlan::parse($signed_wire) }, 'readback returns the verified plan without publication mutation');
    my $relocated = clone_tree($root);
    unlink("$relocated/freebsd15.1/x86_64/plans/.package-plan.lock") or croak $!;
    is(xCAT::FreeBSDPackagePlan::inspect("$relocated/$relative", $relocated)->{digest}, $digest,
        'installation-root relocation preserves plan identity and source binding');
    ok(!-e "$relocated/freebsd15.1/x86_64/plans/.package-plan.lock", 'readback creates no publication lock');
    my $repositories = relocated_references($supplement{repositories}, $root, $relocated);
    is(xCAT::FreeBSDPackagePlan::compose(%supplement, installroot => $relocated, repositories => $repositories), $signed_wire,
        'composition is independent of the imported installation-root pathname');
    is_deeply(published_files($root), ["$digest.plan"], 'publication leaves no staging file or extra persistent artifact');
    return;
}

sub source_binding_cases {
    for my $case (
        ['archive SHA', sub { plan_record($_[0], 'package')->[10] = '0' x 64 }],
        ['archive size', sub { ++plan_record($_[0], 'package')->[9] }],
        ['native checksum', sub { plan_record($_[0], 'package')->[11] = '0' x 64 }],
        ['selected version', sub { plan_record($_[0], 'package')->[4] = '99' }],
        ['catalogue SHA', sub { plan_record($_[0], 'file')->[5] = '0' x 64 }],
        ['catalogue size', sub { ++plan_record($_[0], 'file')->[4] }],
        ['release trust digest', sub { plan_record($_[0], 'repository')->[5] = '0' x 64 }],
        ['publication identity', sub { plan_record($_[0], 'repository')->[2] = '0' x 64 }],
    ) {
        my $bytes = changed($base_wire, $case->[1]);
        ok(xCAT::FreeBSDPackagePlan::parse($bytes), "$case->[0] mutation is structurally valid");
        my $destination = clone_tree($root);
        my $before = published_files($destination);
        rejects(sub { xCAT::FreeBSDPackagePlan::publish($bytes, $destination) }, "publication rejects a false $case->[0] pin");
        is_deeply(published_files($destination), $before, "$case->[0] failure leaves no publication or stage");
        my $path = "$destination/freebsd15.1/x86_64/plans/" . sha256_hex($bytes) . '.plan';
        write_file($path, $bytes);
        chmod(oct('0444'), $path) or croak $!;
        rejects(sub { xCAT::FreeBSDPackagePlan::inspect($path, $destination) },
            "readback rejects a false $case->[0] despite its matching outer hash and path");
    }
    my $false_key = changed($signed_wire, sub {
        my ($repository) = grep { $_->[0] eq 'repository' && $_->[1] eq 'r1' } @{$_[0]};
        my ($key) = grep { $_->[0] eq 'file' && $_->[2] eq 'key' } @{$_[0]};
        $repository->[5] = '0' x 64;
        $key->[5] = '0' x 64;
    });
    ok(xCAT::FreeBSDPackagePlan::parse($false_key), 'matching false key and trust pins are structurally consistent');
    rejects(sub { xCAT::FreeBSDPackagePlan::publish($false_key, $root) },
        'matching false key and trust pins cannot replace the actual imported public key');
    return;
}

sub changed_import_cases {
    for my $case (
        ['payload', "base/All/FreeBSD-runtime-15.1.pkg", 'replace'],
        ['primary catalogue', 'base/data.pkg', 'replace'],
        ['fallback catalogue', 'base/packagesite.pkg', 'remove'],
        ['metadata', 'base/meta.conf', 'replace'],
        ['public key', 'repository.pub', 'replace'],
    ) {
        my $destination = clone_tree($root);
        my $import = $case->[1] eq 'repository.pub' ? $signed : $disc;
        my $path = "$destination/freebsd15.1/x86_64/repositories/$import->{digest}/$case->[1]";
        if ($case->[2] eq 'remove') {
            unlink($path) or croak $!;
        } else {
            write_file($path, 'changed imported bytes');
        }
        my $repositories = relocated_references($supplement{repositories}, $root, $destination);
        rejects(sub { xCAT::FreeBSDPackagePlan::compose(%supplement, installroot => $destination, repositories => $repositories) },
            "composition rejects changed $case->[0]");
        rejects(sub { xCAT::FreeBSDPackagePlan::publish($signed_wire, $destination) },
            "publication reuse rejects changed $case->[0]");
        my $plan_path = "$destination/freebsd15.1/x86_64/plans/" . sha256_hex($signed_wire) . '.plan';
        rejects(sub { xCAT::FreeBSDPackagePlan::inspect($plan_path, $destination) },
            "readback rejects changed $case->[0]");
        is(read_file($plan_path), $signed_wire, "$case->[0] rejection does not rewrite the existing plan");
    }
    return;
}

sub plan_metadata_cases {
    for my $case (
        ['changed bytes', sub { write_file($_[0], $base_wire) }],
        ['symlink', sub { rename($_[0], "$_[0].actual") or croak $!; symlink("$_[0].actual", $_[0]) or croak $! }],
        ['hard link', sub { link($_[0], directory() . '/linked') or croak $! }],
        ['FIFO', sub { unlink($_[0]) or croak $!; mkfifo($_[0], oct('0444')) == 0 or croak $! }],
        ['directory', sub { unlink($_[0]) or croak $!; mkdir($_[0], oct('0555')) or croak $! }],
        ['writable file', sub { chmod(oct('0644'), $_[0]) or croak $! }],
        ['foreign owner', sub { chown(65534, 65534, $_[0]) == 1 or croak $! }],
        ['zero timestamp', sub { utime(0, 0, $_[0]) == 1 or croak $! }],
        ['oversized file', sub { truncate($_[0], 8388609) or croak $! }],
    ) {
        my $destination = clone_tree($root);
        my $path = "$destination/freebsd15.1/x86_64/plans/" . sha256_hex($signed_wire) . '.plan';
        $case->[1]->($path);
        rejects(sub { xCAT::FreeBSDPackagePlan::inspect($path, $destination) }, "readback rejects $case->[0]");
        rejects(sub { xCAT::FreeBSDPackagePlan::publish($signed_wire, $destination) },
            "publication does not overwrite an existing $case->[0] destination");
    }
    for my $path (undef, [], 'relative', "$root/freebsd15.1/x86_64/plans/" . ('0' x 64) . '.plan',
        "$root/freebsd15.1/x86_64/plans/../plans/" . sha256_hex($signed_wire) . '.plan') {
        rejects(sub { xCAT::FreeBSDPackagePlan::inspect($path, $root) }, 'readback rejects a missing, malformed or wrong plan path');
    }
    my $empty = directory();
    rejects(sub { xCAT::FreeBSDPackagePlan::inspect("$empty/freebsd15.1/x86_64/plans/" . sha256_hex($signed_wire) . '.plan', $empty) },
        'readback does not create missing publication parents');
    ok(!-e "$empty/freebsd15.1", 'failed readback leaves an empty installation root');
    return;
}

sub busy_lock_cases {
    my $parent = "$root/freebsd15.1/x86_64/plans";
    sysopen(my $lock, "$parent/.package-plan.lock", O_RDWR | O_CREAT, oct('0600')) or croak $!;
    flock($lock, LOCK_EX | LOCK_NB) or croak $!;
    my $path = "$parent/" . sha256_hex($signed_wire) . '.plan';
    my @before = stat($path);
    pipe(my $reader, my $writer) or croak $!;
    my $pid = fork();
    croak $! unless defined($pid);
    if (!$pid) {
        alarm(30);
        close($reader) or _exit(2);
        close($lock) or _exit(2);
        syswrite($writer, 'r', 1) == 1 or _exit(2);
        my $result;
        my $ok = eval { $result = xCAT::FreeBSDPackagePlan::publish($signed_wire, $root); 1; };
        my $error = $@;
        write_file("$tmp/waiting-writer.json", $json->encode({ ok => $ok ? 1 : 0, result => $result, error => $error }));
        syswrite($writer, 'd', 1) == 1 or _exit(2);
        close($writer) or _exit(2);
        _exit(0);
    }
    close($writer) or croak $!;
    my $ready = IO::Select->new($reader);
    croak 'Publication child did not start' unless $ready->can_read(10);
    is(sysread($reader, my $token, 1), 1, 'concurrent request signals readiness');
    is($token, 'r', 'request is about to publish');
    ok(!$ready->can_read(2), 'publication waits while another caller owns the lock');
    close($lock) or croak $!;
    is(waitpid($pid, 0), $pid, 'waiting publisher is reaped');
    is($?, 0, 'waiting publisher completes normally');
    close($reader) or croak $!;
    my $result = $json->decode(read_file("$tmp/waiting-writer.json"));
    ok($result->{ok}, 'contending request succeeds without a caller retry') or diag($result->{error});
    is($result->{result}{reused}, 1, 'waiting publisher verifies and reuses the plan');
    is(xCAT::FreeBSDPackagePlan::publish($signed_wire, $root)->{reused}, 1,
        'a later request also reuses the plan');
    my @after = stat($path);
    is_deeply([@after[0, 1, 3, 9, 10]], [@before[0, 1, 3, 9, 10]],
        'waiting and reuse preserve the same immutable inode');
    return;
}

sub lock_metadata_cases {
    for my $case (
        ['symlink', sub { my $other = directory() . '/lock'; write_file($other, '');
            chmod(oct('0600'), $other) or croak $!; symlink($other, $_[0]) or croak $! }],
        ['hard link', sub { my $other = directory() . '/lock'; write_file($other, '');
            chmod(oct('0600'), $other) or croak $!; link($other, $_[0]) or croak $! }],
        ['wrong permissions', sub { write_file($_[0], ''); chmod(oct('0644'), $_[0]) or croak $! }],
        ['nonempty content', sub { write_file($_[0], 'unexpected'); chmod(oct('0600'), $_[0]) or croak $! }],
        ['foreign owner', sub { write_file($_[0], ''); chmod(oct('0600'), $_[0]) or croak $!;
            chown(65534, 65534, $_[0]) == 1 or croak $! }],
        ['FIFO', sub { mkfifo($_[0], oct('0600')) == 0 or croak $! }],
    ) {
        my $destination = clone_tree($root);
        my $parent = "$destination/freebsd15.1/x86_64/plans";
        my $lock_path = "$parent/.package-plan.lock";
        unlink($lock_path) or croak $!;
        $case->[1]->($lock_path);
        rejects(sub { xCAT::FreeBSDPackagePlan::publish($signed_wire, $destination) },
            "publication rejects lock with $case->[0]");
        my $path = "$parent/" . sha256_hex($signed_wire) . '.plan';
        is(read_file($path), $signed_wire, "$case->[0] lock preserves the existing immutable plan");
        is_deeply(published_files($destination), [sha256_hex($signed_wire) . '.plan'],
            "$case->[0] lock creates no staging or additional plan file");
    }
    return;
}

sub concurrent_writer {
    my ($index, $destination, $reader, $writer) = @_;
    close($writer) or _exit(2);
    my $ready = sysread($reader, my $token, 1);
    _exit(3) unless defined($ready) && $ready == 1;
    my $result;
    my $ok = eval { $result = xCAT::FreeBSDPackagePlan::publish($signed_wire, $destination); 1; };
    my $error = $@;
    write_file("$tmp/writer-$index.json", $json->encode({ ok => $ok ? 1 : 0, result => $result, error => $error }));
    return _exit(0);
}

sub concurrency_cases {
    my $destination = clone_tree($root);
    my $path = "$destination/freebsd15.1/x86_64/plans/" . sha256_hex($signed_wire) . '.plan';
    unlink($path) or croak $!;
    pipe(my $reader, my $writer) or croak $!;
    my @children;
    for my $index (0 .. 4) {
        my $pid = fork();
        croak $! unless defined($pid);
        concurrent_writer($index, $destination, $reader, $writer) unless $pid;
        push @children, $pid;
    }
    close($reader) or croak $!;
    print {$writer} 'xxxxx' or croak $!;
    close($writer) or croak $!;
    for my $pid (@children) {
        is(waitpid($pid, 0), $pid, 'concurrent writer is reaped');
        is($?, 0, 'concurrent writer returns its complete result');
    }
    my @results = map { $json->decode(read_file("$tmp/writer-$_.json")) } (0 .. 4);
    is(scalar(grep { $_->{ok} } @results), 5, 'all five concurrent requests complete publication');
    for my $result (@results) {
        is($result->{error}, '', 'concurrent request reports no publication error');
    }
    is(scalar(grep { $_->{ok} && !$_->{result}{reused} } @results), 1, 'only one writer creates the final inode');
    is(read_file($path), $signed_wire, 'concurrent publication retains complete exact bytes');
    my @state = stat($path);
    is($state[3], 1, 'concurrent writers remove all temporary hard links');
    is($state[2] & oct('7777'), oct('0444'), 'concurrent result retains immutable permissions');
    is(xCAT::FreeBSDPackagePlan::inspect($path, $destination)->{digest}, sha256_hex($signed_wire),
        'concurrent result verifies against the complete imported sources');
    is(xCAT::FreeBSDPackagePlan::publish($signed_wire, $destination)->{reused}, 1,
        'an explicit retry after both writers finish reuses the verified result');
    my @retried = stat($path);
    is_deeply([@retried[0, 1, 3, 9, 10]], [@state[0, 1, 3, 9, 10]],
        'retry retains the winning writer inode and its single link');
    is_deeply(published_files($destination), [sha256_hex($signed_wire) . '.plan'], 'concurrent writers leave no stage artifacts');
    return;
}

sub archive_staging_cases {
    my $destination = directory();
    chmod(oct('0700'), $destination) == 1 or croak $!;
    my $result = xCAT::FreeBSDPackagePlan::stage_archives($signed_wire, $root, $destination);
    my $plan = xCAT::FreeBSDPackagePlan::parse($signed_wire);
    my $total = 0;
    for my $package (@{$plan->{packages}}) {
        my $path = "$destination/$package->{id}.pkg";
        my $bytes = read_file($path);
        is(length($bytes), $package->{size}, "$package->{name} archive size is retained");
        is(sha256_hex($bytes), $package->{sha256}, "$package->{name} archive bytes match the bound plan");
        my @state = lstat($path);
        is_deeply([@state[3, 4], $state[2] & oct('7777')], [1, $>, oct('0400')],
            "$package->{name} archive is a private independent file");
        $total += $package->{size};
    }
    is_deeply($result, { packages => scalar(@{$plan->{packages}}), bytes => $total,
        plan_sha256 => sha256_hex($signed_wire) }, 'staging reports the complete pinned payload');
    is((stat($destination))[2] & oct('7777'), oct('0500'), 'completed archive directory is read-only and private');
    rejects(sub { xCAT::FreeBSDPackagePlan::stage_archives($signed_wire, $root, $destination) },
        'a second staging attempt cannot overwrite an admitted payload');
    my $occupied = directory();
    chmod(oct('0700'), $occupied) == 1 or croak $!;
    write_file("$occupied/sentinel", 'preserved');
    rejects(sub { xCAT::FreeBSDPackagePlan::stage_archives($signed_wire, $root, $occupied) },
        'unrelated staging content prevents writes');
    is(read_file("$occupied/sentinel"), 'preserved', 'unrelated staging content is preserved');
    my $link = "$tmp/archive-link";
    symlink($occupied, $link) or croak $!;
    rejects(sub { xCAT::FreeBSDPackagePlan::stage_archives($signed_wire, $root, $link) },
        'symlinked staging directories are rejected');
    my $empty = directory();
    chmod(oct('0700'), $empty) == 1 or croak $!;
    my $false = changed($signed_wire, sub { plan_record($_[0], 'package')->[10] = '0' x 64 });
    rejects(sub { xCAT::FreeBSDPackagePlan::stage_archives($false, $root, $empty) },
        'structurally valid forged archive identities fail repository rebinding');
    opendir(my $handle, $empty) or croak $!;
    my @remaining = grep { $_ ne '.' && $_ ne '..' } readdir($handle);
    closedir($handle) or croak $!;
    is_deeply(\@remaining, [], 'failed source binding copies no archive');
    my $copy = "$empty/copy";
    my $source = "$destination/p0.pkg";
    my $ok = eval { xCAT::FreeBSDRepoImport::copy_verified_file($source, $copy, -s $source, '0' x 64); 1; };
    my $error = $@;
    ok(!$ok, 'verified copying rejects different archive bytes');
    like($error, qr/changed during copying/, 'copy failure identifies the byte-integrity error');
    return;
}

sub manifest_staging_cases {
    my $archives = directory();
    chmod(oct('0700'), $archives) == 1 or croak $!;
    xCAT::FreeBSDPackagePlan::stage_archives($signed_wire, $root, $archives);
    my $destination = directory();
    chmod(oct('0700'), $destination) == 1 or croak $!;
    my $result = eval { xCAT::FreeBSDPackagePlan::stage_manifests($signed_wire, $root, $destination); };
    if (!ok($result, 'verification stages full manifests from the verified archive set')) {
        diag($@);
        return;
    }
    my $request = "format\txcat-freebsd-local-manifests-1\nplan\t" . sha256_hex($signed_wire) . "\n";
    my ($total, $archive_bytes, $count) = (0, 0, 0);
    for my $row (grep { /\Apackage\t/x } split(/\n/x, $signed_wire)) {
        my @fields = split(/\t/x, $row);
        my $id = $fields[1];
        my $expected = command('/usr/bin/tar', '-xOf', "$archives/$id.pkg", '+MANIFEST');
        is(read_file("$destination/$id.manifest"), $expected, "$id preserves the complete native manifest bytes");
        ok(!-e "$destination/$id.pkg", "$id verification retains no package payload");
        my @state = lstat("$destination/$id.manifest");
        is_deeply([@state[3, 4], $state[2] & oct('7777')], [1, $>, oct('0400')],
            "$id manifest is a private independent file");
        $request .= join("\t", $row, length($expected), sha256_hex($expected)) . "\n";
        $total += length($expected);
        $archive_bytes += $fields[9];
        ++$count;
    }
    is_deeply($result, { packages => $count, bytes => $total, archive_bytes => $archive_bytes,
        plan_sha256 => sha256_hex($signed_wire), request => $request },
        'request binds original archive provenance and the exact full manifests');
    is((stat($destination))[2] & oct('7777'), oct('0500'), 'manifest directory is sealed');
    rejects(sub { xCAT::FreeBSDPackagePlan::stage_manifests($signed_wire, $root, $destination) },
        'manifest staging cannot overwrite existing evidence');
    my $empty = directory();
    chmod(oct('0700'), $empty) == 1 or croak $!;
    my $false = changed($signed_wire, sub { plan_record($_[0], 'package')->[10] = '0' x 64 });
    rejects(sub { xCAT::FreeBSDPackagePlan::stage_manifests($false, $root, $empty) },
        'manifest staging still requires verified original archive provenance');
    is_deeply([glob("$empty/*")], [], 'failed source binding emits no manifests');
    return;
}

subtest 'base selection and canonical source pins' => \&base_cases;
subtest 'DVD, later application attachment and signed nested repositories' => \&application_cases;
subtest 'composition rejects incomplete or ambiguous selections' => \&composition_failure_cases;
subtest 'wire grammar rejects noncanonical or cross-record contradictions' => \&grammar_cases;
subtest 'finite plan bounds accept the edge and reject overflow' => \&bound_cases;
subtest 'immutable publication, reuse and root relocation' => \&publication_cases;
subtest 'structural parsing cannot substitute for source rebinding' => \&source_binding_cases;
subtest 'changed imports prevent composition, publication and readback' => \&changed_import_cases;
subtest 'plan pathname and operational metadata are verified' => \&plan_metadata_cases;
subtest 'a held publication lock waits without a caller retry' => \&busy_lock_cases;
subtest 'malformed publication locks cannot authorize writes' => \&lock_metadata_cases;
subtest 'concurrent writers publish one complete immutable plan' => \&concurrency_cases;
subtest 'stage private package archives from the verified plan' => \&archive_staging_cases;
subtest 'stage full manifests for native verification without file payload' => \&manifest_staging_cases;
ok(!-e "$tmp/package-script-executed", 'neither repository inspection nor plan preparation runs package scripts');
ok(!-e '/var/db/pkg', 'all native fixture and plan operations leave the default package database absent');
done_testing();
