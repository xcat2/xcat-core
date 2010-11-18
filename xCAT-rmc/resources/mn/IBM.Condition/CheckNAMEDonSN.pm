#!/usr/bin/perl

$RES::Condition{'CheckNAMEDonSN'} = {
	Name => q(CheckNAMEDonSN),
	ResourceClass => q(IBM.Program),
	EventExpression => q(Processes.CurPidCount == 0),
	EventDescription => q(An event will be generated when the name server is down on the service node. There may be other nodes in this management domain such as HMCs. To exclude them, just change the SelectionString to: "ProgramName=='named' && NodeNameList >< {'hmc1','hmc2}" where hmc1 and hmc2 are the names for the nodes that you want to exclude.),
        RearmExpression => q(Processes.CurPidCount != 0),
        RearmDescription => q(A rearm event will be generated when the name server is up on the service node.),
        SelectionString => q(ProgramName=='named'),
	ManagementScope => q(4),
	Severity => q(1),
};
1;
