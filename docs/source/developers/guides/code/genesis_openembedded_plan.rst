Genesis on OpenEmbedded
========================

Genesis is the small Linux environment that xCAT boots before a node has an
installed operating system.  It discovers the node, enrolls it with xCAT, and
runs the action assigned by the management node.

Older Genesis images inherit their kernel, CPU baseline, drivers, and package
choices from a general-purpose distribution.  This implementation uses an
xCAT-owned OpenEmbedded layer instead.  The same layer builds every supported
architecture, while each architecture still has its own kernel and userspace
artifacts.

Build base
----------

The build uses the Yocto Project 6.0 Wrynose LTS series, glibc, systemd, and an
xCAT kernel configuration.  Wrynose is the OpenEmbedded release series.  The
xCAT distribution codename is ``cheetah``.

KAS checks out exact tags and commits from ``oe/kas/common.yml``.  Release
branches are not used as floating build inputs.  Updates within the 6.0 series
arrive as reviewed changes to those pins, so an old commit can always rebuild
the same source tree.

The kernel release ends in ``-xCAT-genesis``.  Names such as
``yocto-standard`` are build details and do not appear in the installed kernel
identity.

Supported architectures
-----------------------

.. list-table::
   :header-rows: 1

   * - Artifact
     - Baseline
     - Validation
   * - ``x86_64``
     - x86-64-v1
     - QEMU and physical hardware
   * - ``ppc64le``
     - Little-endian POWER8
     - QEMU and physical hardware
   * - ``x86``
     - 32-bit i686
     - QEMU
   * - ``ppc64``
     - 64-bit big-endian PowerPC ELFv1
     - QEMU
   * - ``armv7hf``
     - ARMv7-A hard-float
     - QEMU
   * - ``aarch64``
     - ARMv8-A
     - QEMU
   * - ``riscv64``
     - RV64GC with OpenSBI
     - QEMU ``virt``

``x86_64`` is the first release target and ``ppc64le`` is the second because
both have physical test systems.  The other targets have the same software
contract, but emulation does not prove support for physical firmware, device
trees, or controllers.

Architecture names are exact.  In particular, ``ppc64`` and ``ppc64le`` are
different artifacts.  The build does not preserve the old xCAT alias between
them.  ``riscv32``, pre-ARMv7 processors, and i586-only x86 processors are not
supported.

Networking
----------

NetworkManager owns the Genesis network state and uses its internal DHCP
client.  The image does not contain ``dhclient``, ``dhcpcd``, or
``systemd-networkd``.  Kea is a DHCP server on the xCAT side and is unrelated
to the DHCP client in Genesis.

The NetworkManager build keeps Ethernet, IP over InfiniBand, bonds, VLANs,
bridges, DHCPv4, DHCPv6, and IPv6 autoconfiguration.  Desktop, Wi-Fi, WWAN,
Bluetooth, PPP, VPN, cloud, and interactive UI features are disabled.

Genesis prefers the interface named by ``BOOTIF``.  It can also select an
interface that reaches the configured xCAT server, renew a lease after node
assignment, and handle static network settings passed on the kernel command
line.  DNS, routes, MTU, and addresses come from NetworkManager state.

The Genesis clients and discovery sender accept IPv4 and IPv6 endpoints.  An
IPv6-only deployment also needs matching support in xCAT server code, DHCP,
boot firmware, and boot configuration.  Those changes are outside this layer
and must not be hidden inside the Genesis image.

xCAT protocol
-------------

Genesis keeps the existing xCAT XML protocol for ``getdestiny``,
``nextdestiny``, discovery, and certificate enrollment.  JSON is not used on
the xcatd wire protocol.

The boot sequence is split into ordered systemd services:

#. NetworkManager configures candidate interfaces.
#. The network state service selects a management path.
#. Registration asks xcatd for the node destiny.
#. Discovery sends inventory when the node is not assigned.
#. The action service handles the operation returned by xCAT.

Runtime status is written as small key-value records below
``/run/xcat/status``.  The console reads those records but does not control the
services.

Shell code
----------

Bash is an intentional runtime dependency.  The orchestration and provider
scripts use arrays, ``[[ ... ]]``, ``pipefail``, and other Bash features.  They
use ``#!/bin/bash`` and do not depend on what a distribution links to
``/bin/sh``.  Ubuntu's use of Dash for ``/bin/sh`` therefore has no effect on
Genesis.

Small helpers that need only POSIX shell keep a ``/bin/sh`` shebang.  The
runtime scripts source a packaged ``genesis-functions`` library for shared
status, timer, destiny, and component-state handling.

Status console
--------------

The normal console is a C17 program linked directly to libnewt.  Its layout is
similar to the text interfaces used by Red Hat installers.  A plain renderer
uses the same state model and field formatting, which prevents the two modes
from defining separate status semantics.

The main page shows information needed while a node is being provisioned:

* current state, activity, and time in the state
* assigned node name and firmware serial
* management interface, link, address, method, and MAC address
* xCAT endpoint and the result of the last contact
* assigned action, target, progress, error, and recovery text

Inventory such as the kernel, release, architecture, firmware, extensions,
and provider availability is on the diagnostics page.  The log page reads
journald directly.  It follows new records while the cursor is at the end;
scrolling up pauses following until the operator presses ``End``.

