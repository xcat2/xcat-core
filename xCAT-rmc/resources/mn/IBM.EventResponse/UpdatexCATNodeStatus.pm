#!/usr/bin/perl

$RES::EventResponse{'UpdatexCATNodeStatus'} = {
	Name => q(UpdatexCATNodeStatus),
	Locked => q(0),
	Actions => q({[updatexCAT,{127},{0},{86400},/opt/xcat/sbin/rmcmon/updatexcatnodestatus,3,0,0,0,{},0]}),
};
1;
