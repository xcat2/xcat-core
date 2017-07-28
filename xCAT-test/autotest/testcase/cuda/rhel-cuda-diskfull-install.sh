#!/bin/bash

########
# Set all the variables below

COMPUTE_NODE="c910f03c01p10"
OSIMAGE_NAME="rhels7.3-ppc64le-install-cudafull"
OSIMAGE_OTHERPKGDIR="/install/post/otherpkgs/rhels7.3/ppc64le"
SOURCE_BASEDIR="/media/xcat"

RHEL_ISO="${SOURCE_BASEDIR}/RHEL-7.3-20161019.0-Server-ppc64le-dvd1.iso"
CUDA_RPMS=(
	"${SOURCE_BASEDIR}/cuda-repo-rhel7-8-0-local-ga2v2-8.0.61-1.ppc64le.rpm"
	"${SOURCE_BASEDIR}/cuda-repo-rhel7-8-0-local-cublas-performance-update-8.0.61-1.ppc64le.rpm"
)
DKMS_RPM="${SOURCE_BASEDIR}/dkms-2.3-5.20170523git8c3065c.el7.noarch.rpm"

# Set all the variables above
########

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
    osarch=ppc64le
    osdistroname=rhels7.3-ppc64le
    osname=Linux
    osvers=rhels7.3
    otherpkgdir="${OSIMAGE_OTHERPKGDIR}"
    pkgdir=/install/rhels7.3/ppc64le
    pkglist=/opt/xcat/share/xcat/install/rh/cudafull.rhels7.ppc64le.pkglist
    profile=compute
    provmethod=install
    template=/opt/xcat/share/xcat/install/rh/compute.rhels7.tmpl
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
