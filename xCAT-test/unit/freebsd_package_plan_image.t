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
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
plan(skip_all => 'Image plan fixtures require Linux container root') unless $^O eq 'linux' && $> == 0;

my $tmp = abs_path(tempdir(CLEANUP => 1, DIR => '/tmp'));
local $ENV{XCATROOT} = abs_path("$FindBin::Bin/../..");
local $ENV{XCATCFG} = "$tmp/xcatcfg";
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
    my (@arguments) = @_;
    return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments);
}

sub identity {
    my ($index, $name, $version, $origin) = @_;
    return { repository => $index, identity => [$name, $version, $origin, 'FreeBSD:15:amd64'] };
}

sub rejected {
    my ($operation, $pattern, $description) = @_;
    my $result;
    my $ok = eval { $result = $operation->(); 1; };
    my $error = $@;
    ok(!$ok && !defined($result), $description);
    like($error, $pattern, "$description reports the cause");
    return;
}

make_path("$tmp/empty", "$tmp/repos", "$tmp/xcatcfg");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
$tool->{sha256} = sha256_hex(read_file($tool->{path}));
my $root = $fixture->new_directory();
my ($dvd, $disc, $supplement, $base, $mixed);
subtest 'actual native repositories and published plans' => sub {
    is(run_pkg('-v'), "2.8.2\n", 'fixtures use native pkg 2.8.2');
    ok(!-e '/var/db/pkg', 'default package database is absent');
    for my $pair ([$dvd = {}, 1], [$disc = {}, 0]) {
        my $source = $fixture->release_tree($pair->[1]);
        %{$pair->[0]} = %{xCAT::FreeBSDRepoImport::import_release($source, $root,
            tool => $tool, trust => { type => 'operator-trusted-release',
                digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} })};
    }
    my $source = $fixture->repository(0, [
        ['bind-dep'], ['bind-app', deps => { 'bind-dep' => { origin => 'misc/bind-dep', version => '1' } }],
    ]);
    $supplement = xCAT::FreeBSDRepoImport::import_repository($source, $root, tool => $tool,
        trust => { type => 'operator-trusted-tree', digest => xCAT::FreeBSDRepo::snapshot_tree($source)->{digest} });
    my $resolver = { version => '2.8.2', sha256 => $tool->{sha256} };
    $resolver->{library_digest} = $tool->{library_digest} if exists($tool->{library_digest});
    my @selected = map { identity(0, $_, '15.1', "base/$_") }
      qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base);
    push @selected, identity(0, 'pkg', '2.6.2_1', 'ports-mgmt/pkg');
    my %options = (installroot => $root, resolver => $resolver, components => ['base', 'kernel'],
        repositories => [{ publication => $dvd->{path}, role => 'base' }], selected => \@selected, applications => []);
    $base = xCAT::FreeBSDPackagePlan::publish(xCAT::FreeBSDPackagePlan::compose(%options), $root);
    my $dvd_app = identity(1, 'application', '1', 'misc/application');
    my $app = identity(2, 'bind-app', '1', 'misc/bind-app');
    $mixed = xCAT::FreeBSDPackagePlan::publish(xCAT::FreeBSDPackagePlan::compose(%options,
        repositories => [@{$options{repositories}}, { publication => $dvd->{path}, role => 'applications' },
            { publication => $supplement->{path}, role => 'repository' }],
        selected => [@selected, $dvd_app, $app, identity(2, 'bind-dep', '1', 'misc/bind-dep')],
        applications => [$app, $dvd_app]), $root);
    is($dvd->{native_validated}, 1, 'DVD publication has actual native validation');
    is($supplement->{native_validated}, 1, 'supplemental publication has actual native validation');
    isnt($disc->{digest}, $dvd->{digest}, 'alternate base publication is a distinct input');
    is(xCAT::FreeBSDPackagePlan::inspect($mixed->{path}, $root)->{digest}, $mixed->{digest},
        'ordinary inspection verifies the published mixed plan');
    done_testing();
};

my $sequence = 0;
sub image {
    my $mixed_image = shift;
    my $lists = "$tmp/lists-" . ++$sequence;
    write_file("$lists/base", "# source A\nbase\n");
    write_file("$lists/kernel", "kernel\n");
    my $image = { imagetype => 'freebsd', osvers => 'freebsd15.1', osarch => 'x86_64',
        provmethod => 'install', osname => 'FreeBSD', imageversion => '2',
        bootdir => "$tmp/boot", pkgdir => "$dvd->{path}/base", pkglist => "$lists/base,$lists/kernel" };
    if ($mixed_image) {
        write_file("$lists/first", "# application roots\nbind-app\n");
        write_file("$lists/last", "application\n");
        $image->{otherpkgdir} = "$dvd->{path}/applications,$supplement->{path}/repository";
        $image->{otherpkglist} = "$lists/first,$lists/last";
    }
    return $image;
}

