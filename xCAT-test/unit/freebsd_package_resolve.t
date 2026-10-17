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
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_SOLVER to the native resolver executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_SOLVER});
plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_LIBDIR to the pinned native library directory')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
plan(skip_all => 'Native resolver fixtures require Linux execution') unless $^O eq 'linux';
plan(skip_all => 'Native resolver database fixtures require container root') if $> != 0;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
my $solver = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_SOLVER}) };
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

sub rejects {
    my ($action, $pattern, $description) = @_;
    my $ok = eval { $action->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    like($error, $pattern, "$description diagnostic");
    return $error;
}

sub dependency {
    my ($name, $version, $origin) = @_;
    return { $name => { version => $version, origin => $origin } };
}

sub package_names {
    my $plan = shift;
    return [sort map { $_->{name} } @{$plan->{packages}}];
}

sub application_names {
    my $plan = shift;
    my %packages = map { $_->{id} => $_->{name} } @{$plan->{packages}};
    return [map { $packages{$_} } @{$plan->{applications}}];
}

make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false,
    PKG_TRIGGERS_ENABLE => JSON::false, HANDLE_RC_SCRIPTS => JSON::false, SYSLOG => JSON::false }));
$tool->{sha256} = sha256_hex(read_file($tool->{path}));
$solver->{sha256} = sha256_hex(read_file($solver->{path}));
is(run_pkg('-v'), "2.8.2\n", 'fixtures use the pinned native pkg version');
ok(!-e '/var/db/pkg' && !-l '/var/db/pkg', 'default package database is absent before resolver fixtures');
command('/usr/bin/openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', "$tmp/repo.key");
chmod(oct('0600'), "$tmp/repo.key") or croak $!;
command('/usr/bin/openssl', 'pkey', '-in', "$tmp/repo.key", '-pubout', '-out', "$tmp/repo.pub");

my @base_definitions;
for my $name (qw(FreeBSD-runtime FreeBSD-base-runtime FreeBSD-kernel-generic
        FreeBSD-set-minimal FreeBSD-set-base FreeBSD-unused FreeBSD-ssh FreeBSD-bsdconfig)) {
    my %options = (version => '15.1', origin => "base/$name",
        annotations => { FreeBSD_version => '1501000' });
    $options{deps} = dependency('FreeBSD-runtime', '15.1', 'base/FreeBSD-runtime')
      if $name eq 'FreeBSD-set-minimal';
    $options{deps} = dependency('FreeBSD-base-runtime', '15.1', 'base/FreeBSD-base-runtime')
      if $name eq 'FreeBSD-set-base';
    push @base_definitions, [$name, %options];
}
push @base_definitions, ['pkg', version => '2.6.2_1', origin => 'ports-mgmt/pkg'];
my $native_base = $fixture->repository(0, \@base_definitions);
my $installroot = $fixture->new_directory();

sub imported_release {
    my $dvd = shift;
    my $source = $fixture->release_tree($dvd);
    command('/usr/bin/cp', '-a', "$native_base/.", "$source/usr/freebsd-packages/offline");
    return xCAT::FreeBSDRepoImport::import_release($source, $installroot, tool => $tool,
        trust => { type => 'operator-trusted-release',
            digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} });
}

sub imported_repository {
    my ($definitions, $signed, $nested, $source) = @_;
    $source = $fixture->repository($signed, $definitions) unless defined($source);
    if ($nested) {
        my $outer = $fixture->new_directory();
        command('/usr/bin/cp', '-a', $source, "$outer/FreeBSD:15:amd64");
        symlink('FreeBSD:15:amd64', "$outer/freebsd:15:x86:64") or croak $!;
        $source = $outer;
    }
    my $trust = $signed
      ? { type => 'pubkey', path => "$tmp/repo.pub", sha256 => sha256_hex(read_file("$tmp/repo.pub")) }
      : { type => 'operator-trusted-tree', digest => xCAT::FreeBSDRepo::snapshot_tree($source)->{digest} };
    return xCAT::FreeBSDRepoImport::import_repository($source, $installroot, tool => $tool,
        catalogue_prefix => $nested ? 'FreeBSD:15:amd64' : '', trust => $trust);
}

my $disc = imported_release(0);
my $dvd = imported_release(1);
my $signed = imported_repository([
    ['resolve-dep'],
    ['resolve-app', deps => dependency('resolve-dep', '1', 'misc/resolve-dep')],
    ['resolve-unused'],
], 1, 1);
my $disc_before = xCAT::FreeBSDRepoImport::inspect_import($disc->{path}, $installroot);
my $dvd_before = xCAT::FreeBSDRepoImport::inspect_import($dvd->{path}, $installroot);
my $signed_before = xCAT::FreeBSDRepoImport::inspect_import($signed->{path}, $installroot);
my %base = (installroot => $installroot, repositories => [{ publication => $disc->{path}, role => 'base' }],
    components => ['base'], applications => [], tool => $tool, solver => $solver);
my @minimal_names = sort qw(FreeBSD-bsdconfig FreeBSD-kernel-generic FreeBSD-runtime FreeBSD-set-minimal FreeBSD-ssh pkg);
my @base_names = sort(@minimal_names, qw(FreeBSD-base-runtime FreeBSD-set-base));

sub resolve_plan {
    my %overrides = @_;
    my %options = (%base, %overrides);
    my $bytes = xCAT::FreeBSDPackagePlan::resolve(%options);
    return ($bytes, xCAT::FreeBSDPackagePlan::parse($bytes));
}

subtest 'native components select complete and limited base closures' => sub {
    my ($minimal_bytes, $minimal) = resolve_plan(components => []);
    is_deeply($minimal->{components}, [], 'explicit empty components are preserved');
    is_deeply(package_names($minimal), \@minimal_names, 'minimal includes the runtime closure, kernel, pkg, SSH and configuration tools');
    is_deeply($minimal->{applications}, [], 'base-only installation has no application roots');
    my ($bytes, $plan) = resolve_plan();
    is_deeply(package_names($plan), \@base_names, 'base adds its native set and dependency without unrelated archives');
    is_deeply($plan->{components}, ['base'], 'explicit base selection is retained');
    isnt($bytes, $minimal_bytes, 'empty and base selections have distinct wire identities');
    ok(!grep({ $_->{repository} ne 'r0' } @{$plan->{packages}}), 'all base jobs belong to the approved base role');
    is($plan->{resolver}{sha256}, $solver->{sha256}, 'plan pins the resolver helper rather than the catalogue client');
    is($plan->{resolver}{version}, '2.8.2', 'plan records the actual native resolver version');
    is_deeply($plan->{resolver}, { version => '2.8.2', sha256 => $solver->{sha256},
        exists($tool->{library_digest}) ? (library_digest => $tool->{library_digest}) : () },
        'resolver identity includes its exact private library pin when present');
    my ($again) = resolve_plan();
    is($again, $bytes, 'a repeated native resolution produces identical canonical bytes');
};

for my $required (qw(FreeBSD-ssh FreeBSD-bsdconfig)) {
    subtest "a managed-node plan requires $required before deployment" => sub {
        my @without = grep { $_->[0] ne $required } @base_definitions;
        my $repository = $fixture->repository(0, \@without);
        my $source = $fixture->release_tree(0);
        command('/usr/bin/cp', '-a', "$repository/.", "$source/usr/freebsd-packages/offline");
        my $import = xCAT::FreeBSDRepoImport::import_release($source, $installroot, tool => $tool,
            trust => {type => 'operator-trusted-release',
                digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest}});
        my $ok = eval { resolve_plan(components => [],
            repositories => [{publication => $import->{path}, role => 'base'}]); 1 };
        my $error = $@;
        ok(!$ok, "a minimal set without $required cannot provision a managed node");
        like($error, qr/Base[ ]repository[ ]requires[ ]the[ ]\Q$required\E[ ]package/x,
            'the missing required package is an explicit planning error');
    };
}

sub debug_component_cases {
    my @debug_names = qw(FreeBSD-set-minimal-dbg FreeBSD-set-base-dbg FreeBSD-kernel-generic-dbg);
    my @definitions = (@base_definitions, map {
        [$_, version => '15.1', origin => "base/$_", annotations => { FreeBSD_version => '1501000' }]
    } @debug_names, qw(FreeBSD-set-src FreeBSD-set-tests));
    my $repository = $fixture->repository(0, \@definitions);
    my $source = $fixture->release_tree(0);
    command('/usr/bin/cp', '-a', "$repository/.", "$source/usr/freebsd-packages/offline");
    my $publication = xCAT::FreeBSDRepoImport::import_release($source, $installroot, tool => $tool,
        trust => { type => 'operator-trusted-release',
            digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} });
    for my $components ([qw(base debug kernel-dbg)], [qw(base debug kernel-dbg base-dbg)],
        [qw(base src debug kernel-dbg)], [qw(base tests debug kernel-dbg)],
        [qw(base src tests debug kernel-dbg)]) {
        my $plan;
        my $resolved = eval {
            (undef, $plan) = resolve_plan(
                repositories => [{ publication => $publication->{path}, role => 'base' }],
                components => $components);
            1;
        };
        my $error = $@;
        if (!ok($resolved, 'native debug selection resolves: ' . join(' ', @$components))) {
            diag($error);
            next;
        }
        my @optional = map { "FreeBSD-set-$_" } grep { $_ eq 'src' || $_ eq 'tests' } @$components;
        is_deeply(package_names($plan), [sort(@base_names, @debug_names, @optional)],
            'debug sets and the debug kernel resolve without requiring doubled debug suffixes');
        is_deeply($plan->{components}, $components, 'explicit debug component order is retained');
        ok(!grep({ $_->{repository} ne 'r0' } @{$plan->{packages}}),
            'all debug packages retain the imported base provider');
    }
    return;
}

subtest 'available native debug components produce a complete package plan' => \&debug_component_cases;

subtest 'debug selection permits sets without debug counterparts' => sub {
    my $plan;
    my $resolved = eval { (undef, $plan) = resolve_plan(components => [qw(base debug)]); 1; };
    my $error = $@;
    if (!ok($resolved, 'native debug selection resolves when no debug sets are available')) {
        diag($error);
        done_testing();
        return;
    }
    is_deeply(package_names($plan), \@base_names, 'no unavailable debug packages are invented');
    is_deeply($plan->{components}, [qw(base debug)], 'the requested component selection is retained');
    done_testing();
};