``F1`` opens help, ``F2`` opens diagnostics, ``F3`` opens logs, and ``F12``
opens a confirmed root maintenance shell.  Exiting the shell returns to the
console.  Plain mode accepts the ``shell`` command when it is attached to an
interactive terminal.  Both paths use the same maintenance-shell launcher.

Newt mode expects an 80 by 24 VT100-compatible terminal.  Timers update once
per second without repainting stable fields.  A periodic full repaint allows
a late serial attachment to recover.

The console source has separate modules for state collection, Newt rendering,
plain rendering, support functions, and shell handling.  Meson builds it as
C17 with compiler warnings treated as errors.  C17 affects source semantics;
the OpenEmbedded machine configuration still controls the CPU baseline of the
resulting binary.

Local structured data
---------------------

JSON is used for two local, versioned interfaces:

* hardware provider manifests and provider results
* signed system extension manifests

These records need typed booleans, lists, strict schemas, and safe parsing.
They are consumed locally with ``jq`` or ``JSON::PP`` and are not an
OpenEmbedded requirement.  JSONL is also used for hardware-operation audit
records.  Yocto produces SPDX JSON independently as part of its software bill
of materials support.

Kea configuration is JSON because Kea defines that format.  This is separate
from both the Genesis-local records and the xCAT XML protocol.

Hardware support
----------------

The base image contains upstream kernel drivers and redistributable open
utilities needed for discovery and service work.  The initial tool set covers
PCI, USB, DMI, networking, RDMA, storage, NVMe, SCSI, IPMI, and common
diagnostics.  Open-source ``mstflint`` is part of this base.  ``iprutils`` is
included where it applies.

Hardware operations use provider manifests.  A provider declares its name,
version, kind, capabilities, and whether each capability is destructive.
Provider output is bounded and validated before Genesis returns it to xCAT.
Destructive operations require an explicit task and produce an audit record.

Vendor tools
------------

Tools such as StorCLI, PERCCLI, SSACLI, ARCCONF, NVIDIA drivers, NVIDIA MFT,
and AMD management software may be added as signed system extensions.  They
are not part of the public base image unless their license permits
redistribution.

An extension is tied to a Genesis release and architecture.  Its manifest
also records its digest, signing key, license class, capabilities, and
supported PCI identifiers.  Extensions containing kernel modules must match
the exact Genesis kernel release.

Genesis verifies Ed25519 signatures before loading extensions with
``systemd-sysext``.  It does not download vendor software while booting.  A
site may build a restricted extension from an authorized private source
mirror when the vendor license forbids public redistribution.

The extension exporter binds the image, manifest, signature, public key, and
checksums into one directory.  A site layer adds that directory to the
``xcat-genesis-extensions`` recipe and sets
``XCAT_GENESIS_EXTENSION_BUNDLE`` to its name.  The signing key remains
outside both the bundle and the source repository.

Licensing and release records
-----------------------------

The image is a multi-license aggregate.  xCAT code remains under EPL-1.0, and
each included component keeps its own license.  OpenEmbedded checks recipe
licenses and blocks recipes protected by ``LICENSE_FLAGS`` until the builder
accepts them explicitly.

Each release records source revisions, patches, configuration, artifact
checksums, licenses, an SPDX software bill of materials, and a VEX report.
The build uses the Yocto release key stored in this repository and verifies
its fingerprint; it does not contact a public keyserver.

xCAT server boundary
--------------------

The OpenEmbedded layer builds and exports a kernel, compressed initramfs,
checksums, reports, and optional signed extensions.  Installing those
artifacts and writing network boot configuration belongs to xCAT server code.

Server integration should be reviewed separately from the image.  Independent
bugs found while testing Genesis, such as TFTP path handling or Kea policy,
also belong in their own changes.  This keeps the image review from becoming a
general xCAT server review and gives sites that do not use Genesis smaller,
clearer updates.

Validation
----------

Every architecture must pass a clean build from pinned sources, QEMU boot,
systemd health checks, artifact checksum checks, and tests for the supported
network and xCAT protocol paths.  Tests also cover invalid signatures, wrong
architectures, mismatched releases, malformed provider output, and unknown
actions.

``x86_64`` and ``ppc64le`` require physical tests before release.  VM tests
cannot certify platform firmware, BMC behavior, storage-controller tools,
RDMA firmware operations, GPUs, Secure Boot on vendor firmware, or
board-specific device trees.

References
----------

* `Yocto Project 6.0 release notes
  <https://docs.yoctoproject.org/6.0/migration-guides/release-notes-6.0.html>`_
* `KAS project configuration
  <https://kas.readthedocs.io/en/latest/userguide/project-configuration.html>`_
* `NetworkManager dispatcher interface
  <https://networkmanager.dev/docs/api/latest/NetworkManager-dispatcher.html>`_
* `NetworkManager initrd generator
  <https://networkmanager.dev/docs/api/latest/nm-initrd-generator.html>`_
* `systemd system extensions
  <https://www.freedesktop.org/software/systemd/man/latest/systemd-sysext.html>`_
* `Yocto Project license controls
  <https://docs.yoctoproject.org/6.0/dev-manual/licenses.html>`_
