#!/bin/bash
PATH="/opt/xcat/bin:/opt/xcat/sbin:/opt/xcat/share/xcat/tools:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin"
export PATH
function runcmd(){
    echo "Run command $* ..."
    result=`$*`
    if [[ $? -eq 0 ]];then
        echo -e "Run command $* ... [Succeed]\n";
        return 0;
    else
        echo -e "Run command $* ... [Failed]\n";
        return 1;
    fi
}

# We should be using private networks
TESTNODE=testnode
TESTNODE_IP="192.168.3.1"

MASTER_PRIVATE_IP="192.168.1.1"
MASTER_PRIVATE_NETMASK="255.255.0.0"
MASTER_PRIVATE_NETWORK="192_168_0_0-255_255_0_0"


function check_destiny() {
    cmd="chdef ${TESTNODE} arch=ppc64le cons=ipmi groups=all ip=${TESTNODE_IP} mac=4e:ee:ee:ee:ee:0e netboot=$NETBOOT tftpserver=$MASTER_PRIVATE_IP xcatmaster=$MASTER_PRIVATE_IP";
    runcmd $cmd;
    lsdef ${TESTNODE}

    MASTERIP=`lsdef -t site -i master -c 2>&1 | awk -F'=' '{print $2}'`;
    MASTERNET=`ifconfig  | awk "BEGIN{RS=\"\"}/\<$MASTERIP\>/{print \$1}"|head -n 1 | awk -F ' ' '{print $1}'|awk -F ":"  '{print \$1}' 2>&1`;
    NET2=`netstat -i -a|grep -v Kernel|grep -v Iface |grep -v lo|grep -v $MASTERNET|head -n 1|awk '{print $1}'`;

    echo "MASTERIP=$MASTERIP"
    echo "MASTERNET=$MASTERNET"
    echo "NET2=$NET2"

    if [[ -z $NET2 ]];then
        echo "There is no second network, could not verify the test"
        return 1;
    else
        cmd="ip addr add $MASTER_PRIVATE_IP/$MASTER_PRIVATE_NETMASK dev $NET2";
        runcmd $cmd;
        echo "Check if ip addess $MASTER_PRIVATE_IP/$MASTER_PRIVATE_NETMASK is added for $NET2"
        ip addr show $NET2
        cmd="makenetworks";
        runcmd $cmd;
        tabdump networks
        cmd="makehosts ${TESTNODE}"
        runcmd $cmd
        echo "Check if ${TESTNODE} can be found in /etc/hosts"
        grep ${TESTNODE} /etc/hosts 
        cmd="nodeset ${TESTNODE}  shell";
        runcmd $cmd;
        cmd="ip addr del $MASTER_PRIVATE_IP/$MASTER_PRIVATE_NETMASK dev $NET2";
        runcmd $cmd;
        echo "Check if 'nodeset ${TESTNODE} shell' is added to ${SHELLFOLDER}/${TESTNODE}"
        echo "==============================================="
        cat "${SHELLFOLDER}/${TESTNODE}"
        echo "==============================================="
        cat "${SHELLFOLDER}/${TESTNODE}" |grep "xcatd=${MASTER_PRIVATE_IP}:3001 destiny=shell";
        if [[ $? -eq 0 ]] ;then
            return 0;
        else
            echo "'nodeset ${TESTNODE} shell' FAILED";
            return 1;
        fi
    fi
}

function clear_env() {
    rmdef -t network -o ${MASTER_PRIVATE_NETWORK}
    makehosts -d ${TESTNODE}
    rmdef ${TESTNODE}
    if [[ $? -eq 0 ]];then
       return 0;
    else
       return 1;
    fi
}

NETBOOT=""
SHELLFOLDER=""
while [ "$#" -ge "0" ]; do
    case $1 in
        "--check" )
        NETBOOT=$2;
        if [[ $NETBOOT =~ petitboot ]];then
            SHELLFOLDER="/tftpboot/petitboot";
        elif [[ $NETBOOT =~  xnba ]];then
            SHELLFOLDER="/tftpboot/xcat/xnba/nodes"
        else
            SHELLFOLDER="/tftpboot/boot/grub2";
        fi
        check_destiny ;
        if [[ $? -eq 1 ]];then
            exit 1
        else
            exit 0
        fi
        ;;
        "-c"|"--clear" )
        clear_env;
        if [[ $? -eq 1 ]];then
            exit 1
        else
            exit 0
        fi
        ;;
        *)
        echo
        echo "Error: Usage: $0: -cd|-c"
        echo
        exit 1;
        ;;
        esac
done
