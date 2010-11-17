#!/usr/bin/perl

$RES::Condition{'AnyNodeRealMemFree_H'} = {
	Name => q(AnyNodeRealMemFree_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the events from the condition AnyNodeRealMemFree on the service nodes. The AnyNodeRealMemFree condition monitors the compute nodes. An event is generated when the percentage of real memory that are free falls below 5 percent),
        RearmDescription => q(An rearm event will be generated after the percentage of the real free memory on the compute nodes exceeds 10 percent.),
        SelectionString => q(Name="AnyNodeRealMemFree"),
	ManagementScope => q(4),
	Severity => q(1),
        NoToggleExprFlag => q(1),
};
1;
