#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#egan@us.ibm.com

$mask = pack("CCCC",$ARGV[0],$ARGV[1],$ARGV[2],$ARGV[3]);
$bits += unpack("%32b*", $mask);

print "$bits\n";

