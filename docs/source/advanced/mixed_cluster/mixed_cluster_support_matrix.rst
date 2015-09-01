Mixed Cluster Support Matrix
============================

Supported xCAT cross-distribution hardware control and OS installation environments
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Notes:

* All the "yes" and "no" statements in the table are referring to hardware control and os provisioning, for the general purpose management like file sync and parallel commands, we do not see any obvious problem with any of the combination.

* The "yes" means should work but may or may not have been verified by the xCAT development/testing team. 

* For diskless node, need another node that has the same os version and arch with the compute nodes to create diskless image, see TODO:Building_a_Stateless_Image_of_a_Different_Architecture_or_OS for more details

+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
|         | RedHat  | SLES    | RedHat  | SLES    | Ubuntu  | RedHat  | SLES    | Ubuntu  | AIX  |
|         | ppc64   | ppc64   | x86_64  | x86_64  | x86_64  | ppc64le | ppc64le | ppc64el | CN   |
|         | CN      | CN      | CN      | CN      | CN      | CN      | CN      | CN      |      |
+=========+=========+=========+=========+=========+=========+=========+=========+=========+======+
| RedHat  |         |         |         |         |         |         |         |         |      |
| ppc64   |  yes    |  yes    | yes     | yes     | yes     |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         | :sup:`1`| :sup:`1`| :sup:`1`|         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| ppc64   |  yes    |  yes    | yes     | yes     | yes     |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         | :sup:`1`| :sup:`1`| :sup:`1`|         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| RedHat  |         |         |         |         |         |         |         |         |      |
| x86_64  | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | :sup:`4`| :sup:`4`|         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| x86_64  | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | :sup:`4`| :sup:`4`|         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| Ubuntu  |         |         |         |         |         |         |         |         |      |
| x86_64  | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | :sup:`5`| :sup:`5`|         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| RedHat  |         |         |         |         |         |         |         |         |      |
| ppc64le | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | :sup:`2`| :sup:`2`|         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| ppc64le |  no     |  no     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| Ubuntu  |         |         |         |         |         |         |         |         |      |
| ppc64el | yes     | yes     |  yes    |  yes    |  yes    |  yes    |  yes    |  yes    |  no  |
| MN/SN   | :sup:`3`| :sup:`3`|         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| AIX     |  no     |  no     |  no     |  no     |  no     |  no     |  no     |  no     |  yes |
| MN/SN   |         |         |         |         |         |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+


Notes:

#. To manage x86_64 servers from ppc64/ppc64le nodes, will need to install the packages **xnba-undi elilo-xcat** and **syslinux-xcat** manually on the management node. And manually run command "cp /opt/xcat/share/xcat/netboot/syslinux/pxelinux.0 /tftpboot/"

#. If the compute nodes are DFM managed systems, will need xCAT 2.9.1 or high versions and the ppc64le DFM and ppc64le hardware server on the management node.

#. If the compute nodes are DFM managed systems, will need xCAT 2.10 or high versions and the ppc64le DFM and ppc64le hardware server on the management node.

#. If the compute nodes are DFM managed systems, will need the ppc64le DFM and ppc64le hardware server on the management node.

#. Does not support DFM managed compute nodes, hardware control does not work.
