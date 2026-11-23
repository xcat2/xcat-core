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
use Storable qw(dclone);
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::PostageFixture qw(fixture read_file write_file $root $custom);
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDInstall;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;
use xCAT::FreeBSDPostscript;

plan(skip_all => 'Update fixtures require Linux root') unless $^O eq 'linux' && $> == 0;
for my $variable (qw(XCAT_FREEBSD_NATIVE_PKG XCAT_FREEBSD_NATIVE_SOLVER XCAT_FREEBSD_NATIVE_LIBDIR)) {
    plan(skip_all => "Set $variable to the pinned native tool or library directory") unless defined($ENV{$variable});
}
umask 0077;
my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tables = fixture(1);
my $installroot = "$root/install";
my $tree = "$installroot/postscripts";
my $template = read_file($custom);
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}),
    library_directory => abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR}) };
my $solver = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_SOLVER}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C', LD_LIBRARY_PATH => $tool->{library_directory});

sub command {
    my (@arguments) = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@arguments, cwd => $tmp,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}
sub run_pkg { my @arguments = @_; return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments); }
sub fixture_write { my ($path, $bytes) = @_; make_path(dirname($path)); return write_file($path, $bytes); }

$tool->{sha256} = sha256_hex(read_file($tool->{path}));
$solver->{sha256} = sha256_hex(read_file($solver->{path}));
$tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&fixture_write);
my $release = $fixture->release_tree(0);
my $repository = "$release/usr/freebsd-packages/offline";
for my $name (qw(FreeBSD-ssh FreeBSD-bsdconfig FreeBSD-unused)) {
    $fixture->create_package("$repository/All", $name, version => '15.1', origin => "base/$name",
        annotations => { FreeBSD_version => '1501000' });
}
$fixture->create_package("$repository/All", 'FreeBSD-set-minimal', version => '15.1',
    origin => 'base/FreeBSD-set-minimal', annotations => { FreeBSD_version => '1501000' },
    deps => { 'FreeBSD-runtime' => { origin => 'base/FreeBSD-runtime', version => '15.1' } });
run_pkg('repo', $repository);
my $base = xCAT::FreeBSDRepoImport::import_release($release, $installroot, tool => $tool,
    trust => { type => 'operator-trusted-release', digest => xCAT::FreeBSDRepo::inspect_release_tree($release)->{digest} });
my $applications = $fixture->repository(0, [
    ['update-dep'], ['update-unused'],
    ['update-app', deps => { 'update-dep' => { origin => 'misc/update-dep', version => '1' } }],
]);
my $supplement = xCAT::FreeBSDRepoImport::import_repository($applications, $installroot, tool => $tool,
    trust => { type => 'operator-trusted-tree', digest => xCAT::FreeBSDRepo::snapshot_tree($applications)->{digest} });
write_file("$tmp/base-list", "base\n");
write_file("$tmp/app-list", "update-app\n");
write_file("$tmp/policy.json", $json->encode({ format => 'xcat-freebsd-import-policy-1',
    tool => $tool, solver => $solver, releases => {}, repositories => {} }));
$::XCATSITEVALS{freebsdimportpolicy} = "$tmp/policy.json";
@{$tables->{osimage}[0]}{qw(imagetype osname postscripts postbootscripts)} = ('freebsd', 'FreeBSD', 'custom', '');
$tables->{freebsdimage} = [{ imagename => 'image1', imageversion => '2', bootdir => "$tmp/boot",
    pkgdir => "$base->{path}/base", pkglist => "$tmp/base-list",
    otherpkgdir => "$supplement->{path}/repository", otherpkglist => "$tmp/app-list" }];
$tables->{postscripts} = [
    { node => 'xcatdefaults', postscripts => 'ospkgs', postbootscripts => '' },
    { node => 'node1', postscripts => '', postbootscripts => 'otherpkgs' },
];
my %stock = map { $_ => read_file("$FindBin::Bin/../../xCAT/postscripts/$_") }
  qw(ospkgs otherpkgs xcatpackages.freebsd);
for my $script (keys %stock) { write_file("$tree/$script", $stock{$script}); chmod(0700, "$tree/$script") or croak $!; }
write_file("$tree/custom", "#!/bin/sh\ntouch '$tmp/script-executed'\n");
chmod(0700, "$tree/custom") or croak $!;
my $installed = { phase => 'booted', generation => 'a' x 32, attempt => 'b' x 32 };
local *xCAT::FreeBSDInstall::state = gensym();
*xCAT::FreeBSDInstall::state = sub { return dclone($installed); };
my @base_names = sort qw(FreeBSD-bsdconfig FreeBSD-kernel-generic FreeBSD-runtime FreeBSD-set-base FreeBSD-set-minimal FreeBSD-ssh pkg);
my @app_names = qw(update-app update-dep);
my %expected = (base => \@base_names, applications => \@app_names, all => [sort(@base_names, @app_names)]);
my $sequence = 0;
sub store { return "$tmp/store-" . ++$sequence; }

