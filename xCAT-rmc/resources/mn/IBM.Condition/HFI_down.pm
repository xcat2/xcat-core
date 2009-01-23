#!/usr/bin/perl

$RES::Condition{'HFI_down'} = {
	Name => q(HFI_down),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32>0),
	RearmExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32<0),	
        EventDescription => q(HFI is unavailable for use due to severe HFI or ISR hardware error.),
	RearmDescription => q(HFI is back to normal.),
        SelectionString => q(Name="HFI_status"),
	ManagementScope => q(1),
	Severity => q(1),
        NoToggleExprFlag => q(1),
};
1;
