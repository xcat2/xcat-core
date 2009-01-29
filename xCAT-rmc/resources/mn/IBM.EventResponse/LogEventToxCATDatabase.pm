#!/usr/bin/perl

$RES::EventResponse{'LogEventToxCATDatabase'} = {
	Name => q(LogEventToxCATDatabase),
	Locked => q(0),
	Actions => q({[updatexCAT,{127},{0},{86400},/opt/xcat/sbin/rmcmon/logeventtoxcat,3,0,0,0,{},0]}),
};
1;
