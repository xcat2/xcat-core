Operating System & Hardware Support Matrix
==========================================

+-------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
|       | Power | Power | zVM | Power | x86_64 | x86_64 | x86_64 | aarch64  | riscv64  |
|       |       | LE    |     | KVM   |        | KVM    | Esxi   |          |          |
+=======+=======+=======+=====+=======+========+========+========+==========+==========+
|RHEL   | yes   | yes   | yes | yes   | yes    | yes    | yes    | yes      | yes      |
|       |       |       |     |       |        |        |        |          |          |
+-------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
|SLES   | yes   | yes   | yes | yes   | yes    | yes    | yes    | no       | no       |
|       |       |       |     |       |        |        |        |          |          |
+-------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
|Ubuntu | no    | yes   | no  | yes   | yes    | yes    | yes    | no       | no       |
|       |       |       |     |       |        |        |        |          |          |
+-------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
|CentOS | no    | no    | no  | no    | yes    | yes    | yes    | no       | no       |
|       |       |       |     |       |        |        |        |          |          |
+-------+-------+-------+-----+-------+--------+--------+--------+----------+----------+
|Windows| no    | no    | no  | no    | yes    | yes    | yes    | no       | no       |
|       |       |       |     |       |        |        |        |          |          |
+-------+-------+-------+-----+-------+--------+--------+--------+----------+----------+

riscv64 support covers EL10 compute nodes (Rocky Linux 10 and the RHEL 10 RISC-V developer preview) that boot through UEFI firmware and grub2. See :doc:`/guides/admin-guides/manage_clusters/riscv64/index` for details.
