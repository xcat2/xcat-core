#!/usr/bin/perl
$RES::Sensor{'ErrorLogSensor'} = {
	Name => q(ErrorLogSensor),
	Command => "/etc/xcat/rmcmon/scripts/monerrorlog",
	UserName => q(root),
	RefreshInterval => q(60),
	ControlFlags => q(4),
};
1;
