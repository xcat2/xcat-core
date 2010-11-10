#!/usr/bin/perl

$RES::EventResponse{'EmailRootAnyTime_H'} = {
	Name => q(EmailRootAnyTime_H),
	Locked => q(0),
	Actions => q({[emailEvent,{127},{0},{86400},/opt/xcat/sbin/rmcmon/email-hierarchical-event root,3,0,0,0,{},0]}),
};
1;
