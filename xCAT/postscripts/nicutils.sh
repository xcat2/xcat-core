#!/bin/bash
#
#This is network lib for confignetwork to configure bond/vlan/bridge

awk="awk"
sed="sed"
cut="cut"
sleep="sleep"
sort="sort"
ps="ps"
head="head"
readlink="readlink"
basename="basename"
udevadm="udevadm"
touch="touch"
tail="tail"
dmesg="dmesg"
grep="grep"
lspci="lspci"
ifup="ifup"
ifdown="ifdown"
nmcli="nmcli"
dirname="dirname"
ip="ip"
ifconfig="ifconfig"
brctl="brctl"
uniq="uniq"
xargs="xargs"
modprobe="modprobe"
xcatcreatedcon=''
if [ -n "$LOGLABEL" ]; then
    log_label=$LOGLABEL
else
    log_label="xcat"
fi
#########################################################################
# ifdown/ifup will not be executed in diskful provision postscripts stage
#########################################################################
reboot_nic_bool=1
if [ -z "$UPDATENODE" ] || [ $UPDATENODE -ne 1 ] ; then
    if [ "$NODESETSTATE" = "install" ] && ! grep "REBOOT=TRUE" /opt/xcat/xcatinfo >/dev/null 2>&1; then
        reboot_nic_bool=0
    fi
fi

######################################################
#
# log lines
#
# input : info or warn or error or status
#
# output : multiple lines of string
#
######################################################
function log_lines {
    local pcnt=$#
    local __level=$1
    shift
    local cmd=log_${__level}

    local hit=0
    local OIFS=$IFS
    local NIFS=$'\n'
    IFS=$NIFS
    local __msg
    for __msg in $*
    do
        IFS=$OIFS
        $cmd "$__msg"
        hit=1
        IFS=$NIFS
    done
    IFS=$OIFS

    [ $hit -eq 0 -a $pcnt -le 1 ] && \
    while read __msg;
    do
        $cmd "$__msg"
    done
}

######################################################
#
# error information
#
# input : string
#
# output : [E]: message
# return : 0
#
######################################################
function log_error {
    local __msg="$*"
    $log_print_cmd $log_print_arg "[E]:Error: $__msg"
    logger -t $log_label -p local4.err "$__msg"
    return 1
}

######################################################
#
# warning information
#
# input : string
#
# output : [W]: message
# return : 0
#
######################################################
function log_warn {
    local __msg="$*"
    $log_print_cmd $log_print_arg "[W]: $__msg"
    logger -t $log_label -p local4.info "$__msg"
    return 0
}

######################################################
#
# log information
#
# input : string
#
# output : [I]: message
# return : 0
#
######################################################
function log_info {
    local __msg="$*"
    $log_print_cmd $log_print_arg "[I]: $__msg"
    logger -t $log_label -p local4.info "$__msg"
    return 0
}

####################################################
#
# print command status
#
# input : message
#
# output : [S]: message
#
###################################################
__my_log_status=
function log_status {
    local __msg="$*"
    $log_print_cmd $log_print_arg "[S]: $__msg"

    # call my_log_status hook to triger more processing for status messages.
    if [ -n "$__my_log_status" ]; then
        $__my_log_status "$__msg"
    fi
    return 0
}

####################################################
#
# print output
#
###################################################
function log_print_default {
    printf "%s\n" "$*"
}

####################################################
#
# handle command
#
###################################################
function set_log_print {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        return 1
    fi
    shift
    local args="$*"

    eval "log_print_cmd=\"$cmd\""
    eval "log_print_arg=\"$args\""
}

# let log work
[ -z "$log_print" ] && set_log_print "log_print_default"

#####################################################
#
# uniq line in cfg files
#
# input : -t"str_for_FS" -k"num"
#
# output : text have no duplicate linkes
#
#####################################################
function uniq_per_key {
    local fs=""
    local keyno=0

    local opt
    while getopts "t:k:" opt;
    do
        case $opt in
            t) fs="$OPTARG";;
            k) keyno="$OPTARG";;
        esac
    done
    shift $(($OPTIND - 1))

    $awk ${fs:+"-F"}"$fs" -v keyno=$keyno '
    BEGIN { cnt=0; }
    {
        if(!($keyno in keya)) {
            keya[$keyno]=cnt;
            cnt+=1;
        };
        idx=keya[$keyno];
        vala[idx]=$0;
    }
    END {
        for(i = 0; i < cnt; i++) {
            print vala[i];
        };
    }'
}

##################################################################################
#
# load kernel module
#
# input : module=<type> retry=<retry_times> interval=<time> -- <module_parameters>
#
################################################################################
function load_kmod {
    local lines=""

    local retry=0
    local interval=0
    local module=""
    local module_parameters=""

    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | cut -s -d= -f1`
        if [ "$key" = "retry" ] || \
           [ "$key" = "interval" ] || \
           [ "$key" = "module" ]; then
            eval "$1"
        elif [ "$1" = "--" ]; then
            shift
            module_parameters="$*"
            break
        fi
        shift
    done

    if [ -z "$module" ]; then
        log_error "Empty kernel module name to be loaded!"
    fi

    # load the module
    ((i=0))
    while [ ! -d /sys/module/$module ];
    do
        [ $i -eq 0 ] && lines=`$modprobe $module $module_parameters 2>&1`
        $sleep $interval
        ((i+=1))
        [ $i -ge $retry ] && break
    done
    if [ $i -ge $retry ]; then
        log_error "Fail to load kernel module \"$module\""
        echo "$lines" \
        | $sed -e 's/^/>> /g' \
        | log_lines info
        $false
    fi
}


#################################################################
#
# query nicextraparams from nics table
# example: nicextraparams.eth0="MTU=9000 something=yes"
# input: nic, here is eth0
# output: set value for globe ${array_extra_param_names}
#         and ${array_extra_param_values}
#         example:
#         array_extra_param_names[0]="MTU"
#         array_extra_param_values[0]="9000"
#         array_extra_param_names[1]="something"
#         array_extra_param_values[0]="yes"
#
#################################################################
function query_extra_params {
    # reset global variables
    unset array_nic_params
    unset array_extra_param_names
    unset array_extra_param_values

    nic=$1
    if [ -z "$nic" ]; then
        return
    fi
    get_nic_extra_params $nic "$NICEXTRAPARAMS"
    j=0
    while [ $j -lt ${#array_nic_params[@]} ]
    do
        #get key=value pair from nicextraparams
        #for example: MTU=9000
        exparampair="${array_nic_params[$j]}"
        j=$((j+1))
    done
    if [ ${#array_nic_params[@]} -gt 0 ]; then
        #Current confignetwork only support one ip for vlan/bond/bridge
        #So only need the first ${array_nic_params[0]} for first nicips
        #TODO: support multiple nicips for vlan/bond/bridge
        str_extra_params=${array_nic_params[0]}
        parse_nic_extra_params "$str_extra_params"
    fi

}

#################################################################
#
# query attribute from networks table
#
# input : fkey=<number> vkey=<attribute> fval=<number>
#
# output : found attribute value
#
###############################################################
function query_nicnetworks {
    local fkey=2
    local vkey=$1
    local fval=1

    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | cut -s -d= -f1`
        if [ "$key" = "fkey" ] || \
           [ "$key" = "vkey" ] || \
           [ "$key" = "fval" ]; then
            eval "$1"
        fi
        shift
    done

    local vval=`echo "$NICNETWORKS" | $sed -e 's/,/\n/g' \
    | $awk -v fkey=$fkey -v vkey=$vkey -v fval=$fval -F'!' \
        '$fkey == vkey {r=$fval;} END{print r;}'`
    [ -n "$vval" ] && echo "$vval"
}

###############################################################
#
# query networks nic from networks table
#
# input : netname, such as 30_0_0_0-255_0_0_0
#
# output : nic
#
###########################################################
function query_nicnetworks_nic {
    query_nicnetworks fkey=2 vkey=$1 fval=1
}

#############################################################
#
# query netname from networks table
#
# input : nic
#
# output : netname
#
#############################################################
function query_nicnetworks_net {
    query_nicnetworks fkey=1 vkey=$1 fval=2
}

#######################################################################################
#
# get network attribute from NETWORKS_LINEX
#
# NETWORKS_LINES=2
# NETWORKS_LINE1='netname=10_0_0_0-255_255_255_0||net=10.0.0.0||mask=255.255.255.0||mgtifname=eth2||gateway=&lt;xcatmaster&gt;||dhcpserver=||tftpserver=10.0.0.153||nameservers=||ntpservers=||logservers=||dynamicrange=10.0.0.1-10.0.0.254||staticrange=||staticrangeincrement=||nodehostname=||ddnsdomain=||vlanid=||domain=||mtu=||disable=||comments=__BEAT_IPRANGE_10.0.0.1-10.0.0.254'
# NETWORKS_LINE2='netname=10_9_10_0-255_255_255_0||net=10.9.10.0||mask=255.255.255.0||mgtifname=eth1:1||gateway=&lt;xcatmaster&gt;||dhcpserver=||tftpserver=10.9.10.1||nameservers=||ntpservers=||logservers=||dynamicrange=||staticrange=10.9.10.11-10.9.10.30||staticrangeincrement=1||nodehostname=||ddnsdomain=||vlanid=||domain=||mtu=||disable=||comments=__BEAT_IPRANGE_10.9.10.11-10.9.10.30'
#
# input : network_name attribute_name
#
# output : attribute value
#
########################################################################################
function get_network_attr {
   local netname=$1
   local attrname=$2

   local netline=""
   local index=1
   while [ $index -le $NETWORKS_LINES ]
   do
       eval netline=\$NETWORKS_LINE$index
       echo "$netline" | grep -sq ".*netname=$netname" && break;
       ((index+=1))
   done

   if [ $index -le $NETWORKS_LINES ]; then
       echo "$netline" | $sed -e 's/||/\n/g' | $awk -F'=' '$1 == "'$attrname'" {print $2}'
   else
       return 1
   fi
}

