#!/usr/bin/awk -f
BEGIN {
	xcatdhost = ARGV[1]
	xcatdport = ARGV[2]

	ns = "/inet/tcp/0/" ARGV[1] "/" xcatdport
        log_label=ENVIRON["LOGLABEL"]
        if(!log_label){
            log_label="xcat"
        }
	 while(1) {
                if((ns |& getline) > 0)
                        print $0 | "logger -t "log_label" -p local4.info "
                else {
                    print "Retrying unlock of tftp directory"
                    print "$0: Retrying unlock of tftp directory" | "logger -t "log_label" -p local4.info "
                    close(ns)
                    system("sleep 5")
                }

                if($0 == "ready")
                        print "unlocktftpdir" |& ns
                if($0 == "done")
                        break
        }
	close(ns)

	exit 0
}