subtest 'DVD and signed nested application closures remain separate from base' => sub {
    my (undef, $dvd_plan) = resolve_plan(repositories => [
        { publication => $dvd->{path}, role => 'base' },
        { publication => $dvd->{path}, role => 'applications' }], applications => ['application']);
    is_deeply(package_names($dvd_plan), [sort(@base_names, 'application')], 'DVD selects its requested application only');
    is($dvd_plan->{repositories}[0]{publication}, $dvd_plan->{repositories}[1]{publication},
        'base and applications can share a DVD publication');
    my ($bootstrap) = grep { $_->{name} eq 'pkg' } @{$dvd_plan->{packages}};
    is($bootstrap->{repository}, 'r0', 'DVD bootstrap duplication does not replace the base pkg provider');
    is_deeply(application_names($dvd_plan), ['application'], 'DVD root maps to its exact selected job');
    my (undef, $plan) = resolve_plan(repositories => [@{$base{repositories}},
        { publication => $signed->{path}, role => 'repository' }], applications => ['resolve-app']);
    is_deeply(package_names($plan), [sort(@base_names, qw(resolve-app resolve-dep))],
        'native resolver includes the application dependency and excludes an unrelated package');
    is_deeply(application_names($plan), ['resolve-app'], 'dependency is not mislabeled as an explicit root');
    is($plan->{repositories}[1]{trust_type}, 'pubkey', 'signed supplemental trust survives resolution');
    is($plan->{repositories}[1]{trust_digest}, sha256_hex(read_file("$tmp/repo.pub")), 'published signing key remains pinned');
    is($plan->{repositories}[1]{prefix}, 'FreeBSD:15:amd64', 'native catalogue prefix remains a transport property');
    my @application_jobs = grep { $_->{name} =~ /\Aresolve-/x } @{$plan->{packages}};
    ok(!grep({ $_->{repository} ne 'r1' } @application_jobs), 'application closure retains supplemental provenance');
    my (undef, $ordered) = resolve_plan(repositories => [@{$base{repositories}},
        { publication => $signed->{path}, role => 'repository' }], applications => [qw(resolve-app resolve-dep)]);
    is_deeply(application_names($ordered), [qw(resolve-app resolve-dep)], 'explicit root order survives native job ordering');
    is_deeply(package_names($ordered), package_names($plan), 'explicitly naming a shared dependency does not duplicate it');
};

sub precedence_cases {
    my @sources = map { imported_repository([
        ['resolve-overlap', version => $_, origin => 'misc/resolve-overlap'],
    ], 0, 0) } qw(1 2);
    for my $order ([0, 1], [1, 0]) {
        my ($first, $later) = @sources[@$order];
        my $version = $order->[0] + 1;
        my %options = (repositories => [@{$base{repositories}},
            { publication => $first->{path}, role => 'repository' },
            { publication => $later->{path}, role => 'repository' }],
            applications => ['resolve-overlap']);
        my ($bytes, $plan) = resolve_plan(%options);
        my @selected = grep { $_->{name} eq 'resolve-overlap' } @{$plan->{packages}};
        is(scalar(@selected), 1, 'overlapping application providers yield exactly one selected package');
        my $package = $selected[0] || {};
        is($package->{version}, "$version", 'the first application repository determines the selected version');
        is($package->{origin}, 'misc/resolve-overlap', 'the selected package retains the requested origin');
        is($package->{repository}, 'r1', 'the selected job belongs to the first application repository');
        is($plan->{repositories}[1]{publication}, $first->{digest}, 'the first provider retains its publication digest');
        my $path = "repository/All/resolve-overlap-$version.pkg";
        is($package->{path}, $path, 'the selected payload belongs to the first provider');
        is($package->{sha256}, sha256_hex(read_file("$first->{path}/$path")),
            'the selected checksum identifies the first provider archive');
        my ($again) = resolve_plan(%options);
        is($again, $bytes, 'repeating the same application repository order preserves exact plan bytes');
    }
    return;
}

subtest 'application repository order selects exact native package provenance' => \&precedence_cases;

sub unavailable_repository_cases {
    my @sources = map { imported_repository([
        ['resolve-unavailable', version => $_, origin => 'misc/resolve-unavailable'],
    ], 0, 0) } qw(1 2);
    my %options = (repositories => [@{$base{repositories}},
        map { { publication => $_->{path}, role => 'repository' } } @sources],
        applications => ['resolve-unavailable']);
    my (undef, $before) = resolve_plan(%options);
    my ($selected) = grep { $_->{name} eq 'resolve-unavailable' } @{$before->{packages}};
    is($selected->{repository}, 'r1', 'the available preferred repository supplies the application');
    is($selected->{version}, '1', 'the preferred repository supplies its older version');
    my $runner = \&xCAT::FreeBSDPkg::run_command;
    my $observation = "$tmp/unavailable-repository.json";
    my $bytes;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @arguments) = @_;
            return $runner->($argv, @arguments) unless @$argv == 6
              && $argv->[0] eq $solver->{path} && $argv->[3] eq 'resolve';
            my $config = $json->decode(read_file($argv->[2]));
            my $database = "$config->{PKG_DBDIR}/repos/r1";
            croak 'Preferred repository fixture is absent' if !-d $database || -l $database;
            my $digest = xCAT::FreeBSDRepo::snapshot_tree($database)->{digest};
            rename($database, "$database.retained") or croak $!;
            my $result;
            my $ran = eval { $result = $runner->($argv, @arguments); 1; };
            my $error = $@;
            rename("$database.retained", $database) or croak $!;
            croak $error unless $ran;
            croak 'Repository observation already exists' if -e $observation;
            write_file($observation, $json->encode({ result => $result,
                restored => xCAT::FreeBSDRepo::snapshot_tree($database)->{digest} eq $digest ? 1 : 0 }));
            return $result;
        };
        rejects(sub { ($bytes) = resolve_plan(%options) },
            qr/\ANative[ ]pkg[ ]dependency[ ]resolution[ ]failed\n\z/x,
            'an unavailable enabled repository prevents a plan');
    }
    ok(!defined($bytes), 'repository failure publishes no plan bytes');
    ok(-f $observation, 'the missing catalogue reaches one actual resolver invocation');
    my $native = -f $observation ? $json->decode(read_file($observation)) : {};
    is($native->{restored}, 1, 'the missing catalogue is restored unchanged');
    my $result = $native->{result} || {};
    is($result->{exitcode}, 1, 'the resolver fails instead of selecting the available lower-priority provider');
    is($result->{signal}, 0, 'the resolver reports the failure without a signal');
    is($result->{stdout}, '', 'the failed resolver emits no selected jobs');
    like($result->{stderr}, qr/Repository[ ]r1[ ]cannot[ ]be[ ]opened/x,
        'the resolver retains the actual repository-open diagnostic');
    my (undef, $after) = resolve_plan(%options);
    is_deeply($after, $before, 'the restored repository produces the same complete plan');
    return;
}

subtest 'unavailable enabled repositories cannot fall back to a different provider' => \&unavailable_repository_cases;

sub missing_selection_cases {
    my %missing = %base;
    delete($missing{components});
    rejects(sub { xCAT::FreeBSDPackagePlan::resolve(%missing) }, qr/component/ix, 'omitted components are not defaulted');
    for my $components (undef, 'base', ['not-a-component'], ['base', 'base'], ['Base']) {
        rejects(sub { resolve_plan(components => $components) }, qr/component/ix, 'invalid or duplicate native component is rejected');
    }
    rejects(sub { resolve_plan(components => ['src']) }, qr/(?:component|package|root|available)/ix,
        'a supported but unavailable component cannot produce an incomplete plan');
    rejects(sub { resolve_plan(components => ['kernel-dbg']) }, qr/Unavailable[ ]native[ ]base[ ]component/ix,
        'an absent debug kernel cannot produce an incomplete plan');
    rejects(sub { resolve_plan(applications => ['missing-root']) }, qr/(?:application|package|root|resolution)/ix,
        'missing application root is reported');
    rejects(sub { resolve_plan(applications => ['pkg']) }, qr/(?:application|base|bootstrap|owner)/ix,
        'application roots cannot request the base bootstrap');
    my $broken = imported_repository([
        ['broken-app', deps => dependency('missing-dependency', '1', 'misc/missing-dependency')],
    ], 0, 0);
    my $observed = omission_call('existing missing dependency', {
        repositories => [@{$base{repositories}}, { publication => $broken->{path}, role => 'repository' }],
        applications => ['broken-app'],
    }, undef);
    ok(!$observed->{ok}, 'missing transitive dependency fails native resolution');
    is($observed->{error}, "Native pkg dependency resolution failed\n",
        'missing transitive dependency has the exact helper failure diagnostic');
    is(scalar(@{$observed->{solves}}), 1, 'missing transitive dependency reaches the real native helper');
    ok(@{$observed->{solves}} == 1 && $observed->{solves}[0]{result}{exitcode}
        && !$observed->{solves}[0]{result}{signal}, 'missing transitive dependency causes a real nonzero helper exit');
    return;
}

subtest 'missing components, roots and dependencies fail without a plan' => \&missing_selection_cases;

subtest 'newer supplemental packages cannot take base or bootstrap ownership' => sub {
    for my $target (['pkg', 'ports-mgmt/pkg'], ['FreeBSD-runtime', 'base/FreeBSD-runtime']) {
        my ($target_name, $origin) = @$target;
        my $takeover = imported_repository([
            [$target_name, version => '99', origin => $origin, annotations => { FreeBSD_version => '1501000' }],
            ['takeover-app', deps => dependency($target_name, '99', $origin)],
        ], 0, 0);
        my %options = (repositories => [@{$base{repositories}},
            { publication => $takeover->{path}, role => 'repository' }], applications => ['takeover-app']);
        if ($target_name eq 'pkg') {
            my (undef, $plan) = resolve_plan(%options);
            my ($bootstrap) = grep { $_->{name} eq 'pkg' } @{$plan->{packages}};
            is($bootstrap->{repository}, 'r0', 'explicit bootstrap root retains the higher-priority base provider');
            is($bootstrap->{version}, '2.6.2_1', 'a newer supplemental bootstrap does not replace the requested base version');
            my $import = xCAT::FreeBSDRepoImport::inspect_import($takeover->{path}, $installroot);
            my ($replacement) = grep { $_->{name} eq 'pkg' } values %{$import->{source}{packages}};
            response_failure(['supplemental bootstrap selection', sub {
                my $response = shift;
                my ($job) = grep { $_->{package}{name} eq 'pkg' } @{$response->{jobs}};
                $job->{repository} = 'r1';
                $job->{package} = { map { $_ => $replacement->{$_} } qw(name version origin abi repopath sum pkgsize) };
            }, qr/non-base[ ]provider[ ]for[ ]a[ ]base[ ]package/ix], \&xCAT::FreeBSDPkg::run_command, \%options);
            next;
        }
        rejects(sub { resolve_plan(%options) },
            qr/(?:base|bootstrap|owner|provenance)/ix, "$target_name from a supplemental repository is rejected after solving");
    }
};

subtest 'base-origin application rejection does not disclose a selected name' => sub {
    my $name = 'protected-application-root-75c6a83e';
    my $repository = imported_repository([
        [$name, origin => 'base/private-component'],
    ], 0, 0);
    my $error = rejects(sub { resolve_plan(repositories => [@{$base{repositories}},
        { publication => $repository->{path}, role => 'repository' }], applications => [$name]) },
        qr/non-base[ ]provider[ ]for[ ]a[ ]base[ ]package/ix,
        'an application with a base origin is rejected after native resolution');
    unlike($error, qr/\Q$name\E/x, 'the rejected application name stays out of the diagnostic');
};