sub inspect_image {
    my ($published, $definition) = @_;
    return xCAT::FreeBSDPackagePlan::inspect_image($published->{path}, $root, $definition);
}

sub selection_cases {
    subtest 'bind existing plans without converting dependencies to roots' => sub {
        my $definition = image(1);
        my $before = $json->encode($definition);
        my $plain = xCAT::FreeBSDPackagePlan::inspect($mixed->{path}, $root);
        my $bound = inspect_image($mixed, $definition);
        is_deeply({ map { $_ => $bound->{$_} } qw(digest relative path plan) }, $plain,
            'binding retains every ordinary inspection result');
        is_deeply($bound->{request}{image}, $definition, 'binding retains the exact relevant image fields');
        is_deeply($bound->{request}{components}, ['base', 'kernel'], 'components retain requested order');
        is_deeply($bound->{request}{applications}, ['bind-app', 'application'], 'only explicit roots retain requested order');
        is_deeply([map { $_->{role} } @{$bound->{request}{repositories}}],
            [qw(base applications repository)], 'repository roles retain request order');
        is_deeply([map { $_->{publication} } @{$bound->{request}{repositories}}],
            [$dvd->{path}, $dvd->{path}, $supplement->{path}], 'role paths bind canonical publications');
        ok(scalar(grep { $_->{name} eq 'bind-dep' } @{$bound->{plan}{packages}}), 'actual dependency remains in the plan');
        ok(!scalar(grep { $_ eq 'bind-dep' } @{$bound->{request}{applications}}), 'dependency is not an explicit request');
        is($json->encode($definition), $before, 'binding does not mutate the caller image');
        my @paths = (split(/,/x, $definition->{pkglist}), split(/,/x, $definition->{otherpkglist}));
        is(scalar(@{$bound->{request}{lists}}), 4, 'each protected list has one retained observation');
        for my $index (0 .. $#paths) {
            my $bytes = read_file($paths[$index]);
            is_deeply($bound->{request}{lists}[$index],
                { field => $index < 2 ? 'pkglist' : 'otherpkglist', path => $paths[$index],
                    bytes => $bytes, size => length($bytes), sha256 => sha256_hex($bytes) },
                "list $index binds exact bytes, path and source field");
        }
        my $base_image = image(0);
        is_deeply(inspect_image($base, $base_image)->{request}{applications}, [],
            'base-only image has no invented application request');
        $base_image->{otherpkgdir} = '';
        $base_image->{otherpkglist} = '';
        is_deeply(inspect_image($base, $base_image)->{request}{applications}, [],
            'explicit empty optional fields retain the existing parser meaning');
        my ($first) = split(/,/x, $definition->{pkglist});
        write_file($first, "# source B\nbase\n");
        my $changed = inspect_image($mixed, $definition);
        is($changed->{digest}, $bound->{digest}, 'a stable comment change need not change plan semantics');
        isnt($changed->{request}{lists}[0]{sha256}, $bound->{request}{lists}[0]{sha256},
            'a stable same-size comment change has distinct request provenance');
        is(length($changed->{request}{lists}[0]{bytes}), length($bound->{request}{lists}[0]{bytes}),
            'the provenance near-miss preserves byte count');
        is(xCAT::FreeBSDPackagePlan::inspect_image($mixed->{path}, "$root//", $definition)->{digest},
            $mixed->{digest}, 'install root normalization matches ordinary inspection');
        done_testing();
    };

    subtest 'reject different ordered repository identities' => sub {
        for my $case (
            [sub { $_[0]{pkgdir} = "$disc->{path}/base"; }, 'another valid base publication'],
            [sub { $_[0]{otherpkgdir} = "$supplement->{path}/repository,$dvd->{path}/applications"; }, 'reordered supplemental repositories'],
            [sub { $_[0]{otherpkgdir} = "$dvd->{path}/repository,$supplement->{path}/repository"; }, 'wrong role under the same publication'],
            [sub { $_[0]{otherpkgdir} = "$dvd->{path}/applications"; }, 'missing supplemental repository'],
            [sub { $_[0]{pkgdir} = "$tmp/unrelated/$dvd->{digest}/base"; }, 'same digest under another parent'],
        ) {
            my $definition = image(1);
            $case->[0]->($definition);
            rejected(sub { inspect_image($mixed, $definition) }, qr/Image[ ]repositories[ ]differ/x, $case->[1]);
        }
        done_testing();
    };

    subtest 'reject different ordered component roots' => sub {
        for my $case (
            ["minimal\nkernel\n", 'different base component'],
            ["kernel\nbase\n", 'reordered base components'],
            ["base\n", 'missing base component'],
        ) {
            my $definition = image(1);
            my ($first, $final_path) = split(/,/x, $definition->{pkglist});
            write_file($first, $case->[0]);
            write_file($final_path, '');
            rejected(sub { inspect_image($mixed, $definition) }, qr/Image[ ]components[ ]differ/x, $case->[1]);
        }
        done_testing();
    };

    subtest 'reject different explicit application roots' => sub {
        for my $case (
            ["application\nbind-app\n", 'reordered explicit application roots'],
            ["bind-app\napplication\nbind-dep\n", 'closure dependency promoted to explicit root'],
            ["bind-app\n", 'missing explicit application root'],
            ["unavailable-private-root\napplication\n", 'unselected application root'],
        ) {
            my $definition = image(1);
            my ($first, $final_path) = split(/,/x, $definition->{otherpkglist});
            write_file($first, $case->[0]);
            write_file($final_path, '');
            my $message = 'FreeBSD package plan: Image application roots differ from the published plan';
            rejected(sub { inspect_image($mixed, $definition) }, qr/\A\Q$message\E\n\z/x,
                $case->[1]);
        }
        done_testing();
    };

    return;
}

