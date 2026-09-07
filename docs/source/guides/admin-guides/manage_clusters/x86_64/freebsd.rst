FreeBSD stateful installation
=============================

This installation path targets FreeBSD 15.1-RELEASE on amd64 nodes. The xCAT
architecture name is ``x86_64``. The management node and service nodes remain
Linux systems.

xCAT starts a scripted installation in mfsBSD. The installed system boots from
its own disk. The boot sequence is::

    PXE firmware -> xNBA -> FreeBSD loader -> mfsBSD -> bsdinstall -> local disk

This is not SAN boot. No remote block device supplies the installed root
filesystem. The DHCP ``root-path`` option supplies a TFTP directory to the
FreeBSD loader; it does not select an NFS root or an iSCSI disk.

Scope and requirements
----------------------

* Use ``netboot=xnba`` and an imported ``imagetype=freebsd`` installation image.
* Select one disk by its FreeBSD device name and hardware serial. Automatic disk
  selection is not available. Installation replaces the selected disk contents.
* Select a single-disk ZFS root pool or UFS. ZFS mirrors, RAID-Z, encryption,
  multi-disk layouts, and Linux ZFS provisioning are outside this implementation.
* Use IPv4 and one provisioning interface selected by MAC address. The installed
  system receives static addressing from the xCAT database. The node name must
  resolve to that interface's address, and reverse resolution must identify the
  same xCAT node. Status callbacks must retain that source address without NAT.
* Use one installation owner per node. Nodes assigned to a service node require
  an explicit, single ``xcatmaster``. State and boot publication must run there.
* Serve DHCP, TFTP, and HTTP from that same host. Remote file-service offload and
  automatic controller failover are not available.
* Use an isolated, trusted provisioning network. Configuration and release sets
  use HTTP; the loader pins the configuration checksum and the installer checks
  the release-set checksums. These checks do not authenticate the provisioning
  network itself.
* Supply plain SSH public keys. Password login is disabled on the installed
  system. Linux postscripts, package lists, diskless images, and service-node
  installation on FreeBSD are not supported by this path.

Prepare the mfsBSD image
------------------------

Build on a FreeBSD 15.1-RELEASE amd64 host as root. Install the build dependencies
required by the selected mfsBSD source revision. Copy the complete
``/opt/xcat/share/xcat/install/freebsd`` directory to the build host.

Obtain matching ``MANIFEST``, ``base.txz``, and ``kernel.txz`` files from the
FreeBSD release. Verify the release source and record the trusted SHA256 of
``MANIFEST`` before building. Select an exact mfsBSD Git commit, not a moving
branch name.

The builder takes five arguments::

    sh freebsd/buildmfsbsd.sh MFSBSD_SOURCE DIST_DIRECTORY OUTPUT_ISO MFSBSD_COMMIT MANIFEST_SHA256

``MFSBSD_COMMIT`` is the full 40-character commit ID. ``MANIFEST_SHA256`` is the
64-character checksum. ``OUTPUT_ISO`` must not already exist. Build paths must
not contain spaces or shell metacharacters.

The builder verifies the release sets, adds the installation runtime, and
produces BIOS and UEFI boot media. It applies a checksum-pinned FreeBSD 15.1
installer cleanup correction for empty mount lists. An unexpected installer
source stops the build.

Copy the ISO to the installation owner and import it::

    copycds /path/to/xcat-mfsbsd.iso
    lsdef -t osimage

Use the image name reported by ``copycds``. The default name includes a media
digest suffix. Imported media resides below
``<installdir>/freebsd15.1/x86_64/<full-digest>``. Do not modify that directory.
Import a new bundle when the runtime or release payload changes.

Define installation policy
--------------------------

Import does not select a disk or an SSH key. Create a protected policy directory
on the installation owner, such as ``/etc/xcat/freebsd``. Policy files, public
key files, and their parent directories must be owned by root and must not be
writable by other users. Symlink paths are not accepted.

The image ``template`` attribute selects a key=value settings file. For example,
``/etc/xcat/freebsd/settings`` contains::

    authorized_keys_file=/etc/xcat/freebsd/administrators.pub

