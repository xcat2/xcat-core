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

# The configuration part

MYSQL_HOST="localhost"
MYSQL_USER="root"
MYSQL_PASS="password"
MYSQL_DB="xCATjkLogAnalyzer"

# The main part

for c in mysql tail sed grep
do
	! type "${c}" >/dev/null 2>&1 &&
		echo "Command \"${c}\" not found" >&2 && exit 1
done

Email report

$report_setTo      "Alice"            alice@example.org

$report_setFrom    "xCAT Jenkins Mail Bot"  root@localhost.localdomain

DateTime="$(date -R)"

MYSQL_COMMAND=("mysql" "-h" "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASS}" "${MYSQL_DB}")
Subject="$("${MYSQL_COMMAND[@]}" <<<"SELECT CONCAT('Passed: ', SUM(Passed), ' Failed: ', SUM(Failed), ' No run: ', SUM(\`No run\`)) AS Summary FROM LatestDailyReport;" | tail -n 1)"

$report_setSubject "[xCAT Jenkins] ${Subject}"

$report_setHTML <<-EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta name="viewpoint" content="width=device-width, initial-scale=1.0" />
<title>xCATjk Test Report</title>
</head>
<body style="font-weight: 500; font-size: 10.5pt; font-family: Helvetica, Arial, sans-serif; text-align: center;">
<table style="border-collapse: collapse; border-style: none; border-width: 0; margin: auto; text-align: left; width: 680px;">
<tr style="vertical-align: baseline;">
<td style="padding: 2px 3px; vertical-align: top; width: 540px;"><p style="font-weight: 900; font-size: 16pt;">xCATjk Test Report</p></td>
<td style="padding: 2px 3px; text-align: right"><img src="data:image/png;base64,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" alt="xCAT Logo" title="xCAT Logo" style="border-style: none; border-width: 0;" width="120" height="90" /></td>
</tr>
</table>
<p style="font-size: 12pt; font-weight: 700; text-align: center;"></p>
<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px">Duration</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>
</tr>
$(
LatestDailyReport="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT Title, Arch, OS, Duration, Passed, Failed, \`No run\`, Subtotal, \`Pass rate\` FROM LatestDailyReport;")"
oIFS="${IFS}"
IFS="|"
color=""
while read n title arch os duration passed failed no_run subtotal pass_rate n
do
	[ "${color}" = "#e0e0e0" ] && color="#a0d0ff" || color="#e0e0e0"
	echo "<tr style=\"background-color: ${color}; vertical-align: baseline;\" title=\"${title}\">"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${arch}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${os}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${duration}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${subtotal}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
	echo "</tr>"
done < <(grep -v -- ---- <<<"${LatestDailyReport}" | sed -e '1d' -e 's/ *| */|/g')
IFS="${oIFS}"

LatestDailyReportSummary="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT SEC_TO_TIME(SUM(TIME_TO_SEC(Duration))) AS Duration, SUM(Passed), SUM(Failed), SUM(\`No run\`), SUM(Subtotal), IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A') AS \`Pass rate\` FROM LatestDailyReport;")"
oIFS="${IFS}"
IFS="|"
read n duration passed failed no_run total pass_rate n < <(grep -v -- ---- <<<"${LatestDailyReportSummary}" | sed -e '1d' -e 's/ *| */|/g')
echo "<tr style=\"background-color: #cccccc; vertical-align: baseline;\">"
echo "<th style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">Total</th>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">-</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${duration}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${total}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
echo "</tr>"
IFS="${oIFS}"
)
</table>
<hr style="background-color: #cccccc; border-width: 0; box-shadow: 1px 2px 3px #cccccc; height: 1px; width: 680px;" />
<p style="font-size: 12pt; font-weight: 700; text-align: center;">Failed Test Cases</p>
<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px;">Arch</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Failed test cases</th>
</tr>
$(
FailedTestCasesReport="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT Title, Arch, OS, \`Failed test cases\` FROM LatestDailyReport;")"
oIFS="${IFS}"
IFS="|"
color=""
while read n title arch os failed_test_cases n
do
	[ "${color}" = "#e0e0e0" ] && color="#a0d0ff" || color="#e0e0e0"
	[ "${color}" = "#e0e0e0" ] && color2="#f0f0f0" || color2="#d0e8ff"
	echo "<tr style=\"background-color: ${color}; vertical-align: baseline;\" title=\"${title}\">"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${arch}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${os}</td>"
	echo "<td style=\"background-color: ${color2}; border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${failed_test_cases}</td>"
	echo "</tr>"
done < <(grep -v -- ---- <<<"${FailedTestCasesReport}" | sed -e '1d' -e 's/ *| */|/g')
)
</table>
<p style="font-size: 12pt; font-weight: 700; text-align: center;">Seven-day Look Back</p>
<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px;">Test runs</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>
</tr>
$(
SevenDayLookBack="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT Arch, OS, \`Test runs\`, Passed, Failed, \`No run\`, Subtotal, \`Pass rate\` FROM SevenDayLookBack;")"
oIFS="${IFS}"
IFS="|"
color=""
while read n arch os test_runs passed failed no_run subtotal pass_rate n
do
	[ "${color}" = "#e0e0e0" ] && color="#a0d0ff" || color="#e0e0e0"
	echo "<tr style=\"background-color: ${color}; vertical-align: baseline;\" title=\"${title}\">"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${arch}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${os}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${test_runs}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${subtotal}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
	echo "</tr>"
done < <(grep -v -- ---- <<<"${SevenDayLookBack}" | sed -e '1d' -e 's/ *| */|/g')
IFS="${oIFS}"

SevenDayLookBackSummary="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT SUM(\`Test runs\`), SUM(Passed), SUM(Failed), SUM(\`No run\`), SUM(Subtotal), IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A') AS \`Pass rate\` FROM SevenDayLookBack;")"
oIFS="${IFS}"
IFS="|"
read n test_runs passed failed no_run total pass_rate n < <(grep -v -- ---- <<<"${SevenDayLookBackSummary}" | sed -e '1d' -e 's/ *| */|/g')
echo "<tr style=\"background-color: #cccccc; vertical-align: baseline;\">"
echo "<th style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">Total</th>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">-</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${test_runs}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${total}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
echo "</tr>"
IFS="${oIFS}"
)
</table>
<p style="font-size: 12pt; font-weight: 700; text-align: center;">Thirty-day Look Back</p>
<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px;">Test runs</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>
</tr>
$(
ThirtyDayLookBack="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT Arch, OS, \`Test runs\`, Passed, Failed, \`No run\`, Subtotal, \`Pass rate\` FROM ThirtyDayLookBack;")"
oIFS="${IFS}"
IFS="|"
color=""
while read n arch os test_runs passed failed no_run subtotal pass_rate n
do
	[ "${color}" = "#e0e0e0" ] && color="#a0d0ff" || color="#e0e0e0"
	echo "<tr style=\"background-color: ${color}; vertical-align: baseline;\" title=\"${title}\">"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${arch}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${os}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${test_runs}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${subtotal}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
	echo "</tr>"
done < <(grep -v -- ---- <<<"${ThirtyDayLookBack}" | sed -e '1d' -e 's/ *| */|/g')
IFS="${oIFS}"

ThirtyDayLookBackSummary="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT SUM(\`Test runs\`), SUM(Passed), SUM(Failed), SUM(\`No run\`), SUM(Subtotal), IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A') AS \`Pass rate\` FROM ThirtyDayLookBack;")"
oIFS="${IFS}"
IFS="|"
read n test_runs passed failed no_run total pass_rate n < <(grep -v -- ---- <<<"${ThirtyDayLookBackSummary}" | sed -e '1d' -e 's/ *| */|/g')
echo "<tr style=\"background-color: #cccccc; vertical-align: baseline;\">"
echo "<th style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">Total</th>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">-</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${test_runs}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${total}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
echo "</tr>"
IFS="${oIFS}"
)
</table>
<p style="font-size: 12pt; font-weight: 700; text-align: center;">Ninety-day Look Back</p>
<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px;">Test runs</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>
</tr>
$(
NinetyDayLookBack="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT Arch, OS, \`Test runs\`, Passed, Failed, \`No run\`, Subtotal, \`Pass rate\` FROM NinetyDayLookBack;")"
oIFS="${IFS}"
IFS="|"
color=""
while read n arch os test_runs passed failed no_run subtotal pass_rate n
do
	[ "${color}" = "#e0e0e0" ] && color="#a0d0ff" || color="#e0e0e0"
	echo "<tr style=\"background-color: ${color}; vertical-align: baseline;\" title=\"${title}\">"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${arch}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${os}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${test_runs}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${subtotal}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
	echo "</tr>"
done < <(grep -v -- ---- <<<"${NinetyDayLookBack}" | sed -e '1d' -e 's/ *| */|/g')
IFS="${oIFS}"

NinetyDayLookBackSummary="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT SUM(\`Test runs\`), SUM(Passed), SUM(Failed), SUM(\`No run\`), SUM(Subtotal), IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A') AS \`Pass rate\` FROM NinetyDayLookBack;")"
oIFS="${IFS}"
IFS="|"
read n test_runs passed failed no_run total pass_rate n < <(grep -v -- ---- <<<"${NinetyDayLookBackSummary}" | sed -e '1d' -e 's/ *| */|/g')
echo "<tr style=\"background-color: #cccccc; vertical-align: baseline;\">"
echo "<th style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">Total</th>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">-</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${test_runs}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${passed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${failed}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${no_run}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${total}</td>"
echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${pass_rate}</td>"
echo "</tr>"
IFS="${oIFS}"
)
</table>
<p style="font-size: 12pt; font-weight: 700; text-align: center;">Top 50 Failed Test Cases</p>
<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 40px;">Rank</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Test case</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 50px;">Last 7 days</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 50px;">Last 30 days</th>
<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 50px;">Last 90 days</th>
</tr>
$(
Top50FailedTestCases="$("${MYSQL_COMMAND[@]}" -t <<<"SELECT @rank := @rank + 1 AS Rank, \`Test case\`, Arch, OS, \`Last seven days\`, \`Last thirty days\`, \`Last ninety days\` FROM FailedTestCasesTopList, (SELECT @rank := 0) AS RANK LIMIT 50;")"
oIFS="${IFS}"
IFS="|"
color=""
while read n rank test_case arch os last_seven_days last_thirty_days last_ninety_days n
do
	[ "${color}" = "#e0e0e0" ] && color="#a0d0ff" || color="#e0e0e0"
	[ "${color}" = "#e0e0e0" ] && color2="#f0f0f0" || color2="#d0e8ff"
	echo "<tr style=\"background-color: ${color2}; vertical-align: baseline;\">"
	echo "<td style=\"background-color: ${color}; border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${rank}</td>"
	echo "<td style=\"background-color: ${color}; border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${test_case}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${arch}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;\">${os}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${last_seven_days}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${last_thirty_days}</td>"
	echo "<td style=\"border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">${last_ninety_days}</td>"
	echo "</tr>"
done < <(grep -v -- ---- <<<"${Top50FailedTestCases}" | sed -e '1d' -e 's/ *| */|/g')
IFS="${oIFS}"
)
</table>
<hr style="background-color: #cccccc; border-width: 0; box-shadow: 1px 2px 3px #cccccc; height: 1px; width: 680px;" />
<table style="border-collapse: collapse; border-color: #666666; border-style: solid; border-width: 1px; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">
<tr style="background-color: #e0e0e0; vertical-align: baseline;">
<td style="padding: 4px 5px; vertical-align: bottom;"><p style="font-size: 9pt;"><sup>&#x273b;</sup>This email has been sent to you by xCATjk Mail Bot.<br />
<sup>&#x2020;</sup>This email was sent from a notification-only address that cannot accept incoming email. Please do not reply to this message. If you have received this email in error, please delete it.<br />
<sup>&#x2021;</sup>All the times shown in this test report are the local times of the testing environment.</p>
<p style="font-size: 9pt;">${DateTime}</p></td>
</tr>
</table>
</body>
</html>
EOF

$report_send
