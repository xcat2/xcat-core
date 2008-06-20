#!/usr/bin/perl

$RES::EventResponse{'MsgHierarchicalEvents'} = {
	Name => q(MsgHierarchicalEvents),
	Locked => q(0),
	Actions => q({[msgEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/msg-hierarchical-event,3,0,0,0,{},0]}),
};
1;
