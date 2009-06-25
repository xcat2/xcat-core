#!/usr/bin/awk -f
BEGIN {
        server = "openssl s_client -quiet -connect " ENVIRON["XCATSERVER"]

        quit = "no"

        print "<xcatrequest>" |& server
        print "   <command>syncfiles</command>" |& server
        print "</xcatrequest>" |& server

        while (server |& getline) {
                if (match($0,"<syncfiles done>")) {
                  quit = "yes"
                }
                if (match($0,"</xcatresponse>") && match(quit,"yes")) {
                  close(server)
                  exit
               }
        }
}
