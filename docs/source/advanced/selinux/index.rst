SELinux
=======

xCAT runs on a management node that has SELinux in enforcing mode. An xCAT
installation does not change the SELinux mode of the machine.

Scope
-----

This version covers the management node. A service node and a compute node are
out of scope: no run measures them, and xCAT does not select their mode.

The xcat_t domain
-----------------

``xcatd`` and the xCAT client commands run in one domain, ``xcat_t``. The
``xCAT-selinux`` package labels the three files the domain is entered through:

==============================  =======================
File                            Type
==============================  =======================
/opt/xcat/sbin/xcatd            ``xcatd_exec_t``
/opt/xcat/bin/xcatclient        ``xcat_client_exec_t``
/opt/xcat/bin/xcatclientnnr     ``xcat_client_exec_t``
==============================  =======================

systemd enters ``xcat_t`` on the ``xcatd`` script, so the ``ExecStart`` of the
unit must name ``xcatd`` and not a shell. 115 command names are symlinks to
``xcatclient`` or ``xcatclientnnr``, and each one enters the domain through the
file it points to. ``/usr/sbin/xcatd`` is a symlink, and ``execve`` resolves it,
so the context belongs to the file in ``/opt/xcat``.

Read the domain of the running daemon with::

    ps -o label= -p "$(cat /run/xcatd.pid)"
    ps -eo label,args | grep '[x]catd:'

The domain is permissive
------------------------

The policy source declares ``permissive xcat_t;``. The host policy stays
enforcing, and the kernel records each access that ``xcat_t`` makes outside the
rules rather than refusing it. The CI collects those records, and each rule the
module gains comes from one of them. A later release removes the declaration
and the domain becomes enforcing.

List the permissive domains of the loaded policy with::

    semodule -l | grep -x xcat
    seinfo --permissive

A denial that the kernel enforced carries ``permissive=0``. On a management node
of this version, only such a record reports a refused access::

    ausearch --input-logs -m AVC,USER_AVC -ts today | grep permissive=0

Commands run by a user
----------------------

Targeted policy gives root the ``unconfined_t`` domain, and the module
transitions from there into ``xcat_t``. A confined user domain, such as
``staff_t``, gets no transition: it would leave its own confinement for a
permissive domain. A command run from such a domain stays in it, and SELinux
still applies the rules of that domain.

SELinux does not replace the file permissions. A user who cannot read
``/etc/xcat`` cannot read it in ``xcat_t`` either.

The access the module grants other services
-------------------------------------------

``xcat_t`` is one part of the module. The rest grants the access that the
services around xCAT need:

* ``/install`` is ``public_content_t``, so ``httpd`` serves it. Each ``rootimg``
  tree is left out of the relabel, because it keeps the labels of its own
  operating system.
* ``httpd`` reads and maps the ``/tftpboot`` files that ``xcat.conf`` serves.
* ``xcatws.cgi`` connects to the ``xcatd`` port.
* ``rsync`` reads ``/etc/shadow`` and writes a copy it created at mode 0000.
* ``useradd`` and ``groupadd`` read the ``rootimg`` ``/var/run`` symlink, which
  the rpm scriptlets of a ``genimage`` build need.

Reading denials
---------------

``ausearch`` without ``--input-logs`` reported nothing on an AlmaLinux 10 node
whose log held 1032 denials, because audit 4.0.3 reads the journal rather than
the file ``auditd.conf`` names. Pass ``--input-logs``, or read the log file,
before you conclude that a machine is clean.

The kernel also drops audit records printed before ``auditd`` starts, at
``printk_ratelimit_burst`` and with no notice. Boot with
``sysctl.kernel.printk_ratelimit=0`` to see that window whole. A count taken
without it is a lower bound.
