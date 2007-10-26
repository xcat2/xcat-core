#!/usr/bin/awk -f
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
BEGIN {
  ns = "/inet/tcp/0/127.0.0.1/301"

  print "<xcatrequest>" |& ns
  print "<command>nextdestiny</command>" |& ns
  print "</xcatrequest>" |& ns

  while (1) {
    if ((ns |& getline) > 0) {
      print $0 > "/tmp/destiny"
      if ($0 == "</xcatresponse>")
        break
    } else {
        close(ns)
        exit 1
    }
  }
  close(ns)
  exit 0
}
