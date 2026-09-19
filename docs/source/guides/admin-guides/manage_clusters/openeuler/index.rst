openEuler
=========

This page describes the openEuler installation and image profiles.
Release and role qualification is still in progress; this page does not
declare a completed support matrix.

Release targets
---------------

Qualification uses one service pack from each LTS release:

.. list-table::
   :header-rows: 1

   * - Release
     - Architecture
     - xCAT OS name
   * - 20.03 LTS SP4
     - x86_64
     - ``openeuler20.03sp4``
   * - 22.03 LTS SP4
     - x86_64
     - ``openeuler22.03sp4``
   * - 24.03 LTS SP4
     - x86_64
     - ``openeuler24.03sp4``
   * - 24.03 LTS GA
     - ppc64le
     - ``openeuler24.03``

These service packs are fixed for this delivery. Earlier service packs
do not require a separate full qualification matrix. The POWER GA image
is a functional target; its qualification does not establish maintained
POWER service-pack support. Consult the distribution's maintenance policy
separately.

Keep the complete OS name in node, image and repository definitions.
For example, ``openeuler24.03sp4`` must not be shortened to
``openeuler24`` or replaced with an EL version. Profile lookup prefers
the exact service pack, then its LTS release, then the generic openEuler
profile. It does not select a profile from another service pack.

Management-node packages
------------------------

Use native openEuler RPMs for the selected release and architecture.
Prepare signed xcat-core, xcat-dep and distribution repositories, including
the native dependency packages needed by the selected roles. An EL
repository does not supply the openEuler dependency closure.

The native repository target is ``<osname>/<architecture>``, for example
``openeuler24.03sp4/x86_64``. Configure repository files with the matching
base URLs, trusted signing keys and ``gpgcheck=1``. Then use the normal
bootstrap command with those files::

    ./go-xcat --xcat-core=/path/to/xcat-core.repo \
              --xcat-dep=/path/to/xcat-dep.repo --yes install

For an offline installation, make the complete signed dependency closure
available locally before running this command. Preserve the repository
metadata, package versions and signing-key fingerprints with the installation
record. This page does not identify a published openEuler package channel.

Follow :doc:`/guides/install-guides/yum/configure_xcat` for site configuration
and :doc:`/guides/install-guides/yum/verify_xcat` for management-node checks.
openEuler uses the ISC DHCP backend. Configure the provisioning interfaces
explicitly before starting DHCP.

Media and installed nodes
-------------------------

Import the official DVD without an OS-name override. For 24.03 SP4::

    copycds -i /path/to/openEuler-24.03-LTS-SP4-x86_64-dvd.iso
    copycds -w /path/to/openEuler-24.03-LTS-SP4-x86_64-dvd.iso
    lsdef -t osimage openeuler24.03sp4-x86_64-install-compute

The import creates compute and service installation images, a compute
netboot image, and a management-node profile. It does not create StateLite
images. Review ``pkgdir``, ``pkglist``, ``template`` and ``otherpkgdir`` before
using an image. Put custom assets under ``/install/custom`` and select them
through the image attributes.

After defining the node's network, target disk and hardware-control method,
select the installation image and boot the node::

    nodeset cn01 osimage=openeuler24.03sp4-x86_64-install-compute
    rpower cn01 boot

Check the installation status, executed postscripts and installed disk boot.
Keep the imported native repositories available for installation and updates.
The openEuler post-installation path disables the distribution's default
``openEuler.repo`` file in the resulting system.

Stateless compute images
-------------------------

Build the image on an openEuler host of the target architecture, using its
native kernel, modules and package repositories. Check the image's network
drivers and interface settings before generation. For the imported compute
profile::

    genimage openeuler24.03sp4-x86_64-netboot-compute
    packimage -m cpio -c gzip openeuler24.03sp4-x86_64-netboot-compute
    nodeset cn01 osimage=openeuler24.03sp4-x86_64-netboot-compute
    rpower cn01 boot

