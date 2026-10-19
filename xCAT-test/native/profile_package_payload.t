#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
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
for my $source (@assets) {
    my $relative = substr($source, length($share) + 1);
    my $delivered = "$root/opt/xcat/share/xcat/$relative";
    ok(-r $delivered, "$relative is readable after extraction") or next;
    is(read_binary($delivered), read_binary($source), "$relative retains its complete contents");
    is(sprintf('%04o', S_IMODE((stat($delivered))[2])), $source =~ /\.postinstall$/ ? '0755' : '0644',
        "$relative has the packaged permissions");
}
my ($status, $output) = run_command($^X,
    repo_path('xCAT-test/unit/profile_customization.t'), "$root/opt/xcat");
is($status, 0, 'packaged profiles resolve and remain independently customizable') or diag($output);

if (!-f '/etc/debian_version') {
    local $ENV{fsm} = 1;
    my $reduced = tempdir(CLEANUP => 1);
    my $rpm = XCAT::Test::RPM->build('xCAT-server', 1);
    XCAT::Test::Lifecycle::checked('bash', '-o', 'pipefail', '-c',
        'cd "$1" && rpm2cpio "$2" | cpio -idm --quiet', 'bash', $reduced, $rpm);
    ok(!-e "$reduced/opt/xcat/share/xcat/install", 'the reduced RPM omits install profiles');
    ok(!-e "$reduced/opt/xcat/share/xcat/netboot/rh", 'the reduced RPM omits RHEL netboot profiles');
    for my $source (glob "$share/netboot/rocky/*.riscv64.*") {
        my $relative = substr($source, length($share) + 1);
        my $delivered = "$reduced/opt/xcat/share/xcat/$relative";
        ok(-r $delivered, "reduced RPM: $relative still resolves") or next;
        is(read_binary($delivered), read_binary($source),
            "reduced RPM: $relative retains its complete contents");
        is(sprintf('%04o', S_IMODE((stat($delivered))[2])), $source =~ /\.postinstall$/ ? '0755' : '0644',
            "reduced RPM: $relative has the packaged permissions");
    }
}

done_testing();
