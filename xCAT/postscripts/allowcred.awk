#!/usr/bin/awk -f
BEGIN {
        listener = "/inet/tcp/300/0/0"
        quit = "no"


        while (match(quit,"no") && (listener |& getline) > 0) {
                if (match($0,"CREDOKBYYOU?")) {
                        print "CREDOKBYME" |& listener
                        quit="yes"
                }
        }
        close(listener)
}
