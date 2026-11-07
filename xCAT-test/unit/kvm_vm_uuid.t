#!/usr/bin/env perl
# vpd.uuid holds the system UUID that the guest reports. QEMU stores the libvirt domain UUID as
# SMBIOS 2.6 specifies, so the guest reports the domain UUID unchanged, and the KVM plugin must
# carry vpd.uuid to the domain and back without changing its byte order: mkvm writes it to the
# domain XML, rscan imports the domain UUID into vpd.uuid, and rinv prints it. Machine types
# pc-i440fx-2.1, pc-q35-2.1, pc-i440fx-rhel7.1.0 and pc-i440fx-utopic are the exception: their guest
# reports the domain UUID with the first three fields swapped, so the plugin swaps them for those
# machine types only.
#
# The plugin runs through process_request, with a private SQLite database and a hypervisor
# connection that serves fixed domain XML in place of libvirt.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use Test::More;
use XML::LibXML;

my $uuid = '12345678-1234-4bcd-9876-1234567890ab';

# A connection to a hypervisor that holds the domains in @XCATTestHypervisor::domains.
BEGIN {
    package Sys::Virt;
    our $VERSION = '10.0.0';
    sub new { return bless {}, 'XCATTestHypervisor'; }

    package Sys::Virt::Domain;
    use constant {
        STATE_NOSTATE => 0,
        STATE_RUNNING => 1,
        STATE_BLOCKED => 2,
        STATE_PAUSED  => 3,
        STATE_SHUTOFF => 5,
    };

    $INC{'Sys/Virt.pm'}         = __FILE__;
    $INC{'Sys/Virt/Domain.pm'}  = __FILE__;

    # Only rpower reports node status to monitoring.
    package xCAT_monitoring::monitorctrl;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
}

{
    package XCATTestHypervisor;
    our @domains;
    our $default_machine = 'pc-i440fx-8.2';
    sub get_node_info { return { model => 'x86_64' }; }
    # libvirt names the machine type that a domain gets for no machine type or for the alias pc.
    sub get_domain_capabilities {
        my ( undef, undef, undef, $machine ) = @_;
        $machine = $default_machine if !defined($machine) or $machine eq 'pc';
        return "<domainCapabilities><machine>$machine</machine></domainCapabilities>";
    }
    sub list_all_domains { return map { bless { xml => $_ }, 'XCATTestDomain' } @domains; }
    sub get_domain_by_name {
        my ( undef, $name ) = @_;
        foreach my $xml (@domains) {
            return bless { xml => $xml }, 'XCATTestDomain' if $xml =~ m{<name>\Q$name\E</name>};
        }
        die "no domain $name\n";
    }

    package XCATTestDomain;
    sub get_xml_description { return $_[0]->{xml}; }
    sub get_name { return ( $_[0]->{xml} =~ m{<name>([^<]+)</name>} )[0]; }
    sub get_info { return { state => Sys::Virt::Domain::STATE_RUNNING() }; }
    sub get_block_info { return { capacity => 1073741824, allocation => 0 }; }
}

my $db = tempdir( CLEANUP => 1 );
$ENV{XCATCFG}  = "SQLite:$db";
$ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server";
require xCAT::Table;

sub set_rows {
    my ( $table, %rows ) = @_;
    my $tab = xCAT::Table->new( $table, -create => 1 ) or die "Cannot open $table\n";
    $tab->setNodeAttribs( $_, $rows{$_} ) foreach sort keys %rows;
    $tab->close;
}

sub node_attribute {
    my ( $table, $node, $column ) = @_;
    my $tab = xCAT::Table->new($table) or return undef;
    my $ent = $tab->getNodeAttribs( $node, [$column] );
    $tab->close;
    return $ent ? $ent->{$column} : undef;
}

# cn1 has a vpd.uuid. cn2 has none, so mkvm generates one. cn3 runs on machine type pc-i440fx-2.1.
# cn4 names no machine type and cn5 names the alias pc, so libvirt picks the default machine type.
# cn6 runs on machine type pc-q35-2.1.
# known1 is a guest that an earlier rscan defined, with a DHCPv6 client identifier chosen in
# mac.duid. This process keeps the node list it reads first, and the forked plugin inherits it, so
# every node exists before the first command.
my $known = '0a1b2c3d-4e5f-4a6b-8c7d-8e9fa0b1c2d3';
set_rows( 'nodelist', cn1 => { groups => 'all' }, cn2 => { groups => 'all' }, cn3 => { groups => 'all' },
    cn4 => { groups => 'all' }, cn5 => { groups => 'all' }, cn6 => { groups => 'all' }, known1 => { groups => 'vm,all' },
    hyp1 => { groups => 'all' } );