#######################################################################
#
# get mac
#
# input : nic name
#
# output : its mac
#
######################################################################
function get_mac {
    declare ifname=$1
    # if bond slave interface, get its real mac
    if [ -L /sys/class/net/$ifname/master ]; then
        declare ifmaster=`ls -l /sys/class/net/$ifname/master | $sed -e 's/^.*virtual\/net\///g'`
        grep -E "^Slave Interface:|^Permanent HW addr:" /proc/net/bonding/$ifmaster \
        | grep -A1 ": $ifname" | $tail -n1 | $awk '{print $4}'

    # confirm the interface does exist before running "ip link show" command
    elif [ -L /sys/class/net/$ifname ]; then
        $ip link show $ifname | grep "link\/ether" | $awk '{print $2}'
    fi
}

####################################################################
#
# wait for nic state
#
# input : <nic> <expect_state> <try_count> <sleep_time>
#
####################################################################
function wait_for_ifstate {
    local ifname=$1
    local ifstate=$2
    local tryCnt=$3
    local tryInt=$4
    local state=""
    local i
    ((i=0))
    while [ $i -lt $tryCnt ]
    do
        lines=`$ip link show $ifname`
        echo "$lines" | grep -sq "state $ifstate"
        rc=$?
        [ $rc -eq 0 ] && break

        if [ $tryInt -ne 0 ]; then
            state=`echo "$lines" | grep "state" | $sed -e 's/^.*state \([a-zA-Z]\+\) .*$/\1/g'`
            log_info "State of \"$ifname\" was \"$state\" instead of expected \"$ifstate\". Wait $i of $tryCnt with interval $tryInt."
        fi
        $sleep $tryInt
        ((i+=1))
    done
    test $i -lt $tryCnt
}

##################################################################
#
# create ifcfg-* files
#
# input : ifname=<ifname> nwdir="cfg_file_dir" xcatnet=<xcatnet> _ipaddr=<ip> _netmask=<mask> inattrs=<attrs>
#
# return : 0 success
#
#################################################################
function create_persistent_ifcfg {
    log_info "create_persistent_ifcfg $@"

    local nwdir="/etc/sysconfig/network-scripts"

    local ifname=""
    local xcatnet=""
    local _ipaddr=""
    local _netmask=""
    local _mtu=""
    local inattrs=""

    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "nwdir" ] || \
           [ "$key" = "xcatnet" ] || \
           [ "$key" = "_ipaddr" ] || \
           [ "$key" = "_netmask" ] || \
           [ "$key" = "_mtu" ] || \
           [ "$key" = "inattrs" ]; then
            eval "$1"
        fi
        shift
    done

    local fcfg=$nwdir/ifcfg-$ifname
    # if no ip addr/mask specified explicitely, search in xCAT environment.
    if [ -n "$xcatnet" ]; then
        if [ -z "$_ipaddr" ]; then
            ifname_exp=`query_nicnetworks_nic $xcatnet`
            # search NICIPS for static config
            if [ x"$ifname_exp" == x ]; then
                ifname_exp=$ifname
            fi
            _ipaddr=`echo "$NICIPS" | $sed -e 's/,/\n/g' \
                     | $awk -vifname=$ifname_exp -F'!' '$1 == ifname{print $2}' \
                     | $awk -F'|' '{print $1}'`
        fi
        if [ -z "$_netmask" ]; then
            _netmask=`get_network_attr $xcatnet mask`
            if [ $? -ne 0 ]; then
                log_error "There is no netmask configured for network $xcatnet in networks table"
                _netmask=""
            fi
        fi

        # Query mtu value from "networks" table
        if [ -z "$_mtu" ]; then
            _mtu=`get_network_attr $xcatnet mtu`
            if [ $? -ne 0 ]; then
                _mtu=""
            fi
        fi

    fi
    query_extra_params $ifname

    local attrs=""
    attrs=${attrs}${attrs:+,}"DEVICE=$ifname"
    attrs=${attrs}${attrs:+,}"BOOTPROTO=static"
    [ -n "$_ipaddr" ] && \
    attrs=${attrs}${attrs:+,}"IPADDR=$_ipaddr"
    [ -n "$_netmask" ] && \
    attrs=${attrs}${attrs:+,}"NETMASK=$_netmask"
    [ -n "$_mtu" ] && \
    attrs=${attrs}${attrs:+,}"MTU=$_mtu"

    # NetworkManager attributes
    attrs=${attrs}${attrs:+,}"NAME=$ifname"

    # some auto-detected attributes
    # - mark vlan interfac3
    if [ -f /proc/net/vlan/$ifname ]; then
        attrs=${attrs}${attrs:+,}"VLAN=yes"
    fi

    # - mark bond interfac3
    # https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Networking_Guide/sec-Network_Bonding_Using_the_Command_Line_Interface.html#sec-Create_a_Channel_Bonding_Interface
    if [ -f /proc/net/bonding/$ifname ]; then
        attrs=${attrs}${attrs:+,}"BONDING_MASTER=yes"
    fi

    # - mark mac address for non-virtual interface.
    # Note: ignore HWADDR attribute if it's a bond slave.
    if ! echo "$inattrs" | grep -sq 'SLAVE="\?yes"\?'; then
        mac=`get_mac $ifname`
        if [ -n "$mac" -a ! -d /sys/devices/virtual/net/$ifname ]; then
            attrs=${attrs}${attrs:+,}"HWADDR=$mac"
        fi
    fi

    #add extra params
    i=0
    while [ $i -lt ${#array_extra_param_names[@]} ]
    do
        name="${array_extra_param_names[$i]}"
        value="${array_extra_param_values[$i]}"
        attrs=${attrs}${attrs:+,}"${name}=${value}"
        i=$((i+1))
    done
    # record manual and auto attributes first
    # since input attributes might overwrite them.
    #
    # record extra attributes later. They will overwrite
    # previous generated attributes if duplicate.
    [ -f $fcfg ] && mv -f $fcfg `dirname $fcfg`/.`basename $fcfg`.bak
    echo "$inattrs,$attrs" \ | $sed -e 's/,/\n/g' | grep -v "^$" \
    | $sed -e 's/=/="/' -e 's/ *$/"/' \
    | uniq_per_key -t'=' -k1 >$fcfg
    local rc=$?
    # log for debug
    echo "['ifcfg-${ifname}']" >&2
    cat $fcfg | $sed -e 's/^/ >> /g' | log_lines info
    return $rc
}

################################################################################
#
# get all physical network devices
# remove duplicate entries while keep their order.
#
# input : <cat1>=<filter1_params>,<cat2>=<filter2_params>
#
###############################################################################
function expand_ports {
    log_info "expand_ports $@"

    local i
    local ports=`echo "$1" | $sed -e 's/,/ /g'`

    # get all interfaces
    local allifs=""

    # get all physical network devices
    local alldevs=""

    local rports=""
    local p
    for p in $ports
    do
        if echo "$p" | grep -sq ".*="; then
            key=`echo "$p" | cut -s -d= -f1`
            val=`echo "$p" | cut -s -d= -f2-`

        # include direct non-virtual interface
        elif [ -L /sys/class/net/$p -a ! -d /sys/devices/virtual/net/$p ]; then
            rports=${rports}${rports:+,}$p

        # warn other direct interface, such as virtual
        else
            log_warn "Invalid member port \"$p\". Ignore it!"
        fi
    done

    # remove duplicate entries while keep their order.
    [ -n "$rports" ] && echo "$rports" | \
    $sed -e 's/,\+/,/g' -e 's/^,//' -e 's/,/\n/g' \
    | uniq_per_key -t" " -k0 \
    | $xargs | $sed -e 's/ /,/g'
}

###########################################################################
#
# migrate ip from sports to ifname
#
# input : ifname=<current_nic> sports=<pre_ports>
#
#########################################################################
function migrate_ip {
    log_info "migrate_ip $@"

    local ifname=""
    local sports=""

    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "sports" ]; then
            eval "$1"
        fi
        shift
    done

    [ -n "$sports" ] && sports=`echo "$sports" | $sed -e 's/,/ /g'`


    # loop for every source port and migrate ips and routes
    local p=""
    for p in $sports
    do
        [ -L /sys/class/net/$p ] || continue


        #route for now
        saveroutes=`$ip route | grep default | grep "dev $p"| grep via | $sed -e 's/dev .*//'`

        saveips=`$ip addr show dev $p scope global | grep inet | $sed -e 's/inet.//' | $sed -e 's/[^ ]*$//'`
        if [ -n "$saveips" ]; then
            # Migrate ip address from source ports to target port
            OIFS=$IFS
            IFS=$'\n'
            for line in $saveips
            do
                newline=`echo $line|sed 's/dynamic//g'`
                eval "$ip addr del dev $p $newline"
                log_info "$ip addr del dev $p $newline"
                eval "$ip addr add dev $ifname $newline"
                log_info "$ip addr add dev $ifname $newline"
            done
            IFS=$OIFS
        fi

        # restore saved routes which assume to be applied to the target interface
        if [ -n "$saveroutes" ]; then
            eval "$ip route add $saveroutes"
            log_info "$ip route add $saveroutes"
        fi
    done

}



