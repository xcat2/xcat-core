#!/usr/bin/perl

$RES::Condition{'AllServiceableEvents'} = {
	Name => q(AllServiceableEvents),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(String=?"LSSVCEVENTS_ALL%"),
	EventDescription => q(An event will be generated whenever there is outpout from running sensor related to any serviceable events.),
        SelectionString => q(Name="CSMServiceableEventSensor"),
	ManagementScope => q(4),
	Severity => q(0),
};
1;
