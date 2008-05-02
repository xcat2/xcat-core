#!/usr/bin/awk -f
BEGIN {
        server = "/inet/tcp/0/127.0.0.1/400"
        quit = "no"


        print "<xcatrequest>" |& server
        print "   <command>getpostscript</command>" |& server
        print "   <scripttype>install</scripttype>" |& server
        print "</xcatrequest>" |& server

        while (server |& getline) {
                print $0
        }
}
