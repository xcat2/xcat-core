#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# Regression: on a netplan-rendered node configeth took the NIC down on every reconfigure,
# while the `netplan apply` that brings it back is gated on reboot_nic_bool. In the diskful
# provision postscripts stage reboot_nic_bool is 0, so the interface went down and nothing
# brought it back until the node rebooted -- over the very NIC the postscripts are talking on.
#
# The other two arms already pair the two halves: the ifupdown arm answers `ifdown` with an
# unconditional `ifup`, and the redhat arm gates BOTH the down and the up on reboot_nic_bool.
# Only the netplan arm took one half of the pair.
#
# This drives the two blocks configeth actually executes rather than matching its text: the
# down-selection inside the modify branch, and the restart block underneath it. `ip` and
# `netplan` are shadowed by shell functions, which bash resolves ahead of $PATH, so the host's
# network is never touched -- every call is recorded to a file instead.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $configeth = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'configeth' );
plan skip_all => "configeth not found" unless -f $configeth;

my $src = do { local $/; open my $fh, '<', $configeth or die $!; <$fh> };

# BAIL_OUT rather than skip: a rename that stops these matching must fail loudly instead of
# silently covering nothing.
my ($down_block) = $src =~ /\n(            if \[ "\$str_nic_status" = "up" \];then\n.*?\n            fi\n)/ms;
BAIL_OUT('could not extract the nic-down block from configeth')
  unless defined $down_block;

my ($restart_block) = $src =~ /\n(    #restart the nic\n    if \[ \$bool_restart_flag -eq 1 \];then\n.*?\n    fi\n)/ms;
BAIL_OUT('could not extract the restart block from configeth')
  unless defined $restart_block;

my $dir = tempdir( CLEANUP => 1 );
my $run_no = 0;

# Run both blocks back to back for one (reboot_nic_bool, arm) combination and return what the
# script asked the system to do, in order.
sub drive {
    my (%opt) = @_;
    $run_no++;
    my $root = File::Spec->catdir( $dir, "run$run_no" );
    mkdir $root;
    my $calls = File::Spec->catfile( $root, 'calls' );

    my $harness = File::Spec->catfile( $root, 'harness.sh' );
    open my $fh, '>', $harness or die $!;
    print $fh <<"PRE";
#!/bin/bash
NODE=cn1
str_nic_name=eth0
str_nic_status=up
str_os_type='$opt{os_type}'
netplan_active='$opt{netplan_active}'
networkmanager_active=0
reboot_nic_bool=$opt{reboot_nic_bool}
bool_modify_flag=1
bool_restart_flag=1
error_code=0
array_ip_old_temp=()
log_info(){ :; }
log_warn(){ :; }
log_error(){ echo "log_error \$*" >> '$calls'; }
ip(){ echo "ip \$*" >> '$calls'; }
ifdown(){ echo "ifdown \$*" >> '$calls'; }
ifup(){ echo "ifup \$*" >> '$calls'; }
nmcli(){ echo "nmcli \$*" >> '$calls'; }
netplan(){ echo "netplan \$*" >> '$calls'; }
networkctl(){ echo "networkctl \$*" >> '$calls'; }
netplan_apply(){ echo "netplan_apply \$*" >> '$calls'; return 0; }
wait_for_ifstate(){ echo 0; return 0; }
PRE
    print $fh $down_block, "\n", $restart_block, "\n";
    close $fh;

    system( '/bin/bash', $harness );
    return '' unless -f $calls;
    my $out = do { local $/; open my $c, '<', $calls or die $!; <$c> };
    return $out;
}

# The bug, stated as behaviour: during the install postscripts stage the NIC must not be left
# down. Either the link is not touched, or something brings it back.
my $install = drive( os_type => 'debian', netplan_active => 1, reboot_nic_bool => 0 );
my $took_down = $install =~ /^ip link set dev eth0 down/m;
my $brought_up = $install =~ /^netplan_apply/m;
ok( !$took_down || $brought_up,
    'netplan: with reboot_nic_bool=0 the NIC is not left down' );
unlike( $install, qr/^ip link set dev eth0 down/m,
    'netplan: with reboot_nic_bool=0 the link is not taken down at all' );

# The redhat arm is the reference: it has always gated both halves.
my $rh_install = drive( os_type => 'rhel', netplan_active => 0, reboot_nic_bool => 0 );
unlike( $rh_install, qr/^ip link set dev eth0 down/m,
    'redhat: with reboot_nic_bool=0 the link is not taken down (reference behaviour)' );

# ifupdown pairs its own halves unconditionally, so it may take the link down.
my $deb_install = drive( os_type => 'debian', netplan_active => 0, reboot_nic_bool => 0 );
like( $deb_install, qr/^ifdown --force eth0/m,
    'ifupdown: takes the link down' );
like( $deb_install, qr/^ifup -a -i /m,
    'ifupdown: and brings it back unconditionally, so it is never left down' );

# reboot_nic_bool=1 is the normal reconfigure: both halves must run.
my $reboot = drive( os_type => 'debian', netplan_active => 1, reboot_nic_bool => 1 );
like( $reboot, qr/^ip link set dev eth0 down/m,
    'netplan: with reboot_nic_bool=1 the link is taken down' );
like( $reboot, qr/^netplan_apply eth0/m,
    'netplan: with reboot_nic_bool=1 the apply brings it back' );

my ($down_at) = $reboot =~ /\A(.*?)^netplan_apply/ms;
ok( defined $down_at && $down_at =~ /ip link set dev eth0 down/,
    'netplan: the down happens before the apply, not after it' );

done_testing();
