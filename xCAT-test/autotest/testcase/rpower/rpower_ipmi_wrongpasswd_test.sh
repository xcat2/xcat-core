#!/bin/bash
function check_passwd_table(){
tabdump passwd |grep ipmi
    if [ $? -eq 0 ];then
        `tabdump passwd |grep ipmi>/tmp/xcat_test_rpower_ipmi_wrongpasswd`
    else
        return 1;
    fi
}
function modify_passwd_table(){
Username=`cat /tmp/xcat_test_rpower_ipmi_wrongpasswd |awk -F "\""  '{print $4}'`;
Passwd=`cat /tmp/xcat_test_rpower_ipmi_wrongpasswd |awk -F "\""  '{print $6}'`;
`chtab key=ipmi passwd.password=$Passwd.wrong passwd.username=$Username`;
tabdump passwd;
}
function add_passwd_table()
{
echo i is $1,$2,$3
`chtab key=ipmi passwd.password=$2 passwd.username=$3`;
rpower $1 stat
    if [ $? -eq 0 ];then
        `chtab key=ipmi passwd.password=$2.wrong passwd.username=$3`;
        tabdump passwd;
    else
        echo "wrong password";
    fi
}
function modify_node_definition()
{
echo node is  $1,$2,$3
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
    if [ -f /tmp/xcat_test_rpower_ipmi_wrongpasswd ];then
        Username=`cat /tmp/xcat_test_rpower_ipmi_wrongpasswd |awk -F "\""  '{print $4}'`;
        Passwd=`cat /tmp/xcat_test_rpower_ipmi_wrongpasswd |awk -F "\""  '{print $6}'`;
        chtab key=ipmi passwd.password=$Passwd passwd.username=$Username;tabdump passwd; 
        rm -rf /tmp/xcat_test_rpower_ipmi_wrongpasswd;
    else
        `chtab -d key=ipmi passwd`;
        chdef $1 bmcpassword= bmcusername=;
    fi
}
function check_result(){
echo node is $1;
output=$(rpower $1 stat /dev/null  2>&1)
echo output is $output
    if [[ $output =~ "Incorrect password provided" ]];then
        return 0;
    else
        return 1;
    fi
}
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


