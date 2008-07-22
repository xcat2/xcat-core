#!/usr/bin/awk -f
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
BEGIN {
        localport = ARGV[1]
        ns = "/inet/tcp/0/127.0.0.1/" localport
        canexit = 0

        print "<xcatrequest>" |& ns
        print "<command>getbmcconfig</command>" |& ns
        print "</xcatrequest>" |& ns

        while (1) {
                if ((ns |& getline) > 0) {
                        print $0 > "/tmp/ipmi.data"
                        if ($0 ~ /<\/serverdone>/)
                            canexit = 1
                        if (canexit == 1 && $0 == "</xcatresponse>")
                                break
                } else {
                   close(ns)
                   exit 1
                }
        }
        close(ns)
        exit 0
}