sub prepare {
    my ($selection, @options) = @_;
    my $directory = store();
    my $export = xCAT::FreeBSDPostscript::prepare_update('node1', $selection, directory => $directory, @options);
    return ($export, $directory);
}

sub check_scope {
    my ($selection, $scope, $scripts, @options) = @_;
    my ($export, $directory) = prepare($selection, @options);
    my $path = "$directory/$export->{binding}{preparation}";
    my $plan = xCAT::FreeBSDPackagePlan::parse(read_file("$path/package.plan"));
    my $request = $json->decode(read_file("$path/package-request.json"));
    is($export->{binding}{package_mode}, defined($scope) ? 'update' : 'verify', 'export selects the intended package operation');
    is($request->{scope}, $scope, 'preparation retains the selected scope');
    is_deeply([sort map { $_->{name} } @{$plan->{packages}}], $expected{$scope || 'all'},
        'payload includes exactly the selected dependency closure');
    my $compiled = xCAT::FreeBSDPostscript::compile_execution($export->{binding}{preparation}, directory => $directory);
    is_deeply([map { pack('H*', $_->{raw}) } @{$compiled->{entries}}], $scripts,
        'the exported driver preserves selection, order and arguments');
    is_deeply(xCAT::FreeBSDPostscript::read_export($export->{binding}{run}, directory => $directory), $export,
        'retained export verifies');
    return ($export, $directory);
}

subtest 'explicit package scripts select their own dependency closures' => sub {
    check_scope('ospkgs', 'base', ['ospkgs']);
    check_scope('otherpkgs', 'applications', ['otherpkgs']);
    check_scope('./ospkgs,otherpkgs,ospkgs', 'all', ['./ospkgs', 'otherpkgs', 'ospkgs']);
    check_scope(q{"otherpkgs"}, 'applications', [q{"otherpkgs"}]);
    done_testing();
};

subtest 'installed-node updates export boot state after sealing' => sub {
    write_file("$root/tftp/xcat/xnba/nodes/node1", "#!gpxe\n#boot\n");
    write_file($custom, "NODESETSTATE=\$NSETSTATE\nexport NODESETSTATE\nUPDATENODE=0\n" . $template);
    my ($export, $directory) = prepare('custom');
    my $compiled = xCAT::FreeBSDPostscript::compile_execution(
        $export->{binding}{preparation}, directory => $directory);
    like($compiled->{driver}, qr/^NODESETSTATE=boot$/m, 'the delivered update exports the installed-node state');
    like($compiled->{driver}, qr/^UPDATENODE=1$/m, 'the update flag remains consistent with that state');
    write_file($custom, $template);
    write_file("$root/tftp/xcat/xnba/nodes/node1", "#!gpxe\n#install\n");
    done_testing();
};

