#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# mkinstall logged "Unknown arch" for every architecture other than x86_64, x86, ppc64le and
# ppc64el, so each diskful riscv64 install produced a false message. install_darch names the
# architectures xCAT installs Ubuntu on and the Debian name each one maps to.

# xCAT modules put $::XCATROOT/lib/perl ahead of @INC as they compile, so on a host with xCAT
# installed the modules loaded after the first one would come from /opt/xcat. XCATROOT points
# at this checkout before any of them compiles.
BEGIN {
    my $root = tempdir( CLEANUP => 1 );
    make_path("$root/lib");
    symlink( "$FindBin::Bin/../../perl-xCAT", "$root/lib/perl" ) or die "symlink: $!";
    $ENV{XCATROOT} = $root;
}

BEGIN {
    package xCAT::TableUtils;
    our $tftpdir;
    sub getTftpDir { return $tftpdir; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;
}

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
require $plugin;

my @cases = (
    # arch       Debian name  installs Ubuntu
    [ 'x86_64',  'amd64',     1 ],
    [ 'x86',     'i386',      1 ],
    [ 'ppc64le', 'ppc64le',   1 ],
    [ 'ppc64el', 'ppc64el',   1 ],
    [ 'riscv64', 'riscv64',   1 ],
    [ 'aarch64', 'aarch64',   0 ],
    [ 'sparc',   'sparc',     0 ],
);
foreach my $case (@cases) {
    my ( $arch, $darch, $known ) = @$case;
    my ( $got_darch, $got_known ) = xCAT_plugin::debian::install_darch($arch);
    is( $got_darch, $darch, "$arch installs from the $darch tree" );
    is( $got_known, $known, $known ? "... and is an architecture xCAT installs Ubuntu on" : "... and is reported as unknown" );
}

done_testing();
