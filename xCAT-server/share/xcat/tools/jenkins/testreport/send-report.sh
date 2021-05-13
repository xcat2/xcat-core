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
MYSQL_PASS="xxxxxxx"
MYSQL_DB="xCATjkLogAnalyzer"

MYSQL_COMMAND=("mysql" -B -N -r -s "-h" "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASS}" "${MYSQL_DB}")

# The main part

Email report

$report_setTo      "Peter Wong"     wpeter@us.ibm.com
$report_setTo      "Mark Gurevich"  gurevich@us.ibm.com
$report_setTo      "Nathan Besaw"   besawn@us.ibm.com

$report_setReplyTo "Nathan Besaw"   besawn@us.ibm.com

$report_setFrom    "xCAT Jenkins Mail Bot"    root@c910f03c17k07.pok.stglabs.ibm.com

HTML_REPORT="/tmp/xcat-jenkins-mail-report-$$.html"

"${MYSQL_COMMAND[@]}" <<<"CALL CreateLatestDailyMailReportV2;" |
	"${BASE_DIR}/git-log-report.sh" >"${HTML_REPORT}"

$report_setText < <(elinks -dump --dump-width 78 "${HTML_REPORT}")
$report_setHTML <"${HTML_REPORT}"

rm -f "${HTML_REPORT}"

REPORT_SUBJECT="$("${MYSQL_COMMAND[@]}" <<<"SELECT * FROM LatestDailyMailReportSubjectV2;")"
if [[ ${REPORT_SUBJECT} =~ 'Failed: 0 No run: 0' ]]
then
	REPORT_SUBJECT=$'\xf0'$'\x9f'$'\x98'$'\xb9'" ${REPORT_SUBJECT} [xCAT Jenkins]"
else
	REPORT_SUBJECT=$'\xf0'$'\x9f'$'\x98'$'\xbe'" ${REPORT_SUBJECT} [xCAT Jenkins]"
fi

$report_setSubject "${REPORT_SUBJECT}"

$report_send

unset ${!report_@}
