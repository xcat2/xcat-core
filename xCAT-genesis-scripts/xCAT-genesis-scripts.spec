%ifarch i386 i586 i686 x86
%define tarch x86
%endif
%ifarch x86_64
%define tarch x86_64
%endif
%ifarch ppc ppc64
%define tarch ppc64
%endif
%define rpminstallroot /opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs
BuildArch: noarch
%define name	xCAT-genesis-scripts-%{tarch}
%define __spec_install_post :
%define debug_package %{nil}
%define __prelink_undo_cmd %{nil}
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 1
AutoReq: false
Prefix: /opt/xcat
AutoProv: false
Obsoletes: xCAT-genesis-%{tarch}
Provides: xCAT-genesis-%{tarch}



Name:	 %{name}
Version: %(cat Version)
Group: System/Utilities
License: EPL
Vendor: IBM Corp
Summary: xCAT Genesis netboot image - Core content
URL:	 http://xcat.org
Source1: xCAT-genesis-scripts.tar.bz2
Requires: xCAT-genesis-base-%{tarch}

Buildroot: %{_localstatedir}/tmp/xCAT-genesis
Packager: IBM Corp.

%Description
xCAT genesis (Genesis Enhanced Netboot Environment for System Information and Servicing) is a small, embedded-like environment for xCAT's use in discovery and management actions when interaction with an OS is infeasible.
This package reperesents the EPL content that is more tightly bound to specific xcat-core versions
%Prep


%Build

%Install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT
tar jxf %{SOURCE1}
mkdir -p opt/xcat/share/xcat/netboot/genesis/%{tarch}/
mv xCAT-genesis-scripts opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs
rm opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/*.spec
rm opt/xcat/share/xcat/netboot/genesis/%{tarch}/fs/LICENSE.html
cd -


# Since this rpm is being installed/updated, we need to run mknb to combine it with
# xCAT-genesis-base-x86_64, but mknb will not work during an initial install of xcat
# until the xCAT meta pkg has run xcatconfig or xCATsn has started xcatd.  Use of a trigger
# allows us to tell those pkgs to run the code below after they run their %post scriptlets.
# (If xCAT or xCATsn is installed already, this trigger will run when xCAT-genesis-scripts
# is installed/updated.)

%post
# Touch this file to tell the xCAT and xCATsn rpms that when they install/update they
# should run mknb.  Tried to use rpm triggers, but in several cases the trigger would
# get run multiple times.
#echo "touching /etc/xcat/genesis-scripts-updated"
echo "If you are installing/updating xCAT-genesis-base separately, not as part of installing/updating all of xCAT, run 'mknb <arch> manually'"
mkdir -p /etc/xcat
touch /etc/xcat/genesis-scripts-updated


%Files
%defattr(-,root,root)
#%dir %attr(-,root,root) %{rpminstallroot}
%{rpminstallroot}/bin/allowcred.awk
%{rpminstallroot}/bin/bmcsetup
%{rpminstallroot}/bin/dodiscovery
%{rpminstallroot}/bin/dosysclone
%{rpminstallroot}/bin/doxcat
%{rpminstallroot}/bin/getcert
%{rpminstallroot}/bin/getdestiny
%{rpminstallroot}/bin/getipmi
%{rpminstallroot}/bin/ifup
%{rpminstallroot}/bin/minixcatd.awk
%{rpminstallroot}/bin/nextdestiny
%{rpminstallroot}/bin/remoteimmsetup
%{rpminstallroot}/bin/udpcat.awk
%{rpminstallroot}/bin/updateflag.awk
%{rpminstallroot}/bin/pseries_platform
%{rpminstallroot}/bin/update_flash
%{rpminstallroot}/bin/update_flash_nv
%{rpminstallroot}/debian/changelog
%{rpminstallroot}/debian/compat
%{rpminstallroot}/debian/control
%{rpminstallroot}/debian/copyright
#%{rpminstallroot}/debian/dirs
%{rpminstallroot}/debian/docs
#%{rpminstallroot}/debian/install
%{rpminstallroot}/debian/postinst
%{rpminstallroot}/debian/postrm
%{rpminstallroot}/debian/preinst
%{rpminstallroot}/debian/prerm
%{rpminstallroot}/debian/rules
%{rpminstallroot}/etc/init.d/functions
%{rpminstallroot}/etc/udev/rules.d/99-imm.rules
%{rpminstallroot}/sbin/setupimmnic
