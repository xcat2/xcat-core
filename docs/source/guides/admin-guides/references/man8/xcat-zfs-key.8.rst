
##############
xcat-zfs-key.8
##############


****
NAME
****


\ **xcat-zfs-key**\  - save or recover a FreeBSD data-pool encryption key


********
SYNOPSIS
********


\ **xcat-zfs-key save**\  \ *node*\  \ *pool*\  \ */private/directory/pool.key*\

\ **xcat-zfs-key restore**\  \ *node*\  \ *pool*\  \ */private/directory/pool.key*\


***********
DESCRIPTION
***********


Run this command as root on the xCAT management node. \ **save**\  reads an existing
32-byte raw key and stores its recoverable hexadecimal representation in the
\ **passwd**\  table, under key \ **freebsd-zfs**\  and username \ *node/pool*\ . It does not
generate a key, rotate encryption or send a key to a node.
The combined \ *node/pool*\  identity must fit the table's 128-character key limit.

An ordinary \ **dumpxCATdb**\  backup includes the saved key unless the \ **passwd**\
table is excluded. Protect this backup as a credential backup. The key is
encoded, not encrypted. After \ **restorexCATdb**\ , \ **restore**\  recreates the raw key
file for SSH file synchronization to the installed FreeBSD node.

The key file must be a regular file owned by root, with group root, mode 0600
and one link. Its containing directory must be owned by root with mode 0700.
Parent directories must not be symlinks or writable by group or others.

Saving the same key or recovering an identical file succeeds without replacing
it. A different saved key or a different destination file causes failure.
Existing encrypted data requires its original key. This command never creates
a replacement key when recovery fails.


********
EXAMPLES
********


Save an existing key before creating an encrypted data pool:


.. code-block:: perl

  xcat-zfs-key save node01 tank /root/freebsd-keys/node01/tank.key
  dumpxCATdb -p /root/xcat-backup


After restoring the xCAT database, recreate the private directory and recover
the key:


.. code-block:: perl

  install -d -m 0700 /root/freebsd-keys/node01
  xcat-zfs-key restore node01 tank /root/freebsd-keys/node01/tank.key


Deliver that directory through the image's protected \ **synclists**\ . Import the
preserved pool using its recorded GUID and original storage policy.


********
SEE ALSO
********


dumpxCATdb(1), restorexCATdb(1), passwd(5)
