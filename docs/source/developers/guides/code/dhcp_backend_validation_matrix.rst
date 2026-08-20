DHCP Backend Validation Matrix
==============================

Purpose
-------

This document defines the default validation matrix for xCAT DHCP backend
changes.

Use this matrix for:

* backend selection changes
* DHCP renderer changes
* reservation add, delete, or query changes
* DDNS and service-management changes
* PXE, xNBA, or boot-policy changes

Acceptance Scope
----------------

The validation result for this matrix is scoped to DHCP backend behavior and
boot handoff:

* backend selection matches the platform policy
* generated backend configuration validates with the backend-native validator
* static reservations allocate correctly, including Kea reservations outside
  ``networks.dynamicrange``
* dynamic pools are emitted only by the DHCP server that owns the network
* the expected bootloader, node script, kernel, initrd, or root image artifacts
  are offered and fetched for the row under test
* shell-oriented rows reach the expected xNBA or Genesis shell state

Failures after the expected boot artifacts have been delivered are image,
initrd, kernel, userspace, or packaging follow-up work. They must be tracked,
but they do not turn the DHCP backend acceptance row red unless the failure is
caused by DHCP policy, allocation, or boot option rendering.

Secure Boot is not part of this matrix. Secure OVMF builds such as
``OVMF_CODE.secboot.fd`` and ``OVMF_VARS.secboot.fd`` must be treated as
unsupported unless xCAT explicitly adds Secure Boot support.

Backend Policy
--------------

The default backend split is:

* EL9, Ubuntu 20.04 LTS, and older supported releases: ``ISC DHCP``
* EL10, Ubuntu 22.04 LTS, and newer supported releases: ``Kea``

``site.dhcpbackend=auto`` must follow that rule. Explicit ``isc`` and ``kea``
overrides remain available for development and troubleshooting.

Always-Run Checks
-----------------

Run these checks for every DHCP backend change before live validation:

* Perl syntax checks for changed DHCP modules
* unit tests for backend selection, range handling, boot policy, and renderer
  behavior
* Kea version-aware renderer checks when client classification is touched:

  * Kea 2.4 output must use ``only-if-required`` and
    ``require-client-classes``
  * Kea 3.x output must use ``only-in-additional-list`` and
    ``evaluate-additional-classes``
  * Kea UEFI x86_64 boot classes must cover PXE architecture ids ``0x0007``
    and ``0x0009`` plus UEFI HTTP boot architecture id ``0x0010``

* backend-native configuration validation:

  * ``dhcpd -t -cf <config>`` for ISC
  * ``kea-dhcp4 -t <config>`` for Kea DHCPv4
  * ``kea-dhcp6 -t <config>`` for Kea DHCPv6 when used
  * ``kea-ctrl-agent -t <config>`` for Control Agent when used
  * ``kea-dhcp-ddns -t <config>`` for D2 when used

Default Live Matrix
-------------------

The following matrix is the default live validation gate for DHCP backend work.

