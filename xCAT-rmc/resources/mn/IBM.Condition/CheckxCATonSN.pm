#!/usr/bin/perl

$RES::Condition{'CheckxCATonSN'} = {
        Name => q(CheckxCATonSN),
        ResourceClass => q(IBM.Sensor),
        EventExpression => q(String ne "xcatd is ok"),
        EventDescription => q(An event will be generated when xcatd is not working.),
        RearmExpression => q(String eq "xcatd is ok"),
        RearmDescription => q(An rearm event will be generated when xcatd resumes working state.),
        SelectionString => q(Name="CheckxCATSensor"),
	ManagementScope => q(4),
        Severity => q(1),
};


1;
