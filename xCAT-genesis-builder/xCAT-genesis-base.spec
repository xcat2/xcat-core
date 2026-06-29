Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
%ifarch i386 i586 i686 x86
%define tarch x86
%endif
%ifarch x86_64
%define tarch x86_64
%endif
%ifarch ppc ppc64 ppc64le
%define tarch ppc64
%endif
%ifarch aarch64
%define tarch aarch64
%endif
BuildArch: noarch
%define name	xCAT-genesis-base-%{tarch}
%define __spec_install_post :
%define debug_package %{nil}
%define __prelink_undo_cmd %{nil}
# To fix the issue error: Arch dependent binaries in noarch package, the following line is needed on Fedora 23 ppc64
%define _binaries_in_noarch_packages_terminate_build   0
Epoch: 2
AutoReq: false
Prefix: /opt/xcat
AutoProv: false

Name:	 %{name}
Group: System/Utilities
License: Various (see individual packages for details)
Vendor: IBM Corp.
Summary: xCAT Genesis netboot image
URL:	 https://xcat.org/
Source0: xCAT-genesis-base-build-support.tar.bz2
Conflicts: xCAT-genesis-scripts-%{tarch} < 1:2.13.10
BuildRequires: bc
BuildRequires: bind-utils
BuildRequires: chrony
BuildRequires: cpio
BuildRequires: e2fsprogs
BuildRequires: hostname
%if "%{_target_cpu}" == "x86_64"
BuildRequires: dmidecode
BuildRequires: efibootmgr
%endif
BuildRequires: dosfstools
BuildRequires: dracut
BuildRequires: dracut-network
BuildRequires: ethtool
BuildRequires: gawk
BuildRequires: ipmitool
BuildRequires: iproute
BuildRequires: kexec-tools
BuildRequires: kernel-core
BuildRequires: lldpad
BuildRequires: lvm2
BuildRequires: mdadm
BuildRequires: mstflint
BuildRequires: net-tools
BuildRequires: nfs-utils
BuildRequires: nmap-ncat
BuildRequires: openssh-clients
BuildRequires: openssh-server
BuildRequires: parted
BuildRequires: pciutils
BuildRequires: perl
BuildRequires: perl-interpreter
BuildRequires: procps-ng
BuildRequires: psmisc
BuildRequires: rsync
BuildRequires: rsyslog
BuildRequires: tmux
BuildRequires: usbutils
BuildRequires: util-linux
BuildRequires: vim-minimal
BuildRequires: wget
BuildRequires: xfsprogs

Buildroot: %{_localstatedir}/tmp/xCAT-genesis
Packager: IBM Corp.

%Description
xCAT genesis (Genesis Enhanced Netboot Environment for System Information and Servicing) is a small, embedded-like environment for xCAT's use in discovery and management actions when interaction with an OS is infeasible.
This package comprises the base platform with most of the xCAT specific behavior left to xCAT-genesis-scripts package.
Built in environment "%dist" on %{_arch}.
%prep
%setup -q -n xCAT-genesis-base-build-support


%build

%Install
set -euxo pipefail

rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/genesis/%{tarch}

GENESIS_TMPDIR=$(mktemp -d %{_tmppath}/xcat-genesis.%{tarch}.XXXXXX)
GENESIS_ROOT=$GENESIS_TMPDIR/%{prefix}/share/xcat/netboot/genesis/%{tarch}
GENESIS_FS=$GENESIS_ROOT/fs
DRACUT_IMAGE=$GENESIS_TMPDIR/genesis.rfs

cleanup() {
    rm -rf "$GENESIS_TMPDIR"
    rm -rf "$DRACUTMODDIR"
}
trap cleanup EXIT

if [ -d /usr/share/dracut/modules.d ]; then
    DRACUT_PARENT=/usr/share/dracut/modules.d
else
    DRACUT_PARENT=/usr/lib/dracut/modules.d
fi
DRACUTMODDIR=$DRACUT_PARENT/97xcat
rm -rf "$DRACUTMODDIR"
mkdir -p "$DRACUTMODDIR"
cp -a "%{_builddir}/xCAT-genesis-base-build-support/dracut_105/el/." "$DRACUTMODDIR/"
chmod 0755 "$DRACUTMODDIR/module-setup.sh" "$DRACUTMODDIR/xcatroot" "$DRACUTMODDIR/dhclient-script"
if [ "%{_target_cpu}" != "x86_64" ]; then
    sed -i '/efibootmgr dmidecode/d' "$DRACUTMODDIR/module-setup.sh"