###############################################################################
#
# create bridge
#
# input : bridge name
#
##############################################################################
function add_br() {

     BNAME=$1
     BRIDGE=$2

     if [[ $BRIDGE == "bridge_ovs" ]]; then
         log_info "ovs-vsctl add-br $BNAME"
         ovs-vsctl add-br $BNAME
     elif [[ $BRIDGE == "bridge" ]]; then
         log_info "brctl addbr $BNAME"
         brctl addbr $BNAME
         log_info "brctl stp $BNAME on"
         brctl stp $BNAME on
     fi
}

###############################################################################
#
# check brctl
#
##############################################################################
function check_brctl() {
    BRIDGE=$1
    if [[ $BRIDGE == "bridge_ovs" ]]; then
         type brctl >/dev/null 2>/dev/null
         if [ $? -ne 0 ]; then
             log_error "There is no brctl"
             return 1
         fi
    elif [[ $BRIDGE == "bridge" ]]; then
         type brctl >/dev/null 2>/dev/null
         if [ $? -ne 0 ]; then
             log_error "There is no brctl"
             return 1
         fi
    fi
}

###############################################################################
#
# check and set device managed
# input: network device interface
# output: 0   managed
#         1   umanaged
#
###############################################################################
function check_and_set_device_managed() {
    devname=$1
    rc=1
    log_info "check_and_set_device_managed for device $devname"
    $nmcli device show $devname >/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Device $devname not found"
        # Could not find the device we wanted. Display all devices
        $nmcli device show
    else
        $nmcli -g GENERAL.STATE device show $devname|grep unmanaged >/dev/null 2>/dev/null
        if [ $? -eq 0 ]; then
            log_info "$nmcli device set $devname managed yes"
            $nmcli device set $devname managed yes
            if [ $? -eq 0 ]; then
                rc=0
            else
                log_error "nmcli fail to set device $devname managed"
            fi
        else
            rc=0
        fi
    fi
    return $rc
}

###############################################################################
#
# create add port for bridge
#
# input : bridge name
#         port name
#
##############################################################################
function add_if() {
    BNAME=$1
    PORT=$2
    BRIDGE=$3

    if [[ $BRIDGE == "bridge_ovs" ]]; then
         log_info "ovs-vsctl add-br $BNAME"
         ovs-vsctl add-br $BNAME

        log_info "ovs-vsctl add-port $BNAME $PORT"
        ovs-vsctl add-port $BNAME $PORT
    elif [[ $BRIDGE == "bridge" ]]; then
        log_info "brctl addif $BNAME $PORT"
        brctl addif $BNAME $PORT
    fi


}

###############################################################################
#
# create raw vlan for bridge
#
# input : ifname=<ifname> _mtu=<mtu> _bridge=<bridge_name>
#
###############################################################################
function create_raw_vlan_for_br {

    log_info "create_raw_vlan_interface $@"
    local lines=""

    local ifname=""
    local _mtu=""
    local _bridge=""

    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "_mtu" ] || \
           [ "$key" = "_bridge" ]; then
            eval "$1"
        fi
        shift
    done

    #handle vlanid
    local vlanid=""
    if echo "$ifname" | grep -sq ".*\.[0-9]\+"; then
        vlanid=`echo "$ifname" | $cut -s -d. -f2-`
        ifname=`echo "$ifname" | $cut -s -d. -f1`
    elif echo "$ifname" | grep -sq ".*vla\?n\?[0-9]\+"; then
        vlanid=`echo "$ifname" | $sed -e 's/^\(.*\)vla\?n\?\([0-9]\+\)$/\2/'`
        ifname=`echo "$ifname" | $sed -e 's/^\(.*\)vla\?n\?\([0-9]\+\)$/\1/'`
    fi

    # generate raw vlan interface definition
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"

    if grep -q -i "release 6" /etc/redhat-release ; then
       cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    cfg="${cfg}${cfg:+,}USERCTL=no"
    cfg="${cfg}${cfg:+,}VLAN=yes"
    cfg="${cfg}${cfg:+,}BRIDGE=$_bridge"
    [ -n "$_mtu" ] && \
    cfg="${cfg}${cfg:+,}MTU=$_mtu"
    create_persistent_ifcfg \
        ifname=$ifname.$vlanid \
        inattrs="$cfg"

}

###############################################################################
#
# create raw bond for bridge
#
# input : ifname=<ifname> _mtu=<mtu> _bonding_opts=<string> _bridge=<bridge_name>
#
###############################################################################
function create_raw_bond_for_br {

    log_info "create_raw_bond_interface $@"
    local lines=""
    local ifname=""
    local _mtu=""
    local _bridge=""
    local _bonding_opts=""
    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "_mtu" ] || \
           [ "$key" = "_bonding_opts" ] || \
           [ "$key" = "_bridge" ]; then
            eval "$1"
        fi
        shift
    done

    # migrate bond ports ip and route to bridge
    #migrate_ip ifname=$ifname sports="$_bridge"

    # define and bring up raw bond interface
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"

    if grep -q -i "release 6" /etc/redhat-release ; then
        cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    cfg="${cfg}${cfg:+,}USERCTL=no"
    cfg="${cfg}${cfg:+,}TYPE=Bond"
    cfg="${cfg}${cfg:+,}BONDING_MASTER=yes"
    cfg="${cfg}${cfg:+,}BONDING_OPTS='$_bonding_opts'"
    cfg="${cfg}${cfg:+,}BOOTPROTO=none"
    cfg="${cfg}${cfg:+,}DHCLIENTARGS='-timeout 200'"
    cfg="${cfg}${cfg:+,}BRIDGE=$_bridge"
    [ -n "$_mtu" ] && \
    cfg="${cfg}${cfg:+,}MTU=$_mtu"
    create_persistent_ifcfg \
        ifname=$ifname \
        inattrs="$cfg"
}

###############################################################################
#
# create  bridge
#
# input : ifname=<ifname> xcatnet=<xcat_network> _ipaddr=<ip> _netmask=<netmask> _port=<port> _pretype=<nic_type> _brtype=<bridge|bridge_ovs> _mtu=<mtu> _bridge=<bridge_name>
#
###############################################################################
function create_bridge_interface {

    log_info "create_bridge_interface $@"
    local lines=""
    local ifname="" #current bridge
    local xcatnet=""
    local _ipaddr=""
    local _netmask=""
    local _brtype=""
    local _pretype=""
    local _port=""  #pre nic
    local _mtu=""
    rc=0
    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "xcatnet" ] || \
           [ "$key" = "_ipaddr" ] || \
           [ "$key" = "_netmask" ] || \
           [ "$key" = "_brtype" ] || \
           [ "$key" = "_pretype" ] || \
           [ "$key" = "_port" ] || \
           [ "$key" = "_mtu" ]; then
            eval "$1"
        fi
        shift
    done

    # let's query "nicnetworks" table about its target "xcatnet"
    if [ -n "$ifname" -a -z "$xcatnet" -a -z "$_ipaddr" ]; then
        xcatnet=`query_nicnetworks_net $ifname`
        log_info "Pickup xcatnet, \"$xcatnet\", from NICNETWORKS for interface \"$ifname\"."
    fi

    # Query mtu value from "networks" table
    if [ -z "$_mtu" ]; then
        _mtu=`get_network_attr $xcatnet mtu`
        if [ $? -ne 0 ]; then
            _mtu=""
        fi
    fi

    if [ x$_pretype == "xethernet" ]; then
        create_raw_ethernet_for_br \
            ifname=$_port \
            _bridge=$ifname \
            _mtu=$_mtu
    elif [ x$_pretype == "xvlan" ]; then
        create_raw_vlan_for_br \
            ifname=$_port \
            _bridge=$ifname \
            _mtu=$_mtu

    elif [ x$_pretype == "xbond" ]; then
        create_raw_bond_for_br \
            ifname=$_port \
            _bridge=$ifname \
            _mtu=$_mtu \
            _bonding_opts="mode=802.3ad miimon=100"
    fi

    add_br $ifname $_brtype
    add_if $ifname $_port $_brtype
    # setup interface on the fly
    [ -n "$_mtu" ] && $ip link set $ifname mtu $_mtu

    # log for debug

    migrate_ip ifname=$ifname sports="$_port"

    # define and bring up bridge interface, if required.
    # generate bridge interface definition
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"
    cfg="${cfg}${cfg:+,}STP=on"
    if grep -q -i "release 6" /etc/redhat-release ; then
        cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    if [ x$_brtype == x"bridge" ]; then

        cfg="${cfg}${cfg:+,}TYPE=Bridge"
    elif [ x$_brtype == x"bridge_ovs" ]; then

        cfg="${cfg}${cfg:+,}TYPE=OVSBridge"

    fi
    [ -n "$_mtu" ] && \
         cfg="${cfg}${cfg:+,}MTU=$_mtu"
         create_persistent_ifcfg \
             ifname=$ifname \
             xcatnet=$xcatnet \
         inattrs="$cfg"

    # bring up interface formally
    if [ $reboot_nic_bool -eq 1 ]; then
        lines=`$ifdown $ifname; $ifup $ifname`
        rc=$?
    fi
    if [ $rc -ne 0 ]; then
        log_warn "ifup $ifname failed with return code equals to $rc"
        echo "$lines" \
        | $sed -e 's/^/>> /g' \
        | log_lines info
    fi
    return $rc

}
###############################################################################
#
# create ethernet
#
# input : ifname=<ifname> slave_ports=<ports> xcatnet=<xcatnetwork> _ipaddr=<ip> _netmask=<netmask> _mtu=<mtu> _bridge=<bridge_name> vlanid=<vlanid>
#
###############################################################################
function create_ethernet_interface {
    log_info "create_ethernet_interface $@"

    local lines=""
    local ifname=""
    local mport=""
    local xcatnet=""
    local _ipaddr=""
    local _netmask=""
    local _mtu=""

    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "mport" ] || \
           [ "$key" = "xcatnet" ] || \
           [ "$key" = "_ipaddr" ] || \
           [ "$key" = "_netmask" ] || \
           [ "$key" = "_mtu" ]; then
            eval "$1"
        fi
        shift
    done
    if [ -z "$ifname" -a -z "$mport" ]; then
        log_error "No valid \"ifname\" or \"mport\". Abort!"
        return 1

    # if caller only knows the real "mport", assume it is the defined "ifname".
    elif [ -z "$ifname" ]; then
        log_info "Assume defined nic is the member nic \"$mport\"."
        ifname=$mport
    fi
    # let's query "nicnetworks" table about its target "xcatnet"
    if [ -n "$ifname" -a -z "$xcatnet" ]; then
        xcatnet=`query_nicnetworks_net $ifname`
    fi

    # Verify if there could be valid ipaddr/netmask
    if [ -z "$xcatnet" -a -z "$_ipaddr" ]; then
        log_error "No valid \"xcatnet\" or explicite \"_ipaddr/_netmask\". Abort!"
        return 1
    fi

    # Query mtu value from "networks" table
    if [ -z "$_mtu" ]; then
        _mtu=`get_network_attr $xcatnet mtu`
        if [ $? -ne 0 ]; then
            _mtu=""
        fi

    fi

    # define and bring up interface
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"

    if grep -q -i "release 6" /etc/redhat-release ; then
       cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    cfg="${cfg}${cfg:+,}USERCTL=no"
    cfg="${cfg}${cfg:+,}TYPE=Ethernet"
    [ -n "$_mtu" ] && \
    cfg="${cfg}${cfg:+,}MTU=$_mtu"
    create_persistent_ifcfg \
        ifname=$ifname \
        xcatnet=$xcatnet \
        _ipaddr=$_ipaddr \
        _netmask=$_netmask \
        inattrs="$cfg"

    # bring up interface formally
    if [ $reboot_nic_bool -eq 1 ]; then
        lines=`$ifdown $ifname; $ifup $ifname`
        rc=$?
    fi
    if [ $rc -ne 0 ]; then
        log_warn "ifup $ifname failed with return code equals to $rc"
        echo "$lines" \
        | $sed -e 's/^/>> /g' \
        | log_lines info
    fi

    return $rc
}

