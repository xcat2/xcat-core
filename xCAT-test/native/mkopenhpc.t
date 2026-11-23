#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'requires Linux and root in the test sandbox' if $^O ne 'linux' || $>;

my $command = repo_path('xCAT-server/sbin/mkopenhpc');
my $postscript = repo_path('xCAT/postscripts/configopenhpc');
my $package_list = repo_path('xCAT/postscripts/openhpc.pkglist');
my $netboot_postinstall = repo_path('xCAT-server/share/xcat/scripts/openhpc-netboot-postinstall');
my $image = 'alma10.2-x86_64-install-ohpc';
my $state_path = '/var/lib/xcat/openhpc';

sub stub {
    my ($file, $body) = @_;
    write_binary($file, "#!/bin/bash\n$body");
    chmod 0755, $file or die "chmod $file: $!";
}

sub isolated {
    my ($root, $script, $env, @args) = @_;
    my ($code, $output) = sandbox_run($root, {
        read_only => { $script => '/command', $package_list => '/openhpc.pkglist' },
        writable => { "$root/var-lib" => '/var/lib' },
        env => $env,
    }, '/bin/bash', '/command', @args);
    return ($code, $output);
}

sub stub_lsdef {
    my ($root) = @_;
    stub("$root/xcat/bin/lsdef", <<'SH');
case "$*" in
    "-t osimage -o $4 -i osvers,osarch,provmethod,otherpkgdir,gpgcheck -c")
        cat /fixture/definition
        ;;
    '-t site -i installdir -c')
        echo 'clustersite: installdir=/fixture/custom-install'
        ;;
    *) exit 2 ;;
esac
SH
}

subtest 'registers and checks an eligible image' => sub {
    my $root = sandbox_root();
    make_path("$root/etc/munge", "$root/var-lib", "$root/xcat/bin");
    write_binary("$root/etc/xCATMN", '');
    write_binary("$root/etc/munge/munge.key", "fixture key\n");
    chmod 0400, "$root/etc/munge/munge.key" or die "chmod key: $!";
    stub_lsdef($root);
    stub("$root/xcat/bin/chdef", <<'SH');
printf '%s\n' "$*" >> /fixture/chdef
exit "${CHDEF_STATUS:-0}"
SH

    my @options = ('--image', $image, '--controller', 'slurmctl.example:6817');
    my %env = (XCATROOT => '/fixture/xcat');
    my $definition = "$image: osvers=alma10.2\n$image: osarch=x86_64\n$image: provmethod=install\n";
    write_binary("$root/definition", $definition =~ s/provmethod=install/provmethod=statelite/r);
    my ($code, $output) = isolated($root, $command, \%env, @options);
    isnt($code, 0, 'rejects statelite provisioning');
    like($output, qr/provmethod install or netboot/, 'explains the image requirement');

    write_binary("$root/definition", $definition);
    ($code, $output) = isolated($root, $command, \%env, @options, '--check');
    is($code, 0, 'preflight passes') or diag $output;
    ok(!-e "$root/var-lib/xcat", 'preflight leaves the filesystem untouched');
    ok(!-e "$root/chdef", 'preflight does not change the database');

    ($code, $output) = isolated($root, $command, \%env, @options);
    is($code, 0, 'registration succeeds') or diag $output;
    my $state = "$root/var-lib/xcat/openhpc";
    is(read_binary("$state/$image.controller"), "slurmctl.example:6817\n", 'writes the controller address');
    is(read_binary("$state/$image.synclist"),
        "$state_path/$image.controller -> $state_path/controller\n"
        . "/etc/munge/munge.key -> $state_path/munge.key\n", 'uses xCAT synchronization for the key');
    is(read_binary("$root/chdef"),
        "-p -t osimage -o $image synclists=$state_path/$image.synclist postbootscripts=configopenhpc\n",
        'updates the image with append semantics for both attributes');

    write_binary("$root/definition", $definition =~ s/osvers=alma10/osvers=rocky10/r);
    ($code, $output) = isolated($root, $command, \%env, @options);
    is($code, 0, 'also registers Rocky Linux 10 stateful') or diag $output;

    for my $release ('sp2', 'sp4') {
        write_binary("$root/definition", $definition =~ s/osvers=alma10\.2/osvers=openeuler24.03$release/r);
        ($code, $output) = isolated($root, $command, \%env, @options, '--check');
        is($code, 0, "accepts openEuler $release on x86_64") or diag $output;
        like($output, qr/experimental OpenHPC integration/, 'reports experimental support');
    }
    my $arm_euler = $definition =~ s/osvers=alma10\.2\n\Q$image\E: osarch=x86_64/osvers=openeuler24.03sp2\n$image: osarch=aarch64/r;
    write_binary("$root/definition", $arm_euler);
    ($code, $output) = isolated($root, $command, \%env, @options, '--check');
    isnt($code, 0, 'rejects the unqualified openEuler aarch64 path');

    write_binary("$root/definition", $definition);
    $env{CHDEF_STATUS} = 1;
    $options[-1] = 'changed.example';
    ($code, $output) = isolated($root, $command, \%env, @options);
    isnt($code, 0, 'propagates a failed xCAT registration');
    is(read_binary("$state/$image.controller"), "slurmctl.example:6817\n", 'keeps the configured controller on failure');
};

