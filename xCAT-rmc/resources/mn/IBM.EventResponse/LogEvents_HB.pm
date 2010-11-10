#!/usr/bin/perl

$RES::EventResponse{'LogEvents_HB'} = {
	Name => q(LogEvents_HB),
	Locked => q(0),
	Actions => q({[logEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/log-hierarchical-batch-event /tmp/eventlog -d,3,0,0,0,{},0]}),
};
1;
