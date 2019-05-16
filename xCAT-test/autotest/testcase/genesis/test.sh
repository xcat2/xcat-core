#!/bin/bash
function check_destiny(){
chdef testnode arch=ppc64le cons=ipmi groups=all ip=60.1.1.1 mac=4e:ee:ee:ee:ee:0e netboot=$NETBOOT;
masterip=`lsdef -t site -i master -c 2>&1 | awk -F'=' '{print $2}'`;
masternet=`ifconfig  | awk "BEGIN{RS=\"\"}/\<$masterip\>/{print \$1}"|head -n 1 | awk -F ' ' '{print $1}'|awk -F ":"  '{print \$1}' 2>&1`;
net2=`netstat -i -a|grep -v Kernel|grep -v Iface |grep -v lo|grep -v $masternet|head -n 1|awk '{print $1}'`;echo net2 is  $net2;
net2ip="";
    if [[ -z $net2 ]];then
        echo "There is no second network,could not verify the test"
        return 1;
    else
        net2ipstring=`ifconfig $net2 |grep inet|grep -v inet6`;
            if [[ $? -eq 0 ]];then
                net2ip=`ifconfig $net2 |grep inet|grep -v inet6|awk -F ' ' '{print $2}'|awk -F ":" '{print $2}'`;
                    if [[ -z $net2ip ]];then
                        net2ip=`ifconfig $net2 |grep inet|grep -v inet6|awk -F ' ' '{print $2}'`;
                    fi
            else
                net2ip=0.0.0.0;
            fi
        ifconfig $net2 60.3.3.3 ;
        makenetworks;        
        makehosts testnode;
        nodeset testnode  shell;
        ifconfig $net2 "$net2ip";
        cat "$SHELLFOLDER"testnode |grep "xcatd=60.3.3.3:3001 destiny=shell";
            if [[ $? -eq 0 ]] ;then
                return 0;
            else
                echo wrong;
                return 1;
            fi
    fi
}
function clear_env(){
rmdef -t network -o 60_0_0_0-255_0_0_0
makehosts -d testnode
rmdef testnode
    if [[ $? -eq 0 ]];then
       return 0;
    else
       return 1;
    fi
}
NETBOOT=""
SHELLFOLDER=""
while [ "$#" -gt "0" ]
do
        case $1 in
                "--check" )
                NETBOOT=$2;
                    if [[ $NETBOOT =~ petitboot ]];then
                        SHELLFOLDER="/tftpboot/petitboot/";
                    elif [[ $NETBOOT =~  xnba ]];then
                        SHELLFOLDER="/tftpboot/xcat/xnba/nodes/"
                    else
                        SHELLFOLDER="/tftpboot/boot/grub2/";
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
                echo "Please Insert $0: -cd|-c"
                echo
                exit 1;
                ;;
                esac
done