.. list-table::
   :header-rows: 1
   :widths: 14 10 10 18 48

   * - Platform
     - Arch
     - Backend
     - Boot Validation
     - Minimum Required Checks
   * - EL9
     - ``x86_64``
     - ``ISC``
     - ``xNBA shell``
     - ``makedhcp -n``; ``dhcpd -t``; reservation add/query/delete; DHCP/TFTP;
       node-specific xNBA handoff; Genesis fetch
   * - Ubuntu 20.04 LTS
     - ``x86_64``
     - ``ISC``
     - ``xNBA shell``
     - ``makedhcp -n``; ``dhcpd -t``; reservation add/query/delete; DHCP/TFTP;
       node-specific xNBA handoff; Genesis fetch
   * - Ubuntu 22.04 LTS
     - ``x86_64``
     - ``Kea``
     - ``xNBA shell`` and compute-image handoff
     - ``makedhcp -n``; ``kea-dhcp4 -t``; reservation add/query/delete;
       xNBA shell boot; compute-image boot artifact handoff through kernel,
       initrd, and root image when image validation is in scope
   * - EL10
     - ``x86_64``
     - ``Kea``
     - ``xNBA shell`` and compute-image handoff
     - ``makedhcp -n``; ``kea-dhcp4 -t``; reservation add/query/delete;
       xNBA shell boot; compute-image boot artifact handoff through kernel,
       initrd, and root image when image validation is in scope
   * - Ubuntu 24.04 LTS
     - ``x86_64``
     - ``Kea``
     - ``xNBA shell`` and compute-image handoff
     - ``makedhcp -n``; ``kea-dhcp4 -t``; reservation add/query/delete;
       xNBA shell boot; compute-image boot artifact handoff through kernel,
       initrd, and root image when image validation is in scope
   * - Ubuntu 26.04 LTS
     - ``x86_64``
     - ``Kea``
     - ``xNBA shell`` and compute-image handoff
     - ``makedhcp -n``; ``kea-dhcp4 -t``; reservation add/query/delete;
       xNBA shell boot; stateful subiquity and stateless compute-image handoff
       through kernel, initrd, and root image when image validation is in scope

Kea Boot and Reservation Regression Matrix
------------------------------------------

Run this matrix whenever a change touches Kea boot policy, client
classification, address pools, or host reservations.

.. list-table::
   :header-rows: 1
   :widths: 20 18 62

   * - Scenario
     - Backend Scope
     - Minimum Required Checks
   * - BIOS PXE/xNBA
     - ``ISC`` and ``Kea`` when touched
     - DHCP offer for architecture ``0x0000``; expected BIOS loader
       ``pxelinux.0`` or ``xcat/xnba.kpxe``; xNBA second-stage URL when the
       client returns with user-class ``xNBA``.
   * - UEFI PXE architecture ``0x0007``
     - ``Kea``
     - Client matches ``xcat-uefi-x64``; offer includes ``xcat/xnba.efi``;
       node-specific xNBA UEFI second-stage class returns the ``.uefi`` node
       script URL.
   * - UEFI PXE architecture ``0x0009``
     - ``Kea``
     - Same checks as ``0x0007``. This is the alternate x86_64 UEFI PXE
       architecture id observed in the existing xCAT DHCP logic.
   * - UEFI HTTP architecture ``0x0010``
     - ``Kea``
     - Client matches ``xcat-uefi-x64`` and the xNBA UEFI second-stage class;
       validate the DHCP offer against real UEFI HTTP firmware or an
       equivalent DHCP client fixture. The April 26, 2026 validation used a raw
       DHCP fixture with option 93 set to ``0x0010`` and confirmed Kea offered
       the reserved outside-pool address and ``xcat/xnba.efi`` without
       ``ALLOC_FAIL_NO_POOLS``.
   * - Static reservation outside dynamic pool
     - ``Kea``
     - Node address is inside the Kea subnet and outside
       ``networks.dynamicrange``; generated reservation includes
       ``ip-address``; DHCP ACK uses the reserved address; Kea logs do not
       contain ``ALLOC_FAIL_NO_POOLS``.
   * - Static reservation inside dynamic pool
     - ``Kea``
     - Record the expected behavior explicitly. Current ``makedhcp`` treats
       node IPs overlapping ``networks.dynamicrange`` as dynamic and does not
       render a fixed ``ip-address`` reservation. Any change that supports
       in-pool fixed reservations must add live allocation coverage.
   * - Dynamic pool ownership in hierarchy
     - ``Kea``
     - When ``networks.dhcpserver`` is set, only the owning DHCP server renders
       ``networks.dynamicrange`` as Kea pools. Non-owning service nodes may
       render the subnet for reservations and options, but must not render
       duplicate dynamic pools.
   * - Stateful netboot image
     - ``ISC`` and ``Kea`` when touched
     - DHCP/TFTP/HTTP handoff reaches kernel, initrd, root image, and the
       expected xCAT node state.
   * - Stateless netboot image
     - ``ISC`` and ``Kea`` when touched
     - DHCP/TFTP/HTTP handoff reaches the stateless image and validates
       post-boot xCAT state.
   * - ``ALLOC_FAIL_NO_POOLS`` regression
     - ``Kea``
     - Reproduce a node with static reservation and no usable dynamic pool;
       confirm Kea still allocates the reserved address and no allocation
       failure is logged.

