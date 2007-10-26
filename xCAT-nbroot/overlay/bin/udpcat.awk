#!/usr/bin/awk -f
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
BEGIN {
  xcatdport = ARGV[2]
  xcatdhost = ARGV[1]
  delete ARGV[1]
  delete ARGV[2]
  RS=""
}
END {
  print $0 |& "/inet/udp/301/"xcatdhost"/"xcatdport
}
