# $Id: Makefile,v 1.4 2006/06/20 18:55:37 jmates Exp $
#
# NOTE If running OpenSSL 0.9.8a or higher, see -newkey, below.
#
# Automates the setup of a custom Certificate Authority and provides
# routines for signing and revocation of certificates. To use, first
# customize the commands in this file and the settings in openssl.cnf,
# then run:
#
# make init
#
# Then, copy in certificate signing requests, and ensure their suffix is
# .csr before signing them with the following command:
#
# make sign
#
# To revoke a key, name the certificate file with the cert option
# as shown below:
#
# make revoke cert=foo.cert
#
# This will revoke the certificate and call gencrl; the revocation list
# will then need to be copied somehow to the various systems that use
# your CA cert.

requests = *.csr

sign: ${requests}

# remove -batch option if want chance to not certify a particular request
${requests}: FORCE
	@openssl ca -config openssl.cnf -in $@ -out ${@:.csr=.cert}
	@[ -f ${@:.csr=.cert} ] && rm $@

revoke:
	@test $${cert:?"usage: make revoke cert=certificate"}
	@openssl ca -config openssl.cnf -revoke $(cert)
	@$(MAKE) gencrl

gencrl:
	@openssl ca -config openssl.cnf -gencrl -out ca-crl.pem

clean:
	-rm ${requests}

# creates required supporting files, CA key and certificate
init:
	@test ! -f serial
	@mkdir crl certs private
	@chmod go-rwx private
	@echo '01' > serial
	@touch index
	# NOTE use "-newkey rsa:2048" if running OpenSSL 0.9.8a or higher
#	@openssl req -nodes -config openssl.cnf -days 2650 -x509 -newkey rsa:2048 -out ca-cert.pem -outform PEM

help:
	@echo make sign
	@echo '  - signs all *.csr files in this directory'
	@echo
	@echo make revoke cert=filename
	@echo '  - revokes certificate in named file and calls gencrl'
	@echo
	@echo make gencrl
	@echo '  - updates Certificate Revocation List (CRL)'
	@echo
	@echo make clean
	@echo '  - removes all *.csr files in this directory'
	@echo
	@echo make init
	@echo '  - required initial setup command for new CA'

# for legacy make support
FORCE:
