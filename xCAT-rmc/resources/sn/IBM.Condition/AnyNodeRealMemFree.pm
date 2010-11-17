#!/usr/bin/perl

$RES::Condition{'AnyNodeRealMemFree'} = {
	Name => q(AnyNodeRealMemFree),
	ResourceClass => q(IBM.Host),
	EventExpression => q(PctRealMemFree < 5),
	EventDescription => q(An event is generated when the percentage of real memory that are free falls below 5 percent.),
        RearmExpression => q(PctRealMemFree > 10),
        RearmDescription => q(The event will be rearmed to be generated again after the percentage of the real free memory exceeds 10 percent.),
	ManagementScope => q(4),
	Severity => q(1),
};
1;
