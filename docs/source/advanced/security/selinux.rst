SELinux
=======

xCAT runs with SELinux enforcing on the management node and on a diskful compute or
service node. A stateless node runs with SELinux disabled.

xCAT never changes the SELinux mode. ``xcatconfig`` reads the mode and reports it, and
``/etc/selinux/config`` belongs to the site.

What the cluster gets
---------------------

================= ========================= ==========================================
Machine           Provisioning method        SELinux
================= ========================= ==========================================
Management node    any                       the mode the site set. Enforcing works
Compute node       diskful (kickstart)       the mode ``noderes.selinux`` resolves
Service node       diskful (kickstart)       the mode ``noderes.selinux`` resolves
Compute node       stateless (netboot)       disabled. ``nodeset`` says why
Compute node       statelite                 disabled
================= ========================= ==========================================

This covers the OS families that ship an SELinux policy: RHEL and its rebuilds, Fedora
and openEuler. Ubuntu and SLES use AppArmor, and a node of those families resolves to
disabled.

Why a stateless node runs with SELinux disabled
-----------------------------------------------

A stateless root is a cpio archive unpacked into tmpfs. cpio carries no SELinux label, so
the root starts unlabelled, and an unlabelled root cannot be made to boot:

* A dracut hook that loads the policy before ``switch_root`` denies every later program in
  the initramfs. The initramfs root is ``root_t``, and ``kernel_t`` cannot execute it. The
  stock dracut ``98selinux`` module does this, which is why its ``check()`` returns 255 and
  no xCAT image includes it.
* A dracut hook that labels the root with ``setfiles`` and loads no policy does label it,
  and ``systemd`` then loads the policy after ``switch_root``, fails to relabel ``/dev``
  and ``/run``, and stops with ``Failed to allocate manager object``.

So ``mknetboot`` writes ``selinux=0`` for every stateless node, whatever
``noderes.selinux`` and ``site.selinux`` say, and ``nodeset`` prints the reason::

    cn1: SELinux is disabled: a stateless rhels10.0 node cannot label its RAM root

``xCAT::SELinux->netboot_supported`` is the one place that answers this question.

xCAT itself is not confined
---------------------------

``xcatd``, ``in.tftpd``, ``kea-dhcp4`` and ``goconserver`` run in
``unconfined_service_t``. The ``xCAT-selinux`` package defines no type and confines
nothing. It carries the rules that let the CONFINED services of the OS reach the files
xCAT owns, for example ``httpd`` reading ``/tftpboot``.

So SELinux on an xCAT cluster constrains the OS services, not xCAT. Running xCAT with
SELinux enforcing is the goal; confining xCAT is not part of it.

Setting the mode of a node
--------------------------

``noderes.selinux`` on the node, then the ``noderes.selinux`` of its groups, then
``site.selinux``, then disabled. A node row can turn SELinux on when ``site.selinux`` is
disabled::

    chdef -t site selinux=enforcing
    chdef cn1 selinux=permissive
    lsdef cn1 -i selinux

The value is ``enforcing``, ``permissive`` or ``disabled``. The first install of xCAT
records ``site.selinux`` from the mode of the management node, through
``recordselinuxdefault``.

An existing cluster
-------------------

``recordselinuxdefault`` runs on INITIALINSTALL only, so an upgrade does not write
``site.selinux``. An upgraded cluster has no value, which resolves to disabled, and every
node keeps being provisioned with SELinux off. Set the value to change that::

    chdef -t site selinux=enforcing

A cluster that xCAT provisioned before this release has SELinux disabled on its nodes, and
``/etc/selinux/config`` on those nodes says ``SELINUX=disabled``. Reprovisioning a node is
what gives it the new mode; ``chdef`` alone does not reach a running node.

On the management node, xCAT never disabled SELinux, but the installation guides used to
ask the admin to. Turn it back on with the usual OS procedure, which relabels the
filesystem and reboots::

    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    touch /.autorelabel
    reboot

Install ``xCAT-selinux`` before that reboot, so ``/install`` and ``/tftpboot`` are
relabelled with the xCAT rules in place.

Checking a node
---------------

``xcatprobe xcatmn`` reports the mode, whether the ``xcat`` policy module is loaded, and
the labels of ``installdir`` and ``tftpdir``.

Read the denials with ``ausearch --input-logs``. Without ``--input-logs``, ``ausearch``
reads the journal, which carries no audit records on EL10, and answers that there are
none::

    ausearch --input-logs -m AVC,USER_AVC -ts today

A cluster denies things xCAT has nothing to do with: on an idle enforcing management node
``httpd`` asks for ``net_admin`` on itself every ten seconds, and the base policy has no
``dontaudit`` rule for it. ``selinux_avc_check.sh`` in the xCAT test suite reports only the
denials whose subject program or object path belongs to xCAT.
