#!/usr/bin/awk -f
BEGIN {
        if (ENVIRON["USEOPENSSLFORXCAT"]) {
            server = "openssl s_client -connect " ENVIRON["XCATSERVER"] " -rand /bin/nice 2> /dev/null"
        } else {
            server = "/inet/tcp/0/127.0.0.1/400"
        }
        
        quit = "no"

        print "<xcatrequest>" |& server
        print "   <command>getpostscript</command>" |& server
        if ( ARGV[1] ) {
            args = sprintf("   <arg>%s</arg>", ARGV[1])
            print args |& server
        }
        print "</xcatrequest>" |& server

        start = 0
        while (server |& getline) {
                if (match($0,"<xcatresponse>")) {
                  start = 1
                }
                if (start == 1) {
                  print $0
                }

                if (match($0,"<serverdone>")) {
                  quit = "yes"
                }
                if (match($0,"</xcatresponse>") && match(quit,"yes")) {
                  close(server)
                  exit
               }
        }
}
