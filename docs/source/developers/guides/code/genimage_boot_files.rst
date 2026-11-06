genimage Boot Files
===================

Every ``genimage`` script builds a kernel and one or more initial ramdisks for
a diskless image, and writes them to the image directory, the ``rootimgdir`` of
the osimage.  ``geninitrd`` runs ``genimage --onlyinitrd``, which takes the
same steps.
``nodeset`` copies the kernel and the ramdisks as one set, so the files in the
image directory must always come from the same build.

Rules
-----

#. Build the boot files in a staging directory inside the image directory.
   Create it with ``File::Temp->newdir`` in the image directory, so that each
   file moves into place with a ``rename`` on the same file system.
#. Copy the kernel of the image with ``imgutils::copy_kernel``.
#. Pack a ramdisk without dracut with ``imgutils::pack_initrd``.  It stops
   when any command of the ``find``, ``cpio`` and compression pipeline fails.
#. Stop when a step fails: the kernel copy, dracut, the move of a ramdisk into
   the staging directory, or the cpio pipeline.  Exit with a status other than
   0, and leave the earlier boot files in the image directory.
#. Publish the kernel and all the ramdisks with
   ``imgutils::publish_staged_boot_files`` after the last ramdisk is built.  If
   a move fails, it puts back the files that it already replaced.
#. Write the ``rootimgcheck`` and UFTP markers after the publication.  They
   describe the published stateless ramdisk.
#. Put code that more than one ``genimage`` script needs in ``imgutils.pm``.
   Do not copy it into another script.  When a fix applies to more than one
   release, do not limit it to one release.

Scripts
-------

``rh/genimage`` follows these rules.  It is the ``genimage`` of RHEL,
AlmaLinux, Rocky Linux, CentOS, Oracle Linux, Scientific Linux, Fedora and
openEuler.  ``ubuntu/genimage`` also follows them.

The ``sles``, ``suse``, ``debian`` and ``fedora12`` scripts still write the
kernel and the ramdisks directly into the image directory.

Tests
-----

``xCAT-test/unit/imgutils_boot_file_build.t`` and
``xCAT-test/unit/imgutils_staged_boot_files.t`` cover the ``imgutils``
functions.  ``xCAT-test/native/openeuler_genimage_bootfiles.t`` runs
``rh/genimage --onlyinitrd`` for openEuler and EL images, with a failure in
each step.

A change to the boot file steps of a ``genimage`` script also needs a
``geninitrd`` run on a real image with a failed dracut.  After the run, the
image directory must hold the earlier kernel and ramdisks.
