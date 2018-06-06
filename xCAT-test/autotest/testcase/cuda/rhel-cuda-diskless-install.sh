#!/bin/bash

########
# Set all the variables below

LINUX_DISTRO="rhels7.5-alternate"
LINUX_ARCH="ppc64le"

COMPUTE_NODE="c910f03c01p10"
SOURCE_DIR="/install/tmp"

########

# $SOURCE_DIR is a directory this test case will be searched for.
# Files with the name looked like the following will be searched.
#
# -rw-r--r-- 1 nobody nobody  124064759 Jun 28 16:58 cuda-repo-rhel7-8-0-local-cublas-performance-update-8.0.61-1.ppc64le.rpm
# -rw-r--r-- 1 nobody nobody 1331397445 Feb 10 18:17 cuda-repo-rhel7-8-0-local-ga2v2-8.0.61-1.ppc64le.rpm
# -rw-r--r-- 1 nobody nobody      79404 Jul 27 01:20 dkms-2.3-5.20170523git8c3065c.el7.noarch.rpm
# -rwxrwxrwx 2 nobody nobody 3283865600 Jul 27 23:21 RHEL-7.4-20170711.0-Server-ppc64le-dvd1.iso

########
# Auto detect all the source packages from the ${SOURCE_DIR}

[ -d "${SOURCE_DIR}" ]
[ "$?" -ne "0" ] && echo "Directory ${SOURCE_DIR} not found." >&2 && exit 1

declare RHEL_ISO
declare -a CUDA_RPMS
declare DKMS_RPM

