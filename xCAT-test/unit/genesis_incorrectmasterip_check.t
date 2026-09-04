#!/usr/bin/env perl
# Run the nodeset_shell_incorrectmasterip check against a scratch tftp root, with the xCAT
# commands and the net tools shadowed.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $script = repo_path('xCAT-test/autotest/testcase/genesis/test.sh');
plan skip_all => 'genesis test.sh not found' unless -f $script;
plan tests => 5;

my $host_arch = `uname -m`;
chomp $host_arch;

# The case defined its node as ppc64le whatever the management node was, so nodeset could not
# find a genesis kernel for it on x86_64 and the case could never pass there.
my $run = run_check('xnba', write_boot_file => 1);
is($run->{status}, 0, 'the xnba check passes when nodeset writes the boot file')
    or diag($run->{output});
like($run->{chdef}, qr/\barch=\Q$host_arch\E\b/,
    'the test node is defined with the management node arch');
ok($host_arch eq 'ppc64le' || $run->{chdef} !~ /\barch=ppc64le\b/,
    'the test node arch is not pinned to ppc64le');

# A nodeset that writes nothing must fail the check, not pass it.
my $empty = run_check('xnba', write_boot_file => 0);
isnt($empty->{status}, 0, 'the check fails when nodeset writes no boot file');

# grub2 and petitboot read their configuration from other directories under the tftp root.
my $grub = run_check('grub2', write_boot_file => 1);
is($grub->{status}, 0, 'the grub2 check reads the grub2 directory')
    or diag($grub->{output});

#---
# run_check: run `test.sh --check <loader>` against a scratch tftp root. test.sh resets PATH,
# so the xCAT commands are shadowed with shell functions, which bash resolves first. The fake
# nodeset writes the boot file the check greps, so the assertion is on the check, not on xCAT.
#---
sub run_check {
    my ($loader, %opt) = @_;
    my $root = tempdir(CLEANUP => 1);
    my $tftp = "$root/tftpboot";
    make_path("$tftp/xcat/xnba/nodes", "$tftp/boot/grub2", "$tftp/petitboot");

    my $folder = $loader eq 'xnba'      ? "$tftp/xcat/xnba/nodes"
               : $loader eq 'petitboot' ? "$tftp/petitboot"
               :                          "$tftp/boot/grub2";
    my $write = $opt{write_boot_file}
        ? "printf 'xcatd=192.168.1.1:3001 destiny=shell\\n' > '$folder/testnode'"
        : ":";

    my $driver = "$root/driver.sh";
    write_text($driver, <<"DRIVER");
chdef() { echo "\$@" >> '$root/chdef.log'; }
lsdef() {
    if [ "\$1" = "-t" ] && [ "\$2" = "site" ]; then echo "clustersite: master=192.168.9.9"; return 0; fi
    echo "Object name: testnode"
}
ifconfig() { printf 'eth0: flags\\n        inet 192.168.9.9\\n\\n'; }
netstat() { printf 'Kernel\\nIface\\neth0\\neth1\\nlo\\n'; }
ip() { return 0; }
makenetworks() { return 0; }
tabdump() { return 0; }
makehosts() { return 0; }
rmdef() { return 0; }
nodeset() { $write; return 0; }
export TFTPDIR='$tftp'
. '$script' --check $loader
DRIVER

    my $out = `/bin/bash "$driver" 2>&1`;
    my $status = $? >> 8;
    my $chdef = -f "$root/chdef.log" ? read_text("$root/chdef.log") : '';
    return { status => $status, output => $out, chdef => $chdef };
}

