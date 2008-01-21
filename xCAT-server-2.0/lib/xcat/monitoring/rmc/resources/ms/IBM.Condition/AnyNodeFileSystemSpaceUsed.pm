#!/usr/bin/perl

$RES::Condition{'AnyNodeFileSystemSpaceUsed'} = {
	Name => q(AnyNodeFileSystemSpaceUsed),
	ResourceClass => q(IBM.FileSystem),
	EventExpression => q(PercentTotUsed>90),
	EventDescription => q(An event will be generated when more than 90 percent of the total space of the file system is in use.),
        RearmExpression => q(PercentTotUsed<75),
        RearmDescription => q(A rearm event will be generated when the percentage of the space used in the file system falls below 75 percent.),
	ManagementScope => q(4),
	Severity => q(2),
};
1;
