#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));

my $spec = read_file('xCAT-genesis-builder/xCAT-genesis-base.spec');
like($spec, qr/^BuildRequires:\s+kernel-core$/m, 'genesis build installs the kernel core');
like($spec, qr/^BuildRequires:\s+kernel-modules$/m, 'genesis build installs the standard kernel modules');
like($spec, qr/^BuildRequires:\s+kernel-modules-extra$/m, 'genesis build installs the extra kernel modules');

my $dracut_module = read_file('xCAT-genesis-builder/dracut_105/el/module-setup.sh');
like(
    $dracut_module,
    qr/installkernel\(\) \{.*?modules_dep=.*?while IFS= read -r modfile;.*?instmods "\$modname".*?done < "\$modules_dep"/s,
    'genesis dracut module installs every module available to the build'
);

my $doxcat = read_file('xCAT-genesis-scripts/usr/bin/doxcat');
like($doxcat, qr/^modprobe ib_ipoib$/m, 'genesis loads the IP over InfiniBand module');
like(
    $doxcat,
    qr/if \[ -z "\$bootnic" \]; then\s+bootnic=`ip link show\|grep -B1 infiniband/s,
    'genesis checks InfiniBand addresses only after the Ethernet lookup misses'
);

done_testing();

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile($repo_root, split m{/}, $file);
    open(my $fh, '<', $path) or die "open $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $contents;
}
