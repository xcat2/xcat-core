#!/bin/bash

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

! source "${BASE_DIR}/email.sh" >/dev/null 2>&1 &&
	echo "File \"${BASE_DIR}/email.sh\" not found" >&2 && exit 1
! type mysql >/dev/null 2>&1 &&
	echo "Command \"mysql\" not found" >&2 && exit 1

# The configuration part

MYSQL_HOST="localhost"
MYSQL_USER="root"
MYSQL_PASS="password"
MYSQL_DB="xCATjkLogAnalyzer"

MYSQL_COMMAND=("mysql" -B -N -r -s "-h" "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASS}" "${MYSQL_DB}")

# The main part

Email report

$report_setTo      "Alice"            alice@example.org

$report_setFrom    "xCAT Jenkins Mail Bot"    root@localhost.localdomain

$report_setSubject "$("${MYSQL_COMMAND[@]}" <<<"SELECT * FROM LatestDailyMailReportSubject;")"
$report_setHTML < <("${MYSQL_COMMAND[@]}" <<<"CALL CreateLatestDailyMailReport;")

$report_send
