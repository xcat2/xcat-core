# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# To create certficate for docker host
echo "$0 xcatdockerhost"

umask 0077
CNA="xcatdockerhost"

XCATDOCKERDIR=/etc/xcatdockerca
XCATDOCKERCADIR=$XCATDOCKERDIR/ca

if [ ! -e $XCATDOCKERDIR ]; then
  mkdir -p $XCATDOCKERDIR
  mkdir -p $XCATDOCKERCADIR
fi

if [ ! -e $XCATDOCKERCADIR/openssl.cnf ]; then
  cp /etc/xcat/ca/openssl.cnf $XCATDOCKERCADIR/
fi
if [ ! -e $XCATDOCKERCADIR/ca-cert.pem ]; then
  cp /etc/xcat/ca/ca-cert.pem $XCATDOCKERCADIR/
fi

if [ ! -e $XCATDOCKERCADIR/private/ca-key.pem ]; then
  mkdir -p $XCATDOCKERCADIR/private
  cp /etc/xcat/ca/private/ca-key.pem $XCATDOCKERCADIR/private/
fi

if [ -e $XCATDOCKERDIR/cert ]; then
  echo -n "$XCATDOCKERDIR/cert already exists, delete and start over (y/n)?"
  read ANSWER
  if [ "$ANSWER" != "y" ]; then
    echo "Aborting at user request"
    exit 0
  fi
  rm -rf $XCATDOCKERDIR/cert
fi
mkdir -p $XCATDOCKERDIR/cert


cd $XCATDOCKERDIR

if [ ! -e $XCATDOCKERCADIR/openssl.cnf ]; then
  echo -n "$XCATDOCKERCADIR/openssl.cnf not exist"
  exit 1
fi
sed -i "s@^dir.*=.*/etc/xcat/ca@dir = $XCATDOCKERCADIR@g" $XCATDOCKERCADIR/openssl.cnf 

if [  -e $XCATDOCKERCADIR/index ]; then
  rm -f $XCATDOCKERCADIR/index*
fi
touch $XCATDOCKERCADIR/index

echo "00" > $XCATDOCKERCADIR/serial


if [ ! -e $XCATDOCKERCADIR/certs ]; then
  mkdir -p $XCATDOCKERCADIR/certs
fi

openssl genrsa -out ca/dockerhost-key.pem 2048
openssl req -config ca/openssl.cnf -new -key ca/dockerhost-key.pem -out cert/dockerhost-req.pem -extensions server -subj "/CN=$CNA"
mv cert/dockerhost-req.pem  ca/$CNA\.csr
cd -
cd $XCATDOCKERCADIR

#   - "make sign" doesn't seem to work on my AIX system???
#   - seems to be a problem with the use of the wildcard in the Makefile
#   - call cmds directly instead - seems safe
# make sign

#CA certificate and CA private key do not match
openssl ca -startdate 600101010101Z -config openssl.cnf -in $CNA\.csr -out $CNA\.cert -extensions server -batch
#openssl ca -selfsign -config openssl.cnf -in $CNA\.csr -startdate 700101010101Z -days 7305 -out $CNA\.cert -extensions v3_ca -batch
if [ -f $CNA\.cert ]; then
    rm $CNA\.csr
fi

mv $CNA\.cert $XCATDOCKERDIR/cert/dockerhost-cert.pem
cat dockerhost-key.pem >> $XCATDOCKERDIR/cert/dockerhost-cert.pem

cd -
