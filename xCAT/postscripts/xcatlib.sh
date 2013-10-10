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
    `grep "#XCAT_CONFIG" /etc/network/interfaces`
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

