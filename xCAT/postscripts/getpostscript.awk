#!/usr/bin/awk -f
BEGIN {
        if (ENVIRON["USEOPENSSLFORXCAT"]) {
            server = "openssl s_client -quiet -connect " ENVIRON["XCATSERVER"] " 2> /dev/null"
        } else {
            server = "/inet/tcp/0/127.0.0.1/400"
        }


        quit = "no"


        print "<xcatrequest>" |& server
        print "   <command>getpostscript</command>" |& server
        print "</xcatrequest>" |& server

        while (server |& getline) {
                print $0 
                if (match($0,"<serverdone>")) {
                  quit = "yes"
                }
                if (match($0,"</xcatresponse>") && match(quit,"yes")) {
                  close(server)
                  exit
               }
        }
}
