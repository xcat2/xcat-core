#!/bin/bash

if [[ -z ${1} ]]; then
    echo "ERROR, pass in the '\$OS' variable as the second argument"
    exit  1
fi
OS=${1}

if [[ $OS != *"rhels"* ]]; then
    echo "INFO: will not run this test for $OS"
    exit  0
fi

MAJOR_OS_VER=`echo $OS | cut -d'.' -f1`
if [[ $OS == *"$MAJOR_OS_VER"* ]]; then
    IFS='
'
    for image in `lsdef -t osimage -i template -c | grep $OS | grep "install"`; do
        THE_NAME=`echo $image | cut -d' ' -f1`
        THE_TEMPLATE=`echo $image | cut -d' ' -f2`
        TEMPLATE_FILE=`echo $THE_TEMPLATE | cut -d= -f2`

        if [[ $TEMPLATE_FILE != *"$MAJOR_OS_VER"* ]]; then
            echo "ERROR - template attribute not set correctly when copycds for $THE_NAME"
            echo -e "ERROR - $TEMPLATE_FILE"
            exit  1
        else
            echo "Template file looks good for $THE_NAME"
            echo -e "\t$THE_TEMPLATE"
        fi
    done
fi

exit 0