subtest 'registers netboot with image preparation and scoped boot-time sync' => sub {
    my $root = sandbox_root();
    make_path("$root/etc/munge", "$root/var-lib", "$root/xcat/bin", "$root/xcat/share/xcat/scripts",
        "$root/custom-install/postscripts");
    write_binary("$root/etc/xCATMN", '');
    write_binary("$root/etc/munge/munge.key", "fixture key\n");
    chmod 0400, "$root/etc/munge/munge.key" or die "chmod key: $!";
    stub_lsdef($root);
    stub("$root/xcat/bin/chdef", "printf '%s\\n' \"\$@\" > /fixture/chdef\n");
    stub("$root/xcat/share/xcat/scripts/openhpc-netboot-postinstall", "exit 0\n");

    my $netboot_image = 'rocky10.2-aarch64-netboot-ohpc';
    my @options = ('--image', $netboot_image, '--controller', 'slurmctl.example');
    my %env = (XCATROOT => '/fixture/xcat');
    my $definition = "$netboot_image: osvers=rocky10.2\n$netboot_image: osarch=aarch64\n$netboot_image: provmethod=netboot\n";
    write_binary("$root/definition", $definition);
    my ($code, $output) = isolated($root, $command, \%env, @options);
    isnt($code, 0, 'requires a node range for netboot');
    like($output, qr/specify the allowed compute node range/, 'explains the missing node range');

    push @options, '--nodes', 'cn[01-02]';
    ($code, $output) = isolated($root, $command, \%env, @options);
    isnt($code, 0, 'requires configured repositories for netboot');
    like($output, qr/configure trusted .* repositories in otherpkgdir/, 'explains the missing repositories');

    $definition .= "$netboot_image: otherpkgdir=https://repo.example/?pkg=OpenHPC\n";
    write_binary("$root/definition", $definition);
    ($code, $output) = isolated($root, $command, \%env, @options);
    isnt($code, 0, 'requires the shipped OpenHPC package list');
    like($output, qr{could not read the OpenHPC package list at /fixture/custom-install/postscripts/openhpc\.pkglist},
        'reads packages from the xCAT site install directory');
    write_binary("$root/custom-install/postscripts/openhpc.pkglist", read_binary($package_list));

    write_binary("$root/definition", $definition . "$netboot_image: gpgcheck=no\n");
    ($code, $output) = isolated($root, $command, \%env, @options);
    isnt($code, 0, 'rejects explicitly disabled package signature checks');
    like($output, qr/set gpgcheck=yes/, 'explains the signature requirement');

    write_binary("$root/definition", $definition);
    ($code, $output) = isolated($root, $command, \%env, @options);
    is($code, 0, 'registers Rocky Linux 10 aarch64 netboot') or diag $output;
    my $state = "$root/var-lib/xcat/openhpc";
    is(read_binary("$state/$netboot_image.synclist"),
        "$state_path/$netboot_image.controller -> (cn[01-02]) $state_path/controller\n"
        . "/etc/munge/munge.key -> (cn[01-02]) $state_path/munge.key\n",
        'qualifies both files so image synchronization skips them');
    is(read_binary("$state/$netboot_image.pkglist"), read_binary($package_list),
        'stages the runtime dependencies for genimage');
    is_deeply([split /\n/, read_binary("$root/chdef")], [
        '-p', '-t', 'osimage', '-o', $netboot_image,
        "synclists=$state_path/$netboot_image.synclist", "otherpkglist=$state_path/$netboot_image.pkglist",
        'postinstall=/fixture/xcat/share/xcat/scripts/openhpc-netboot-postinstall',
        'gpgcheck=yes', 'postbootscripts=configopenhpc netboot',
    ], 'appends netboot integration and enables package signature verification');

    write_binary("$root/definition", $definition . "$netboot_image: gpgcheck=1\n");
    ($code, $output) = isolated($root, $command, \%env, @options);
    is($code, 0, 'accepts an already enabled package signature check') or diag $output;
    unlike(read_binary("$root/chdef"), qr/gpgcheck=/, 'keeps an existing signature setting');

    my $euler = $definition =~ s/osvers=rocky10\.2\n\Q$netboot_image\E: osarch=aarch64/osvers=openeuler24.03sp4\n$netboot_image: osarch=x86_64/r;
    write_binary("$root/definition", $euler);
    ($code, $output) = isolated($root, $command, \%env, @options);
    is($code, 0, 'registers openEuler x86_64 in netboot mode') or diag $output;
};