sub isolation_cases {
    rejects(sub { resolve_plan(solver => { %$solver, sha256 => '0' x 64 }) }, qr/(?:checksum|pin|resolver)/ix,
        'a helper checksum mismatch is rejected');
    rejects(sub { resolve_plan(tool => { %$tool, sha256 => '0' x 64 }) }, qr/(?:checksum|pin|tool)/ix,
        'a catalogue client checksum mismatch is rejected');
    my %unpinned = %$tool;
    delete @unpinned{qw(library_directory library_digest)};
    rejects(sub { resolve_plan(tool => \%unpinned) }, qr/planning[ ]requires[ ]a[ ]pinned[ ]library/ix,
        'planning cannot omit the native library pin');
    my $copied = "$tmp/copied-solver";
    write_file($copied, read_file($solver->{path}));
    chmod(oct('0722'), $copied) or croak $!;
    rejects(sub { resolve_plan(solver => { %$solver, path => $copied }) }, qr/Writable[ ]native[ ]path/x,
        'a correctly hashed writable resolver is rejected');
    chmod(oct('0700'), $copied) or croak $!;
    local $ENV{PKG_DBDIR} = "$tmp/forbidden-db";
    local $ENV{REPOS_DIR} = "$tmp/forbidden-repos";
    local $ENV{LD_PRELOAD} = '/must/not/load.so';
    local $ENV{http_proxy} = 'http://127.0.0.1:9';
    local $ENV{https_proxy} = 'http://127.0.0.1:9';
    local $ENV{TMPDIR} = "$tmp/uncreated:temporary";
    my (undef, $plan) = resolve_plan();
    is_deeply(package_names($plan), \@base_names, 'native preparation ignores inherited package, loader and proxy settings');
    ok(!-e "$tmp/forbidden-db" && !-e "$tmp/forbidden-repos", 'inherited package paths remain unused');
    ok(!-e "$tmp/uncreated:temporary", 'caller TMPDIR is not used for native repository URLs');
    return;
}

subtest 'resolver pins and inherited configuration cannot escape isolation' => \&isolation_cases;

sub resolver_root_state {
    my $path = shift;
    my @state = lstat($path);
    croak "Cannot inspect resolver root: $!" if !@state || !-d _ || -l _;
    opendir(my $dh, $path) or croak "Cannot open resolver root: $!";
    my @entries;
    {
        local $! = 0;
        @entries = readdir($dh);
        croak "Cannot read resolver root: $!" if $!;
    }
    @entries = sort grep { $_ ne '.' && $_ ne '..' } @entries;
    closedir($dh) or croak "Cannot close resolver root: $!";
    return { device => $state[0], inode => $state[1], uid => $state[4],
        gid => $state[5], mode => $state[2] & oct('07777'), entries => \@entries };
}

sub resolver_root_lifecycle {
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my (@roots, @plans);
    my $observed = 0;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @options) = @_;
            return $original_runner->($argv, @options)
              unless $argv->[0] eq $solver->{path} && $argv->[3] eq 'resolve';
            ++$observed;
            return $original_runner->($argv, @options)
              unless is(scalar(@$argv), 6, 'native solve receives an explicit root argument');
            my $root = $argv->[5];
            push @roots, $root;
            my $before = resolver_root_state($root);
            is($before->{uid}, 0, 'the caller creates a root-owned directory');
            is($before->{mode}, oct('0700'), 'the caller creates a private directory');
            is_deeply($before->{entries}, [], 'the caller passes an empty directory');
            is(dirname($root), dirname($argv->[4]), 'root and request share the protected workspace');
            my $config = $json->decode(read_file($argv->[2]));
            for my $path ($argv->[2], $config->{PKG_DBDIR}, $config->{PKG_CACHEDIR},
                @{$config->{REPOS_DIR}}) {
                like($path, qr{\A/}x, 'native configuration retains an absolute path');
                ok(index("$path/", "$root/") != 0, 'configuration and package state remain outside the empty root');
            }
            my $result = $original_runner->($argv, @options);
            is($result->{exitcode}, 0, 'the real native solve succeeds');
            is($result->{signal}, 0, 'the real native solve is not signalled');
            is_deeply(resolver_root_state($root), $before, 'native solve preserves the same empty root');
            if ($observed == 1) {
                my $alternate = tempdir('resolver-mode-XXXXXXXX', DIR => $tmp, CLEANUP => 1);
                chmod(oct('0755'), $alternate) or croak $!;
                my $alternate_before = resolver_root_state($alternate);
                my @alternate_argv = @$argv;
                $alternate_argv[5] = $alternate;
                my $direct = $original_runner->(\@alternate_argv, @options);
                is($direct->{exitcode}, 0, 'the native interface accepts a protected 0755 root');
                is($direct->{signal}, 0, 'the protected 0755 solve is not signalled');
                is($direct->{stdout}, $result->{stdout}, 'a different protected root preserves all native jobs');
                is_deeply(resolver_root_state($alternate), $alternate_before,
                    'the direct solve retains the same empty 0755 root');
            }
            return $result;
        };
        for (1 .. 2) {
            my ($bytes, $plan) = resolve_plan();
            push @plans, $bytes;
            is_deeply(package_names($plan), \@base_names, 'root isolation preserves the actual base package selection');
        }
    }
    is($observed, 2, 'both real solves reach the observation boundary');
    is(scalar(@roots), 2, 'both real solves supply a root');
    isnt($roots[0], $roots[1], 'repeated solves use distinct roots') if @roots == 2;
    is($plans[0], $plans[1], 'fresh roots do not change the canonical package plan');
    for my $root (@roots) {
        ok(!-e $root && !-l $root, 'the completed solve removes its empty root');
        ok(!-e dirname($root), 'the completed solve removes its scratch workspace');
    }
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, 'root observation restores the process boundary');
    return;
}

subtest 'native solves use fresh isolated empty roots' => \&resolver_root_lifecycle;

sub resolver_root_contamination {
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my ($root, $changes);
    $changes = 0;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @options) = @_;
            my $result = $original_runner->($argv, @options);
            return $result unless @$argv == 6 && $argv->[0] eq $solver->{path}
              && $argv->[3] eq 'resolve';
            croak 'Native solve failed before root contamination'
              if $result->{exitcode} || $result->{signal};
            $root = $argv->[5];
            write_file("$root/unexpected-file", "post-solve fixture\n");
            ++$changes;
            return $result;
        };
        rejects(sub { resolve_plan() }, qr/\ANative[ ]resolver[ ]root[ ]is[ ]not[ ]empty\n\z/x,
            'a root populated after native solve cannot produce an approved plan');
    }
    is($changes, 1, 'one successful real native response is contaminated');
    if (defined($root)) {
        ok(!-e $root && !-l $root, 'rejected root contents are removed with owned scratch');
        ok(!-e dirname($root), 'rejection removes the scratch workspace');
    }
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, 'contamination restores the process boundary');
    return;
}

subtest 'the caller rejects root contamination after successful solving' => \&resolver_root_contamination;

sub elf_fixture {
    my ($executable_flags, $library_flags) = @_;
    my $root = $fixture->new_directory();
    my $directory = "$root/lib";
    make_path($directory);
    write_file("$root/library.c", "int native_pin_fixture(void) { return 0; }\n");
    command('/usr/bin/cc', '-shared', '-fPIC', '-Wl,-soname,libpkg.so.999',
        @$library_flags, '-o', "$directory/libpkg.so.999", "$root/library.c");
    symlink('libpkg.so.999', "$directory/libpkg.so") or croak $!;
    my $sentinel = "$root/executed";
    write_file("$root/helper.c", "#include <stdio.h>\nint native_pin_fixture(void);\n"
        . 'int main(void) { FILE *f = fopen(' . $json->encode($sentinel)
        . ', "w"); if (f != NULL) fclose(f); return native_pin_fixture(); }' . "\n");
    my $executable = "$root/helper";
    command('/usr/bin/cc', "$root/helper.c", "-L$directory", '-lpkg',
        @$executable_flags, '-o', $executable);
    return ({ %$tool, library_directory => $directory,
        library_digest => xCAT::FreeBSDRepo::snapshot_tree($directory)->{digest} },
        { path => $executable, sha256 => sha256_hex(read_file($executable)) }, $sentinel);
}

sub native_elf_cases {
    for my $case (
        ['external RPATH', ['-Wl,--disable-new-dtags,-rpath,/tmp/unpinned-native'], []],
        ['external RUNPATH', ['-Wl,--enable-new-dtags,-rpath,/tmp/unpinned-native'], []],
        ['loader variable expansion', ['-Wl,-rpath,$ORIGIN/lib'], []],
        ['transitive library RPATH', [], ['-Wl,--disable-new-dtags,-rpath,/tmp/unpinned-native']],
    ) {
        my ($selected, $helper, $sentinel) = elf_fixture($case->[1], $case->[2]);
        rejects(sub { resolve_plan(tool => $selected, solver => $helper) },
            qr/loader[ ]path[ ]differs[ ]from[ ]the[ ]pinned[ ]library/ix,
            "$case->[0] is rejected before native execution");
        ok(!-e $sentinel, "$case->[0] does not execute the helper");
    }
    my ($selected, $helper, $sentinel) = elf_fixture([], ['-Wl,-soname,/tmp/unpinned-libpkg.so.999']);
    rejects(sub { resolve_plan(tool => $selected, solver => $helper) },
        qr/dependencies[ ]must[ ]be[ ]library[ ]basenames/ix,
        'a pathful native dependency cannot bypass library-directory selection');
    ok(!-e $sentinel, 'a pathful dependency does not execute the helper');
    ($selected, $helper, $sentinel) = elf_fixture([], []);
    my $missing_library = 'Native libpkg dependency is absent from the pinned library directory';
    rejects(sub { resolve_plan(solver => $helper) },
        qr/\Q$missing_library\E/x,
        'a solver cannot obtain its libpkg ABI from the system fallback');
    ok(!-e $sentinel, 'an absent pinned libpkg does not execute the helper');
    my $nonelf = "$tmp/non-elf-solver";
    write_file($nonelf, "#!/bin/sh\nprintf '2.8.2\\n'\n");
    chmod(oct('0700'), $nonelf) or croak $!;
    rejects(sub { resolve_plan(solver => { path => $nonelf, sha256 => sha256_hex(read_file($nonelf)) }) },
        qr/planning[ ]requires[ ]ELF/ix, 'a script cannot masquerade as the native ELF resolver');
    return;
}

subtest 'native ELF loading cannot bypass the pinned library tree' => \&native_elf_cases;