for f in "${SOURCE_DIR}"/*
do
	r="$(realpath "${f}")"
	[ -f "${r}" ] || continue
	case "${r##*/}" in
	"RHEL-"*"-"*"-Server-${LINUX_ARCH}-dvd1.iso")
		RHEL_ISO="${r}"
		;;
	"cuda-repo-rhel"*"-"*"-local-"*".${LINUX_ARCH}.rpm")
		if [[ "$(echo "${r##*/}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" \
			> \
			"$(echo "${CUDA_RPMS[0]}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" ]]
		then
			CUDA_RPMS=("${r}")
		elif [[ "$(echo "${r##*/}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" \
			= \
			"$(echo "${CUDA_RPMS[0]}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" ]]
		then
			CUDA_RPMS+=("${r}")
		fi
		;;
	"dkms-"*".el7.noarch.rpm")
		DKMS_RPM="${r}"
		;;
	"nvidia-driver-local-repo-rhel"*"-"*".${LINUX_ARCH}.rpm")
		CUDA_RPMS+=("${r}")
		;;
	esac
done

########
# Override the auto detect results here.

#RHEL_ISO="${SOURCE_DIR}/RHEL-7.4-20170711.0-Server-ppc64le-dvd1.iso"
#CUDA_RPMS=(
#	"${SOURCE_DIR}/cuda-repo-rhel7-8-0-local-ga2v2-8.0.61-1.ppc64le.rpm"
#	"${SOURCE_DIR}/cuda-repo-rhel7-8-0-local-cublas-performance-update-8.0.61-1.ppc64le.rpm"
#)
#DKMS_RPM="${SOURCE_DIR}/dkms-2.3-5.20170523git8c3065c.el7.noarch.rpm"

########
echo "Red Hat Enterprise Linux Server ISO"
echo "==================================="
echo "${RHEL_ISO}"
echo
echo "CUDA RPM(s)"
echo "==========="
for f in "${CUDA_RPMS[@]}"
do
	echo "${f}"
done
echo
echo "DKMS RPM"
echo "========"
echo "${DKMS_RPM}"
echo

echo "The files listed above were found and will be used for this test case"
echo "Press Ctrl-C to abort!"
for t in {5..1}
do
	echo -n " ... ${t}"
	sleep 1
	echo -n -e "\b\b\b\b\b\b"
done
########

umask 0022

OSIMAGE_NAME="${LINUX_DISTRO}-${LINUX_ARCH}-netboot-cudafull"
OSIMAGE_OTHERPKGDIR="/install/post/otherpkgs/${LINUX_DISTRO}/${LINUX_ARCH}"
OSIMAGE_ROOTIMGDIR="/install/netboot/${LINUX_DISTRO}/${LINUX_ARCH}/${OSIMAGE_NAME}"

[ -f "${RHEL_ISO}" ]
[ "$?" -ne "0" ] && echo "File ${RHEL_ISO} not found." >&2 && exit 1
copycds "${RHEL_ISO}"
[ "$?" -ne "0" ] && echo "Copy CD failed." >&2 && exit 1

rmdef -t osimage "${OSIMAGE_NAME}"
mkdef -z <<-EOF
# <xCAT data object stanza file>

${OSIMAGE_NAME}:
    objtype=osimage
    exlist=/opt/xcat/share/xcat/netboot/rh/compute.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.exlist
    imagetype=linux
    osarch=${LINUX_ARCH}
    osdistroname=${LINUX_DISTRO}-${LINUX_ARCH}
    osname=Linux
    osvers=${LINUX_DISTRO}
    otherpkgdir="${OSIMAGE_OTHERPKGDIR}"
    otherpkglist=/opt/xcat/share/xcat/netboot/rh/cudafull.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.otherpkgs.pkglist
    permission=755
    pkgdir=/install/${LINUX_DISTRO}/${LINUX_ARCH}
    pkglist=/opt/xcat/share/xcat/netboot/rh/compute.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.pkglist
    postinstall=/install/custom/netboot/rh/cudafull.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.postinstall
    profile=compute
    provmethod=netboot
    rootimgdir=${OSIMAGE_ROOTIMGDIR}
EOF
[ "$?" -ne "0" ] && echo "Make osimage definition failed." >&2 && exit 1

mkdir -p /install/custom/netboot/rh
(
	cat "/opt/xcat/share/xcat/netboot/rh/compute.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.postinstall"
	cat <<-EOF

	cp /install/postscripts/cuda_power9_setup "\$installroot/tmp/cuda_power9_setup"
	chroot "\$installroot" /tmp/cuda_power9_setup

	rm -f "\$installroot/tmp/cuda_power9_setup"
	EOF
) >"/install/custom/netboot/rh/cudafull.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.postinstall"
chmod 0755 "/install/custom/netboot/rh/cudafull.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.postinstall"

rm -rf "${OSIMAGE_OTHERPKGDIR}"
mkdir -p "${OSIMAGE_OTHERPKGDIR}"
for f in "${CUDA_RPMS[@]}"
do
	[ -f "${f}" ]
	[ "$?" -ne "0" ] && echo "File ${f} not found." >&2 && exit 1
	rpm2cpio "${f}" | ( cd "${OSIMAGE_OTHERPKGDIR}" && cpio -ivd )
done

mkdir -p "${OSIMAGE_OTHERPKGDIR}"/dkms
[ -f "${DKMS_RPM}" ]
[ "$?" -ne "0" ] && echo "File ${DKMS_RPM} not found." >&2 && exit 1
cp "${DKMS_RPM}" "${OSIMAGE_OTHERPKGDIR}/dkms"

( cd "${OSIMAGE_OTHERPKGDIR}" && createrepo . )

rm -rf "${OSIMAGE_ROOTIMGDIR}"

genimage "${OSIMAGE_NAME}"
[ "$?" -ne "0" ] && echo "genimage failed" >&2 && exit 1
packimage "${OSIMAGE_NAME}"
[ "$?" -ne "0" ] && echo "packimage failed" >&2 && exit 1

makedhcp -n
rinstall "${COMPUTE_NODE}" "osimage=${OSIMAGE_NAME}"

NETBOOT_TIMEOUT=600
declare -i WAIT=0

while sleep 10
do
	(( WAIT += 10 ))
	nodestat "${COMPUTE_NODE}" | grep ': sshd$'
	[ "$?" -eq "0" ] && break
	[ "${WAIT}" -le "${NETBOOT_TIMEOUT}" ]
	[ "$?" -ne "0" ] && echo "Netboot failed" >&2 && exit 1
done

# For workaround the GitHub issue #3549
sleep 5

xdsh "${COMPUTE_NODE}" date
[ "$?" -ne "0" ] && echo "Failed connect to compute node via SSH." >&2 && exit 1

xdsh "${COMPUTE_NODE}" 'rpm -q cuda' | grep ': cuda-'
[ "$?" -ne "0" ] && echo "CUDA installation checking failed" >&2 && exit 1

exit 0
