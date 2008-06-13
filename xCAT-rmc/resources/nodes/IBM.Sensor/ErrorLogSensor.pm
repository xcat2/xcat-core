#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'ErrorLogSensor'} = {
	Name => q(ErrorLogSensor),
	Command => "$::XCATROOT/sbin/rmcmon/monerrorlog",
	UserName => q(root),
	RefreshInterval => q(60),
	ControlFlags => q(4),
};
1;
