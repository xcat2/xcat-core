#!/bin/bash

#
# Author:   GONG Jie <gongjie@linux.vnet.ibm.com>
# Create:   2016-05-27
# Update:   2016-06-07
# Version:  0.99
#
# EXAMPLE
#   #!/bin/bash
#
#   source /path/to/email.sh
#
#   Email report
#
#   $report_setTo bob@example.org
#   $report_setTo charlie@example.org
#   $report_setTo Dave dave@example.org
#   $report_setCc trent@example.org
#   $report_setBcc eve@example.org
#   $report_setFrom Alice alice@example.org
#   $report_setSubject "A Sample Email Report"
#
#   $report_setText <<-EOF
#   	Blah blah blah...
#   EOF
#
#   $report_addAttachmentFile /path/to/doc/document-a4.pdf
#   $report_addAttachmentFile /path/to/doc/onepage-a4.pdf
#
#   $report_send
#
# SEE ALSO
#    RFC 2045, RFC 2046, RFC 2047, RFC 2822, RFC 5322, RFC 5321
#

function Email()
{
	local base="${FUNCNAME}"
	local this="$1"

	! type base64 >/dev/null 2>&1 &&
		echo "${c}: command not found" >&2 &&
		return 1

	declare -g base64_encode=base64

	[[ "$(base64 --help)" =~ GNU ]] &&
		declare -g base64_encode="base64 -w 0"

	declare -g ${this}_mailTo=""
	declare -g ${this}_mailCc=""
	declare -g ${this}_mailBcc=""
	declare -g ${this}_mailFrom=""
	declare -g ${this}_mailReplyTo=""
	declare -g ${this}_mailSubject=""
	declare -g -a ${this}_mailAttachmentContentTypes
	declare -g -a ${this}_mailAttachmentMessages
	declare -g -a ${this}_mailAttachmentNames

	eval "${this}_mailAttachmentContentTypes=()"
	eval "${this}_mailAttachmentMessages=()"
	eval "${this}_mailAttachmentNames=()"

	local method

	for method in $(compgen -A function "${base}_")
	do
		declare -g ${method/#$base\_/$this\_}="${method} ${this}"
	done
}

function Email_setTo()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inName=""
	[ -n "$3" ] && inName="$2" && shift
	local inAddress="$2"

	local mailTo="${this}_mailTo"

	# The format of Email address,
	# see RFC 5322, sections 3.2.3 and 3.4.1, and RFC 5321

	[[ "${inAddress}" =~ ^[0-9A-Za-z._%+-]+@([0-9A-Za-z][0-9A-Za-z-]+\.)+[A-Za-z]{2,3}$ ]] ||
		return 1
	[ -n "${!mailTo}" ] && declare -g ${mailTo}+=","$'\n'" "
	[ -n "${inName}" ] &&
		declare -g ${mailTo}+="=?UTF-8?B?$(echo -n "${inName}" |
			${base64_encode})?="$'\n'" <${inAddress}>" ||
		declare -g ${mailTo}+="${inAddress}"

	return 0
}

function Email_setCc()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inName=""
	[ -n "$3" ] && inName="$2" && shift
	local inAddress="$2"

	local mailCc="${this}_mailCc"

	[[ "${inAddress}" =~ ^[0-9A-Za-z._%+-]+@([0-9A-Za-z][0-9A-Za-z-]+\.)+[A-Za-z]{2,3}$ ]] ||
		return 1
	[ -n "${!mailCc}" ] && declare -g ${mailCc}+=","$'\n'" "
	[ -n "${inName}" ] &&
		declare -g ${mailCc}+="=?UTF-8?B?$(echo -n "${inName}" |
			${base64_encode})?="$'\n'" <${inAddress}>" ||
		declare -g ${mailCc}+="${inAddress}"

	return 0
}

function Email_setBcc()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inName=""
	[ -n "$3" ] && inName="$2" && shift
	local inAddress="$2"

	local mailBcc="${this}_mailBcc"

	[[ "${inAddress}" =~ ^[0-9A-Za-z._%+-]+@([0-9A-Za-z][0-9A-Za-z-]+\.)+[A-Za-z]{2,3}$ ]] ||
		return 1
	[ -n "${!mailBcc}" ] && declare -g ${mailBcc}+=","$'\n'" "
	[ -n "${inName}" ] &&
		declare -g ${mailBcc}+="=?UTF-8?B?$(echo -n "${inName}" |
			${base64_encode})?="$'\n'" <${inAddress}>" ||
		declare -g ${mailBcc}+="${inAddress}"

	return 0
}

