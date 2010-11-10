#!/usr/bin/perl

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;

if (exists($ENV{RSCT_VER})) {
    my $rsct_ver=$ENV{RSCT_VER};
    if (xCAT::Utils->CheckVersion($rsct_ver, "2.3.5.0") < 0) {
	exit(0);
    } 
}

$RES::Condition{'NodeReachability_B'} = {
	Name => q(NodeReachability_B),
	ResourceClass => q(IBM.MngNode),
	EventExpression => q(Status!=Status@P),
	EventDescription => q(An event will be generated when a status changes. This is a batch condition.),
	ManagementScope => q(1),
	EventBatchingInterval => q(60),
	EventBatchingMaxEvents => q(200),
	Severity => q(2),
};


1;
