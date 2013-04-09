#!/bin/bash
# IBM(c) 2013  EPL license http://www.eclipse.org/legal/epl-v10.html
exec 13<>/dev/udp/$1/$2
echo "resourcerequest: xcatd" >&13
parpid=$$
touch /tmp/goahead.$parpid
touch /tmp/killme.$parpid
exec 2> /dev/null
while ! grep 'resourcerequest: ok' /tmp/goahead.$parpid > /dev/null; do
	(
	  mypid=$BASHPID
	  (sleep $(((RANDOM%60)+120)).$((RANDOM%50)); if [ -f /tmp/killme.$parpid ]; then kill -TERM $mypid; fi) &
	  exec awk '{print $0 > "/tmp/goahead.'$parpid'";exit}' <&13
	)	
done
rm /tmp/killme.$parpid

