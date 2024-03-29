OpenSSL Configuration
=====================

xCAT does not ship OpenSSL RPMS nor does it statically link to any OpenSSL libraries.  Communication between the xCAT client and daemon utilizes OpenSSL and the administrator can configure the SSL_version and SSL_cipher that should be used by xCAT daemons.

The configuration is stored in the xCAT site table using the ``site.xcatsslversion`` and ``site.xcatsslciphers`` attributes.

Configuration
-------------

``site.xcatsslversion`` is the ``SSL_version`` option used by ``xcatd`` and passed to ``IO::Socket::SSL->start_SSL()``. See https://metacpan.org/pod/IO::Socket::SSL for more information. By default, xCAT ships with an empty value for ``site.xcatsslversion``. In this case, ``xcatd`` will use ``SSLv23:!SSLv2:!SSLv3:!TLSv1`` internally.

Here is an example of changing ``site.xcatsslversion`` to a different value, ``TLSv1_2``, for example. ::

    chtab key=xcatsslversion site.value=TLSv1_2

If running > ``TLSv1``, it is possible to disable insecure ciphers.  Here's an example of one possible configuration: ::

    "xcatsslciphers","kDH:kEDH:kRSA:!SSLv3:!SSLv2:!aNULL:!eNULL:!MEDIUM:!LOW:!MD5:!EXPORT:!CAMELLIA:!ECDH",,

After making any changes to these configuration values, ``xcatd`` must be restarted: ::

    service restart xcatd

If any mistakes have been made and communication is lost to xCAT, use ``XCATBYPASS`` to fix the bad configuration: ::

    XCATBYPASS=1 tabedit site


Validation
----------

Use the ``openssl`` command to validate the SSL configuration is valid and expected.

* To check whether TLSv1 is supported by xcatd: ::

    openssl s_client -connect 127.0.0.1:3001 -tls1

* To check if SSLv3 is disabled on ``xcatd``: ::

    openssl s_client -connect localhost:3001 -ssl3

  You should get a response similar to: ::

    70367087597568:error:14094410:SSL routines:SSL3_READ_BYTES:sslv3 alert handshake failure:s3_pkt.c:1259:SSL alert number 40
    70367087597568:error:1409E0E5:SSL routines:SSL3_WRITE_BYTES:ssl handshake failure:s3_pkt.c:598:
