#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

my $cmd;
if ($^O =~ /^linux/i) { $cmd="$::XCATROOT/sbin/rmcmon/monerrorlog";}
else {$cmd="$::XCATROOT/sbin/rmcmon/monaixsyslog";}

$RES::Sensor{'IBSwitchLogSensor'} = {
	Name => q(IBSwitchLogSensor),
	Command => "$cmd -p local6.info",
	UserName => q(root),
	RefreshInterval => q(60),
        ErrorExitValue => q(1),
        ControlFlags => q(0),
};
1;
