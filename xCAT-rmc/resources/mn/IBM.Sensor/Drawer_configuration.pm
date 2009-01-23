#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'Drawer_configuration'} = {
	Name => q(Drawer_configuration),
	Command => "/tmp/fake",
	UserName => q(root),
	RefreshInterval => q(0),
	ControlFlags => q(0),#change to 8 for rsct 2.5.3.0 and greater
	Description => q(This sensor is refreshed when a drawer (FSP) has not been populated with its server-specific configuration data. It is also refreshed when the drawer is back to normal.),
};
1;
