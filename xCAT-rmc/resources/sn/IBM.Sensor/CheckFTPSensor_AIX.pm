#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

my $cmd="$::XCATROOT/sbin/rmcmon/check_ftpd";

$RES::Sensor{'CheckFTPSensor_AIX'} = {
	Name => q(CheckFTPSensor_AIX),
	Command => "$cmd",
	Description => "This sensor monitors the FTP server on AIX.",
	UserName => q(root),
	RefreshInterval => q(60),
        ErrorExitValue => q(1),
        ControlFlags => q(1),
};
1;
