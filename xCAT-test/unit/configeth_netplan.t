#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# Regression (issue #7454): on Ubuntu 18.04+ the network is rendered by netplan. ifupdown is
# not installed and /etc/network/interfaces.d/* is ignored entirely, so configeth's Debian
# branch configured nothing at all. It must write /etc/netplan/*.yaml and `netplan apply`.
#
# These tests drive configipv4/configipv6/delete_nic_config_files -- the branch selection that
# is the actual fix -- rather than the private write_netplan_* writers underneath them. Driving
# only the writers passes even when the netplan branch is deleted from configipv4 outright.
#
# netplan parses every file under /etc/netplan as ONE document, so anything it rejects takes the
# whole node's network with it rather than one interface. Where netplan is installed (it is on
# the ubuntu-24.04 CI runner) the last test feeds the generated tree to the real parser.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $configeth = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'configeth' );
plan skip_all => "configeth not found" unless -f $configeth;

my $src = do { local $/; open my $fh, '<', $configeth or die $!; <$fh> };

# Everything from the netplan detection through delete_nic_config_files: the writers, the
# configipv4/configipv6 dispatch, and the removal path. BAIL_OUT rather than skip, so that a
# rename which stops this matching fails loudly instead of silently covering nothing.
my ($unit) = $src =~ /^(netplan_active=0\n.*?\nfunction delete_nic_config_files\(\)\{.*?\n\})\n/ms;
BAIL_OUT('could not extract the netplan unit from configeth') unless defined $unit;

my $dir = tempdir( CLEANUP => 1 );

# The real sentinel configeth uses for "this attribute is unset" (configeth sets
# str_default_token="default"); a made-up token here would let a hard-coded literal pass.
my ($token) = $src =~ /^str_default_token="([^"]+)"/m;
BAIL_OUT('could not read str_default_token from configeth') unless defined $token;
is( $token, 'default', 'the harness drives the sentinel configeth actually uses' );

my $run_no = 0;

# Run a snippet against the extracted unit. netplan/ifup/systemctl and wait_for_ifstate are
# shadowed by shell functions, which bash resolves ahead of $PATH, so nothing here touches the
# host's network however the suite is run -- and `netplan apply` is recorded, not executed.
sub run_configeth {
    my ($script) = @_;
    $run_no++;
    my $root = File::Spec->catdir( $dir, "run$run_no" );
    mkdir $root;
    mkdir File::Spec->catdir( $root, 'etc' );
    mkdir File::Spec->catdir( $root, 'etc', 'netplan' );

    my $harness = File::Spec->catfile( $root, 'harness.sh' );
    open my $fh, '>', $harness or die $!;
    print $fh <<"PRE";
#!/bin/bash
NODE=cn1
str_default_token='$token'
str_os_type=debian
str_cfg_dir='$root/'
export NETPLAN_DIR='$root/etc/netplan'
log_info(){ :; }
log_warn(){ echo "WARN: \$*" >> '$root/warnings'; }
log_error(){ echo "ERR: \$*" >> '$root/warnings'; }
netplan(){ echo "netplan \$*" >> '$root/applied'; }
wait_for_ifstate(){ return 0; }
ip(){ :; }
v4mask2prefix(){
    local m=\$1 p=0 o
    for o in \${m//./ }; do
        case \$o in
            255) p=\$((p+8));; 254) p=\$((p+7));; 252) p=\$((p+6));; 248) p=\$((p+5));;
            240) p=\$((p+4));; 224) p=\$((p+3));; 192) p=\$((p+2));; 128) p=\$((p+1));;
        esac
    done
    echo \$p
}
parse_nic_extra_params(){
    unset array_extra_param_names array_extra_param_values
    local k=0 t
    for t in \$1; do
        array_extra_param_names[\$k]=\${t%%=*}
        array_extra_param_values[\$k]=\${t#*=}
        k=\$((k+1))
    done
}
declare -a array_extra_param_names
declare -a array_extra_param_values
PRE
    print $fh "$unit\n";
    # the detection above ran against the real host; these tests are about the netplan branch
    print $fh "netplan_active=1\n";
    print $fh "$script\n";
    close $fh;
    system( '/bin/bash', $harness ) == 0 or die "harness failed";
    return $root;
}

