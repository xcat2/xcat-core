#!/bin/bash

function usage()
{
	local script="${0##*/}"

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	Usage: ${script} [OPTIONS] DIRECTORY

	Options:
	  --help                        display this help and exit

	Examples:

	  ${script} /xCATjk/log/ubuntu16.04-ppc64el/8
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
	check_exec_or_exit awk sed tr date
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

#
# xcattestlog2sql
#
#       $1      The name of the test run
#       $2	Log file of xcattest
#
function xcattestlog2sql()
{
	local test_run_name="$1"
	local logfile="$2"

	local test_case_name=""
	local test_case_result=""
	local duration=""

	[ -n "${test_run_name}" ]
	warn_if_bad "$?" "test run has no name" || return 1

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	--
	-- Test run has the name '${test_run_name}'
	--

	EOF

	[ -f "${logfile}" ]
	warn_if_bad "$?" "${logfile}: no such log file" || return 1

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	--
	-- Analyzing file '${logfile}'
	--

	EOF

	while read -r test_case_name test_case_result duration
	do
		while read -r ; do echo "${REPLY}" ; done <<-EOF
		INSERT INTO TestCase (TestCaseId, TestCaseName)
		SELECT * FROM (SELECT NULL AS TestCaseId,
		    '${test_case_name}' AS TestCaseName) AS tmp
		WHERE NOT EXISTS (
		    SELECT TestCaseId FROM TestCase WHERE TestCaseName = '${test_case_name}'
		) LIMIT 1;

		INSERT INTO ResultDict (ResultId, ResultName)
		SELECT * FROM (SELECT NULL AS ResultId,
		    '${test_case_result}' AS ResultName) AS tmp
		WHERE NOT EXISTS (
		    SELECT ResultId FROM ResultDict WHERE ResultName = '${test_case_result}'
		) LIMIT 1;

		REPLACE INTO TestResult (TestRunId, TestCaseId, ResultId, DurationTime)
		SELECT (
		    SELECT TestRunId FROM TestRun WHERE TestRunName = '${test_run_name}'
		) AS TestRunId, (
		    SELECT TestCaseId FROM TestCase WHERE TestCaseName = '${test_case_name}'
		) AS TestCaseId, (
		    SELECT ResultId FROM ResultDict WHERE ResultName = '${test_case_result}'
		) AS ResultId, '${duration}';

		EOF
	done < <(tr -d '\r' <"${logfile}" | grep "^------END" |
		sed -e 's/^.*END::\(.*\)::\([A-Za-z0-9]*\)::.*Duration::\(-*[0-9]*\) sec.*$/\1 \2 \3/')

	return 0
}

#
# xcattestbundle2sql
#
#       $1      The name of the test run
#       $2	Bundle file of xcattest
#
function xcattestbundle2sql()
{
	local test_run_name="$1"
	local logfile="$2"

	local test_case_name=""
	local test_case_result="No run"

	[ -n "${test_run_name}" ]
	warn_if_bad "$?" "test run has no name" || return 1

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	--
	-- Test run has name '${test_run_name}'
	--

	EOF

	[ -f "${logfile}" ]
	warn_if_bad "$?" "${logfile}: no such log file" || return 1

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	--
	-- Analyzing file '${logfile}'
	--

	INSERT INTO ResultDict (ResultId, ResultName)
	SELECT * FROM (SELECT NULL AS ResultId,
	    '${test_case_result}' AS ResultName) AS tmp
	WHERE NOT EXISTS (
	    SELECT ResultId FROM ResultDict WHERE ResultName = '${test_case_result}'
	) LIMIT 1;

	EOF

	while read -r test_case_name
	do
		# Remove any comment
		test_case_name="${test_case_name%%#*}"
		# Chomp
		test_case_name=$(echo ${test_case_name})
		[ -z "${test_case_name}" ] && continue

		while read -r ; do echo "${REPLY}" ; done <<-EOF
		INSERT INTO TestCase (TestCaseId, TestCaseName)
		SELECT * FROM (SELECT NULL AS TestCaseId,
		    '${test_case_name}' AS TestCaseName) AS tmp
		WHERE NOT EXISTS (
		    SELECT TestCaseId FROM TestCase WHERE TestCaseName = '${test_case_name}'
		) LIMIT 1;

		INSERT IGNORE INTO TestResult (TestRunId, TestCaseId, ResultId, DurationTime)
		SELECT (
		    SELECT TestRunId FROM TestRun WHERE TestRunName = '${test_run_name}'
		) AS TestRunId, (
		    SELECT TestCaseId FROM TestCase WHERE TestCaseName = '${test_case_name}'
		) AS TestCaseId, (
		    SELECT ResultId FROM ResultDict WHERE ResultName = '${test_case_result}'
		) AS ResultId, '0';

		EOF
	done < <(tr -d '\r' <"${logfile}")
}

#
# jenkinsprojectlog2sql
#
#       $1	Log file of jenkins project run
#
#	When return 0, will set global shell variable TestRunName
#
function jenkinsprojectlog2sql()
{
	local logfile="$1"
	local foo=""

	local test_run_name=""
	local start_time=""
	local end_time=""
	local os=""
	local arch=""
	local xcat_version=""
	local xcat_release=""
	local build_datetime=""
	local build_commit_id=""
	local build_branch=""
	local build_machine=""
	local build_type=""
	local memo=""

	[ -f "${logfile}" ]
	warn_if_bad "$?" "${logfile}: no such log file" || return 1

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	--
	-- Analyzing file '${logfile}'
	--

	EOF

	test_run_name="$(tr -d '\r' <"${logfile}" |
		 awk '/project.*description/ { print $(NF - 1); exit }')"
	[ -n "${test_run_name}" ]
	warn_if_bad "$?" "${test_run_name}: fail to parse test run name" || return 1

	start_time="$(tr -d '\r' <"${logfile}" | head -n 1 | cut -d ' ' -f 1,2)"
        # Start time expected format YYYY-MM-DD HH:MM:SS
	[ "${#start_time}" = 19 ]
	warn_if_bad "$?" "${start_time}: fail to parse test start time" || return 1

	end_time="$(tr -d '\r' <"${logfile}" | tail -n 1 | cut -d ' ' -f 1,2)"
	# End time expected format YYYY-MM-DD HH:MM:SS
	[ "${#end_time}" = 19 ]
	warn_if_bad "$?" "${end_time}: fail to parse test end time" || return 1

	arch="$(tr -d '\r' <"${logfile}" |
		awk -F - '/project.*description/ { print $4; exit }')"
	# If arch is "ppc64el" change to "ppc64le" to be consistent with other formats
	[ "${arch}" = "ppc64el" ] && arch="ppc64le"
	# If arch is "alt" check the next field for actual arch
	[ "${arch}" = "alt" ] && arch="$(tr -d '\r' <"${logfile}" |
		awk -F - '/project.*description/ { print $5; exit }')"
	[ -n "${arch}" ]
	warn_if_bad "$?" "${arch}: fail to parse arch" || return 1

	os="$(tr -d '\r' <"${logfile}" | awk '/os.*=>/ { print $NF; exit }')"
	[ -n "${os}" ]
	warn_if_bad "$?" "${os}: fail to parse operating system" || return 1

	xcat_version="$(tr -d '\r' <"${logfile}" |
		awk '/version.*=>/ { print $NF; exit }')"
	xcat_release="$(tr -d '\r' <"${logfile}" |
		awk '/release.*=>/ { print $NF; exit }')"
	build_datetime="$(tr -d '\r' <"${logfile}" |
		awk '/build time.*=>/ { match($0, /=> +(.*)$/, a); print substr($0, a[1, "start"], a[1, "length"]); exit }')"
	build_commit_id="$(tr -d '\r' <"${logfile}" |
		awk '/commit number.*=>/ { print $NF; exit }')"
	build_branch="$(tr -d '\r' <"${logfile}" |
		awk '/xcatcore.*=>/ { match($0, /\/([^/]*)\/core-[a-z-]+\.tar\.bz2/, a); $branch = substr($0, a[1, "start"], a[1, "length"]); if ("devel" == $branch) $branch = "master"; print $branch; exit }')"
	build_machine="$(tr -d '\r' <"${logfile}" |
		awk '/build server.*=>/ { print $NF; exit }')"
	build_type="$(tr -d '\r' <"${logfile}" |
		awk '/xcatcore.*=>/ { match($0, /(deb|rpm)/, a); print substr($0, a[1, "start"], a[1, "length"]); exit }')"

	memo="$(tr -d '\r' <"${logfile}" | grep -A 7 'project.*description' | cut -d ' ' -f 4-)"

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	INSERT INTO ArchDict (ArchId, ArchName)
	SELECT * FROM (SELECT NULL AS ArchId,
	    '${arch}' AS ArchName) AS tmp
	WHERE NOT EXISTS (
	    SELECT ArchId FROM ArchDict WHERE ArchName = '${arch}'
	) LIMIT 1;

	INSERT INTO OSDict (OSId, OSName)
	SELECT * FROM (SELECT NULL AS OSId,
	    '${os}' AS OSName) AS tmp
	WHERE NOT EXISTS (
	    SELECT OSId FROM OSDict WHERE OSName = '${os}'
	) LIMIT 1;

	EOF

	if [ -n "${xcat_version}" -a -n "${xcat_release}" -a \
		-n "${build_datetime}" -a -n "${build_commit_id}" -a \
		-n "${build_machine}" -a -n "${build_type}" ]
	then
		while read -r ; do echo "${REPLY}" ; done <<-EOF
		INSERT INTO BuildDict (BuildId, BuildVersion, BuildRelease,
		    BuildDateTime, BuildCommitId, BuildBranch, BuildMachine, BuildType)
		SELECT * FROM (SELECT NULL AS BuildId,
		    '${xcat_version}' AS BuildVersion,
		    '${xcat_release}' AS BuildRelease,
		    '${build_datetime}' AS BuildDateTime,
		    '${build_commit_id}' AS BuildCommitId,
		    '${build_branch}' AS BuildBranch,
		    '${build_machine}' AS BuildMachine,
		    '${build_type}' AS BuildType
		) AS tmp
		WHERE NOT EXISTS (
		    SELECT BuildId FROM BuildDict WHERE BuildVersion = '${xcat_version}'
		        AND BuildRelease = '${xcat_release}'
		        AND BuildDateTime = '${build_datetime}'
		        AND BuildCommitId = '${build_commit_id}'
		        AND BuildMachine = '${build_machine}'
		        AND BuildType = '${build_type}'
		) LIMIT 1;

		EOF
	else
		warn_if_bad 1 "${logfile}: xcat build information not available"
		while read -r ; do echo "${REPLY}" ; done <<-EOF
		-- xCAT build information not available

		EOF
	fi

	while read -r ; do echo "${REPLY}" ; done <<-EOF
	INSERT IGNORE INTO TestRun
	    (TestRunId, TestRunName, StartTime, EndTime, ArchId, OSId, BuildId, Memo)
	SELECT NULL, '${test_run_name}', '${start_time}', '${end_time}', (
	    SELECT ArchId FROM ArchDict WHERE ArchName = '${arch}'
	) AS ArchId, (
	    SELECT OSId FROM OSDict WHERE OSName = '${os}'
	) AS OSId, (
	    SELECT BuildId FROM BuildDict WHERE BuildVersion = '${xcat_version}'
	        AND BuildRelease = '${xcat_release}'
	        AND BuildDateTime = '${build_datetime}'
	        AND BuildCommitId = '${build_commit_id}'
	        AND BuildMachine = '${build_machine}'
	        AND BuildType = '${build_type}'
	) AS BuildId, '${memo}';

	EOF

	TestRunName="${test_run_name}"

	return 0
}

