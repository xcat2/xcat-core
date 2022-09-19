# xCAT-genesis-builder

`xCAT-genesis-builder` is a utility for building base initrd images for deploying diskless nodes in your cluster for discovery. This tool is required only if you have the intention of building your own version of `xCAT-genesis-base` RPM which is available in `xcat-dep` (latest version was built on Fedora28).

# Background

For every architecture in your cluster, be it x86_64, or ppc64, you need to have a default
`initrd` image for performing the initial boot and deploying the diskless operating system.

If for some reason, the versions included in the xCAT `xcat-dep` repository are insufficient, you can simply
run this utility on the target architecture which will build a `xCAT-genesis-base` RPM designed for the target
architecture.  You can then transfer that RPM to your xCAT Management Node, install it, and then rebuild
the various netboot images.

# Pre-requisites

The `xCAT-genesis-builder` package is designed to be run from a Red Hat compatible operating system
that support the Red Hat Package Manager (rpm) development tools.  The script `buildrpm` will
attempt to install some of these core packages if they are not already present.

## Instructions for buiding `xCAT-genesis-builder` RPM
Latest version 2.16.3 of `xCAT-genesis-builder` RPM available at https://www.xcat.org/files/xcat/xcat-dep/2.x_Linux/beta and was verified to install and run on Fedora28 and Red Hat 8. Earlier version 2.14.5 of `xCAT-genesis-builder` RPM available at https://www.xcat.org/files/xcat/xcat-dep/2.x_Linux/beta and was verified to install and run on Fedora26 and Red Hat 7.
If a new version of `xCAT-genesis-builder` RPM needs to be built:

1. Clone `xcat-core` git repository:

```sh
git clone -b master https://github.com/xcat2/xcat-core.git
```

2. Build new `xCAT-genesis-builder` RPM:

```sh
cd xcat-core
./makerpm-genesisbuilder
```

## Instructions for buiding `xCAT-genesis-base` RPM

First, you need to clone the `xcat-core` repo to the target architecture using the following command:

```sh
git clone -b master https://github.com/xcat2/xcat-core.git
```

Once there, you can choose to either build the entire package, or more simply, 
do the following (assuming 2.16.10 is your xCAT version):

```sh
cd xcat-core/xCAT-genesis-builder
```

If needed, update version number inside `xCAT-genesis-base.spec`

```
./buildrpm
```

If this command is successful, runs error free, it will generate a `xCAT-genesis-base` RPM that you can transfer
to your xCAT server and install and then rebuild your netboot images prior to deploying
the netboot images to your nodes.

The RPM will be placed into the following directory `/root/rpmbuild/RPMS/noarch` if the build is successful.

When running the `buildrpm` the output should look similar to the following:

