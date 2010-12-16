#!/usr/bin/perl

my $cmd;
if (-r "/var/xcat/rmcmon/scripts/monerrorlog") {
   $cmd="/var/xcat/rmcmon/scripts/monerrorlog";
} else {
   $cmd="/opt/xcat/sbin/rmcmon/monerrorlog";
}

$RES::Sensor{'ErrorLogSensor'} = {
	Name => q(ErrorLogSensor),
	Command => "$cmd",
	UserName => q(root),
	RefreshInterval => q(60),
	ControlFlags => q(4),
};
1;