function Email_setFrom()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inName=""
	[ -n "$3" ] && inName="$2" && shift
	local inAddress="$2"

	local mailFrom="${this}_mailFrom"

	[[ "${inAddress}" =~ ^[0-9A-Za-z._%+-]+@([0-9A-Za-z][0-9A-Za-z-]+\.)+[A-Za-z]{2,3}$ ]] ||
		return 1
	[ -n "${inName}" ] &&
		declare -g ${mailFrom}="=?UTF-8?B?$(echo -n "${inName}" |
			 ${base64_encode})?="$'\n'" <${inAddress}>" ||
		declare -g ${mailFrom}="${inAddress}"

	return 0
}

function Email_setReplyTo()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inName=""
	[ -n "$3" ] && inName="$2" && shift
	local inAddress="$2"

	local mailReplyTo="${this}_mailReplyTo"

	[[ "${inAddress}" =~ ^[0-9A-Za-z._%+-]+@([0-9A-Za-z][0-9A-Za-z-]+\.)+[A-Za-z]{2,3}$ ]] ||
		return 1
	[ -n "${inName}" ] &&
		declare -g ${mailReplyTo}="=?UTF-8?B?$(echo -n "${inName}" |
			${base64_encode})?="$'\n'" <${inAddress}>" ||
		declare -g ${mailReplyTo}="${inAddress}"

	return 0
}

function Email_setSubject()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inSubject="$2"

	local mailSubject="${this}_mailSubject"

	local oLANG="${LANG}"
	LANG=C

	[[ "${#inSubject}" -le 66 && "${inSubject}" =~ ^[0-9A-Za-z\ ._/=+-]+$ ]] &&
		declare -g ${mailSubject}="${inSubject}" &&
		return 0

	# See RFC 5355

	declare -g ${mailSubject}="=?UTF-8?B?"

	local c=""
	local w=""
	local -i limit=39

	while :
	do
		read -n 1
		[[ -z "${REPLY}" || "${REPLY}" =~ [\x00-\x7f\xc0-\xff] ]] &&
			(( ${#w} + ${#c} > limit )) &&
			declare -g ${mailSubject}+="$(echo -n "${w}" |
				${base64_encode})?="$'\n'" =?UTF-8?B?" &&
			w="" && limit=45
			w+="${c}" && c=""
		[ -n "${REPLY}" ] && c+="${REPLY}" || break
	done < <(echo -n "${inSubject}")
	declare -g ${mailSubject}+="$(echo -n "${w}" | ${base64_encode})?="

	LANG="${oLANG}"

	return 0
}

function Email_setText()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"

	Email_addAttachment "${this}" "" "text/plain; charset=UTF-8"
}

function Email_setHTML()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"

	Email_addAttachment "${this}" "" "text/html; charset=UTF-8"
}

function Email_addAttachment()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inName="$2"
	local inContentType="$3"
	local inMessage=""

	# 76 is a magic number, see RFC 2045

	while read -n 76
	do
		inMessage+="${REPLY}"
		inMessage+=$'\n'
	done < <(${base64_encode} && echo)

	local mailAttachmentContentTypes="${this}_mailAttachmentContentTypes"
	local mailAttachmentMessages="${this}_mailAttachmentMessages"
	local mailAttachmentNames="${this}_mailAttachmentNames"

	eval "${mailAttachmentContentTypes}+=(\"${inContentType}\")"
	eval "${mailAttachmentMessages}+=(\"${inMessage}\")"
	eval "${mailAttachmentNames}+=(\"${inName}\")"
}

