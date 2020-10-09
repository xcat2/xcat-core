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

        if (ENVIRON["USEOPENSSLFORXCAT"]) {
            server = "openssl s_client -no_ssl3 -connect " ENVIRON["XCATSERVER"] " "randombytes" 2> /dev/null"
            if (!system("openssl s_client -help 2>&1 | grep -m 1 -q -- -no_ssl2")) {
                server = "openssl s_client -no_ssl3 -no_ssl2 -connect " ENVIRON["XCATSERVER"] " "randombytes" 2> /dev/null"
            }
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
                  if (match($0,"<xcatdsource>") == 0) {
                    print $0
                  }
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