###############################################################################
#
# create vlan
#
# input : ifname=<ifname> slave_ports=<ports> xcatnet=<xcatnetwork> _ipaddr=<ip> _netmask=<netmask> _mtu=<mtu> _bridge=<bridge_name> vlanid=<vlanid>
# return : 0 success
#
###############################################################################
function create_vlan_interface {
    log_info "create_vlan_interface $@"

    local lines=""
    local ifname=""
    local vlanid=""
    local xcatnet=""
    local _ipaddr=""
    local _netmask=""
    local _mtu=""
    local _bridge=""
    # in case it's on top of bond, we need to migrate ip from its
    # member vlan ports.
    local slave_ports=""
    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "slave_ports" ] || \
           [ "$key" = "xcatnet" ] || \
           [ "$key" = "_ipaddr" ] || \
           [ "$key" = "_netmask" ] || \
           [ "$key" = "_mtu" ] || \
           [ "$key" = "_bridge" ] || \
           [ "$key" = "vlanid" ]; then
            eval "$1"
        fi
        shift
    done

    if [ -z "$vlanid" ]; then
        log_error "No \"vlanid\" specificd for vlan interface. Abort!"
        return 1
    fi

    # let's query "nicnetworks" table about its target "xcatnet"
    if [ -n "$ifname" -a -z "$xcatnet" -a -z "$_ipaddr" -a -n "$vlanid" ]; then
        xcatnet=`query_nicnetworks_net $ifname.$vlanid`
        log_info "Pickup xcatnet, \"$xcatnet\", from NICNETWORKS for interface \"$ifname\"."
    fi

    # Query mtu value from "networks" table
    if [ -z "$_mtu" ]; then
        _mtu=`get_network_attr $xcatnet mtu`
        if [ $? -ne 0 ]; then
            _mtu=""
        fi

    fi


    #load the 8021q module if not loaded.
    load_kmod module=8021q retry=10 interval=0.5

    # create vlan on top of target interface if that's required.
    ((i=0))
    while [ ! -f /proc/net/vlan/$ifname.$vlanid ];
    do
        if [ $i -eq 0 ]; then
            cmd="$ip link add link $ifname name $ifname.$vlanid type vlan id $(( 10#$vlanid ))"
            $cmd
            log_info "$cmd"
        fi
        $sleep 0.5
        ((i+=1))
        [ $i -ge 10 ] && break
    done
    if [ $i -ge 10 ]; then
        log_error "Fail to create vlan interface \"$ifname.$vlanid\""
        return 1
    fi

    [ -n "$_mtu" ] && $ip link set $ifname.$vlanid mtu $_mtu
    $ip link set $ifname.$vlanid up
    log_info "$ip link set $ifname.$vlanid up"
    wait_for_ifstate $ifname.$vlanid UP 200 1
    rc=$?

    _g_migrate_ip=1


    [ $_g_migrate_ip -eq 1 ] && \
    [ -n "$slave_ports" ] && \
    migrate_ip ifname=$ifname.$vlanid sports="$slave_ports"

    # define and bring up vlan interface on top of raw bond interface, if required.
    # generate vlan interface definition
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"

    if grep -q -i "release 6" /etc/redhat-release ; then
       cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    cfg="${cfg}${cfg:+,}USERCTL=no"
    cfg="${cfg}${cfg:+,}VLAN=yes"
    [ -n "$_mtu" ] && \
    cfg="${cfg}${cfg:+,}MTU=$_mtu"
    create_persistent_ifcfg \
        ifname=$ifname.$vlanid \
        xcatnet=$xcatnet \
        inattrs="$cfg"
    if [ x$xcatnet != x ]; then
        # bring up interface formally
        if [ $reboot_nic_bool -eq 1 ]; then
            lines=`$ifdown $ifname.$vlanid; $ifup $ifname.$vlanid`
            rc=$?
        fi
        if [ $rc -ne 0 ]; then
            log_warn "ifup $ifname.$vlanid failed with return code equals to $rc"
            echo "$lines" \
            | $sed -e 's/^/>> /g' \
            | log_lines info
        fi
    fi
    return $rc
}

###############################################################################
#
# create raw ethernet cfg file for bridge
# This is for eth-> br
#
# input : ifname=<ifname> _mtu=<mtu> _bridge=<bridge_name>
#
###############################################################################
function create_raw_ethernet_for_br {

    log_info "create_raw_eth_interface_for_br $@"

    local lines=""
    local ifname=""
    local _bridge=""
    local _mtu=""
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "_mtu" ] || \
           [ "$key" = "_bridge" ]; then
            eval "$1"
        fi
        shift
    done

    # create raw ethnet ifcfg file for bridge.
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"

    if grep -q -i "release 6" /etc/redhat-release ; then
        cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    cfg="${cfg}${cfg:+,}TYPE=Ethernet"
    cfg="${cfg}${cfg:+,}BRIDGE=$_bridge"
    cfg="${cfg}${cfg:+,}BOOTPROTO=none"
    [ -n "$_mtu" ] && \
    cfg="${cfg}${cfg:+,}MTU=$_mtu"
    create_persistent_ifcfg \
    ifname=$ifname \
    inattrs="$cfg"

}

