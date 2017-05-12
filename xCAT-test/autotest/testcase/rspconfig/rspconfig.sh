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
	a=$(echo "$1" | awk -F "." '{print $1" "$2" "$3" "$4}')
        for num in $a;
	do
		while (($num!=0));do
 			echo -n $(($num%2)) >> /tmp/$$.num;
			num=$(($num/2));
		done
	done
	rc=$(grep -o "1" /tmp/$$.num | wc -l)
	rm /tmp/$$.num
        ip="$2/$rc"
	A=($(echo "$ip"|sed 's/[./;]/ /g'))
	B=$(echo $((2**(32-${A[4]})-1)))
	C=($(echo "obase=256;ibase=10; $B"|bc|awk '{if(NF==4)a=$0;if(NF==3)a="0"$0;if(NF==2)a="0 0"$0;if(NF==1)a="0 0 0"$0;print a}'))
	D=$(echo ${A[*]} ${C[*]})
	rc2=echo echo $D|awk 'BEGIN{OFS="."}{print $1,$2,$3,$4"-"$1+$6,$2+$7,$3+$8,$4+$9}' |awk -F '-' '{print $2}'
}
function change_ip()
{
	test_ip $1;
	if [[ $? -ne 0 ]];then return 1;fi
	echo $1 > /tmp/BMCIP
	ip1=`echo $1|awk -F. '{print $1}'`
	ip2=`echo $1|awk -F. '{print $2}'`
	ip3=`echo $1|awk -F. '{print $3}'`
	ip4=`echo $1|awk -F. '{print $4}'`
	echo ip is $ip1.$ip2.$ip3.$ip4 
	rc=$(net $3 $1)
	rc4=`echo $rc |awk -F. '{print $4}'`
	rc4=`expr "$rc4"`
	if [[ $rc4 > 255 ]];then rc4=255;fi
	ip=$ip4
	while true;
	do [[ $ip == "$rc4" ]] && return 1;
		ping $ip1.$ip2.$ip3.$ip -c 2 >/dev/null ;
		if [[ $? != 0 ]]; then
			coutip="$ip1.$ip2.$ip3.$ip"
			BMCNEWIP=$coutip;
			echo $1,$2,$3
			rspconfig $2 ip=$BMCNEWIP
			if [[ $? -eq 0 ]];then
				echo right command;
			else
				return 1;
			fi
			chdef $2 bmc=$BMCNEWIP
			check_result $2 ip $BMCNEWIP
			if [[ $? -ne 0 ]] ;then
				return 1;
			else
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
	if [[ -f /tmp/BMCIP ]];then 
        	originip=$(cat /tmp/BMCIP);
        	echo originip is $originip;
        	rspconfig $2 ip=$originip
        	if [[ $? -eq 0 ]];then
            		echo right command;
        	else
            		return 1;
        	fi
        	rm -rf /tmp/BMCIP
        	chdef $2 bmc=$originip
        	check_result $2 $3 $originip
       		if [[ $? -ne 0 ]] ;then
      			return 1;
       		else
                        return 0; 
       		fi
    	fi
        return 1;
}
function change_gateway 
{
 	test_ip $1;
	if [[ $? -ne 0 ]];then return 1;fi
		rspconfig $2 gateway=$1;
	if [[ $? -eq 0 ]];then
		echo set gateway ok;
	else
		return 1;
	fi
	check_result $2 $3 $1
	if [[ $? -ne 0 ]] ;then
		return 1;
	else
		return 0;
	fi
}
function change_netmask 
{
	test_ip $1;
	if [[ $? -ne 0 ]];then return 1;fi
	rspconfig $2 netmask=$1;
	if [[ $? -eq 0 ]];then
		echo set netmask ok;
	else
		return 1;
	fi
	check_result $2 $3 $1
	if [[ $? -ne 0 ]] ;then
		return 1;
	else
		return 0;
	fi
}
BMCIP=""
BMCGTEWAT=""
BMCNETMASK=""
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
		change_ip $BMCIP $2 $BMCNETMASK  
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
