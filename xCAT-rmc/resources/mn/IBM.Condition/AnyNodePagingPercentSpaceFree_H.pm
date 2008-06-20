#!/usr/bin/perl

$RES::Condition{'AnyNodePagingPercentSpaceFree_H'} = {
	Name => q(AnyNodePagingPercentSpaceFree_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AnyNodePagingPercentSpaceFree events from the service nodes. An event will be generated when the total amount of free paging space falls below 10 percent.),
        RearmDescription => q(A rearm event will be generated when the free paging space increases to 15 percent.),
        SelectionString => q(Name="AnyNodePagingPercentSpaceFree"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