#############################################################################################################################
#
# create bond or bond->vlan interface
# https://www.kernel.org/doc/Documentation/networking/bonding.txt
# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Networking_Guide/sec-Using_Channel_Bonding.html
#
# input : ifname=<nic> xcatnet=<xcatnetwork> _ipaddr=<ip> _netmask=<netmask> _bonding_opts=<bonding_opts> _mtu=<mtu> slave_ports=<port1,port2>
#
############################################################################################################################
function create_bond_interface {
    log_info "create_bond_interface $@"

    local lines=""
    local ifname=""
    local xcatnet=""
    local _ipaddr=""
    local _netmask=""
    local _bonding_opts=""
    local _mtu=""
    local slave_ports=""
    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "xcatnet" ] || \
           [ "$key" = "_ipaddr" ] || \
           [ "$key" = "_netmask" ] || \
           [ "$key" = "_bonding_opts" ] || \
           [ "$key" = "_mtu" ] || \
           [ "$key" = "slave_ports" ] || \
           [ "$key" = "slave_type" ]; then
            eval "$1"
        fi
        shift
    done
    _g_migrate_ip=1
    if [ -z "$slave_ports" ]; then
        log_error "No valid slave_ports defined. Abort!"
        return 1
    fi
    if [ -z "$slave_type" ] || [ x"$slave_type" = "xethernet" ]; then
        slave_type="Ethernet"
        # note:
        # - "miimon" requires drivers for each slave nic support MII tool.
        #   $ ethtool <interface_name> | grep "Link detected:"
        # - "802.3ad" mode requires a switch that is 802.3ad compliant.
        _bonding_opts="mode=802.3ad miimon=100"
    elif [ "$slave_type" = "infiniband" ]; then
        slave_type="Infiniband"
        _bonding_opts="mode=1 miimon=100 fail_over_mac=1"
    fi
    # let's query "nicnetworks" table about its target "xcatnet"
    if [ -n "$ifname" -a -z "$xcatnet" -a -z "$_ipaddr" ]; then
        xcatnet=`query_nicnetworks_net $ifname`
        log_info "Pickup xcatnet, \"$xcatnet\", from NICNETWORKS for interface \"$ifname\"."
    fi

    local cnt

    # convert the delimitor of _bonding_opts from comma to blank
    if [ -n "$_bonding_opts" ]; then
        _bonding_opts=`echo "$_bonding_opts" | $sed -e 's/,/ /g'`
    fi

    # Query mtu value from "networks" table
    if [ -z "$_mtu" ]; then
        _mtu=`get_network_attr $xcatnet mtu`
        if [ $? -ne 0 ]; then
            _mtu=""
        fi
    fi
    ##############################
    # Create target bond interface
    # if target bond device was already exists, assume succ.
    # stage 0: create interface
    # stage 1: setup bond options which need to bring down bond first
    # stage 2: setup bond slaves, apply other options on the fly and bring interface up
    # stage 3: check target interface up
    cnt=0
    while [ $cnt -lt 4 ];
    do
        # Stage 0:
        # create raw bond device on the fly, if not created yet.
        if [ $cnt -eq 0 -a ! -f /proc/net/bonding/$ifname ]; then
            # load the bonding module if not loaded.
            load_kmod module=bonding retry=10 interval=0.5

            # create required bond device
            ((i=0))
            while ! grep -sq "\b$ifname\b" /sys/class/net/bonding_masters;
            do
                [ $i -eq 0 ] && echo "+$ifname" >/sys/class/net/bonding_masters
                $sleep 0.5
                ((i+=1))
                [ $i -ge 10 ] && break
            done
            if [ $i -ge 10 -o ! -f /proc/net/bonding/$ifname ]; then
                log_error "stage 0: Fail to create bond device \"$ifname\""
                break
            fi

        # Stage 1:
        # setup bond options
        elif [ $cnt -eq 1 -a -n "$_bonding_opts" ]; then
            # 1.1) bring down bond interface before setup its attributes
            $ip link set $ifname down
            log_info "$ip link set $ifname down"
            $ip link show $ifname | $sed -e 's/^/[bond.down] >> /g' | log_lines info

            # 1.2) remove current slaves first
            local saved_slaves=$(</sys/class/net/$ifname/bonding/slaves)
            for ifslave in $saved_slaves
            do
                echo "-$ifslave" >/sys/class/net/$ifname/bonding/slaves
            done
            lines=`$(</sys/class/net/$ifname/bonding/slaves)`
            if [ -n "$lines" ]; then
                log_warn "stage 1: Cannot clean up bond slaves before setting up its attributes."
                echo "$lines" \
                | $sed -e 's/[failed.slaves] >> /g' \
                | log_lines info
            fi

            # 1.3) apply bond options
            local option
            for option in $_bonding_opts
            do
                key=`echo "$option" | $cut -s -d= -f1`
                val=`echo "$option" | $cut -s -d= -f2-`
                echo "$val" >/sys/class/net/$ifname/bonding/$key
                rc=$?
                if [ $rc -ne 0 ]; then
                    log_warn "stage 1: Fail to set bonding option \"$key\" to \"$val\" in device \"$ifname\""
                    cat /sys/class/net/$ifname/bonding/$key \
                    | $sed -e 's/^/[bond.'$key'] >>/g' \
                    | log_lines info
                fi
            done

            # 1.4) restore saved bond slaves
            for ifslave in $saved_slaves
            do
                echo "+$ifslave" >/sys/class/net/$ifname/bonding/slaves
            done
            log_info "[bond.slavesAft] >> $(</sys/class/net/$ifname/bonding/slaves)"

        # Stage 2:
        # add slave ports
        elif [ $cnt -eq 2 ]; then
            # 2.1) add new slaves
            for ifslave in `echo "$slave_ports" | $sed -e 's/,/ /g'`
            do
                # if the interface was not bonded as slave of master, do it now.
                if ! grep -sq "Slave Interface: *$ifslave *$" /proc/net/bonding/$ifname; then
                    # bring it down before adding it to the master, or the operation will fail
                    # the slave interface will be brought up implicitely after bonded to master.
                    $ip link set $ifslave down
                    log_info "$ip link set $ifslave down"

                    # log for debug
                    $ip link show $ifslave | $sed -e 's/^/[slave]: >> /g' \
                    | log_lines info >&2

                    echo "+$ifslave" >/sys/class/net/$ifname/bonding/slaves
                fi

                # define and bring up slave interfaces.
                cfg=""
                cfg="${cfg}${cfg:+,}ONBOOT=yes"

                if grep -q -i "release 6" /etc/redhat-release ; then
                    cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
                fi

                cfg="${cfg}${cfg:+,}USERCTL=no"
                cfg="${cfg}${cfg:+,}TYPE=$slave_type"
                cfg="${cfg}${cfg:+,}SLAVE=yes"
                cfg="${cfg}${cfg:+,}MASTER=$ifname"
                cfg="${cfg}${cfg:+,}BOOTPROTO=none"
                [ -n "$_mtu" ] && \
                cfg="${cfg}${cfg:+,}MTU=$_mtu"
                create_persistent_ifcfg \
                    ifname=$ifslave \
                    inattrs="$cfg"
            done
            # log for debug
            log_info "[bond.slavesNew] >> $(</sys/class/net/$ifname/bonding/slaves)"

            # 2.2) apply other bond interface options on the fly
            [ -n "$_mtu" ] && $ip link set $ifname mtu $_mtu

            # 2.3) bring interface up
            $ip link set $ifname up
            log_info "$ip link set $ifname up"

        elif [ $cnt -eq 3 ]; then
            # 3.1) Check bond interface status
            wait_for_ifstate $ifname UP 200 1
            rc=$?
            # log for debug
            $ip link show $ifname | $sed -e 's/^/[ip.link] >> /g' | log_lines info

            if [ $rc -ne 0 ]; then
                log_warn "stage 3: Fail to bring up bond interface \"$ifname\""
                break
            fi
        fi

        ((cnt+=1))
    done
    test $cnt -eq 4
    rc=$?

    # migrate slave ports ip and route to bond master
    #[ $_g_migrate_ip -eq 1 ] && \
    #migrate_ip ifname=$ifname sports="$slave_ports"

    # define and bring up raw bond interface
    # DHCLIENTARGS is optional, but default to have.
    cfg=""
    cfg="${cfg}${cfg:+,}ONBOOT=yes"

    if grep -q -i "release 6" /etc/redhat-release ; then
        cfg="${cfg}${cfg:+,}NM_CONTROLLED=no"
    fi

    cfg="${cfg}${cfg:+,}USERCTL=no"
    cfg="${cfg}${cfg:+,}TYPE=Bond"
    cfg="${cfg}${cfg:+,}BONDING_MASTER=yes"
    cfg="${cfg}${cfg:+,}BONDING_OPTS='$_bonding_opts'"
    cfg="${cfg}${cfg:+,}BOOTPROTO=none"
    cfg="${cfg}${cfg:+,}DHCLIENTARGS='-timeout 200'"
    [ -n "$_mtu" ] && \
    cfg="${cfg}${cfg:+,}MTU=$_mtu"
    create_persistent_ifcfg \
        ifname=$ifname \
        xcatnet=$xcatnet \
        inattrs="$cfg"
    if [ x$xcatnet != x ]; then
        if [ $reboot_nic_bool -eq 1 ]; then
            lines=`$ifdown $ifname; $ifup $ifname 2>&1`
            rc=$?
        fi
        if [ $rc -ne 0 ]; then
            log_warn "ifup $ifname failed with return code equals to $rc"
            echo "$lines" \
            | $sed -e 's/^/'$ifname' ifup out >> /g' \
            | log_lines info
        fi
    fi
    wait_for_ifstate $ifname UP 200 1
    rc=$?
    if [ $rc -ne 0 ]; then
        log_error "Interface \"$ifname\" could not be brought \"UP\"."
        $ip link show $ifname \
        | $sed -e 's/^/['$ifname' ip out >> /g' \
        | log_lines info
    fi

    return $rc
}

#############################################################################
#
# base64 encoded, decode first
#
# input : string
#
############################################################################
function decode_arguments {
    local rc=1
    local line=`echo "$1" | $base64 -d 2>/dev/null`
    if echo "$line" | grep -sq "^{BASE64}:"; then
        line=`echo "$line" | $sed -e 's/^{BASE64}:[ 	]*//'`
        rc=0
    fi
    echo "$line"
    return $rc
}

