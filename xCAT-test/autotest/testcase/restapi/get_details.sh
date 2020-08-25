#!/bin/bash

# This script display the detail of a resource.
# MN, CN, username, password, resource and specific resource must be specified.

MN=$1
CN=$2
username=$3
password=$4
RS=$5
ITEM=$6

xdsh $CN "curl -X GET --cacert /root/ca-cert.pem 'https://$MN/xcatws/$RS/$ITEM?userName=$username&userPW=$password'"
