#!/bin/bash
function test_ip()
{
    IP=$1
    VALID_CHECK=$(echo $IP|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
    if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$">/dev/null; then
        if [ ${VALID_CHECK:-no} == "yes" ]; then
            echo $1;
        else
            return 1;
        fi
    else
         return 1;
    fi

}
function change_ip()
{
    test_ip $1;
    if [[ $? -eq 1 ]]; then 
        echo ipvalue is invalid
        exit 1;
    fi
    echo $1 > /tmp/BMCIP
    ip1=`echo $1|awk -F. '{print $1}'`
    ip2=`echo $1|awk -F. '{print $2}'`
    ip3=`echo $1|awk -F. '{print $3}'`
    ip4=`echo $1|awk -F. '{print $4}'`
    echo ip is $ip1.$ip2.$ip3.$ip4 
    ip=$ip4;
    while [[ $ip != "10" ]]; do 
    ping $ip1.$ip2.$ip3.$ip -c 2 > /dev/null; 
    if [[ $? != 0 ]]; then 
        coutip="$ip1.$ip2.$ip3.$ip"
        BMCNEWIP=$coutip;
        echo $1,$2,$3
        rspconfig $2 ip=$BMCNEWIP
        if [[ $? -eq 0 ]];then 
            echo right command;
        else 
            exit 1;
        fi
    chdef $2 bmc=$BMCNEWIP
    check_result $2 ip
    fi
    ip=`expr "$ip" "+" "1"`
    done
}
function check_result {

    a=0; while true;
    do [ $a -eq 3 ] && exit 1;
    echo $a
    sleep 20
    output=$(rspconfig $1 $2 );
        if [[ $? -eq 0 ]] ;then
            echo $output;exit 0;
        else
            a=$[$a+1];
            sleep 1;
        fi
    done
}
function clear_env {
    if [[ -f /tmp/BMCIP ]];then 
        echo need to clear env;
        originip=$(cat /tmp/BMCIP);
        echo originip is $originip;
        rspconfig $2 ip=$originip
        echo $2,$3
        rm -rf /tmp/BMCIP
        chdef $2 bmc=$originip
        check_result $2 $3
    fi
}
function change_gateway {
    test_ip $1;
    rspconfig $2 gateway=$1;
    check_result $2 $3
}
function change_netmask {
    test_ip $1;
    rspconfig $2 netmask=$1;
    echo $2 ,$3
    check_result $2 $3

}
BMCIP=""
BMCNETWORK=""
BMCGATEWAY=""
BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
BMCGATEWAYE=`rspconfig  $2 gateway |awk -F":" '{print $3}'`
BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
while [ "$#" -gt "0" ]
do
case $1 in
  "-i"|"--ip" )
  change_ip $BMCIP $2 
;;
  "-g"|"--gateway" )
  change_gateway $BMCGATEWAYE $2 $3 
;;
   "-n"|"--netmask" )
  change_netmask $BMCNETMASK $2 $3
;;
   "-c"|"--clear" )
  clear_env $1 $2 
;;
  *)
  echo
  echo "Please Insert $0: -i|-g|-n|-c"
  echo
  exit 1;
;;
esac
done

