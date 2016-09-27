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

SQLofCreateTables="${BASE_DIR}/xCATjkLogAnalyzer.sql"
if [ ! -f "${SQLofCreateTables}" ]
then
	echo "${SQLofCreateTables}: SQL file not found" >&2
	exit 1
fi


xCATjkScanLogs="${BASE_DIR}/xcatjk-scanlogs.sh"
if [ ! -x "${xCATjkScanLogs}" ]
then
	echo "Script ${xCATjkScanLogs} not found" >&2
	exit 1
fi

while read -r ; do echo "${REPLY}" ; done <<EOF
-- xCATjkLogs redo everything
--
-- Run on host ${HOSTNAME}
-- ------------------------------------------------------

EOF

while read -r ; do echo "${REPLY}" ; done <"${SQLofCreateTables}"

"${xCATjkScanLogs}" /xCATjk/log
