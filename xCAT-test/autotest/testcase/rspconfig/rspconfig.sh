#!/bin/bash
function usage()
{
	local script="${0##*/}"
	while read -r ; do echo "${REPLY}" ; done <<-EOF
Usage: ${script} [OPTION]... [ACTION]
	Test rspconfig automatically

Options:
	Mandatory arguments to long options are mandatory for short options too.
	-h, --help                    display this help and exit
	-i|--ip                       To test rspconfig could change bmc's ip
	-lip|--list ip                To test rspconfig could get bmc's ip
	-g|--gateway                  To test rspconfig could change bmc's gateway
	-lg|--list gateway            To test rspconfig could list bmc's gateway
	-n|--netmask                  To test rspconfig could change bmc's netmask
	-ln|--list netmask            To test rspconfig could list bmc's netmask
	-v|--vlan                     To test rspconfig could change bmc's vlan
 	-lv|--list vlan               To test rspconfig could list bmc's vlan
	-a|--all                      To test rspconfig could change bmc's ip,gateway,netmask,vlan
	-la|--list all                To test rspconfig could list bmc's ip,gateway,netmask,vlan
	-c|--clear                    To clear test environment 
Examples:
	${script} -i noderange nodeip=node's ip
	${script} -n noderange netmask
	${script} -g noderange gateway
	${script} -v noderange vlan
	${script} -lip noderange
	${script} -ln noderange
	${script} -lg noderange
	${script} -lv noderange
	${script} -a noderange
	${script} -la noderange

EOF
}
function test_ip()
{
	IP=$1
	VALID_CHECK=$(echo $IP|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')
	if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$">/dev/null; then
       		if [ ${VALID_CHECK:-no} == "yes" ]; then
                       	echo $1 is valid;
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
}
function change_ip()
{
	echo "Prepare to change node's bmc ip."
	echo "Start to check node's bmc original ip valid."
	NODEIP=$4;
	test_ip $1;
	if [[ $? -ne 0 ]];then echo "node's bmc original ip is invalid";return 1;fi
	echo "node's bmc original ip is valid.";
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
	while true;
	do [[ $ip == "$ip5" ]] && echo "exit for using last ip."&&return 1;
		ping $ip1.$ip2.$ip3.$ip -c 2 >/dev/null ;
		if [[ $? != 0 && "$ip" != "$ip4" && "$ip1.$ip2.$ip3.$ip" != "$NODEIP" ]]; then
			coutip="$ip1.$ip2.$ip3.$ip"
			BMCNEWIP=$coutip;
			echo "Start to set node's bmc ip to $BMCNEWIP."
			rspconfig $2 ip=$BMCNEWIP
			if [[ $? -eq 0 ]];then
				echo "Run  rspconfig $2 ip=$BMCNEWIP and return value is 0.";
			else
				echo "Run rspconfig $2 ip=$BMCNEWIP and return value is 1.";
				return 1;
			fi
			chdef $2 bmc=$BMCNEWIP
			echo "Start to check node's bmc's ip really setted using rspconfig."
			check_result $2 ip $BMCNEWIP
			if [[ $? -ne 0 ]] ;then
				echo "Node's bmc ip really setted failed .";
				return 1;
			else
				echo "Node's bmc ip really setted successfully.";
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
		if [[ $(echo $output|tr '.' '+'|bc) -eq $(echo $3|tr '.' '+'|bc)  ]];then 
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
        	rspconfig $2 ip=$originip
        	if [[ $? -eq 0 ]];then
            		echo "Run rspconfig $2 ip=$originip and return value is 0.";
        	else
            		echo "Run rspconfig $2 ip=$originip and return value is 1.";
            		return 1;
        	fi
        	rm -rf /tmp/BMCIP
        	chdef $2 bmc=$originip
        	check_result $2 $3 $originip
       		if [[ $? -ne 0 ]] ;then
            		echo "Node's bmc ip really setted to originip failed.";
      			return 1;
       		else
            		echo "Node's bmc ip really setted to originip successfully.";
                        return 0; 
       		fi
    	fi
        return 1;
}
function change_nonip
{
	echo "Prepare to change node's bmc $4.";
	echo "Start to check node's bmc $4 valid or not.";
	if [[ $4 =~ "gateway" ]]||[[ $4 =~ "netmask" ]];then 
        	test_ip $1;
		if [[ $? -ne 0 ]];then 
			echo "Node's bmc $4 is invalid";
			return 1;
		fi
	fi
	echo "Start to change bmc's $4.";
	rspconfig $2 $4=$1;
	if [[ $? -eq 0 ]];then
		echo "Run rspconfig $2 $4=$1 and return value is 0.";
	else
		echo "Run rspconfig $2 $4=$1 and return value is 1.";
		return 1;
	fi
	echo "Start to check node's bmc $4 really setted using rspconfig.";
	check_result $2 $3 $1
	if [[ $? -ne 0 ]] ;then
		echo "Node's bmc $4 really setted failed.";
		return 1;
	else
		echo "Node's bmc $4 really setted successfully.";
		return 0;
	fi

}
function change_all
{
	echo "Prepare to change ip/netmask/gateway/vlan for node's bmc."
	echo "Start to change ip/netmask/gatway/vlan for node's bmc."
	rspconfig $1 gateway netmask vlan ip
	if [[ $? -eq 0 ]];then
		BMCIP=`rspconfig $1 ip |awk -F":" '{print $3}'|sed s/[[:space:]]//g`;
		BMCNETMASK=`rspconfig  $1 netmask |awk -F":" '{print $3}'|sed s/[[:space:]]//g`;
		BMCGGATEWAY=`rspconfig  $1 gateway |awk -F":" '{print $3}'|sed s/[[:space:]]//g`;
		output=`rspconfig  $1 vlan`
		if [[ $output =~ "BMC VLAN ID enabled" ]];then
			BMCVLAN=`rspconfig  $1 vlan |awk -F":" '{print $3}'|sed s/[[:space:]]//g`
			rspconfig $1 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY vlan=$BMCVLAN
				if [[ $? -eq 0 ]];then
		               		echo "Run rspconfig $1 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY vlan=$BMCVLAN and return value is 0.";
		       		else
	                      		echo "Run rspconfig $1 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY vlan=$BMCVLAN and return value is 1.";
			             	return 1;
		     		 fi
				echo "Start to check node's BMC IP/netmask/gateway/vlan really setted using rspconfig.";
				check_result $1 ip $BMCIP
                		rc1=$?;
                		check_result $1 netmask $BMCNETMASK
                		rc2=$?;
                		check_result $1 gateway $BMCGGATEWAY
                		rc3=$?;
                		check_result $1 vlan $BMCVLAN
                		rc4=$?;
				if [[ $rc1 -eq 0 ]] && [[ $rc2 -eq 0 ]] && [[ $rc3 -eq 0 ]] && [[ $rc4 -eq 0 ]];then
					echo "Node's bmc IP/netmask/gateway/vlan really setted successfully."
					return 0;
				else
					echo "Node's bmc IP/netmask/gateway really setted failed."
					return 1;
				fi


		else
			echo "------------------Bmc vlan disabled so could not change vlan id using rspconfig.--------------------"
			rspconfig $1 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY 
				if [[ $? -eq 0 ]];then
		               		echo "Run rspconfig $1 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY and return value is 0.";
		       		else
	                      		echo "Run rspconfig $1 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY and return value is 1.";
			             	return 1;
          			 fi
				echo "Start to check node's BMC IP/netmask/gateway really setted using rspconfig.";
				check_result $1 ip $BMCIP
                		rc1=$?;
                		check_result $1 netmask $BMCNETMASK
                		rc2=$?;
                		check_result $1 gateway $BMCGGATEWAY
                		rc3=$?;
				if [[ $rc1 -eq 0 ]] && [[ $rc2 -eq 0 ]] && [[ $rc3 -eq 0 ]];then 
					echo "Node's bmc IP/netmask/gateway really setted successfully."
					return 0;
				else
					echo "Node's bmc  IP/netmask/gateway really setted failed."
					return 1;
				fi

		fi
	fi

}
BMCIP=""
BMCIP_LSDEF=""
BMCGTEWAT=""
BMCNETMASK=""
BMCVLAN=""
FIRSTIP=""
LASTIP=""
NODEIP=""
while [ "$#" -gt "0" ]
do
	case $1 in
		"-i"|"--ip" )
		echo "--------------------Start to test rspconfig change node's bmc ip .--------------------"
		rspconfig $2 ip
		if [[ $? -eq 0 ]];then
			BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
			BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
		else
			echo "Run rspconfig $2 ip and return value is 1. "
			exit 1; 
		fi
		change_ip $BMCIP $2 $BMCNETMASK $3
		if [[ $? -eq 1 ]];then
			echo "--------------------Result for test rspconfig change node's bmc ip failed.--------------------"
			exit 1
		else
			echo "--------------------Restult for test rspconfig change node's bmc ip successfully.-------------------" 
			exit 0
		fi
		;;
		"-lip"|"--list ip" )
		echo "--------------------Start to test rspconfig list node's bmc ip .--------------------"
		BMCIP_LSDEF=`lsdef $2 |grep "bmc=" |awk -F "=" '{print $2}'`
		rspconfig $2 ip
		if [[ $? -eq 0 ]];then
			BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
				if [[ $BMCIP =~ "$BMCIP_LSDEF" ]];then 
					echo "-----------------Result for test rspconfig list node's bmc ip successfully.-----------------"
					exit 0;
				else
					echo "-------------------Result for test rspconfig list node's bmc ip failed.----------------"
					exit 1;
				fi
		else
			echo "------------------Result for test rspconfig list node's bmc ip failed.-------------------"
			exit 1;
		fi
		;;

		"-g"|"--gateway" )
		echo "--------------------Start to test rspconfig change node's bmc gateway .---------------------"
		rspconfig  $2 gateway
		if [[ $? -eq 0 ]];then
			BMCGATEWAYE=`rspconfig  $2 gateway |awk -F":" '{print $3}'`
		else
			echo "Run rspconfig  $2 gateway and return value is 1."
			exit 1;
		fi
		change_nonip $BMCGATEWAYE $2 $3 gateway
		if [[ $? -eq 1 ]];then
			echo "--------------------Result for test rspconfig change node's bmc gateway failed.--------------------"
			exit 1
		else
			echo "--------------------Result for test rspconfig change node's bmc gateway successfully.--------------------"
			exit 0
		fi
		;;
		"-lg"|"--list gateway" )
		output=`rspconfig $2 gateway`
		if [[ $? -eq 0 ]];then
			if [[ $output =~ "$2: BMC Gateway:" ]];then 
				echo "--------------------Result for test rspconfig list node's bmc gateway  successfully.-----------------"
				exit 0;
			else
				echo "------------------Result for test rspconfig list node's bmc  gateway failed.-------------------"
				exit 1;
			fi
		else
			echo "-------------------Result for test rspconfig list node's bmc gateway failed.---------------"
			exit 1;	
		fi
		;;
		"-n"|"--netmask" )
		rspconfig  $2 netmask
		echo "---------------------Start to test rspconfig change node's bmc netmask .--------------------"
		if [[ $? -eq 0 ]];then
			BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
		else
			echo "Run rspconfig  $2 netmask and return value is 1."
			exit 1;
		fi
		change_nonip $BMCNETMASK $2 $3 netmask
		if [[ $? -eq 1 ]];then
			echo "--------------------Result for rspconfig change node's  bmc netmask failed.------------------"
			exit 1
		else
			echo "--------------------Result for rspconfig change node's bmc netmask successfully.-------------------"
			exit 0
		fi
		;;
		"-ln"|"--list netmask" )
		output=`rspconfig $2 netmask` 
		if [[ $? -eq 0 ]];then
			if [[ $output =~ "$2: BMC Netmask:" ]];then
				echo "-------------------Result for test rspconfig list node's bmc Netmask successfully.-----------------"
				exit 0;
			else
				echo "-----------------Result for test rspconfig list node's bmc Netmask  failed.-------------------"
				exit 1;
			fi
 		else
			echo "-------------------Result for test rspconfig list node's bmc Netmask failed.---------------"
			exit 1;
		fi
		;;
		"-v"|"--vlan" )
		output=`rspconfig  $2 vlan`
		echo "---------------------Start to test rspconfig change node's bmc vlan .--------------------"
		if [[ $? -eq 0 ]]&&[[ $output =~ "BMC VLAN ID enabled" ]];then
			BMCVLAN=`rspconfig  $2 vlan |awk -F":" '{print $3}'`
		else
			echo "------------------Bmc vlan disabled so could not change vlan id using rspconfig.--------------------"
			exit 1;
		fi
		change_nonip $BMCVLAN $2 $3 vlan
		if [[ $? -eq 1 ]];then
			echo "--------------------Result for rpsconfig change node's bmc vlan  failed.------------------"
			exit 1
		else
			echo "--------------------Result for rspconfig change node's bmc vlan successfully.-------------------"
			exit 0
		fi
		;;
		"-lv"|"--list vlan" )
		output=`rspconfig $2 vlan`
		if [[ $? -eq 0 ]];then
			if [[ $output =~ "$2: BMC VLAN ID" ]];then
				echo "-------------------Result for rspconfig list node's bmc Vlan successfully.-----------------"
				exit 0;
			else
				echo "-----------------Result for rspconfig list node's bmc Vlan failed.-------------------"
				exit 1;
			fi
		else
			echo "-------------------Result for rspconfig list node's bmc Vlan  failed.---------------"
			exit 1;
		fi
		;;
		"-a"|"--all" )
		change_all $2
		if [[ $? -eq 1 ]];then
			echo "--------------------Result for rspconfig change node's BMC IP/netmask/gateway/vlan failed.------------------"
			exit 1
                else
			echo "--------------------Result for rspconfig change node's BMC IP/netmask/gateway/vlan successfully.-------------------"
			exit 0
		fi
		;;
		"-la"|"--list all" )
		BMCIP_LSDEF=`lsdef $2 |grep "bmc=" |awk -F "=" '{print $2}'`
		BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
		output=`rspconfig $2 ip gateway netmask vlan`
		if [[ $? -eq 0 ]];then
			if [[ $output =~ "$2: BMC VLAN ID" ]]&&[[ $output =~ "BMC Netmask:" ]]&&[[ $output =~ "BMC Gateway:" ]]&&[[ $BMCIP =~ "$BMCIP_LSDEF" ]];then 
				echo "------------------Result for rspconfig list node's  BMC IP/netmask/gateway/vlan succssfully.-----------------"
				exit 0
			else
				echo "--------------------Result for rspconfig list node's  BMC IP/netmask/gateway/vlan failed.--------------------"
				exit 1
			fi
		fi
		;;
		"-c"|"--clear" )
		echo "--------------------To clear the test envionment.--------------------"
		clear_env $1 $2 $3
		if [[ $? -eq 1 ]];then
			echo "--------------------To clear the test environment failed.-----------------"	
			exit 1
		else
			echo "--------------------To clear the test environment sucessfully.-----------------"
			exit 0
		fi
		;;
		"-h"|"--help" )
                usage
                exit 0
                ;;
		*)
		echo
		echo "Please Insert $0: -i|-lip|-g|-lg|-n|-ln|-v|-lv|-c|-a|-la"
		echo
		exit 1;
		;;
		esac
		shift
done
