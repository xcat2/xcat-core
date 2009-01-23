#!/usr/bin/perl

$RES::Condition{'Drawer_not_configured'} = {
	Name => q(Drawer_not_configured),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32>0),
	RearmExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32<0),	
        EventDescription => q(Drawer (FSP) has not been populated with its server-specific configuration data.),
	RearmDescription => q(Drawer (FSP) is configured.),
        SelectionString => q(Name="Drawer_configuration"),
	ManagementScope => q(1),
	Severity => q(1),
        NoToggleExprFlag => q(1),
};
1;
