#!/usr/bin/perl

$RES::Condition{'HFI_not_configured'} = {
	Name => q(HFI_not_configured),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32>0),
	RearmExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32<0),	
        EventDescription => q(HFI did not get configured during server power-on.),
	RearmDescription => q(HFI is configured.),
        SelectionString => q(Name="HFI_configuration"),
	ManagementScope => q(1),
	Severity => q(1),
        NoToggleExprFlag => q(1),
};
1;
