Operating System & Hardware Support Matrix
==========================================

+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| Distro | Version | Power | Power | zVM | Power | x86_64 | x86_64 | x86_64 | aarch64  | riscv64  |
|        |         |       | LE    |     | KVM   |        | KVM    | Esxi   |          |          |
+========+=========+=======+=======+=====+=======+========+========+========+==========+==========+
| EL     | 8       | yes   | yes   | yes | yes   | yes    | yes    | yes    | yes      | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| EL     | 9       | yes   | yes   | yes | yes   | yes    | yes    | yes    | yes      | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| EL     | 10      | yes   | yes   | yes | yes   | yes    | yes    | yes    | yes      | yes      |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| SLES   | 12      | yes   | yes   | yes | yes   | yes    | yes    | yes    | no       | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| SLES   | 15      | yes   | yes   | yes | yes   | yes    | yes    | yes    | no       | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| Ubuntu | 20.04   | no    | yes   | no  | yes   | yes    | yes    | yes    | no       | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| Ubuntu | 22.04   | no    | yes   | no  | yes   | yes    | yes    | yes    | no       | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| Ubuntu | 24.04   | no    | yes   | no  | yes   | yes    | yes    | yes    | no       | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
| Ubuntu | 26.04   | no    | yes   | no  | yes   | yes    | yes    | yes    | no       | no       |
+--------+---------+-------+-------+-----+-------+--------+--------+--------+----------+----------+

.. note::

   EL: Enterprise Linux, such as: RHEL, Rocky Linux, Alma Linux, CentOS and Oracle Linux.

riscv64 support covers EL10 compute nodes (Rocky Linux 10 and the RHEL 10 RISC-V developer preview) that boot through UEFI firmware and grub2. See :doc:`/guides/admin-guides/manage_clusters/riscv64/index` for details.