```sh
[root@vmhost6 xcat-core]# cd xCAT-genesis-builder
[root@vmhost6 xCAT-genesis-builder]# ./buildrpm
Last metadata expiration check: 3:03:21 ago on Fri 27 Aug 2021 06:07:01 AM EDT.
Package rpmdevtools-8.10-8.el8.noarch is already installed.
Package rpm-build-4.14.3-14.el8_4.x86_64 is already installed.
Package screen-4.6.2-12.el8.x86_64 is already installed.
Package lldpad-1.0.1-13.git036e314.el8.x86_64 is already installed.
Package mstflint-4.15.0-1.el8.x86_64 is already installed.
Dependencies resolved.
Nothing to do.
Complete!
Last metadata expiration check: 3:03:23 ago on Fri 27 Aug 2021 06:07:01 AM EDT.
Package efibootmgr-16-1.el8.x86_64 is already installed.
Package bc-1.07.1-5.el8.x86_64 is already installed.
Dependencies resolved.
Nothing to do.
Complete!
/root/xcat-core/xCAT-genesis-builder
cp: -r not specified; omitting directory '/root/xcat-core/xCAT-genesis-builder/debian'
Creating the initramfs in /tmp/xcatgenesis.351827.rfs using dracut ...

Expanding the initramfs into /tmp/xcatgenesis.351827/opt/xcat/share/xcat/netboot/genesis/x86_64/fs ...
623218 blocks
Adding perl libary /usr/share/perl5
Adding perl libary /usr/lib64/perl5
Adding kernel /boot/vmlinuz-x86_64 ...
/root/xcat-core/xCAT-genesis-builder
Tarring /tmp/xcatgenesis.351827/opt into /root/rpmbuild/SOURCES/xCAT-genesis-base-x86_64.tar.bz2 ...
Building xCAT-genesis-base rpm from /root/rpmbuild/SOURCES/xCAT-genesis-base-x86_64.tar.bz2 and /root/xcat-core/xCAT-genesis-builder/xCAT-genesis-base.spec ...
Executing(%prep): /bin/sh -e /var/tmp/rpm-tmp.z5jzb9
+ umask 022
+ cd /root/rpmbuild/BUILD
+ exit 0
Executing(%build): /bin/sh -e /var/tmp/rpm-tmp.Q5Rg87
+ umask 022
+ cd /root/rpmbuild/BUILD
+ exit 0
Executing(%install): /bin/sh -e /var/tmp/rpm-tmp.F7t435
+ umask 022
+ cd /root/rpmbuild/BUILD
+ '[' /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64 '!=' / ']'
+ rm -rf /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
++ dirname /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
+ mkdir -p /root/rpmbuild/BUILDROOT
+ mkdir /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
+ rm -rf /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
+ mkdir -p /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
+ cd /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
+ tar jxf /root/rpmbuild/SOURCES/xCAT-genesis-base-x86_64.tar.bz2
+ cd -
/root/rpmbuild/BUILD
+ :
Processing files: xCAT-genesis-base-x86_64-2.16.10-snap202108270912.noarch
Provides: xCAT-genesis-base-x86_64 = 2:2.16.10-snap202108270912
Requires(interp): /bin/sh
Requires(rpmlib): rpmlib(BuiltinLuaScripts) <= 4.2.2-1 rpmlib(CompressedFileNames) <= 3.0.4-1 rpmlib(FileDigests) <= 4.6.0-1 rpmlib(PartialHardlinkSets) <= 4.0.4-1 rpmlib(PayloadFilesHavePrefix) <= 4.0-1
Requires(post): /bin/sh
Conflicts: xCAT-genesis-scripts-x86_64 < 1:2.13.10
warning: Arch dependent binaries in noarch package
Checking for unpackaged file(s): /usr/lib/rpm/check-files /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
Wrote: /root/rpmbuild/SRPMS/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.src.rpm
Wrote: /root/rpmbuild/RPMS/noarch/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.noarch.rpm
Executing(%clean): /bin/sh -e /var/tmp/rpm-tmp.yShjx5
+ umask 022
+ cd /root/rpmbuild/BUILD
+ /usr/bin/rm -rf /root/rpmbuild/BUILDROOT/xCAT-genesis-base-x86_64-2.16.10-snap202108270912.x86_64
+ exit 0
```

Once you transfer the RPM to your xCAT server, you should install it.  However, if there is
already an xCAT-genesis-base-* RPM for your architecture installed, you will have to uninstall
it first using the command below, assuming x86_64 architecture.  We use the 
`--nodeps` option as the uninstall will fail due to other dependencies.

```sh
rpm -e --nodeps xCAT-genesis-base-x86_64*
```

To install the new RPM, issue the following command, using the 2.16.10 example from above:

```sh
rpm -ivh xCAT-genesis-base*.rpm
```

Now, assuming that the architecture that you have built the `xCAT-genesis-base` for was `ppc64`,
you would then, on the xCAT server run the following command:

```sh
mknb ppc64
```

At this point in time, you can discover nodes by following https://xcat-docs.readthedocs.io/en/stable/guides/admin-guides/manage_clusters/ppc64le/discovery/mtms/discovery.html

# Open Source License

xCAT is made available under the EPL license: https://opensource.org/licenses/eclipse-1.0.php

# Developers

Want to help? Check out the [developers guide](http://xcat-docs.readthedocs.io/en/latest/developers)!

