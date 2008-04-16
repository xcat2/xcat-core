#!/usr/bin/awk -f
BEGIN {
        listener = "/inet/tcp/300/0/0"
        server = "/inet/tcp/0/127.0.0.1/400"
        quit = "no"


        print "<xcatrequest>" |& server
        print "   <command>getcredentials</command>" |& server
        print "   <callback_port>300</callback_port>" |& server
        print "   <arg>"ARGV[1]"</arg>" |& server
        print "</xcatrequest>" |& server

        while (match(quit,"no") && (listener |& getline) > 0) {
                if (match($0,"CREDOKBYYOU?")) {
                        print "CREDOKBYME" |& listener
                        quit="yes"
                }
        }
        close(listener)

        while (server |& getline) {
                print $0
        }
}
