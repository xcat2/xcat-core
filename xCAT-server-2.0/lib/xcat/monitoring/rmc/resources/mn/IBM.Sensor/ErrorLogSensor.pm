#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'ErrorLogSensor'} = {
	Name => q(ErrorLogSensor),
	Command => "$::XCATROOT/lib/perl/xCAT_monitoring/rmc/monerrorlog",
	UserName => q(root),
	RefreshInterval => q(60),
	ControlFlags => q(4),
};
1;
