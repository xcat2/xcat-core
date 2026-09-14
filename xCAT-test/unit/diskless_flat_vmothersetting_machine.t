#!/usr/bin/perl
# reg_linux_diskless_installation_flat corrupts the KVM machine type of the compute node, checks
# that the node fails to boot, and then restores it. The restore reads a machine type from a ladder
# that names ppc64 and x86_64 only, so on any other architecture it writes an empty vmothersetting
# and the check after it fails.
#
# The two commands are lifted out of the case file and RUN, with lsdef and chdef shadowed, so the
# assertions read the value the case would write. die when an extraction stops matching, so a
# rewrite fails loudly instead of covering nothing.
use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);

my $case = dirname(__FILE__)
    . '/../autotest/testcase/installation/reg_linux_diskless_installation_flat';
open my $fh, '<', $case or die("cannot read $case: $!");
my @lines = <$fh>;
close $fh;

# The command that restores the machine type, and the one that removes it again afterwards.
my ($restore) = grep { /^cmd:.*str2="machine:invalid".*chdef \$\$CN vmothersetting=\$str5/ } @lines;
my ($remove)  = grep { /^cmd:.*str2=";".*=~ "ppc64".*chdef \$\$CN vmothersetting=/ } @lines;
die('cannot find the command that restores the machine type') unless $restore;
die('cannot find the command that removes the machine type')  unless $remove;

# Render one command the way xcattest does, then run it with lsdef and chdef shadowed. bash
# resolves a function ahead of PATH, so the case's own backticks read the stub.
my $run = sub {
    my ($cmd, $arch, $lsdef_value) = @_;
    $cmd =~ s/^cmd://;
    $cmd =~ s/__GETNODEATTR\(\$\$CN,arch\)__/$arch/g;
    $cmd =~ s/__GETNODEATTR\(\$\$CN,mgt\)__/kvm/g;
    $cmd =~ s/\$\$CN/cn1/g;
    my $prelude = "lsdef() { echo '    vmothersetting=$lsdef_value'; }\n"
                . "chdef() { echo \"CHDEF:\$*\"; }\n";
    my $out = qx{bash -c @{[ quotemeta_cmd($prelude . $cmd) ]} 2>&1};
    my ($written) = $out =~ /^CHDEF:cn1 vmothersetting=(.*)$/m;
    return { out => $out, written => $written, rc => $? >> 8 };
};

sub quotemeta_cmd { my ($s) = @_; $s =~ s/'/'\\''/g; return "'$s'" }

# The machine type each architecture must end up with. riscv64 guests run the qemu "virt" machine;
# kvm.pm sets it in guest_arch_profile.
my %machine = (
    ppc64le => 'pseries',
    x86_64  => 'pc',
    riscv64 => 'virt',
);

for my $arch (sort keys %machine) {
    my $r = $run->($restore, $arch, 'machine:invalid');
    ok( defined $r->{written} && length $r->{written},
        "$arch: the restore writes a vmothersetting rather than an empty one" );
    like( $r->{written} // '', qr/\bmachine:/,
        "$arch: the restored vmothersetting names a machine type" );
    like( $r->{written} // '', qr/\Q$machine{$arch}\E/,
        "$arch: the restored machine type is $machine{$arch}" );

    # The check the case runs straight after the restore.
    my $keeps_machine = ( $r->{written} // '' ) =~ /machine/ ? 0 : 1;
    is( $keeps_machine, 0,
        "$arch: the check after the restore, 'vmothersetting contains machine', passes" );

    # The remove path reads the same ladder; it must not die on an empty str3.
    my $d = $run->($remove, $arch, "machine:$machine{$arch}");
    unlike( $d->{out}, qr/unary operator expected/,
        "$arch: the remove path compares two defined strings" );
}

done_testing();
