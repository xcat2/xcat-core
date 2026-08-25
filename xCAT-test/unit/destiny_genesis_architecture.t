#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/destiny.pm";
open(my $source_fh, '<', $source) or die "open $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh) or die "close $source: $!";

my @routines;
for my $name (qw(_genesis_boot_arch _genesis_uses_power_console)) {
    my ($routine) = $content =~ /^(sub \Q$name\E\s*\{.*?^\})/ms;
    BAIL_OUT("could not extract $name from destiny.pm") unless $routine;
    push(@routines, $routine);
}
eval join("\n", @routines); ## no critic (BuiltinFunctions::ProhibitStringyEval)
BAIL_OUT("could not load Genesis architecture helpers: $@") if $@;

my $tftp = tempdir(CLEANUP => 1);
make_path("$tftp/xcat");

is(
    _genesis_boot_arch($tftp, 'ppc64le'),
    'ppc64',
    'ppc64le keeps the legacy POWER fallback when no exact image exists',
);

open(my $marker_fh, '>', "$tftp/xcat/genesis.exact-arch.ppc64")
  or die "create exact POWER marker: $!";
close($marker_fh) or die "close exact POWER marker: $!";

is(
    _genesis_boot_arch($tftp, 'ppc64le'),
    'ppc64le',
    'ppc64le does not fall back to a canonical big-endian ppc64 image',
);
unlink("$tftp/xcat/genesis.exact-arch.ppc64")
  or die "remove exact POWER marker: $!";

open(my $kernel_fh, '>', "$tftp/xcat/genesis.kernel.ppc64le")
  or die "create exact POWER kernel: $!";
close($kernel_fh) or die "close exact POWER kernel: $!";

is(
    _genesis_boot_arch($tftp, 'ppc64le'),
    'ppc64le',
    'ppc64le uses the exact OpenEmbedded boot artifact',
);
is(
    _genesis_boot_arch($tftp, 'ppc64el'),
    'ppc64le',
    'the Debian spelling resolves to the exact ppc64le artifact',
);
is(_genesis_boot_arch($tftp, 'x86_64'), 'x86_64', 'other architectures are unchanged');

ok(_genesis_uses_power_console('ppc64'), 'legacy POWER uses the hypervisor console');
ok(_genesis_uses_power_console('ppc64le'), 'ppc64le uses the hypervisor console');
ok(!_genesis_uses_power_console('x86_64'), 'x86_64 keeps the serial console path');

like(
    $content,
    qr/my \$arch = _genesis_boot_arch\(\$tftpdir, \$ent->\{arch\}\);/,
    'destiny applies the tested architecture selection to nodeset',
);

done_testing();
