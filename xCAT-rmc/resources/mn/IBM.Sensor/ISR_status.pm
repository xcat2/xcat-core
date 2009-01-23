#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'ISR_status'} = {
	Name => q(ISR_status),
	Command => "/tmp/fake",
	UserName => q(root),
	RefreshInterval => q(0),
	ControlFlags => q(0), #change to 8 for rsct 2.5.3.0 and greater
	Description => q(This sensor is refreshed when an ISR is unavailable for use due to severe hardware error. It is also refreshed when ISR is back to normal.),
};
1;
