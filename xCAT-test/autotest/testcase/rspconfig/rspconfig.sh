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
	return 0;
}
function net()
{
	LASTIP=`echo "$1 $2"|awk -F '[ .]+' 'BEGIN{OFS="."} END{print or($1,xor($5,255)),or($2,xor($6,255)),or($3,xor($7,255)),or($4,xor($8,255))}'`
	FIRSTIP=`echo "$1 $2"|awk -F '[ .]+' 'BEGIN{OFS="."} END{print and($1,$5),and($2,$6),and($3,$7),and($4,$8)}'`
	echo lastip is $LASTIP
	echo first ip is $FIRSTIP

}
function change_ip()
{
        echo "Prepare to change ip."
        echo "Start to check ip valid ."
        $NODEIP=$4;
	test_ip $1;
	if [[ $? -ne 0 ]];then echo "ip is invalid";return 1;fi
        echo "ip is valid.";
	echo $1 > /tmp/BMCIP
        net $1 $3
	ip1=`echo $1|awk -F. '{print $1}'`
	ip2=`echo $1|awk -F. '{print $2}'`
	ip3=`echo $1|awk -F. '{print $3}'`
        ip4=`echo $1|awk -F. '{print $4}'`
	ipfirst=`echo $FIRSTIP|awk -F. '{print $4}'`
        ip=`expr "$ipfirst" "+" "1"`
	iplast=`echo $LASTIP|awk -F. '{print $4}'`
        ip5=`expr "$iplast" "-" "1"`
        echo ip is $ip ,ip5 is $ip5
	while true;
	do [[ $ip == "$ip5" ]] && echo "exit for using last ip."&&return 1;
		ping $ip1.$ip2.$ip3.$ip -c 2 >/dev/null ;
		if [[ $? != 0 && "$ip" != "$ip4" && "$ip1.$ip2.$ip3.$ip" != "$NODEIP" ]]; then
			coutip="$ip1.$ip2.$ip3.$ip"
			BMCNEWIP=$coutip;
			echo $1,$2,$3
                        echo "Start to set ip for node."
			rspconfig $2 ip=$BMCNEWIP
			if [[ $? -eq 0 ]];then
				echo "Could set ip for node.";
			else
                                echo "Could not set ip for node";
				return 1;
			fi
			chdef $2 bmc=$BMCNEWIP
                        echo "Start to check ip setted successfully or not."
			check_result $2 ip $BMCNEWIP
			if [[ $? -ne 0 ]] ;then
                                echo "Ip could  not be setted.";
				return 1;
			else
				echo "Ip could be setted.";
                                return 0;
			fi
		fi
		ip=`expr "$ip" "+" "1"`
	done
}
function check_result()
{	
	a=0; while true;
	do [ $a -eq 20 ] && return 1;
		output=`rspconfig $1 $2 |awk -F: '{print $3}'`;
		echo output is $output;
		if [[ $(echo $output|tr '.' '+'|bc) -eq $(echo $3|tr '.' '+'|bc)  ]];then 
        		echo checkresult is  $output;
        		return 0 ;
     		else
        		a=$[$a+1];
        		sleep 1;
     		fi
	done
    	return 1;
}
function clear_env()
{
echo "Start to clear test environment.";
	if [[ -f /tmp/BMCIP ]];then 
        	originip=$(cat /tmp/BMCIP);
        	echo originip is $originip;
        	rspconfig $2 ip=$originip
        	if [[ $? -eq 0 ]];then
            		echo "Could set the node's bmc ip to originip";
        	else
            		echo "Could not set the node's bmc ip to originip";
            		return 1;
        	fi
        	rm -rf /tmp/BMCIP
        	chdef $2 bmc=$originip
        	check_result $2 $3 $originip
       		if [[ $? -ne 0 ]] ;then
            		echo "Could set the node's bmc ip to originip sucessfully.";
      			return 1;
       		else
            		echo "Could set the node's bmc ip to originip successfully.";
                        return 0; 
       		fi
    	fi
        return 1;
}
function change_gateway 
{
 	echo "Prepare to change gateway.";
        echo "Start to check gateway valid or not.";
        test_ip $1;
	if [[ $? -ne 0 ]];then echo "Gateway is invalid";return 1;fi
                echo "Start to change gateway.";
		rspconfig $2 gateway=$1;
	if [[ $? -eq 0 ]];then
		echo "Could set gateway.";
	else
		echo "Could not set gateway.";
                return 1;
	fi
        echo "Start to check gateway setted successfully or not.";
	check_result $2 $3 $1
	if [[ $? -ne 0 ]] ;then
                echo "Could not set gateway successfully.";
		return 1;
	else
		echo "Could set gateway successfully.";
                return 0;
	fi
}
function change_netmask 
{
	echo "Prepare to change netmask";
        echo "Start to check netmask valid or not.";
        test_ip $1;
	if [[ $? -ne 0 ]];then echo "Net mask is invalid.";return 1;fi
	rspconfig $2 netmask=$1;
	if [[ $? -eq 0 ]];then
		echo "Could set netmask.";
	else
                echo "Could not set netmask.";
		return 1;
	fi
	check_result $2 $3 $1
	if [[ $? -ne 0 ]] ;then
                echo "Could not set netmask successfully.";
		return 1;
	else
		echo "Could set netmask successfully.";
                return 0;
	fi
}
BMCIP=""
BMCGTEWAT=""
BMCNETMASK=""
FIRSTIP=""
LASTIP=""
NODEIP=""
while [ "$#" -gt "0" ]
do
	case $1 in
		"-i"|"--ip" )
		rspconfig $2 ip
		if [[ $? -eq 0 ]];then
			BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
			BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
		else
			exit 1; 
		fi
		change_ip $BMCIP $2 $BMCNETMASK $3
		if [[ $? -eq 1 ]];then
			exit 1
		else 
			exit 0
		fi
		;;
		"-g"|"--gateway" )
		rspconfig  $2 gateway
		if [[ $? -eq 0 ]];then
			BMCGATEWAYE=`rspconfig  $2 gateway |awk -F":" '{print $3}'`
		else
      			exit 1;
		fi
		change_gateway $BMCGATEWAYE $2 $3 
		if [[ $? -eq 1 ]];then
			exit 1
		else
			exit 0
		fi
		;;
		"-n"|"--netmask" )
		rspconfig  $2 netmask
		if [[ $? -eq 0 ]];then
			BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
		else
			exit 1;
		fi
		change_netmask $BMCNETMASK $2 $3
		if [[ $? -eq 1 ]];then
			exit 1
		else
			exit 0
		fi
		;;
		"-c"|"--clear" )
		clear_env $1 $2 $3
		if [[ $? -eq 1 ]];then
			exit 1
		else
			exit 0
		fi
		;;
		*)
		echo
		echo "Please Insert $0: -i|-g|-n|-c"
		echo
		exit 1;
		;;
		esac
done
