#!/bin/bash

# Author:   GONG Jie <neo@linux.vnet.ibm.com>
# Create:   2016-10-17
# Update:   2016-10-21
# Version:  1.3.0

#
# warn_if_bad		Put out warning message(s) if $1 has bad RC.
#
#	$1	0 (pass) or non-zero (fail).
#	$2+	Remaining arguments printed only if the $1 is non-zero.
#
#	Incoming $1 is returned unless it is 0
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
# exit_if_bad		Put out error message(s) if $1 has bad RC.
#
#	$1	0 (pass) or non-zero (fail).
#	$2+	Remaining arguments printed only if the $1 is non-zero.
#
#               Exits with 1 unless $1 is 0
#
function exit_if_bad()
{
	warn_if_bad "$@" || exit 1
	return 0
}

#
# check_root_or_break
#
#	Breaks the script if not running as root.
#
#	If this returns 1, the invoker MUST abort the script.
#
#	returns 0 if running as root
#	returns 1 if not (and breaks the script)
#
function check_root_or_exit()
{
	[ "${UID}" -eq "0" ]
	exit_if_bad "$?" "Must be run by UID=0. Actual UID=${UID}."
	return 0
}

#
# check_executes	Check for executable(s)
#
#	Returns 0 if true.
#	Returns 1 if not.
#
function check_executes()
{
	local cmd
	local all_ok="yes"
	for cmd in "$@"
	do
		if ! type "${cmd}" &>/dev/null
		then
			echo "Command \"${cmd}\" not found" >&2
			all_ok="no"
		fi
	done
	[ "${all_ok}" = "yes" ]
}

#
# check_exec_or_exit	Check for required executables.
#
#	Exits (not returns) if commands listed on command line do not exist.
#
#	Returns 0 if true.
#	Exits with 1 if not.
#
function check_exec_or_exit()
{
	check_executes "$@"
	exit_if_bad "$?" "Above listed required command(s) not found"
	return 0
}

#
# internal_setup	Script setup
#
#	Returns 0 on success.
#	Exits (not returns) with 1 on failure.
#
function internal_setup()
{
	# Trap exit for internal_cleanup function.
	trap "internal_cleanup" 0

	umask 0077

	check_exec_or_exit cat cpio find grep tail tee touch xargs
}

#
# internal_cleanup	Script cleanup (reached via trap 0)
#
#	Destory any temporarily facility created by internal_setup.
#
function internal_cleanup()
{
	custom_cleanup
}

function custom_cleanup()
{
	rm -rf "/install/netboot/testing0000"
}


PATH="/opt/xcat/bin:/opt/xcat/sbin:/bin:/sbin:/usr/bin:/usr/sbin"

OSIMAGE="$(lsdef -t osimage | grep -- -netboot-compute | head -n 1)"
[ -n "${OSIMAGE}" ]
exit_if_bad "$?" "Diskless osimage not found"

lsdef -t osimage "${OSIMAGE}" -z | sed -e 's/^.*:$/compute_9999z/' | mkdef -z

# The new osimage name is compute_9999z
OSIMAGE="compute_9999z"

lsdef -t osimage "${OSIMAGE}"
exit_if_bad "$?" "Diskless osimage ${OSIMAGE} not created"

chdef -t osimage "${OSIMAGE}" "rootimgdir=/install/netboot/testing0000/${OSIMAGE}"
exit_if_bad "$?" "Command chdef failed"

genimage "${OSIMAGE}" &
CHILD="$!"

sleep 1

kill -0 "${CHILD}"
exit_if_bad "$?" "Process not found"

kill -SIGINT "${CHILD}"
exit_if_bad "$?" "Send SIGINT failed"

sleep 2

ps axo comm | grep genimage
[ "$?" -ne "0" ]
exit_if_bad "$?" "Still running 000"

ps axo pgrp | grep "${CHILD}"
[ "$?" -ne "0" ]
exit_if_bad "$?" "Still running 001"

exit 0
