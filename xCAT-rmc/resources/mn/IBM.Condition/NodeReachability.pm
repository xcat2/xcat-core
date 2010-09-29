#!/usr/bin/perl

$RES::Condition{'NodeReachability'} = {
	Name => q(NodeReachability),
	ResourceClass => q(IBM.MngNode),
	EventExpression => q(Status!=Status@P),
	EventDescription => q(An event will be generated when a status changes),
	ManagementScope => q(1),
	Severity => q(2),
};
1;