subtest 'removes the package-generated key from netboot staging' => sub {
    my $root = sandbox_root();
    make_path("$root/target/rootimg/etc/munge", "$root/etc/munge", "$root/var-lib");
    write_binary("$root/target/rootimg/etc/munge/munge.key", "staging key\n");
    write_binary("$root/etc/munge/munge.key", "controller key\n");
    my ($code, $output) = isolated($root, $netboot_postinstall, {}, '/target/rootimg');
    is($code, 0, 'cleans the staging root') or diag $output;
    ok(!-e "$root/target/rootimg/etc/munge/munge.key", 'removes the staging key');
    is(read_binary("$root/etc/munge/munge.key"), "controller key\n", 'preserves the controller key');
    symlink('/etc/munge', "$root/target/rootimg/etc/bad-munge") or die "symlink: $!";
    rmdir "$root/target/rootimg/etc/munge" or die "rmdir: $!";
    rename "$root/target/rootimg/etc/bad-munge", "$root/target/rootimg/etc/munge" or die "rename: $!";
    ($code, $output) = isolated($root, $netboot_postinstall, {}, '/target/rootimg');
    isnt($code, 0, 'refuses a symlinked staging key directory');
    is(read_binary("$root/etc/munge/munge.key"), "controller key\n", 'still preserves the controller key');
};

