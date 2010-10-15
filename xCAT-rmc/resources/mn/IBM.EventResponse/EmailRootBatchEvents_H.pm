#!/usr/bin/perl

$RES::EventResponse{'EmailRootBatchEvents_H'} = {
	Name => q(EmailRootBatchEvents_H),
	Locked => q(0),
	Actions => q({[emailEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/email-hierarchical-batch-event root -d,3,0,0,0,{},0]}),
};
1;
