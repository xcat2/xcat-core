#!/bin/bash
PATH="/opt/xcat/bin:/opt/xcat/sbin:/opt/xcat/share/xcat/tools:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin"
export PATH
function runcmd(){
    echo "Run command $* ..."
    result=`$*`
    if [[ $? -eq 0 ]];then
        echo -e "Run command $*... [Succeed]\n";
        return 0;
    else
        echo -e "Run command $*... [Failed]\n";
        return 1;
    fi
}

# We should be using private networks
TESTNODE=testnode
TESTNODE_IP=60.1.1.1

MASTER_PRIVATE_IP="192.168.1.1"
MASTER_PRIVATE_NETMASK="255.255.0.0"
MASTER_PRIVATE_NETWORK="192.168.0.0-255_255_0_0"


function check_destiny() {
    cmd="chdef ${TESTNODE} arch=ppc64le cons=ipmi groups=all ip=${TESTNODE_IP} mac=4e:ee:ee:ee:ee:0e netboot=$NETBOOT";
    runcmd $cmd;
    lsdef ${TESTNODE}

    MASTERIP=`lsdef -t site -i master -c 2>&1 | awk -F'=' '{print $2}'`;
    MASTERNET=`ifconfig  | awk "BEGIN{RS=\"\"}/\<$MASTERIP\>/{print \$1}"|head -n 1 | awk -F ' ' '{print $1}'|awk -F ":"  '{print \$1}' 2>&1`;
    NET2=`netstat -i -a|grep -v Kernel|grep -v Iface |grep -v lo|grep -v $MASTERNET|head -n 1|awk '{print $1}'`;
    NET2IP="";

    echo "MASTERIP=$MASTERIP"
    echo "MASTERNET=$MASTERNET"
    echo "NET2=$NET2"
    echo "NET2IP=$NET2IP"

    if [[ -z $NET2 ]];then
        echo "There is no second network, could not verify the test"
        return 1;
    else
        NET2IPstring=`ifconfig $NET2 |grep inet|grep -v inet6`;
        if [[ $? -eq 0 ]];then
            echo "Something is set for $NET2IPstring ... using it." 
            NET2IP=`ifconfig $NET2 |grep inet|grep -v inet6|awk -F ' ' '{print $2}'|awk -F ":" '{print $2}'`;
            if [[ -z $NET2IP ]];then
                NET2IP=`ifconfig $NET2 |grep inet|grep -v inet6|awk -F ' ' '{print $2}'`;
            fi
        else
            NET2IP=0.0.0.0;
        fi

        # Seems like this NET2IP doesn't do anything with it, what happens if it's not in the 60 network 
        echo "The original NET2 IP is $NET2IP"
        cmd="ifconfig $NET2 $MASTER_PRIVATE_IP netmask $MASTER_PRIVATE_NETMASK";
        runcmd $cmd;
        cmd="makenetworks";
        runcmd $cmd;
        makehosts ${TESTNODE}
        cmd="nodeset ${TESTNODE}  shell";
        runcmd $cmd;
        cmd="ifconfig $NET2 $NET2IP";
        runcmd $cmd;
        echo "Check if 'nodeset ${TESTNODE} shell' is added to ${SHELLFOLDER}/${TESTNODE}"
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