sub admission_cases {
    subtest 'reuse image admission and the protected list parser' => sub {
        for my $case (
            [sub { return []; }, qr/image[ ]definition/x, 'non-hash image'],
            [sub { $_[0]{imageversion} = '1'; return $_[0]; }, qr/imageversion=2/x, 'legacy image version'],
            [sub { $_[0]{osarch} = 'aarch64'; return $_[0]; }, qr/osarch=x86_64/x, 'wrong architecture'],
            [sub { $_[0]{osname} = 'Linux'; return $_[0]; }, qr/osname=FreeBSD/x, 'wrong operating system'],
            [sub { $_[0]{provmethod} = 'netboot'; return $_[0]; }, qr/provmethod=install/x, 'unsupported provisioning method'],
            [sub { $_[0]{pkgdir} = []; return $_[0]; }, qr/path[ ]string/x, 'reference-valued repository path'],
            [sub { delete($_[0]{pkglist}); return $_[0]; }, qr/pkglist[ ]requires[ ]a[ ]path/x, 'missing required list'],
            [sub { $_[0]{pkglist} .= ','; return $_[0]; }, qr/canonical[ ]absolute[ ]paths/x, 'empty list path member'],
            [sub { $_[0]{otherpkglist} = $_[0]{pkglist}; return $_[0]; }, qr/Duplicate[ ]package[ ]list[ ]source/x, 'same source in both list fields'],
        ) {
            my $definition = $case->[0]->(image(1));
            rejected(sub { inspect_image($mixed, $definition) }, $case->[1], $case->[2]);
        }
        for my $case (
            ["base\nbase\n", qr/Duplicate[ ]package[ ]list[ ]root/x, 'duplicate root'],
            ["base\r\n", qr/LF[ ]line[ ]endings/x, 'CRLF list'],
            ['base', qr/final[ ]LF/x, 'missing final LF'],
            ["\xff\n", qr/Invalid[ ]package[ ]list[ ]UTF-8/x, 'invalid UTF-8'],
            ["#INCLUDE:elsewhere\n", qr/Unsupported[ ]package[ ]list[ ]directive/x, 'include directive'],
            [" #ENV:private=value\n", qr/Unsupported[ ]package[ ]list[ ]directive/x, 'environment directive'],
            ["#NEW_INSTALL_LIST#\n", qr/Unsupported[ ]package[ ]list[ ]directive/x, 'install-list directive'],
        ) {
            my $definition = image(1);
            my ($path) = split(/,/x, $definition->{pkglist});
            write_file($path, $case->[0]);
            rejected(sub { inspect_image($mixed, $definition) }, $case->[1], $case->[2]);
        }
        for my $case (
            [sub { chmod(oct('0666'), $_[0]) or croak $!; }, qr/protected[ ]bounded[ ]regular[ ]file/x, 'writable list'],
            [sub { my $path = shift; rename($path, "$path-real") or croak $!; symlink("$path-real", $path) or croak $!; },
                qr/protected[ ]bounded[ ]regular[ ]file/x, 'symlinked list'],
        ) {
            my $definition = image(1);
            my ($path) = split(/,/x, $definition->{pkglist});
            $case->[0]->($path);
            rejected(sub { inspect_image($mixed, $definition) }, $case->[1], $case->[2]);
        }
        rejected(sub { xCAT::FreeBSDPackagePlan::inspect_image($mixed->{path}, $root) },
            qr/requires[ ]a[ ]path,[ ]install[ ]root[ ]and[ ]image/x, 'missing image argument');
        rejected(sub { xCAT::FreeBSDPackagePlan::inspect_image($mixed->{path}, $root, image(1), 'extra') },
            qr/Invalid[ ]package[ ]selection[ ]scope/x, 'invalid scope argument');
        rejected(sub { xCAT::FreeBSDPackagePlan::inspect_image($mixed->{path}, $root, image(1), 'all', 'extra') },
            qr/requires[ ]a[ ]path,[ ]install[ ]root[ ]and[ ]image/x, 'extra argument');
        done_testing();
    };

    return;
}

