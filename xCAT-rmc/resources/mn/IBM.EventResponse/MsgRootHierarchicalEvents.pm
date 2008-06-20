#!/usr/bin/perl

$RES::EventResponse{'MsgRootHierarchicalEvents'} = {
	Name => q(MsgRootHierarchicalEvents),
	Locked => q(0),
	Actions => q({[msgEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/msg-hierarchical-event root,3,0,0,0,{},0]}),
};
1;
