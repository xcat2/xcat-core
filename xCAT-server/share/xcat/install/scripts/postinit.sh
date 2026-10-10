xcat_disable_postinit()
{
    if [ -f /xcatpost/mypostscript.post ]; then
        if [ "$1" = legacy ]; then
            OSVER=`grep '^OSVER=' /xcatpost/mypostscript.post | cut -d= -f2 | sed s/\'//g`
        fi
        RUNBOOTSCRIPTS=`grep 'RUNBOOTSCRIPTS=' /xcatpost/mypostscript.post | cut -d= -f2 | tr -d \'\" | tr A-Z a-z`
        XCATDEBUGMODE=`grep 'XCATDEBUGMODE=' /xcatpost/mypostscript.post | cut -d= -f2 | tr -d \'\" | tr A-Z a-z`
        MASTER_IP=`grep '^MASTER_IP=' /xcatpost/mypostscript.post | cut -d= -f2 | sed s/\'//g`
    fi
    [ -f /xcatpost/mypostscript ] && NODESTATUS=`grep 'NODESTATUS=' /xcatpost/mypostscript | awk -F = '{print $2}' | tr -d \'\" | tr A-Z a-z`
    [ -z "$NODESTATUS" ] && NODESTATUS="1"

    case "$1:$OSVER" in
    legacy:ubuntu*)
        case "$RUNBOOTSCRIPTS" in
        1|yes|y) ;;
        *) update-rc.d -f xcatpostinit1 remove ;;
        esac
        case "$XCATDEBUGMODE" in
        1|2) msgutil_r "$MASTER_IP" "debug" "update-rc.d -f xcatpostinit1 remove" "/var/log/xcat/xcat.log" "xcat.xcatinstallpost" ;;
        esac
        ;;
    *)
        case "$RUNBOOTSCRIPTS" in 1|yes|y) return 0 ;; esac
        case "$NODESTATUS" in 1|yes|y) return 0 ;; esac
        if [ "$1" = legacy ]; then
            chkconfig xcatpostinit1 off
            case "$XCATDEBUGMODE" in
            1|2) msgutil_r "$MASTER_IP" "debug" "service xcatpostinit1 disabled" "/var/log/xcat/xcat.log" "xcat.xcatinstallpost" ;;
            esac
        else
            systemctl disable xcatpostinit1.service
            case "$XCATDEBUGMODE" in
            1|2) msgutil_r "$MASTER_IP" "debug" "systemctl disable xcatpostinit1.service" "/var/log/xcat/xcat.log" "xcat.xcatinstallpost" ;;
            esac
        fi
        ;;
    esac
}
