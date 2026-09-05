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
# nodeset resolves the genesis kernel by the node arch. A hardcoded ppc64le node fails on
# every other management node with "Could not find genesis.kernel.ppc64".
TESTNODE_ARCH="$(uname -m)"
# The boot-loader configuration lives under the tftp root. Overridable so the check can run
# against a scratch tree.
TFTPDIR="${TFTPDIR:-/tftpboot}"

# grub2.pm names the boot loader grub2.<arch>, with every ppc64 flavour written as "ppc".
TESTNODE_LOADER_ARCH="$TESTNODE_ARCH"
[[ $TESTNODE_LOADER_ARCH =~ ^ppc64 ]] && TESTNODE_LOADER_ARCH="ppc"
STAGED_BOOT_LOADER=""

MASTER_PRIVATE_IP="192.168.1.1"
MASTER_PRIVATE_NETMASK="255.255.0.0"
MASTER_PRIVATE_NETWORK="192_168_0_0-255_255_0_0"


# xCAT builds no grub2 network boot loader for x86_64 or aarch64. The administrator installs
# grub2.<arch> by hand -- docs/source/guides/install-guides/yum/grub2.rst. grub2.pm stops the
# configuration when the file is absent, and this case reads the configuration only.
function stage_boot_loader() {
    local loader="$TFTPDIR/boot/grub2/grub2.$TESTNODE_LOADER_ARCH";
    if [[ -e $loader ]];then
        return 0;
    fi
    mkdir -p "$TFTPDIR/boot/grub2" || return 1;
    : > "$loader" || return 1;
    STAGED_BOOT_LOADER="$loader";
    echo "Staged an empty boot loader at $loader for the check";
    return 0;
}

function unstage_boot_loader() {
    if [[ -z $STAGED_BOOT_LOADER ]];then
        return 0;
    fi
    # grub2.pm links grub2-<node> to the loader. Remove the link with the file it points at.
    rm -f "$STAGED_BOOT_LOADER" "$TFTPDIR/boot/grub2/grub2-${TESTNODE}";
    STAGED_BOOT_LOADER="";
    return 0;
}

function check_destiny() {
    cmd="chdef ${TESTNODE} arch=${TESTNODE_ARCH} cons=ipmi groups=all ip=${TESTNODE_IP} mac=4e:ee:ee:ee:ee:0e netboot=$NETBOOT tftpserver=$MASTER_PRIVATE_IP xcatmaster=$MASTER_PRIVATE_IP";
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
        # grub2.pm writes the boot configuration and only then stops on a missing boot loader,
        # so the file the check reads below exists even when nodeset failed.
        nodeset_rc=$?;
        cmd="ip addr del $MASTER_PRIVATE_IP/$MASTER_PRIVATE_NETMASK dev $NET2";
        runcmd $cmd;
        if [[ $nodeset_rc -ne 0 ]];then
            echo "'nodeset ${TESTNODE} shell' FAILED";
            return 1;
        fi
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
            SHELLFOLDER="$TFTPDIR/petitboot";
        elif [[ $NETBOOT =~  xnba ]];then
            SHELLFOLDER="$TFTPDIR/xcat/xnba/nodes"
        else
            SHELLFOLDER="$TFTPDIR/boot/grub2";
            stage_boot_loader || exit 1;
        fi
        check_destiny ;
        rc=$?;
        unstage_boot_loader;
        if [[ $rc -eq 1 ]];then
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
