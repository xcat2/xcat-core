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
        echo "Start to check ip valid."
        NODEIP=$4;
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
				echo "Could set bmc's ip for node using rspconfig.";
			else
                                echo "Could not set bmc's ip for node using rspconfig.";
				return 1;
			fi
			chdef $2 bmc=$BMCNEWIP
                        echo "Start to check bmc's ip setted successfully or not."
			check_result $2 ip $BMCNEWIP
			if [[ $? -ne 0 ]] ;then
                                echo "Set bmc's ip failed.";
				return 1;
			else
				echo "Set bmc's ip successfully.";
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
            		echo "Could set bmc's ip to originip using rspconfig.";
        	else
            		echo "Could not set bmc's ip to originip using rspconfig.";
            		return 1;
        	fi
        	rm -rf /tmp/BMCIP
        	chdef $2 bmc=$originip
        	check_result $2 $3 $originip
       		if [[ $? -ne 0 ]] ;then
            		echo "Set bmc's ip to originip failed.";
      			return 1;
       		else
            		echo "Set bmc's ip to originip successfully.";
                        return 0; 
       		fi
    	fi
        return 1;
}
function change_nonip
{
echo "Prepare to change $4.";
echo "Start to check $4 valid or not.";
	if [[ $4 =~ "gateway" ]]||[[ $4 =~ "netmask" ]];then 
        	test_ip $1;
		if [[ $? -ne 0 ]];then 
			echo "$4 is invalid";
			return 1;
		fi
	fi
	echo "Start to change bmc's $4.";
	rspconfig $2 $4=$1;
	if [[ $? -eq 0 ]];then
                echo "Could set bmc's $4.";
        else
                echo "Could not set bmc's $4.";
                return 1;
        fi
        echo "Start to check $4 setting successfully or not.";
        check_result $2 $3 $1
        if [[ $? -ne 0 ]] ;then
                echo "Set bmc's $4 failed.";
                return 1;
        else
                echo "Set bmc's $4 successfully.";
                return 0;
        fi

}
function change_all
{
echo "Prepare to change all for bmc."
echo "Start to change all for bmc."
	rspconfig $2 gateway netmask vlan ip
	if [[ $? -eq 0 ]];then
		BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`;
		BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`;
		BMCGGATEWAY=`rspconfig  $2 gateway |awk -F":" '{print $3}'`;
                output=`rspconfig  $2 vlan`
                if [[ $output =~ "BMC VLAN ID enabled" ]];then
                        BMCVLAN=`rspconfig  $2 vlan |awk -F":" '{print $3}'`
                else
                        echo "------------------Bmc vlan disabled so could not change vlan id using rspconfig.--------------------"
                        return 1;
                fi
	rspconfig $2 ip=$BMCIP netmask=$BMCNETMASK gateway=$BMCGGATEWAY vlan=$BMCVLAN
		if [[ $? -eq 0 ]];then
                	echo "Could set bmc's all options.";
        	else
                	echo "Could not set bmc's all options.";
                	return 1;
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
		echo "--------------------To test bmc ip could be changed using rspconfig.--------------------"
		rspconfig $2 ip
		if [[ $? -eq 0 ]];then
			BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
			BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
		else
			exit 1; 
		fi
		change_ip $BMCIP $2 $BMCNETMASK $3
		if [[ $? -eq 1 ]];then
			echo "--------------------To test bmc ip could be changed using rspconfig failed.--------------------"
			exit 1
		else
			echo "--------------------To test bmc ip could be change using rspconfig successfully.-------------------" 
			exit 0
		fi
		;;
		"-lip"|"--list ip" )
                echo "--------------------To test bmc ip could be listed using rspconfig.--------------------"
                BMCIP_LSDEF=`lsdef $2 |grep "bmc=" |awk -F "=" '{print $2}'`
                rspconfig $2 ip
                if [[ $? -eq 0 ]];then
                        BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
				if [[ $BMCIP =~ "$BMCIP_LSDEF" ]];then 
					echo "-----------------To test bmc ip could be listed using rspconfig successfully.-----------------"
					exit 0;
				else
					echo "-------------------To test bmc ip could be listed using rspconfig failed.----------------"
					exit 1;
				fi
                else
			echo "------------------To test bmc ip could be listed using rspconfig failed.-------------------"
                        exit 1;
                fi
                ;;

		"-g"|"--gateway" )
		echo "--------------------To test bmc gateway could be changed using rspconfig.---------------------"
		rspconfig  $2 gateway
		if [[ $? -eq 0 ]];then
			BMCGATEWAYE=`rspconfig  $2 gateway |awk -F":" '{print $3}'`
		else
      			exit 1;
		fi
		change_nonip $BMCGATEWAYE $2 $3 gateway
		if [[ $? -eq 1 ]];then
                        echo "--------------------To test bmc gateway could be changed using rspconfig failed.--------------------"
			exit 1
		else
			echo "--------------------To test bmc gateway could be changed using rspconfig successfully.--------------------"
			exit 0
		fi
		;;
		"-lg"|"--list gateway" )
		output=`rspconfig $2 gateway`
