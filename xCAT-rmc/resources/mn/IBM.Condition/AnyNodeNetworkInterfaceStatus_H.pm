#!/usr/bin/perl

$RES::Condition{'AnyNodeNetworkInterfaceStatus_H'} = {
	Name => q(AnyNodeNetworkInterfaceStatus_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AnyNodeNetworkInterfaceStatus events from the service nodes. An event will be generated whenever any network interface on the node is not online.),
        RearmDescription => q(A rearm event will be generated when the network interface on the node becomes online again.),
        SelectionString => q(Name="AnyNodeNetworkInterfaceStatus"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
