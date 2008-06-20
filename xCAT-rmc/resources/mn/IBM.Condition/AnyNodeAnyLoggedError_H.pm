#!/usr/bin/perl

$RES::Condition{'AnyNodeAnyLoggedError_H'} = {
	Name => q(AnyNodeAnyLoggedError_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AnyNodeAnyLoggedError events from the service nodes. An event will be generated when an error is logged to either the AIX Error Log or the Linux Syslog of a node in the cluster.),
        SelectionString => q(Name="AnyNodeAnyLoggedError"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
