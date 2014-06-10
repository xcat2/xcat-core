#!/usr/bin/env perl
#IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::rrdutil;
use strict;
use IO::Socket;
BEGIN
{
	$::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

#Modules to use:
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;

################################################
#sub start_RRD_server
#Description:
#	FOR AIX:
#	add "rrdsrv $port/tcp #RRD server" to /etc/services 
#	add "rrdsrv stream tcp no wait root /usr/bin/rrdtool rrdtool - $dir"
#	to /etc/inetd.conf
#	restart inetd
#	FOR LINUX:
#	add rrdsrv to xinetd
#	restart xinetd
#Input:
#	$port	Port number of RRD server,
#	$dir	directory to save *.rrd
#return:
#	0 success
#	!0 fail
################################################
sub start_RRD_server
{
	my ($port, $dir) = @_;
	if(xCAT::Utils->isAIX()){
		my $cmd = undef;
		my @old = ();
		my @new = ();
		my $offset = 0;
		my $found = 0;
		@old = xCAT::Utils->runcmd("cat /etc/services", -2);
		push @new, "rrdsrv $port/tcp #RRD server";
		foreach (@old) {
			if ($_ =~ /rrdsrv/){
				if(!$found){
					splice(@old, $offset, 1, @new);
					$found = 1;
				} else {
					splice(@old, $offset, 1);
				}
			} else {
				$offset++;
			}
		}
	
		if(!$found){
			push @old, @new;
		}
	
		open FILE, ">/etc/services.new" or return -1;
		foreach (@old){
			print FILE "$_\n" or return -1;
		}
		close FILE or return -1;
		$cmd = "mv -f /etc/services.new /etc/services";
		xCAT::Utils->runcmd($cmd, -2);

		if(! -d $dir){
			$cmd = "mkdir -p $dir";
			xCAT::Utils->runcmd($cmd, -2);
		} else {
			$cmd = "rm -rf $dir/*";
			xCAT::Utils->runcmd($cmd, -2);
		}
		@old = ();
		@new = ();
		@old = xCAT::Utils->runcmd("cat /etc/inetd.conf", -2);
		$offset = 0;
		$found = 0;
		push @new, "rrdsrv stream tcp nowait root /usr/bin/rrdtool rrdtool - $dir";
		foreach (@old) {
			if ($_ =~ /rrdsrv/){
				if(!$found){
					splice(@old, $offset, 1, @new);
					$found = 1;
				} else {
					splice(@old, $offset, 1);
				}
			} else {
				$offset++;
			}
		}
		if(!$found){
			push @old, @new;
		}
		open FILE, ">/etc/inetd.conf.new" or return -1;
        	foreach (@old){
                	print FILE "$_\n" or return -1;
        	}
		close FILE or return -1;
		xCAT::Utils->runcmd("mv -f /etc/inetd.conf.new /etc/inetd.conf", -2);

		xCAT::Utils->runcmd("stopsrc -s inetd", 0);
		xCAT::Utils->runcmd("startsrc -s inetd", 0);
	} elsif (xCAT::Utils->isLinux()){
		if(-e "/etc/xinetd.d/rrdsrv"){
			xCAT::Utils->runcmd("mv -f /etc/xinetd.d/rrdsrv /etc/xinetd.d/.rrdsrv.xcatbak",0)
		}
		open FILE, ">/etc/xinetd.d/rrdsrv" or return -1;
		print FILE "# This is the configuration for the tcp/stream rrdsrv service.\n\n";
		print FILE "service rrdsrv\n";
		print FILE "{\n";
		print FILE "\tdisable = no\n";
		print FILE "\tport = 13900\n";
		print FILE "\ttype = UNLISTED\n";
		print FILE "\twait = no\n";
		print FILE "\tsocket_type = stream\n";
		print FILE "\tprotocol = tcp\n";
		print FILE "\tuser = root\n";
		print FILE "\tserver = /usr/bin/rrdtool\n";
		print FILE "\tserver_args = - /var/rrd\n";
		print FILE "}\n";
		close FILE;
		#xCAT::Utils->runcmd("service xinetd restart", 0);
		xCAT::Utils->restartservice("xinetd");
	}
	return 0;
}

################################################
#sub stop_RRD_server
#Description:
#	FOR AIX:
#	remove "rrdsrv $port/tcp #RRD server" from /etc/services 
#	remove "rrdsrv stream tcp no wait root /usr/bin/rrdtool rrdtool - $dir"
#	from /etc/inetd.conf
#	restart inetd
#	FOR LINUX:
#	remove from xinetd
#	restart xinetd
#Input:
#	None
#return:
#	0 success
#	!0 fail
################################################
sub stop_RRD_server
{
	if(xCAT::Utils->isAIX()){
		my @old = ();
		my $offset = 0;
		@old = xCAT::Utils->runcmd("cat /etc/services", -2);
		foreach (@old) {
			if ($_ =~ /rrdsrv/){
				splice(@old, $offset, 1);
			} else {
				$offset++;
			}
		}
		open FILE, ">/etc/services.new" or return -1;
        	foreach (@old){
                	print FILE "$_\n" or return -1;
        	}
		close FILE or return -1;
		xCAT::Utils->runcmd("mv -f /etc/services.new /etc/services", -1);

		@old = ();
		@old = xCAT::Utils->runcmd("cat /etc/inetd.conf", -1);
		$offset = 0;
		foreach (@old) {
			if ($_ =~ /rrdsrv/){
				splice(@old, $offset, 1);
			} else {
				$offset++;
			}
		}
		open FILE, ">/etc/inetd.conf.new" or return -1;
       		foreach (@old){
                	print FILE "$_\n" or return -1;
        	}
		close FILE or return -1;
		xCAT::Utils->runcmd("mv -f /etc/inetd.conf.new /etc/inetd.conf", -2);
		xCAT::Utils->runcmd("stopsrc -s inetd", 0);
		xCAT::Utils->runcmd("startsrc -s inetd", 0);
	} elsif (xCAT::Utils->isLinux()){
		if(-e "/etc/xinetd.d/.rrdsrv.xcatbak"){
			xCAT::Utils->runcmd("mv -f /etc/xinetd.d/.rrdsrv.xcatbak /etc/xinetd.d/rrdsrv", 0);
		} else {
			xCAT::Utils->runcmd("rm -f /etc/xinetd.d/rrdsrv", 0);
		}
		#xCAT::Utils->runcmd("service xinetd restart", 0);
		xCAT::Utils->restartservice("xinetd");
	}
	return 0;
}

################################################
#sub runrrdcmd_remote
#Description:
#	Run the given RRD cmd on remote RRD server, 
#	and return the output in an array.
#Input:
#	$cmd	RRD command
#	$host	IP or hostname of RRD server
#	$port	Port number of RRD server,
#return:
#	output of command
################################################
sub runrrdcmd_remote
{
	my($cmd,  $host, $port) = @_;

	my $socket = IO::Socket::INET->new
		(PeerAddr=>$host,
		PeerPort=>$port,
		Proto=>'tcp',
		Type=>SOCK_STREAM);

	if(! $socket){
		print "ERROR: to connect with $host:$port\n";
		return -1;
	}

	print $socket "$cmd\n";
	my $output = [];
	my $line = undef;
	while($line = <$socket>){
		push @$output, $line;
		if($line =~ /(OK|ERROR)/){
			last;
		}
	}
	print $socket "quit";
	close($socket);
	return $output;
}


################################################
#sub RRD_create
#Description:
#	RRD_create will overwrite a RRdb if it already exists,
#Input:
#	$rrd	filename of RRD to create		
#	$sum	if $sum != 0 to create a database file for SUMMARY information
#	$step	the base interval in seconds with which data will be fed into the RRD
#	$start_time the time in seconds when the first value should be added to the RRD
#	$ds_type ds-name:GAUGE | COUNTER | DERIVE | ABSOLUTE
#	$data_source the IP or hostname of remote host
#return:
#	0 sucess
#	!0 fail
################################################
sub RRD_create
{
	my ($rrd, $sum, $step, $start_time, $ds_type, $data_source) = @_;
	my $output = [];
	my $heartbeat = 8 * $step;
	my $cmd = "create $rrd --start $start_time --step $step DS:sum:$ds_type:$heartbeat:U:U";
	if($sum){
		$cmd = $cmd." DS:num:$ds_type:$heartbeat:U:U";
	}
	#TODO: Specified custom RR archives here?
	$cmd = $cmd." RRA:AVERAGE:0.5:1:244 RRA:AVERAGE:0.5:24:244 RRA:AVERAGE:0.5:168:244 RRA:AVERAGE:0.5:672:244 RRA:AVERAGE:0.5:5760:374";
	if(defined($data_source)){
		$output = &runrrdcmd_remote($cmd, $data_source, 13900);
	} else {
		@$output = xCAT::Utils->runcmd("rrdtool $cmd", 0);
	}
	my $line =  pop(@$output);
	if($line =~ /ERROR/){
		return -1;
	} else {
		return 0;
	}
}

################################################
#sub RRD_update
#Description:
#	RRD_update 
#Input:
#	$rrd	filename of RRD to update	
#	$sum	sum of all numeric metrics
#	$num	number of all numeric metrics, should be null for a host metrics
#	$process_time update time
#	$data_source the IP or hostname of remote host
#return:
#	0 sucess
#	!0 fail
################################################
sub RRD_update
{
	my ($rrd, $sum, $num, $process_time, $data_source) = @_;
	my $output = [];
	my $cmd = "update $rrd";
	if($num ne "null"){
		$cmd = $cmd." $process_time:$sum:$num";
	} else {
		$cmd = $cmd." $process_time:$sum";
	}
	if(defined($data_source)){
		$output = &runrrdcmd_remote($cmd, $data_source, 13900);
	} else {
		@$output = xCAT::Utils->runcmd("rrdtool $cmd", 0);
	}
	my $line =  pop(@$output);
	if($line =~ /ERROR/){
		return -1;
	} else {
		return 0;
	}

	return 0;
}

################################################
#sub RRD_fetch
#Description:
#	RRD_fetch 
#Input:
#	$rrd	filename of RRD to update
#	$start_time start of time series
#	$end_time end of time series
#	$data_source	the IP or hostname of remote host
#return:
#	0 sucess
#	!0 fail
################################################
sub RRD_fetch
{
	my ($rrd, $start_time, $end_time, $data_source) = @_;
	my $output = [];
	my $resolution = undef;
	my $cmd = undef;
	$cmd = "fetch $rrd AVERAGE -s $start_time -e $end_time";
	if(defined($data_source)){
		$output = &runrrdcmd_remote($cmd, $data_source, 13900);
	} else {
		@$output = xCAT::Utils->runcmd("rrdtool $cmd", 0);
	}
	return $output;
}

################################################
#sub push_data_to_rrd
#Description:
#	push_data_to_rrd
#Input:
#	$rrd	filename of RRD to update
#	$sum	sum of all numeric metrics
#	$num	number of all numeric metrics, should be null for a host metrics
#	$step	the base interval in seconds with which data will be fed into the RRD
#	$process_time update time
#	$ds_type ds-name:GAUGE | COUNTER | DERIVE | ABSOLUTE
#	$data_source	the IP or hostname of remote host
#return:
#	0 sucess
#	!0 fail
################################################

sub push_data_to_rrd
{
	my $ret = 0;
	my($rrd, $sum, $num, $step, $process_time, $ds_type, $data_source) = @_;
	my $summary = $num eq 'null' ? 0 : 1;
	if(! -f $rrd){
		$ret = RRD_create($rrd, $summary, $step, $process_time-$step, $ds_type, $data_source);
		if($ret != 0){
			return $ret;
		}
	}
	$ret = RRD_update($rrd, $sum, $num, $process_time, $data_source);
	return $ret;
}

1;