function Email_addAttachmentFile()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"
	local inFileName="$2"

	[ -f "${inFileName}" ] || return 1
	[ -r "${inFileName}" ] || return 1

	local inContentType=""

	# These are magic strings, see RFC 2046

	case "${inFileName##*.}" in
	"7z")	inContentType="application/x-7z-compressed" ;;
	"bz"|"bz2")
		inContentType="application/x-bzip2" ;;
	"bpg")	inContentType="image/bpg" ;;
	"cpio")	inContentType="application/x-cpio" ;;
	"gif")	inContentType="image/gif" ;;
	"gz")	inContentType="application/x-gzip" ;;
	"htm"|"html")
		inContentType="text/html" ;;
	"jpe"|"jpeg"|"jpg")
		inContentType="image/jpeg" ;;
	"png")	inContentType="image/png" ;;
	"rar")	inContentType="application/x-rar-compressed" ;;
	"tar")	inContentType="application/x-tar" ;;
	"txt")	inContentType="text/plain" ;;
	"xz")	inContentType="application/x-xz" ;;
	"zip")	inContentType="application/x-zip-compressed" ;;
	*)	inContentType="application/octet-stream" ;;
	esac

	Email_addAttachment "${this}" "${inFileName##*/}" "${inContentType}" <"${inFileName}"
}

function Email_send()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"

	local mailTo="${this}_mailTo"
	local mailCc="${this}_mailCc"
	local mailBcc="${this}_mailBcc"
	local mailFrom="${this}_mailFrom"
	local mailReplyTo="${this}_mailReplyTo"
	local mailSubject="${this}_mailSubject"

	# Sendmail is here, see Linux Standard Base Core Specification
	# - Generic 5.0 Edition, section 17.2

	local SENDMAIL="/usr/sbin/sendmail"

	! type "${SENDMAIL}" >/dev/null 2>&1 &&
		echo "${SENDMAIL}: command not found" >&2 &&
		return 1

	# Email headers, see RFC 2076

	"${SENDMAIL}" -t -i <<-EOF
	To: ${!mailTo}
	Cc: ${!mailCc}
	Bcc: ${!mailBcc}
	From: ${!mailFrom}
	Reply-To: ${!mailReplyTo}
	Subject: ${!mailSubject}
	X-Mailer: Flying Nimbus 0.0.1
	MIME-Version: 1.0
	$(Email_buildMultipart "${this}")
	EOF
}

function Email_buildMultipart()
{
	local base="${FUNCNAME%%_*}"
	local this="$1"

	local mailAttachmentContentTypes="${this}_mailAttachmentContentTypes"
	local mailAttachmentMessages="${this}_mailAttachmentMessages"
	local mailAttachmentNames="${this}_mailAttachmentNames"

	local boundary="-=0xdeadbeef${RANDOM}${RANDOM}=-"

	# See RFC 2046, section 5.1.3

	echo "Content-Type: multipart/mixed; boundary=0__${boundary}"
	echo
	echo "This is a message with multiple parts in MIME format."
	echo "--0__${boundary}"

	local -i i

	# See RFC 2046, section 5.1.4

	echo "Content-Type: multipart/alternative; boundary=1__${boundary}"
	echo
	echo -n "--1__${boundary}"
	for (( i = 0; i < $(eval "echo \"\${#${mailAttachmentNames}[@]}\""); ++i ))
	do
		local mailAttachmentContentType="${mailAttachmentContentTypes}[${i}]"
		local mailAttachmentMessage="${mailAttachmentMessages}[${i}]"
		local mailAttachmentName="${mailAttachmentNames}[${i}]"

		[ -n "${!mailAttachmentName}" ] && continue

		echo
		echo "Content-Type: ${!mailAttachmentContentType}"
		echo "Content-Disposition: inline"
		echo "Content-Transfer-Encoding: base64"
		echo
		echo "${!mailAttachmentMessage}"
		echo
		echo -n "--1__${boundary}"
	done
	echo "--"
	echo -n "--0__${boundary}"

	for (( i = 0; i < $(eval "echo \"\${#${mailAttachmentNames}[@]}\""); ++i ))
	do
		local mailAttachmentContentType="${mailAttachmentContentTypes}[${i}]"
		local mailAttachmentMessage="${mailAttachmentMessages}[${i}]"
		local mailAttachmentName="${mailAttachmentNames}[${i}]"

		[ -z "${!mailAttachmentName}" ] && continue

		echo
		echo "Content-Type: ${!mailAttachmentContentType}; name=\"${!mailAttachmentName}\""
		echo "Content-Disposition: attachment; filename=${!mailAttachmentName}"
		echo "Content-Transfer-Encoding: base64"
		echo
		echo "${!mailAttachmentMessage}"
		echo
		echo -n "--0__${boundary}"
	done
	echo "--"
}
# End of file
