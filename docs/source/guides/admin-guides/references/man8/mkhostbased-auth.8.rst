
##################
mkhostbased-auth.8
##################

.. highlight:: perl


****
NAME
****


mkhostbased-auth - configure SSH host-based authentication between selected xCAT nodes


********
SYNOPSIS
********


\ **mkhostbased-auth**\  \ *noderange*\  \ **-**\ **-user**\  \ *account*\  [\ **-**\ **-check**\ ] < \ *verified-known-hosts*\

\ **mkhostbased-auth**\  \ *noderange*\  \ **-**\ **-remove**\  [\ **-**\ **-check**\ ] < \ *verified-known-hosts*\

\ **mkhostbased-auth**\  \ **-**\ **-help**\


***********
DESCRIPTION
***********


Run this command as root on the management node. It enables host-based authentication for
one existing non-root account, between two or more selected stateful Linux compute nodes.
The same account name must exist on each node. Each selected peer's host key authenticates
the login, so enroll only nodes whose administrators can be trusted as the selected account.
The nodes' existing account policies, allow lists, and other SSH authentication methods
remain in effect.

The nodes need systemd-managed OpenSSH, Python 3.6 or newer at \ ``/usr/bin/python3``\ ,
the distribution's privileged \ ``ssh-keysign``\ , and standard OpenSSH host key paths.
On Enterprise Linux 10, install the \ ``openssh-keysign``\  package on each selected node.
The management node must be able to reach the nodes directly by their xCAT names using
root public-key SSH with the default SSH port and key locations. All nodes must use their
selected stable provisioning IPv4 addresses when connecting to one another. The server
must use \ ``UseDNS no``\  and an \ ``AuthenticationMethods``\  policy that permits host-based login
on its own.

Pass independently verified public host keys on standard input, one
\ ``node keytype public-key-blob``\  record per line. A key comment may follow the blob.
Use the exact selected xCAT name with each record, and supply at least one Ed25519,
ECDSA, or RSA public host key for each node. Obtain the public keys through a trusted
console or enrollment mechanism. For example, on a trusted console,
\ ``ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key``\  prints the public part that follows
the node name in the input. The command uses these pins for the management connections
and verifies them against the installed host keys. Shared xCAT provisioning keys and
keys duplicated across selected nodes are rejected. Ensure that future provisioning
or \ ``remoteshell``\  runs keep the nodes' host keys unique.

The setup writes \ ``01-xcat-hostbased-auth.conf``\  to the standard \ ``/etc/ssh/ssh_config.d``\
and \ ``/etc/ssh/sshd_config.d``\  directories if the corresponding main configuration
includes them globally. When the standard include is absent, the setup uses labeled
blocks in the main configuration. The public host keys and host equivalence rules
are managed in labeled blocks in \ ``/etc/ssh/ssh_known_hosts``\  and \ ``/etc/ssh/shosts.equiv``\ .
The command rejects competing host-based policies, existing equivalence rules and
system host trust entries for the selected hosts, including entries in
\ ``/etc/ssh/ssh_known_hosts2``\ . It validates all selected nodes before applying changes.
If application later fails on a node, its previous files are restored and the command
reports an error. Fix the failure on the reported node and rerun the command with
the same peers.


*******
OPTIONS
*******



\ **-**\ **-user**\  \ *account*\

 Permit the selected account to authenticate as the same account on the other selected nodes.



\ **-**\ **-check**\

 Validate the proposed setup or removal on the selected nodes without applying it.



\ **-**\ **-remove**\

 Remove the xCAT-managed drop-ins and labeled blocks from the selected nodes. Specify all original nodes before
 changing the account or peer list so that every old peer stops accepting the old trust group.
 Verified host keys are still required for the selected nodes. To revoke trust after a node
 is decommissioned, remove the configuration from all remaining peers before applying the new group.
 If SSH access to a remaining peer is unavailable, use its console to remove the managed
 drop-ins and labeled blocks, validate with \ ``sshd -t``\ , and reload OpenSSH.



\ **-h**\ , \ **-**\ **-help**\

 Display usage.




*******
EXAMPLE
*******



.. code-block:: perl

    mkhostbased-auth 'compute[01-02]' --user hpc --check < verified-known-hosts
    mkhostbased-auth 'compute[01-02]' --user hpc < verified-known-hosts


From the \ ``hpc``\  account on \ ``compute01``\ , exercise the host-based method directly.


.. code-block:: perl

    ssh -o PreferredAuthentications=hostbased compute02 hostname



********
SEE ALSO
********


ssh(1), ssh-keysign(8), sshd_config(5)
