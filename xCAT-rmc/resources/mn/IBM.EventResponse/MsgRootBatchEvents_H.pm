#!/usr/bin/perl

$RES::EventResponse{'MsgRootBatchEvents_H'} = {
	Name => q(MsgRootBatchEvents_H),
	Locked => q(0),
	Actions => q({[msgEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/msg-hierarchical-batch-event root -d,3,0,0,0,{},0]}),
};
1;
