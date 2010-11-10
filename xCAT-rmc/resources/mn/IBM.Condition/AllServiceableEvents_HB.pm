#!/usr/bin/perl

$RES::Condition{'AllServiceableEvents_HB'} = {
	Name => q(AllServiceableEvents_HB),
	ResourceClass => q(IBM.Condition),
	EventExpression => q(LastBatchedEventFile.Saved != 0),
	EventDescription => q(An event will be generated when a serviceable event occurs on a HMC. The serviceable events are monitored by a batch condition called AllServiceableEvents_B on the HMC.  This condition monitors the batch condition. This way, if the mn is down, the conditions events will still be saved on the batch files on the HMC. ),
    SelectionString => q(Name="AllServiceableEvents_B"),
	ManagementScope => q(4),
	Severity => q(0),
};
1;
