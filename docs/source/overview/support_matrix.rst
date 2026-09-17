Operating System & Hardware Support Matrix
==========================================

+--------+---------+--------+---------+----------+
| Distro | Version | x86_64 | ppc64le | riscv64  |
+========+=========+========+=========+==========+
| EL     | 8       | yes    | yes     | no       |
+--------+---------+--------+---------+----------+
| EL     | 9       | yes    | yes     | no       |
+--------+---------+--------+---------+----------+
| EL     | 10      | yes    | yes     | yes      |
+--------+---------+--------+---------+----------+
| SLES   | 12      | yes    | yes     | no       |
+--------+---------+--------+---------+----------+
| SLES   | 15      | yes    | yes     | no       |
+--------+---------+--------+---------+----------+
| Ubuntu | 22.04   | yes    | yes     | no       |
+--------+---------+--------+---------+----------+
| Ubuntu | 24.04   | yes    | yes     | no       |
+--------+---------+--------+---------+----------+
| Ubuntu | 26.04   | yes    | yes     | no       |
+--------+---------+--------+---------+----------+

.. note::

   EL stands for Enterprise Linux, such as: Red Hat Enterprise Linux (RHEL), Rocky Linux, AlmaLinux, CentOS and Oracle Linux.

riscv64 support covers EL 10 (Rocky Linux 10 and the RHEL 10 RISC-V developer preview), on nodes
that boot through UEFI firmware and grub2. Both stateful and stateless nodes are supported, and
the management node itself can run on riscv64. See
:doc:`/guides/admin-guides/manage_clusters/riscv64/index` for details.
