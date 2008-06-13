#!/usr/bin/perl

$RES::EventResponse{'MsgEventsToRootAnyTime'} = {
	Name => q(MsgEventsToRootAnyTime),
	Locked => q(0),
	Actions => q({[msgEvent,{127},{0},{86400},/usr/sbin/rsct/bin/msgevent root,3,0,0,0,{},0]}),
};
1;