sub drift_cases {
    subtest 'reject observed request drift across actual inspection' => sub {
        for my $case (
            [sub { write_file($_[0], "# source B\nbase\n"); }, qr/request[ ]changed/x, 'same-size comment drift'],
            [sub { write_file($_[0], "minimal\n"); }, qr/request[ ]changed/x, 'root bytes drift'],
            [sub { $_[1]{bootdir} = "$tmp/another-boot"; }, qr/request[ ]changed/x, 'image field drift'],
            [sub { my ($path, $definition) = @_; write_file("$path-copy", read_file($path));
                $definition->{pkglist} =~ s/\Q$path\E/$path-copy/x; }, qr/request[ ]changed/x, 'path drift with identical list bytes'],
            [sub { chmod(oct('0666'), $_[0]) or croak $!; }, qr/protected[ ]bounded[ ]regular[ ]file/x, 'list protection lost'],
            [sub { unlink($_[0]) or croak $!; }, qr/protected[ ]bounded[ ]regular[ ]file/x, 'list removed'],
        ) {
            my $definition = image(1);
            my ($path) = split(/,/x, $definition->{pkglist});
            my $reader = \&xCAT::FreeBSDRepoImport::read_protected_file;
            my $injected = 0;
            {
                local *xCAT::FreeBSDRepoImport::read_protected_file = gensym();
                *xCAT::FreeBSDRepoImport::read_protected_file = sub {
                    my @arguments = @_;
                    my $bytes = $reader->(@arguments);
                    if ($arguments[0] eq $path && !$injected) {
                        ++$injected;
                        $case->[0]->($path, $definition);
                    }
                    return $bytes;
                };
                rejected(sub { inspect_image($mixed, $definition) }, $case->[1], $case->[2]);
            }
            is($injected, 1, "$case->[2] follows one actual protected read");
        }
        done_testing();
    };

    return;
}

