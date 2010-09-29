#!/usr/bin/perl

$RES::Condition{'AnyNodeProcessorsIdleTime'} = {
	Name => q(AnyNodeProcessorsIdleTime),
	ResourceClass => q(IBM.Host),
	EventExpression => q(PctTotalTimeIdle>=70),
	EventDescription => q(An event will be generated when the average time all processors are idle at least 70 percent of the time.),
        RearmExpression => q(PctTotalTimeIdle<10),
        RearmDescription => q(A rearm event will be generated when the idle time decreases below 10 percent.),
	ManagementScope => q(4),
	Severity => q(0),
};
1;
