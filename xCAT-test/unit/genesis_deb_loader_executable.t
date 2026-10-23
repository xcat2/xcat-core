#!/usr/bin/env perl
# THE GENESIS PAYLOAD'S DYNAMIC LOADER MUST KEEP ITS EXECUTE BIT IN THE DEB.
#
# xCAT-genesis-base/debian/rules was a bare `dh $@`, so dh_fixperms applied its *.so* rule to the
# whole package -- correct for a Debian shared library, wrong for a netboot ROOT FILESYSTEM. The
# kernel execs the payload's dynamic loader, and a loader with no execute bit makes open_exec()
# return EACCES, so every ELF in the Genesis image fails to start:
#
#   Failed to execute /init (error -13)
#   Kernel panic - not syncing: No working init found.
#
# mknb copies the tree verbatim into genesis.fs.<arch>.lzma, so the broken mode travels into the
# image. The pipeline's iPXE command line carries `quiet`, which hid the reason.
#
# Measured 2026-10-23 on xcat-master-ub, from the installed package:
#   644 .../netboot/genesis/x86_64/fs/usr/lib64/ld-linux-x86-64.so.2
#   755 .../netboot/genesis/x86_64/fs/usr/bin/basename
# and reproduced off the lab: the MN's own kernel and image under qemu panicked at 35s, repacked
# unchanged panicked again, and repacked with only chmod 0755 on the loader booted. The EL rpm is
# unaffected -- it never runs dh_fixperms -- which is why only xcat-test-ubuntu-24-x86_64
# -genesis-legacy saw it, and why that leaf has never had a non-mock green.
#
# debian/rules IS the artifact here: there is nothing to execute and the text is the contract, the
# same reason a test may assert a package name in a .spec. The live proof is the leaf.
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Slurper qw(read_text);

my $rules = "$FindBin::Bin/../../xCAT-genesis-base/debian/rules";
ok(-f $rules, 'xCAT-genesis-base/debian/rules is present') or die "no rules file\n";
my $text = read_text($rules);

# The override must exist. Without it dh_fixperms runs with its defaults over the payload.
like($text, qr/^override_dh_fixperms:/m,
     'debian/rules overrides dh_fixperms');

# It must still RUN dh_fixperms. Dropping it would leave the rest of the package unnormalised --
# the chown 0:0 pass and the 0644 on documentation are both wanted.
like($text, qr/^override_dh_fixperms:\n(?:.*\n)*?\tdh_fixperms\b/m,
     '... and still calls dh_fixperms rather than replacing it');

# And it must restore the loader afterwards, under the netboot tree only.
my ($body) = $text =~ /^override_dh_fixperms:\n((?:[\t ].*\n|\n)*)/m;
ok(defined $body && length $body, 'the override has a body') or die "no override body\n";
like($body, qr/netboot\/genesis/,
     'the restore is scoped to the netboot payload, not the whole package');
like($body, qr/chmod\s+0?755/,
     '... and puts the execute bit back');
like($body, qr/ld-\*\.so/,
     '... on the glibc loader (ld-*.so)');
like($body, qr/ld64\.so/,
     '... and on the ppc64le loader (ld64.so.*)');

# ORDER: dh_fixperms strips the bit, so the chmod has to come after it. A chmod first would be
# undone by the very command this override exists to correct.
my @lines = split /\n/, $body;
my ($fix) = grep { $lines[$_] =~ /\bdh_fixperms\b/ } 0 .. $#lines;
my ($chm) = grep { $lines[$_] =~ /\bchmod\b/ } 0 .. $#lines;
if (defined $fix && defined $chm) {
    cmp_ok($fix, '<', $chm, 'dh_fixperms runs BEFORE the chmod that corrects it');
}

# NOT with -X. Excluding the tree from dh_fixperms would also skip its chown 0:0 pass, so the
# payload would ship owned by the build user.
# Command lines only. A comment that merely MENTIONS -X is not an exclusion, and matching the
# whole file made this assertion fail on the comment that explains why -X was not used.
my @recipe = grep { /^\t/ } split /\n/, $text;
ok(!(grep { /dh_fixperms[^\n]*-X/ } @recipe),
   'the tree is not excluded from dh_fixperms wholesale');

done_testing;
