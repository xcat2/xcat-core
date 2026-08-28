Ubuntu diskful install needs memory for the live filesystem
===========================================================

An Ubuntu diskful (Subiquity) install boots the live installer over NFS and then copies it
into RAM, because the kernel command line xCAT generates carries ``toram``. This is
deliberate: with the NFS root still mounted at the end of the install, ``systemd-shutdown``
blocks on I/O to it and the node never reboots into the disk it just installed.

The consequence is that the compute node must have enough memory for the live filesystem on
top of whatever the installer itself needs. The squashfs layers are roughly 1.5 GB on 24.04
and grow with each release, so **4 GB is a practical floor and 8 GB is comfortable**.

A node with too little memory fails part-way through the install, and the symptom resembles
an unrelated problem: the node reboots back into the installer, so it looks like a PXE loop
rather than an out-of-memory condition. Check the console before assuming a boot-flip
failure. ::

    rcons <node>

To confirm, look for the OOM killer in the installer's kernel messages, or watch the node's
memory from the hypervisor while it installs. For a libvirt-hosted node the memory is
``vmm``/``vmmemory`` in the **vm** table. ::

    lsdef <node> -i vmmemory
    chdef <node> vmmemory=8192

Diskless (netboot) nodes have a related but separate requirement: the rootimg is unpacked
into a tmpfs, and on ppc64le the 64 KB page size inflates it considerably.
