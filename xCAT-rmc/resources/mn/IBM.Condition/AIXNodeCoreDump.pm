#!/usr/bin/perl

$RES::Condition{'AIXNodeCoreDump'} = {
	Name => q(AIXNodeCoreDump),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(String=?"%label = CORE_DUMP%"),
	EventDescription => q(An event will be generated when a core dump is logged in the AIX Error log of a node in the cluster.),
        SelectionString => q(Name="ErrorLogSensor"),
	ManagementScope => q(4),
	Severity => q(0),
};
1;
