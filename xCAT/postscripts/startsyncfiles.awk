#!/usr/bin/awk -f
BEGIN {
  server = "openssl s_client -quiet -connect " ENVIRON["XCATSERVER"] " 2> /dev/null"

  quit = "no"
  exitcode = 1

  print "<xcatrequest>" |& server
  print "   <command>syncfiles</command>" |& server
  print "</xcatrequest>" |& server

  while (server |& getline) {
    if (match($0,"<serverdone>")) {
      quit = "yes"
    }
    if (match($0,"<errorcode>") || match($0,"<error>")) {
      exitcode = 0
    }

    if (match($0,"</xcatresponse>") && match(quit,"yes")) {
      close(server)
      exit exitcode
    }
  }
}
