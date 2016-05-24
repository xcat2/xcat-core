Support Matrix
==============

+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
|         | RHEL    | SLES    | RHEL    | SLES    | Ubuntu  | RHEL    | SLES    | Ubuntu  | AIX  |
|         | ppc64   | ppc64   | x86_64  | x86_64  | x86_64  | ppc64le | ppc64le | ppc64el | CN   |
|         | CN      | CN      | CN      | CN      | CN      | CN      | CN      | CN      |      |
+=========+=========+=========+=========+=========+=========+=========+=========+=========+======+
| RHEL    |         |         |         |         |         |         |         |         |      |
| ppc64   |  yes    |  yes    | yes     | yes     | yes     |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         | [1]_    | [1]_    | [1]_    |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| ppc64   |  yes    |  yes    | yes     | yes     | yes     |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         | [1]_    | [1]_    | [1]_    |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| RHEL    |         |         |         |         |         |         |         |         |      |
| x86_64  | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | [4]_    | [4]_    |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| x86_64  | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | [4]_    | [4]_    |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| Ubuntu  |         |         |         |         |         |         |         |         |      |
| x86_64  | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | [5]_    | [5]_    |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| RHEL    |         |         |         |         |         |         |         |         |      |
| ppc64le | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | [2]_    | [2]_    |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| ppc64le |  no     |  no     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| Ubuntu  |         |         |         |         |         |         |         |         |      |
| ppc64el | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | [3]_    | [3]_    |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| AIX     |  no     |  no     |  no     |  no     |  no     |  no     |  no     |  no     |  yes |
| MN/SN   |         |         |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+

Notes:

* The support statements refers to hardware control, operating system (os) provisioning, and general purpose system management where we do not see any obvious problems with the indicated combination.

* For diskless mixed cluster support, the initial diskless image must be created on a node running the target operating system version and architecture. see :doc:`/advanced/mixed_cluster/building_stateless_images` for more details.

.. rubric:: Footnotes

.. [1] To manage x86_64 servers from ppc64/ppc64le nodes, will need to install the packages **xnba-undi elilo-xcat** and **syslinux-xcat** manually on the management node. And manually run command "cp /opt/xcat/share/xcat/netboot/syslinux/pxelinux.0 /tftpboot/"
.. [2] If the compute nodes are DFM managed systems, will need xCAT 2.9.1 or high versions and the ppc64le DFM and ppc64le hardware server on the management node.
.. [3] If the compute nodes are DFM managed systems, will need xCAT 2.10 or high versions and the ppc64le DFM and ppc64le hardware server on the management node.
.. [4] If the compute nodes are DFM managed systems, will need the ppc64le DFM and ppc64le hardware server on the management node.
.. [5] Does not support DFM managed compute nodes, hardware control does not work.
