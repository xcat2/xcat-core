#!/usr/bin/env perl
# The boot file both DHCP backends name for a grub2 node. An aarch64 node gets a name that ends in
# .efi once nodeset has created it: some aarch64 UEFI firmware ignores any other name and requests
# grubaa64.efi instead.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

use xCAT::DHCP::BootPolicy;
use xCAT::TableUtils;

# dhcp.pm reads the site TFTP directory once, when it loads. noderes.tftpdir moves one node elsewhere.
my $site_tftp = tempdir( CLEANUP => 1 );
my $node_tftp = tempdir( CLEANUP => 1 );
{
    no warnings 'redefine';
    *xCAT::TableUtils::getTftpDir = sub { return $site_tftp; };
}
require( repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm') );

for my $dir ( $site_tftp, $node_tftp ) {
    make_path("$dir/boot/grub2");
    open( my $loader, '>', "$dir/boot/grub2/grub2.aarch64" ) or die "Cannot create the loader: $!";
    close($loader) or die "Cannot close the loader: $!";
}

# The node loader links in a TFTP directory, as a nodeset left them.
sub publish {
    my ( $dir, @names ) = @_;
    unlink( glob("$dir/boot/grub2/grub2-cn1*") );
    for my $name (@names) {
        symlink( 'grub2.aarch64', "$dir/boot/grub2/$name" ) or die "Cannot create $dir/boot/grub2/$name: $!";
    }
    return;
}

# A table returns only the columns the plugin asks for, like the real one.
{
    package GrubLoaderTable;

    our %rows;
    sub new { my ( $class, $name ) = @_; return bless { name => $name }, $class; }

    sub getNodesAttribs {
        my ( $self, $nodes, $cols ) = @_;
        my %out;
        for my $node (@$nodes) {
            my $row = $rows{ $self->{name} }{$node} or next;
            $out{$node} = [ { map { exists $row->{$_} ? ( $_ => $row->{$_} ) : () } @$cols } ];
        }
        return \%out;
    }
    sub getNodeAttribs { return; }
    sub getAllAttribs  { return; }
    sub getAttribs     { return { username => 'xcat_key', password => 'dGVzdA==' }; }
    sub close          { return; }

    package GrubLoaderISCBackend;
    sub name { return 'isc'; }

    package GrubLoaderKeaBackend;
    sub subnet_id_for_ip { return 1; }
}

sub node_rows {
    my ( $arch, $netboot, $tftpdir ) = @_;
    return (
        noderes => { cn1 => { netboot => $netboot, tftpserver => '192.0.2.1', ( $tftpdir ? ( tftpdir => $tftpdir ) : () ) } },
        chain    => { cn1 => { currstate => 'install' } },
        mac      => { cn1 => { mac => '02:00:00:00:00:11' } },
        nodetype => { cn1 => { os => 'rhels9.4', provmethod => 'install', ( defined $arch ? ( arch => $arch ) : () ) } },
    );
}

my @errors;
no warnings 'redefine';
local *xCAT::Table::new = sub { return GrubLoaderTable->new( $_[1] ); };
local *xCAT::TableUtils::get_site_attribute = sub { return; };
local *xCAT::MsgUtils::trace = sub { return; };
local *xCAT_plugin::dhcp::getipaddr = sub { return '192.0.2.11'; };
local *xCAT::NetworkUtils::getipaddr = sub { return '192.0.2.11'; };
local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };
local $xCAT_plugin::dhcp::callback = sub { push @errors, @{ $_[0]->{error} || [] }; };
use warnings 'redefine';

# The boot file of the reservation the Kea backend builds for cn1.
sub kea_boot_file {
    my ( $arch, $netboot, $tftpdir ) = @_;
    local %GrubLoaderTable::rows = node_rows( $arch, $netboot, $tftpdir );
    my $reservations = xCAT_plugin::dhcp::kea_build_node_reservations( bless( {}, 'GrubLoaderKeaBackend' ), {}, ['cn1'] );
    return [ map { $_->{'boot-file-name'} } @$reservations ];
}

# The RFC 5970 bootfile-url of the DHCPv6 reservation the Kea backend builds for cn1.
sub kea_boot_url6 {
    my ( $arch, $netboot, $tftpdir ) = @_;
    local %GrubLoaderTable::rows = node_rows( $arch, $netboot, $tftpdir );
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::getipaddr = sub {
        my ( $host, %opt ) = @_;
        return $opt{OnlyV6} ? '2001:db8::11' : undef;
    };
    local *xCAT::NetworkUtils::ipv6_server_for_node = sub { return '2001:db8::1'; };
    use warnings 'redefine';
    my $reservations = xCAT_plugin::dhcp::kea_build_node_reservations6( bless( {}, 'GrubLoaderKeaBackend' ), {}, ['cn1'] );
    return [ map { map { $_->{data} } grep { $_->{name} eq 'bootfile-url' } @{ $_->{'option-data'} || [] } } @$reservations ];
}

my $dir = tempdir( CLEANUP => 1 );
my $conf = "$dir/dhcpd.conf";
open( my $fh, '>', $conf ) or die "Cannot create $conf: $!";
print {$fh} "#xCAT generated dhcp configuration\n",
  "option space gpxe;\n",
  @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() },
  "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
  "} # 192.0.2.0/255.255.255.0 subnet_end\n";
close($fh) or die "Cannot close $conf: $!";

