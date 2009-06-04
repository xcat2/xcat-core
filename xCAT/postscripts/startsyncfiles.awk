#!/usr/bin/awk -f
BEGIN {
        if (ENVIRON["USEOPENSSLFORXCAT"]) {
            server = "openssl s_client -quiet -connect " ENVIRON["XCATSERVER"]
        } else {
            server = "/inet/tcp/0/127.0.0.1/400"
        }

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
