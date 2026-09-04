do_configure:s390x() {
    LDCONFIG=true ${S}/configure --prefix=${prefix} --shared --libdir=${libdir} --uname=GNU --disable-crcvx
}
