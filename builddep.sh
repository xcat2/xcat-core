#!/bin/sh
cd `dirname $0`
GREP=grep
export DESTDIR=`pwd`/dep-snap
export SRCDIR=`pwd`/dep-snap-srpms
UPLOAD=0
if [ "$1" == "UPLOAD" ]; then
   UPLOAD=1 
fi
if [ -f /etc/redhat-release ]
then
  pkg="redhat"
else
  pkg="packages"
fi

#rm -rf $DESTDIR
#rm -rf $SRCDIR
if [ $UPLOAD == 0 ]; then
 echo "Nothing new detected"
 exit 0;
fi
createrepo $DESTDIR
cd $DESTDIR/..
export DFNAME=dep-rpms-snap.`date +%Y.%m.%d`.tar.bz2
tar jcvf $DFNAME dep-snap
scp $DFNAME jbjohnso@shell1.sf.net:/home/groups/x/xc/xcat/htdocs/yum/
ssh jbjohnso@shell1.sf.net "cd /home/groups/x/xc/xcat/htdocs/yum/; rm -rf dep-snap; tar jxvf $DFNAME"
