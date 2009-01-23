#!/usr/bin/perl

$RES::Condition{'ISR_down'} = {
	Name => q(ISR_down),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32>0),
	RearmExpression => q(SD.Uint32 != SD@P.Uint32 && SD.Int32<0),	
        EventDescription => q(ISR is unavailable for use due to severe hardware error.),
	RearmDescription => q(ISR is back to normal.),
        SelectionString => q(Name="ISR_status"),
	ManagementScope => q(1),
	Severity => q(1),
        NoToggleExprFlag => q(1),
};
1;
