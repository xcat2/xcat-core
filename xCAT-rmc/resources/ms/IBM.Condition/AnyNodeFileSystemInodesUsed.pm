#!/usr/bin/perl

$RES::Condition{'AnyNodeFileSystemInodesUsed'} = {
	Name => q(AnyNodeFileSystemInodesUsed),
	ResourceClass => q(IBM.FileSystem),
	EventExpression => q(PercentINodeUsed>90),
	EventDescription => q(An event will be generated when more than 90 percent of the total inodes in the file system is in use.),
        RearmExpression => q(PercentINodeUsed<75),
        RearmDescription => q(A rearm event will be generated when the percentage of the inodes used in the file system falls below 75 percent.),
	ManagementScope => q(4),
	Severity => q(2),
};
1;
