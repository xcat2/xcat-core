function hashencode(){
        local str_map="$1"
         echo `echo $str_map | sed 's/\./xDOTx/g' | sed 's/:/xCOLONx/g' | sed 's/,/:xCOMMAx/g'`
}

function hashset(){
    local str_hashname="hash${1}${2}"
    local str_value=$3
    str_hashname=$(hashencode $str_hashname)
    eval "${str_hashname}='${str_value}'"
}

function hashget(){
    local str_hashname="hash${1}${2}"
    str_hashname=$(hashencode $str_hashname)
    eval echo "\$${str_hashname}"
}

function debianpreconf(){
    #create the config sub dir
    if [ ! -d "/etc/network/interfaces.d" ];then
        mkdir -p "/etc/network/interfaces.d"
    fi
    #search xcat flag
    grep '#XCAT_CONFIG' /etc/network/interfaces
    if [ $? -eq 0 ];then
        return
    fi

    #back up the old interface configure
    if [ ! -e "/etc/network/interfaces.bak" ];then
        mv /etc/network/interfaces /etc/network/interfaces.bak
    fi

    #create the new config file
    echo "#XCAT_CONFIG" > /etc/network/interfaces
    echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces

    local str_conf_file=''

    #read the backfile
    cat /etc/network/interfaces.bak | while read str_line
    do
        if [ ! "$str_line" ];then
            continue
        fi
        local str_first_char=${str_line:0:1}
        if [ $str_first_char = '#' ];then
            continue
        fi

        local str_conf_type=`echo $str_line | cut -d" " -f1`
        if [ $str_conf_type = 'auto' -o $str_conf_type = 'allow-hotplug' ];then
            str_line=${str_line#$str_conf_type}
            for str_nic_name in $str_line; do
                echo "$str_conf_type $str_nic_name" > "/etc/network/interfaces.d/$str_nic_name"
            done
        elif [ $str_conf_type = 'iface' -o $str_conf_type = 'mapping' ];then
            #find out the nic name, should think about the eth0:1
            str_nic_name=`echo $str_line | cut -d" " -f 2 | cut -d":" -f 1`
            str_conf_file="/etc/network/interfaces.d/$str_nic_name"
            if [ ! -e $str_conf_file ];then
                echo "auto $str_nic_name" > $str_conf_file
            fi

            #write lines into the conffile
            echo $str_line >> $str_conf_file
        else
            # Write the remaining lines of the nic conf info to conffile
            # It is possible that there are some lines at the beginning of /etc/network/interfaces,
            # that we could not recognize, ignore these lines. The indication is that the str_conf_file is empty
            if [ ! -z "$str_conf_file" ]; then
                echo $str_line >> $str_conf_file
            fi
        fi
    done
}

#tranfer the netmask to prefix for ipv4
function v4mask2prefix(){
    local num_bits=0
    local old_ifs=$IFS
    IFS=$'.'
    local array_num_temp=($1)
    IFS=$old_ifs
    for num_dec in ${array_num_temp[@]}
    do
        case $num_dec in
            255) let num_bits+=8;;
            254) let num_bits+=7;;
            252) let num_bits+=6;;
            248) let num_bits+=5;;
            240) let num_bits+=4;;
            224) let num_bits+=3;;
            192) let num_bits+=2;;
            128) let num_bits+=1;;
            0) ;;
            *) echo "Error: $dec is not recognised"; exit 1
        esac
    done
    echo "$num_bits"
}

function v4prefix2mask(){
    local a=$1
    local b=0
    local num_index=1
    local str_temp=''
    local str_mask=''

    while [[ $num_index -le 4 ]]
    do
        if [ $a -ge 8 ];then
            b=8
            a=$((a-8))
        else
            b=$a
            a=0
        fi
        case $b in
            0) str_temp="0";;
            1) str_temp="128";;
            2) str_temp="192";;
            3) str_temp="224";;
            4) str_temp="240";;
            5) str_temp="248";;
            6) str_temp="252";;
            7) str_temp="254";;
            8) str_temp="255";;
        esac

        str_mask=$str_mask$str_temp"."

        num_index=$((num_index+1))
    done

    str_mask=`echo $str_mask | sed 's/\.$//'`
    echo "$str_mask"
}

