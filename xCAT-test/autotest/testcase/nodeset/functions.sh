#!/bin/bash

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

#
# internal_setup        Script setup
#
#       Returns 0 on success.
#       Exits (not returns) with 1 on failure.
#
function internal_setup()
{
	shopt -s extglob

	# Trap exit for internal_cleanup function.
	trap "internal_cleanup" EXIT

	umask 0077

	TMP_DIR="$(mktemp -d "/tmp/${0##*/}.XXXXXXXX" 2>/dev/null)"
	[ -d "${TMP_DIR}" ]
	exit_if_bad "$?" "Make temporary directory failed."

	custom_setup
}

#
# internal_cleanup      Script cleanup (reached via trap 0)
#
#       Destory any temporarily facility created by internal_setup.
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
	:
}

#
# custom_cleanup
#
function custom_cleanup()
{
	:
}

internal_setup

function make_bogus_grub2_nodes()
{
	local i
	# grub2
	for i in {001..005}
	do
		mkdef -t node -o tz${i} \
			arch=ppc64 cons=hmc groups=lpar mgt=hmc \
			netboot=grub2 \
			ip=10.99.1.$((10#${i})) \
			mac=e6:d4:d2:3a:ad:0$((10#${i})) \
			profile=compute os=rhels7.99
	done
}

function make_bogus_petitboot_nodes()
{
	local i
	# petitboot
	for i in {001..005}
	do
		mkdef -t node -o tz${i} \
			arch=ppc64le cons=bmc groups=ipmi mgt=ipmi \
			netboot=petitboot \
			ip=10.99.1.$((10#${i})) \
			mac=e6:d4:d2:3a:ad:0$((10#${i})) \
			profile=compute os=rhels7.99
	done
}

function make_bogus_xnba_nodes()
{
	local i
	# xnba
	for i in {001..005}
	do
		mkdef -t node -o tz${i} \
			arch=x86_64 cons=kvm groups=kvm mgt=kvm \
			netboot=xnba \
			ip=10.99.1.$((10#${i})) \
			mac=e6:d4:d2:3a:ad:0$((10#${i})) \
			profile=compute os=rhels7.99
	done
}

function destory_bogus_nodes()
{
	rmdef -t node tz001+4
}

umask 0022

function make_bogus_ppc64le_osimage()
{
	mkdef "rhels7.99-ppc64le-install-compute" \
		-u profile=compute provmethod=install \
		osvers=rhels7.99 osarch=ppc64le
	mkdir -p /install/rhels7.99/ppc64le/ppc/ppc64le
	echo blah >/install/rhels7.99/ppc64le/ppc/ppc64le/vmlinuz
	echo blah >/install/rhels7.99/ppc64le/ppc/ppc64le/initrd.img
}

function make_bogus_ppc64_osimage()
{
	mkdef "rhels7.99-ppc64-install-compute" \
		-u profile=compute provmethod=install \
		osvers=rhels7.99 osarch=ppc64
	mkdir -p /install/rhels7.99/ppc64/ppc/ppc64
	echo blah >/install/rhels7.99/ppc64/ppc/ppc64/vmlinuz
	echo blah >/install/rhels7.99/ppc64/ppc/ppc64/initrd.img
}

#function make_bogus_ppc64_osimage()
#{
#	mkdef "rhels6.99-ppc64-install-compute" \
#		-u profile=compute provmethod=install \
#		osvers=rhels6.99 osarch=ppc64
#	mkdir -p /install/rhels6.99/ppc64/ppc/{chrp,ppc64}
#	echo blah >/install/rhels6.99/ppc64/ppc/ppc64/vmlinuz
#	echo blah >/install/rhels6.99/ppc64/ppc/ppc64/initrd.img
#	echo blah >/install/rhels6.99/ppc64/ppc/chrp/yaboot
#}

function make_bogus_x64_osimage()
{
	mkdef "rhels6.99-x86_64-install-compute" \
		-u profile=compute provmethod=install \
		osvers=rhels6.99 osarch=x86_64
	mkdir -p /install/rhels6.99/x86_64/images/pxeboot
	echo blah >/install/rhels6.99/x86_64/images/pxeboot/vmlinuz
	echo blah >/install/rhels6.99/x86_64/images/pxeboot/initrd.img
}

function destory_bogus_osimages()
{
	local o
	for o in \
		rhels7.99-ppc64le-install-compute \
		rhels7.99-ppc64-install-compute \
		rhels6.99-ppc64-install-compute \
		rhels6.99-x86_64-install-compute
	do
		rmdef -t osimage ${o}
	done
}