sub readback_cases {
    subtest 'retain ordinary plan and repository verification' => sub {
        my $definition = image(1);
        my $plan_bytes = read_file($mixed->{path});
        my @plan_state = stat($mixed->{path});
        chmod(oct('0600'), $mixed->{path}) or croak $!;
        write_file($mixed->{path}, $plan_bytes . "\n");
        chmod(oct('0444'), $mixed->{path}) or croak $!;
        rejected(sub { inspect_image($mixed, $definition) }, qr/Plan[ ]path[ ]and[ ]checksum[ ]differ/x, 'altered published plan');
        chmod(oct('0600'), $mixed->{path}) or croak $!;
        write_file($mixed->{path}, $plan_bytes);
        utime($plan_state[8], $plan_state[9], $mixed->{path}) or croak $!;
        chmod(oct('0444'), $mixed->{path}) or croak $!;
        my $plain = xCAT::FreeBSDPackagePlan::inspect($mixed->{path}, $root);
        my ($package) = grep { $_->{name} eq 'bind-app' } @{$plain->{plan}{packages}};
        my $path = "$supplement->{path}/$package->{path}";
        my $archive = read_file($path);
        my @archive_state = stat($path);
        chmod(oct('0600'), $path) or croak $!;
        write_file($path, 'corrupt');
        chmod(oct('0444'), $path) or croak $!;
        rejected(sub { inspect_image($mixed, $definition) }, qr/(?:publication|repository|file)/ix, 'altered imported archive');
        chmod(oct('0600'), $path) or croak $!;
        write_file($path, $archive);
        utime($archive_state[8], $archive_state[9], $path) or croak $!;
        chmod(oct('0444'), $path) or croak $!;
        is(inspect_image($mixed, $definition)->{digest}, $mixed->{digest}, 'restored actual bytes verify again');
        is(read_file($mixed->{path}), $plan_bytes, 'inspection leaves canonical plan bytes unchanged');
        ok(!-e "$tmp/package-script-executed", 'no package script ran');
        ok(!-e '/var/db/pkg', 'no default package database was created');
        done_testing();
    };

    subtest 'retain bounded observations at the existing list limits' => sub {
        my $definition = image(0);
        my @paths;
        my @contents;
        for my $index (0 .. 7) {
            my $tail = $index ? "\n" : "\nbase\nkernel\n";
            my $bytes = '#' . ('x' x (1048576 - length($tail) - 1)) . $tail;
            my $path = "$tmp/bounded-lists/$index";
            write_file($path, $bytes);
            push @paths, $path;
            push @contents, $bytes;
        }
        $definition->{pkglist} = join(',', @paths);
        my $bound = inspect_image($base, $definition);
        is(scalar(@{$bound->{request}{lists}}), 8, 'eight bounded source files are retained');
        my $size = 0;
        $size += $_->{size} for @{$bound->{request}{lists}};
        is($size, 8388608, 'exact aggregate byte cap is admitted');
        ok($bound->{request}{lists}[0]{bytes} eq $contents[0], 'first exact-cap source bytes are retained');
        ok($bound->{request}{lists}[7]{bytes} eq $contents[7], 'last exact-cap source bytes are retained');
        is_deeply($bound->{request}{components}, ['base', 'kernel'], 'bounded comments do not become roots');
        is($bound->{request}{lists}[7]{sha256}, sha256_hex($contents[7]), 'last source digest describes its actual bytes');
        write_file($paths[7], $contents[7] . "\n");
        rejected(sub { inspect_image($base, $definition) }, qr/protected[ ]bounded[ ]regular[ ]file/x,
            'one byte beyond the per-file cap');
        write_file($paths[7], $contents[7]);
        write_file("$tmp/bounded-lists/extra", "\n");
        $definition->{pkglist} .= ",$tmp/bounded-lists/extra";
        rejected(sub { inspect_image($base, $definition) }, qr/Combined[ ]package[ ]list[ ]bytes[ ]exceed/x,
            'one byte beyond the aggregate cap');
        done_testing();
    };
    subtest 'retain canonical plan bytes for private preparation' => sub {
        my ($bound, $expected);
        for my $case ([$base, 0, 'base'], [$mixed, 1, 'mixed']) {
            $bound = inspect_image($case->[0], image($case->[1]));
            $expected = read_file($case->[0]{path});
            ok(defined($bound->{bytes}) && $bound->{bytes} eq $expected,
                "$case->[2] result retains exact published plan bytes");
            is(sha256_hex(defined($bound->{bytes}) ? $bound->{bytes} : ''), $bound->{digest},
                "$case->[2] retained bytes match the inspected digest");
            my $parsed = eval { xCAT::FreeBSDPackagePlan::parse($bound->{bytes}); };
            is_deeply($parsed, $bound->{plan}, "$case->[2] retained bytes use the existing public parser");
        }
        ok(!exists(xCAT::FreeBSDPackagePlan::inspect($mixed->{path}, $root)->{bytes}),
            'ordinary inspection retains its existing result fields');
        rename($mixed->{path}, "$mixed->{path}.retained") or croak $!;
        my $parsed = eval { xCAT::FreeBSDPackagePlan::parse($bound->{bytes}); };
        rename("$mixed->{path}.retained", $mixed->{path}) or croak $!;
        is_deeply($parsed, $bound->{plan}, 'retained bytes parse while the original plan is unavailable');
        $bound->{plan}{components}[0] = 'debug';
        ok(defined($bound->{bytes}) && $bound->{bytes} eq $expected,
            'changing the returned model does not change the retained bytes');
        ok(read_file($mixed->{path}) eq $expected, 'the fixture publication is restored unchanged');
        done_testing();
    };
    return;
}

my $commands = 0;
{
    local *xCAT::FreeBSDPkg::run_command = gensym();
    *xCAT::FreeBSDPkg::run_command = sub { ++$commands; croak 'Image binding attempted external execution'; };
    selection_cases();
    admission_cases();
    drift_cases();
    readback_cases();
}
is($commands, 0, 'binding and readback never invoke a native command or solver');
done_testing();
