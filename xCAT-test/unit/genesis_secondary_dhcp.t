#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $doxcat = File::Spec->catfile(
    $repo_root, qw(xCAT-genesis-scripts usr bin doxcat)
);

open( my $doxcat_fh, '<', $doxcat ) or die "Unable to read $doxcat: $!";
my $source = do { local $/; <$doxcat_fh> };
close($doxcat_fh);

my ($helper) =
  $source =~ /^(secondary_nic_needs_dhcp\(\)\s*\{.*?^\}\n)/ms;
ok( defined($helper), 'doxcat defines the secondary DHCP eligibility helper' );

my ($selection) =
  $source =~ /(^\s*NICCANDIDATES=`.*?^\s*export NICSTOBRINGUP\s*$)/ms;
ok( defined($selection), 'doxcat filters candidates before exporting them' );

# Keep the test runnable against the old source for a behavioral negative control.
if ( !defined($helper) ) {
    $helper = "secondary_nic_needs_dhcp() { return 0; }\n";
}
if ( !defined($selection) ) {
    ($selection) = $source =~ /(^\s*NICSTOBRINGUP=`ip link.*?`\s*$)/m;
    $selection = defined($selection)
      ? "$selection\nexport NICSTOBRINGUP"
      : "NICSTOBRINGUP=\nexport NICSTOBRINGUP";
}

my $test_tsm_file = '"$TEST_TSM_FILE"';
my $test_sys_class_net = '"$TEST_SYS_CLASS_NET"';
$selection =~ s{/tmp/tsmhostnic}{$test_tsm_file}g;
$selection =~ s{/sys/class/net}{$test_sys_class_net}g;

my $scratch = tempdir( CLEANUP => 1 );
my ( $runner_fh, $runner ) = tempfile( DIR => $scratch, UNLINK => 1 );
print {$runner_fh} $helper;
print {$runner_fh} <<'BASH';

ip() {
    if [ "$#" -eq 1 ] && [ "$1" = link ]; then
        command cat "$TEST_FIXTURE/link-list"
    elif [ "$#" -eq 5 ] && [ "$1" = -o ] && [ "$2" = link ] &&
         [ "$3" = show ] && [ "$4" = dev ]; then
        [ ! -e "$TEST_FIXTURE/links/$5.fail" ] || return 17
        [ -f "$TEST_FIXTURE/links/$5" ] || return 18
        command cat "$TEST_FIXTURE/links/$5"
    elif [ "$#" -eq 5 ] && [ "$1" = -o ] && [ "$2" = addr ] &&
         [ "$3" = show ] && [ "$4" = dev ]; then
        [ ! -e "$TEST_FIXTURE/addrs/$5.fail" ] || return 19
        [ -f "$TEST_FIXTURE/addrs/$5" ] || return 20
        command cat "$TEST_FIXTURE/addrs/$5"
    else
        return 64
    fi
}

bootnic=$TEST_BOOTNIC
BASH
print {$runner_fh} "$selection\n";
print {$runner_fh} <<'BASH';
printf '%s\n' "$NICSTOBRINGUP"
BASH
close($runner_fh);

sub write_file {
    my ( $path, $contents ) = @_;
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh);
}

sub link_output {
    my ( $interface, $index ) = @_;
    my $flags = $interface->{flags};
    my $state = exists( $interface->{state} )
      ? $interface->{state}
      : ( $flags =~ /(?:^|,)UP(?:,|$)/ ? 'UP' : 'DOWN' );
    my $link_type = $interface->{link_type} || 'ether';

    return sprintf(
        "%d: %s: <%s> mtu 1500 qdisc noop state %s mode DEFAULT group default qlen 1000\n" .
          "    link/%s 02:00:00:00:00:%02x brd ff:ff:ff:ff:ff:ff\n",
        $index, $interface->{nic}, $flags, $state, $link_type, $index
    );
}

sub run_case {
    my ($case) = @_;
    my $root = tempdir( DIR => $scratch, CLEANUP => 1 );
    my $links = File::Spec->catdir( $root, 'links' );
    my $addrs = File::Spec->catdir( $root, 'addrs' );
    my $sys_class_net = File::Spec->catdir( $root, qw(sys class net) );
    my $devices = File::Spec->catdir( $root, 'devices' );
    my $masters = File::Spec->catdir( $root, 'masters' );
    make_path( $links, $addrs, $sys_class_net, $devices, $masters );

    my $link_list = '';
    my $index = 1;
    foreach my $interface ( @{ $case->{interfaces} } ) {
        my $nic = $interface->{nic};
        my $output = link_output( $interface, $index++ );
        $link_list .= $output;

        if ( $interface->{link_fail} ) {
            write_file( File::Spec->catfile( $links, "$nic.fail" ), '' );
        } else {
            write_file( File::Spec->catfile( $links, $nic ), $output );
        }

        if ( $interface->{addr_fail} ) {
            write_file( File::Spec->catfile( $addrs, "$nic.fail" ), '' );
        } elsif ( exists( $interface->{addresses} ) ) {
            write_file(
                File::Spec->catfile( $addrs, $nic ),
                $interface->{addresses}
            );
        }

        my $sys_nic = File::Spec->catdir( $sys_class_net, $nic );
        make_path($sys_nic);
        if ( $interface->{physical} ) {
            my $device_root = File::Spec->catdir( $devices, $nic );
            my $device = File::Spec->catdir( $device_root, 'interface' );
            make_path($device);
            if ( exists( $interface->{usb_vendor} ) ) {
                write_file(
                    File::Spec->catfile( $device_root, 'idVendor' ),
                    "$interface->{usb_vendor}\n"
                );
            }
            if ( exists( $interface->{usb_product} ) ) {
                write_file(
                    File::Spec->catfile( $device_root, 'idProduct' ),
                    "$interface->{usb_product}\n"
                );
            }
            symlink( $device, File::Spec->catfile( $sys_nic, 'device' ) )
              or die "Unable to link physical device for $nic: $!";
        }
        if ( $interface->{master} ) {
            my $master = File::Spec->catdir( $masters, $nic );
            make_path($master);
            symlink( $master, File::Spec->catfile( $sys_nic, 'master' ) )
              or die "Unable to link master for $nic: $!";
        }
    }
    write_file( File::Spec->catfile( $root, 'link-list' ), $link_list );

    my $tsm_file = File::Spec->catfile( $root, 'tsmhostnic' );
    write_file( $tsm_file, $case->{tsmnic} ) if defined( $case->{tsmnic} );

    local %ENV = (
        %ENV,
        TEST_BOOTNIC       => $case->{bootnic} || 'boot0',
        TEST_FIXTURE       => $root,
        TEST_SYS_CLASS_NET => $sys_class_net,
        TEST_TSM_FILE      => $tsm_file,
    );

    open( my $result_fh, '-|', 'bash', '--noprofile', '--norc', $runner )
      or die "Unable to run secondary DHCP harness: $!";
    my $output = do { local $/; <$result_fh> };
    close($result_fh);
    my $status = $? >> 8;
    my @actual = grep { length($_) } split /\s+/, $output;

    is( $status, 0, "$case->{name}: selector succeeds" );
    is_deeply( \@actual, $case->{expected}, "$case->{name}: selected NICs" );
}

my @cases = (
    {
        name => 'DOWN virtual interface keeps the legacy path',
        interfaces => [
            { nic => 'veth0', flags => 'BROADCAST,MULTICAST', state => 'DOWN' },
        ],
        expected => ['veth0'],
    },
    {
        name => 'DOWN interface short-circuits every ownership guard',
        tsmnic => 'eno1',
        interfaces => [
            {
                nic         => 'eno1',
                flags       => 'BROADCAST,MULTICAST',
                physical    => 1,
                master      => 1,
                usb_vendor  => '046b',
                usb_product => 'ffb0',
                addresses   => "2: eno1 inet 192.0.2.21/24 scope global eno1\n",
            },
        ],
        expected => ['eno1'],
    },
    {
        name => 'operational state does not replace the IFF_UP flag',
        interfaces => [
            { nic => 'eno2', flags => 'BROADCAST,MULTICAST', state => 'UP' },
        ],
        expected => ['eno2'],
    },
    {
        name => 'UP physical unaddressed interface is selected',
        interfaces => [
            {
                nic       => 'eno3',
                flags     => 'BROADCAST,MULTICAST,UP,LOWER_UP',
                physical  => 1,
                addresses => '',
            },
        ],
        expected => ['eno3'],
    },
    {
        name => 'UP without carrier is still administratively UP',
        interfaces => [
            {
                nic       => 'eno4',
                flags     => 'BROADCAST,MULTICAST,UP',
                state     => 'DOWN',
                physical  => 1,
                addresses => '',
            },
        ],
        expected => ['eno4'],
    },
    {
        name => 'IFF_UP is recognized as the first flag',
        interfaces => [
            { nic => 'eno5', flags => 'UP,BROADCAST', physical => 1, addresses => '' },
        ],
        expected => ['eno5'],
    },
    {
        name => 'IFF_UP is recognized as the only flag',
        interfaces => [
            { nic => 'eno6', flags => 'UP', physical => 1, addresses => '' },
        ],
        expected => ['eno6'],
    },
    {
        name => 'IFF_UP is recognized as the last flag',
        interfaces => [
            { nic => 'eno7', flags => 'BROADCAST,UP', physical => 1, addresses => '' },
        ],
        expected => ['eno7'],
    },
    {
        name => 'physical IPoIB interface remains eligible',
        interfaces => [
            {
                nic       => 'ib0',
                flags     => 'BROADCAST,MULTICAST,UP,LOWER_UP',
                link_type => 'infiniband',
                physical  => 1,
                addresses => '',
            },
        ],
        expected => ['ib0'],
    },
    {
        name => 'link-local IPv4 and IPv6 addresses do not claim the interface',
        interfaces => [
            {
                nic       => 'eno8',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addresses =>
                    "2: eno8 inet 169.254.10.20/16 scope link eno8\n" .
                    "2: eno8 inet6 fe80::20/64 scope link\n" .
                    "2: eno8 inet6 feb0::20/64 scope link\n",
            },
        ],
        expected => ['eno8'],
    },
    {
        name => 'global IPv4 address preserves existing ownership',
        interfaces => [
            {
                nic       => 'eno9',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addresses => "2: eno9 inet 198.51.100.9/24 scope global eno9\n",
            },
        ],
        expected => [],
    },
    {
        name => 'global IPv6 address preserves existing ownership',
        interfaces => [
            {
                nic       => 'eno10',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addresses => "2: eno10 inet6 2001:db8::10/64 scope global\n",
            },
        ],
        expected => [],
    },
    {
        name => 'global address wins when link-local addresses also exist',
        interfaces => [
            {
                nic       => 'eno11',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addresses =>
                    "2: eno11 inet6 fe80::11/64 scope link\n" .
                    "2: eno11 inet 203.0.113.11/24 scope global eno11\n",
            },
        ],
        expected => [],
    },
    {
        name => 'TSM-owned interface is excluded by exact name',
        tsmnic => 'eno12',
        interfaces => [
            {
                nic       => 'eno12',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addresses => '',
            },
        ],
        expected => [],
    },
    {
        name => 'known management USB devices are excluded before setup markers',
        interfaces => [
            {
                nic         => 'enp18s0f0u1',
                flags       => 'BROADCAST,MULTICAST,UP',
                physical    => 1,
                usb_vendor  => '046b',
                usb_product => 'ffb0',
                addresses   => '',
            },
            {
                nic         => 'enp18s0f0u2',
                flags       => 'BROADCAST,MULTICAST,UP',
                physical    => 1,
                usb_vendor  => '04b3',
                usb_product => '4010',
                addresses   => '',
            },
        ],
        expected => [],
    },
    {
        name => 'other USB device identities remain eligible',
        interfaces => [
            {
                nic         => 'enp18s0f0u3',
                flags       => 'BROADCAST,MULTICAST,UP',
                physical    => 1,
                usb_vendor  => '046b',
                usb_product => 'ffb1',
                addresses   => '',
            },
            {
                nic         => 'enp18s0f0u4',
                flags       => 'BROADCAST,MULTICAST,UP',
                physical    => 1,
                usb_vendor  => '04b4',
                usb_product => '4010',
                addresses   => '',
            },
            {
                nic         => 'enp18s0f0u5',
                flags       => 'BROADCAST,MULTICAST,UP',
                physical    => 1,
                usb_vendor  => '046c',
                usb_product => 'ffb0',
                addresses   => '',
            },
            {
                nic         => 'enp18s0f0u6',
                flags       => 'BROADCAST,MULTICAST,UP',
                physical    => 1,
                usb_vendor  => '04b3',
                usb_product => '4011',
                addresses   => '',
            },
        ],
        expected => [
            'enp18s0f0u3', 'enp18s0f0u4',
            'enp18s0f0u5', 'enp18s0f0u6'
        ],
    },
    {
        name => 'TSM ownership does not use substring matching',
        tsmnic => 'eno130',
        interfaces => [
            {
                nic       => 'eno13',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addresses => '',
            },
        ],
        expected => ['eno13'],
    },
    {
        name => 'UP virtual interface is excluded',
        interfaces => [
            { nic => 'vnet0', flags => 'BROADCAST,MULTICAST,UP', addresses => '' },
        ],
        expected => [],
    },
    {
        name => 'UP physical slave is excluded',
        interfaces => [
            {
                nic       => 'eno14',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                master    => 1,
                addresses => '',
            },
        ],
        expected => [],
    },
    {
        name => 'link-state query failure is closed',
        interfaces => [
            {
                nic       => 'eno15',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                link_fail => 1,
                addresses => '',
            },
        ],
        expected => [],
    },
    {
        name => 'address query failure is closed',
        interfaces => [
            {
                nic       => 'eno16',
                flags     => 'BROADCAST,MULTICAST,UP',
                physical  => 1,
                addr_fail => 1,
            },
        ],
        expected => [],
    },
    {
        name => 'caller excludes loopback, boot, and USB interfaces',
        bootnic => 'boot0',
        interfaces => [
            { nic => 'lo', flags => 'LOOPBACK,UP,LOWER_UP', physical => 1, addresses => '' },
            { nic => 'boot0', flags => 'BROADCAST,MULTICAST,UP', physical => 1, addresses => '' },
            { nic => 'usb0', flags => 'BROADCAST,MULTICAST,UP', physical => 1, addresses => '' },
            { nic => 'eno17', flags => 'BROADCAST,MULTICAST,UP', physical => 1, addresses => '' },
        ],
        expected => ['eno17'],
    },
);

run_case($_) foreach @cases;

done_testing();
