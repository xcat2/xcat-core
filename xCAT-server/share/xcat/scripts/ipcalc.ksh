#!/bin/ksh
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#egan@us.ibm.com
#(C)IBM Corp

#
#RH ipcalc "cleanroom" clone in ksh
#no --silent option, just 2>/dev/null
#

MYNAME=$0

function validateip
{
	set -A ipa $(echo $* | tr '.' ' ')
	integer nipa=${#ipa[*]}
	if ((nipa != 4))
	then
		return 1
	fi
	integer a=${ipa[0]}
	for j in 0 1 2 3
	do
		integer a=${ipa[$j]}
		if ((a > 255))
		then
			return 4
		fi
	done
}

function usage {
	echo "\nUsage: ${MYNAME} [--hostname] [--broadcast] [--network] [--netmask] ip [netmask]\n"
}

if [ "$#" = "0" ]
then
	usage >&2
	exit 1
fi

HOSTNAME=0
BROADCAST=0
NETWORK=0
NETMASK=0

for i in $*
do
	case "$i" in
		-*)
			case "$i" in
				"--hostname")
					HOSTNAME=1
					shift
					;;
				"--broadcast")
					BROADCAST=1
					shift
					;;
				"--network")
					NETWORK=1
					shift
					;;
				"--netmask")
					NETMASK=1
					shift
					;;
				*)
					usage >&2
					exit 1
					;;
			esac
			;;
	esac
done

if [ -z "$1" ]
then
	usage >&2
	exit 1
fi
IP=$1
shift

NM=""
if [ ! -z "$1" ]
then
	NM=$1
	shift
fi

if [ "$#" -gt "0" ]
then
	usage >&2
	exit 1
fi

if validateip $IP
then
	:
else
	echo "$0: bad ip $IP" >&2
	exit 1
fi

if [ ! -z "$NM" ]
then
	if validateip $NM
	then
		:
	else
		echo "$0: bad netmask $NM" >&2
		exit 1
	fi
fi

if [ "$BROADCAST" = "1" -o "$NETWORK" = "1" ]
then
	if [ -z "$NM" ]
	then
		echo "$0: netmask expected" >&2
		exit 1
	fi
fi

if [ "$HOSTNAME" = "1" ]
then
	if host $IP >/dev/null 2>&1
	then
		HOSTNAME=$(host $IP 2>/dev/null | awk '{print $5}' | awk -F. '{print $1}')
		echo "HOSTNAME=$HOSTNAME"
	else
		echo "$0: cannot find hostname for $IP: Unknown host" >&2
	fi
fi

if [ "$BROADCAST" = "1" -o "$NETWORK" = "1" ]
then
	set -A ipa $(echo $IP | tr '.' ' ')
	set -A nma $(echo $NM | tr '.' ' ')
	NW=""
	BC=""
	for j in 0 1 2 3
	do
		integer a=${ipa[$j]}
		integer b=${nma[$j]}
		integer c=a\&b
		NW="$NW$c."
		integer d=b\^255
		integer e=c\|d
		BC="$BC$e."
	done
	NW=$(echo $NW | sed 's/.$//')
	BC=$(echo $BC | sed 's/.$//')
	if [ "$BROADCAST" = "1" ]
	then
		echo "BROADCAST=$BC"
	fi
	if [ "$NETWORK" = "1" ]
	then
		echo "NETWORK=$NW"
	fi
fi

if [ "$NETMASK" = "1" ]
then
	if [ -z "$NM" ]
	then
		integer ipa=$(echo $IP | awk -F. '{print $1}')
		NM=255.255.0.0
		if((ipa < 128))
		then
			NM=255.0.0.0
		fi
		if((ipa > 191))
		then
			NM=255.255.255.0
		fi
	fi
	echo "NETMASK=$NM"
fi

exit 0

