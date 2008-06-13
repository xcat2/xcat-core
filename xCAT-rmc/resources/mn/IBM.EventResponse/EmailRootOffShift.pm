#!/usr/bin/perl

$RES::EventResponse{'EmailRootOffShift'} = {
	Name => q(EmailRootOffShift),
	Locked => q(0),
	Actions => q({[emilRoot,{62,62,65},{61200,0,0},{86400,28800,86400},/usr/sbin/rsct/bin/notifyevent root,3,0,-1,0,{},0]}),
};
1;
