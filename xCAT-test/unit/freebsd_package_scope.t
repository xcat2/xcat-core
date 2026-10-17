#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;

plan(skip_all => 'Scoped package fixtures require Linux root') unless $^O eq 'linux' && $> == 0;
for my $variable (qw(XCAT_FREEBSD_NATIVE_PKG XCAT_FREEBSD_NATIVE_SOLVER XCAT_FREEBSD_NATIVE_LIBDIR)) {
    plan(skip_all => "Set $variable to the pinned native tool or library directory") unless defined($ENV{$variable});
}

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}),
    library_directory => abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR}) };
my $solver = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_SOLVER}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C', LD_LIBRARY_PATH => $tool->{library_directory});

sub read_file {
    my ($path) = @_;
    open(my $file, '<', $path) or croak "$path: $!";
    binmode($file) or croak $!;
    local $/ = undef;
    my $bytes = <$file>;
    close($file) or croak $!;
    return defined($bytes) ? $bytes : '';
}

sub write_file {
    my ($path, $bytes) = @_;
    make_path(dirname($path));
    open(my $file, '>', $path) or croak "$path: $!";
    binmode($file) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

sub command {
    my (@arguments) = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@arguments, cwd => $tmp,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub run_pkg {
    my (@arguments) = @_;
    return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments);
}

sub names {
    my ($plan) = @_;
    return [sort map { $_->{name} } @{$plan->{packages}}];
}

sub rejects {
    my ($operation, $pattern, $description) = @_;
    my $ok = eval { $operation->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    like($error, $pattern, 'rejection identifies the invalid selection or binding');
    return;
}

$tool->{sha256} = sha256_hex(read_file($tool->{path}));
$solver->{sha256} = sha256_hex(read_file($solver->{path}));
$tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);
my $root = $fixture->new_directory();
my $release = $fixture->release_tree(1);
my $repository = "$release/usr/freebsd-packages/offline";
for my $name (qw(FreeBSD-ssh FreeBSD-bsdconfig FreeBSD-unused)) {
    $fixture->create_package("$repository/All", $name, version => '15.1', origin => "base/$name",
        annotations => { FreeBSD_version => '1501000' });
}
$fixture->create_package("$repository/All", 'FreeBSD-set-minimal', version => '15.1',
    origin => 'base/FreeBSD-set-minimal', annotations => { FreeBSD_version => '1501000' },
    deps => { 'FreeBSD-runtime' => { origin => 'base/FreeBSD-runtime', version => '15.1' } });
run_pkg('repo', $repository);
my $base = xCAT::FreeBSDRepoImport::import_release($release, $root, tool => $tool,
    trust => { type => 'operator-trusted-release', digest => xCAT::FreeBSDRepo::inspect_release_tree($release)->{digest} });
my $applications = $fixture->repository(0, [
    ['scope-dep'], ['scope-unused'],
    ['scope-app', deps => { 'scope-dep' => { origin => 'misc/scope-dep', version => '1' } }],
    ['scope-base-app', deps => { 'FreeBSD-runtime' => { origin => 'base/FreeBSD-runtime', version => '15.1' } }],
]);
my $supplement = xCAT::FreeBSDRepoImport::import_repository($applications, $root, tool => $tool,
    trust => { type => 'operator-trusted-tree', digest => xCAT::FreeBSDRepo::snapshot_tree($applications)->{digest} });
my %options = (installroot => $root, repositories => [
    { publication => $base->{path}, role => 'base' },
    { publication => $base->{path}, role => 'applications' },
    { publication => $supplement->{path}, role => 'repository' }],
    components => ['base'], applications => [qw(application scope-app)], tool => $tool, solver => $solver);
my @base_names = sort qw(FreeBSD-bsdconfig FreeBSD-kernel-generic FreeBSD-runtime FreeBSD-set-base FreeBSD-set-minimal FreeBSD-ssh pkg);
my @application_names = qw(application scope-app scope-dep);
my $full_bytes = xCAT::FreeBSDPackagePlan::resolve(%options);
my $full = xCAT::FreeBSDPackagePlan::parse($full_bytes);
my %expected = (all => [sort(@base_names, @application_names)], base => \@base_names, applications => \@application_names);

sub resolve_scope {
    my ($scope, %overrides) = @_;
    my $bytes = eval { xCAT::FreeBSDPackagePlan::resolve(%options, scope => $scope, %overrides); };
    my $error = $@;
    ok(defined($bytes), "$scope resolves through the native solver") or diag($error);
    return unless defined($bytes);
    return xCAT::FreeBSDPackagePlan::parse($bytes);
}

sub scope_cases {
    for my $scope (qw(all base applications)) {
        subtest "$scope selects only its requested closure" => sub {
            my $plan = resolve_scope($scope);
            return unless $plan;
            is_deeply(names($plan), $expected{$scope}, 'exact package names exclude unselected roots and unrelated packages');
            is($plan->{scope} || 'all', $scope, 'scoped operation identity survives decoding');
            is_deeply($plan->{components}, $scope eq 'applications' ? [] : ['base'], 'base root provenance follows scope');
            my %packages = map { $_->{id} => $_->{name} } @{$plan->{packages}};
            is_deeply([map { $packages{$_} } @{$plan->{applications}}], $scope eq 'base' ? [] : [qw(application scope-app)],
                'application provenance retains explicit roots without promoting dependencies');
            is_deeply($plan->{repositories}, $full->{repositories}, 'repository identities, trust and order are preserved');
            is_deeply($plan, $full, 'explicit all retains ordinary installation semantics') if $scope eq 'all';
        };
    }
    return;
}

scope_cases();

subtest 'unselected roots do not become update prerequisites' => sub {
    my $os = resolve_scope('base', applications => ['unavailable-app']);
    is_deeply(names($os), \@base_names, 'base update does not resolve an unavailable application') if $os;
    my $apps = resolve_scope('applications', components => ['unavailable-component']);
    is_deeply(names($apps), \@application_names, 'application update does not resolve an unavailable optional base component') if $apps;
};

subtest 'an application brings only the base packages it depends on' => sub {
    my $plan = resolve_scope('applications', applications => ['scope-base-app']);
    return unless $plan;
    is_deeply(names($plan), [qw(FreeBSD-runtime scope-base-app)], 'the dependency does not expand into an OS update');
    my ($runtime) = grep { $_->{name} eq 'FreeBSD-runtime' } @{$plan->{packages}};
    is($runtime->{repository}, 'r0', 'the base dependency uses its verified base provider');
};

subtest 'unknown scopes and invalid selected roots fail before publication' => sub {
    for my $invalid_scope (undef, '', 'All', 'otherpkgs', []) {
        rejects(sub { xCAT::FreeBSDPackagePlan::resolve(%options, scope => $invalid_scope); }, qr/scope/x, 'unknown scope is rejected');
    }
    rejects(sub { xCAT::FreeBSDPackagePlan::resolve(%options, scope => 'applications', applications => ['missing-app']); },
        qr/unavailable/x, 'selected application must exist');
    rejects(sub { xCAT::FreeBSDPackagePlan::resolve(%options, scope => 'base', components => ['missing-component']); },
        qr/component/x, 'selected component must exist');
    ok(!-e "$root/freebsd15.1/x86_64/plans", 'resolution and rejected requests publish no plans');
};

write_file("$tmp/base-list", "# image base\nbase\n");
write_file("$tmp/app-list", "# image applications\napplication\nscope-app\n");
my $image = { imagetype => 'freebsd', osvers => 'freebsd15.1', osarch => 'x86_64',
    provmethod => 'install', osname => 'FreeBSD', imageversion => '2', bootdir => "$tmp/boot",
    pkgdir => "$base->{path}/base", pkglist => "$tmp/base-list",
    otherpkgdir => "$base->{path}/applications,$supplement->{path}/repository", otherpkglist => "$tmp/app-list" };

subtest 'published scoped plans retain the original image request' => sub {
    for my $scope (qw(base applications all)) {
        my $published = eval { xCAT::FreeBSDPackagePlan::publish_image(installroot => $root,
            image => $image, tool => $tool, solver => $solver, scope => $scope); };
        my $error = $@;
        ok($published, "$scope publishes with native resolution and source binding") or diag($error);
        next unless $published;
        is_deeply(names($published->{plan}), $expected{$scope}, 'publication retains the scoped closure');
        my $bound = xCAT::FreeBSDPackagePlan::inspect_image($published->{path}, $root, $image, $scope);
        is_deeply($bound->{request}{components}, ['base'], 'original base request remains in provenance');
        is_deeply($bound->{request}{applications}, [qw(application scope-app)], 'original application request remains in provenance');
        is($bound->{request}{scope}, $scope, 'request records which roots the operation selects');
        is_deeply([map { $_->{bytes} } @{$bound->{request}{lists}}],
            [read_file("$tmp/base-list"), read_file("$tmp/app-list")], 'both exact protected lists remain bound');
        if ($scope ne 'all') {
            rejects(sub { xCAT::FreeBSDPackagePlan::inspect_image($published->{path}, $root, $image); },
                qr/Image[ ]package[ ]scope[ ]differs/x, 'scoped plan cannot satisfy a full installation request');
        }
        my $archives = $fixture->new_directory();
        chmod(oct('0700'), $archives) or croak $!;
        my $staged = xCAT::FreeBSDPackagePlan::stage_archives($bound->{bytes}, $root, $archives);
        is($staged->{packages}, scalar(@{$expected{$scope}}), 'payload contains only the scoped closure');
        for my $package (@{$bound->{plan}{packages}}) {
            is(sha256_hex(read_file("$archives/$package->{id}.pkg")), $package->{sha256}, 'staged package matches imported bytes');
        }
        chmod(oct('0700'), $archives) or croak $!;
    }
};

sub scoped_binding_cases {
    subtest 'scope remains bound when image roots alone would match' => sub {
        write_file("$tmp/minimal-list", '');
        my %minimal = (%$image, pkglist => "$tmp/minimal-list");
        for my $choice (qw(base applications)) {
            my %definition = (%minimal, $choice eq 'base' ? (otherpkglist => '') : ());
            my $published = xCAT::FreeBSDPackagePlan::publish_image(installroot => $root,
                image => \%definition, tool => $tool, solver => $solver, scope => $choice);
            rejects(sub { xCAT::FreeBSDPackagePlan::inspect_image($published->{path}, $root, \%definition); },
                qr/Image[ ]package[ ]scope[ ]differs/x, 'an update scope cannot become an installation through empty image lists');
            my $legacy = $published->{bytes};
            $legacy =~ s/\Aformat\txcat-freebsd-package-plan-2\n/format\txcat-freebsd-package-plan-1\n/x;
            rejects(sub { xCAT::FreeBSDPackagePlan::parse($legacy); }, qr/(?:Noncanonical|Invalid)/x,
                'a scoped plan cannot use the installation wire format');
        }
    };

    subtest 'empty applications retain verified provenance without selecting packages' => sub {
        my %definition = (%$image, otherpkglist => '');
        my $published = eval { xCAT::FreeBSDPackagePlan::publish_image(installroot => $root,
            image => \%definition, tool => $tool, solver => $solver, scope => 'applications'); };
        my $error = $@;
        ok($published, 'an empty application operation publishes') or diag($error);
        return unless $published;
        is_deeply($published->{plan}{packages}, [], 'the empty operation does not fall back to base packages');
        is_deeply($published->{request}{components}, ['base'], 'unselected base intent remains in provenance');
        is_deeply($published->{request}{applications}, [], 'the request explicitly has no application roots');
        is($published->{request}{scope}, 'applications', 'empty operations retain their scope');
        is_deeply($published->{plan}{repositories}, $full->{repositories}, 'all repository identities and trust remain verified');
        my $archives = $fixture->new_directory();
        chmod(oct('0700'), $archives) or croak $!;
        my $staged = xCAT::FreeBSDPackagePlan::stage_archives($published->{bytes}, $root, $archives);
        is_deeply([@$staged{qw(packages bytes)}], [0, 0], 'empty operations stage zero payload bytes');
        chmod(oct('0700'), $archives) or croak $!;
        for my $client (qw(tool solver)) {
            my %invalid = %{ $client eq 'tool' ? $tool : $solver };
            $invalid{sha256} = '0' x 64;
            rejects(sub { xCAT::FreeBSDPackagePlan::publish_image(installroot => $root,
                    image => \%definition, tool => $tool, solver => $solver, scope => 'applications',
                    $client => \%invalid); }, qr/(?:checksum|digest)/x,
                'empty operations still require the pinned native client');
        }
        for my $change (
            sub { $_[0] =~ s/^scope\tapplications\n//mx; },
            sub { $_[0] =~ s/^scope\tapplications\n/scope\tbase\n/mx; },
            sub { $_[0] =~ s/^scope\tapplications\n/scope\tall\n/mx; },
        ) {
            my $bytes = $published->{bytes};
            $change->($bytes);
            rejects(sub { xCAT::FreeBSDPackagePlan::parse($bytes); }, qr/(?:selection|scoped[ ]package[ ]plan)/x,
                'zero packages cannot satisfy a missing or different scope');
        }
        if (defined($ENV{XCAT_FREEBSD_SCOPE_EVIDENCE})) {
            write_file("$ENV{XCAT_FREEBSD_SCOPE_EVIDENCE}/empty.plan", $published->{bytes});
            write_file("$ENV{XCAT_FREEBSD_SCOPE_EVIDENCE}/empty.request.json", $json->encode($published->{request}));
        }
    };
    return;
}

scoped_binding_cases();

ok(!-e "$tmp/package-script-executed", 'planning and staging execute no package scripts');
ok(!-e '/var/db/pkg' && !-l '/var/db/pkg', 'planning and staging create no default package database');
is(sha256_hex(read_file($tool->{path})), $tool->{sha256}, 'native package tool is unchanged');
is(sha256_hex(read_file($solver->{path})), $solver->{sha256}, 'native resolver is unchanged');
done_testing();
