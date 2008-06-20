#!/usr/bin/perl

$RES::EventResponse{'BroadcastEventsAnyTime'} = {
	Name => q(BroadcastEventsAnyTime),
	Locked => q(0),
	Actions => q({[wallEvent,{127},{0},{86400},/usr/sbin/rsct/bin/wallevent,3,0,0,0,{},0]}),
};
1;
