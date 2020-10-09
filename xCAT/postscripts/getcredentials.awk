#!/usr/bin/awk -f
BEGIN {
        if (!system("test -f /usr/bin/nice")) {
           randombytes = "-rand /usr/bin/nice"
        } else {
           randombytes = ""
        }
        if (!system("test -f openssl")) {
           print "Error: openssl utility missing"
           exit 1
        }

        if ((ENVIRON["USEOPENSSLFORXCAT"]) || (ENVIRON["AIX"])) {
            server = "openssl s_client -quiet -no_ssl3 -connect " ENVIRON["XCATSERVER"] " "randombytes" 2> /dev/null"
            if (!system("openssl s_client -help 2>&1 | grep -m 1 -q -- -no_ssl2")) {
                server = "openssl s_client -quiet -no_ssl3 -no_ssl2 -connect " ENVIRON["XCATSERVER"] " "randombytes" 2> /dev/null"
            }
        } else {
            server = "/inet/tcp/0/127.0.0.1/400"
        }
        quit = "no"


        print "<xcatrequest>" |& server
        print "   <command>getcredentials</command>" |& server
        print "   <callback_port>300</callback_port>" |& server
        for (i=1; i<ARGC; i++)
            print "   <arg>"ARGV[i]"</arg>" |& server
        print "</xcatrequest>" |& server

        while (server |& getline) {
                if (match($0,"<xcatdsource>") == 0) {
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
