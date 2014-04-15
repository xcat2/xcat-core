# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#XCATDIR=`gettab key=xcatconfdir site.value`
if [ -z "$XCATDIR" ]; then
  XCATDIR=/etc/xcat
fi
if [ -z "$1" ]; then
  echo "Usage: $0 servername"
fi
umask 0077
CNA=$*

XCATCADIR=$XCATDIR/ca

if [ -e $XCATDIR/cert ]; then
  echo -n "$XCATDIR/cert already exists, delete and start over (y/n)?"
  read ANSWER
  if [ "$ANSWER" != "y" ]; then
    echo "Aborting at user request"
    exit 0
  fi
  rm -rf $XCATDIR/cert
fi
mkdir -p $XCATDIR/cert
cd $XCATDIR/cert
openssl genrsa -out server-key.pem 2048
openssl req -config $XCATCADIR/openssl.cnf -new -key server-key.pem -out server-req.pem -extensions server -subj "/CN=$CNA"
cp server-req.pem  $XCATDIR/ca/`hostname`.csr
cd -
cd $XCATDIR/ca

#   - "make sign" doesn't seem to work on my AIX system???
#   - seems to be a problem with the use of the wildcard in the Makefile
#   - call cmds directly instead - seems safe
# make sign

openssl ca -startdate 600101010101Z -config openssl.cnf -in `hostname`.csr -out `hostname`.cert -extensions server
if [ -f `hostname`.cert ]; then
    rm `hostname`.csr
fi

cp `hostname`.cert $XCATDIR/cert/server-cert.pem
#Put key and cert in a single file for the likes of conserver
cat $XCATDIR/cert/server-cert.pem $XCATDIR/cert/server-key.pem > $XCATDIR/cert/server-cred.pem 
cp ca-cert.pem $XCATDIR/cert/ca.pem
cd -