The commands above select the cpio/gzip image path. Other pack formats need
their own qualification. Preserve the previous packed image before updating
it. Verify a second network boot, loss of transient root contents, an image
update and rollback. Image generation alone does not verify node operation.

Service nodes
-------------

Use MariaDB or PostgreSQL on the management node before deploying service
nodes. SQLite is for standalone management-node operation. Install the
matching native database client modules on each service node; a PostgreSQL
client package does not provide a PostgreSQL server.

Use the normal :doc:`/advanced/hierarchy/index` procedures for database
credentials, service-node definitions, resource sharing and downstream
ownership. Configure the downstream interface before activating its services.
When that interface needs ``confignetwork``, order the node's postscripts as
``confignetwork,servicenode``.

The installed service profile is
``openeuler24.03sp4-x86_64-install-service``. Its other-package list expects
these repository paths below ``otherpkgdir``::

    xcat/xcat-core/openeuler24.03sp4/x86_64/
    xcat/xcat-dep/openeuler24.03sp4/x86_64/

Each directory needs its RPMs and repository metadata. The selected service
profile supplies ``xCATsn`` and ``goconserver`` through these repositories.

Create a diskless service image from the imported compute template, then
select every service asset explicitly::

    mkdef -t osimage -o oe24-service \
        --template openeuler24.03sp4-x86_64-netboot-compute \
        profile=service provmethod=netboot
    chdef -t osimage oe24-service \
        pkglist=/opt/xcat/share/xcat/netboot/openeuler/service.openeuler.pkglist \
        exlist=/opt/xcat/share/xcat/netboot/openeuler/service.openeuler.exlist \
        postinstall=/opt/xcat/share/xcat/netboot/openeuler/service.openeuler.postinstall \
        otherpkglist=/opt/xcat/share/xcat/netboot/openeuler/service.openeuler24.03sp4.x86_64.otherpkgs.pkglist \
        otherpkgdir=/install/post/otherpkgs/openeuler24.03sp4/x86_64 \
        rootimgdir=/install/netboot/openeuler24.03sp4/x86_64/oe24-service

Set the service-node network and postscript attributes, then run ``genimage``
and ``packimage`` for ``oe24-service``. The imported definitions do not include
a ``netboot-service`` template. Build a separate image for each selected
release and architecture.

Verify both service-node forms after reboot, including remote database writes
and provisioning of installed and stateless downstream nodes. Follow
:doc:`/advanced/hierarchy/provision/verify_sn` for service checks. Resource
replication and manual takeover require their own configured paths and tests.

Discovery, security and upgrades
--------------------------------

Install Genesis packages for each payload architecture served by the
management node. ``mknb x86_64`` and ``mknb ppc64le`` use different payloads.
An openEuler Genesis build requires native UTF-8 locale data for its terminal
multiplexer. A successful ``mknb`` command must be followed by an actual
discovery boot, registration and subsequent provisioning.

The current validation configuration disables SELinux and the host firewall.
It uses signed packages, TLS client authorization, SSH keys and secure-root
mode. Enforcing SELinux and a host firewall policy are not qualified by these
results. Keep the provisioning network isolated and configure access for the
services selected in the site and hierarchy definitions.

Before an xCAT RPM upgrade, back up the database, ``/etc/xcat`` and customized
service and image configuration. Keep xcatd running during CSV database
restore. Check restore errors and table contents, then verify services and
data after reboot. Use the native repositories with the normal
:doc:`/guides/install-guides/yum/update_xcat` procedure.

An xCAT RPM upgrade does not qualify an operating-system service-pack upgrade.
Document each supported OS transition separately; no cross-LTS in-place
upgrade or downgrade is implied. POWER PostgreSQL server availability and
physical firmware qualification remain unresolved requirements. Virtual
firmware results do not establish physical BIOS, UEFI or Petitboot support.
