#!/bin/bash

########
#
# For manually run this script in a standalone test environment without xCAT-test,
# do the following steps.
#
# * Set all the variables in LINE 11, 13, 16, and 17.
# * Download all the ISO files, RPMs needed, and put them in ${SOURCE_DIR}
# * If you intend to specify all the packages explicitly, set variable in LINE 61, 62, 63.
#

[ -n "$LINUX_DISTRO" ] ||
LINUX_DISTRO="rhels7.4"
[ -n "$LINUX_ARCH" ] ||
LINUX_ARCH="ppc64le"

[ -n "$COMPUTE_NODE" ] ||
COMPUTE_NODE="nonexistent"
SOURCE_DIR="/path/to/source"

########

# $SOURCE_DIR is a directory this test case will be searched for.
# Files with the name looked like the following will be searched.
#
# -rw-r--r-- 1 nobody nobody      79404 Jul 27 01:20 dkms-2.3-5.20170523git8c3065c.el7.noarch.rpm
# -rw-r--r-- 1 nobody nobody 29085696   Jul  9 09:24 mlnx-en-4.1-1.0.2.0-rhel7.3-ppc64le.iso
# -rw-r--r-- 2 nobody nobody 3188944896 Oct 31  2016 RHEL-7.3-20161019.0-Server-ppc64le-dvd1.iso

########
# Auto detect all the source packages from the ${SOURCE_DIR}

[ -d "${SOURCE_DIR}" ]
[ "$?" -ne "0" ] && echo "Directory ${SOURCE_DIR} not found." >&2 && exit 1

declare DKMS_RPM
declare RHEL_ISO
declare MLNX_ISO

for f in "${SOURCE_DIR}"/*
do
	r="$(realpath "${f}")"
	[ -f "${r}" ] || continue
	case "${r##*/}" in
	"RHEL-"*"-"*"-Server-${LINUX_ARCH}-dvd1.iso")
		RHEL_ISO="${r}"
		;;
	"MLNX_OFED_LINUX-"*"-"*"-${LINUX_DISTRO/s/}-${LINUX_ARCH}.iso")
		MLNX_ISO="${r}"
		;;
	"dkms-"*".el7.noarch.rpm")
		DKMS_RPM="${r}"
		;;
	esac
done

########
# Override the auto detect results here.

#MLNX_ISO="${SOURCE_DIR}/mlnx-en-4.1-1.0.2.0-rhel7.3-ppc64le.iso"
#RHEL_ISO="${SOURCE_DIR}/RHEL-7.3-20161019.0-Server-ppc64le-dvd1.iso"
#DKMS_RPM="${SOURCE_DIR}/dkms-2.3-5.20170523git8c3065c.el7.noarch.rpm"

########
echo "Red Hat Enterprise Linux Server ISO"
echo "==================================="
echo "${RHEL_ISO}"
echo
echo "Mellanox EN Driver for Linux"
echo "============================"
echo "${MLNX_ISO}"
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

OSIMAGE_NAME="${LINUX_DISTRO}-${LINUX_ARCH}-install-mlnx"
OSIMAGE_OTHERPKGDIR="/install/post/otherpkgs/${LINUX_DISTRO}/${LINUX_ARCH}"
OSIMAGE_ROOTIMGDIR="/install/install/${LINUX_DISTRO}/${LINUX_ARCH}/${OSIMAGE_NAME}"

[ -f "${RHEL_ISO}" ]
[ "$?" -ne "0" ] && echo "File ${RHEL_ISO} not found." >&2 && exit 1
copycds "${RHEL_ISO}"
[ "$?" -ne "0" ] && echo "Copy CD failed." >&2 && exit 1

rmdef -t osimage "${OSIMAGE_NAME}"
mkdef -z <<-EOF
# <xCAT data object stanza file>

${OSIMAGE_NAME}:
    objtype=osimage
    imagetype=linux
    osarch=${LINUX_ARCH}
    osdistroname=${LINUX_DISTRO}-${LINUX_ARCH}
    osname=Linux
    osvers=${LINUX_DISTRO}
    otherpkgdir="${OSIMAGE_OTHERPKGDIR}"
    otherpkglist=/install/custom/install/rh/mlnx.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.otherpkgs.pkglist
    pkgdir=/install/${LINUX_DISTRO}/${LINUX_ARCH}
    pkglist=/install/custom/install/rh/mlnx.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.pkglist
    profile=compute
    provmethod=install
    template=/opt/xcat/share/xcat/install/rh/compute.${LINUX_DISTRO%%.*}.tmpl
EOF
[ "$?" -ne "0" ] && echo "Make osimage definition failed." >&2 && exit 1

mkdir -p /install/mlnx
cp "${MLNX_ISO}" /install/mlnx

mkdir -p /install/custom/install/rh

(
	cat /opt/xcat/share/xcat/install/rh/compute.${LINUX_DISTRO%%.*}.pkglist

	cat <<-EOF

	# For MLNX OFED support
	EOF
	cat /opt/xcat/share/xcat/ib/netboot/rh/ib.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.pkglist
) >"/install/custom/install/rh/mlnx.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.pkglist"

(
	:
) >"/install/custom/install/rh/mlnx.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.otherpkgs.pkglist"

cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install.v2 \
	/install/postscripts/mlnxofed_ib_install.v2

chdef "${COMPUTE_NODE}" "postscripts=syslog,remoteshell,syncfiles,mlnxofed_ib_install.v2 -p /install/mlnx/${MLNX_ISO##*/} -m --add-kernel-support"

rm -rf "${OSIMAGE_OTHERPKGDIR}"
mkdir -p "${OSIMAGE_OTHERPKGDIR}"

mkdir -p "${OSIMAGE_OTHERPKGDIR}"/dkms
[ -f "${DKMS_RPM}" ]
[ "$?" -ne "0" ] && echo "File ${DKMS_RPM} not found." >&2
cp "${DKMS_RPM}" "${OSIMAGE_OTHERPKGDIR}/dkms"

( cd "${OSIMAGE_OTHERPKGDIR}" && createrepo . )

makedhcp -n
rinstall "${COMPUTE_NODE}" "osimage=${OSIMAGE_NAME}"

INSTALL_TIMEOUT=1800
declare -i WAIT=0

while sleep 10
do
	(( WAIT += 10 ))
	nodestat "${COMPUTE_NODE}" | grep ': sshd$'
	[ "$?" -eq "0" ] && break
	[ "${WAIT}" -le "${INSTALL_TIMEOUT}" ]
	[ "$?" -ne "0" ] && echo "Operating system installation failed." >&2 && exit 1
done

# For workaround the GitHub issue #3549
sleep 5

xdsh "${COMPUTE_NODE}" date
[ "$?" -ne "0" ] && echo "Failed connect to compute node via SSH." >&2 && exit 1

xdsh "${COMPUTE_NODE}" 'rpm -qa' | grep 'mlnx'
[ "$?" -ne "0" ] && echo "MLNX OFED installation checking failed." >&2 && exit 1

xdsh "${COMPUTE_NODE}" 'lspci'
xdsh "${COMPUTE_NODE}" 'lsslot -c pci'
xdsh "${COMPUTE_NODE}" 'lsslot'
xdsh "${COMPUTE_NODE}" 'ibv_devinfo'
xdsh "${COMPUTE_NODE}" 'iblinkinfo'

exit 0
