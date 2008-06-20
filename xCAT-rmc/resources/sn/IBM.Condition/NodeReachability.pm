#!/usr/bin/perl

$RES::Condition{'NodeReachability'} = {
	Name => q(NodeReachability),
	ResourceClass => q(IBM.MngNode),
	EventExpression => q(Status@P==1 && Status!=1),
	EventDescription => q(An event will be generated when a node becomes network unreachable from the management server.),
        RearmExpression => q(Status=1),
        RearmDescription => q(A rearm event will be generated when the node is reachable again.),
	ManagementScope => q(1),
	Severity => q(2),
};
1;