sub response_failure {
    my ($case, $original_runner, $overrides) = @_;
    $overrides ||= {};
    my $mutations = 0;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my @arguments = @_;
            my $result = $original_runner->(@arguments);
            my $argv = $arguments[0];
            return $result unless (@$argv == 5 || @$argv == 6)
              && $argv->[0] eq $solver->{path} && $argv->[1] eq '-C'
              && $argv->[2] =~ m{\A/}x && $argv->[3] eq 'resolve'
              && $argv->[4] =~ m{\A/}x && (@$argv == 5 || $argv->[5] =~ m{\A/}x);
            croak 'Native resolver failed before response mutation' if $result->{exitcode} || $result->{signal};
            ++$mutations;
            my %changed = %$result;
            if ($case->[1]) {
                my $response = $json->decode($result->{stdout});
                $case->[1]->($response);
                $changed{stdout} = $json->encode($response);
            } elsif ($case->[0] eq 'malformed JSON') {
                $changed{stdout} = '{';
            } elsif ($case->[0] eq 'runner error') {
                croak 'runner failed with native-secret-value';
            } else {
                $changed{exitcode} = 7;
                $changed{stderr} = 'native resolution failed with native-secret-value';
            }
            return \%changed;
        };
        my $error = rejects(sub { resolve_plan(%$overrides) }, $case->[2], "$case->[0] is rejected at the native response boundary");
        unlike($error, qr/native-secret-value/x, 'native failure diagnostics do not expose input bytes')
          if $case->[0] eq 'nonzero status' || $case->[0] eq 'runner error';
    }
    is($mutations, 1, "$case->[0] changes exactly one successful native solve response");
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, "$case->[0] restores the real process boundary");
    return;
}

subtest 'native response validation rejects changed or incomplete successful jobs' => sub {
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my @cases = (
        ['unknown repository', sub { $_[0]{jobs}[0]{repository} = 'r99'; }, qr/native[ ]resolver[ ]repository/ix],
        ['duplicate job', sub { push @{$_[0]{jobs}}, { %{$_[0]{jobs}[0]} }; }, qr/conflicting[ ]package[ ]providers/ix],
        ['non-install job', sub { $_[0]{jobs}[0]{job_type} = 'remove'; }, qr/non-install[ ]job/ix],
        ['changed identity', sub { $_[0]{jobs}[0]{package}{version} = 'unavailable-version'; }, qr/absent[ ]from[ ]its[ ]verified[ ]repository/ix],
        ['changed checksum', sub { $_[0]{jobs}[0]{package}{sum} = 'changed'; }, qr/selected[ ]sum[ ]differs/ix],
        ['changed archive path', sub { $_[0]{jobs}[0]{package}{repopath} = 'All/changed.pkg'; }, qr/selected[ ]repopath[ ]differs/ix],
        ['changed archive size', sub { ++$_[0]{jobs}[0]{package}{pkgsize}; }, qr/selected[ ]pkgsize[ ]differs/ix],
        ['missing required root', sub {
            my $response = shift;
            $response->{jobs} = [grep { $_->{package}{name} ne 'FreeBSD-kernel-generic' } @{$response->{jobs}}];
        }, qr/required[ ]base[ ]root[ ]is[ ]absent/ix],
        ['malformed JSON', undef, qr/invalid[ ]JSON/ix],
        ['nonzero status', undef, qr/dependency[ ]resolution[ ]failed/ix],
        ['runner error', undef, qr/dependency[ ]resolution[ ]failed/ix],
    );
    response_failure($_, $original_runner) for @cases;
};

sub diagnostic_command_matches {
    my ($argv, $stage, $solve) = @_;
    my $update = @$argv == 5 && $argv->[0] eq $tool->{path}
      && $argv->[1] eq '-C' && $argv->[2] =~ m{\A/}x
      && $argv->[3] eq 'update' && $argv->[4] eq '-f';
    my $resolution = $solve && @$argv == 6 && $argv->[1] eq '-C'
      && $argv->[2] =~ m{\A/}x && $argv->[4] =~ m{\A/}x
      && $argv->[5] =~ m{\A/}x;
    return $stage eq 'update' ? $update : $resolution;
}

sub successful_native_diagnostic {
    my $case = shift;
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my ($native, $changed, $plan_bytes);
    my ($mutations, $solves) = (0, 0);
    my %scratch;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @options) = @_;
            my $solve = @$argv >= 4 && $argv->[0] eq $solver->{path}
              && $argv->[3] eq 'resolve';
            ++$solves if $solve;
            my $result = $original_runner->($argv, @options);
            return $result unless diagnostic_command_matches($argv, $case->{stage}, $solve);
            croak 'Native command failed before diagnostic injection'
              if $result->{exitcode} || $result->{signal} || length($result->{stderr});
            my %options = @options;
            $scratch{$options{cwd}} = 1;
            ++$mutations;
            $native = { %$result };
            $changed = { %$result, stderr => $case->{stderr} };
            return $changed;
        };
        my $error = rejects(sub { ($plan_bytes) = resolve_plan() }, $case->{pattern},
            'a zero-exit native error cannot produce an approved plan');
        unlike($error, $case->{private}, 'native diagnostic bytes are not disclosed');
    }
    is($mutations, 1, 'exactly one successful native response receives diagnostic stderr');
    is($solves, $case->{solves}, 'the helper invocation count respects the failure boundary');
    ok(!defined($plan_bytes), 'the rejected call returns no plan bytes');
    $native ||= {};
    $changed ||= {};
    is($native->{exitcode}, 0, 'the real native command returned zero before injection');
    is($native->{signal}, 0, 'the real native command was not signalled');
    is($native->{stderr}, '', 'the real native command had no diagnostic stderr');
    is($changed->{stderr}, $case->{stderr}, 'the injected diagnostic is retained exactly');
    my %preserved = %$changed;
    $preserved{stderr} = $native->{stderr};
    is_deeply(\%preserved, $native, 'all other result fields retain the real native values');
    is(scalar(keys %scratch), 1, 'one owned scratch workspace reaches the injection boundary');
    for my $path (keys %scratch) {
        ok(!-e $path && !-l $path, 'failure removes the owned native scratch workspace');
    }
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, 'diagnostic injection restores the real process boundary');
    my (undef, $plan) = resolve_plan();
    is_deeply(package_names($plan), \@base_names, 'an ordinary native solve still succeeds after restoration');
    return;
}

subtest 'catalogue extraction errors stop resolution despite native exit zero' => sub {
    successful_native_diagnostic({
        stage => 'update', solves => 0,
        stderr => "pkg: Unable to drop privileges: no 'nobody' user\npkg: Repo extraction failed\n",
        private => qr/(?:nobody|Repo[ ]extraction)/x,
        pattern => qr/\ANative[ ]pkg[ ]resolver[ ]catalogue[ ]update[ ]failed\n\z/x,
    });
};

subtest 'repository-open errors reject successful native jobs without disclosing input' => sub {
    successful_native_diagnostic({
        stage => 'resolve', solves => 1,
        stderr => "FreeBSD resolver: Repository native-secret-value cannot be opened. 'pkg update' required\n",
        private => qr/native-secret-value/x,
        pattern => qr/\ANative[ ]pkg[ ]dependency[ ]resolution[ ]failed\n\z/x,
    });
};

sub readback_query_matches {
    my $argv = shift;
    return 0 unless @$argv == 12 && $argv->[0] eq $tool->{path}
      && $argv->[1] eq '-C' && $argv->[2] =~ m{\A/}x;
    return $json->encode([@$argv[3 .. 11]]) eq $json->encode(
        ['search', '-U', '-r', 'r1', '--raw', '--raw-format', 'json-compact', '-g', '*']);
}

sub readback_response {
    my ($case, $result) = @_;
    croak 'Native catalogue query failed before response mutation'
      if $result->{exitcode} || $result->{signal} || length($result->{stderr});
    my $records = $json->decode($result->{stdout});
    croak 'Native catalogue query did not return the existing supplemental fixture'
      unless ref($records) eq 'ARRAY' && @$records == 3;
    my @targets = grep { $_->{name} eq 'resolve-app' } @$records;
    croak 'Native catalogue query lost the unselected dependency-bearing package'
      unless @targets == 1 && $json->encode($targets[0]{deps})
        eq $json->encode(dependency('resolve-dep', '1', 'misc/resolve-dep'));
    my %changed = %$result;
    if ($case->{modify}) {
        $case->{modify}->($records, $targets[0]);
        $changed{stdout} = $json->encode($records);
    } else {
        $changed{stderr} = "native-readback-private-42\n";
    }
    return \%changed;
}

sub readback_failure {
    my ($case, $options, $baseline) = @_;
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my ($native, $changed, $plan_bytes);
    my @solves;
    my %scratch;
    my $mutations = 0;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @arguments) = @_;
            my $result = $original_runner->($argv, @arguments);
            push @solves, $result if @$argv == 6 && $argv->[0] eq $solver->{path}
              && $argv->[1] eq '-C' && $argv->[3] eq 'resolve';
            return $result unless readback_query_matches($argv);
            my %arguments = @arguments;
            $scratch{$arguments{cwd}} = 1;
            ++$mutations;
            $native = { %$result };
            $changed = readback_response($case, $result);
            return $changed;
        };
        my $error = rejects(sub { ($plan_bytes) = resolve_plan(%$options) },
            $case->{pattern}, "$case->{name} is rejected before native solving");
        unlike($error, qr/native-readback-private-42/x, 'native query stderr is not disclosed');
    }
    is($mutations, 1, 'one successful native query response is changed');
    is(scalar(@solves), 0, 'catalogue rejection precedes the native helper');
    ok(!defined($plan_bytes), 'catalogue rejection returns no plan bytes');
    $native ||= {};
    $changed ||= {};
    is_deeply([@$native{qw(exitcode signal stderr)}], [0, 0, ''],
        'the real query succeeds without diagnostics before mutation');
    my %preserved = %$changed;
    my $field = $case->{modify} ? 'stdout' : 'stderr';
    isnt($changed->{$field}, $native->{$field}, 'the selected native response field changes');
    $preserved{$field} = $native->{$field};
    is_deeply(\%preserved, $native, 'all other native response fields are unchanged');
    is_deeply([map { [@$_{qw(exitcode signal stderr)}] } @solves],
        [map { [0, 0, ''] } @solves], 'any reached native helper completes successfully');
    is(scalar(keys %scratch), 1, 'one owned workspace reaches the native query boundary');
    for my $path (keys %scratch) {
        ok(!-e $path && !-l $path, 'catalogue rejection removes the owned native workspace');
    }
    is(\&xCAT::FreeBSDPkg::run_command, $original_runner, 'query mutation restores the real process boundary');
    my ($restored) = resolve_plan(%$options);
    is($restored, $baseline, 'restoration preserves the complete ordinary plan bytes');
    return;
}

