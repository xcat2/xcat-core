#!/usr/bin/perl

$RES::Condition{'AnyNodePagingPercentSpaceFree'} = {
	Name => q(AnyNodePagingPercentSpaceFree),
	ResourceClass => q(IBM.Host),
	EventExpression => q(PctTotalPgSpFree<10),
	EventDescription => q(An event will be generated when the total amount of free paging space falls below 10 percent.),
        RearmExpression => q(PctTotalPgSpFree>15),
        RearmDescription => q(A rearm event will be generated when the free paging space increases to 15 percent.),
	ManagementScope => q(4),
	Severity => q(2),
};
1;
