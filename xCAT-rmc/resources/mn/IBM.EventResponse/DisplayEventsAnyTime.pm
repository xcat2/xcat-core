#!/usr/bin/perl

$RES::EventResponse{'DisplayEventsAnyTime'} = {
	Name => q(DisplayEventsAnyTime),
	Locked => q(0),
	Actions => q({[displayEvent,{127},{0},{86400},/usr/sbin/rsct/bin/displayevent admindesktop:0,3,0,0,0,{},0]}),
};
1;
