#!/usr/bin/perl

$RES::Condition{'CheckFTPonSN_AIX'} = {
        Name => q(CheckFTPonSN_AIX),
        ResourceClass => q(IBM.Sensor),
        EventExpression => q(String ne "ftpd is active"),
        EventDescription => q(For AIX only. An event will be generated when the FTP server is down on the service node. There may be other nodes in this management domain such as HMCs. To exclude them, just change the SelectionString to: "ProgramName=='vsftpd' && NodeNameList >< {'hmc1','hmc2}" where hmc1 and hmc2 are the names for the nodes that you want to exclude.),
        RearmExpression => q(String eq "ftpd is active"),
        RearmDescription => q(A rearm event will be generated when the FTP server is up on the service node.),
        SelectionString => q(Name="CheckFTPSensor_AIX"),
	ManagementScope => q(4),
        Severity => q(1),
};


1;
