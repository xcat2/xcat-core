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

xCATjkScanLogs="${BASE_DIR}/xcatjk-scanlogs.sh"
if [ ! -x "${xCATjkScanLogs}" ]
then
	echo "Script ${xCATjkScanLogs} not found" >&2
	exit 1
fi

while read -r ; do echo "${REPLY}" ; done <<EOF
-- xCATjkLogs scan last three days
--
-- Run on host ${HOSTNAME}
-- ------------------------------------------------------

EOF

"${xCATjkScanLogs}" --recent /xCATjk/log