sub yaml_of {
    my ( $root, $nic ) = @_;
    my $f = File::Spec->catfile( $root, 'etc', 'netplan', "90-xcat-$nic.yaml" );
    return '' unless -f $f;
    local $/;
    open my $fh, '<', $f or die $!;
    my $c = <$fh>;
    # the "# xcat-state:" lines are this writer's own bookkeeping, not netplan config
    $c =~ s/^# xcat-state:.*\n//mg;
    return $c;
}

sub slurp { my ($p) = @_; return '' unless -f $p; local $/; open my $f, '<', $p or die $!; return <$f>; }

# --- configipv4 drives the netplan branch ------------------------------------
# Two addresses, an mtu, a real nicextraparams pair, and an unset-mtu sentinel.
my $r = run_configeth( <<'SH' );
configipv4 eth0 10.0.0.5 10.0.0.0 255.255.255.0 0 "MTU=1500 ONBOOT=no" 1500
configipv4 eth0 10.0.1.5 10.0.1.0 255.255.255.0 1 default default
SH

my $eth0 = yaml_of( $r, 'eth0' );
ok( length $eth0, 'configipv4 writes a netplan drop-in on a netplan node' );
like( $eth0, qr/^  ethernets:$/m, 'a plain NIC is declared under ethernets:' );
unlike( $eth0, qr/^  vlans:$/m,   'a plain NIC is not declared as a vlan' );
like( $eth0, qr/addresses:\n\s*- 10\.0\.0\.5\/24\n\s*- 10\.0\.1\.5\/24/,
    'multiple addresses keep the order they were added' );
like( $eth0, qr/^      mtu: 1500$/m, 'an MTU nicextraparam maps onto the netplan mtu key' );

# netplan merges same-id netdefs across files key by key, so an earlier cloud-init dhcp4:true
# survives unless this stanza turns it off explicitly.
like( $eth0, qr/^      dhcp4: false$/m, 'DHCP is switched off for a statically addressed NIC' );
like( $eth0, qr/^      dhcp6: false$/m, 'DHCP6 is switched off for a statically addressed NIC' );

# ONBOOT is an ifcfg key with no netplan meaning; passing it through fails the whole file.
unlike( $eth0, qr/ONBOOT/i, 'a nicextraparams key netplan does not know is not emitted' );
like( slurp("$r/warnings"), qr/ONBOOT/, 'and dropping it is reported' );

# the sentinel arm: an unset mtu must not reach the file as the literal "default"
unlike( $eth0, qr/mtu:\s*default/, 'an unset mtu is skipped rather than written as the sentinel' );

# --- an address removed from the nics table must actually go -------------------
$r = run_configeth( <<'SH' );
configipv4 eth0 10.0.0.5 10.0.0.0 255.255.255.0 0 default default
configipv4 eth0 10.0.0.99 10.0.0.0 255.255.255.0 0 default default
SH
$eth0 = yaml_of( $r, 'eth0' );
like( $eth0, qr/- 10\.0\.0\.99\/24/, 're-running with a new address writes the new address' );
unlike( $eth0, qr/- 10\.0\.0\.5\/24/, 'and the address it replaces is dropped, not accumulated' );

# --- a VLAN interface ---------------------------------------------------------
# The parent carries no address of its own, so nothing else declares it. netplan resolves link:
# at parse time, so the parent has to be in this file or the whole configuration is rejected.
$r = run_configeth( <<'SH' );
configipv4 eth1.100 10.100.0.5 10.100.0.0 255.255.255.0 0 default default
SH
my $vlan = yaml_of( $r, 'eth1.100' );
like( $vlan, qr/^  vlans:$/m,       'a <parent>.<vid> NIC is declared under vlans:' );
like( $vlan, qr/^      id: 100$/m,     'the VLAN carries its id' );
like( $vlan, qr/^      link: eth1$/m,  'the VLAN is linked to its parent interface' );
like( $vlan, qr/^  ethernets:\n    eth1: \{\}/m,
    'the VLAN parent is declared in the same file so link: resolves' );

