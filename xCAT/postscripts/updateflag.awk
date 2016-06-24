#!/usr/bin/awk -f
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

BEGIN {
    xcatdhost = ARGV[1]
    xcatdport = ARGV[2]
    flag = ARGV[3]
    
    if (!flag) flag = "next"

    ns = "/inet/tcp/0/" ARGV[1] "/" xcatdport

    loop = 0
    while(1) {
        if((ns |& getline) > 0)
            print $0 | "logger -t xcat -p local4.info"
        else {
            print "Retrying flag update" | "logger -t xcat -p local4.info"
            print "updateflag.awk: Retrying flag update" >> "/var/log/xcat/xcat.log"
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
            print "updateflag.awk: flag update failed" >> "/var/log/xcat/xcat.log"
            break
        }
    }

    close(ns)

    exit 0
}

