#!/usr/bin/perl

$RES::Condition{'AnyNodeFileSystemInodesUsed_H'} = {
	Name => q(AnyNodeFileSystemInodesUsed_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AnyNodeFileSystemInodesUsed events from the service nodes. An event will be generated when more than 90 percent of the total inodes in the file system is in use.),
        RearmDescription => q(A rearm event will be generated when the percentage of the inodes used in the file system falls below 75 percent."),
        SelectionString => q(Name="AnyNodeFileSystemInodesUsed"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
