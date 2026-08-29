Apache Hardening
================

xCAT uses Apache HTTP Server to serve install media, postscripts, and boot
files to nodes during provisioning. The default configuration prioritizes
ease of deployment, but administrators should apply the hardening measures
below to reduce the attack surface.

Directory Indexing Disabled by Default
--------------------------------------

Starting with xCAT 2.18, directory indexing (``Options Indexes``) is disabled
by default for the ``/install`` and ``/tftpboot`` directories. This prevents
unauthenticated users from browsing directory listings and discovering file
paths. All provisioning workflows continue to work because nodes fetch files
by their known paths.

If you are upgrading from an earlier version of xCAT, update your Apache
configuration manually. Remove ``Indexes`` from the ``/install`` and
``/tftpboot`` blocks, but add explicit exceptions for the directories that
provisioning scripts crawl recursively.

**Apache 2.4** (RHEL 7+, SLES 12+, Ubuntu 16.04+)::

    # /etc/httpd/conf.d/xcat.conf
    ServerTokens Prod

    <Directory "/tftpboot">
        Options FollowSymLinks
        <IfModule mod_headers.c>
            Header always set X-Frame-Options SAMEORIGIN
            Header always set X-Content-Type-Options nosniff
            Header always set Content-Security-Policy "script-src 'self' 'unsafe-eval'"
            Header always set X-Permitted-Cross-Domain-Policies none
        </IfModule>
        AllowOverride None
        Require all granted
    </Directory>
    <Directory "/install">
        Options FollowSymLinks
        <IfModule mod_headers.c>
            Header always set X-Frame-Options SAMEORIGIN
            Header always set X-Content-Type-Options nosniff
            Header always set Content-Security-Policy "script-src 'self' 'unsafe-eval'"
            Header always set X-Permitted-Cross-Domain-Policies none
        </IfModule>
        AllowOverride None
        Require all granted
    </Directory>
    <Directory "/install/postscripts">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    <Directory "/install/post">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

**Apache 2.2** (RHEL 6, SLES 11)::

    # /etc/httpd/conf.d/xcat.conf
    ServerTokens Prod

    <Directory "/tftpboot">
        Options FollowSymLinks
        <IfModule mod_headers.c>
            Header always set X-Frame-Options SAMEORIGIN
            Header always set X-Content-Type-Options nosniff
            Header always set Content-Security-Policy "script-src 'self' 'unsafe-eval'"
            Header always set X-Permitted-Cross-Domain-Policies none
        </IfModule>
        AllowOverride None
        Order allow,deny
        Allow from all
    </Directory>
    <Directory "/install">
        Options FollowSymLinks
        <IfModule mod_headers.c>
            Header always set X-Frame-Options SAMEORIGIN
            Header always set X-Content-Type-Options nosniff
            Header always set Content-Security-Policy "script-src 'self' 'unsafe-eval'"
            Header always set X-Permitted-Cross-Domain-Policies none
        </IfModule>
        AllowOverride None
        Order allow,deny
        Allow from all
    </Directory>
    <Directory "/install/postscripts">
        Options Indexes FollowSymLinks
        AllowOverride None
        Order allow,deny
        Allow from all
    </Directory>
    <Directory "/install/post">
        Options Indexes FollowSymLinks
        AllowOverride None
        Order allow,deny
        Allow from all
    </Directory>

.. warning::

   Do not remove ``Indexes`` from ``/install/postscripts`` or
   ``/install/post``. xCAT provisioning scripts use recursive ``wget`` to
   download all files from these directories and depend on Apache directory
   listings to discover file paths.

Local Customizations
--------------------

``xcat.conf`` belongs to the xCAT package. Keep site-specific rules in a
separate file that Apache reads after it:

* EL: ``/etc/httpd/conf.d/zz-xcat-local.conf``
* SUSE: ``/etc/apache2/conf.d/zz-xcat-local.conf``

