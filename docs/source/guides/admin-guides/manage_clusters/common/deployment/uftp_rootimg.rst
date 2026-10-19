Distribute the root image with UFTP multicast
=============================================

A stateless node downloads its root image over HTTP while it boots. When many nodes boot at the same time, the image server sends the same image once per node. UFTP multicast sends the image once to all nodes that ask for it during a short batch window. HTTP stays available as the fallback.

UFTP distribution is optional. It is off unless the ``rootimgtransport`` attribute of the osimage, or ``site.rootimgtransport``, is ``uftp``. Images that use ``http``, the default, boot as before, and the UFTP software is not needed.

How it works
------------

#. ``genimage`` adds the UFTP receiver ``uftpd`` and a fetch helper to the stateless initial ramdisk when the image contains the ``uftp`` package of xcat-dep built for the image architecture. It checks that the ramdisk it built holds them, and records that the ramdisk can receive the root image over UFTP. Another ``uftp`` build or architecture in the image gets a warning and is left out.
#. ``packimage`` publishes the archive with its SHA-256 checksum file, as for every image.
#. For an image whose transport is ``uftp``, ``nodeset`` adds ``xcat.uftp=<listener port>`` and ``xcat.uftpfp=<server key fingerprint>`` to the kernel command line, next to ``imgurl=`` and ``rootimgchecksum=yes``.
#. The booting node downloads the checksum file of ``imgurl``. It asks ``xcat-uftp-listener`` on the image server for the archive that the checksum file lists, then starts its receiver in a private directory.
#. The listener collects the requests for the same archive for ``batch_delay`` seconds, then sends it to all of those nodes in one encrypted UFTP session. It drops a node that misses nearly all the data of a part of the image, so that node cannot delay the others.
#. The node checks the received archive against the checksum file, as it checks an HTTP download.
#. If any step fails, the node stops its receiver, removes its partial files, and downloads ``imgurl`` over HTTP. The node never extracts an archive that does not match the checksum file.

Supported configurations
------------------------

* Stateless images built by ``genimage`` for:

  * the Red Hat family (RHEL, AlmaLinux, Rocky Linux, Oracle Linux, CentOS) with dracut 033 or later,
  * openEuler 20.03, 22.03 and 24.03 LTS,
  * SLES 15 and openSUSE Leap 15 with dracut 033 or later,
  * Ubuntu with dracut.

* All ``packimage`` formats: ``cpio`` and ``tar`` with ``gzip``, ``pigz`` or ``xz``, and ``squashfs``.
* An IPv4 provisioning network that carries multicast between the image server and the nodes.
* ``site.httpmethod=http``.
* The ``uftp`` package of xcat-dep on the image server and in the image. It provides UFTP 5.0.4 with fixes to the sender and the receiver for Enterprise Linux, openEuler, SLES 15 SP6 or later, openSUSE Leap 15.6, and Ubuntu. Its SLES build needs glibc 2.34, which SLES 15 SP5 and older do not have.

``nodeset`` refuses a node of a ``uftp`` image, and keeps its current boot entry, in these cases:

* The root image checksum is turned off by ``rootimgchecksum``.
* ``site.httpmethod`` is ``https``. The node never sends a request meant for HTTPS over plain HTTP.
* The image was packed with ``packimage --tracker`` (BitTorrent).
* The initial ramdisk that nodes boot is not the one that ``genimage`` built with the UFTP receiver.
* The ``rootimgdir`` of the image is outside the ``image_roots`` of the listener, or has characters other than letters, digits and ``._+-`` in its path.
* ``linuximage.addkcmdline`` or ``bootparams.addkcmdline`` sets ``xcat.uftp`` or ``xcat.uftpfp``. ``nodeset`` generates them.

StateLite images ignore ``rootimgtransport``. Other UFTP builds, UFTP 4.x included, are not supported. ``genimage`` leaves their receiver out of the initial ramdisk, and the listener does not start with their sender. The ``uftp`` packages that Ubuntu ships are UFTP 4.10.

Security
--------

The kernel command line is the trust anchor. It reaches the node through the same TFTP or HTTP path as the kernel and the initial ramdisk. Anyone who can change those files can change the image that a node boots, with or without UFTP.

* The listener sends only an archive that ``packimage`` published with its checksum file in a configured image root. A request names the image path and a digest that the checksum file must list. Paths are checked after symbolic links are resolved. The image directory, the archive and its checksum file must be owned by root and not writable by other users. The listener opens the archive once and keeps it open until the transfer, so a later ``packimage`` cannot change the bytes of a queued transfer.
* No value from a request reaches the ``uftp`` command line. The listener runs ``uftp`` with an argument vector built from its own configuration.
* UFTP sessions are always encrypted. The listener signs them with ``/etc/xcat/uftp/server.key``. Nodes accept only encrypted sessions from a server with the fingerprint in ``xcat.uftpfp``.
* The nodes of a transfer share its group key, and the server key signs only the messages that set up the session. A node of the batch can therefore send the other nodes file names and file data as if it were the server. The receiver of xcat-dep keeps those files below its staging directory, and the node checks the archive against the checksum file. Such a node can make the other nodes download the image over HTTP.
* The listener refuses a ``uftp`` sender without the build mark of xcat-dep. Stock UFTP 5.0.4 can write past its buffers when a node sends a malformed status message.
* The checksum file protects the integrity of the archive against corruption and against changes on the network, for UFTP and HTTP alike. It does not give confidentiality, and it comes from the same image server as the archive.
* The HTTP fallback has the same confidentiality as an image download without UFTP: none. The image contains the encrypted root password and the files that you added to it.
* The listener accepts requests from any address that can reach ``listen_address``. Set ``allowed_networks`` to limit it to the provisioning networks.