echo "output is $output"
		if [[ $? -eq 0 ]];then
			if [[ $output =~ "$2: BMC Gateway:" ]];then 
				echo "--1-----------------To test bmc gateway could be listed using rspconfig successfully.-----------------"
				exit 0;
			else
				echo "---2--------------To test bmc gateway could be listed using rsconfig failed.-------------------"
				exit 1;
			fi
		else
			echo "------------3-------To test bmc gateway could be listed using rspconfig failed.---------------"
			exit 1;	
		fi
		;;
		"-n"|"--netmask" )
		rspconfig  $2 netmask
		echo "---------------------To test bmc netmask could be changed using rspconfig.--------------------"
		if [[ $? -eq 0 ]];then
			BMCNETMASK=`rspconfig  $2 netmask |awk -F":" '{print $3}'`
		else
			exit 1;
		fi
		change_nonip $BMCNETMASK $2 $3 netmask
		if [[ $? -eq 1 ]];then
			echo "--------------------To test bmc netmask could be changed using rspconfig failed.------------------"
			exit 1
		else
			echo "--------------------To test bmc netmask could be changed using rspconfig successfully.-------------------"
			exit 0
		fi
		;;
                "-ln"|"--list netmask" )
                output=`rspconfig $2 netmask` 
                if [[ $? -eq 0 ]];then
                        if [[ $output =~ "$2: BMC Netmask:" ]];then
                                echo "-------------------To test bmc Netmask could be listed using rspconfig successfully.-----------------"
                                exit 0;
                        else
                                echo "-----------------To test bmc Netmask could be listed using rsconfig failed.-------------------"
                                exit 1;
                        fi
                else
                        echo "-------------------To test bmc Netmask could be listed using rspconfig failed.---------------"
                        exit 1;
                fi
                ;;
                "-v"|"--vlan" )
                output=`rspconfig  $2 vlan`
                echo "---------------------To test bmc vlan could be changed using rspconfig.--------------------"
                if [[ $? -eq 0 ]]&&[[ $output =~ "BMC VLAN ID enabled" ]];then
                        BMCVLAN=`rspconfig  $2 vlan |awk -F":" '{print $3}'`
                else
                        echo "------------------Bmc vlan disabled so could not change vlan id using rspconfig.--------------------"
			exit 1;
                fi
                change_nonip $BMCVLAN $2 $3 vlan
                if [[ $? -eq 1 ]];then
                        echo "--------------------To test bmc vlan could be changed using rspconfig failed.------------------"
                        exit 1
                else
                        echo "--------------------To test bmc vlan could be changed using rspconfig successfully.-------------------"
                        exit 0
                fi
                ;;
                "-lv"|"--list vlan" )
                output=`rspconfig $2 vlan`
                if [[ $? -eq 0 ]];then
                        if [[ $output =~ "$2: BMC VLAN ID" ]];then
                                echo "-------------------To test bmc Vlan could be listed using rspconfig successfully.-----------------"
                                exit 0;
                        else
                                echo "-----------------To test bmc Vlan could be listed using rsconfig failed.-------------------"
                                exit 1;
                        fi
                else
                        echo "-------------------To test bmc Vlan could be listed using rspconfig failed.---------------"
                        exit 1;
                fi
                ;;
		"-a"|"--all" )
                change_all $2
		if [[ $? -eq 1 ]];then
                        echo "--------------------To test bmc's all options could be changed using rspconfig failed.------------------"
                        exit 1
                else
                        echo "--------------------To test bmc's all options could be changed using rspconfig successfully.-------------------"
                        exit 0
                fi
		;;
		"-la"|"--list all" )
		BMCIP_LSDEF=`lsdef $2 |grep "bmc=" |awk -F "=" '{print $2}'`
		BMCIP=`rspconfig $2 ip |awk -F":" '{print $3}'`
		output=`rspconfig $2 ip gateway netmask vlan`
		if [[ $? -eq 0 ]];then
			#if [[ $output =~ "BMC VLAN ID:" ]]&&[[ $output =~ "BMC Netmask:" ]]&&[[ $output =~ "BMC Gateway:" ]]&&[[ $BMCIP =~ "$BMCIP_LSDEF" ]];then 
			if [[ $output =~ "$2: BMC VLAN ID" ]]&&[[ $output =~ "BMC Netmask:" ]]&&[[ $output =~ "BMC Gateway:" ]]&&[[ $BMCIP =~ "$BMCIP_LSDEF" ]];then 
				echo "------------------To test bmc's all option could be listed using rspconfig succssfully.-----------------"
				exit 0
			else
				echo "--------------------To test bmc's all options could be listed using rspconfig failed.--------------------"
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
		*)
		echo
		echo "Please Insert $0: -i|-g|-n|-c"
		echo
		exit 1;
		;;
		esac
done
