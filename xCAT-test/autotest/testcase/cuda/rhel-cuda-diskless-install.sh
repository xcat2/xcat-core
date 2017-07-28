#!/bin/bash

########
# Set all the variables below

LINUX_DISTRO="rhels7.4"
LINUX_ARCH="ppc64le"

COMPUTE_NODE="c910f03c01p10"
SOURCE_BASEDIR="/media/xcat"

RHEL_ISO="${SOURCE_BASEDIR}/RHEL-7.4-20170711.0-Server-ppc64le-dvd1.iso"
CUDA_RPMS=(
	"${SOURCE_BASEDIR}/cuda-repo-rhel7-8-0-local-ga2v2-8.0.61-1.ppc64le.rpm"
	"${SOURCE_BASEDIR}/cuda-repo-rhel7-8-0-local-cublas-performance-update-8.0.61-1.ppc64le.rpm"
)
DKMS_RPM="${SOURCE_BASEDIR}/dkms-2.3-5.20170523git8c3065c.el7.noarch.rpm"

# Set all the variables above
########

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
    postinstall=/opt/xcat/share/xcat/netboot/rh/compute.${LINUX_DISTRO%%.*}.${LINUX_ARCH}.postinstall
    profile=compute
    provmethod=netboot
    rootimgdir=${OSIMAGE_ROOTIMGDIR}
EOF
[ "$?" -ne "0" ] && echo "Make node definition failed." >&2 && exit 1

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