# Main

declare VERSION="1.0.1"

declare xCATjkLog_DIR=""
declare TestRunName=""

declare JenkinsProjectLog=""
declare xCATTestLogs=""

while [ "$#" -gt "0" ]
do
	case "$1" in
	"--help")
		usage
		exit 0
		;;
	*)
		[ "$1" == "--" ] && shift
		[ -z "${xCATjkLog_DIR}" ]
		exit_if_bad "$?" "invalid predicate - $1"
		xCATjkLog_DIR="$1"
		;;
	esac
	shift
done

[ -z "${xCATjkLog_DIR}" ] && usage >&2 && exit 1

[ -d "${xCATjkLog_DIR}" ]
exit_if_bad "$?" "${xCATjkLog_DIR}: no such directory"

# Check if the mail log is there. If it is not, exit directly
JenkinsMailLog="$(echo "${xCATjkLog_DIR}/mail."*)"
[ -f "${JenkinsMailLog}" ]
exit_if_bad "$?" "${JenkinsMailLog}: no such log file"

while read -r ; do echo "${REPLY}" ; done <<EOF
-- xCATjkLog2SQL - version ${VERSION}
--
-- Run on host ${HOSTNAME}
-- Database: xCATjkLogAnalyzer
-- ------------------------------------------------------
-- Log directory    '${xCATjkLog_DIR}'

EOF

JenkinsProjectLog="$(echo "${xCATjkLog_DIR}/log."*)"
jenkinsprojectlog2sql "${JenkinsProjectLog}"
exit_if_bad "$?" "${JenkinsProjectLog}: parse error"

xCATTestBundle="$(echo "${xCATjkLog_DIR}/"*".bundle")"
xcattestbundle2sql "${TestRunName}" "${xCATTestBundle}"
warn_if_bad "$?" "${xCATTestBundle}: parse error"

for xCATTestLog in "${xCATjkLog_DIR}/xcattest.log."*
do
	xcattestlog2sql "${TestRunName}" "${xCATTestLog}"
	warn_if_bad "$?" "${xCATTestLog}: parse error"
done

while read -r ; do echo "${REPLY}" ; done <<EOF
-- Log files parsing completed on $(date "+%Y-%m-%d %H:%M:%S %z")
EOF

exit 0
