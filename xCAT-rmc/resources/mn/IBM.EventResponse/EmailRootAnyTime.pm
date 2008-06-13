#!/usr/bin/perl

$RES::EventResponse{'EmailRootAnyTime'} = {
	Name => q(EmailRootAnyTime),
	Locked => q(0),
	Actions => q({[emailRoot,{127},{0},{86400},/usr/sbin/rsct/bin/notifyevent root,3,0,0,0,{},0]}),
};
1;
