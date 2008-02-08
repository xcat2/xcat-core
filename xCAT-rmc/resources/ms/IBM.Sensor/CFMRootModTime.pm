#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

$RES::Sensor{'CFMRootModTime'} = {
	Name => q(CFMRootModTime),
	Command => "$::XCATROOT/lib/perl/xCAT_monitoring/rmc/mtime /cfmroot",
	UserName => q(root),
	RefreshInterval => q(60),
};
1;