function v4calcbcase(){
    local str_mask=$2
    echo $str_mask | grep '\.' > /dev/null
    if [ $? -ne 0 ];then
        str_mask=$(v4prefix2mask $str_mask)
    fi
    local str_bcast=''
    local str_temp=''
    local str_ifs=$IFS
    IFS=$'.'
    local array_ip=($1)
    local array_mask=($str_mask)
    IFS=$str_ifs

    if [ ${#array_ip[*]} -ne 4 -o ${#array_mask[*]} -ne 4 ];then
        echo "255.255.255.255"
        return
    fi

    for index in {0..3}
    do
        str_temp=`echo $[ ${array_ip[$index]}|(${array_mask[$index]} ^ 255) ]`
        str_bcast=$str_bcast$str_temp"."
    done

    str_bcast=`echo $str_bcast | sed 's/\.$//'`
    echo "$str_bcast"
}

function v4calcnet(){
    local str_mask=$2
    echo $str_mask | grep '\.' > /dev/null
    if [ $? -ne 0 ];then
        str_mask=$(v4prefix2mask $str_mask)
    fi
    local str_net=''
    local str_temp=''
    local str_ifs=$IFS
    IFS=$'.'
    local array_ip=($1)
    local array_mask=($str_mask)
    IFS=$str_ifs

    for index in {0..3}
    do
        str_temp=`echo $[ ${array_ip[$index]}&${array_mask[$index]} ]`
        str_net=$str_net$str_temp"."
    done

    str_net=`echo $str_net | sed 's/\.$//'`
    echo "$str_net"
}

function v6expand(){
    local str_v6address=$1
    str_v6address=${str_v6address%%/*}
    echo "$str_v6address" | grep '::' > /dev/null
    if [ $? -ne 0 ];then
        echo "$str_v6address"
        return
    fi

    local num_colon=`echo "$str_v6address" | grep -o ':' | wc -l`
    local num_omit=$((7-num_colon))
    local str_temp=0
    local num_index=1
    while [ $num_index -le $num_omit  ];do
        str_temp=$str_temp":0"
        num_index=$((num_index+1))
    done
    
    str_v6address=`echo $str_v6address | sed "s/::/:$str_temp:/" | sed 's/^:/0:/' | sed 's/:$/:0/'`
    echo "$str_v6address"
}

function v6prefix2mask(){
    local num_v6prefix=$1
    num_v6prefix=`echo $num_v6prefix | sed 's:/::g'`
    if [ $num_v6prefix -gt 128 ];then
        $num_v6prefix=128
    fi

    if [ $num_v6prefix -le 0 ];then
        $num_v6prefix=1
    fi

    local num_i=1
    local str_mask=''
    while [ $num_i -le 8 ];do
        if [ $num_v6prefix -ge 16 ];then
            str_mask=$str_mask"ffff:"
            num_v6prefix=$((num_v6prefix-16))
        elif [ $num_v6prefix -eq 0 ];then
            str_mask=$str_mask"0:"
        else
            local str_temp=$(((65535>>$num_v6prefix)^65535))
            str_temp=`echo "$str_temp"|awk '{printf("%x\n",$0)}'`
            str_mask=$str_mask"$str_temp:"
            num_v6prefix=0
        fi
        num_i=$((num_i+1))
    done

    str_mask=`echo $str_mask | sed 's/:$//'`
    echo "$str_mask"
}

function v6calcnet(){
    local str_v6ip=$(v6expand $1)
    local str_v6mask=$2
    local str_v6net=''

    echo "$str_v6maks " | grep ':' > /dev/null
    if [ $? -ne 0 ];then
        str_v6mask=$(v6prefix2mask $str_v6mask)
    fi

    local str_old_ifs=$IFS
    IFS=$':'
    local array_ip=($str_v6ip)
    local array_mask=($str_v6mask)
    IFS=$str_old_ifs

    for num_i in {0..7}
    do
        str_temp=$(( 0x${array_ip[$num_i]} & 0x${array_mask[$num_i]} ))
        str_temp=`echo $str_temp | awk '{printf("%x\n",$0)}'`
        str_v6net=$str_v6net$str_temp":"
    done

    str_v6net=`echo $str_v6net | sed 's/:$//'`
    echo "$str_v6net"
}


function servicemap {
   local svcname=$1
   local svcmgrtype=$2
   local svclistname=   

  # if there are more than 1 possible service names for a service among 
  # different os distributions and os releases, the service should be 
  # specified with structure 
  # INIT_(general service name) = "list of possible service names"
  #  
   INIT_dhcp="dhcp3-server dhcpd isc-dhcp-server";

   INIT_nfs="nfsserver nfs-server nfs nfs-kernel-server";

   INIT_named="named bind9";

   INIT_syslog="syslog syslogd rsyslog";
 
   INIT_firewall="iptables firewalld ufw";

   INIT_http="apache2 httpd";

   INIT_ntpserver="ntpd ntp";

   INIT_mysql="mysqld mysql";

   INIT_ssh="sshd ssh";

   local path=
   local postfix=""
   local retdefault=$svcname
   local svcvar=${svcname//[-.]/_}
   if [ "$svcmgrtype" = "0"  ];then
      path="/etc/init.d/"
   elif [ "$svcmgrtype" = "1"  ];then
      #retdefault=$svcname.service
      path="/usr/lib/systemd/system/"
      postfix=".service"
   elif [ "$svcmgrtype" = "2"  ];then
      path="/etc/init/"
      postfix=".conf"
   fi
   
   svclistname=INIT_$svcvar
   local svclist=$(eval echo \$$svclistname)      

   if [ -z "$svclist" ];then
      svclist="$retdefault"
   fi

   for name in `echo $svclist`
   do
      if [ -e "$path$name$postfix"  ];then
         echo $name
         break
      fi
   done
   
}

#some special services cannot be processed in sysVinit, upstart and systemd framework, should be process here...
#Notice:
# return value: 
# 127 :         if the service $svcname cannot be processed in this function
# otherwise:    the return value of the service action

function specialservicemgr {
   local svcname=$1
   local action=$2

   if [ "$svcname" = "firewall"  ];then
      type -P SuSEfirewall2 >/dev/null 2>&1
      if [ "$?" = "0" ] ;then
         case "$action" in
              "start"|"stop")
              SuSEfirewall2 $action
              ;;
              "restart")
              SuSEfirewall2 stop
              SuSEfirewall2 start
              ;;
              "disable")
              SuSEfirewall2 off
              ;;
              "enable")
              SuSEfirewall2 on
              ;;
              "status")
              service SuSEfirewall2_setup status
              ;;
              *)
              return 127 
              ;;
         esac
         return $?
      fi
   fi

   return 127
}

function startservice {
   local svcname=$1

   local retval
   specialservicemgr "$svcname" start 
   retval=$?
   if [ "$retval" != "127"  ]; then
      return $retval
   fi


   local cmd=
   local svcunit=`servicemap $svcname 1`
   local svcjob=`servicemap $svcname 2`
   local svcd=`servicemap $svcname 0`
  
   if [ -n "$svcunit"  ];then
      cmd="systemctl start $svcunit"
   elif [ -n "$svcjob"  ];then
      cmd="initctl start $svcjob";
   elif [ -n "$svcd"  ];then
      cmd="service $svcd start";
   fi

   if [ -z "$cmd"  ];then
      return 127
   fi
   
   eval $cmd
}



function stopservice {
   local svcname=$1

   local retval
   specialservicemgr "$svcname" stop 
   retval=$?
   if [ "$retval" != "127"  ]; then
      return $retval
   fi

   local cmd=
   local svcunit=`servicemap $svcname 1`
   local svcjob=`servicemap $svcname 2`
   local svcd=`servicemap $svcname 0`
  
   if [ -n "$svcunit"  ];then
      cmd="systemctl stop $svcunit"
   elif [ -n "$svcjob"  ];then
      initctl status $svcjob | grep stop
      if [ "$?" = "0" ] ; then
         return 0
      else
         cmd="initctl stop $svcjob"       
      fi
   elif [ -n "$svcd"  ];then
      cmd="service $svcd stop"
   fi
    
   echo $cmd

   if [ -z "$cmd"  ];then
      return 127
   fi
   
   eval $cmd
}


function restartservice {
   local svcname=$1

   local retval
   specialservicemgr "$svcname" restart 
   retval=$?
   if [ "$retval" != "127"  ]; then
      return $retval
   fi


   local cmd=
   local svcunit=`servicemap $svcname 1`
   local svcjob=`servicemap $svcname 2`
   local svcd=`servicemap $svcname 0`
  
   if [ -n "$svcunit"  ];then
      cmd="systemctl restart $svcunit"
   elif [ -n "$svcjob"  ];then
      initctl status $svcjob | grep stop
      if [ "$?" = "0" ];then 
         cmd= "initctl start $svcjob"
      else
         cmd="initctl restart $svcjob"
      fi 
   elif [ -n "$svcd"  ];then
      cmd="service $svcd restart"
   fi

   if [ -z "$cmd"  ];then
      return 127
   fi
   
   eval $cmd
}


function checkservicestatus {
   local svcname=$1

   local retval
   specialservicemgr "$svcname" status 
   retval=$?
   if [ "$retval" != "127"  ]; then
      return $retval
   fi


   local svcunit=`servicemap $svcname 1`
   local svcjob=`servicemap $svcname 2`
   local svcd=`servicemap $svcname 0`
 
   local output= 
   local retcode=3  

   if [ -n "$svcunit"  ];then
      output=$(systemctl show --property=ActiveState $svcunit|awk -F '=' '{print $2}')
      if echo $output|grep -E -i "^active$";then
         retcode=0
      elif echo $output|grep -E -i "^inactive$";then
         retcode=1
      elif echo $output|grep -E -i "^failed$";then
         retcode=2
      fi
   elif [ -n "$svcjob"  ];then
      output=$(initctl status $svcjob)
      if echo $output|grep -i "waiting";then
         retcode=2
      elif echo $output|grep -i "running";then 
         retcode=0
      fi 
   elif [ -n "$svcd"  ];then
      output=$(service $svcd status)
      retcode=$?
      echo $output 
#      if echo $output|grep -E -i "(stopped|not running)";then
#         retcode=1
#      elif echo $output|grep -E -i "running";then
#         retcode=0
#      fi
   else
      retcode=127
   fi
#echo $svcunit-----$svcd   
   return $retcode
    
}

function enableservice {
   local svcname=$1

   local retval
   specialservicemgr "$svcname" enable 
   retval=$?
   if [ "$retval" != "127"  ]; then
      return $retval
   fi


   local cmd=
   local svcunit=`servicemap $svcname 1`
   local svcjob=`servicemap $svcname 2`
   local svcd=`servicemap $svcname 0`
  
   if [ -n "$svcunit"  ];then
      cmd="systemctl enable  $svcunit"
   elif [ -n "$svcjob"  ];then
      cmd="update-rc.d $svcjob defaults"
   elif [ -n "$svcd"  ];then
     command -v chkconfig >/dev/null 2>&1
     if [ $? -eq 0 ];then
        cmd="chkconfig $svcd on"
     else
        command -v update-rc.d >/dev/null 2>&1
        if [ $? -eq 0 ];then
           cmd="update-rc.d $svcd defaults"
        fi  
     fi
   fi

   if [ -z "$cmd"  ];then
      return 127
   fi
   
   eval $cmd
}


function disableservice {
   local svcname=$1

   local retval
   specialservicemgr "$svcname" disable 
   retval=$?
   if [ "$retval" != "127"  ]; then
      return $retval
   fi

   local cmd=
   local svcunit=`servicemap $svcname 1`
   local svcjob=`servicemap $svcname 2`
   local svcd=`servicemap $svcname 0`
  
   if [ -n "$svcunit"  ];then
      cmd="systemctl disable  $svcunit"
   elif [ -n "$svcjob"  ];then
      cmd="update-rc.d -f $svcd remove"
   elif [ -n "$svcd"  ];then
     command -v chkconfig >/dev/null 2>&1
     if [ $? -eq 0 ];then
        cmd="chkconfig $svcd off";
     else
        command -v update-rc.d >/dev/null 2>&1
        if [ $? -eq 0 ];then
           cmd="update-rc.d -f $svcd remove"
        fi  
     fi
   fi

   if [ -z "$cmd"  ];then
      return 127
   fi
   
   eval $cmd
}

declare -a array_nic_params
declare -a array_extra_param_names
declare -a array_extra_param_values

# This function parse the NICEXTRAPARAMS into an array. 
# Each arry element contains all the extra params for an ip
# For example:
#    
#    NICEXTRAPARAMS="eth0!MTU=1500 sonething=x|MTU=1460,ib0!MTU=65520 CONNECTED_MODE=yes"
#    get_nic_extra_params $eth0 $NICEXTRAPARAMS
#  After the function is called:
#    array_nic_param[0]="MTU=1500 sonething=x"
#    array_nic_param[1]="MTU=1460"
function get_nic_extra_params() {
    nic=$1
    nic_extra=$2

    unset array_nic_params

    if [ ! "$nic_extra" ];then
        return
    fi
    old_ifs=$IFS
    IFS=$','
    array_conf_temp=($nic_extra)
    IFS=$old_ifs
    #echo "nic_extra=$nic_extra"

    i=0
    while [ $i -lt ${#array_conf_temp[@]} ]
    do
        token="${array_conf_temp[$i]}"
        D=
        if echo "$token" | grep "!"; then
            D="!"
        else
            D=":"
        fi
        key=`echo "$token" | cut -d"$D" -f 1`
        #echo "key=$key nic=$nic"
		if [ "$key" == "$nic" ]; then
			str_temp_value=`echo "$token" | cut -d"$D" -f 2`
            #echo "token=$token, str_temp_value=$str_temp_value"
			old_ifs=$IFS
			IFS=$'|'
			array_nic_params=($str_temp_value)
			IFS=$old_ifs
			return
		fi
		i=$((i+1))
    done
}

# This functions parse the extra parameters for an ip address of a nic
# Input is like this:
#     MTU=65520 something=yes
# After the function is called:
#     array_extra_param_names[0]="MTU"
#     array_extra_param_values[0]="65520" 
#     array_extra_param_names[1]="something"
#     array_extra_param_values[0]="yes" 
#     
function parse_nic_extra_params() {
    str_extra=$1
   
    unset array_extra_param_names
    unset array_extra_param_values

	old_ifs=$IFS
	IFS=$' '
	params_temp=($str_extra)
	IFS=$old_ifs
	k=0
	while [ $k -lt ${#params_temp[@]} ]
	do
		token2="${params_temp[$k]}"
		array_extra_param_names[$k]=`echo "$token2" | cut -d'=' -f 1`
		array_extra_param_values[$k]=`echo "$token2" | cut -d'=' -f 2`	
		k=$((k+1))
	done
}