fi

KERNELVERSION=$(ls -1 /lib/modules | sort -V | tail -n 1)
test -n "$KERNELVERSION"

mkdir -p "$GENESIS_FS/etc/ssh"
mkdir -p /run/rpcbind
dracut --compress gzip -m "xcat base" --no-early-microcode -N -f "$DRACUT_IMAGE" "$KERNELVERSION"

(
    cd "$GENESIS_FS"
    zcat "$DRACUT_IMAGE" | cpio -dumi
)

# usrmerge collapse: on a usr-merged build host the extracted genesis fs can
# contain /bin,/sbin,/lib,/lib64 as real directories that duplicate the files
# already under /usr/*, which makes rpm reject the package with file conflicts.
# Fold the top-level dirs into /usr and replace them with symlinks (a no-op on
# hosts where the image already ships them as symlinks).
for _d in bin sbin lib lib64; do
    if [ -d "$GENESIS_FS/$_d" ] && [ ! -L "$GENESIS_FS/$_d" ] && [ -d "$GENESIS_FS/usr/$_d" ]; then
        cp -a "$GENESIS_FS/$_d/." "$GENESIS_FS/usr/$_d/" 2>/dev/null || true
        rm -rf "$GENESIS_FS/$_d"
        ln -s "usr/$_d" "$GENESIS_FS/$_d"
    fi
done

# xCAT 2.14.5 genesis payloads shipped usr/lib/dracut/hooks as a real directory.
# Newer dracut (EL8+) makes it a symlink to ../../../var/lib/dracut/hooks. RPM
# cannot replace a directory with a symlink across an upgrade, so a 2.17 -> 2.18
# upgrade aborts with a file conflict on this path. Materialize the symlink back
# into a real directory (with the hook contents) so the payload type matches the
# installed 2.14.5 layout and the upgrade is conflict-free on EL8/EL9/EL10.
if [ -L "$GENESIS_FS/usr/lib/dracut/hooks" ]; then
    hooks_target="$GENESIS_FS/var/lib/dracut/hooks"
    rm -f "$GENESIS_FS/usr/lib/dracut/hooks"
    if [ -d "$hooks_target" ]; then
        cp -a "$hooks_target" "$GENESIS_FS/usr/lib/dracut/hooks"
    else
        mkdir -p "$GENESIS_FS/usr/lib/dracut/hooks"
    fi
fi
if [ ! -d "$GENESIS_FS/usr/lib/dracut/hooks" ] || [ -L "$GENESIS_FS/usr/lib/dracut/hooks" ]; then
    echo "genesis payload has invalid usr/lib/dracut/hooks layout" >&2
    exit 1
fi

for script in \
    "$GENESIS_FS/sbin/dhclient-script" \
    "$GENESIS_FS/usr/sbin/dhclient-script" \
    "$GENESIS_FS/sbin/xcatroot"
do
    if [ -f "$script" ]; then
        chmod 0755 "$script"
    fi
done

for perl_dir in \
    /usr/share/perl5 \
    /usr/lib64/perl5 \
    /usr/local/lib64/perl5 \
    /usr/local/share/perl5 \
    /usr/share/ntp/lib
do
    if [ -d "$perl_dir" ]; then
        mkdir -p "$GENESIS_FS$perl_dir"
        cp -a "$perl_dir/." "$GENESIS_FS$perl_dir/"
    fi
done

mkdir -p "$GENESIS_FS/lib/udev/rules.d"
if [ -e /lib/udev/rules.d/80-net-name-slot.rules ]; then
    cp /lib/udev/rules.d/80-net-name-slot.rules "$GENESIS_FS/lib/udev/rules.d/"
else
    cp "%{_builddir}/xCAT-genesis-base-build-support/80-net-name-slot.rules" \
       "$GENESIS_FS/lib/udev/rules.d/"
fi

