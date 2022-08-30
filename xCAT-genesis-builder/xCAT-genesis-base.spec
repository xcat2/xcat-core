%global version %(rpm -q xCAT --qf "%{VERSION}" 2>/dev/null | grep -Po '[0-9\.]+' || echo "2.16.5")
Version: %{version}
Release: %{?release:%{release}}%{!?release:snap%(date +"%Y%m%d%H%M")}
%ifarch i386 i586 i686 x86
%define tarch x86
%endif
%ifarch x86_64
%define tarch x86_64
%endif
%ifarch ppc ppc64 ppc64le
%define tarch ppc64
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
Source1: xCAT-genesis-base-%{tarch}.tar.bz2
Conflicts: xCAT-genesis-scripts-%{tarch} < 1:2.13.10

Buildroot: %{_localstatedir}/tmp/xCAT-genesis
Packager: IBM Corp.

%Description
xCAT genesis (Genesis Enhanced Netboot Environment for System Information and Servicing) is a small, embedded-like environment for xCAT's use in discovery and management actions when interaction with an OS is infeasible.
This package comprises the base platform with most of the xCAT specific behavior left to xCAT-genesis-scripts package.
Built in environment "%dist" on %{_arch}.
%Prep


%Build

%Install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT
tar jxf %{SOURCE1}
cd -


%pretrans -p <lua>
-- Lua block of code for removing a directory recursively
-- The Lua function remove_directory_deep should be called
-- with a directory name or, in a spec file, also with
-- a rpm macro defined to a directory name. This function
-- is a possible lua equivalent of the shell command "rm -rf"
-- using the lua posix extension embedded in rpm
local leaf_indent = '| '
local tail_leaf_indent = ' '
local leaf_prefix = '|-- '
local tail_leaf_prefix = '`-- '
local link_prefix = ' -> '

local function printf(...)
    io.write(string.format(unpack(arg)))
end

local function remove_directory(directory, level, prefix)
    local num_dirs = 0
    local num_files = 0
    if posix.access(directory, "rw") then
    local files = posix.dir(directory)
    local last_file_index = table.getn(files)
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
        #mknb %{tarch}
        echo "If you are installing/updating xCAT-genesis-base separately, not as part of installing/updating all of xCAT, run 'mknb <arch>' manually"
        mkdir -p /etc/xcat
        touch /etc/xcat/genesis-base-updated
    fi
fi

%Files
%defattr(-,root,root)
/opt/xcat/share/xcat/netboot/genesis/%{tarch}
