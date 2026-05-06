TLS configuration
=================

xCAT does not ship OpenSSL RPMs and does not statically link OpenSSL. xCAT client and daemon connections use TLS through the system OpenSSL library. Some site table attribute names still contain ``ssl`` for backward compatibility, but they configure TLS behavior.

Use these site table attributes to configure xCAT TLS behavior:

* ``site.xcattlspolicy``
* ``site.xcatsslversion``
* ``site.xcatsslciphers``

Protocol policy
---------------

``site.xcattlspolicy`` controls the default xCAT TLS protocol policy when ``site.xcatsslversion`` is empty.

The default policy is ``modern``. It permits TLS 1.2 and newer. Internally, ``xcatd`` passes this value to ``IO::Socket::SSL``: ::

    SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1

The ``SSLv23`` token is legacy OpenSSL naming for a version-flexible handshake. It does not mean that SSLv2 or SSLv3 are allowed. The exclusions determine which protocols can be negotiated.

Use ``legacy`` only when older nodes or service nodes cannot negotiate TLS 1.2, for example EL6 and older, SLES 11 and older, or Ubuntu 12.04 and older. The legacy policy allows TLS 1.0 and newer while still disabling SSLv2 and SSLv3: ::

    chtab key=xcattlspolicy site.value=legacy

Administrator overrides
-----------------------

``site.xcatsslversion`` overrides the ``SSL_version`` option that ``xcatd`` passes to ``IO::Socket::SSL->start_SSL()``. Most sites should leave it empty and use ``site.xcattlspolicy`` instead. If this value is non-empty, it takes precedence over ``site.xcattlspolicy``. See https://metacpan.org/pod/IO::Socket::SSL for the accepted syntax.

To force the ``IO::Socket::SSL`` setting to ``TLSv1_2``: ::

    chtab key=xcatsslversion site.value=TLSv1_2

``site.xcatsslciphers`` is an administrator override for the TLS cipher list. By default, leave it empty so xCAT uses the OpenSSL library defaults. If a local security policy requires an explicit cipher list, here is an example of one possible configuration: ::

    "xcatsslciphers","kDH:kEDH:kRSA:!SSLv3:!SSLv2:!aNULL:!eNULL:!MEDIUM:!LOW:!MD5:!EXPORT:!CAMELLIA:!ECDH",,

After making any changes to these configuration values, ``xcatd`` must be restarted: ::

    systemctl restart xcatd

On non-systemd systems, use: ::

    service xcatd restart

If a bad TLS value blocks xCAT client connections, use ``XCATBYPASS`` to edit the site table locally: ::

    XCATBYPASS=1 tabedit site


Validation
----------

Use ``openssl`` to check what ``xcatd`` will negotiate.

* To check that the default modern policy rejects TLSv1: ::

    openssl s_client -connect 127.0.0.1:3001 -tls1

  The handshake should fail unless ``site.xcattlspolicy`` is set to ``legacy`` or ``site.xcatsslversion`` explicitly allows TLSv1.

* To check that ``xcatd`` rejects SSLv3: ::

    openssl s_client -connect localhost:3001 -ssl3

  You should get a response similar to: ::

    70367087597568:error:14094410:SSL routines:SSL3_READ_BYTES:sslv3 alert handshake failure:s3_pkt.c:1259:SSL alert number 40
    70367087597568:error:1409E0E5:SSL routines:SSL3_WRITE_BYTES:ssl handshake failure:s3_pkt.c:598:
