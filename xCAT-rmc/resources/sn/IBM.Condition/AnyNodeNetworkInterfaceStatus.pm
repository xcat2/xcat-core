#!/usr/bin/perl

$RES::Condition{'AnyNodeNetworkInterfaceStatus'} = {
	Name => q(AnyNodeNetworkInterfaceStatus),
	ResourceClass => q(IBM.NetworkInterface),
	EventExpression => q(OpState!=1),
	EventDescription => q(An event will be generated whenever any network interface on the node is not online.),
        RearmExpression => q(OpState=1),
        RearmDescription => q(A rearm event will be generated when the network interface on the node becomes online again),
	ManagementScope => q(4),
	Severity => q(2),

};
1;
