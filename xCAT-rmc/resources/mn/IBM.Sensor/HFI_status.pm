#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'HFI_status'} = {
	Name => q(HFI_status),
	Command => "/tmp/fake",
	UserName => q(root),
	RefreshInterval => q(0),
	ControlFlags => q(0), #change to 8 for rsct 2.5.3.0 and greater
	Description => q(This sensor is refreshed when an HFI is unavailable for use due to severe HFI or ISR hardware error. It is also refreshed when the HFI is back to normal.),
};
1;
