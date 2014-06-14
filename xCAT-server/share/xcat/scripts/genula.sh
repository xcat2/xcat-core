#!/bin/bash
# This script will generate an IPv6 ULA.  In IPv6, you know longer get to pick your favorite private network network and go for it,
# you must accept a psuedorandom /48 out of the fd::/8 space.  This script will generate a /48 for either deploying an isolated
# ipv6 network that will almost certainly not conflict with present and future upstream ipv6 networks or just getting your feet wet
# with ipv6

# Implements RFC5193, section 3.2.2, with precision only down to nanoseconds at best (normalized by date output
SECSDOTNANO=$(date +%s.%N|sed -e 's/\.0*/\./')

NANOSECONDS=${SECSDOTNANO#*.}
#Convert from nanoseconds to ntp fractional seconds (I'll call them ticks for convenience)
# ns * 2**32 ticks/second * 1/1000000000 ns/s = ticks
NTPTICKS=$(( ($NANOSECONDS<<32) /1000000000))

EPOCHDELTA=2208988800
SECONDS=${SECSDOTNANO%.*}
SECONDS=$(($SECONDS+$EPOCHDELTA))
TIMESTAMP=$(printf "%08X:%08X" $SECONDS $NTPTICKS)


#next, get a mac address and convert to eui64
EUIPAD="FF:FE"
#MAC=$(/sbin/ifconfig|grep HWaddr|grep -v usb|grep -v 00:00:00:00:00:00|head -n 1|awk '{print $NF}')
MAC=$(ip -oneline link show|grep  -v usb|grep -v 00:00:00:00:00:00|head -n 1|sed -ne "s/.*link\/ether //p"|awk -F ' ' '{print $1}')
FIRSTBYTE=${MAC%%:*}
FIRSTBYTE=$(printf %02X $((0x$FIRSTBYTE|2)))
OTHERMANUF=${MAC%%:??:??:??}
OTHERMANUF=${OTHERMANUF#??:}
LOWMAC=${MAC#??:??:??:}
EUI=$FIRSTBYTE:$OTHERMANUF:$EUIPAD:$LOWMAC

#now, to do the SHA, spec doesn't say much about encoding, so we'll just slap the data together the laziest way

PREFIX="fd"$(echo $TIMESTAMP:$EUI|sha1sum|awk '{print $1}'|cut -c 31-)
PREFIX=$(echo $PREFIX|sed -e 's/\(....\)/\1:/g')
echo $PREFIX:/48
