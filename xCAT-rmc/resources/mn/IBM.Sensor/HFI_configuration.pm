#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'HFI_configuration'} = {
	Name => q(HFI_configuration),
	Command => "/tmp/fake",
	UserName => q(root),
	RefreshInterval => q(0),
	ControlFlags => q(0),  #change to 8 for rsct 2.5.3.0 and greater
	Description => q(This sensor is refreshed when an HFI did not get configured during server power-on. It is also refreshed when the HFI is configured.),
};
1;
