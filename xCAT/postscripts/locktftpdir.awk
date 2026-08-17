#!/usr/bin/awk -f
BEGIN {
	xcatdhost = ARGV[1]
	xcatdport = ARGV[2]

	ns = "/inet/tcp/0/" ARGV[1] "/" xcatdport

	 while(1) {
                if((ns |& getline) > 0)
                        print $0 | "logger -t xcat -p local4.info"
                else { #socket dead, retry
                    print "TFTP lockdir request retrying" | "logger -t xcat -p local4.info"
                    close(ns)
                    system("sleep 1")
                }

                if($0 == "ready")
                        print "locktftpdir" |& ns
                if($0 == "done")
                        break
        }
	close(ns)

	exit 0
}