sub catalogue_readback_cases {
    my %options = (repositories => [@{$base{repositories}},
        { publication => $signed->{path}, role => 'repository' }], applications => ['resolve-dep']);
    my ($baseline, $plan) = resolve_plan(%options);
    is_deeply(package_names($plan), [sort(@base_names, 'resolve-dep')],
        'the real baseline excludes the dependency-bearing supplemental package');
    my $mismatch = 'Native resolver catalogue differs from its verified import';
    my $duplicate = 'Duplicate package identity in resolver catalogue query';
    my $query_error = 'Native pkg resolver catalogue query failed';
    my @cases = (
        { name => 'omitted unselected package', modify => sub {
            my ($records) = @_;
            @$records = grep { $_->{name} ne 'resolve-app' } @$records;
        }, pattern => qr/\A\Q$mismatch\E\n\z/x },
        { name => 'changed unselected field', modify => sub {
            my (undef, $target) = @_;
            $target->{comment} .= ' changed';
        }, pattern => qr/\A\Q$mismatch\E\n\z/x },
        { name => 'changed nested dependency', modify => sub {
            my (undef, $target) = @_;
            $target->{deps}{'resolve-dep'}{version} = '2';
        }, pattern => qr/\A\Q$mismatch\E\n\z/x },
        { name => 'added package', modify => sub {
            my ($records, $target) = @_;
            push @$records, { %$target, name => 'readback-added', origin => 'misc/readback-added' };
        }, pattern => qr/\A\Q$mismatch\E\n\z/x },
        { name => 'duplicate package', modify => sub {
            my ($records, $target) = @_;
            push @$records, { %$target };
        }, pattern => qr/\A\Q$duplicate\E\n\z/x },
        { name => 'zero-exit query stderr', pattern => qr/\A\Q$query_error\E\n\z/x },
    );
    readback_failure($_, \%options, $baseline) for @cases;
    return;
}

subtest 'materialized resolver catalogues retain every verified package record' => \&catalogue_readback_cases;


sub producer_fields {
    my ($package, $fields) = @_;
    return { map { $_ => $package->{$_} } grep { exists($package->{$_}) } @$fields };
}

sub omission_fields {
    return producer_fields(shift,
        [qw(vital messages shlibs_required_ignore users groups shlibs_provided_ignore)]);
}

sub omission_producer {
    my $metadata = {
        vital => JSON::true,
        messages => [{ message => 'Native omission fixture', type => 'install' },
            { message => 'Native upgrade fixture', type => 'upgrade' }],
        shlibs_required_ignore => ['libxcat_omission.so.1:32'],
        users => ['xcat_a', 'xcat_b'],
        groups => ['xcat_a', 'xcat_b'],
        shlibs_provided_ignore => ['libxcat_a.so.1', 'libxcat_b.so.1'],
    };
    my %expected = (
        'omission-vital' => { vital => $metadata->{vital} },
        'omission-messages' => { messages => $metadata->{messages} },
        'omission-ignore' => { shlibs_required_ignore => $metadata->{shlibs_required_ignore} },
        'omission-users' => { users => $metadata->{users} },
        'omission-groups' => { groups => $metadata->{groups} },
        'omission-provided-ignore' => { shlibs_provided_ignore => $metadata->{shlibs_provided_ignore} },
        'omission-all' => $metadata,
        'omission-plain' => {},
    );
    my @definitions = map { [$_, %{$expected{$_}},
        ($_ eq 'omission-all' ? (deps => dependency('omission-plain', '1', 'misc/omission-plain')) : ())]
    } sort keys %expected;
    return readback_producer(\@definitions, \%expected,
        [qw(vital messages shlibs_required_ignore users groups shlibs_provided_ignore)]);
}

sub readback_producer {
    my ($definitions, $expected, $fields) = @_;
    my $publication = imported_repository($definitions, 1, 0);
    my $before = xCAT::FreeBSDRepoImport::inspect_import($publication->{path}, $installroot);
    my %packages = map { $_->{name} => $_ } values %{$before->{source}{packages}};
    is_deeply([sort keys %packages], [sort keys %$expected], 'native producer has the exact package roster')
      or croak 'Native omission producer roster differs';
    my %archives;
    for my $name (sort keys %$expected) {
        is_deeply(producer_fields($packages{$name}, $fields), $expected->{$name},
            "$name authenticated catalogue retains the producer fields")
          or croak 'Native catalogue omitted fixture metadata';
        my $archive = "$publication->{path}/repository/All/$name-$packages{$name}{version}.pkg";
        my $bytes = run_pkg('info', '-F', $archive, '--raw', '--raw-format', 'json-compact');
        $archives{$name} = { bytes => $bytes, sha256 => sha256_hex(read_file($archive)) };
        is_deeply(producer_fields($json->decode($bytes), $fields), $expected->{$name},
            "$name native archive retains the producer fields")
          or croak 'Native archive omitted fixture metadata';
    }
    my $root = "$publication->{path}/repository";
    my $data = $json->decode(command('/usr/bin/tar', '-xOf', "$root/data.pkg", 'data'));
    my $bytes = command('/usr/bin/tar', '-xOf', "$root/packagesite.pkg", 'packagesite.yaml');
    my @manifests = map { $json->decode($_) } grep { length($_) } split(/\n/x, $bytes);
    for my $records ($data->{packages}, \@manifests) {
        is_deeply({ map { $_->{name} => producer_fields($_, $fields) } @$records }, $expected,
            'native catalogue bytes retain every producer field')
          or croak 'Native catalogue member metadata differs';
    }
    return { publication => $publication, before => $before, packages => \%packages,
        archives => \%archives, catalogues => { data => $data, packagesite => $bytes } };
}

sub omission_return_fields {
    my ($records, $packages) = @_;
    for my $package (@$records) {
        my $original = $packages->{$package->{name}};
        croak 'Native query returned an unknown omission fixture' unless $original;
        my $fields = $json->decode($json->encode(omission_fields($original)));
        @{$package}{keys %$fields} = values %$fields;
    }
    return;
}

sub omission_call {
    my ($label, $options, $modify) = @_;
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my $observed = { label => $label, queries => [], solves => [], scratch => {}, mutations => 0 };
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @arguments) = @_;
            my $result = $original_runner->($argv, @arguments);
            push @{$observed->{solves}}, { argv => [@$argv], result => { %$result } }
              if @$argv == 6 && $argv->[0] eq $solver->{path} && $argv->[1] eq '-C'
              && $argv->[3] eq 'resolve';
            return $result unless readback_query_matches($argv);
            croak 'Native omission query failed before observation'
              if $modify && ($result->{exitcode} || $result->{signal} || length($result->{stderr}));
            my %arguments = @arguments;
            $observed->{scratch}{$arguments{cwd}} = 1;
            my $query = { argv => [@$argv], native => { %$result }, returned => { %$result } };
            push @{$observed->{queries}}, $query;
            if ($modify) {
                my $records = $json->decode($result->{stdout});
                $modify->($records);
                $query->{returned}{stdout} = $json->encode($records);
                ++$observed->{mutations};
            }
            return $query->{returned};
        };
        $observed->{ok} = eval {
            @{$observed}{qw(bytes plan)} = resolve_plan(%$options);
            1;
        } ? 1 : 0;
        $observed->{error} = $@;
    }
    $observed->{boundary_restored} = \&xCAT::FreeBSDPkg::run_command == $original_runner ? 1 : 0;
    return $observed;
}

sub omission_response_fields {
    my ($result) = @_;
    my %copy = %$result;
    delete($copy{stdout});
    return \%copy;
}

