SELinux
=======

xCAT runs on a management node that has SELinux in enforcing mode. An xCAT
installation does not change the SELinux mode of the machine.

Scope
-----

This version covers the management node. A service node and a compute node are
out of scope: no run measures them, and xCAT does not select their mode.

The two domains
---------------

``xcatd`` and the xCAT client commands run in ``xcat_t``. The image build runs
in ``xcat_image_t``, because it creates a complete operating system tree and
therefore writes and relabels files of every type. The ``xCAT-selinux`` package
labels the files each domain is entered through:

===========================================  =======================
File                                         Type
===========================================  =======================
/opt/xcat/sbin/xcatd                         ``xcatd_exec_t``
/opt/xcat/bin/xcatclient                     ``xcat_client_exec_t``
/opt/xcat/bin/xcatclientnnr                  ``xcat_client_exec_t``
/opt/xcat/bin/xcatDBcmds                     ``xcat_client_exec_t``
/opt/xcat/bin/genimage                       ``xcat_client_exec_t``
/opt/xcat/share/xcat/netboot/<os>/genimage   ``xcat_image_exec_t``
/opt/xcat/share/xcat/netboot/<os>/geninitrd  ``xcat_image_exec_t``
===========================================  =======================

``xcatd`` runs the per-OS ``genimage`` through a shell, so the build enters
``xcat_image_t`` from ``xcat_t``. An administrator who runs ``genimage``
directly enters it the same way.

What each domain holds
----------------------

``xcat_image_t`` may create, write and relabel a file of any type, including the
security types a package installs inside the image: ``/etc/selinux``, the audit
configuration and the keytabs of the image. The kernel cannot tell a path inside
the image from the same type on the management node, so this is the broadest
grant in the module and the reason the build has a domain of its own.

``xcat_t`` keeps what the daemon needs: its sockets and the ``xcatd`` port,
``/install``, ``/tftpboot``, the configuration of the services it drives, the
credentials under ``/etc/xcat``, and the ``service`` class for the units it
restarts. It also manages and relabels non-security files, because ``packimage``
and ``liteimg`` are symlinks to ``xcatclientnnr`` and their work runs inside
``xcatd``. What it never gets is the security types.

Services xCAT starts itself
---------------------------

xCAT starts ``in.tftpd`` without a systemd unit. The module transitions it to
the stock ``tftpd_t``, so the TFTP server does not serve UDP 69 with the
authority of the management domain. ``chronyd``, which ``setupntp`` runs, reaches
``chronyd_t`` the same way.

systemd enters ``xcat_t`` on the ``xcatd`` script, so the ``ExecStart`` of the
unit must name ``xcatd`` and not a shell. 115 command names are symlinks to
``xcatclient`` or ``xcatclientnnr``, and each one enters the domain through the
file it points to. ``/usr/sbin/xcatd`` is a symlink, and ``execve`` resolves it,
so the context belongs to the file in ``/opt/xcat``.

A rootimg component in the middle of an image root is ambiguous, because
``rootimgdir`` is any path under ``/install``. The file contexts keep the guest
labels there, so an osimage whose ``rootimgdir`` has a directory called
``rootimg`` above the tree leaves its published kernel and initrd unlabeled,
and ``httpd`` cannot serve them. Give such an osimage a ``rootimgdir`` with no
``rootimg`` component, or run ``restorecon`` over the image root after the
package is installed.

The unit holds ``/opt/xcat`` as the default prefix, and ``%post`` writes
``/etc/xcat/xcatroot.env`` with the prefix of the installation, which the unit
reads after that default. The file contexts name ``/opt/xcat``, so a package
relocated with ``rpm --prefix`` starts in its own tree but needs its own file
context entries before the entrypoints reach ``xcat_t``.

Read the domain of the running daemon with::

    ps -o label= -p "$(cat /run/xcatd.pid)"
    ps -eo label,args | grep '[x]catd:'

The domains are permissive
--------------------------

The policy source declares ``permissive xcat_t;`` and
``permissive xcat_image_t;``. The host policy stays
enforcing, and the kernel records each access that ``xcat_t`` makes outside the
rules rather than refusing it. The CI collects those records, and each rule the
module gains comes from one of them. A later release removes the declaration
and the domain becomes enforcing.

List the permissive domains of the loaded policy with::

    semodule -l | grep -x xcat
    seinfo --permissive

A transition to another domain is not covered by a permissive declaration.
``tftpd_t``, ``chronyd_t`` and the stock domains enforce their own rules.

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
