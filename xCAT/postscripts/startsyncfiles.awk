#!/usr/bin/awk -f
BEGIN {
  if (ENVIRON["USEOPENSSLFORXCAT"]) {
      server = "openssl s_client -no_ssl3 -no_ssl2 -connect " ENVIRON["XCATSERVER"] " 2> /dev/null"
  } else {
      server = "/inet/tcp/0/127.0.0.1/400"
  }

  quit = "no"
  exitcode = 0

  print "<xcatrequest>" |& server
  print "   <command>syncfiles</command>" |& server
  print "</xcatrequest>" |& server

  while (server |& getline) {
    if (match($0,"<serverdone>")) {
      quit = "yes"
    }
    if ((match($0,"<errorcode>") && !match($0,"<errorcode>0")) \
      || (match($0,"<error>") && !match($0,"<error>0")) ) {
      exitcode = 1
    }

    if (match($0,"</xcatresponse>") && match(quit,"yes")) {
      close(server)
      exit exitcode
    }
  }
}
