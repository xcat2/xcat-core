#!/usr/bin/env perl
# An unknown UEFI client with the upstream iPXE loader reads its discovery script from
# xcat/ipxe/nets. Nothing signs the Genesis kernel, so with Secure Boot on the script must name a
# shim, which verifies the kernel against the MOK list that the site enrolls. mknb writes the
# scripts into a scratch TFTP root. Tables and name resolution are stand-ins.
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use File::Path qw(make_path);
use File::Slurper qw(read_text write_binary);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

BEGIN {
    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    our $tftpdir;
    sub getTftpDir { return $tftpdir }
    sub get_site_attribute { return $_[-1] eq 'master' ? ('master.example.com') : () }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    sub my_nets    { return { '192.168.144.0/20' => ['192.168.148.10'] } }
    sub my_hexnets { return { c0a89 => ['192.168.148.10'] } }
    sub getipaddr  { return ('203.0.113.10') }
    sub get_nic_ip { return {} }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    sub trace { return }
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT::Table;
    sub new { return }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::NodeRange;
    sub import {
        my $caller = caller;
        no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{"${caller}::noderange"} = sub { return };
        return;
    }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;

    package main;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
}

my $repo = "$FindBin::Bin/../..";
unshift @INC, "$repo/perl-xCAT", "$repo/xCAT-server/lib/perl";
require "$repo/xCAT-server/lib/xcat/plugins/mknb.pm";    ## no critic (Modules::RequireBarewordIncludes)

my $tmp = tempdir( CLEANUP => 1 );
$::XCATROOT = "$tmp/xcatroot";
make_path("$::XCATROOT/share/xcat/netboot/genesis/x86_64");

# What mknb needs in the TFTP root before it writes a configuration: the payload it boots, and the
# Secure Boot shim that ipxe-xcat installs.
sub prepare {
    my (%opt) = @_;
    $xCAT::TableUtils::tftpdir = "$tmp/$opt{name}";
    make_path( "$xCAT::TableUtils::tftpdir/xcat", "$xCAT::TableUtils::tftpdir/etc" );
    write_binary( "$xCAT::TableUtils::tftpdir/xcat/genesis.kernel.x86_64",  '' );
    write_binary( "$xCAT::TableUtils::tftpdir/xcat/genesis.fs.x86_64.gz", '' );
    if ( $opt{shim} ) {
        make_path("$xCAT::TableUtils::tftpdir/xcat/ipxe/x86_64-sb");
        write_binary( "$xCAT::TableUtils::tftpdir/xcat/ipxe/x86_64-sb/shimx64.efi", 'shim' );
    }
    my @errors;
    xCAT_plugin::mknb::process_request( { arg => [ 'x86_64', '--configfileonly' ] },
        sub { push @errors, grep { ref eq 'HASH' && $_->{error} } @_; return } );
    is_deeply( \@errors, [], "mknb writes the x86_64 configuration with shim=" . ( $opt{shim} ? 1 : 0 ) );
    return;
}

sub script {
    my ($relative) = @_;
    return -f "$xCAT::TableUtils::tftpdir/$relative" ? read_text("$xCAT::TableUtils::tftpdir/$relative") : '';
}

prepare( name => 'tftpboot-shim', shim => 1 );
like(
    script('xcat/ipxe/nets/192.168.144.0_20.uefi'),
    qr{^imgload kernel\nshim http://\$\{next-server\}/tftpboot/xcat/ipxe/x86_64-sb/shimx64\.efi$}m,
    'the UEFI discovery script names the shim of ipxe-xcat, after it selects the Genesis kernel'
);
like( script('xcat/ipxe/nets/192.168.144.0_20.uefi'), qr{^shim \S+\nimgargs kernel }m,
    'and names it before the kernel runs' );
unlike( script('xcat/ipxe/nets/192.168.144.0_20'), qr{^shim }m,
    'the BIOS discovery script names no shim' );
unlike( script('xcat/ipxe/nets/192.168.144.0_20.elilo'), qr{^shim }m,
    'the elilo configuration names no shim' );

prepare( name => 'tftpboot-noshim', shim => 0 );
unlike( script('xcat/ipxe/nets/192.168.144.0_20.uefi'), qr{^shim }m,
    'a server without the ipxe-xcat shim names no shim' );

done_testing();
