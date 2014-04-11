#XCATDIR=`gettab key=xcatconfdir site.value`
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
if [ -z "$XCATROOT" ]; then
  XCATROOT=/opt/xcat
fi
if [ -z "$XCATDIR" ]; then
  XCATDIR=/etc/xcat
fi
if [ -z "$1" ]; then
  echo "Usage: $0 <CA name>"
  exit 1
fi
CNA="$*"

XCATCADIR=$XCATDIR/ca

if [ -e $XCATDIR/ca ]; then
  echo -n "Existing xCAT certificate authority detected at $XCATDIR/ca, delete? (y/n):"
  read ANSWER
  if [ $ANSWER != 'y' ]; then
    echo "Aborting install at user request"
    exit 0;
  fi
  rm -rf $XCATDIR/ca
  mkdir -p $XCATDIR/ca
else
  mkdir -p $XCATDIR/ca
fi
sed -e "s@##XCATCADIR##@$XCATCADIR@" $XCATROOT/share/xcat/ca/openssl.cnf.tmpl > $XCATCADIR/openssl.cnf
cp $XCATROOT/share/xcat/ca/Makefile $XCATCADIR/
cd $XCATCADIR
make init
#openssl req -nodes -config openssl.cnf -days 7300 -x509 -newkey rsa:2048 -out ca-cert.pem -extensions v3_ca -outform PEM -subj /CN="$CNA"
openssl genrsa -out private/ca-key.pem 2048
chmod 600 private/ca-key.pem
openssl req -new -key private/ca-key.pem -config openssl.cnf -out ca-req.csr -subj /CN="$CNA" -outform PEM
openssl ca -selfsign -keyfile private/ca-key.pem -in ca-req.csr -startdate 19700101010101Z -days 7305 -extensions v3_ca -config openssl.cnf -out ca-cert.pem
cd -