Extended Architecture Matrix
----------------------------

Run the extended matrix when a change touches architecture-specific boot logic,
client classification, firmware-specific file paths, or non-``x86_64`` code
paths.

.. list-table::
   :header-rows: 1
   :widths: 14 10 10 18 48

   * - Platform
     - Arch
     - Backend
     - Boot Validation
     - Minimum Required Checks
   * - EL10
     - ``ppc64le``
     - ``Kea``
     - ``POWER GRUB handoff``
     - DHCP offer; boot file handoff; POWER boot-path correctness; Genesis
       shell when Genesis payload validation is in scope
   * - Ubuntu 26.04 LTS
     - ``ppc64le``
     - ``Kea``
     - ``POWER GRUB handoff``
     - package installation on ``ppc64el``; DHCP offer; boot file handoff;
       POWER boot-path correctness; Genesis shell when live validation is in
       scope
   * - EL10
     - ``riscv64``
     - ``Kea``
     - ``UEFI grub2 handoff``
     - DHCP offer carries ``boot/grub2/grub2.riscv64`` for client
       architecture 27 (``0x001b``); ``grub2.riscv64`` fetches
       ``boot/grub2/grub.cfg-<hex network prefix>`` for discovery and the
       per-node ``grub.cfg-<hex ip>`` after ``nodeset``; Genesis shell when
       Genesis payload validation is in scope
   * - EL10
     - ``riscv64``
     - ``ISC``
     - ``UEFI grub2 handoff``
     - same as the Kea row through the ISC subnet branch for client
       architecture ``00:1b``; the riscv64 branch must answer before the
       ``/yaboot`` fallback

Current Lab Baseline
--------------------

KVM validation should cover both ``x86_64`` and ``ppc64le`` hosts. Record the
repeatable lab access method privately with the validation run instead of
embedding site-specific hostnames or credentials in this repository.

Full Ubuntu 24.04 ``x86_64`` stateless KVM validation required Ubuntu
``genimage`` fixes for early BOOTIF handling and a lean initrd driver set.
Those image-generation fixes are tracked separately from the Kea DHCP backend
policy changes.

Known Exceptions
----------------

Known blockers do not remove the matrix requirement. They must be recorded
explicitly in the validation result. A blocker only turns a DHCP acceptance row
red when the root cause is DHCP backend policy, allocation, or boot option
rendering.

Current exceptions:

* Ubuntu 22.04 LTS ISC OMAPI/``omshell`` host reservation updates are
  unreliable on current upstream code and are not caused by the Kea backend
  work. ``site.dhcpbackend=auto`` therefore selects Kea for Ubuntu 22.04 and
  newer releases; live Ubuntu 22.04 Kea validation remains a follow-up matrix
  row.
* Ubuntu ``ppc64le`` package installation is missing required boot packages such
  as ``goconserver``, ``grub2-xcat``, and ``xcat-genesis-base-ppc64``. This is
  tracked separately and is not a Kea DHCP behavior issue.

Current PR Validation Snapshot
------------------------------

As of April 26, 2026, this PR has the following DHCP backend acceptance result
for the supported KVM rows. All rows in this table are green for the DHCP
backend scope described above.

