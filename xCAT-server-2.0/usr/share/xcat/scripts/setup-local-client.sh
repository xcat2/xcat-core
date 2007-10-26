
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# not sure about this logic 
#	- it seems most(or all) of the time when using a socket
#	     the gettab call will fail since the certificates are
#	     not ready or have changed?
#	- how would the user specify some other XCATDIR?

#XCATDIR=`gettab key=xcatconfdir site.value`

if [ -z "$XCATDIR" ]; then
  XCATDIR=/etc/xcat
fi
if [ -z "$1" ]; then
  set `whoami`
fi
CNA="$*"
USERHOME=`getent passwd $1|awk -F: '{print $6}'`
XCATCADIR=$XCATDIR/ca

if [ -e $USERHOME/.xcat ]; then
  exit 0
  echo -n "$USERHOME/.xcat already exists, delete and start over (y/n)?"
  read ANSWER
  if [ "$ANSWER" != "y" ]; then
    echo "Aborting at user request"
    exit 0
  fi
  rm -rf $USERHOME/.xcat
fi
mkdir -p $USERHOME/.xcat
cd $USERHOME/.xcat
openssl genrsa -out client-key.pem 2048
openssl req -config $XCATCADIR/openssl.cnf -new -key client-key.pem -out client-req.pem -subj "/CN=$CNA"
cp client-req.pem  $XCATDIR/ca/root.csr
cd -
cd $XCATDIR/ca

#   - "make sign" doesn't work on my AIX test system????
#   - seems to be a problem with the use of the wildcard in the Makefile
#   - calling cmds directly instead - should be safe
# make sign
openssl ca -config openssl.cnf -in root.csr -out root.cert
if [ -f root.cert ]; then
    rm root.csr
fi

cp root.cert $USERHOME/.xcat/client-cert.pem
cp ca-cert.pem $USERHOME/.xcat/ca.pem
chown $1 -R $USERHOME/.xcat
find $USERHOME/.xcat -type f -exec chmod 600 {} \;
find $USERHOME/.xcat -type d -exec chmod 700 {} \;
cd -

