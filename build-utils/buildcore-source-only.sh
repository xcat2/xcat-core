#!/bin/bash

# Source-only artifact delivery used by buildcore.sh.

function xcat_deliver_noarch_package {
    local rpmname="$1"

    if ! xcat_source_only; then
        rm -f $DESTDIR/$rpmname*rpm
        mv $source/RPMS/$NOARCH/$rpmname-$VER*rpm $DESTDIR
    fi
    rm -f $SRCDIR/$rpmname*rpm
    mv $source/SRPMS/$rpmname-$VER*rpm $SRCDIR
}

function xcat_deliver_genesis_packages {
    if ! xcat_source_only; then
        rm -f $DESTDIR/xCAT-genesis-scripts*rpm
        mv $source/RPMS/noarch/xCAT-genesis-scripts-*rpm $DESTDIR
    fi
    rm -f $SRCDIR/xCAT-genesis-scripts*rpm
    mv $source/SRPMS/xCAT-genesis-scripts-*rpm $SRCDIR
}

function xcat_deliver_arch_package {
    local rpmname="$1"

    if ! xcat_source_only; then
        rm -f $DESTDIR/$rpmname-$SHORTSHORTVER*rpm
        mv $source/RPMS/*/$rpmname-$VER*rpm $DESTDIR
    fi
    rm -f $SRCDIR/$rpmname-$SHORTSHORTVER*rpm
    mv $source/SRPMS/$rpmname-$VER*rpm $SRCDIR
}

function xcat_deliver_embed_links {
    if xcat_source_only; then
        return
    fi
    if [ -n "$EMBED" -a -n "$EMBEDLINK" ]; then
        cd $DESTDIR
        maindir="../../$XCATCORE"
        for rpmname in $EMBEDLINK; do
            if [ "$rpmname" = "xCAT" -o "$rpmname" = "xCATsn" ]; then
                if [ "$EMBED" = "zvm" ]; then
                    echo "Creating link for $rpmname-$SHORTSHORTVER"'*.s390x.rpm'
                    rm -f $rpmname-$SHORTSHORTVER*rpm
                    ln -s $maindir/$rpmname-$SHORTSHORTVER*.s390x.rpm .
                fi
            else
                echo "Creating link for $rpmname-$SHORTSHORTVER"'*rpm'
                rm -f $rpmname-$SHORTSHORTVER*rpm
                ln -s $maindir/$rpmname-$SHORTSHORTVER*rpm .
            fi
        done
        cd - >/dev/null
    fi
}

function xcat_create_binary_tarball {
    if xcat_source_only; then
        echo "Not creating $TARNAME: a source-only build makes no binary rpms."
        return
    fi

    echo "Creating $(dirname $DESTDIR)/$TARNAME ..."
    if [[ -e $TARNAME ]]; then
        mkdir -p previous
        mv -f $TARNAME previous
    fi
    if [ "$OSNAME" = "AIX" ]; then
        tar $verboseflag -hcf ${TARNAME%.gz} $XCATCORE
        gzip ${TARNAME%.gz}
    else
        tar $verboseflag -hjcf $TARNAME $XCATCORE
    fi
    chgrp $SYSGRP $TARNAME
    chmod g+w $TARNAME
}

function xcat_publish_tarball_link {
    if [ -n "$DEST" ] && ! xcat_source_only; then
        ln -sf $(basename `pwd`)/$TARNAME ../$TARNAME
        if [ $? != 0 ]; then
            echo "ERROR: Failed to make symbol link $DEST/$TARNAME"
        fi
    fi
}