###############################################################################
#
# check NetworkManager
# output: 3 error
#         2 using NetworkManager but service(systemctl) can not used, this happens in RH8 postscripts
#         1 using NetworkManager
#         0 using network
#
##############################################################################
function check_NetworkManager_or_network_service() {
    #In RH7.6 postscripts stage, network service is active, but xCAT uses NetworkManager to configure IP,
    #after that, xCAT disable NetworkManager, when CN is booted, CN use network service.
    #In RH8, there is only NetworkManager
    #So check network service should before check NetworkManager.
    checkservicestatus network > /dev/null 2>/dev/null || checkservicestatus wicked > /dev/null 2>/dev/null 
    if [ $? -eq 0 ]; then
        stopservice NetworkManager | log_lines info
        disableservice NetworkManager | log_lines info
        log_info "network service is active"
        return 0
    fi
    #check NetworkManager is active
    checkservicestatus NetworkManager > /dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
        log_info "NetworkManager is active"
        #check nmcli is installed
        type $nmcli >/dev/null 2>/dev/null
        if [ $? -ne 0 ]; then
            log_error "There is no nmcli"
        else
            return 1
        fi
    fi
    #In RH8 postscripts stage, nmcli can not modify persistent configure file
    ps -ef|grep -v grep|grep NetworkManager >/dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
        return 2
    fi
    checkservicestatus networking > /dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
        stopservice NetworkManager | log_lines info
        disableservice NetworkManager | log_lines info
        log_info "networking service is active"
        return 0
    fi
    log_error "NetworkManager, network.service and networking service are not active"
    return 2
}

###############################################################################
#
# check nmcli connection name existed or not
# input: network connetion
# return: 0  connection exists
#         1  connection does not exist
#
##############################################################################
function is_nmcli_connection_exist {

    str_con_name=$1
    # the device str_if_name active connectin
    nmcli -g NAME connection show |grep -w $str_con_name >/dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi

}

