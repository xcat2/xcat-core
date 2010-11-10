#!/usr/bin/perl

$RES::EventResponse{'LogEvents_H'} = {
	Name => q(LogEvents_H),
	Locked => q(0),
	Actions => q({[logEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/log-hierarchical-event /tmp/eventlog,3,0,0,0,{},0]}),
};
1;
