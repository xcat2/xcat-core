#!/bin/bash

########
# Set all the variables below

LINUX_DISTRO="ubuntu16.04.2"
LINUX_ARCH="ppc64el"

COMPUTE_NODE="c910f03c11k06"
SOURCE_DIR="/media/xcat"

########

# $SOURCE_DIR is a directory this test case will be searched for.
# Files with the name looked like the following will be searched.
#
# -rw-r--r-- 1 nobody nobody  124037944 Jun 28 17:00 cuda-repo-ubuntu1604-8-0-local-cublas-performance-update_8.0.61-1_ppc64el.deb
# -rw-r--r-- 1 nobody nobody 1321330418 Feb 10 18:18 cuda-repo-ubuntu1604-8-0-local-ga2v2_8.0.61-1_ppc64el.deb
# -rw-r--r-- 1 nobody nobody   69365760 Jul 27 20:35 mini.iso
# -rw-r--r-- 1 nobody nobody  927946752 Feb 15 15:57 ubuntu-16.04.2-server-ppc64el.iso

########
# Auto detect all the source packages from the ${SOURCE_DIR}

[ -d "${SOURCE_DIR}" ]
[ "$?" -ne "0" ] && echo "Directory ${SOURCE_DIR} not found." >&2 && exit 1

declare UBUNTU_ISO
declare UBUNTU_MINI_ISO
declare -a CUDA_DEBS

for f in "${SOURCE_DIR}"/*
do
	r="$(realpath "${f}")"
	[ -f "${r}" ] || continue
	case "${r##*/}" in
	"ubuntu-"*"-server-${LINUX_ARCH}.iso")
		UBUNTU_ISO="${r}"
		;;
	*"mini.iso")
		UBUNTU_MINI_ISO="${r}"
		;;
	"cuda-repo-ubuntu"*"-"*"-local-"*"_${LINUX_ARCH}.deb")
		if [[ "$(echo "${r##*/}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" \
			> \
			"$(echo "${CUDA_DEBS[0]}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" ]]
		then
			CUDA_DEBS=("${r}")
		elif [[ "$(echo "${r##*/}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" \
			= \
			"$(echo "${CUDA_DEBS[0]}" |
			sed -e 's#.*\([0-9]\+.[0-9]\+.[0-9]\+-[0-9]\+\).*#\1#')" ]]
		then
			CUDA_DEBS+=("${r}")
		fi
		;;
	esac
done

########
# Override the auto detect results here.

#UBUNTU_ISO="${SOURCE_DIR}/ubuntu-16.04.2-server-ppc64el.iso"
#UBUNTU_MINI_ISO="${SOURCE_DIR}/mini.iso"
#CUDA_DEBS=(
#	"${SOURCE_DIR}/cuda-repo-ubuntu1604-8-0-local-ga2v2_8.0.61-1_ppc64el.deb"
#	"${SOURCE_DIR}/cuda-repo-ubuntu1604-8-0-local-cublas-performance-update_8.0.61-1_ppc64el.deb"
#)

########
echo "Ubuntu ISO"
echo "==================================="
echo "${UBUNTU_ISO}"
echo
echo "Ubuntu mini ISO"
echo "==================================="
echo "${UBUNTU_MINI_ISO}"
echo
echo "CUDA DEB(s)"
echo "==========="
for f in "${CUDA_DEBS[@]}"
do
	echo "${f}"
done
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

OSIMAGE_NAME="${LINUX_DISTRO}-${LINUX_ARCH}-install-cudafull"
OSIMAGE_OTHERPKGDIR="/install/post/otherpkgs/${LINUX_DISTRO}/${LINUX_ARCH}"

[ -f "${UBUNTU_ISO}" ]
[ "$?" -ne "0" ] && echo "File ${UBUNTU_ISO} not found." >&2 && exit 1
copycds "${UBUNTU_ISO}"
[ "$?" -ne "0" ] && echo "Copy CD failed." >&2 && exit 1

[ -f "${UBUNTU_MINI_ISO}" ]
[ "$?" -ne "0" ] && echo "File ${UBUNTU_MINI_ISO} not found." >&2 && exit 1
MOUNT_POINT="/tmp/ubuntu-mini-iso-$$"
mkdir -p "${MOUNT_POINT}"
mount -o loop "${UBUNTU_MINI_ISO}" "${MOUNT_POINT}"
mkdir -p "/install/${LINUX_DISTRO}/${LINUX_ARCH}/install/netboot"
cp "${MOUNT_POINT}/install/"* "/install/${LINUX_DISTRO}/${LINUX_ARCH}/install/netboot"
umount "${MOUNT_POINT}"
rmdir "${MOUNT_POINT}"

rmdef -t osimage "${OSIMAGE_NAME}"
mkdef -z <<-EOF
# <xCAT data object stanza file>

${OSIMAGE_NAME}:
    objtype=osimage
    imagetype=linux
    osarch=${LINUX_ARCH}
    osname=Linux
    osvers=${LINUX_DISTRO}
    otherpkgdir=${OSIMAGE_OTHERPKGDIR}/var/cuda/repo-8-0-local-ga2v2,http://ports.ubuntu.com/ubuntu-ports/ xenial
    pkgdir=/install/${LINUX_DISTRO}/${LINUX_ARCH}
    pkglist=/opt/xcat/share/xcat/install/ubuntu/cudafull.${LINUX_DISTRO}.${LINUX_ARCH}.pkglist
    profile=compute
    provmethod=install
    template=/opt/xcat/share/xcat/install/ubuntu/compute.tmpl
EOF
[ "$?" -ne "0" ] && echo "Make osimage definition failed." >&2 && exit 1

rm -rf "${OSIMAGE_OTHERPKGDIR}"
mkdir -p "${OSIMAGE_OTHERPKGDIR}"
for f in "${CUDA_DEBS[@]}"
do
	[ -f "${f}" ]
	[ "$?" -ne "0" ] && echo "File ${f} not found." >&2 && exit 1
	dpkg -x "${f}" "${OSIMAGE_OTHERPKGDIR}"
done

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

xdsh "${COMPUTE_NODE}" 'dpkg -l' | grep 'cuda-'
[ "$?" -ne "0" ] && echo "CUDA installation checking failed" >&2 && exit 1

exit 0