KERNEL_IMAGE=/boot/vmlinuz-$KERNELVERSION
if [ ! -e "$KERNEL_IMAGE" ]; then
    for candidate in \
        "/usr/lib/modules/$KERNELVERSION/vmlinuz" \
        "/lib/modules/$KERNELVERSION/vmlinuz" \
        "$(find /usr/lib/modules/$KERNELVERSION -maxdepth 2 -name 'vmlinuz*' 2>/dev/null | head -n 1)" \
        "$(find /lib/modules/$KERNELVERSION -maxdepth 2 -name 'vmlinuz*' 2>/dev/null | head -n 1)" \
        "$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort -V | tail -n 1)"
    do
        if [ -n "$candidate" ] && [ -e "$candidate" ]; then
            KERNEL_IMAGE="$candidate"
            break
        fi
    done
fi
test -n "$KERNEL_IMAGE"
test -e "$KERNEL_IMAGE"
cp "$KERNEL_IMAGE" "$GENESIS_ROOT/kernel"

find "$GENESIS_TMPDIR" -type c -delete
cp -a "$GENESIS_TMPDIR/%{prefix}/." "$RPM_BUILD_ROOT/%{prefix}/"


%pretrans -p <lua>
-- Lua block of code for removing a directory recursively
-- The Lua function remove_directory_deep should be called
-- with a directory name in a spec file, also with
-- a rpm macro defined to a directory name. This function
-- is a possible lua equivalent of the shell command "rm -rf"
-- using the lua posix extension embedded in rpm
local leaf_indent = '| '
local tail_leaf_indent = ' '
local leaf_prefix = '|-- '
local tail_leaf_prefix = '`-- '
local link_prefix = ' -> '

local function printf(...)
    io.write(string.format(table.unpack({...})))
end

local function remove_directory(directory, level, prefix)
    local num_dirs = 0
    local num_files = 0
    if posix.access(directory, "rw") then
    local files = posix.dir(directory)
    local last_file_index = #files
    table.sort(files)
    for i, name in ipairs(files) do
        if name ~= '.' and name ~= '..' then
            local full_name = string.format('%s/%s', directory, name)
            local info = assert(posix.stat(full_name))
            local is_tail = (i==last_file_index)
            local prefix2 = is_tail and tail_leaf_prefix or leaf_prefix
            local link = ''
            if info.type == 'link' then
                linked_name = assert(posix.readlink(full_name))
                link = string.format('%s%s', link_prefix, linked_name)
                posix.unlink(full_name)
            end

            -- printf('%s%s%s%s\n', prefix, prefix2, name, link)

            if info.type == 'directory' then
                local indent = is_tail and tail_leaf_indent or leaf_indent
                sub_dirs, sub_files = remove_directory(full_name, level+1,
                    prefix .. indent)
                num_dirs = num_dirs + sub_dirs + 1
                num_files = num_files + sub_files
                posix.rmdir(full_name)
            else
                posix.unlink(full_name)
                num_files = num_files + 1
            end
        end
    end
    end -- if access
    return num_dirs, num_files
end

local function remove_directory_deep(directory)

    -- print(directory)

    if posix.access(directory, "rw") then
        local info = assert(posix.stat(directory))
        if info.type == 'directory' then
            num_dirs, num_files = remove_directory(directory, 0, '')

            -- printf('\ndropped %d directories, %d files\n', num_dirs, num_files)

            posix.rmdir(directory)
        else
            posix.unlink(directory)
        end
    end
end

remove_directory_deep("/opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/bin")
remove_directory_deep("/opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/sbin")
remove_directory_deep("/opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/lib")
remove_directory_deep("/opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/lib64")
remove_directory_deep("/opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/var/run")

%post
if [ "$1" == "2" ]; then #only on upgrade, as on install it's probably not going to work...
    if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
        . /etc/profile.d/xcat.sh
        # During a full 'dnf update xCAT', xcatd is stopped while xCAT is being
        # upgraded, so mknb cannot reach it and exits non-zero. That must not fail
        # the rpm transaction: drop the genesis-base-updated marker so the netboot
        # image is regenerated later (xcatd post-start / manual 'mknb <arch>').
        mknb %{tarch} || echo "mknb %{tarch} deferred (xcatd not reachable during upgrade); run 'mknb %{tarch}' after xcatd is up"
        mkdir -p /etc/xcat
        touch /etc/xcat/genesis-base-updated
    fi
fi

%Files
%defattr(-,root,root)
/opt/xcat/share/xcat/netboot/genesis/%{tarch}