# --- a dotted name that is NOT a vlan ----------------------------------------
$r = run_configeth( <<'SH' );
configipv4 eno1.custom 10.9.0.5 10.9.0.0 255.255.255.0 0 default default
SH
like( yaml_of( $r, 'eno1.custom' ), qr/^  ethernets:$/m,
    'a dotted name with a non-numeric suffix is not treated as a VLAN' );

# --- configipv6 drives the netplan branch too ---------------------------------
$r = run_configeth( <<'SH' );
configipv6 eth2 2001:db8::5 2001:db8:: 64 0 0 2001:db8::1 "MTU=9000 ONBOOT=no"
SH
my $v6 = yaml_of( $r, 'eth2' );
like( $v6, qr/- 2001:db8::5\/64/, 'configipv6 writes the address' );

# "to: default" is only understood from netplan 0.103; 18.04 never ships past 0.99.
like( $v6, qr/- to: ::\/0\n\s*via: 2001:db8::1/,
    'the v6 default route is written as an explicit CIDR, not the "default" alias' );
unlike( $v6, qr/to:\s*default/, 'the "default" route alias is not emitted' );
like( $v6, qr/^      mtu: 9000$/m, 'configipv6 carries nicextraparams into the stanza' );

# configipv6 takes no mtu argument; $str_nic_mtu would be whatever configipv4 last set.
$r = run_configeth( <<'SH' );
configipv4 eth3 10.0.3.5 10.0.3.0 255.255.255.0 0 default 1500
configipv6 eth4 2001:db8:4::5 2001:db8:4:: 64 0 0 default default
SH
unlike( yaml_of( $r, 'eth4' ), qr/mtu:/,
    'a v6-only NIC does not inherit the MTU of a NIC configured before it' );

# --- route de-duplication -----------------------------------------------------
$r = run_configeth( <<'SH' );
configipv6 eth5 2001:db8:5::5 2001:db8:5:: 64 0 0 2001:db8:5::1 default
configipv6 eth5 2001:db8:5::6 2001:db8:5:: 64 1 0 2001:db8:5::1 default
write_netplan_route eth5 2001:db8:9::/64 2001:db8:5::1
SH
my $eth5 = yaml_of( $r, 'eth5' );
my @defaults = ( $eth5 =~ /- to: ::\/0/g );
is( scalar(@defaults), 1, 'an identical route added twice appears once' );
like( $eth5, qr/- to: 2001:db8:9::\/64\n\s*via: 2001:db8:5::1/,
    'a second route sharing the same gateway is still written' );

# --- removal ------------------------------------------------------------------
$r = run_configeth( <<'SH' );
configipv4 eth6 10.0.6.5 10.0.6.0 255.255.255.0 0 default default
echo "eth6" > "${str_cfg_dir}xcat_history_important"
delete_nic_config_files eth6
SH
is( yaml_of( $r, 'eth6' ), '', 'delete_nic_config_files removes the netplan drop-in' );
unlike( slurp("$r/xcat_history_important"), qr/eth6/,
    'and clears the NIC from xcat_history_important, as the other branches do' );

# --- a nicextraparams name containing a regex metacharacter --------------------
$r = run_configeth( <<'SH' );
configipv4 eth7 10.0.7.5 10.0.7.0 255.255.255.0 0 "a/b=c MTU=1400" default
SH
like( yaml_of( $r, 'eth7' ), qr/^      mtu: 1400$/m,
    'a param name with a "/" does not break the recorded state around it' );

# --- the apply is scoped to the NIC being configured where the backend allows it ------
# `netplan apply` takes no interface argument and re-applies every netdef on the node, which
# during the install postscripts stage would bounce the install NIC the postscript is running
# over. Where systemd-networkd is the renderer and networkctl has the verbs, only this device
# should be reconfigured.
$r = run_configeth( <<'SH' );
networkctl(){ echo "networkctl $*" >> "$str_cfg_dir/applied"; [ "$1" = "--help" ] && echo "  reconfigure DEVICES... Reconfigure interfaces"; return 0; }
systemctl(){ return 0; }
netplan_apply eth0
SH
my $applied = slurp("$r/applied");
like( $applied, qr/^networkctl reconfigure eth0$/m,
    'the apply is scoped to the NIC being configured' );
