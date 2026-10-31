#!/usr/bin/env perl
# The install URLs sles.pm puts on the kernel command line, for an IPv6 management node.
#
# sles.pm joined the server and the port with a colon, so an IPv6 node was told
# "install=http://2001:db8:156::1:80/install/..." . Nothing can tell that address from its
# port, so the installer could not reach the repository. RFC 3986 brackets the host.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

use xCAT::NetworkUtils;
require( repo_path('xCAT-server/lib/xcat/plugins/sles.pm') );

# The authority helper the three URL sites share.
is( xCAT::NetworkUtils::uri_authority('2001:db8:156::1', 80),
    '[2001:db8:156::1]:80', 'an IPv6 address is bracketed' );
is( xCAT::NetworkUtils::uri_authority('192.168.156.1', 80),
    '192.168.156.1:80', 'an IPv4 address is not bracketed' );
is( xCAT::NetworkUtils::uri_authority('!myipfn!', 80),
    '!myipfn!:80', 'a substitution placeholder passes through' );
is( xCAT::NetworkUtils::uri_authority(undef, 80), undef, 'no address gives no authority' );

# The diskful install arguments.
my $v6 = xCAT_plugin::sles::autoyast_boot_args('http', '2001:db8:156::1', 80, '/install/leap15.6/x86_64', 'cn1');
like( $v6, qr{\Qautoyast=http://[2001:db8:156::1]:80/install/autoinst/cn1\E},
    'autoyast= brackets an IPv6 install server' );
like( $v6, qr{\Qinstall=http://[2001:db8:156::1]:80/install/leap15.6/x86_64/1\E},
    'install= brackets an IPv6 install server' );
unlike( $v6, qr{http://2001:db8:156::1:80},
    'no unbracketed IPv6 authority appears in the diskful arguments' );

my $v4 = xCAT_plugin::sles::autoyast_boot_args('http', '192.168.156.1', 80, '/install/leap15.6/x86_64', 'cn1');
like( $v4, qr{\Qautoyast=http://192.168.156.1:80/install/autoinst/cn1\E},
    'an IPv4 install server is unchanged' );

# The statelite and stateless root image URL.
is( xCAT_plugin::sles::rootimg_url('http', '2001:db8:156::1', 80, 'install/netboot/x86_64', 'rootimg.gz'),
    'http://[2001:db8:156::1]:80/install/netboot/x86_64/rootimg.gz',
    'imgurl= brackets an IPv6 image server' );
is( xCAT_plugin::sles::rootimg_url('http', '192.168.156.1', 80, 'install/netboot/x86_64', 'rootimg.gz'),
    'http://192.168.156.1:80/install/netboot/x86_64/rootimg.gz',
    'imgurl= leaves an IPv4 image server alone' );

# grub2.pm substitutes !myipfn! into these same URLs, after the port is already appended.
is( xCAT::NetworkUtils::substitute_facing_address(
        'install=http://!myipfn!:80/install/leap15.6/x86_64/1', '2001:db8:156::1'),
    'install=http://[2001:db8:156::1]:80/install/leap15.6/x86_64/1',
    'a placeholder that a port follows is bracketed for IPv6' );
is( xCAT::NetworkUtils::substitute_facing_address('xcatd=!myipfn! quiet', '2001:db8:156::1'),
    'xcatd=2001:db8:156::1 quiet',
    'a placeholder with no port keeps the bare IPv6 address' );
is( xCAT::NetworkUtils::substitute_facing_address(
        'install=http://!myipfn!:80/x', '192.168.156.1'),
    'install=http://192.168.156.1:80/x', 'an IPv4 address is never bracketed' );
is( xCAT::NetworkUtils::substitute_facing_address('xcatd=!myipfn!', undef),
    'xcatd=!myipfn!', 'no facing address leaves the command line alone' );

done_testing();
