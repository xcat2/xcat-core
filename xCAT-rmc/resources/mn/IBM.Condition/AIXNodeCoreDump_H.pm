#!/usr/bin/perl

$RES::Condition{'AIXNodeCoreDump_H'} = {
	Name => q(AIXNodeCoreDump_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AIXNodeCoreDump events from the service nodes. An event will be generated when a core dump is logged in the AIX Error log of a node in the cluster.),
        SelectionString => q(Name="AIXNodeCoreDump"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