like( $applied, qr/^netplan generate$/m,
    'the backend configuration is generated before reconfiguring the device' );
unlike( $applied, qr/^netplan apply$/m,
    'and the node-wide apply is not used when a single device can be reconfigured' );

# Ubuntu 18.04 ships systemd 237, which has no `networkctl reconfigure`; the NetworkManager
# renderer has no networkctl path at all. Both must still apply, node-wide.
$r = run_configeth( <<'SH' );
networkctl(){ echo "networkctl $*" >> "$str_cfg_dir/applied"; return 0; }
systemctl(){ return 0; }
netplan_apply eth0
SH
$applied = slurp("$r/applied");
like( $applied, qr/^netplan apply$/m,
    'a backend that cannot reconfigure one device falls back to the node-wide apply' );
unlike( $applied, qr/reconfigure/,
    'and does not attempt a verb it does not have' );

# --- and netplan itself must accept what we wrote -----------------------------
# --root-dir is a filesystem root: netplan reads <root>/etc/netplan/*.yaml, which is why the
# harness writes the drop-ins there rather than flat into the scratch directory.
SKIP: {
    my $netplan = `command -v netplan 2>/dev/null`;
    chomp $netplan;
    skip 'netplan not installed', 1 unless $netplan && -x $netplan;

    my $root = File::Spec->catdir( $dir, 'generate' );
    mkdir $root;
    mkdir File::Spec->catdir( $root, 'etc' );
    my $np = File::Spec->catdir( $root, 'etc', 'netplan' );
    mkdir $np;

    # every shape this writer emits, in one tree, the way a real node accumulates them --
    # including a netdef an earlier-sorting file already declares as DHCP
    run_configeth_into( $np, <<'SH' );
configipv4 eth0 10.0.0.5 10.0.0.0 255.255.255.0 0 "MTU=1500 ONBOOT=no" 1500
configipv4 eth0 10.0.1.5 10.0.1.0 255.255.255.0 1 default default
configipv4 eth1.100 10.100.0.5 10.100.0.0 255.255.255.0 0 default default
configipv6 eth2 2001:db8::5 2001:db8:: 64 0 0 2001:db8::1 default
SH
    open my $ci, '>', File::Spec->catfile( $np, '50-cloud-init.yaml' ) or die $!;
    print $ci "network:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true\n";
    close $ci;
    chmod 0600, glob("$np/*.yaml");

    my $out = `netplan generate --root-dir '$root' 2>&1`;
    is( $? >> 8, 0, "netplan generate accepts the generated configuration" )
      or diag($out);
}

# same harness, writing into a caller-chosen netplan directory
sub run_configeth_into {
    my ( $np, $script ) = @_;
    my $root = File::Spec->catdir( $dir, "gen_stage" );
    mkdir $root;
    my $harness = File::Spec->catfile( $root, 'harness.sh' );
    open my $fh, '>', $harness or die $!;
    print $fh <<"PRE";
#!/bin/bash
NODE=cn1
str_default_token='$token'
str_os_type=debian
str_cfg_dir='$root/'
export NETPLAN_DIR='$np'
log_info(){ :; }
log_warn(){ :; }
log_error(){ :; }
netplan(){ :; }
wait_for_ifstate(){ return 0; }
ip(){ :; }
v4mask2prefix(){
    local m=\$1 p=0 o
    for o in \${m//./ }; do
        case \$o in
            255) p=\$((p+8));; 254) p=\$((p+7));; 252) p=\$((p+6));; 248) p=\$((p+5));;
            240) p=\$((p+4));; 224) p=\$((p+3));; 192) p=\$((p+2));; 128) p=\$((p+1));;
        esac
    done
    echo \$p
}
parse_nic_extra_params(){
    unset array_extra_param_names array_extra_param_values
    local k=0 t
    for t in \$1; do
        array_extra_param_names[\$k]=\${t%%=*}
        array_extra_param_values[\$k]=\${t#*=}
        k=\$((k+1))
    done
}
declare -a array_extra_param_names
declare -a array_extra_param_values
PRE
    print $fh "$unit\nnetplan_active=1\n$script\n";
    close $fh;
    system( '/bin/bash', $harness ) == 0 or die "harness failed";
    return;
}

done_testing();
