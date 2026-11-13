#!/usr/bin/awk -f
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#
# The Genesis copy of xCAT/postscripts/updateflag.awk. It writes no file: Genesis has no
# /var/log/xcat directory, rsyslog sends everything to /var/log/xcat.genesis, and gawk is
# fatal when it cannot open a redirect.

BEGIN {
    xcatdhost = ARGV[1]
    xcatdport = ARGV[2]
    flag = ARGV[3]

    if (!flag) flag = "next"

    if (xcatdhost ~ /^\[.*\]$/) {
        sub(/^\[/, "", xcatdhost)
        sub(/\]$/, "", xcatdhost)
    }
    netfamily = index(xcatdhost, ":") ? "inet6" : "inet"
    ns = "/" netfamily "/tcp/0/" xcatdhost "/" xcatdport

    loop = 0
    while(1) {
        if((ns |& getline) > 0)
            print $0 | "logger -t xcat -p local4.info"
        else {
            print "Retrying flag update" | "logger -t xcat -p local4.info"
            close(ns)
            system("sleep 10")
            loop = loop + 1
        }

        if($0 == "ready")
            print flag |& ns
        if($0 == "done")
            break
        if(loop > 10) {
            print "flag update failed" | "logger -t xcat -p local4.info"
            break
        }
    }

    close(ns)

    exit 0
}