set_rows( 'nodehm', cn1 => { mgt => 'kvm', power => 'kvm' }, cn2 => { mgt => 'kvm', power => 'kvm' },
    cn3 => { mgt => 'kvm', power => 'kvm' }, cn4 => { mgt => 'kvm', power => 'kvm' }, cn5 => { mgt => 'kvm', power => 'kvm' },
    cn6 => { mgt => 'kvm', power => 'kvm' }, known1 => { mgt => 'kvm' }, hyp1 => { mgt => 'ipmi' } );
set_rows( 'nodetype', cn1 => { arch => 'x86_64' }, cn2 => { arch => 'x86_64' }, cn3 => { arch => 'x86_64' },
    cn4 => { arch => 'x86_64' }, cn5 => { arch => 'x86_64' }, cn6 => { arch => 'x86_64' }, known1 => { arch => 'x86_64' } );
set_rows( 'vm',
    cn1    => { host => 'hyp1', storage => 'phy:/dev/xcattest',  nics => 'br0', memory => '1024', cpus => '1' },
    cn2    => { host => 'hyp1', storage => 'phy:/dev/xcattest3', nics => 'br0', memory => '1024', cpus => '1' },
    cn3    => { host => 'hyp1', storage => 'phy:/dev/xcattest5', nics => 'br0', memory => '1024', cpus => '1',
                othersettings => 'machine:pc-i440fx-2.1' },
    cn4    => { host => 'hyp1', storage => 'phy:/dev/xcattest8', nics => 'br0', memory => '1024', cpus => '1' },
    cn5    => { host => 'hyp1', storage => 'phy:/dev/xcattest9', nics => 'br0', memory => '1024', cpus => '1',
                othersettings => 'machine:pc' },
    cn6    => { host => 'hyp1', storage => 'phy:/dev/xcattest11', nics => 'br0', memory => '1024', cpus => '1',
                othersettings => 'machine:pc-q35-2.1' },
    known1 => { host => 'hyp1', storage => '/dev/xcattest4', nics => 'br0', othersettings => 'nodefromrscan' } );
set_rows( 'mac', cn1 => { mac => '52:54:00:76:00:21' }, cn2 => { mac => '52:54:00:76:00:23' },
    cn3 => { mac => '52:54:00:76:00:27' }, cn4 => { mac => '52:54:00:76:00:2a' }, cn5 => { mac => '52:54:00:76:00:2b' },
    cn6 => { mac => '52:54:00:76:00:2d' }, known1 => { mac => '52:54:00:76:00:24', duid => 'canonical' } );
set_rows( 'vpd', cn1 => { uuid => $uuid }, cn3 => { uuid => $uuid }, cn4 => { uuid => $uuid }, cn5 => { uuid => $uuid },
    cn6 => { uuid => $uuid }, known1 => { uuid => $known } );

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/kvm.pm";
require $plugin;
{
    # The plugin probes the SSH port of the hypervisor before it connects.
    no warnings qw(once redefine);
    *xCAT_plugin::kvm::nodesockopen = sub { return 1; };
}

# The text values of a response, whatever its nesting.
sub texts {
    my ($value) = @_;
    return map { texts($_) } @$value if ref($value) eq 'ARRAY';
    return map { texts($_) } values %$value if ref($value) eq 'HASH';
    return defined($value) ? ($value) : ();
}

# Run one command and return the text of every response. The per-hypervisor child calls the
# callback too, so the responses go to a file that outlives the fork.
sub run_command {
    my ( $command, $nodes, @args ) = @_;
    my $log = "$db/$command.out";
    unlink $log;
    my $callback = sub {
        open( my $fh, '>>', $log ) or die "Cannot write $log: $!";
        print {$fh} "$_\n" foreach texts( $_[0] );
        close($fh);
    };
    xCAT_plugin::kvm::process_request( { command => [$command], node => $nodes, arg => \@args }, $callback, sub { return; } );
    open( my $fh, '<', $log ) or return ();
    chomp( my @output = <$fh> );
    close($fh);
    return @output;
}

sub domain_uuid {
    my ($xml) = @_;
    return undef unless $xml;
    my ($element) = XML::LibXML->load_xml( string => $xml )->findnodes('/domain/uuid');
    return $element ? $element->textContent : undef;
}

# mkvm builds the domain XML of cn1 and keeps it in kvm_nodedata.
my @mkvm = run_command( 'mkvm', ['cn1'] );
my $xml = node_attribute( 'kvm_nodedata', 'cn1', 'xml' );
ok( $xml, 'mkvm stores the domain XML of cn1' ) or diag( join "\n", @mkvm );
is( domain_uuid($xml), $uuid, 'mkvm gives the domain the UUID in vpd.uuid unchanged' );

run_command( 'mkvm', ['cn2'] );
my $generated = node_attribute( 'vpd', 'cn2', 'uuid' );
like( $generated // '', qr/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
    'mkvm stores a generated UUID in vpd.uuid of cn2' );
