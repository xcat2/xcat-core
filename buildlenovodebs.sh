cd $(dirname $0)
GITUP=0 GPGSIGN=0 ./build-ubunturepo -c
mkdir tmplenovobuild
cd tmplenovobuild
tar xf /sources/core-debs-snap.tar.bz2
find . -type f -name *.deb -exec cp {} /prebuilt/ \;
