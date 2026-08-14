#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: the xCAT node postscripts written in awk use gawk-only features -- the network
# coprocess (/inet/tcp, /inet/udp) and the two-way pipe operator "|&" -- which mawk does not
# implement.  On EL/SLES this works "by accident" because their default /usr/bin/awk is gawk,
# but Ubuntu/Debian default /usr/bin/awk to mawk, so a bare "#!/usr/bin/awk -f" shebang runs
# these scripts under mawk and the coprocess silently no-ops.  The most visible symptom was the
# Ubuntu diskful node never flipping to local-disk boot (updateflag.awk could not reach xcatd),
# but getcredentials/allowcred/startsyncfiles/locktftpdir/setiscsiparms are all exposed too.
#
# The fix is to declare a real dependency on gawk (deb Depends / rpm Requires) and to make the
# affected scripts request gawk explicitly in their shebang instead of relying on whatever
# /usr/bin/awk happens to be.  See VersatusHPC/xcat-core#58.

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

# The node postscripts shipped in the xcat deb / xCAT rpm that use gawk-only constructs.
my @gawk_scripts = qw(
    xCAT/postscripts/updateflag.awk
    xCAT/postscripts/getcredentials.awk
    xCAT/postscripts/getpostscript.awk
    xCAT/postscripts/allowcred.awk
    xCAT/postscripts/startsyncfiles.awk
    xCAT/postscripts/locktftpdir.awk
    xCAT/postscripts/unlocktftpdir.awk
    xCAT/postscripts/setiscsiparms.awk
);

for my $s (@gawk_scripts) {
    my $body = slurp($s);
    SKIP: {
        skip "$s not found", 2 unless defined $body;
        my ($shebang) = ($body =~ /\A(#!.*)\n/);
        $shebang = '' unless defined $shebang;
        like($shebang, qr{^#!/usr/bin/gawk\b},
            "$s requests gawk explicitly in its shebang");
        unlike($shebang, qr{^#!/usr/bin/awk\b},
            "$s does not use the ambiguous /usr/bin/awk shebang (mawk on Debian/Ubuntu)");
    }
}

my $ctrl = slurp('xCAT/debian/control');
SKIP: {
    skip 'debian/control not found', 1 unless defined $ctrl;
    like($ctrl, qr/^Depends:.*\bgawk\b/m,
        'xcat debian package Depends on gawk (postscripts need gawk, not mawk)');
}

my $spec = slurp('xCAT/xCAT.spec');
SKIP: {
    skip 'xCAT.spec not found', 1 unless defined $spec;
    like($spec, qr/^Requires:\s*gawk\b/m,
        'xCAT rpm Requires gawk for the awk node postscripts');
}

done_testing();
