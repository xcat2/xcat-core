#!/bin/bash

cn=$1
mn=$2

ntpservers=`rspconfig $cn ntpservers | awk -F":" '{print $3}' | sed 's/^ //;s/ $//'`
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

output=`rspconfig $cn ntpservers=$new_ntpservers`
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

echo "To clear environment"

if [ $ntpservers != "None" ]; then
    original_ntpservers="$ntpservers"
else
    original_ntpservers=""
fi

output=`rspconfig $cn ntpservers=$original_ntpservers`
if [ $? -ne 0 ]; then
    echo "rspconfig $cn ntpservers=$ntpservers failed when clearing environment"
    exit 1
fi

if [[ "$output" =~ "$cn: BMC NTP Servers" ]] && [[ $output =~ "$ntpservers" ]]; then
    echo "Setting NTPServers as $ntpservers success when clearing environment"
    exit 0
fi

echo "Setting NTPServers as $ntpservers failed when clearing environment"
exit 1