subtest 'default and section selections use the rendered entries' => sub {
    check_scope('', 'all', ['ospkgs', 'custom', 'otherpkgs']);
    check_scope('defaults-postscripts-start-here', 'base', ['ospkgs']);
    check_scope('node-postbootscripts-start-here', 'applications', ['otherpkgs']);
    check_scope('osimage-postscripts-start-here', undef, ['custom']);
    my $changed = $template;
    $changed =~ s/[#]INCLUDE_POSTSCRIPTS_LIST[#]/otherpkgs/x;
    $changed =~ s/[#]INCLUDE_POSTBOOTSCRIPTS_LIST[#]//x;
    write_file($custom, $changed);
    check_scope('', 'applications', ['otherpkgs']);
    write_file($custom, $template);
    done_testing();
};

subtest 'administrator overrides retain their script and argument behavior' => sub {
    my $override = "#!/bin/sh\nexit 0\n";
    write_file("$tree/otherpkgs", $override);
    check_scope(q{otherpkgs --local 'two words'}, undef, [q{otherpkgs --local 'two words'}]);
    check_scope('ospkgs,otherpkgs --local', 'base', ['ospkgs', 'otherpkgs --local']);
    write_file("$tree/otherpkgs", $stock{otherpkgs});
    write_file("$tree/xcatpackages.freebsd", $override);
    check_scope('ospkgs --local', undef, ['ospkgs --local']);
    write_file("$tree/xcatpackages.freebsd", $stock{'xcatpackages.freebsd'});
    write_file("$tree/ospkgs", $stock{ospkgs} . "\n# Linux-only customization\n");
    check_scope('ospkgs', 'base', ['ospkgs']);
    write_file("$tree/ospkgs", $stock{ospkgs});
    rename("$tree/ospkgs", "$tree/stock-ospkgs") or croak $!;
    symlink('stock-ospkgs', "$tree/ospkgs") or croak $!;
    check_scope('ospkgs', 'base', ['ospkgs']);
    unlink("$tree/ospkgs") or croak $!;
    rename("$tree/stock-ospkgs", "$tree/ospkgs") or croak $!;
    done_testing();
};

subtest 'required software updates recognize the shipped adapters and reject a reduced operation' => sub {
    check_scope('ospkgs,otherpkgs', 'all', ['ospkgs', 'otherpkgs'], require_packages => 1);
    for my $adapter_name (qw(ospkgs otherpkgs xcatpackages.freebsd)) {
        for my $replacement ("#!/bin/sh\nexit 0\n",
            $adapter_name eq 'xcatpackages.freebsd' ? ($stock{$adapter_name} . "\n# Changed native adapter\n") : ()) {
            write_file("$tree/$adapter_name", $replacement);
            my $directory = store();
            my $native = \&xCAT::FreeBSDPkg::run_command;
            my $calls = 0;
            {
                local *xCAT::FreeBSDPkg::run_command = gensym();
                *xCAT::FreeBSDPkg::run_command = sub { ++$calls; return $native->(@_); };
                my $ok = eval { xCAT::FreeBSDPostscript::prepare_update('node1', 'ospkgs,otherpkgs',
                    directory => $directory, require_packages => 1); 1; };
                ok(!$ok, "$adapter_name override cannot silently reduce a software update");
                is($@, "FreeBSD software update requires the supplied ospkgs, otherpkgs and xcatpackages.freebsd adapters\n",
                    'rejection identifies the required adapter contract');
            }
            is($calls, 0, 'rejection precedes package resolution and archiving');
            is_deeply([glob("$directory/export-*")], [], 'rejection publishes no executable export');
            write_file("$tree/$adapter_name", $stock{$adapter_name});
        }
    }
    done_testing();
};

subtest 'empty application selection is an explicit update with no packages' => sub {
    local $tables->{freebsdimage}[0]{otherpkglist} = '';
    local $expected{applications} = [];
    my ($export) = check_scope('otherpkgs', 'applications', ['otherpkgs']);
    my $listing = command('/bin/tar', '-tf', $export->{archive}{path});
    unlike($listing, qr/[.]pkg\n/x, 'empty update exports no package archives');
    done_testing();
};

subtest 'stock package arguments fail before resolution or export' => sub {
    my $native = \&xCAT::FreeBSDPkg::run_command;
    my $calls = 0;
    local *xCAT::FreeBSDPkg::run_command = gensym();
    *xCAT::FreeBSDPkg::run_command = sub { ++$calls; return $native->(@_); };
    for my $selection ('ospkgs --repo unknown', q{otherpkgs ''}, 'custom,ospkgs -a', 'otherpkgs,ospkgs --flag') {
        my $directory = store();
        my $ok = eval { xCAT::FreeBSDPostscript::prepare_update('node1', $selection, directory => $directory); 1; };
        ok(!$ok, 'unsupported stock arguments are rejected');
        is($@, "FreeBSD package postscripts do not accept repository options\n",
            'rejection explains the argument contract');
        is_deeply([glob("$directory/export-*")], [], 'no executable export is published');
    }
    is($calls, 0, 'rejections run no package resolver or archiver');
    done_testing();
};

subtest 'source changes during resolution cannot replace the selected sealed scripts' => sub {
    my $native = \&xCAT::FreeBSDPkg::run_command;
    my $changed = 0;
    local *xCAT::FreeBSDPkg::run_command = gensym();
    *xCAT::FreeBSDPkg::run_command = sub {
        unless ($changed++) { write_file("$tree/otherpkgs", "#!/bin/sh\nexit 23\n"); }
        return $native->(@_);
    };
    my ($export, $directory) = check_scope('otherpkgs', 'applications', ['otherpkgs']);
    my $source = xCAT::FreeBSDPostscript::read_source($export->{source}, directory => $directory);
    my $manifest = $json->decode(read_file("$source->{directory}/manifest.json"));
    is($manifest->{entries}{unpack('H*', 'otherpkgs')}{sha256}, sha256_hex($stock{otherpkgs}),
        'export still binds the script used to choose the package scope');
    ok($changed, 'change was injected at the real native command boundary');
    write_file("$tree/otherpkgs", $stock{otherpkgs});
    done_testing();
};

subtest 'installation and image drift cannot publish an execution' => sub {
    for my $fault (qw(image installation)) {
        my $native = \&xCAT::FreeBSDPkg::run_command;
        my $changed = 0;
        my $directory = store();
        local $tables->{osimage}[0]{postscripts} = 'custom';
        local $installed->{attempt} = 'b' x 32;
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub {
            unless ($changed++) {
                $tables->{osimage}[0]{postscripts} = 'otherpkgs' if $fault eq 'image';
                $installed->{attempt} = 'c' x 32 if $fault eq 'installation';
            }
            return $native->(@_);
        };
        my $ok = eval { xCAT::FreeBSDPostscript::prepare_update('node1', 'ospkgs', directory => $directory); 1; };
        ok(!$ok, "$fault drift is rejected");
        like($@, qr/(?:context[ ]changed|Installation[ ]changed)/x, 'rejection identifies concurrent state change');
        is_deeply([glob("$directory/export-*")], [], 'no execution is exported after drift');
    }
    done_testing();
};

ok(!-e "$tmp/script-executed", 'preparation executes no selected script');
ok(!-e "$tmp/package-script-executed", 'resolution executes no package script');
ok(!-e '/var/db/pkg' && !-l '/var/db/pkg', 'default package database remains absent');
done_testing();
