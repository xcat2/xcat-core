#!/usr/bin/perl
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

my $cmd;
if ($^O =~ /^linux/i) { $cmd="$::XCATROOT/sbin/rmcmon/monerrorlog";}
else {$cmd="$::XCATROOT/sbin/rmcmon/monaixsyslog";}

$RES::Sensor{'IBSwitchLogSensor'} = {
	Name => q(IBSwitchLogSensor),
	Command => "$cmd -p local6.notice -f /var/log/xcat/syslog.fabric.notices",
	Description => "This sensor monitors the errors logged by IB Switch management software. The String attribute will get updated with the IB related errors happend within the last 60 seconds.  If the length of the error messages is too long, the errors will be saved into a temporary file under /var/opt/xcat_aix_syslog. And the String attrubute will be updated with the file name instead. The format is XCAT_MONAIXSYSLOG_FILE:filename.",
	UserName => q(root),
	RefreshInterval => q(60),
        ErrorExitValue => q(1),
        ControlFlags => q(0),
};
1;
