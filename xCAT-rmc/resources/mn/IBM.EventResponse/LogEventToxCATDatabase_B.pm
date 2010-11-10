#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;

if (exists($ENV{RSCT_VER})) {
    my $rsct_ver=$ENV{RSCT_VER};
    if (xCAT::Utils->CheckVersion($rsct_ver, "2.3.5.0") < 0) { exit 0;} 
}
 
$RES::EventResponse{'LogEventToxCATDatabase_B'} = {
	Name => q(LogEventToxCATDatabase_B),
	Locked => q(0),
        EventBatching => q(1),
	Actions => q({[updatexCAT,{127},{0},{86400},/opt/xcat/sbin/rmcmon/logeventtoxcat,3,0,0,0,{},0]}),
};
1;
