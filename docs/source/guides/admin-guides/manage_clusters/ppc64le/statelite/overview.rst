Overview
========

This document details the design and setup for the statelite solution of xCAT. ``Statelite`` is an intermediate mode between ``stateful`` and ``stateless``.

Statelite provides two kinds of efficient and flexible solutions, most of the OS image can be NFS mounted read-only, or the OS image can be in the ramdisk with tmpfs type. Different from the stateless solution, statelite provides a configurable list of directories and files that can be read-write. These read-write directories and files can either be persistent across reboots, or volatile (which means restoring to the original state after reboot).

Solutions
---------

There are two solutions, ``NFSROOT-based`` and ``RAMdisk-based``.

There is an attribute named rootfstype in the osimage xCAT data objects. If it is set to ``ramdisk``, the ``RAMdisk-based`` statelite solution will be enabled. If it is left as blank, or set to ``nfs``, the ``NFSROOT-base`` statelite solution will be enabled.

The default solution is ``NFSROOT-based``. In the ``NFSROOT-based`` solution, the ROOTFS is NFS mounted read-only.

In the ``RAMdisk-based`` statelite solution, one image file will be downloaded when the node is booting up, and the file will be extracted to the ramdisk, and used as the ROOTFS.

Advantages
----------

``Statelite`` offers the following advantages over xCAT's stateless (RAMdisk) implementation:

#. Some files can be made persistent over reboot. This is useful for license files or database servers where some state is needed. However, you still get the advantage of only having to manage a single image.
#. Changes to hundreds of machines can take place instantly, and automatically, by updating one main image. In most cases, machines do not need to reboot for these changes to take affect. This is only for the ``NFSROOT-based`` solution.
#. Ease of administration by being able to lock down an image. Many parts of the image can be read-only, so no modifications can transpire without updating the central image.
#. Files can be managed in a hierarchical manner. For example: Suppose you have a machine that is in one lab in Tokyo and another in London. You could set table values for those machines in the xCAT database to allow machines to sync from different places based on their attributes. This allows you to have one base image with multiple sources of file overlay.
#. Ideal for virtualization. In a virtual environment, you may not want a disk image (neither stateless nor stateful) on every virtual node as it consumes memory and disk. Virtualizing with the statelite approach allows for images to be smaller, easier to manage, use less disk, less memory, and more flexible.

Disadvantages
-------------

However, there're still several disadvantages, especially for the ``NFSROOT-based`` solution.

#. NFS Root requires more network traffic to run as the majority of the disk image runs over NFS. This may depend on your workload, but can be minimized. Since the bulk of the image is read-only, NFS caching on the server helps minimize the disk access on the server, and NFS caching on the client helps reduce the network traffic.
#. NFS Root can be complex to set up. As more files are created in different places, there are greater chances for failures. This flexibility is also one of the great virtues of Statelite. The image can work in nearly any environment.

Only one statelite image may be defined for a node or noderange.
