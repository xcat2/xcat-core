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
            echo $str_line >> $str_conf_file
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