# The boot file of every host that makedhcp creates for cn1 through OMAPI.
sub isc_boot_files {
    my ( $arch, $netboot, $tftpdir ) = @_;
    local %GrubLoaderTable::rows = node_rows( $arch, $netboot, $tftpdir );
    my $commands = '';
    no warnings 'redefine';
    local *xCAT::DHCP::Backend::new_backend = sub { return bless {}, 'GrubLoaderISCBackend'; };
    local *xCAT::Utils::isServiceNode = sub { return 0; };
    local *xCAT::Utils::isLinux = sub { return 1; };
    local *xCAT::Utils::isFIPS = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return 0; };
    local *xCAT::NetworkUtils::determinehostname = sub { return ('mn'); };
    local *xCAT::NetworkUtils::nodeonmynet = sub { return 1; };
    local *xCAT::DBobjUtils::getnodetype = sub { return {}; };
    local *xCAT::DBobjUtils::getNetwkInfo = sub { return ( cn1 => { mgtifname => 'eth0' } ); };
    local *xCAT_plugin::dhcp::addnic = sub { return; };
    local *xCAT_plugin::dhcp::addnet = sub { return; };
    local *xCAT_plugin::dhcp::addnet6 = sub { return; };
    local *xCAT_plugin::dhcp::writeout = sub { return; };
    local *xCAT_plugin::dhcp::_open_omshell_writer = sub {
        open( my $out, '>', \$commands ) or die "Cannot open an omshell buffer: $!";
        return $out;
    };
    local *xCAT_plugin::dhcp::_close_omshell_writer = sub { return; };
    local $::XCATSITEVALS{externaldhcpservers};
    local $xCAT_plugin::dhcp::dhcpconffile = $conf;
    local $xCAT_plugin::dhcp::distro = 'rhels9.4';
    use warnings 'redefine';

    open( my $printed, '>', \my $text ) or die "Cannot open an output buffer: $!";
    my $selected = select($printed);
    my $died;
    eval {
        xCAT_plugin::dhcp::process_request( { _xcatpreprocessed => [1], node => ['cn1'], arg => [] },
            sub { push @errors, @{ $_[0]->{error} || [] }; } );
        1;
    } or $died = $@;
    select($selected);
    die "makedhcp died: $died" if $died;

    return [ map { /filename = \\"([^\\"]*)\\"/g } $commands =~ /^set statements = "(.*)"$/mg ];
}

my @both = qw(grub2-cn1 grub2-cn1.efi);
my @old  = qw(grub2-cn1);

# Architecture, links in the site TFTP directory, links in the node's own one (none: no noderes.tftpdir),
# the boot file DHCP names, and the case.
my @cases = (
    [ 'aarch64', \@both, undef,  '/boot/grub2/grub2-cn1.efi', 'after nodeset' ],
    [ 'aarch64', \@old,  undef,  '/boot/grub2/grub2-cn1',     'set by an older nodeset' ],
    [ 'aarch64', [],     undef,  '/boot/grub2/grub2-cn1',     'without loader links' ],
    [ 'aarch64', \@old,  \@both, '/boot/grub2/grub2-cn1.efi', 'after nodeset in its own TFTP directory' ],
    [ 'aarch64', \@both, \@old,  '/boot/grub2/grub2-cn1',     'set by an older nodeset in its own TFTP directory' ],
    [ 'x86_64',  \@old,  undef,  '/boot/grub2/grub2-cn1',     'after nodeset' ],
    [ 'x86_64',  \@both, undef,  '/boot/grub2/grub2-cn1',     'with a stray .efi link' ],
    [ 'riscv64', \@old,  undef,  '/boot/grub2/grub2-cn1',     'after nodeset' ],
    [ 'ppc64',   \@old,  undef,  '/boot/grub2/grub2-cn1',     'after nodeset' ],
    [ 'ppc64le', \@old,  undef,  '/boot/grub2/grub2-cn1',     'after nodeset' ],
    [ '',        \@both, undef,  '/boot/grub2/grub2-cn1',     'with a .efi link' ],
    [ undef,     \@both, undef,  '/boot/grub2/grub2-cn1',     'with a .efi link' ],
);

for my $case (@cases) {
    my ( $arch, $site_links, $node_links, $expected, $state ) = @$case;
    my $label = ( defined $arch ? ( $arch eq '' ? 'a blank arch' : $arch ) : 'no arch' ) . " $state";
    publish( $site_tftp, @$site_links );
    publish( $node_tftp, @{ $node_links || [] } );
    my $tftpdir = $node_links ? $node_tftp : undef;

    for my $netboot (qw(grub2 grub2-tftp grub2-http)) {
        @errors = ();
        is_deeply( kea_boot_file( $arch, $netboot, $tftpdir ), [$expected], "Kea: $netboot node with $label" )
          or diag("errors: @errors");
    }
    @errors = ();
    is_deeply( isc_boot_files( $arch, 'grub2', $tftpdir ), [$expected], "ISC: grub2 node with $label" )
      or diag("errors: @errors");

    # DHCPv6 names the same loader. The URL is the only place the name appears, so an
    # aarch64 node over IPv6 boots nothing when it is built without the suffix.
    @errors = ();
    is_deeply( kea_boot_url6( $arch, 'grub2', $tftpdir ), ["tftp://[2001:db8::1]$expected"],
        "Kea DHCPv6: grub2 node with $label" )
      or diag("errors: @errors");
}

publish( $site_tftp, @both );
is( xCAT_plugin::dhcp::kea_boot_for_node( 'cn1', { netboot => 'grub2' }, undef, undef, undef, '192.0.2.1' )->{'boot-file-name'},
    '/boot/grub2/grub2-cn1', 'Kea: grub2 node without a nodetype entry' );
is( xCAT_plugin::dhcp::kea_boot_for_node(
        'cn1', { netboot => 'grub2' }, { currstate => 'boot' }, { arch => 'aarch64' }, undef, '192.0.2.1'
    )->{'boot-file-name'},
    '', 'Kea: aarch64 grub2 node in boot state still gets no boot file' );

done_testing();
