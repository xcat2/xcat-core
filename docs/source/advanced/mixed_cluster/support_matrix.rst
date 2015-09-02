Support Matrix
==============

+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
|         | RedHat  | SLES    | RedHat  | SLES    | Ubuntu  | RedHat  | SLES    | Ubuntu  | AIX  |
|         | ppc64   | ppc64   | x86_64  | x86_64  | x86_64  | ppc64le | ppc64le | ppc64el | CN   |
|         | CN      | CN      | CN      | CN      | CN      | CN      | CN      | CN      |      |
+=========+=========+=========+=========+=========+=========+=========+=========+=========+======+
| RedHat  |         |         |         |         |         |         |         |         |      |
| ppc64   |  yes    |  yes    | yes     | yes     | yes     |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         | [1]_    | [1]_    | [1]_    |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| SLES    |         |         |         |         |         |         |         |         |      |
| ppc64   |  yes    |  yes    | yes     | yes     | yes     |  yes    |  yes    |  yes    |  no  |
| MN/SN   |         |         | [1]_    | [1]_    | [1]_    |         |         |         |      |
+---------+---------+---------+---------+---------+---------+---------+---------+---------+------+
| RedHat  |         |         |         |         |         |         |         |         |      |
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
| RedHat  |         |         |         |         |         |         |         |         |      |
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

* All the "yes" and "no" statements in the table are referring to hardware control and os provisioning, for the general purpose management like file sync and parallel commands, we do not see any obvious problem with any of the combination.

* The "yes" means should work but may or may not have been verified by the xCAT development/testing team. 

* For diskless node, need another node that has the same os version and arch with the compute nodes to create diskless image, see :ref:`Building_a_Stateless_Image_of_a_Different_Architecture_or_OS` for more details.

.. rubric:: Footnotes

.. [1] To manage x86_64 servers from ppc64/ppc64le nodes, will need to install the packages **xnba-undi elilo-xcat** and **syslinux-xcat** manually on the management node. And manually run command "cp /opt/xcat/share/xcat/netboot/syslinux/pxelinux.0 /tftpboot/"
.. [2] If the compute nodes are DFM managed systems, will need xCAT 2.9.1 or high versions and the ppc64le DFM and ppc64le hardware server on the management node.
.. [3] If the compute nodes are DFM managed systems, will need xCAT 2.10 or high versions and the ppc64le DFM and ppc64le hardware server on the management node.
.. [4] If the compute nodes are DFM managed systems, will need the ppc64le DFM and ppc64le hardware server on the management node.
.. [5] Does not support DFM managed compute nodes, hardware control does not work.