Apache reads ``conf.d`` in alphabetical order, so the ``zz-`` prefix puts the
file after ``xcat.conf`` and its directives take precedence. Use the relative
form of ``Options`` (``+`` or ``-``): it adjusts the options inherited from the
xCAT block, where the absolute form replaces all of them. For example, to allow
browsing of one site directory::

    # /etc/httpd/conf.d/zz-xcat-local.conf
    <Directory "/install/custom/mypkgs">
        Options +Indexes
    </Directory>

Editing ``xcat.conf`` in place still works: an upgrade keeps the modified file.
If the packaged configuration changed too, the new version is written alongside
it as ``xcat.conf.rpmnew`` and has to be merged by hand.

Security Response Headers and Server Banner
-------------------------------------------

xCAT configures ``ServerTokens Prod`` to omit the Apache version and operating
system from the HTTP ``Server`` header. It also applies the following response
headers to ``/install`` and ``/tftpboot``:

* ``X-Frame-Options: SAMEORIGIN``
* ``X-Content-Type-Options: nosniff``
* ``Content-Security-Policy: script-src 'self' 'unsafe-eval'``
* ``X-Permitted-Cross-Domain-Policies: none``

These directives require ``mod_headers``. The xCAT packages enable that module
on distributions where it is not loaded by default and activate the updated
configuration during installation or upgrade. Keep the ``Header always set``
directives when adding local access-control rules to either directory.

Sensitive Directories
---------------------

The following directories under ``/install`` may contain sensitive data and
should be protected with restrictive filesystem permissions:

``/install/custom/``
    Custom postscripts, templates, and package lists. May contain hardcoded
    credentials or internal configuration details.

``/install/syncfiles/``
    Files synchronized to nodes. May include password files, SSL certificates,
    or application secrets.

``/install/autoinst/``
    Generated kickstart and preseed files. Contains root password hashes and
    full network configuration for each node. Nodes fetch these over HTTP
    during installation, so filesystem permissions cannot be restricted without
    breaking provisioning. Use IP-based access control (see below) to limit
    access to the management network instead.

Set restrictive permissions where possible::

    chmod 750 /install/custom
    chmod 750 /install/syncfiles

.. note::

   Do not restrict filesystem permissions on ``/install/postscripts``,
   ``/install/autoinst``, or the OS media directories (e.g.,
   ``/install/rhels9/``), as nodes require HTTP access to these during
   provisioning. Protect these paths with network-level controls instead.

Database Backups
----------------

Never store xCAT database backups under ``/install``. The database contains
BMC credentials, password table entries, and full cluster topology. Store
backups in a directory not served by Apache, for example::

    dumpxCATdb -p /root/xcat-backups

Network Binding
---------------

By default, Apache listens on all interfaces. In environments where the
management network is separate from other networks, bind Apache to the
management interface only::

    # /etc/httpd/conf/httpd.conf
    Listen 10.0.0.1:80

Replace ``10.0.0.1`` with the management node's IP on the provisioning
network.

IP-Based Access Control
-----------------------

For additional protection, restrict access to the provisioning subnet::

    # Apache 2.4+
    <Directory "/install">
        Options FollowSymLinks
        <IfModule mod_headers.c>
            Header always set X-Frame-Options SAMEORIGIN
            Header always set X-Content-Type-Options nosniff
            Header always set Content-Security-Policy "script-src 'self' 'unsafe-eval'"
            Header always set X-Permitted-Cross-Domain-Policies none
        </IfModule>
        AllowOverride None
        Require ip 10.0.0.0/16
    </Directory>
    <Directory "/install/postscripts">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require ip 10.0.0.0/16
    </Directory>
    <Directory "/install/post">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require ip 10.0.0.0/16
    </Directory>

Replace ``10.0.0.0/16`` with your management network CIDR in all blocks.
This ensures only nodes on the provisioning network can access install media.

.. note::

   If ``linuximage.otherpkgdir`` points to a custom path under ``/install``
   outside of ``/install/post`` (e.g., ``/install/custom/mypkgs``), add an
   additional ``<Directory>`` block for that path with ``Options Indexes``
   to allow recursive package downloads.

.. warning::

   If service nodes or hierarchical xCAT setups are in use, ensure all service
   node IPs are included in the allowed range.
