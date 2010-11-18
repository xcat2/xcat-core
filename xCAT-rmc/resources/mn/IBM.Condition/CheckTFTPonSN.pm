#!/usr/bin/perl

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

my $proc="tftpd";
if ($^O =~ /^linux/i) { 
    `rpm -q atftp-xcat`;
    if ($?==0) {
	$proc="atftpd";
    }
}

$RES::Condition{'CheckTFTPonSN'} = {
	Name => q(CheckTFTPonSN),
	ResourceClass => q(IBM.Program),
	EventExpression => q(Processes.CurPidCount == 0),
	EventDescription => "An event will be generated when the TFTP server is down on the service node. There may be other nodes in this management domain such as HMCs. To exclude them, just change the SelectionString to: \"ProgramName=='$proc' && NodeNameList >< {'hmc1','hmc2}\" where hmc1 and hmc2 are the names for the nodes that you want to exclude.",
        RearmExpression => q(Processes.CurPidCount != 0),
        RearmDescription => q(A rearm event will be generated when the TFTP server is up on the service node.),
        SelectionString => "ProgramName=='$proc'",
	ManagementScope => q(4),
	Severity => q(1),
};
1;
