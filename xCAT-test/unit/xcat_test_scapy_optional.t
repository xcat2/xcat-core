#!/usr/bin/env perl
# SCAPY IS OPTIONAL, AND THE TWO PACKAGINGS MUST AGREE THAT IT IS.
#
# Only blackboxtest's DHCP steps need scapy. dhcp.py is the single module that imports it, and it
# does so inside scapy_module(), which raises UnsupportedError naming python3-scapy when the import
# fails -- so the package installs and every other blackboxtest step runs without it.
#
# xCAT-test.spec says exactly that and only RECOMMENDS the package, with the reason in a comment:
# a hard Requires: would make xCAT-test uninstallable on a management node without EPEL.
# debian/control said `Depends:`, which is the same claim with the opposite answer.
#
# The cost is not theoretical. `apt-get install -y xcat-test` installs Recommends by default, and
# python3-scapy recommends matplotlib, scipy and ipython3: 54 packages and about 255 MB, inside a
# step the GitHub workflow caps at 1200 seconds. On 2026-10-23 that download stalled and killed
# xcat_pr_test on xcat-core/#7974 at exactly 1200s, while a sibling run on another runner did the
# same install in 19 seconds.
#
# A packaging manifest is the artifact here -- there is nothing to execute and the text is the
# contract -- which is why this asserts on the files rather than on a build.
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Slurper qw(read_text);

my $root    = "$FindBin::Bin/../..";
my $control = "$root/xCAT-test/debian/control";
my $spec    = "$root/xCAT-test/xCAT-test.spec";
ok(-f $control, 'xCAT-test/debian/control is present') or die "no control file\n";
ok(-f $spec,    'xCAT-test/xCAT-test.spec is present') or die "no spec\n";

my $ctext = read_text($control);
my $stext = read_text($spec);

# The xcat-test stanza, not the source stanza: Build-Depends lives above it.
my ($stanza) = $ctext =~ /^Package:\s*xcat-test\s*$(.*?)(?:^Package:|\z)/ms;
ok(defined $stanza && length $stanza, 'the xcat-test binary stanza is found')
    or die "cannot isolate the xcat-test stanza\n";

my ($depends)    = $stanza =~ /^Depends:\s*(.*)$/m;
my ($recommends) = $stanza =~ /^Recommends:\s*(.*)$/m;

ok(defined $depends, 'xcat-test declares Depends');
unlike($depends // '', qr/python3-scapy/,
       'python3-scapy is NOT a hard Depends of xcat-test');
like($recommends // '', qr/python3-scapy/,
     'python3-scapy is Recommended instead');
# The perl dependency is what makes the package work at all and must survive the change.
like($depends // '', qr/\$\{perl:Depends\}/, 'the perl dependency is still a Depends');
# blackboxtest is a python3 program. Without scapy, nothing else pulls in the interpreter.
my @hard = map { s/^\s+|\s+$//gr } split /,/, $depends // '';
ok((grep { /^python3(?:\s|$)/ } @hard), 'python3 is a hard Depends of xcat-test');

# PARITY. The two packagings answer the same question, so they must answer it the same way: the
# spec has recommended it since the tool was added, and the asymmetry is what this fixes.
like($stext, qr/^Recommends:\s*python3-scapy\s*$/m, 'the EL spec recommends python3-scapy');
unlike($stext, qr/^Requires:[^\n]*python3-scapy/m, '... and does not require it');

# The reason belongs next to the decision, in both files, or the next person reverts it.
like($stanza, qr/scapy/i, 'the control stanza explains the choice');

done_testing;