Install UFTP
------------

#. Install the ``uftp`` package from xcat-dep on the management node and on every service node that serves images, for example: ::

     dnf install uftp

#. Add ``uftp`` from xcat-dep to the image, for example as an other package of the osimage. The package must be built for the image architecture. See :doc:`Install Additional Other Packages</guides/admin-guides/manage_clusters/ppc64le/diskless/customize_image/additional_pkg>`.

Configure the listener
----------------------

The listener is installed with ``xCAT-server`` but is not enabled. Removing ``xCAT-server`` stops and disables it. After an upgrade of ``xCAT-server``, restart a running listener to load the new version.

#. Create the configuration from the sample, and set at least ``listen_address`` to the address of the image server on the provisioning network: ::

     mkdir -p /etc/xcat/uftp
     cp /opt/xcat/share/xcat/conf/uftp-listener.conf.sample /etc/xcat/uftp/listener.conf

   Set ``image_roots`` if an image is outside ``/install/netboot``. Review ``rate_kbps``, ``block_size``, ``batch_delay`` and ``transfer_timeout`` for your network. See `Transfer rate and jumbo frames`_.

#. Create the server key and its fingerprint: ::

     /opt/xcat/sbin/xcat-uftp-listener --init-key

   ``nodeset`` reads the listener port from ``/etc/xcat/uftp/listener.conf``, and the fingerprint from ``/etc/xcat/uftp/server.fingerprint``.

#. Check the configuration, then start the service: ::

     /opt/xcat/sbin/xcat-uftp-listener --check
     systemctl enable --now xcat-uftp-listener

#. Allow the traffic in the firewall of the image server: TCP ``listen_port`` (default 1045) from the nodes, outgoing UDP to ``public_multicast`` and ``private_multicast`` on ``udp_port`` (default 1044), and incoming UDP from the nodes. The nodes answer with unicast UDP to the random port that ``uftp`` sends from, and a stateful firewall does not relate those answers to the multicast traffic.

#. Make sure that the switches forward the multicast groups. With IGMP snooping enabled, the network needs an IGMP querier.

Each image server runs its own listener, which sends only the images in its own image roots. On a service node that serves images, copy ``/etc/xcat/uftp/listener.conf``, ``server.key`` and ``server.fingerprint`` from the management node. Then set ``listen_address``, and ``multicast_interface`` if it is set, to the address of the service node on its provisioning network, and start the service. ``nodeset`` can run on the management node for those nodes, so every image server must use the same listener port and key.

The listener writes its messages to the system journal (``journalctl -u xcat-uftp-listener``), and one log file for each transfer to ``/var/log/xcat-uftp``. The service can write only to that directory. To set another ``log_dir``, add it with ``ReadWritePaths=`` in a systemd drop-in for ``xcat-uftp-listener.service``.

Transfer rate and jumbo frames
------------------------------

Set ``rate_kbps`` to no more than the link speed of the slowest node. A node on a slower link loses the packets that do not fit, and the transfer repeats them for all nodes. The default of 100000 (100 Mb/s) works on any network, but it needs about 52 seconds for a 650 MB image.

One ``uftp`` process sends each transfer on one CPU core, and it handles every packet separately. With the default ``block_size`` of 1300 bytes, a 2.1 GHz Intel Xeon E5 v4 core sends about 1.3 Gb/s, whatever the link speed. A ``block_size`` of 8800 bytes lets the same core send about 3.5 Gb/s. To use it:

#. Set an MTU of 9000 or more on the listener interface and on the switch ports of the provisioning network.
#. Set the MTU of the provisioning network, so that DHCP gives it to the initial ramdisk of the nodes: ::

     chdef -t network <netname> mtu=9000
     makedhcp -n

#. Set ``block_size = 8800`` in ``/etc/xcat/uftp/listener.conf`` and restart ``xcat-uftp-listener``.

A node that boots with a smaller MTU receives no data. It leaves the transfer and downloads the image over HTTP.

Build, pack and boot
--------------------

#. Generate the image. ``genimage`` reports ``The initial ramdisk ... can receive the root image over UFTP.`` when the receiver is in the initial ramdisk: ::

     genimage <osimage>

   An existing image that gets the ``uftp`` package later needs ``genimage`` again to rebuild its initial ramdisk.

#. Pack the image, and set its transport: ::

     packimage <osimage>
     chdef -t osimage <osimage> rootimgtransport=uftp

   To use UFTP for every stateless image that does not set the attribute, set ``site.rootimgtransport`` instead: ::

     chdef -t site rootimgtransport=uftp

#. Write the boot settings, then boot the nodes: ::

     nodeset <noderange> osimage=<osimage>
     rpower <noderange> boot

After a ``packimage``, the nodes receive the new archive at their next boot without a new ``nodeset``. Run ``nodeset`` after every ``genimage``. When the initial ramdisk of a ``uftp`` image lacks the receiver, ``nodeset`` refuses its nodes. Install the ``uftp`` package in the image and run ``genimage`` again, or set ``rootimgtransport=http`` for the image.

To stop using UFTP for an image, set its ``rootimgtransport`` to ``http`` and run ``nodeset`` for its nodes.