subtest 'configures Slurm once and retries a failed update' => sub {
    my $root = sandbox_root();
    my $state = "$root/var-lib/xcat/openhpc";
    make_path($state, "$root/etc/munge", "$root/etc/sysconfig", "$root/etc/systemd/system");
    write_binary("$root/etc/os-release", "ID=almalinux\nVERSION_ID=\"10.2\"\n");
    write_binary("$root/etc/passwd", "munge:x:0:0::/:/bin/false\n");
    write_binary("$root/etc/group", "munge:x:0:\n");
    write_binary("$root/etc/nsswitch.conf", "passwd: files\ngroup: files\n");
    stub("$root/bin/uname", "echo x86_64\n");
    stub("$root/bin/restorecon", "exit 0\n");
    stub("$root/bin/dnf", "echo \"dnf \$*\" >> /fixture/calls\n");
    stub("$root/bin/rpm", "echo \"rpm \$*\" >> /fixture/calls\nexit \"\${RPM_STATUS:-0}\"\n");
    stub("$root/bin/systemctl", <<'SH');
echo "systemctl $*" >> /fixture/calls
if [[ $* == 'enable --now slurmd.service' && ${SLURMD_STATUS:-0} != 0 ]]; then
    exit "$SLURMD_STATUS"
fi
SH
    write_binary("$state/controller", "slurmctl.example\n");
    my ($code, $output) = isolated($root, $postscript, {});
    isnt($code, 0, 'requires the synced key before installing packages');
    ok(!-e "$root/calls", 'does not attempt to install packages or start services');

    write_binary("$state/munge.key", "fixture key\n");
    chmod 0400, "$state/munge.key" or die "chmod key: $!";
    ($code, $output) = isolated($root, $postscript, {});
    is($code, 0, 'applies the compute configuration') or diag $output;
    my $packages = join(' ', split /\n/, read_binary($package_list));
    like(read_binary("$root/calls"), qr/^dnf -y install \Q$packages\E$/m, 'installs the packages from the shared list');
    is((stat("$root/etc/munge/munge.key"))[2] & 0777, 0400, 'the installed key is private');
    is(read_binary("$root/etc/sysconfig/slurmd.xcat-openhpc"),
        "SLURMD_OPTIONS=\"--conf-server slurmctl.example\"\n", 'loads the controller using configless Slurm');
    like(read_binary("$root/calls"), qr/^systemctl enable --now munge\.service\nsystemctl enable --now slurmd\.service$/m,
        'starts MUNGE before Slurm');
    my $applied = read_binary("$state/applied");

    write_binary("$root/calls", '');
    ($code, $output) = isolated($root, $postscript, {});
    is($code, 0, 'reapplying succeeds') or diag $output;
    unlike(read_binary("$root/calls"), qr/daemon-reload|try-restart/, 'unchanged services are not restarted');

    write_binary("$state/controller", "new-controller.example\n");
    ($code, $output) = isolated($root, $postscript, { SLURMD_STATUS => 1 });
    isnt($code, 0, 'propagates an unsuccessful Slurm start');
    is(read_binary("$state/applied"), $applied, 'an unsuccessful update is not marked applied');
    write_binary("$root/calls", '');
    ($code, $output) = isolated($root, $postscript, {});
    is($code, 0, 'retry starts Slurm with the updated controller') or diag $output;
    like(read_binary("$root/calls"), qr/^systemctl try-restart slurmd\.service$/m, 'retry reapplies the service configuration');
    like(read_binary("$state/applied"), qr/^new-controller\.example$/m, 'records the successfully applied update');

    write_binary("$root/etc/os-release", "ID=rocky\nVERSION_ID=\"10.2\"\n");
    write_binary("$root/calls", '');
    ($code, $output) = isolated($root, $postscript, { RPM_STATUS => 1 }, 'netboot');
    isnt($code, 0, 'rejects a diskless image with missing packages');
    unlike(read_binary("$root/calls"), qr/dnf|systemctl/, 'does not install packages or start services on failure');
    ($code, $output) = isolated($root, $postscript, {}, 'netboot');
    is($code, 0, 'configures Rocky Linux 10 at diskless boot') or diag $output;
    like(read_binary("$root/calls"), qr/^rpm -q --quiet \Q$packages\E$/m, 'checks the packages baked into the image');
    unlike(read_binary("$root/calls"), qr/^dnf/m, 'never installs packages at diskless boot');

    for my $service_pack (2, 4) {
        write_binary("$root/etc/os-release", "ID=openEuler\nVERSION_ID=\"24.03\"\nVERSION=\"24.03 (LTS-SP$service_pack)\"\n");
        ($code, $output) = isolated($root, $postscript, {}, 'netboot');
        is($code, 0, "configures openEuler SP$service_pack at diskless boot") or diag $output;
    }
    write_binary("$root/etc/os-release", "ID=openEuler\nVERSION_ID=\"24.03\"\nVERSION=\"24.03 (LTS-SP3)\"\n");
    ($code, $output) = isolated($root, $postscript, {}, 'netboot');
    isnt($code, 0, 'rejects an openEuler service pack outside the experimental scope');
};

done_testing();