sub omission_observation {
    my ($observed, $modified, $names) = @_;
    my $label = $observed->{label};
    my $queries = $observed->{queries};
    is(scalar(@$queries), 1, "$label observes one real query");
    is_deeply([map { [@{$_->{native}}{qw(exitcode signal stderr)}] } @$queries],
        [[0, 0, '']], "$label observes native query success");
    is($observed->{mutations}, $modified, "$label changes exactly the intended response");
    is_deeply([map { omission_response_fields($_->{returned}) } @$queries],
        [map { omission_response_fields($_->{native}) } @$queries],
        "$label preserves every other response field");
    is_deeply([map { [@{$_->{result}}{qw(exitcode signal stderr)}] } @{$observed->{solves}}],
        [map { [0, 0, ''] } @{$observed->{solves}}], "$label reached helpers succeed");
    is(scalar(keys %{$observed->{scratch}}), 1, "$label owns one query workspace");
    ok(!grep({ -e $_ || -l $_ } keys %{$observed->{scratch}}), "$label cleans its query workspace");
    is($observed->{boundary_restored}, 1, "$label restores the process boundary");
    my $records = @$queries ? $json->decode($queries->[0]{native}{stdout}) : [];
    is_deeply([sort map { $_->{name} } @$records], $names, "$label native query retains every package");
    is_deeply([map { omission_fields($_) } @$records], [map { {} } @$names],
        "$label real native query omits the six fields");
    is_deeply([map { $json->encode($_->{licenses}) =~ /\A\["(?:[^"\\]|\\.)*"\]\z/sx ? 1 : 0 } @$records],
        [map { 1 } @$names], "$label real native licenses have the pinned aggregate shape");
    return;
}

sub omission_positive {
    my ($observed, $modified, $names, $selected) = @_;
    omission_observation($observed, $modified, $names);
    my $label = $observed->{label};
    is($observed->{ok}, 1, "$label resolves successfully");
    is($observed->{error}, '', "$label has no public diagnostic");
    is(scalar(@{$observed->{solves}}), 1, "$label reaches one native solve");
    is_deeply(package_names($observed->{plan} || { packages => [] }), $selected,
        "$label preserves the exact selected closure");
    ok(defined($observed->{bytes}) && length($observed->{bytes}), "$label returns plan bytes");
    return;
}

sub omission_negative {
    my ($observed, $names) = @_;
    omission_observation($observed, 1, $names);
    my $label = $observed->{label};
    ok(!$observed->{ok}, "$label is rejected");
    is($observed->{error}, "Native resolver catalogue differs from its verified import\n",
        "$label has the exact readback diagnostic");
    is(scalar(@{$observed->{solves}}), 0, "$label stops before native solving");
    ok(!defined($observed->{bytes}), "$label returns no plan bytes");
    return;
}

sub omission_mutations {
    return (
        ['changed vital value', 'omission-all', 'vital', JSON::false],
        ['changed vital type', 'omission-all', 'vital', 'true'],
        ['null vital', 'omission-all', 'vital', undef],
        ['changed message value', 'omission-all', 'messages', [{ message => 'Changed', type => 'install' },
            { message => 'Native upgrade fixture', type => 'upgrade' }]],
        ['changed message kind', 'omission-all', 'messages', [{ message => 'Native omission fixture', type => 'remove' },
            { message => 'Native upgrade fixture', type => 'upgrade' }]],
        ['reordered messages', 'omission-all', 'messages', [{ message => 'Native upgrade fixture', type => 'upgrade' },
            { message => 'Native omission fixture', type => 'install' }]],
        ['changed message entry type', 'omission-all', 'messages', ['Native omission fixture']],
        ['changed messages type', 'omission-all', 'messages', 'Native omission fixture'],
        ['null messages', 'omission-all', 'messages', undef],
        ['changed ignore namespace', 'omission-all', 'shlibs_required_ignore', ['libxcat_omission.so.1']],
        ['changed ignore type', 'omission-all', 'shlibs_required_ignore', 'libxcat_omission.so.1:32'],
        ['null ignore list', 'omission-all', 'shlibs_required_ignore', undef],
        ['extra vital', 'omission-plain', 'vital', JSON::true],
        ['extra messages', 'omission-plain', 'messages', [{ message => 'Extra', type => 'install' }]],
        ['extra ignore list', 'omission-plain', 'shlibs_required_ignore', ['libextra.so.1:32']],
        ['changed users', 'omission-all', 'users', ['changed', 'xcat_b']],
        ['reordered users', 'omission-all', 'users', ['xcat_b', 'xcat_a']],
        ['wrong users type', 'omission-all', 'users', 'xcat_a'],
        ['null users', 'omission-all', 'users', undef],
        ['extra users', 'omission-plain', 'users', ['xcat_a']],
        ['changed groups', 'omission-all', 'groups', ['changed', 'xcat_b']],
        ['reordered groups', 'omission-all', 'groups', ['xcat_b', 'xcat_a']],
        ['wrong groups type', 'omission-all', 'groups', 'xcat_a'],
        ['null groups', 'omission-all', 'groups', undef],
        ['extra groups', 'omission-plain', 'groups', ['xcat_a']],
        ['changed provided ignore', 'omission-all', 'shlibs_provided_ignore', ['libchanged.so.1']],
        ['reordered provided ignore', 'omission-all', 'shlibs_provided_ignore', ['libxcat_b.so.1', 'libxcat_a.so.1']],
        ['wrong provided ignore type', 'omission-all', 'shlibs_provided_ignore', 'libxcat_a.so.1'],
        ['null provided ignore', 'omission-all', 'shlibs_provided_ignore', undef],
        ['extra provided ignore', 'omission-plain', 'shlibs_provided_ignore', ['libextra.so.1']],
        ['changed ordinary field with omissions', 'omission-all', 'comment', 'Changed', 'omit'],
        ['added actual requirement', 'omission-all', 'shlibs_required', ['libmissing.so.1:32'], 'omit'],
        ['changed nested dependency', 'omission-all', 'deps',
            { 'omission-plain' => { version => '2', origin => 'misc/omission-plain' } }, 'omit'],
        ['added unknown field', 'omission-all', 'unexpected_readback_field', JSON::true],
        ['dropped ordinary field', 'omission-all', 'comment', undef, 'delete'],
    );
}

sub omission_cases {
    my $producer = omission_producer();
    my $packages = $producer->{packages};
    my @names = sort keys %$packages;
    my %options = (repositories => [@{$base{repositories}},
        { publication => $producer->{publication}{path}, role => 'repository' }],
        applications => ['omission-plain']);
    my %selected_options = (%options, applications => [grep { $_ ne 'omission-plain' } @names]);
    my @plain_selection = sort(@base_names, 'omission-plain');
    my @full_selection = sort(@base_names, @names);
    my $restore_fields = sub { omission_return_fields($_[0], $packages) };
    my @observations;
    my $baseline = omission_call('exact returned fields', \%options, $restore_fields);
    push @observations, $baseline;
    omission_positive($baseline, 1, \@names, \@plain_selection);
    croak 'Exact returned fields did not establish the native baseline' unless $baseline->{ok};
    my $selected = omission_call('exact selected returned fields', \%selected_options, $restore_fields);
    push @observations, $selected;
    omission_positive($selected, 1, \@names, \@full_selection);
    croak 'Exact selected fields did not establish the native baseline' unless $selected->{ok};
    for my $case (['natural unselected omissions', \%options, \@plain_selection, $baseline->{bytes}],
            ['natural selected omissions', \%selected_options, \@full_selection, $selected->{bytes}]) {
        my ($label, $settings, $selection, $expected) = @$case;
        my $observed = omission_call($label, $settings, undef);
        push @observations, $observed;
        omission_positive($observed, 0, \@names, $selection);
        is($observed->{bytes}, $expected, "$label preserves complete plan bytes");
    }
    for my $case (omission_mutations()) {
        my ($label, $target, $field, $value, $action) = @$case;
        my $observed = omission_call($label, \%options, sub {
            my $records = shift;
            omission_return_fields($records, $packages) unless defined($action) && $action eq 'omit';
            my @targets = grep { $_->{name} eq $target } @$records;
            croak 'Native omission mutation target is missing' if @targets != 1;
            croak 'Native omission dependency changed before mutation'
              if $field eq 'deps' && $json->encode($targets[0]{deps})
                ne $json->encode(dependency('omission-plain', '1', 'misc/omission-plain'));
            if (defined($action) && $action eq 'delete') {
                delete($targets[0]{$field});
            } else {
                $targets[0]{$field} = $value;
            }
        });
        push @observations, $observed;
        omission_negative($observed, \@names);
        my $restored = omission_call("$label restored", \%options, $restore_fields);
        push @observations, $restored;
        omission_positive($restored, 1, \@names, \@plain_selection);
        is($restored->{bytes}, $baseline->{bytes}, "$label restoration preserves complete plan bytes");
    }
    is_deeply(xCAT::FreeBSDRepoImport::inspect_import($producer->{publication}{path}, $installroot),
        $producer->{before}, 'omission tests preserve all authenticated metadata and archive bytes');
    if (defined($ENV{XCAT_FREEBSD_READBACK_EVIDENCE})) {
        write_file("$ENV{XCAT_FREEBSD_READBACK_EVIDENCE}/observations.json",
            $json->encode({ producer => $producer, observations => \@observations }));
    }
    return;
}

subtest 'planning readback permits only absent non-planning metadata' => \&omission_cases;

sub license_producer {
    my %expected = (
        'license-absent' => { licenselogic => 'single' },
        'license-empty' => { licenselogic => 'single', licenses => [''] },
        'license-delimiter' => { licenselogic => 'single', licenses => ['alpha, beta'] },
        'license-quotes' => { licenselogic => 'single', licenses => [q{name "double" and 'single'}] },
        'license-multiple' => { licenselogic => 'or', licenses => ['Alpha', 'Beta', 'Gamma'] },
    );
    my @definitions = map { [$_, licenses => [], %{$expected{$_}}] } sort keys %expected;
    return readback_producer(\@definitions, \%expected, [qw(licenses licenselogic)]);
}

sub license_mutations {
    return (
        ['missing license aggregate', 'licenses', undef, 'delete'],
        ['null license aggregate', 'licenses', undef],
        ['scalar license aggregate', 'licenses', 'Alpha'],
        ['numeric license aggregate', 'licenses', 0],
        ['object license aggregate', 'licenses', {}],
        ['empty license array', 'licenses', []],
        ['multiple license aggregate entries', 'licenses', ['Alpha', 'Beta']],
        ['null license aggregate entry', 'licenses', [undef]],
        ['numeric license aggregate entry', 'licenses', [0]],
        ['object license aggregate entry', 'licenses', [{}]],
        ['boolean license aggregate entry', 'licenses', [JSON::true]],
        ['nested license aggregate entry', 'licenses', [[]]],
        ['changed license logic', 'licenselogic', 'and'],
        ['wrong license logic type', 'licenselogic', 0],
        ['null license logic', 'licenselogic', undef],
        ['changed shared library provision', 'shlibs_provided', ['libextra.so.1:32']],
        ['changed generic provision', 'provides', ['xcat-extra']],
        ['changed generic requirement', 'requires', ['xcat-missing']],
        ['changed license package identity', 'name', 'license-changed'],
        ['extra license record field', 'unexpected_license_field', JSON::true],
    );
}

sub license_modify {
    my ($records, $field, $value, $action) = @_;
    my @targets = grep { $_->{name} eq 'license-multiple' } @$records;
    croak 'Native license mutation target is missing' if @targets != 1;
    if (defined($action) && $action eq 'delete') {
        delete($targets[0]{$field});
    } else {
        $targets[0]{$field} = $value;
    }
    return;
}

sub readback_archive_call {
    my ($producer, $name, $field, $value) = @_;
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my $observed = { calls => [], mutations => 0 };
    my $archive = "$producer->{publication}{path}/repository/All/$name-$producer->{packages}{$name}{version}.pkg";
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @arguments) = @_;
            my $result = $original_runner->($argv, @arguments);
            return $result unless @$argv == 9 && $argv->[0] eq $tool->{path}
              && $argv->[1] eq '-C' && $json->encode([@$argv[3 .. 8]])
                eq $json->encode(['info', '-F', $archive, '--raw', '--raw-format', 'json-compact']);
            croak 'Native archive query failed before metadata observation'
              if $result->{exitcode} || $result->{signal} || length($result->{stderr});
            my $call = { argv => [@$argv], native => { %$result }, returned => { %$result } };
            push @{$observed->{calls}}, $call;
            if (defined($field)) {
                my $archive_record = $json->decode($result->{stdout});
                $archive_record->{$field} = $value;
                $call->{returned}{stdout} = $json->encode($archive_record);
                ++$observed->{mutations};
            }
            return $call->{returned};
        };
        $observed->{ok} = eval {
            $observed->{inspection} = xCAT::FreeBSDRepo::inspect_repository(
                "$producer->{publication}{path}/repository", tool => $tool,
                trust => { type => 'pubkey', path => "$tmp/repo.pub",
                    sha256 => sha256_hex(read_file("$tmp/repo.pub")) });
            1;
        } ? 1 : 0;
        $observed->{error} = $@;
    }
    $observed->{boundary_restored} = \&xCAT::FreeBSDPkg::run_command == $original_runner ? 1 : 0;
    return $observed;
}

sub license_archive_cases {
    my $producer = shift;
    my @observations;
    for my $field (qw(licenses licenselogic)) {
        my $observed = readback_archive_call($producer, 'license-multiple', $field,
            $field eq 'licenses' ? ['Changed archive license'] : 'and');
        push @observations, $observed;
        is(scalar(@{$observed->{calls}}), 1, "$field archive mutation reads the real archive once");
        is($observed->{mutations}, 1, "$field archive response is changed once");
        is_deeply([map { [@{$_->{native}}{qw(exitcode signal stderr)}] } @{$observed->{calls}}],
            [[0, 0, '']], "$field archive producer succeeds before mutation");
        is_deeply([map { omission_response_fields($_->{returned}) } @{$observed->{calls}}],
            [map { omission_response_fields($_->{native}) } @{$observed->{calls}}],
            "$field archive mutation preserves other response fields");
        is($observed->{boundary_restored}, 1, "$field archive boundary is restored");
        ok(!$observed->{ok}, "$field archive mismatch is rejected");
        is($observed->{error}, "Package archive metadata mismatch: license-multiple $field\n",
            "$field archive mismatch has the exact diagnostic");
        ok(!defined($observed->{inspection}), "$field archive mismatch returns no inspection");
        my $restored = readback_archive_call($producer, 'license-multiple', undef, undef);
        push @observations, $restored;
        is(scalar(@{$restored->{calls}}), 1, "$field restored inspection reads the real archive");
        is($restored->{mutations}, 0, "$field restored inspection leaves the response unchanged");
        is($restored->{ok}, 1, "$field restored inspection succeeds");
        is($restored->{error}, '', "$field restored inspection has no error");
        is($restored->{boundary_restored}, 1, "$field restored inspection restores the boundary");
        is_deeply($restored->{inspection}{packages}, $producer->{before}{source}{packages},
            "$field restored inspection preserves all authoritative package metadata");
    }
    return \@observations;
}

