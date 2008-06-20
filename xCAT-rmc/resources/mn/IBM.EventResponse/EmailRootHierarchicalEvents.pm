#!/usr/bin/perl

$RES::EventResponse{'EmailRootHierarchicalEvents'} = {
	Name => q(EmailRootHierarchicalEvents),
	Locked => q(0),
	Actions => q({[emailEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/email-hierarchical-event root,3,0,0,0,{},0]}),
};
1;
