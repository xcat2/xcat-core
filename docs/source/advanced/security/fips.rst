Installing xCAT on a FIPS-enabled system
========================================

xCAT can run on a management node that was booted with the operating system's
FIPS mode enabled.  xCAT uses the system OpenSSL library for its CA, server,
client, and daemon TLS credentials.  It does not provide a separate validated
cryptographic module.

Enable FIPS mode while installing the operating system, before installing
xCAT.  On RHEL 8, follow the `Red Hat FIPS installation guidance
<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/security_hardening/switching-rhel-to-fips-mode_security-hardening>`_.
After the management node boots, verify the kernel state before installing
xCAT: ::

    fips-mode-setup --check
    cat /proc/sys/crypto/fips_enabled

The second command must print ``1``.  xCAT uses this kernel value when choosing
FIPS-compatible defaults.

Installation behavior
---------------------

During its initial RPM configuration, xCAT generates RSA 2048-bit CA, server,
and client keys.  The certificates use SHA-384 signatures.

In RHEL 8 FIPS mode, DSA and Ed25519 SSH keys are not available.
xCAT retains its RSA keys and treats the unavailable key types as optional.

When their own kernel or switch OS runs in FIPS mode, legacy Genesis and
Cumulus discovery use P-256 bootstrap keys.  The management node's FIPS
setting does not enable FIPS mode on discovered nodes.  OpenEmbedded Genesis
uses RSA 2048-bit bootstrap keys.

After installing xCAT, verify the daemon and generated certificates: ::

    systemctl is-active xcatd
    openssl x509 -in /etc/xcat/ca/ca-cert.pem -noout -text | grep 'Signature Algorithm'
    openssl x509 -in /etc/xcat/cert/server-cert.pem -noout -text | grep 'Signature Algorithm'

The default xCAT TLS policy permits TLS 1.2 and newer.  Leave
``site.xcatsslversion`` empty and ``site.xcattlspolicy`` set to ``modern`` so
the system OpenSSL policy can select permitted protocols and ciphers.

ISC DHCP and BIND
-----------------

When ``site.dhcpomapialgorithm`` is unset outside FIPS mode, xCAT uses
``hmac-md5``.  For new installations on Enterprise Linux 9 or later and
Ubuntu 20.04 or later, xCAT sets ``hmac-sha256`` during initialization.

On new FIPS installations, xCAT saves ``hmac-sha256`` in the site table so
management and service nodes use the same algorithm.  In FIPS mode, if
this attribute is unset, xCAT also selects ``hmac-sha256``.  In FIPS mode,
xCAT rejects an explicit ``site.dhcpomapialgorithm=hmac-md5``.  When regenerating BIND
keys, xCAT reconciles their algorithm with that policy.  To retain another
supported non-MD5 algorithm, set it explicitly in the site table before
regenerating DHCP and DNS configuration.

SHA-based OMAPI requires an ``omshell`` binary with the ``key-algorithm``
command.  Before using SHA-based OMAPI, ``makedhcp`` and ``dhcpop`` check the
configured binary without connecting to a server.  If this check fails,
upgrade ISC DHCP or set ``site.dhcpomshellpath`` to a compatible binary.

The RPMs do not impose a DHCP version requirement for SHA support.
xCAT skips the capability check for MD5.  Kea does not use OMAPI.
On RHEL 8, when SHA support is needed, update the ISC packages together: ::

    dnf upgrade dhcp-server dhcp-common dhcp-libs
    rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}\n' dhcp-server

To migrate an existing installation, run these commands: ::

    chtab key=dhcpomapialgorithm site.value=hmac-sha256
    makedns -n
    makedhcp -n
    makedhcp -a

Validation boundary
-------------------

Installing a FIPS-enabled management node does not qualify its boot images
for FIPS mode.  Validate the Genesis image separately before adding
``fips=1`` to its kernel command line.  Legacy images can omit integrity
files required by their bundled cryptographic libraries.

FIPS validation applies to cryptographic modules, not to xCAT as a complete
product.  Hardware-management protocols and devices must be checked
separately.  In particular, IPMI, SNMP, PDUs, switches, and BMCs can require
legacy authentication or encryption algorithms that a FIPS policy disables.
Validate each enabled management path against the site's security policy.
