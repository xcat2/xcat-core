#!/bin/bash

function test_openbmccommand()
{
node_number=0;
number=0;
if [[ $1 ]]&&[[ $2 ]]&&[[ $3 ]];then
    `$1 $2 $3 >/tmp/openbmccommand.test`;
    if [[ $? -eq 0 ]];then
        echo right command;
        number=`awk 'END{print NR}' /tmp/openbmccommand.test`
        echo number is $number
        `cat /tmp/openbmccommand.test |awk -F : '{print $1}' > /tmp/openbmccommand.test1`
        for i in `cat /tmp/openbmccommand.test1`
            do
                  echo $i
                  if [[ $i == $2 ]];then
                      node_number=1;
                  else
                     echo no than more node checked
                     node_number=2;
                  fi
             done
        if [[ $node_number -eq 1 ]];then
            `cat /tmp/openbmccommand.test |awk -F : '{print $2}'> /tmp/openbmccommand.test2`
            if [[ $number -eq 1 ]]&&[[ `awk -F "" '{for(i=1;i<=NF;++i) if($i==":") ++sum}END{print sum}' /tmp/openbmccommand.test` -eq 1 ]];then
                if [[ `cat /tmp/openbmccommand.test` =~ "No attributes returned from the BMC" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No mprom information is available" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No deviceid information is available" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No uuid information is available" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No guid information is available" ]];then
                    echo "No attributes"
                    return 0;
                else
                    return 1;
                fi
            else
                if [[ `cat /tmp/openbmccommand.test2` =~ "No attributes returned from the BMC" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No mprom information is available" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No deviceid information is available" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No uuid information is available" ]]||[[ `cat /tmp/openbmccommand.test` =~ "No guid information is available" ]];then
                    echo "wrong return"
                    return 1;
                else
                    echo "right return"
                    return 0
                fi
            fi
        else
            if [[ $node_number -eq 2 ]];then
               return 0;
            fi
        fi
    else
        return 1;
    fi
else
    return 1;
fi
}
test_openbmccommand $1 $2 $3
if  [[ $? -eq 0 ]];then
    exit 0;
else
    exit 1;
fi