sub license_cases {
    my $producer = license_producer();
    my @names = sort keys %{$producer->{packages}};
    my %options = (repositories => [@{$base{repositories}},
        { publication => $producer->{publication}{path}, role => 'repository' }],
        applications => ['license-empty']);
    my %selected_options = (%options, applications => \@names);
    my @plain_selection = sort(@base_names, 'license-empty');
    my @full_selection = sort(@base_names, @names);
    my @observations;
    my $baseline = omission_call('natural unselected licenses', \%options, undef);
    push @observations, $baseline;
    omission_positive($baseline, 0, \@names, \@plain_selection);
    my $selected = omission_call('natural selected licenses', \%selected_options, undef);
    push @observations, $selected;
    omission_positive($selected, 0, \@names, \@full_selection);
    for my $case (['changed valid license aggregate', ['Unrelated license aggregate']],
            ['blank valid license aggregate', ['']],
            ['delimiter and quotes in valid aggregate', [q{not, the "original" 'licenses'}]]) {
        my ($label, $value) = @$case;
        my $observed = omission_call($label, \%options,
            sub { license_modify($_[0], 'licenses', $value, undef) });
        push @observations, $observed;
        omission_positive($observed, 1, \@names, \@plain_selection);
        is($observed->{bytes}, $baseline->{bytes}, "$label preserves complete plan bytes");
    }
    for my $case (license_mutations()) {
        my ($label, $field, $value, $action) = @$case;
        my $observed = omission_call($label, \%options,
            sub { license_modify($_[0], $field, $value, $action) });
        push @observations, $observed;
        omission_negative($observed, \@names);
        my $restored = omission_call("$label restored", \%options, undef);
        push @observations, $restored;
        omission_positive($restored, 0, \@names, \@plain_selection);
        is($restored->{bytes}, $baseline->{bytes}, "$label restoration preserves complete plan bytes");
    }
    my $archives = license_archive_cases($producer);
    is_deeply(xCAT::FreeBSDRepoImport::inspect_import($producer->{publication}{path}, $installroot),
        $producer->{before}, 'license tests preserve all authenticated metadata and archive bytes');
    if (defined($ENV{XCAT_FREEBSD_READBACK_EVIDENCE})) {
        write_file("$ENV{XCAT_FREEBSD_READBACK_EVIDENCE}/licenses.json",
            $json->encode({ producer => $producer, observations => \@observations, archives => $archives }));
    }
    return;
}

subtest 'license aggregates do not replace authoritative archive metadata' => \&license_cases;



sub dependency_producers {
    my %expected = (
        'version-provider' => {},
        'version-plain' => {},
        'version-consumer' => { deps => dependency('version-provider', '99', 'misc/version-provider') },
        'version-cross' => { deps => dependency('remote-provider', '99', 'misc/remote-provider') },
        'version-broken' => { deps => dependency('version-unavailable', '1', 'misc/version-unavailable') },
    );
    my @definitions = map { [$_, %{$expected{$_}}] } sort keys %expected;
    my $local = readback_producer(\@definitions, \%expected, ['deps']);
    my @typed = (
        { map { $_ => producer_fields($local->{packages}{$_}, ['deps']) } sort keys %expected },
        { map { $_ => producer_fields($json->decode($local->{archives}{$_}{bytes}), ['deps']) } sort keys %expected },
        { map { $_->{name} => producer_fields($_, ['deps']) } @{$local->{catalogues}{data}{packages}} },
        { map { $_->{name} => producer_fields($_, ['deps']) }
            map { $json->decode($_) } grep { length($_) } split(/\n/x, $local->{catalogues}{packagesite}) },
    );
    is($json->encode(\@typed), $json->encode([map { \%expected } 1 .. 4]),
        'authenticated, archive and both catalogue records retain exact dependency types and values');
    my $remote = readback_producer([['remote-provider']], { 'remote-provider' => {} }, ['deps']);
    return ($local, $remote);
}

sub dependency_query_fields {
    return {
        'version-provider' => {},
        'version-plain' => {},
        'version-consumer' => { deps => dependency('version-provider', '1', 'misc/version-provider') },
        'version-cross' => { deps => { 'remote-provider' => { origin => 'misc/remote-provider' } } },
        'version-broken' => { deps => { 'version-unavailable' => { origin => 'misc/version-unavailable' } } },
    };
}

sub dependency_observation {
    my ($observed, $modified) = @_;
    my $label = $observed->{label};
    my $queries = $observed->{queries};
    is(scalar(@$queries), 1, "$label observes one real local query");
    is_deeply([map { [@{$_->{native}}{qw(exitcode signal stderr)}] } @$queries],
        [[0, 0, '']], "$label observes native query success");
    my $records = @$queries ? $json->decode($queries->[0]{native}{stdout}) : [];
    is($json->encode({ map { $_->{name} => producer_fields($_, ['deps']) } @$records }),
        $json->encode(dependency_query_fields()), "$label observes actual repository-local dependency versions");
    is($observed->{mutations}, $modified, "$label changes exactly the intended response");
    is_deeply([map { omission_response_fields($_->{returned}) } @$queries],
        [map { omission_response_fields($_->{native}) } @$queries],
        "$label preserves every other response field");
    is(scalar(grep { $_->{returned}{stdout} ne $_->{native}{stdout} } @$queries), $modified,
        "$label changes only the intended query bytes");
    is(scalar(keys %{$observed->{scratch}}), 1, "$label owns one query workspace");
    ok(!grep({ -e $_ || -l $_ } keys %{$observed->{scratch}}), "$label cleans its query workspace");
    is($observed->{boundary_restored}, 1, "$label restores the process boundary");
    return;
}

sub dependency_positive {
    my ($observed, $selected) = @_;
    dependency_observation($observed, 0);
    my $label = $observed->{label};
    is($observed->{ok}, 1, "$label resolves successfully");
    is($observed->{error}, '', "$label has no public diagnostic");
    is(scalar(@{$observed->{solves}}), 1, "$label reaches one native solve");
    is_deeply([map { [@{$_->{result}}{qw(exitcode signal stderr)}] } @{$observed->{solves}}],
        [[0, 0, '']], "$label real helper succeeds");
    is_deeply(package_names($observed->{plan} || { packages => [] }), $selected,
        "$label preserves the exact selected closure");
    ok(defined($observed->{bytes}) && length($observed->{bytes}), "$label returns plan bytes");
    return;
}

sub dependency_negative {
    my $observed = shift;
    dependency_observation($observed, 1);
    my $label = $observed->{label};
    ok(!$observed->{ok}, "$label is rejected");
    is($observed->{error}, "Native resolver catalogue differs from its verified import\n",
        "$label has the exact readback diagnostic");
    is(scalar(@{$observed->{solves}}), 0, "$label stops before native solving");
    ok(!defined($observed->{bytes}), "$label returns no plan bytes");
    return;
}

sub dependency_missing {
    my $observed = shift;
    dependency_observation($observed, 0);
    ok(!$observed->{ok}, 'missing provider is rejected');
    is($observed->{error}, "Native pkg dependency resolution failed\n",
        'missing provider has the exact helper failure diagnostic');
    is(scalar(@{$observed->{solves}}), 1, 'missing provider reaches the real native helper');
    my $result = @{$observed->{solves}} ? $observed->{solves}[0]{result} : {};
    ok($result->{exitcode} && !$result->{signal}, 'missing provider causes a real nonzero helper exit');
    is($result->{stderr} || '',
        "FreeBSD resolver: version-broken has a missing dependency: version-unavailable\n"
        . "FreeBSD resolver: cannot solve package requests\n",
        'the real helper identifies the missing provider and its consumer');
    ok(!defined($observed->{bytes}), 'missing provider returns no plan bytes');
    return;
}

sub dependency_mutations {
    return (
        ['wrong provider version', 'version-consumer', 'version-provider', 'version', '99'],
        ['missing provider version', 'version-consumer', 'version-provider', 'version', undef, 'delete'],
        ['null provider version', 'version-consumer', 'version-provider', 'version', undef],
        ['numeric provider version', 'version-consumer', 'version-provider', 'version', 1],
        ['object provider version', 'version-consumer', 'version-provider', 'version', {}],
        ['changed dependency origin', 'version-consumer', 'version-provider', 'origin', 'misc/wrong'],
        ['extra dependency field', 'version-consumer', 'version-provider', 'unexpected', JSON::true],
        ['invented absent provider version', 'version-broken', 'version-unavailable', 'version', '1'],
        ['invented cross-repository version', 'version-cross', 'remote-provider', 'version', '1'],
        ['missing dependency entry', 'version-consumer', 'version-provider', undef, undef, 'delete'],
    );
}

sub dependency_modify {
    my ($records, $case) = @_;
    my (undef, $package, $name, $field, $value, $action) = @$case;
    my @targets = grep { $_->{name} eq $package } @$records;
    croak 'Native dependency mutation target is missing' if @targets != 1;
    my $deps = $targets[0]{deps};
    croak 'Native dependency mutation entry is missing' unless exists($deps->{$name});
    if (!defined($field)) {
        delete($deps->{$name});
    } elsif (defined($action) && $action eq 'delete') {
        delete($deps->{$name}{$field});
    } else {
        $deps->{$name}{$field} = $value;
    }
    return;
}

sub dependency_archive_cases {
    my $producer = shift;
    my $observed = readback_archive_call($producer, 'version-consumer', 'deps',
        dependency('version-provider', '1', 'misc/version-provider'));
    is(scalar(@{$observed->{calls}}), 1, 'dependency archive control reads the real archive once');
    is($observed->{mutations}, 1, 'dependency archive control changes only one native response');
    is_deeply([map { [@{$_->{native}}{qw(exitcode signal stderr)}] } @{$observed->{calls}}],
        [[0, 0, '']], 'dependency archive producer succeeds before mutation');
    is_deeply([map { omission_response_fields($_->{returned}) } @{$observed->{calls}}],
        [map { omission_response_fields($_->{native}) } @{$observed->{calls}}],
        'dependency archive control preserves all other response fields');
    is($observed->{boundary_restored}, 1, 'dependency archive control restores the process boundary');
    ok(!$observed->{ok}, 'the provider version cannot replace the declared archive version');
    is($observed->{error}, "Package archive metadata mismatch: version-consumer deps\n",
        'the archive check has the exact dependency metadata diagnostic');
    ok(!defined($observed->{inspection}), 'the archive mismatch returns no inspection');
    my $restored = readback_archive_call($producer, 'version-consumer', undef, undef);
    is(scalar(@{$restored->{calls}}), 1, 'restored dependency inspection reads the real archive');
    is($restored->{mutations}, 0, 'restored dependency inspection preserves the native response');
    is($restored->{ok}, 1, 'restored dependency inspection succeeds');
    is($restored->{error}, '', 'restored dependency inspection has no diagnostic');
    is($restored->{boundary_restored}, 1, 'restored dependency inspection restores the boundary');
    is_deeply($restored->{inspection}{packages}, $producer->{before}{source}{packages},
        'restored dependency inspection preserves every authoritative package field');
    return [$observed, $restored];
}