###############################################################################
#
# get first addr from nicips if it is valid ipv4 addr
# input: nics.nicips for one nic
# return 0, output: ipv4 addr
# return 1, output error: "IP: $IP not available" or "$IP: IP format error"
#
###############################################################################
function get_first_addr_ipv4 {

    str_ips=$1
    res=1
    if [ -n "$str_ips" ]; then
        IP=$(echo "$str_ips"|awk -F"|" '{print $1}')
        if [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            FIELD1=$(echo $IP|cut -d. -f1)
            FIELD2=$(echo $IP|cut -d. -f2)
            FIELD3=$(echo $IP|cut -d. -f3)
            FIELD4=$(echo $IP|cut -d. -f4)
            if [ $FIELD1 -gt 0 -a $FIELD1 -lt 255 -a $FIELD2 -le 255 -a $FIELD3 -le 255 -a $FIELD4 -le 255 -a $FIELD4 -gt 0 ]; then
                echo "$IP"
                res=0
            else
                log_error "IP: $IP invalid"
            fi
        else
            log_error "$IP: IP format error"
        fi
    fi
    return $res
}

###############################################################################
#
# create vlan using nmcli
#
# input : ifname=<ifname> vlanid=<vlanid> ipaddrs=<ipaddrs> next_nic=<next_nic>
# return : 0 success
#
###############################################################################
function create_vlan_interface_nmcli {
    log_info "create_vlan_interface_nmcli $@"
    local ifname=""
    local vlanid=""
    local ipaddrs=""
    local _ipaddrs=""
    local _xcatnet=""
    local _netmask=""
    local _mtu=""
    local next_nic=""
    rc=0
    # in case it's on top of bond, we need to migrate ip from its
    # member vlan ports.
    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "ipaddrs" ] || \
           [ "$key" = "next_nic" ] || \
           [ "$key" = "vlanid" ]; then
            eval "$1"
        fi
        shift
    done

    if [ -z "$vlanid" ]; then
        log_error "No \"vlanid\" specificd for vlan interface. Abort!"
        return 1
    fi
    if [ -z "$next_nic" ]; then
        _xcatnet=$(query_nicnetworks_net $ifname.$vlanid)
        log_info "Pickup xcatnet, \"$_xcatnet\", from NICNETWORKS for interface \"$ifname\"."

        _mtu_num=$(get_network_attr $xcatnet mtu)
        if [ -n "$_mtu_num" ]; then
            _mtu="mtu $_mtu_num"
        fi

        if [ ! -z "$ipaddrs" ]; then
            _netmask_long=$(get_network_attr $_xcatnet mask)
            if [ $? -ne 0 ]; then
                log_error "No valid netmask get for $ifname.$vlanid"
                return 1
            else
                ipaddr=$(get_first_addr_ipv4 $ipaddrs)
                if [ $? -ne 0 ]; then
                    log_error "No valid IP address get for $ifname.$vlanid, please check $ipaddrs"
                    return 1
                fi
                _netmask=$(v4mask2prefix $_netmask_long)
                _ipaddrs="ip4 $ipaddr/$_netmask"
            fi
        fi
    fi
    check_and_set_device_managed $ifname
    if [ $? -ne 0 ]; then
        log_error "The parent interface $ifname is unmanaged, so skip $ifname.$vlanid"
        return 1
    fi
    log_info "check parent interface $ifname whether it is managed by NetworkManager"
    #load the 8021q module if not loaded.
    load_kmod module=8021q retry=10 interval=0.5
    con_name="xcat-vlan-$ifname.$vlanid"
    tmp_con_name=""
    is_nmcli_connection_exist $con_name
    if [ $? -eq 0 ]; then
        tmp_con_name=$con_name"-tmp"
        cmd="$nmcli con modify $con_name connection.id $tmp_con_name"
        log_info $cmd
        $cmd
    fi
    #create VLAN connetion
    cmd="$nmcli con add type vlan con-name $con_name dev $ifname id $(( 10#$vlanid )) method none $_ipaddrs $_mtu connection.autoconnect-priority 9 autoconnect yes connection.autoconnect-slaves 1 connection.autoconnect-retries 0"
    log_info $cmd
    $cmd
    log_info "create NetworkManager connection for $ifname.$vlanid"

    #add extra params
    add_extra_params_nmcli $ifname.$vlanid $con_name
    [ $? -ne 0 ] && rc=1

    if [ -z "$next_nic" ]; then
        $nmcli con up $con_name
        is_connection_activate_intime $con_name
        is_active=$?
        if [ "$is_active" -eq 0 ]; then
            log_error "The vlan configuration for $ifname.$vlanid can not be booted up"
            $nmcli con delete $con_name
            if [ ! -z "$tmp_con_name" ]; then
                $nmcli con modify $tmp_con_name connection.id $con_name
            fi
            return 1
        fi
    fi
    if [ -n "$tmp_con_name" ]; then
        $nmcli con delete $tmp_con_name
    fi
    $ip address show dev $ifname.$vlanid | $sed -e 's/^/[vlan] >> /g' | log_lines info
    return $rc
}
###############################################################################
#
# add extra params for nmcli connection 
#
# input : $1 nic device
#         $2 nmcli connection name
# return : 1 error
#          0 successful
#
###############################################################################
function add_extra_params_nmcli {

    nicdev=$1
    con_name=$2
    rc=0
    str_conf_file="/etc/sysconfig/network-scripts/ifcfg-${con_name}"
    str_conf_file_1="/etc/sysconfig/network-scripts/ifcfg-${con_name}-1"
    if [ -f $str_conf_file_1 ]; then
        grep -x "NAME=$con_name" $str_conf_file_1 >/dev/null 2>/dev/null
        if [ $? -eq 0 ]; then
            str_conf_file=$str_conf_file_1
        fi
    fi
    #query extra params
    query_extra_params $nicdev
    i=0
    while [ $i -lt ${#array_extra_param_names[@]} ]
    do
        name="${array_extra_param_names[$i]}"
        value="${array_extra_param_values[$i]}"
        if [ -n "$name" -a -n "$value" ]; then
            grep $name $str_conf_file >/dev/null 2>/dev/null
            if [ $? -eq 0 ]; then
                replacevalue="$name=$value"
                sed -i "s/^$name=.*/$replacevalue/" $str_conf_file
            else
                echo "$name="$value"" >> $str_conf_file
            fi
        else
            log_error "invalid extra params $name $value, please check nics.nicextraparams"
            rc=1
        fi
        i=$((i+1))
    done
    $nmcli con reload $str_conf_file
    return $rc
}

###############################################################################
#
# is_connection_activate_intime
#
# input : connection_name
#         time_out (optional, 40 seconds by default)
# return : 1 active
#          0 failed
#
###############################################################################

function is_connection_activate_intime {
    con_name=$1
    time_out=40
    if [ ! -z "$2" ]; then
        time_out=$2
    fi
    i=0
    while [ $i -lt "$time_out" ]; do
        con_state=$($nmcli con show $con_name | grep -i state| awk '{print $2}');
        if [ ! -z "$con_state" -a "$con_state" = "activated" ]; then
            break
        fi
        sleep 1
        i=$((i+1))
    done
    if [ $i -ge "$time_out" ]; then
        return 0
    else
        return 1
    fi
}

###############################################################################
#
# wait_nic_connect_intime
#
# input : nic name
#         time_out (optional, 40 seconds by default)
# return : connection name
#
###############################################################################

function wait_nic_connect_intime {
    nic_name=$1
    time_out=40
    con_name=''
    if [ ! -z "$2" ]; then
        time_out=$2
    fi
    i=0
    while [ $i -lt "$time_out" ]; do
	con_name=$(nmcli dev show $nic_name|grep GENERAL.CONNECTION|awk -F: '{print $2}'|sed 's/^[ \t]*//g')
        if [ ! -z "$con_name" -a "$con_name" != "--" ]; then
            break
        fi
        sleep 1
        i=$((i+1))
    done
    echo $con_name
}

###############################################################################
#
# create  bridge
#
# input : ifname=<ifname> _ipaddr=<ip> _port=<port> _pretype=<nic_type> _brtype=<bridge>
# success: return 0
#
###############################################################################
function create_bridge_interface_nmcli {
    log_info "create_bridge_interface_nmcli $@"
    local ifname="" #current bridge
    local _brtype=""
    local _pretype=""
    local _port=""  #pre nic
    local _mtu=""
    local xcatnet=""
    local _ipaddr=""
    rc=0
    # parser input arguments
    while [ -n "$1" ];
    do
        key=`echo "$1" | $cut -s -d= -f1`
        if [ "$key" = "ifname" ] || \
           [ "$key" = "_brtype" ] || \
           [ "$key" = "_pretype" ] || \
           [ "$key" = "_port" ] || \
           [ "$key" = "_ipaddr" ]; then
            eval "$1"
        fi
        shift
    done
    # query "nicnetworks" table about its target "xcatnet"
    xcatnet=$(query_nicnetworks_net $ifname)
    log_info "Pickup xcatnet, \"$xcatnet\", from NICNETWORKS for interface \"$ifname\"."

    # Query mtu value from "networks" table
    _mtu_num=$(get_network_attr $xcatnet mtu)
    if [ -n "$_mtu_num" ]; then
        _mtu="mtu $_mtu_num"
    fi

    # Query mask value from "networks" table
    _netmask=$(get_network_attr $xcatnet mask)
    if [ $? -ne 0 ]; then
        log_error "No valid netmask get for $ifname"
        return 1
    fi
    # Calculate prefix based on mask
    str_prefix=$(v4mask2prefix $_netmask)

    # Get first valid ip from nics.nicips
    ipv4_addr=$(get_first_addr_ipv4 $_ipaddr)
    if [ $? -ne 0 ]; then
        log_error "No valid IP address get for $ifname, please check $ipaddrs"
        return 1
    fi
    # Check and set slave device status
    # If slave device failed to managed, return 1
    check_and_set_device_managed $_port
    if [ $? -ne 0 ]; then
        return 1
    fi
    # Create bridge connection
    xcat_con_name="xcat-bridge-"$ifname
    tmp_con_name=$xcat_con_name"-tmp"
    if [ x"$_brtype" = "xbridge" ]; then
        is_nmcli_connection_exist $xcat_con_name
        if [ $? -eq 0 ] ; then
            is_connection_activate_intime $xcat_con_name 1
            if [ $? -eq 1 ]; then
                log_info "$xcat_con_name exists, down it first"
                $nmcli con down $xcat_con_name
                $ip link set dev $ifname down
            fi
            log_info "$xcat_con_name exists, rename old $xcat_con_name to $tmp_con_name"
            $nmcli con modify $xcat_con_name connection.id $tmp_con_name autoconnect no
            if [ $? -ne 0 ] ; then
                log_error "$nmcli rename $xcat_con_name failed"
                return 1
            fi
        fi
        log_info "create bridge connection $xcat_con_name"
        cmd="$nmcli con add type bridge con-name $xcat_con_name ifname $ifname $_mtu connection.autoconnect-priority 9 autoconnect yes connection.autoconnect-retries 0 connection.autoconnect-slaves 1"
        log_info $cmd
        $cmd
        if [ $? -ne 0 ]; then
            log_error "nmcli failed to add bridge $ifname"
            is_nmcli_connection_exist $tmp_con_name
            if [ $? -eq 0 ] ; then
                $nmcli con modify $tmp_con_name connection.id $xcat_con_name
            fi
            return 1
        fi
    else
        log_error "$_brtype is not supported."
        return 1
    fi

    # Create slaves connection
    xcat_slave_con="xcat-br-slave-"$_port
    tmp_slave_con_name=$xcat_slave_con"-tmp"
    if [ x"$_pretype" = "xethernet" -o x"$_pretype" = "xvlan" -o x"$_pretype" = "xbond" ]; then
        is_nmcli_connection_exist $xcat_slave_con
        if [ $? -eq 0 ] ; then
            is_connection_activate_intime $xcat_slave_con 1
            if [ $? -eq 1 ]; then
                $nmcli con down $xcat_slave_con
                $ip link set dev $_port down
            fi
            log_info "$xcat_slave_con exists, rename old connetion $xcat_slave_con to $tmp_slave_con_name"
            $nmcli con modify $xcat_slave_con connection.id $tmp_slave_con_name autoconnect no
            if [ $? -ne 0 ] ; then
                log_error "$nmcli rename $xcat_slave_con failed"
                return 1
            fi
        fi
        con_use_same_dev=$(wait_nic_connect_intime $_port)
        if [ "$con_use_same_dev" != "--" -a -n "$con_use_same_dev" ]; then
            cmd="$nmcli con mod "$con_use_same_dev" master $ifname $_mtu connection.autoconnect-priority 9 autoconnect yes connection.autoconnect-slaves 1 connection.autoconnect-retries 0"
            xcat_slave_con=$con_use_same_dev
        else
            cmd="$nmcli con add type $_pretype con-name $xcat_slave_con ifname $_port master $ifname $_mtu connection.autoconnect-priority 9 autoconnect yes connection.autoconnect-slaves 1 connection.autoconnect-retries 0"
        fi
        log_info "create $_pretype slaves connetcion $xcat_slave_con for bridge"
        log_info "$cmd"
        $cmd
        if [ $? -ne 0 ]; then
            log_error "nmcli failed to add bridge slave $_port"
            is_nmcli_connection_exist $tmp_slave_con_name
            if [ $? -eq 0 ] ; then
                $nmcli con modify $tmp_slave_con_name connection.id $xcat_slave_con
            fi
            return 1
        fi
    else
        log_error "create $_pretype slaves for bridge is not supported"
        return 1
    fi

    # Add ip to bridge
    if [ -n "$ipv4_addr" ]; then
        log_info "add ip $ipv4_addr/$str_prefix to bridge"
        $nmcli con mod $xcat_con_name ipv4.method manual ipv4.addresses $ipv4_addr/$str_prefix;
    fi

    # add extra params
    add_extra_params_nmcli $ifname $xcat_con_name
    [ $? -ne 0 ] && rc=1
    # bring up interface formally
    log_info "$nmcli con up $xcat_con_name" 
    $nmcli con up $xcat_con_name
    [ $? -ne 0 ] && rc=1
    log_info "$nmcli con up $xcat_slave_con"
    $nmcli con up $xcat_slave_con
    # If bridge interface is active, delete tmp old connection
    # If bridge interface is not active, delete new bridge and slave connection, and restore old connection
    is_connection_activate_intime $xcat_con_name
    is_active=$?
    if [ "$is_active" -eq 0 ]; then
        log_error "$nmcli con up $xcat_con_name failed with return code equals to $is_active"
        $nmcli con delete $xcat_con_name
        is_nmcli_connection_exist $tmp_con_name
        if [ $? -eq 0 ]; then
            nmcli con modify $tmp_con_name connection.id $xcat_con_name
        fi
        $nmcli con delete $xcat_slave_con
        is_nmcli_connection_exist $tmp_slave_con_name
        if [ $? -eq 0 ]; then
            nmcli con modify $tmp_slave_con_name connection.id $xcat_slave_con
        fi
    else
        is_nmcli_connection_exist $tmp_con_name
        if [ $? -eq 0 ]; then
            $nmcli con delete $tmp_con_name
        fi
        is_nmcli_connection_exist $tmp_slave_con_name
        if [ $? -eq 0 ]; then
            $nmcli con delete $tmp_slave_con_name
        fi
        if [ -n "$xcatcreatedcon" ]; then
            $nmcli con up $xcatcreatedcon
            log_info "$nmcli con up $xcatcreatedcon"
        fi
        wait_for_ifstate $ifname UP 40 40
        [ $? -ne 0 ] && rc=1
        $ip address show dev $ifname| $sed -e 's/^/[bridge] >> /g' | log_lines info
    fi

    return $rc
}

#############################################################################################################################
#
# create bond or bond->vlan interface
#
# input : bondname=<nic> _ipaddr=<ip> slave_ports=<port1,port2> slave_type=<base_nic_type> next_nic=<next_nic>
# return : 0 successful
#          other unsuccessful
#
############################################################################################################################
function create_bond_interface_nmcli {
    log_info "create_bond_interface_nmcli $@"
    local bondname=""
    local xcatnet=""
    local _ipaddr=""
    local _netmask=""
    local _bonding_opts=""
    local _mtu=""
    local slave_ports="" #bond slaves
    local slave_type=""
    local rc=0
    local next_nic=""
    # parser input arguments
    while [ -n "$1" ];
    do
        key=$(echo "$1" | $cut -s -d= -f1)
        if [ "$key" = "bondname" ] || \
           [ "$key" = "_ipaddr" ] || \
           [ "$key" = "slave_ports" ] || \
           [ "$key" = "next_nic" ] || \
           [ "$key" = "slave_type" ]; then
            eval "$1"
        fi
        shift
    done
    if [ "$slave_type" = "ethernet" ]; then
        slave_type="Ethernet"
        # - "802.3ad" mode requires a switch that is 802.3ad compliant.
        _bonding_opts="mode=802.3ad,miimon=100"
    elif [ "$slave_type" = "infiniband" ]; then
        slave_type="Infiniband"
        _bonding_opts="mode=1,miimon=100,fail_over_mac=1"
    else
        _bonding_opts="mode=active-backup"
    fi
    if [ -n "$_ipaddr" ]; then
        # query "nicnetworks" table about its target "xcatnet"
        xcatnet=$(query_nicnetworks_net $bondname)
        log_info "Pickup xcatnet, \"$xcatnet\", from NICNETWORKS for interface \"$bondname\"."

        # Query mtu value from "networks" table
        _mtu_num=$(get_network_attr $xcatnet mtu)
        if [ -n "$_mtu_num" ]; then
            _mtu="mtu $_mtu_num"
        fi

        # Query mask value from "networks" table
        _netmask=$(get_network_attr $xcatnet mask)
        if [ $? -ne 0 ]; then
            log_error "No valid netmask get for $bondname"
            return 1
        fi
            
        # Calculate prefix based on mask
        str_prefix=$(v4mask2prefix $_netmask)

        # Get first valid ip from nics.nicips
        ipv4_addr=$(get_first_addr_ipv4 $_ipaddr)
        if [ $? -ne 0 ]; then
            log_warn "No valid IP address get for $bondname, please check $ipaddrs"
            return 1
        fi
        
    fi
    # check if all slave dev managed or not by nmcli
    xcat_slave_ports=$(echo "$slave_ports" | $sed -e 's/,/ /g')
    for ifslave in $xcat_slave_ports
    do
        check_and_set_device_managed $ifslave
        if [ $? -ne 0 ]; then
            return 1
        fi

    done

    # check if bond connection exist or not
    xcat_con_name="xcat-bond-"$bondname
    tmp_con_name=""
    is_nmcli_connection_exist $xcat_con_name
    if [ $? -eq 0 ]; then
        is_connection_activate_intime $xcat_con_name 1 
        if [ $? -eq 1 ]; then
            $nmcli con down $xcat_con_name
            $ip link set dev $bondname down
            wait_for_ifstate $bondname DOWN 40 1
        fi 
        tmp_con_name="$xcat_con_name-tmp"
        log_info "$xcat_con_name exists, rename old $xcat_con_name to $tmp_con_name"
        $nmcli con modify $xcat_con_name connection.id $tmp_con_name autoconnect no
        if [ $? -ne 0 ] ; then
            log_error "$nmcli rename $xcat_con_name failed"
            return 1
        fi
    fi

    # create raw bond device
    log_info "create bond connection $xcat_con_name"
    cmd=""
    if [ -z "$_ipaddr" ]; then
        cmd="$nmcli con add type bond con-name $xcat_con_name ifname $bondname bond.options $_bonding_opts ipv4.method disabled ipv6.method ignore autoconnect yes connection.autoconnect-priority 9 connection.autoconnect-slaves 1 connection.autoconnect-retries 0"
    else
        cmd="$nmcli con add type bond con-name $xcat_con_name ifname $bondname bond.options $_bonding_opts method none ipv4.method manual ipv4.addresses $ipv4_addr/$str_prefix $_mtu connection.autoconnect-priority 9 connection.autoconnect-slaves 1 connection.autoconnect-retries 0"
    fi
    xcatcreatedcon=$xcat_con_name
    log_info $cmd
    $cmd
    if [ $? -ne 0 ]; then
        log_error "nmcli failed to add bond connection $xcat_con_name"
        if [ -n "$tmp_con_name" ] ; then
            $nmcli con modify $tmp_con_name connection.id $xcat_con_name
        fi
        return 1
    fi

    # Create slaves connection
    xcat_slave_con_names=""
    tmp_slave_con_names=""
    for ifslave in $xcat_slave_ports
    do
        tmp_slave_con_name=""
        xcat_slave_con="xcat-bond-slave-"$ifslave
        is_nmcli_connection_exist $xcat_slave_con
        if [ $? -eq 0 ] ; then
            is_connection_activate_intime $xcat_slave_con 1
            if [ $? -eq 1 ]; then
                $nmcli con down $xcat_slave_con
                ip link set dev $ifslave down
                wait_for_ifstate $ifslave DOWN 40 1
            fi
            tmp_slave_con_name=$xcat_slave_con"-tmp"
            log_info "rename $xcat_slave_con to $tmp_slave_con_name"
            $nmcli con modify $xcat_slave_con connection.id $tmp_slave_con_name autoconnect no
            if [ -n "$tmp_slave_con_names" ]; then
                tmp_slave_con_names="$tmp_slave_con_names $tmp_slave_con_name"
            else
                tmp_slave_con_names=$tmp_slave_con_name
            fi
            
        fi
        con_use_same_dev=$(nmcli dev show $ifslave|grep GENERAL.CONNECTION|awk -F: '{print $2}'|sed 's/^[ \t]*//g')
        if [ "$con_use_same_dev" != "--" -a "$con_use_same_dev" != "$xcat_slave_con" ]; then
            $nmcli con down "$con_use_same_dev"
            $nmcli con mod "$con_use_same_dev" autoconnect no
            $ip link set dev $ifslave down 
            wait_for_ifstate $ifslave DOWN 20 2
        fi
        # InfiniBand slaves should have no MTU defined, only the bond interface
        if [ "$slave_type" = "Infiniband" ]; then
            _mtu=""
        fi
        cmd="$nmcli con add type $slave_type con-name $xcat_slave_con $_mtu ifname $ifslave master $xcat_con_name slave-type bond autoconnect yes connection.autoconnect-priority 9 connection.autoconnect-retries 0"
        log_info $cmd
        $cmd
        if [ $? -ne 0 ]; then
            log_error "nmcli failed to add bond slave connection $xcat_slave_con"
            if [ -n "$tmp_slave_con_name" ] ; then
                $nmcli con modify $tmp_slave_con_name connection.id $xcat_slave_con
            fi
            rc=1
            break
        else
            if [ -n "$xcat_slave_con_names" ]; then
                xcat_slave_con_names="$xcat_slave_con_names $xcat_slave_con"
            else
                xcat_slave_con_names=$xcat_slave_con
            fi
        fi
        cmd="$nmcli con up $xcat_slave_con"
        log_info $cmd
        $cmd
        is_connection_activate_intime $xcat_slave_con
        is_active=$?
        if [ "$is_active" -eq 0 ]; then
            log_error "The bond slave connection $xcat_slave_con can not be booted up"
            $nmcli con delete $xcat_slave_con
            if [ -n "$tmp_slave_con_name" ]; then
                $nmcli con modify $tmp_slave_con_name connection.id $xcat_slave_con
            fi
            rc=1
            break
        fi 
    done
    invalid_extra_params=0 
    if [ $rc -ne 1 ]; then 
        # add extra params
        add_extra_params_nmcli $bondname $xcat_con_name
        [ $? -ne 0 ] && invalid_extra_params=1
        # bring up interface formally
        log_info "$nmcli con up $xcat_con_name"
        $nmcli con up $xcat_con_name
        if [ -n "$_ipaddr" ]; then
            is_connection_activate_intime $xcat_con_name
            is_active=$?
            if [ "$is_active" -eq 0 ]; then
                log_error "connection $xcat_con_name failed to activate"
                rc=1
            else
                wait_for_ifstate $bondname UP 20 10
                if [ $? -ne 0 ]; then
                    rc=1
                else
                    $ip address show dev $bondname| $sed -e 's/^/[bond] >> /g' | log_lines info
                fi
            fi
        fi
    fi

    if [ $rc -eq 1 ]; then
        # delete all bond slave and master which is created by xCAT
        if [ -n "$xcat_slave_con_names" ]; then
            log_info "delete connection $xcat_slave_con_names"
            delete_bond_slaves_con "$xcat_slave_con_names"
        fi
        if [ -n "$tmp_slave_con_names" ]; then
            for tmpslave in $tmp_slave_con_names
            do  
                slavecon=$(echo $tmpslave|sed 's/-tmp$//')
                log_info "restore connection $slavecon"
                $nmcli con modify $tmpslave connection.id $slavecon 
            done
        fi
        is_nmcli_connection_exist $xcat_con_name
        if [ $? -eq 0 ] ; then
            log_info "delete bond connection $xcat_con_name"
            $nmcli con delete $xcat_con_name
        fi
        if [ -n "$tmp_con_name" ] ; then
            log_info "restore bond connection $tmp_con_name"
            $nmcli con modify $tmp_con_name connection.id $xcat_con_name
        fi
    else
        # delete  tmp master and tmp slaves 
        if [ -n "$tmp_con_name" ] ; then
            $nmcli con delete $tmp_con_name
        fi
        if [ -n "$tmp_slave_con_names" ]; then
            delete_bond_slaves_con "$tmp_slave_con_names"
        fi
    fi
    [ $invalid_extra_params -eq 1 ] && rc=$invalid_extra_params
    return $rc
}
######################################################################
#
# delete bond slaves connection
# imput format: <slave1> <slave2> <slave3> ... ...<slaven>
#
######################################################################
function delete_bond_slaves_con {
    slaves_con_names=$1
    if [ -z "$slaves_con_names" ]; then
        log_error "bond slaves connection list is empty"
        return
    fi
    for slave in $slaves_con_names
    do
        is_nmcli_connection_exist $slave
        if [ $? -eq 0 ] ; then
            $nmcli con delete $slave
        fi
    done
}
