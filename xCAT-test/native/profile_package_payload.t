#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
use File::Slurper qw(read_binary);
use Fcntl qw(S_IMODE);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Lifecycle;
use XCAT::Test::RPM;
use XCAT::Test::Process qw(run_command);

plan skip_all => 'requires Linux package tools' unless $^O eq 'linux';
die 'run package builds as an unprivileged user' unless $>;
my $root = tempdir(CLEANUP => 1);
if (-f '/etc/debian_version') {
    my $deb = XCAT::Test::Lifecycle::build_deb('xCAT-server');
    XCAT::Test::Lifecycle::checked('dpkg-deb', '-x', $deb, $root);
} else {
    my $rpm = XCAT::Test::RPM->build('xCAT-server', 1);
    XCAT::Test::Lifecycle::checked('bash', '-o', 'pipefail', '-c',
        'cd "$1" && rpm2cpio "$2" | cpio -idm --quiet', 'bash', $root, $rpm);
}
my $share = repo_path('xCAT-server/share/xcat');
my @assets = grep { /riscv64\./ }
    glob "$share/{install,netboot}/{rh,rocky}/*";
ok(@assets, 'finds the RISC-V profile assets');
my @ubuntu = glob "$share/{install,netboot}/ubuntu/*.pkglist";
ok(@ubuntu, 'finds the Ubuntu package lists');
push @assets, @ubuntu;
sub check_assets {
    my ($payload, $label, @sources) = @_;
    for my $source (@sources) {
        my $relative = substr($source, length($share) + 1);
        my $delivered = "$payload/opt/xcat/share/xcat/$relative";
        ok(-r $delivered, "$label$relative is readable after extraction") or next;
        is(read_binary($delivered), read_binary($source), "$label$relative retains its complete contents");
        is(sprintf('%04o', S_IMODE((stat($delivered))[2])), $source =~ /\.postinstall$/ ? '0755' : '0644',
            "$label$relative has the packaged permissions");
    }
}
check_assets($root, '', @assets);
my ($status, $output) = run_command($^X,
    repo_path('xCAT-test/unit/profile_customization.t'), "$root/opt/xcat");
is($status, 0, 'packaged profiles resolve and remain independently customizable') or diag($output);

my $netboot = "$root/opt/xcat/share/xcat/netboot";
for my $directory (qw(debian imgutils)) {
    my $helper = "$netboot/$directory/xCAT/ProfileUtils.pm";
    ok(-f $helper && !-l $helper, "$directory ships a regular profile helper") or next;
    is(sprintf('%04o', S_IMODE((stat($helper))[2])), '0644', "$directory helper is readable without write access for others");
}
for my $case (
    ['unit/imgutils_standalone.t', 'imgutils'],
    ['native/debian_genimage_profile_assets.t', 'debian'],
) {
    my ($test, $directory) = @$case;
    my ($rc, $result) = run_command($^X, repo_path("xCAT-test/$test"), "$netboot/$directory");
    is($rc, 0, "packaged $directory works when copied without sibling directories") or diag($result);
}

if (!-f '/etc/debian_version') {
    local $ENV{fsm} = 1;
    my $reduced = tempdir(CLEANUP => 1);
    my $rpm = XCAT::Test::RPM->build('xCAT-server', 1);
    XCAT::Test::Lifecycle::checked('bash', '-o', 'pipefail', '-c',
        'cd "$1" && rpm2cpio "$2" | cpio -idm --quiet', 'bash', $reduced, $rpm);
    ok(!-e "$reduced/opt/xcat/share/xcat/install", 'the reduced RPM omits install profiles');
    ok(!-e "$reduced/opt/xcat/share/xcat/netboot/rh", 'the reduced RPM omits RHEL netboot profiles');
    check_assets($reduced, 'reduced RPM: ', glob "$share/netboot/rocky/*.riscv64.*");
} else {
    my $fixture = tempdir(CLEANUP => 1);
    XCAT::Test::Lifecycle::checked('cp', '-a', repo_path('xCAT-server'), "$fixture/xCAT-server");
    my $profiles = "$fixture/xCAT-server/share/xcat";
    XCAT::Test::Lifecycle::checked('chmod', '-R', 'g+w', "$profiles/install", "$profiles/netboot");
    my $data = 'install/rh/compute.rhels10.riscv64.pkglist';
    my $postinstall = 'netboot/rocky/compute.rocky10.riscv64.postinstall';
    chmod(oct('0666'), "$profiles/$data") == 1 or die "chmod: $!";
    for my $mask ('0022', '0002', '0077') {
        subtest "Debian writable sources with umask $mask" => sub {
            my $previous = umask oct($mask);
            my $deb = XCAT::Test::Lifecycle::build_deb('xCAT-server', $fixture);
            umask $previous;
            my $staged = dirname($deb) . '/xCAT-server/share/xcat';
            for my $input ($profiles, $staged) {
                is(sprintf('%04o', S_IMODE((stat("$input/$data"))[2])), '0666',
                    'data source permissions survive staging and packaging');
                is(sprintf('%04o', S_IMODE((stat("$input/$postinstall"))[2])), '0775',
                    'postinstall source permissions survive staging and packaging');
            }
            my $payload = tempdir(CLEANUP => 1);
            XCAT::Test::Lifecycle::checked('dpkg-deb', '-x', $deb, $payload);
            check_assets($payload, '', @assets);
            for my $directory (qw(debian imgutils)) {
                my $helper = "$payload/opt/xcat/share/xcat/netboot/$directory/xCAT/ProfileUtils.pm";
                ok(-f $helper && !-l $helper, "$directory ships a regular helper with umask $mask");
                is(sprintf('%04o', S_IMODE((stat($helper))[2])), '0644',
                    "$directory helper retains readable permissions with umask $mask");
            }
            for my $path (qw(install install/rh netboot netboot/rocky netboot/ubuntu/genimage)) {
                is(sprintf('%04o', S_IMODE((stat("$payload/opt/xcat/share/xcat/$path"))[2])),
                    '0755', "$path remains executable without group or other write access");
            }
        };
    }
}

done_testing();
