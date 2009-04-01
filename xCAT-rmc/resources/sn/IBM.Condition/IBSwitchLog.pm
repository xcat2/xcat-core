#!/usr/bin/perl

$RES::Condition{'IBSwitchLog'} = {
        Name => q(IBSwitchLog),
        ResourceClass => q(IBM.Sensor),
        EventExpression => q(String != ""),
        EventDescription => q(An event will be generated when an error is logged to the Syslog in the local node for IB.),
        SelectionString => q(Name="IBSwitchLogSensor"),
        Severity => q(0),
};


1;
