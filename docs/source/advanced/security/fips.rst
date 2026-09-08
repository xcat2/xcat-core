Installing xCAT on a FIPS-enabled system
========================================

xCAT can run on a management node that was booted with the operating system's
FIPS mode enabled.  xCAT uses the system OpenSSL library for its CA, server,
client, and daemon TLS credentials; it does not provide a separate validated
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
and client keys.  The certificates use SHA-384 signatures.  DSA and Ed25519
SSH keys are not available in RHEL 8 FIPS mode; xCAT retains its RSA keys and
treats the unavailable key types as optional.  Discovery bootstrap uses P-256
elliptic-curve keys in FIPS mode.

After installing xCAT, verify the daemon and generated certificates: ::

    systemctl is-active xcatd
    openssl x509 -in /etc/xcat/ca/ca-cert.pem -noout -text | grep 'Signature Algorithm'
    openssl x509 -in /etc/xcat/cert/server-cert.pem -noout -text | grep 'Signature Algorithm'

The default xCAT TLS policy permits TLS 1.2 and newer.  Leave
``site.xcatsslversion`` empty and ``site.xcattlspolicy`` set to ``modern`` so
the system OpenSSL policy can select permitted protocols and ciphers.

ISC DHCP and BIND
-----------------

On systems outside FIPS mode, legacy ISC DHCP OMAPI and BIND DDNS retain the
``hmac-md5`` compatibility default.  In FIPS mode, xCAT automatically selects
``hmac-sha256`` and rejects an explicit ``site.dhcpomapialgorithm=hmac-md5``.
An administrator can explicitly select a stronger supported algorithm if the
DHCP and DNS servers use the same setting.

On RHEL 8, SHA-based OMAPI authentication requires ``dhcp-server``
``12:4.3.6-48`` or later.  The ``xCAT`` and ``xCATsn`` RPMs enforce this
minimum.  A system on which only ``xCAT-server`` is installed must update ISC
DHCP explicitly: ::

    dnf upgrade dhcp-server dhcp-common dhcp-libs
    rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}\n' dhcp-server

Regenerate both configurations after changing an existing installation: ::

    makedns -n
    makedhcp -n
    makedhcp -a

Validation boundary
-------------------

FIPS validation applies to cryptographic modules, not to xCAT as a complete
product.  Hardware-management protocols and devices must be checked
separately.  In particular, IPMI, SNMP, PDUs, switches, and BMCs can require
legacy authentication or encryption algorithms that a FIPS policy disables.
Validate each enabled management path against the site's security policy.
