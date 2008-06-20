#!/usr/bin/perl

$RES::Condition{'CFMRootModTimeChanged'} = {
	Name => q(CFMRootModTimeChanged),
	ResourceClass => q(IBM.Sensor),
	EventExpression => q(String!=String@P),
	EventDescription => q(An event will be generated whenever a file under /cfmroot is added or modified.),
        SelectionString => q(Name="CFMRootModTime"),
	ManagementScope => q(1),
	Severity => q(0),
};
1;
