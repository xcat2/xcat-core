#!/usr/bin/perl

$RES::Condition{'VarSpaceUsed'} = {
	Name => q(VarSpaceUsed),
	ResourceClass => q(IBM.FileSystem),
	EventExpression => q(PercentTotUsed>90),
	EventDescription => q(An event will be generated when more than 90 percent of the total space in the /var file system is in use on the local node.),
        RearmExpression => q(PercentTotUsed<75),
        RearmDescription => q(A rearm event will be generated when the percentage of the space used in the /var file system falls below 75 percent on the local node.),
        SelectionString => q(Name="/var"),
	Severity => q(2),
};
1;
