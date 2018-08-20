#!/bin/bash
function check_passwd_table(){
tabdump passwd |grep $MGT
    if [ $? -eq 0 ];then
        `tabdump passwd |grep $MGT>$TMPFILE`
    else
        return 1;
    fi
}
function modify_passwd_table(){
Username=`cat $TMPFILE |awk -F "\""  '{print $4}'`;
Passwd=`cat $TMPFILE |awk -F "\""  '{print $6}'`;
`chtab key=$MGT passwd.password=$Passwd.wrong passwd.username=$Username`;
tabdump passwd;
}
function add_passwd_table()
{
`chtab key=$MGT passwd.password=$2 passwd.username=$3`;
rpower $1 stat
    if [ $? -eq 0 ];then
        `chtab key=$MGT passwd.password=$2.wrong passwd.username=$3`;
        tabdump passwd;
    else
        echo "wrong password";
    fi
}
function modify_node_definition()
{
chdef $1 bmcpassword=$2  bmcusername=$3
rpower $1 stat
    if [ $? -eq 0 ];then
        chdef $1 bmcpassword=$2.wrong  bmcusername=$3;
        tabdump passwd;
    else
         echo "wrong password";
    fi
}
function clear_env(){
    if [ -f $TMPFILE ];then
        Username=`cat $TMPFILE |awk -F "\""  '{print $4}'`;
        Passwd=`cat $TMPFILE |awk -F "\""  '{print $6}'`;
        chtab key=$MGT passwd.password=$Passwd passwd.username=$Username;tabdump passwd;
        chdef $1 bmcpassword= bmcusername=;
        rm -rf $TMPFILE;
    else
        `chtab -d key=$MGT passwd`;
        chdef $1 bmcpassword= bmcusername=;
    fi
}
function check_result(){
output=$(rpower $1 stat  2>&1)
echo output is $output
value="";
    if [[ `lsdef $1 |grep mgt ` =~ "ipmi" ]];then
        value="Incorrect password provided";
    else
        value="Error: Invalid username or password";
    fi
        if [[ $output =~ $value ]];then
            return 0;
        else
            return 1;
        fi
}
echo "0 ARG: $0"

SCRIPT=$(readlink -f $0)
echo "SCRIPT=$SCRIPT"

TMPFILE="/tmp/xcat-test-`basename $SCRIPT`.tmp"
echo "TMPFILE=$TMPFILE"
MGT=""
    if [[ `lsdef $2 |grep mgt` =~ "ipmi" ]];then
        MGT="ipmi";
    else
        MGT="openbmc";
    fi
echo mgt is $MGT
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
                        `chtab -d key=ipmi passwd`;
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