sub dependency_version_cases {
    my ($local, $remote) = dependency_producers();
    my %options = (repositories => [@{$base{repositories}},
        { publication => $local->{publication}{path}, role => 'repository' },
        { publication => $remote->{publication}{path}, role => 'repository' }]);
    my @observations;
    for my $case (
        ['unselected dependency versions', ['version-plain'], ['version-plain']],
        ['selected same-repository version', ['version-consumer'], ['version-consumer', 'version-provider']],
        ['selected cross-repository version', ['version-cross'], ['version-cross', 'remote-provider']],
    ) {
        my $observed = omission_call($case->[0], { %options, applications => $case->[1] }, undef);
        push @observations, $observed;
        dependency_positive($observed, [sort(@base_names, @{$case->[2]})]);
    }
    my $cross = $observations[-1]{plan} || { packages => [] };
    is_deeply([map { $_->{repository} } grep { $_->{name} eq 'remote-provider' } @{$cross->{packages}}],
        ['r2'], 'the cross-repository provider retains its actual repository identity');
    my $missing = omission_call('missing dependency provider',
        { %options, applications => ['version-broken'] }, undef);
    push @observations, $missing;
    dependency_missing($missing);
    my %plain = (%options, applications => ['version-plain']);
    for my $case (dependency_mutations()) {
        my $observed = omission_call($case->[0], \%plain, sub { dependency_modify($_[0], $case) });
        push @observations, $observed;
        dependency_negative($observed);
        my $restored = omission_call("$case->[0] restored", \%plain, undef);
        push @observations, $restored;
        dependency_positive($restored, [sort(@base_names, 'version-plain')]);
        is($restored->{bytes}, $observations[0]{bytes}, "$case->[0] restoration preserves complete plan bytes");
    }
    my $archives = dependency_archive_cases($local);
    for my $producer ($local, $remote) {
        is_deeply(xCAT::FreeBSDRepoImport::inspect_import($producer->{publication}{path}, $installroot),
            $producer->{before}, 'dependency tests preserve all authenticated metadata and archive bytes');
    }
    if (defined($ENV{XCAT_FREEBSD_READBACK_EVIDENCE})) {
        write_file("$ENV{XCAT_FREEBSD_READBACK_EVIDENCE}/dependencies.json",
            $json->encode({ producers => [$local, $remote], observations => \@observations, archives => $archives }));
    }
    return;
}

subtest 'native dependency versions follow only sealed same-repository providers' => \&dependency_version_cases;

sub duplicate_roster {
    my ($records) = @_;
    return [sort map { $json->encode([@$_{qw(name version origin)}]) } @$records];
}

sub dependency_duplicate_source {
    my ($definitions, $name) = @_;
    my $original_runner = \&xCAT::FreeBSDPkg::run_command;
    my $build = { calls => [] };
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            my ($argv, @arguments) = @_;
            my $result = $original_runner->($argv, @arguments);
            push @{$build->{calls}}, { argv => [@$argv], result => { %$result } };
            return $result;
        };
        $build->{ok} = eval { $build->{source} = $fixture->repository(1, $definitions); 1; } ? 1 : 0;
        $build->{error} = $@;
    }
    $build->{boundary_restored} = \&xCAT::FreeBSDPkg::run_command == $original_runner ? 1 : 0;
    if (defined($ENV{XCAT_FREEBSD_READBACK_EVIDENCE})) {
        write_file("$ENV{XCAT_FREEBSD_READBACK_EVIDENCE}/$name-build.json", $json->encode($build));
    }
    croak $build->{error} unless $build->{ok};
    return $build;
}

sub dependency_duplicate_producer {
    my $referenced = shift;
    my $root_name = $referenced ? 'duplicate-consumer' : 'duplicate-plain';
    my @definitions = (
        ['duplicate-provider', origin => 'misc/duplicate-one'],
        ['duplicate-provider', version => '2', origin => 'misc/duplicate-two'],
        [$root_name, $referenced ? (deps => dependency('duplicate-provider', '1', 'misc/duplicate-one')) : ()],
    );
    my $build = dependency_duplicate_source(\@definitions, $root_name);
    my $expected = [sort map { $json->encode($_) }
        ['duplicate-provider', '1', 'misc/duplicate-one'],
        ['duplicate-provider', '2', 'misc/duplicate-two'], [$root_name, '1', "misc/$root_name"]];
    my $root = $build->{source};
    my @archives = map { run_pkg('info', '-F', "$root/All/$_", '--raw', '--raw-format', 'json-compact') }
        ('duplicate-provider-1.pkg', 'duplicate-provider-2.pkg', "$root_name-1.pkg");
    is_deeply(duplicate_roster([map { $json->decode($_) } @archives]), $expected,
        'real archive manifests retain both same-name versions');
    my $data = $json->decode(command('/usr/bin/tar', '-xOf', "$root/data.pkg", 'data'));
    my $site = command('/usr/bin/tar', '-xOf', "$root/packagesite.pkg", 'packagesite.yaml');
    is_deeply(duplicate_roster($data->{packages}), $expected, 'the native data catalogue retains both versions');
    is_deeply(duplicate_roster([map { $json->decode($_) } grep { length($_) } split(/\n/x, $site)]),
        $expected, 'the native manifest catalogue retains both versions');
    if (defined($ENV{XCAT_FREEBSD_READBACK_EVIDENCE})) {
        write_file("$ENV{XCAT_FREEBSD_READBACK_EVIDENCE}/$root_name-source.json",
            $json->encode({ archives => \@archives, catalogues => { data => $data, packagesite => $site },
                snapshot => xCAT::FreeBSDRepo::snapshot_tree($root) }));
    }
    my $publication = imported_repository(undef, 1, 0, $root);
    my $before = xCAT::FreeBSDRepoImport::inspect_import($publication->{path}, $installroot);
    is_deeply(duplicate_roster([values %{$before->{source}{packages}}]), $expected,
        'the real imported producer retains both same-name versions');
    return { publication => $publication, before => $before, expected => $expected,
        root_name => $root_name, build => $build,
        archives => \@archives, catalogues => { data => $data, packagesite => $site } };
}

sub dependency_duplicate_case {
    my $referenced = shift;
    my $producer = dependency_duplicate_producer($referenced);
    my $observed = omission_call($referenced ? 'referenced duplicate versions' : 'unreferenced duplicate versions', {
        repositories => [@{$base{repositories}}, { publication => $producer->{publication}{path}, role => 'repository' }],
        applications => [$producer->{root_name}],
    }, undef);
    is(scalar(@{$observed->{queries}}), 1, 'duplicate versions reach the real resolver query');
    my $query = @{$observed->{queries}} ? $observed->{queries}[0] : { native => {}, returned => {} };
    is_deeply([@{$query->{native}}{qw(exitcode signal)}], [0, 0], 'duplicate-version query exits normally');
    my $records = defined($query->{native}{stdout}) ? $json->decode($query->{native}{stdout}) : [];
    is_deeply(duplicate_roster($records), $producer->{expected}, 'native query retains both same-name versions');
    if ($referenced) {
        like($query->{native}{stderr}, qr/duplicate[ ]dependency[ ]listing:[ ]duplicate-provider/x,
            'native stderr identifies the competing dependency providers');
        ok(!$observed->{ok}, 'referenced competing versions are rejected');
        is($observed->{error}, "Native pkg resolver catalogue query failed\n",
            'referenced competing versions stop at the exact native-query boundary');
        is(scalar(@{$observed->{solves}}), 0, 'referenced competing versions never reach the helper');
        ok(!defined($observed->{bytes}), 'referenced competing versions return no plan');
    } else {
        is($query->{native}{stderr}, '', 'unreferenced duplicate versions have no native diagnostic');
        is($observed->{ok}, 1, 'unreferenced duplicate versions remain accepted');
        is($observed->{error}, '', 'unreferenced duplicate versions have no public error');
        is(scalar(@{$observed->{solves}}), 1, 'unreferenced duplicate versions reach the real helper');
        is_deeply([map { [@{$_->{result}}{qw(exitcode signal stderr)}] } @{$observed->{solves}}],
            [[0, 0, '']], 'the unreferenced duplicate-version helper succeeds');
        is_deeply(package_names($observed->{plan} || { packages => [] }), [sort(@base_names, 'duplicate-plain')],
            'unreferenced duplicate versions do not enter the selected closure');
    }
    is_deeply($query->{returned}, $query->{native}, 'duplicate-version observation preserves the complete real result');
    is($observed->{mutations}, 0, 'duplicate-version observation changes no response');
    is($observed->{boundary_restored}, 1, 'duplicate-version observation restores the process boundary');
    is(scalar(keys %{$observed->{scratch}}), 1, 'duplicate versions use one query workspace');
    ok(!grep({ -e $_ || -l $_ } keys %{$observed->{scratch}}), 'duplicate-version observation cleans the workspace');
    is_deeply(xCAT::FreeBSDRepoImport::inspect_import($producer->{publication}{path}, $installroot),
        $producer->{before}, 'duplicate-version observation preserves the imported source');
    return { producer => $producer, observation => $observed };
}

sub dependency_duplicate_cases {
    my @observations = map { dependency_duplicate_case($_) } (0, 1);
    if (defined($ENV{XCAT_FREEBSD_READBACK_EVIDENCE})) {
        write_file("$ENV{XCAT_FREEBSD_READBACK_EVIDENCE}/duplicate-versions.json", $json->encode(\@observations));
    }
    return;
}

subtest 'duplicate provider versions remain subject to native catalogue diagnostics' => \&dependency_duplicate_cases;

ok(!-e "$tmp/package-script-executed", 'native resolution never executes package install scripts');
ok(!-e '/var/db/pkg' && !-l '/var/db/pkg', 'native resolution never creates the default package database');
ok(!-e "$installroot/freebsd15.1/x86_64/plans", 'resolution produces bytes without publication side effects');
is(sha256_hex(read_file($tool->{path})), $tool->{sha256}, 'native pkg executable is unchanged');
is(sha256_hex(read_file($solver->{path})), $solver->{sha256}, 'native resolver executable is unchanged');
is_deeply(xCAT::FreeBSDRepoImport::inspect_import($disc->{path}, $installroot), $disc_before,
    'base publication is unchanged by native resolution');
is_deeply(xCAT::FreeBSDRepoImport::inspect_import($dvd->{path}, $installroot), $dvd_before,
    'DVD publication is unchanged by native resolution');
is_deeply(xCAT::FreeBSDRepoImport::inspect_import($signed->{path}, $installroot), $signed_before,
    'signed supplemental publication is unchanged by native resolution');

done_testing();
