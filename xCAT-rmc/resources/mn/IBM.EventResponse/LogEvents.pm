#!/usr/bin/perl

$RES::EventResponse{'LogEvents'} = {
	Name => q(LogEvents),
	Locked => q(0),
	Actions => q({[logEvent,{127},{0},{86400},/usr/sbin/rsct/bin/logevent /tmp/eventlog,3,0,0,0,{},0]}),
};
1;
