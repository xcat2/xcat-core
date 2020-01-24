#!/bin/bash
PATH="/opt/xcat/bin:/opt/xcat/sbin:/opt/xcat/share/xcat/tools:/usr/sbin:/usr/bin:/sbin:/bin:/root/bin"
export PATH

function runcmd(){
    echo "Run command $*"
    result=`$*`
    if [[ $? -eq 0 ]];then
        echo $result;
        echo "Run command $*....[Succeed]\n";
        return 0;
    else
        echo $result;
        echo "Run command $*... [Failed]\n";
        return 1;
    fi
}

function check_passwd_table(){
echo "Run tabdump passwd to check if password with $MGT exists"
tabdump passwd |grep $MGT
    if [ $? -eq 0 ];then
        `tabdump passwd |grep $MGT>$TMPFILE`
    else
        echo "There is no password in passwd table associated with $MGT"
        return 1;
    fi
}
function modify_passwd_table(){
Username=`cat $TMPFILE |awk -F "\""  '{print $4}'`;
Passwd=`cat $TMPFILE |awk -F "\""  '{print $6}'`;
cmd="chtab key=$MGT passwd.password=$Passwd.wrong passwd.username=$Username";
runcmd $cmd;
cmd="tabdump passwd";
runcmd $cmd;
}
function add_passwd_table()
{
cmd="chtab key=$MGT passwd.password=$2 passwd.username=$3";
runcmd $cmd;
cmd="rpower $1 stat";
runcmd $cmd;
    if [ $? -eq 0 ];then
        cmd="chtab key=$MGT passwd.password=$2.wrong passwd.username=$3";
        runcmd $cmd;
        cmd="tabdump passwd";
        runcmd $cmd; 
    else
        echo "rpower $1 stat failed.Wrong password is provided, please check bmc username and password";
    fi
}
function modify_node_definition()
{
cmd="chdef $1 bmcpassword=$2  bmcusername=$3";
runcmd $cmd;
cmd="rpower $1 stat";
runcmd $cmd;
    if [ $? -eq 0 ];then
        runcmd "chdef $1 bmcpassword=$2.wrong  bmcusername=$3";
        runcmd "tabdump passwd";
    else
        echo "rpower $1 stat failed.Wrong password is provided, please check bmc username and password"; 
    fi
}
function clear_env(){
    if [ -f $TMPFILE ];then
        Username=`cat $TMPFILE |awk -F "\""  '{print $4}'`;
        Passwd=`cat $TMPFILE |awk -F "\""  '{print $6}'`;
        cmd="chtab key=$MGT passwd.password=$Passwd passwd.username=$Username";
	runcmd $cmd;
	cmd="tabdump passwd";
        runcmd $cmd;
        cmd="chdef $1 bmcpassword= bmcusername=";
        runcmd $cmd;
        rm -rf $TMPFILE;
    else
        cmd="chtab -d key=$MGT passwd";
        runcmd $cmd;
        cmd="chdef $1 bmcpassword= bmcusername=";
        runcmd $cmd;
    fi
}
function check_result(){
output=$(rpower $1 stat  2>&1)
echo "rpower $1 stat output is $output"
value="";
    if [[ `lsdef $1 |grep mgt ` =~ "ipmi" ]];then
        value="Incorrect password provided";
    else
        value="Error: Invalid username or password";
    fi
        if [[ $output =~ $value ]];then
            return 0;
        else
            echo "The expected output is \"$value\" since there password is wrong, but the real output is $output"
            return 1;
        fi
}

SCRIPT=$(readlink -f $0)

TMPFILE="/tmp/xcat-test-`basename $SCRIPT`.tmp"
MGT=""
    if [[ `lsdef $2 |grep mgt` =~ "ipmi" ]];then
        MGT="ipmi";
    else
        MGT="openbmc";
    fi
echo "The node $2's mgt is defined as $MGT"
while [ "$#" -gt "0" ]
do
        case $1 in
                "-pt"|"--passwdtable" )
                check_passwd_table
                    if [[ $? -eq 0 ]];then
                        modify_passwd_table
                        check_result $2
                            if [[ $? -eq 1 ]];then
                                exit 1
                            else
                                exit 0
                            fi

                    else
                        add_passwd_table $2 $3 $4
                        check_result $2
                            if [[ $? -eq 1 ]];then
                                exit 1
                            else
                                exit 0
                            fi
                    fi
                ;;
                "-apt"|"--addpasswdtable" )
                check_passwd_table
                    if [[ $? -eq 0 ]];then
                         cmd="chtab -d key=ipmi passwd";
                         runcmd $cmd; 
                            if [[ $? -eq 1 ]];then
                                exit 1
                            fi
                    fi
                    modify_node_definition  $2 $3 $4
                    check_result $2
                        if [[ $? -eq 1 ]];then
                            exit 1
                        else
                            exit 0
                        fi
                ;;
                "-c"|"--clear" )
                clear_env $2
                if [[ $? -eq 1 ]];then
                    exit 1
                else
                    exit 0
                fi
                ;;
                *)
                echo
                echo "Please Insert $0: -pt|-apt|-c"
                echo
                exit 1;
                ;;
                esac
done


