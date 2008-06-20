#!/usr/bin/perl

$RES::Condition{'AllServiceableEvents_H'} = {
	Name => q(AllServiceableEvents_H),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 0x0233) == 0),
	RearmExpression => q(LastEvent.Occurred==1 && LastEvent.ErrNum==0 && (LastEvent.EventFlags & 3) ==1),	
        EventDescription => q(This condition collects all the AllServiceableEvents events from the service nodes. An event will be generated whenever there is outpout from running sensor related to any serviceable events.),
        SelectionString => q(Name="AllServiceableEvents"),
	ManagementScope => q(4),
	Severity => q(0),
        NoToggleExprFlag => q(1),
};
1;
