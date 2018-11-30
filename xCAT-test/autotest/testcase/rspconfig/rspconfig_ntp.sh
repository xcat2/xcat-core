#!/bin/bash

cn=$1
mn=$2

ipsrc=`rspconfig $cn ipsrc | grep "BMC IP Source" | awk -F":" '{print $3}' | sed 's/^ //;s/ $//'`
if [ $? -ne 0 ]; then
    echo "rspconfig $cn ipsrc failed"
    exit 1
fi

echo "BMC IP Source is $ipsrc"

ntpservers=`rspconfig $cn ntpservers | grep "BMC NTP Servers" | awk -F":" '{print $3}' | sed 's/^ //;s/ $//'`
if [ $? -ne 0 ]; then
    echo "rspconfig $cn ntpservers failed"
    exit 1
fi

echo "The original BMC NTP Servers is $ntpservers"

if [ $ntpservers != "None" ]; then
   new_ntpservers=$ntpservers"_test"
else
   new_ntpservers=$mn
fi

output=`rspconfig $cn ntpservers=$new_ntpservers 2>&1`
echo "$output"
if [ $ipsrc == "DHCP" ]; then
    if [ $? -ne 1 ]; then
        if [[ "$output" =~ "Error: BMC IP source is DHCP, could not set NTPServers" ]]; then
            echo "Get correct output for BMC IP source is DHCP"
            exit 0
        else
            echo "Get output '$output' when want to set NTPServers for BMC IP source is DHCP"
            exit 1
        fi
    else
        echo "Get wrong exit code $? when want to set NTPServers for BMC IP source is DHCP" 
        exit 1
    fi
fi

if [ $? -ne 0 ]; then
    echo "rspconfig $cn ntpservers=$new_ntpservers failed"
    exit 1
fi

if [[ $output =~ "$cn: BMC NTP Servers" ]]  && [[ $output =~ "$new_ntpservers" ]]; then
    echo "Setting NTPServers as $new_ntpservers success"
else
    echo "Setting NTPServers as $new_ntpservers failed, the output is $output"
    exit 1
fi

output=`rspconfig $cn ntpservers 2>&1`
if [[ $output =~ "$cn: BMC NTP Servers" ]]  && [[ $output =~ "$new_ntpservers" ]]; then
    echo "Checked NTPServers as $new_ntpservers success"
else
    echo "Checked NTPServers as $new_ntpservers failed, the output is $output"
    exit 1
fi

echo "rpower $cn bmcreboot to check ntpservers setting..."
rpower $cn bmcreboot
if [ $? -ne 0 ]; then
    echo "run rpower $cn bmcreboot failed"
else
    sleep 300
fi

output=`rspconfig $cn ntpservers 2>&1`
if [[ $output =~ "$cn: BMC NTP Servers" ]]  && [[ $output =~ "$new_ntpservers" ]]; then
    echo "Verified NTPServers $new_ntpservers after BMC reboot"
else
    echo "Verified NTPServers as $ntpservers failed after BMC reboot, output is $output"
    exit 1
fi

echo "To clear environment"

if [ $ntpservers != "None" ]; then
    original_ntpservers="$ntpservers"
else
    original_ntpservers=""
fi

output=`rspconfig $cn ntpservers=$original_ntpservers 2>&1`
if [ $? -ne 0 ]; then
    echo "rspconfig $cn ntpservers=$ntpservers failed when clearing environment"
    exit 1
fi
if [[ "$output" =~ "$cn: BMC NTP Servers" ]] && [[ $output =~ "$ntpservers" ]]; then
    echo "Setting NTPServers as $ntpservers success when clearing environment"
fi

output=`rspconfig $cn ntpservers 2>&1`
if [[ "$output" =~ "$cn: BMC NTP Servers" ]] && [[ $output =~ "$ntpservers" ]]; then
    echo "Checked NTPServers as $ntpservers success when clearing environment" 
else
    echo "Checked NTPServers as $ntpservers failed when clearing environment output is $output"
    exit 1
fi

echo "rpower $cn bmcreboot to recover environment"
rpower $cn bmcreboot
if [ $? -ne 0 ]; then
    echo "run rpower $cn bmcreboot failed when recover environment"
    exit 1
else
    sleep 300
fi

output=`rspconfig $cn ntpservers 2>&1`
if [[ "$output" =~ "$cn: BMC NTP Servers" ]] && [[ $output =~ "$ntpservers" ]]; then
    echo "Verified NTPServers as $ntpservers success when clearing environment after BMC reboot"
    exit 0
fi

echo "Verified NTPServers as $ntpservers failed when clearing environment after BMC reboot, output is $output"
exit 1
