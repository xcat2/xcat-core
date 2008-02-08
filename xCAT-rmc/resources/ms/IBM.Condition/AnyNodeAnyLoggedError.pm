#!/usr/bin/perl

$RES::Condition{'AnyNodeAnyLoggedError'} = {
	Name => q(AnyNodeAnyLoggedError),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(String != ""),
	EventDescription => q(An event will be generated when an error is logged to either the AIX Error Log or the Linux Syslog of a node in the cluster.),
        SelectionString => q(Name="ErrorLogSensor"),
	ManagementScope => q(4),
	Severity => q(0),
};
1;