.. list-table::
   :header-rows: 1
   :widths: 16 10 12 18 12 32

   * - Platform
     - Arch
     - Backend
     - Boot Path
     - Result
     - Notes
   * - EL9
     - ``x86_64``
     - ``ISC``
     - BIOS PXE/xNBA
     - Pass
     - DHCP/TFTP, node-specific xNBA handoff, Genesis shell, and compute-image
       validation passed.
   * - EL9
     - ``x86_64``
     - ``ISC``
     - UEFI PXE/xNBA
     - Pass
     - Non-Secure-Boot UEFI DHCP/TFTP, node-specific xNBA handoff, Genesis
       shell, and compute-image validation passed.
   * - EL9
     - ``ppc64le``
     - ``ISC``
     - POWER GRUB/Genesis
     - Pass
     - DHCP/TFTP/GRUB handoff fetched ``genesis.kernel.ppc64`` and
       ``genesis.fs.ppc64.gz``; node reached the Genesis shell.
   * - EL10
     - ``x86_64``
     - ``Kea 3.0.1``
     - BIOS PXE/xNBA
     - Pass
     - Static reservation outside ``networks.dynamicrange`` allocated; no
       ``ALLOC_FAIL_NO_POOLS``; xNBA shell passed; regenerated compute-image
       boot reached ``sshd`` with ``selinux=0`` in the command line.
   * - Ubuntu 24.04 LTS
     - ``x86_64``
     - ``Kea 2.4.1``
     - BIOS PXE/xNBA
     - Pass
     - Static reservation outside ``networks.dynamicrange`` allocated; no
       ``ALLOC_FAIL_NO_POOLS``; xNBA shell passed; compute-image boot fetched
       ``rootimg.cpio.gz`` and reached ``sshd`` with ``netdrivers=overlay``.
   * - EL10
     - ``x86_64``
     - ``Kea 3.0.1``
     - UEFI PXE/xNBA
     - Pass
     - Non-Secure-Boot UEFI path matched the Kea x86_64 UEFI boot policy;
       regenerated compute-image boot reached ``sshd`` with ``selinux=0`` in
       the command line.
   * - EL10
     - ``x86_64``
     - ``Kea 3.0.1``
     - UEFI HTTP arch ``0x0010``
     - Pass
     - Raw DHCP fixture on the KVM provisioning bridge sent option 93
       ``0x0010`` from the reserved outside-pool node MAC and received lease
       ``10.241.10.22`` with boot file ``xcat/xnba.efi``; no
       ``ALLOC_FAIL_NO_POOLS`` was observed.
   * - Ubuntu 24.04 LTS
     - ``x86_64``
     - ``Kea 2.4.1``
     - UEFI PXE/xNBA
     - Pass
     - Non-Secure-Boot UEFI path matched the Kea x86_64 UEFI boot policy;
       xNBA shell passed; compute-image boot fetched ``rootimg.cpio.gz`` and
       reached ``sshd`` with the separate Ubuntu ``genimage`` fixes applied.
   * - EL10
     - ``ppc64le``
     - ``Kea 3.0.1``
     - POWER GRUB/Genesis
     - Pass
     - Static reservation outside ``networks.dynamicrange`` allocated; no
       ``ALLOC_FAIL_NO_POOLS``; TFTP/GRUB handoff passed; original EL10
       ``genesis.kernel.ppc64`` and ``genesis.fs.ppc64.gz`` reached xCAT
       ``shell`` state after replacing the broken ``grub2-xcat 1.0-3`` ppc
       GRUB core/module tree with the coherent
       ``2.02-0.76.el7.1.snap201905160255`` tree. The remaining follow-up is
       package provenance for ``grub2-xcat``, not DHCP or Genesis payload
       behavior.
   * - Ubuntu 24.04 LTS
     - ``ppc64le``
     - ``Kea 2.4.1``
     - POWER GRUB/Genesis
     - Pass
     - Static reservation outside ``networks.dynamicrange`` allocated; no
       ``ALLOC_FAIL_NO_POOLS``; DHCP/TFTP/GRUB handoff passed and the node
       reached Genesis with the temporary EL9 ppc64le payload workaround.

Ubuntu LTS KVM Validation Snapshot
----------------------------------

As of May 1, 2026, the Ubuntu LTS KVM validation for the Ubuntu
provisioning restoration work has the following result:

