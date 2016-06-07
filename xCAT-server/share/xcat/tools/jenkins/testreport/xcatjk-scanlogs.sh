#!/bin/bash

function usage()
{
	local script="${0##*/}"

	while read ; do echo "${REPLY}" ; done <<-EOF
	Usage: ${script} [OPTIONS] DIRECTORY

	Options:
	  --help                        display this help and exit
	  --recent                      scan logs for the last three days

	Examples:

	  ${script} --recent /xCATjk/log
	EOF
}

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

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
# check_root_or_exit
#
#	Breaks the script if not running as root.
#
#	If this returns 1, the invoker MUST abort the script.
#
#	Returns 0 if running as root
#	Returns 1 if not (and breaks the script)
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
			echo "Command \"${cmd}\" not found." >&2
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
	exit_if_bad "$?" "Above listed required command(s) not found."
	return 0
}

TMP_DIR=""

#
# internal_setup	Script setup
#
#	Returns 0 on success.
#	Exits (not returns) with 1 on failure.
#
function internal_setup()
{
	shopt -s extglob

	# Trap exit for internal_cleanup function.
	trap "internal_cleanup" EXIT

	check_exec_or_exit awk mktemp printf

	umask 0077

	TMP_DIR="$(mktemp -d "/tmp/${0##*/}.XXXXXXXX" 2>/dev/null)"
	[ -d "${TMP_DIR}" ]
	exit_if_bad "$?" "Make temporary directory failed."

	custom_setup
}

#
# internal_cleanup	Script cleanup (reached via trap 0)
#
#	Destory any temporarily facility created by internal_setup.
#
function internal_cleanup()
{
	custom_cleanup

	[ -d "${TMP_DIR}" ] && rm -rf "${TMP_DIR}"
}

#
# custom_setup
#
function custom_setup()
{
	check_exec_or_exit awk dirname
}

#
# custom_cleanup
#
function custom_cleanup()
{
	:
}

#
# cleanup_n_exec	Do the cleanup, then execute the command
#
#	$1+	The command to execute
#
function cleanup_n_exec()
{
	internal_cleanup

	exec "$@"
}

internal_setup

SCRIPT="$0"
! type readlink >/dev/null 2>&1 &&
        echo "Command \"readlink\" not found" >&2 && exit 1
while [ -L "${SCRIPT}" ]
do
        LINK="$(readlink "${SCRIPT}")"
        if [ "/" = "${LINK:0:1}" ]
        then
                SCRIPT="${LINK}"
        else
                SCRIPT="${SCRIPT%/*}/${LINK}"
        fi
done
BASE_DIR="${SCRIPT%/*}"

xCATjkLog2SQL="${BASE_DIR}/xcatjk-log2sql.sh"
[ -x "${xCATjkLog2SQL}" ]
exit_if_bad "$?" "Script ${xCATjkLog2SQL} not found"

declare VERSION="0.0.1"

declare xCATjkLog_TOPDIR=""
declare -a FIND_ARGS=()

while [ "$#" -gt "0" ]
do
	case "$1" in
	"--help")
		usage
		exit 0
		;;
	"--recent")
		FIND_ARGS=(-mtime -3)
		;;
	*)
		[ "$1" == "--" ] && shift
		[ -z "${xCATjkLog_TopDir}" ]
		exit_if_bad "$?" "invalid predicate - $1"
		xCATjkLog_TopDir="$1"
		;;
	esac
	shift
done

[ -z "${xCATjkLog_TopDir}" ] && usage >&2 && exit 1

[ -d "${xCATjkLog_TopDir}" ]
exit_if_bad "$?" "${xCATjkLog_TopDir}: No such directory"

while read ; do echo "${REPLY}" ; done <<EOF
-- xCATjkScanLogs - version ${VERSION}
--
-- Run on host ${HOSTNAME}
-- ------------------------------------------------------
-- Top level log directory    '${xCATjkLog_TopDir}'

EOF

find "${xCATjkLog_TopDir}" -name 'log.*-*-*' "${FIND_ARGS[@]}" -print0 |
	xargs -r -n 1 -0 awk '{ print $1, FILENAME; exit }' | sort -k 1 |
	awk '{ print $2 }' | xargs -r -n 1 dirname |
	xargs -r -n 1 "${xCATjkLog2SQL}"

while read ; do echo "${REPLY}" ; done <<EOF

--
-- All log directories parse completed on $(date "+%Y-%m-%d %H:%M:%S %z")
EOF

exit 0
