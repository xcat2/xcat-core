#!/usr/bin/perl

$RES::EventResponse{'LogEventToTealEvenetLog'} = {
	Name => q(LogEventToTealEvenetLog),
	Locked => q(0),
	Actions => q({[logToTeal,{127},{0},{86400},/opt/xcat/sbin/rmcmon/logeventtoteal,3,0,0,0,{},0]}),
};
1;
