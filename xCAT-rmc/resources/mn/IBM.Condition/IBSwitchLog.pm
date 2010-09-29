#!/usr/bin/perl

$RES::Condition{'IBSwitchLog'} = {
        Name => q(IBSwitchLog),
        ResourceClass => q(IBM.Sensor),
        EventExpression => q(String != ""),
        EventDescription => q(An event will be generated when errors are logged to the Syslog in the local node for IB. The errors are saved in the String attribute in the event. However, if the String attribute in the event starts with XCAT_MONAIXSYSLOG_FILE:filename, then the errors can be found in the file. In this case, it is the responsibility of the response that associates with the condition to remove the temporary file.),
        SelectionString => q(Name="IBSwitchLogSensor"),
        Severity => q(0),
};


1;
