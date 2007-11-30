#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#egan@us.ibm.com

$bits = ((2 ** 32) - 1) << (32 - $ARGV[0]);

printf "%d.",($bits & 0xff000000) >> 24;
printf "%d.",($bits & 0x00ff0000) >> 16;
printf "%d.",($bits & 0x0000ff00) >> 8;
printf "%d\n",($bits & 0x000000ff);

exit;
