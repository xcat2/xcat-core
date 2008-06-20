#!/usr/bin/perl

$RES::Condition{'NodeReachability_H'} = {
	Name => q(NodeReachability_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the NodeReachability events from the service nodes. An event will be generated when a node becomes network unreachable from the management server.),
        RearmDescription => q(A rearm event will be generated when the node is reachable again.),
        SelectionString => q(Name="NodeReachability"),
	ManagementScope => q(4),
	Severity => q(2),
        NoToggleExprFlag => q(1),
};
1;
