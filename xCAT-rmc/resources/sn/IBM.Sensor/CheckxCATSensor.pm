#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

my $cmd="$::XCATROOT/sbin/rmcmon/check_xcatd";

$RES::Sensor{'CheckxCATSensor'} = {
	Name => q(CheckxCATSensor),
	Command => "$cmd",
	Description => "This sensor monitors the xcatd daemon.",
	UserName => q(root),
	RefreshInterval => q(60),
        ErrorExitValue => q(1),
        ControlFlags => q(0),
};
1;
