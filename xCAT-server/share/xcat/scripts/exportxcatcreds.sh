TEMPDIR=`mktemp -d /tmp/xcatcreds.$$.XXXX`
if [ -r /etc/xcat/cert/server-cert.pem ]; then
	SERVERNAME=`openssl x509 -in /etc/xcat/cert/server-cert.pem -noout -text|grep Subject:|sed -e 's/.*CN=//'`
	echo 'xcatserver='$SERVERNAME > $TEMPDIR/xcat.cfg
fi
cp $HOME/.xcat/ca.pem $TEMPDIR/ca.pem
openssl pkcs12 -export -in $HOME/.xcat/client-cert.pem -inkey $HOME/.xcat/client-key.pem -out $TEMPDIR/user.pfx
cd $TEMPDIR
ZIPNAME="xcat-server.zip"
if [ ! -z "$SERVERNAME" ]; then
	ZIPNAME="xcat-$SERVERNAME.zip"
fi
zip $HOME/$ZIPNAME *
cd -
echo "Credential package for powershell client can be found in $HOME/$ZIPNAME"
rm -rf $TEMPDIR