.. list-table::
   :header-rows: 1
   :widths: 14 9 9 12 12 12 12 30

   * - Platform
     - Arch
     - Backend
     - BIOS Stateless
     - BIOS Stateful
     - UEFI Stateless
     - UEFI Stateful
     - Notes
   * - Ubuntu 18.04 LTS
     - ``x86_64``
     - ``ISC``
     - Pass
     - Pass
     - Pass
     - Pass
     - Stateless and stateful compute boots passed against an Ubuntu 18.04
       headnode. The 18.04 debian-installer initrd did not include
       ``virtio_blk`` in this KVM environment, so stateful VMs used
       ``virtio-scsi`` disks. The legacy preseed disables installer
       update/security services so stateful installs and ``apt-get update``
       use only the local xCAT install media. Persistent interface naming used
       ``R::net.ifnames=0 R::biosdevname=0``.
   * - Ubuntu 20.04 LTS
     - ``x86_64``
     - ``ISC``
     - Pass
     - Pass
     - Pass
     - Pass
     - Stateless and stateful compute boots passed. Stateful validation used a
       manual static reservation workaround for the known forced-ISC OMAPI
       issue.
   * - Ubuntu 22.04 LTS
     - ``x86_64``
     - ``Kea``
     - Pass
     - Pass
     - Pass
     - Pass
     - Stateless and stateful compute boots passed. Kea 2.0.2 configuration
       validation with ``kea-dhcp4 -t`` passed on the Ubuntu 22.04 headnode.
       ``makedns -n`` starts ``bind9`` successfully, and the DHCP section of
       ``xcatprobe xcatmn`` passed on consecutive runs.
   * - Ubuntu 24.04 LTS
     - ``x86_64``
     - ``Kea``
     - Pass
     - Pass
     - Pass
     - Pass
     - Stateless and stateful compute boots passed. Kea 2.4.1 configuration
       validation with ``kea-dhcp4 -t`` passed on the Ubuntu 24.04 headnode.
       ``makedns -n`` starts ``bind9`` successfully, and the DHCP section of
       ``xcatprobe xcatmn`` passed on consecutive runs. UEFI validation used
       OVMF Secure Boot disabled.
   * - Ubuntu 26.04 LTS
     - ``x86_64``
     - ``Kea``
     - Pass
     - Pass
     - Pass
     - Pass
     - Stateless and stateful compute boots passed against an Ubuntu 26.04
       headnode. Kea 3.0.3 configuration validation with ``kea-dhcp4 -t``
       passed. Stateless BIOS and UEFI nodes reached ``sshd`` after the
       netboot image was repacked with the recursive postscript download fix;
       stateful BIOS and UEFI nodes completed Subiquity install and booted from
       disk. Kea logs showed no ``ALLOC_FAIL_NO_POOLS``. UEFI validation used
       OVMF Secure Boot disabled.

Follow-up Tracking
------------------

These issues are outside the DHCP acceptance result but must be referenced when
reporting this validation run:

.. list-table::
   :header-rows: 1
   :widths: 12 22 66

   * - Issue
     - Area
     - Impact
   * - Ubuntu ``ppc64le`` packages
     - Ubuntu ``ppc64le`` packages
     - Missing ``goconserver``, ``grub2-xcat``, and
       ``xcat-genesis-base-ppc64`` block clean Ubuntu ppc64le package
       installation.
   * - ``ppc64le`` GRUB package
     - ``ppc64le`` GRUB package
     - EL10 ppc64le fails with ``grub2-xcat 1.0-3`` because its POWER GRUB
       core/module tree cannot load the ppc64le Genesis kernel. The live row is
       green after hotpatching the TFTP GRUB tree to
       ``2.02-0.76.el7.1.snap201905160255`` while keeping the original EL10
       Genesis payload.

Reporting Rule
--------------

Every DHCP backend PR should summarize validation using this matrix:

* what rows were run
* what passed
* what failed
* what was blocked by a known external issue

If a row was skipped, the PR should state why.