is( domain_uuid( node_attribute( 'kvm_nodedata', 'cn2', 'xml' ) ), $generated,
    'and gives the domain that UUID unchanged' );

# A domain as libvirt reports it, for the commands that read domains back.
sub domain_xml {
    my ( $name, $domain_uuid, $disk, $mac, $machine ) = @_;
    $machine //= 'q35';
    my $machine_attr = length($machine) ? qq( machine="$machine") : '';
    return <<"XML";
<domain type="kvm" id="7">
  <name>$name</name>
  <uuid>$domain_uuid</uuid>
  <memory unit="KiB">1048576</memory>
  <vcpu>1</vcpu>
  <os><type arch="x86_64"$machine_attr>hvm</type></os>
  <devices>
    <disk type="block" device="disk"><source dev="$disk"/><target dev="vda" bus="virtio"/></disk>
    <interface type="bridge"><source bridge="br0"/><mac address="$mac"/><model type="virtio"/></interface>
  </devices>
</domain>
XML
}

# rinv prints the domain UUID, which is the UUID the guest reports.
@XCATTestHypervisor::domains = ( domain_xml( 'cn1', $uuid, '/dev/xcattest', '52:54:00:76:00:21' ) );
my @rinv = run_command( 'rinv', ['cn1'] );
ok( ( grep { $_ eq $uuid } @rinv ), 'rinv prints the domain UUID unchanged' ) or diag( join "\n", @rinv );

# rscan -w defines a node from a domain that xCAT did not create, and stores its UUID.
my $scanned = '87654321-4321-4dcb-8967-ba0987654321';
@XCATTestHypervisor::domains = ( domain_xml( 'scanned1', $scanned, '/dev/xcattest2', '52:54:00:76:00:22' ) );
my @rscan = run_command( 'rscan', ['hyp1'], '-w' );
is( node_attribute( 'vpd', 'scanned1', 'uuid' ), $scanned, 'rscan -w stores the domain UUID in vpd.uuid unchanged' )
  or diag( join "\n", @rscan );

# rscan -u and rscan -w rewrite a guest that xCAT already knows. They update its MAC address, and its
# mac row keeps mac.duid, so the reservation that makedhcp builds next does not change.
require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
my $canonical = '00:04:0a:1b:2c:3d:4e:5f:4a:6b:8c:7d:8e:9f:a0:b1:c2:d3';
my %rescan_mac = ( '-u' => '52:54:00:76:00:25', '-w' => '52:54:00:76:00:26' );
foreach my $option ( '-u', '-w' ) {
    @XCATTestHypervisor::domains = ( domain_xml( 'known1', $known, '/dev/xcattest4', $rescan_mac{$option} ) );
    my @output = run_command( 'rscan', ['hyp1'], $option );
    is( node_attribute( 'mac', 'known1', 'mac' ), $rescan_mac{$option}, "rscan $option updates the MAC address of the guest" )
      or diag( join "\n", @output );
    is( node_attribute( 'mac', 'known1', 'duid' ), 'canonical', "rscan $option keeps mac.duid" );
    is( xCAT_plugin::dhcp::dhcp6_client_duids( ['known1'] )->{known1}->{duid}, $canonical,
        "after rscan $option the DHCPv6 reservation still uses the identifier that mac.duid selects" );
}

