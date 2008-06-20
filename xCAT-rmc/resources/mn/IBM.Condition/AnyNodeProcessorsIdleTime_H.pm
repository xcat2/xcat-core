#!/usr/bin/perl

$RES::Condition{'AnyNodeProcessorsIdleTime_H'} = {
	Name => q(AnyNodeProcessorsIdleTime_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AnyNodeProcessorsIdleTime events from the service nodes. An event will be generated when the average time all processors are idle at least 70 percent of the time.),
        RearmDescription => q(A rearm event will be generated when the idle time decreases below 10 percent.),
        SelectionString => q(Name="AnyNodeProcessorsIdleTime"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
