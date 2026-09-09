#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# copycd builds the riscv64 boot loader by running grub-mkimage, and the plugin that runs it ships
# in xcat-server. Nothing declared the package that provides that command, so a management or
# service node installed without it copies riscv64 media and then produces no loader at all, while
# DHCP keeps pointing every riscv64 node at the path where the loader should be.
#
# grub-common provides /usr/bin/grub-mkimage on every supported Ubuntu release. That the plugin
# runs grub-mkimage is shown by ubuntu_copycd_grub2_loader.t, which drives it through a stub.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );

sub depends_of {
    my ($package) = @_;
    my $file = File::Spec->catfile( $repo_root, $package, 'debian', 'control' );
    open( my $fh, '<', $file ) or die "Unable to read $file: $!";
    my $control = do { local $/; <$fh> };
    close($fh);
    my ($depends) = $control =~ /^Depends:\s*(.*)$/m;
    return [ split( /\s*,\s*/, $depends // '' ) ];
}

my $server = depends_of('xCAT-server');
ok( scalar( grep { /^grub-common\b/ } @{$server} ),
    'xcat-server depends on the package that provides grub-mkimage' );

# The plugin runs there, so the metapackages inherit it and must not carry their own copy.
foreach my $package (qw(xCAT xCATsn)) {
    is_deeply( [ grep { /^grub-common\b/ } @{ depends_of($package) } ], [],
        "$package leaves the dependency with the package that runs the command" );
}

done_testing();