# Measured with -uuid 12345678-1234-4bcd-9876-1234567890ab on QEMU 8.2, the qemu-kvm 6.2 of EL8 and the
# QEMU 2.5 of Ubuntu 16.04: the pc-i440fx-2.1, pc-q35-2.1, pc-i440fx-rhel7.1.0 and pc-i440fx-utopic guests
# report 78563412-3412-cd4b-9876-1234567890ab, and the other machine types report the UUID unchanged.
my $swapped = '78563412-3412-cd4b-9876-1234567890ab';
foreach my $machine ( 'pc-i440fx-2.1', 'pc-q35-2.1', 'pc-i440fx-rhel7.1.0', 'pc-i440fx-utopic' ) {
    is( xCAT::KVMUtils::guest_uuid( $uuid, $machine ), $swapped, "guest_uuid swaps the UUID of a $machine domain" );
    is( xCAT::KVMUtils::guest_uuid( $swapped, $machine ), $uuid, 'and swapping again gives the domain UUID back' );
}
foreach my $machine ( undef, 'pc-i440fx-2.0', 'pc-i440fx-2.2', 'pc-i440fx-2.11', 'pc-q35-2.0', 'pc-q35-2.4',
    'pc-q35-2.11', 'pc-i440fx-8.2', 'pc-i440fx-rhel7.0.0', 'pc-i440fx-rhel7.2.0', 'pc-i440fx-rhel10.0.0',
    'pc-i440fx-trusty', 'pc-i440fx-wily', 'pc-i440fx-xenial', 'q35', 'pc-q35-rhel10.2.0' ) {
    is( xCAT::KVMUtils::guest_uuid( $uuid, $machine ), $uuid, 'guest_uuid keeps the UUID of machine type ' . ( $machine // 'default' ) );
}

# mkvm, rinv and rscan swap the UUID for a pc-i440fx-2.1 guest, so the guest still reports vpd.uuid.
run_command( 'mkvm', ['cn3'] );
my $legacy_xml = node_attribute( 'kvm_nodedata', 'cn3', 'xml' );
my ($legacy_type) = $legacy_xml ? XML::LibXML->load_xml( string => $legacy_xml )->findnodes('/domain/os/type') : ();
is( $legacy_type ? $legacy_type->getAttribute('machine') : undef, 'pc-i440fx-2.1', 'mkvm gives cn3 the machine type of vm.othersettings' );
is( domain_uuid($legacy_xml), $swapped, 'and a domain UUID that its guest reports as vpd.uuid' );

@XCATTestHypervisor::domains = ( domain_xml( 'cn1', $uuid, '/dev/xcattest', '52:54:00:76:00:21', 'pc-i440fx-2.1' ) );
my @legacy_rinv = run_command( 'rinv', ['cn1'] );
ok( ( grep { $_ eq $swapped } @legacy_rinv ), 'rinv prints the UUID that a pc-i440fx-2.1 guest reports' )
  or diag( join "\n", @legacy_rinv );

@XCATTestHypervisor::domains = ( domain_xml( 'scanned2', $uuid, '/dev/xcattest6', '52:54:00:76:00:28', 'pc-i440fx-2.1' ) );
run_command( 'rscan', ['hyp1'], '-w' );
is( node_attribute( 'vpd', 'scanned2', 'uuid' ), $swapped, 'rscan -w stores the UUID that a pc-i440fx-2.1 guest reports' );

@XCATTestHypervisor::domains = ( domain_xml( 'scanned3', $uuid, '/dev/xcattest7', '52:54:00:76:00:29', 'pc-i440fx-rhel7.1.0' ) );
run_command( 'rscan', ['hyp1'], '-w' );
is( node_attribute( 'vpd', 'scanned3', 'uuid' ), $swapped, 'rscan -w stores the UUID that a pc-i440fx-rhel7.1.0 guest reports' );

# A domain that names no machine type, or the alias pc, gets the default machine type of the hypervisor.
# Where that default is pc-i440fx-rhel7.1.0, its UUID is swapped as for that machine type.
$XCATTestHypervisor::default_machine = 'pc-i440fx-rhel7.1.0';
foreach my $node ( 'cn4', 'cn5' ) {
    run_command( 'mkvm', [$node] );
    is( domain_uuid( node_attribute( 'kvm_nodedata', $node, 'xml' ) ), $swapped,
        "mkvm swaps the UUID of $node, whose default machine type is pc-i440fx-rhel7.1.0" );
}
@XCATTestHypervisor::domains = ( domain_xml( 'scanned4', $uuid, '/dev/xcattest10', '52:54:00:76:00:2c', '' ) );
run_command( 'rscan', ['hyp1'], '-w' );
is( node_attribute( 'vpd', 'scanned4', 'uuid' ), $swapped,
    'rscan -w swaps the UUID of a domain whose default machine type is pc-i440fx-rhel7.1.0' );
$XCATTestHypervisor::default_machine = 'pc-i440fx-8.2';

# mkvm, rinv and rscan swap the UUID for a pc-q35-2.1 guest too.
run_command( 'mkvm', ['cn6'] );
is( domain_uuid( node_attribute( 'kvm_nodedata', 'cn6', 'xml' ) ), $swapped, 'mkvm swaps the UUID of a pc-q35-2.1 guest' );
@XCATTestHypervisor::domains = ( domain_xml( 'cn1', $uuid, '/dev/xcattest', '52:54:00:76:00:21', 'pc-q35-2.1' ) );
my @q35_rinv = run_command( 'rinv', ['cn1'] );
ok( ( grep { $_ eq $swapped } @q35_rinv ), 'rinv prints the UUID that a pc-q35-2.1 guest reports' )
  or diag( join "\n", @q35_rinv );
@XCATTestHypervisor::domains = ( domain_xml( 'scanned5', $uuid, '/dev/xcattest12', '52:54:00:76:00:2e', 'pc-q35-2.1' ) );
run_command( 'rscan', ['hyp1'], '-w' );
is( node_attribute( 'vpd', 'scanned5', 'uuid' ), $swapped, 'rscan -w stores the UUID that a pc-q35-2.1 guest reports' );

done_testing();
