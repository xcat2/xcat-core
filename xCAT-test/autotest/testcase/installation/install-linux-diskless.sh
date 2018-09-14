#!/bin/bash

# The purpose of this test case is rewrite the existing diskfull compute node
# installation test for xCAT. But allow the compute node to run a different
# Linux distro or version from the management node.

#
#
#

#
# warn_if_bad           Put out warning message(s) if $1 has bad RC.
#
#       $1      0 (pass) or non-zero (fail).
#       $2+     Remaining arguments printed only if the $1 is non-zero.
#
#       Incoming $1 is returned unless it is 0
#
function warn_if_bad()
{
	local -i rc="$1"
	local script="${0##*/}"

	# Ignore if no problems
	[ "${rc}" -eq "0" ] && return 0

	# Broken
	shift
	echo "${script}: $@" >&2
	return "${rc}"
}

#
# exit_if_bad           Put out error message(s) if $1 has bad RC.
#
#       $1      0 (pass) or non-zero (fail).
#       $2+     Remaining arguments printed only if the $1 is non-zero.
#
#               Exits with 1 unless $1 is 0
#
function exit_if_bad()
{
	warn_if_bad "$@" || exit 1
	return 0
}

function usage()
{
	cat <<-EOF
	Usage: ${0##*/} --compute-node a_node --iso-file /path/to/rhels8-ppc64le.iso
	EOF
}

while [ "$#" -gt "0" ]
do
	case "$1" in
	"-h"|"--help")
		usage
		exit 0
		;;
	"--compute-node")
		shift
		COMPUTE_NODE="$1"
		;;
	"--compute-node="*)
		COMPUTE_NODE="${1#--compute-node=}"
		;;
	"--iso-file")
		shift
		ISO_FILE="$1"
		;;
	"--iso-file="*)
		ISO_FILE="${1#--iso-file=}"
		;;
	*)
		warn_if_bad "$?" "redundancy command line argument -- \`$1'"
		exit_if_bad "$?" "Try \`$0 --help' for more information"
		;;
	esac
	shift
done

# Make sure the compute node is defined
lsdef -t node "${COMPUTE_NODE}"
exit_if_bad "$?" "No xCAT definition of compute node \`${COMPUTE_NODE}'"

# Make sure the ISO file exist
[ -f "${ISO_FILE}" ]
exit_if_bad "$?" "File not found - \`${ISO_FILE}'"
[ -r "${ISO_FILE}" ]
exit_if_bad "$?" "Permission denied - \`${ISO_FILE}'"

# Guess the Distro name of the ISO file
# Guess the Arch of the ISO file
while read -r line
do
	case "${line}" in
	"OS Image:"*)
		;;
	"DISTNAME:"*)
		DISTRO="${line#DISTNAME:}"
		;;
	"ARCH:"*)
		ARCH="${line#ARCH:}"
		;;
	"DISCNO:"*)
		;;
	esac
done < <(copycds -i "${ISO_FILE}")
unset line

# Make sure there is no service node involved
chdef -t node -o "${COMPUTE_NODE}" servicenode= monserver= nfsserver= tftpserver= xcatmaster=

makedns -n

makegocons "${COMPUTE_NODE}" || makeconservercf "${COMPUTE_NODE}"

case "$(lsdef -t node "${COMPUTE_NODE}" -i mgt | awk -F = '/mgt=/ { print $NF }')" in
"fsp"|"hmc")
	getmacs -D "${COMPUTE_NODE}"
	;;
esac

chdef -t site extntpservers=
chdef -t site 'ntpservers=<xcatmaster>'

makentp
makedhcp -n
makedhcp "${COMPUTE_NODE}"

declare -i NETBOOT_TIMEOUT=90
declare -i WAIT=0
declare -i SLEEP=2

while sleep "${SLEEP}"
do
	(( WAIT += SLEEP ))
	makedhcp -q "${COMPUTE_NODE}" | grep "^${COMPUTE_NODE}:" && break
	(( WAIT <= NETBOOT_TIMEOUT ))
	exit_if_bad "$?" "timeout"
done

copycds "${ISO_FILE}"

chdef -t node -o "${COMPUTE_NODE}" postscripts=setupntp

genimage "${DISTRO}-${ARCH}-netboot-compute"
exit_if_bad "$?" "genimage failed"

packimage "${DISTRO}-${ARCH}-netboot-compute"
exit_if_bad "$?" "packimage failed"

# Use the xCAT default generated osimage definition
rinstall "${COMPUTE_NODE}" "osimage=${DISTRO}-${ARCH}-netboot-compute"
exit_if_bad "$?" "rinstall failed"

# Wait for the node status change to `booted'

declare -i NETBOOT_TIMEOUT=900
declare -i WAIT=0
declare -i SLEEP=10

while sleep "${SLEEP}"
do
	(( WAIT += SLEEP ))
	case "$(lsdef -t node "${COMPUTE_NODE}" -i status | awk -F = '/status=/ { print $NF }')" in
	"booted")
		break
		;;
	esac
	(( WAIT <= NETBOOT_TIMEOUT ))
	exit_if_bad "$?" "timeout"
done

# Wait for the nodestat change to `sshd'

declare -i NETBOOT_TIMEOUT=300
declare -i WAIT=0
declare -i SLEEP=10

while sleep "${SLEEP}"
do
	(( WAIT += SLEEP ))
	nodestat "${COMPUTE_NODE}" | grep ': sshd$' && break
	(( WAIT <= NETBOOT_TIMEOUT ))
	exit_if_bad "$?" "timeout"
done

# Wait for a successful xdsh

declare -i NETBOOT_TIMEOUT=300
declare -i WAIT=0
declare -i SLEEP=10

while sleep "${SLEEP}"
do
	(( WAIT += SLEEP ))
	xdsh "${COMPUTE_NODE}" 'date -R' && break
	(( WAIT <= NETBOOT_TIMEOUT ))
	exit_if_bad "$?" "timeout"
done