The public key file accepts plain OpenSSH keys, without authorized_keys options.
It does not accept private keys.

Create a disk policy for each node. For example,
``/etc/xcat/freebsd/node01.disk`` contains::

    target_disk=da0
    target_disk_ident=REPLACE_WITH_VERIFIED_DISK_SERIAL
    filesystem=zfs
    swap_size=0

Confirm the device name and serial on that node before using this policy. Do not
copy another node's disk identity. Valid device names use ``ada``, ``da``,
``nda``, ``nvd``, or ``vtbd`` followed by a number. ``filesystem`` accepts ``zfs``
or ``ufs``. ``swap_size`` accepts ``0`` or an integer followed by ``M`` or ``G``;
the default is ``0``.

Set the policy paths on the imported image::

    chdef -t osimage -o IMAGE_NAME template=/etc/xcat/freebsd/settings 'partitionfile=/etc/xcat/freebsd/#NODE#.disk'

``#NODE#`` expands to the xCAT node name. These files are not shell scripts and
do not use the Linux installation-template syntax.

Configure and install a node
----------------------------

Define the node address, MAC, and matching ``networks`` entry through the normal
xCAT configuration commands. Every enabled IPv4 ``networks`` entry must have a
valid, contiguous dotted-decimal mask, including entries for other subnets.
Exactly one network entry must match the node.
Configure a gateway in the node subnet if an installation endpoint is outside
that subnet.

Select xNBA and the provisioning MAC::

    chdef node01 netboot=xnba installnic=mac

The MAC table must identify one unambiguous provisioning MAC. If the node has
several eligible MAC addresses, set ``installnic`` to the desired colon-separated
MAC explicitly. Interface names such as ``em0`` are not accepted here.

For a service-node owner, set both attributes explicitly::

    chdef node01 servicenode=sn01 xcatmaster=sn01

The owner must have the imported bundle, policy files, and local DHCP/HTTP/TFTP
services. Retain the normal xCAT ``/install`` HTTP alias, including when
``site.installdir`` points to a different filesystem directory. HTTPS-only
distribution service is not supported by the initial runtime.

Prepare the installation, update DHCP, and boot the node::

    nodeset node01 osimage=IMAGE_NAME
    makedhcp node01
    rpower node01 boot

Do not boot the node if preparation or DHCP configuration reports an error.
Remove ``bootparams.addkcmdline`` settings before preparation; this path does
not accept Linux kernel arguments.
An invalid FreeBSD image detected during preflight stops a mixed-node request
before any installation image is prepared.

An explicit iSCSI server and target conflict with this installation path and
cause preparation to fail. Remove an obsolete SAN configuration only after
confirming that the node no longer uses it.

The installer verifies configuration, release sets, the provisioning interface,
and disk ownership before requesting permission to start. Imported ZFS pools,
attached GELI providers, and ambiguous existing storage cause a failure before
partitioning. Completion requires xCAT to select disk boot and acknowledge the
status update. A first-boot service reports that the installed system started.
It runs in the background, logs errors through syslog, and leaves reporting
pending after a timeout so that the next boot can retry.
The controller handles up to 64 FreeBSD status requests concurrently, with one
worker per node. The installer retries acknowledgments for about 15 minutes.
It does not reboot after installation without a completion acknowledgment.

Failure and retry
-----------------

Inspect the node console and xCAT status after a failed installation. Do not
assume that a failure after installation started left the target disk unchanged.

A repeated preparation with unchanged inputs reuses a prepared generation. An
installation that has started, is completing, or has failed cannot be rearmed
while it may still be running. Stop the node first, cancel the attempt, correct
the cause, and prepare a new installation::

    rpower node01 off
    nodeset node01 offline
    nodeset node01 osimage=IMAGE_NAME
    makedhcp node01
    rpower node01 boot

Installation ownership records reside in ``/var/lib/xcat/freebsd-install`` on
the selected owner. Do not remove these records to bypass an active attempt.
Stop the node before changing its installation owner.
Configuration and boot generations are retained for retry and diagnosis; they
are not automatically deleted after installation.
