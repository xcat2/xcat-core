#!/usr/bin/awk -f
BEGIN {
        port = ("XCAT_CREDENTIAL_CALLBACK_PORT" in ENVIRON) ? ENVIRON["XCAT_CREDENTIAL_CALLBACK_PORT"] : 300
        if (port !~ /^[0-9]+$/ || port < 1 || port > 65535) {
                port = 300
        }

        master = ("MASTER_IP" in ENVIRON) ? ENVIRON["MASTER_IP"] : ""
        if (master == "") {
                master = ("MASTER" in ENVIRON) ? ENVIRON["MASTER"] : ""
        }
        if (master ~ /:/) {
                listener = "/inet6/tcp/" port "/0/0"
        } else {
                listener = "/inet/tcp/" port "/0/0"
        }
        quit = "no"
       while (match(quit,"no")) {
         while ((listener |& getline) > 0) {
                 if (match($0,"CREDOKBYYOU?")) {
                         print "CREDOKBYME" |& listener
                   }
         }
         close(listener)
      }
}
