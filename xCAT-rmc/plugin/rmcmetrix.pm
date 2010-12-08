#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::rmcmetrix;
#Modules to use:
#use threads;
#use threads::shared;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::Utils;
use xCAT_monitoring::rrdutil;

1;
#metrix{Attr}{NodeNameList}{Name} = value
#NodeNameList could be NodeNameList | summary | number
#Attr	could be Attribute | summary | number
%metrix={};

######################################
#sub print_metrix
#Description:
#	to print all content of %metrix, for debug
#Input:
#	None
#Return:
#	None
#####################################
sub print_metrix
{
	my $key1;
	my $key2;
	my $key3;
	my $value;
	while(($key1, $key2) = each %metrix){
		if(! exists($metrix{$key1}{$key2})){
			print "$key1=>$key2\n";
			next;
		}
		while(($key2, $key3) = each %{$metrix{$key1}}){
			if(! exists($metrix{$key1}{$key2}{$key3})){
				print "$key1.$key2=>$key3\n";
			}
			while(($key3, $value) = each %{$metrix{$key1}{$key2}}){
				print "$key1.$key2.$key3=>$value\n";
			}
		}
	}

}

#######################################
#sub update_metrix2rrd
#Description:
#	update RRDtool database based on content of %metrix,
#	all statistic be stored as GAUGE in RRDtool,
#Input:
#	$step the base interval in seconds with which data will be fed into the RRD
#Return:
#	None
#####################################

sub update_metrix2rrd
{
	my $step = shift @_;
	my $ret = 0;
	my $attr;
	my $nnlist;
	my $name;
	my $value;
	my $rmcrrdroot = "/var/rrd";
	my $rrddir = undef;
	my $rrd = undef;
	my $process_time = xCAT::Utils->runcmd("date +%s", 0);
	$process_time = (int $process_time/$step)*$step;
	my $temp = undef;

	while(($attr, $nnlist) = each %metrix){
		while(($nnlist, $name) = each %{$metrix{$attr}}){
			if($nnlist eq 'number'){
				next;
			}
			$rrddir = "$rmcrrdroot/$nnlist";
			if(! -d $rrddir){
				xCAT::Utils->runcmd("mkdir -p $rrddir");
			}
			if($nnlist eq 'summary'){
				$rrd = "$rrddir/"."$attr.rrd";
				$temp = $metrix{$attr}{summary}/$metrix{$attr}{number};
				$ret = xCAT_monitoring::rrdutil::push_data_to_rrd($rrd, $temp, $metrix{$attr}{number}, $step, $process_time, 'GAUGE');
				if($ret != 0){
					return ($ret, "Can't push data to $rrd\n");
				}
			} else {
				while(($name, $value) = each %{$metrix{$attr}{$nnlist}}){
					if($name eq 'number'){
						next;
					}
					if($name eq 'summary'){
						$rrd = "$rrddir/$attr.rrd";
						$temp = $metrix{$attr}{$nnlist}{summary}/$metrix{$attr}{$nnlist}{number};
						$ret = xCAT_monitoring::rrdutil::push_data_to_rrd($rrd, $temp, $metrix{$attr}{$nnlist}{number}, $step, $process_time, 'GAUGE');
						if($ret != 0){
							return($ret, "Can't push data to $rrd\n");
						}
					} else {
						$rrd = "$rrddir/$attr"."_$name.rrd";
						xCAT_monitoring::rrdutil::push_data_to_rrd($rrd, $metrix{$attr}{$nnlist}{$name}, 'null', $step, $process_time, 'GAUGE');
						if($ret != 0){
							return($ret, "Can't push data to $rrd\n");
						}
					}
				}
			}
		}
	}
	return (0, "Success");

}

######################################
#sub parse_lsrsrc_output
#Description:
#	parse the output of lsrsrc and store the information to %metrix
#Input:
#	resource class
#	array of attributes
#	array of output of lsrsrc command
#Return:
#	0 Success
#	!0 Fail
#####################################
sub parse_lsrsrc_output
{
	my ($rsrc, $pattr, $output) = @_;
	my $nnlist = undef;
	my $name = undef;
	my $line = undef;
	my $attr = undef;
	my @value = ();
	my $i = undef; 
	my %count = {};
	
	foreach $line (@$output){
		@value = split /::/, $line;
		$name = $value[0];
		$name =~ s/[^A-Za-z0-9]+/'.'/;
		if($name eq ''){
			$name = 'null';
		}
		$value[1] =~ /{(\w+)}/;
		$nnlist = $1;
		$i = 2;
		foreach $attr (@$pattr){
			if($rsrc eq 'IBM.Processor'){
				$metrix{$attr}{$nnlist}{$name} += $value[$i];
			} else {
				$metrix{$attr}{$nnlist}{$name} = $value[$i];
			}
			$metrix{$attr}{$nnlist}{summary} += $value[$i];
			$metrix{$attr}{$nnlist}{number} += 1;
			$i++;
		}
		if($rsrc eq 'IBM.Processor'){
			$count{$nnlist}{$name} += 1;
		}
	}
	if($rsrc eq 'IBM.Processor'){
		foreach $nnlist (keys %count){
			foreach $name (keys %{$count{$nnlist}}){
				if ($count{$nnlist}{$name} > 1) {
					foreach $attr (@$pattr){
						$metrix{$attr}{$nnlist}{$name} /= $count{$nnlist}{$name};
					}
				}
			}
		}
	}
	
	
	return 0;

}

######################################
#sub getmetrix
#Description:
#	Get %metrix using lsrsrc-api, and store to RRD
#Input:
#	$rsrc	the resource class of RMC, such as "IBM.EthernetDevice"
#	$rname	the resource name of resouce class, if ($rname eq "__ALL__") then all
#		resource name will be monitoring
#	$attrlist the list of attributes of the monitoring resource
#	$minute the interval to collect data in minute
#Return:
#	0 Success
#	!0 Fail
#####################################
sub getmetrix
{
	my ($rsrc, $rname, $attrlist, $minute) = @_;
	my @attrs = ();
	my $attr = undef;
	my $nnlist = undef;
	my @names = ();
	my $name = undef;
	my @output = ();
	my $rrd = undef;
	my $line = undef;
	my $ret = undef;
	my $msg = undef;
	my $cmd = undef;

	@attrs = split /,/, $attrlist;
	
	$attr = join '::', @attrs;
#	if(xCAT::Utils->isMN()){
#		if($rname eq "__ALL__"){
#			$cmd = "CT_MANAGEMENT_SCOPE=1 lsrsrc-api -i -s $rsrc"."::::Name::NodeNameList::$attr";
#			@output = xCAT::Utils->runcmd($cmd, 0);
#			if($::RUNCMD_RC  != 0){
#				$line = join '', @output;
#				return ($::RUNCMD_RC, $line);
#			}
#			&parse_lsrsrc_output($rsrc, \@attrs, \@output);
#		} else {
#			@names = split /,/, $rname;
#			foreach $name (@names){
#				$cmd = "CT_MANAGEMENT_SCOPE=1 lsrsrc-api -i -s $rsrc"."::\'Name==\"$name\"\'::Name::NodeNameList::$attr";
#				@output = xCAT::Utils->runcmd($cmd, 0);
#				if($::RUNCMD_RC != 0){
#					$line = join '', @output;
#					return ($::RUNCMD_RC, $line);
#				}
#				&parse_lsrsrc_output($rsrc, \@attrs, \@output);
#			}
#		}
#	}

	if($rname eq "__ALL__"){
		$cmd = "CT_MANAGEMENT_SCOPE=3 lsrsrc-api -i -s $rsrc"."::::Name::NodeNameList::$attr";
		@output = xCAT::Utils->runcmd($cmd, 0);
		if($::RUNCMD_RC != 0){
			$line = join '', @output;
			return ($::RUNCMD_RC, $line);
		}
		&parse_lsrsrc_output($rsrc, \@attrs, \@output);
	} else {
		@names = split /,/, $rname;
		foreach $name (@names){
			$cmd = "CT_MANAGEMENT_SCOPE=3 lsrsrc-api -i -s $rsrc"."::\'Name==\"$name\"\'::Name::NodeNameList::$attr";
			@output = xCAT::Utils->runcmd($cmd, 0);
			if($::RUNCMD_RC){
				$line = join '', @output;
				return ($::RUNCMD_RC, $line);
			}
			&parse_lsrsrc_output($rsrc, \@attrs, \@output);
		}
	}
	
	foreach $attr (keys %metrix){
		foreach $nnlist (keys %{$metrix{$attr}}){
			if(($nnlist ne 'summary') && ($nnlist ne 'number')){
				$metrix{$attr}{summary} += $metrix{$attr}{$nnlist}{summary};
				$metrix{$attr}{number} += $metrix{$attr}{$nnlist}{number};
			}
			
		}
	}
	
	my $step = $minute * 60;
	($ret, $msg) = &update_metrix2rrd($step);
	
	return ($ret, $msg);
}

######################################
#sub get_metrix_conf
#Description:
#	Get configure for table monsetting, and return an array 
#Input:
#	None;
#Return:
#	an array of configuration (rsrc0, attrlist0, minute0, rsrc1, attrlist1,minute1, ...)
#####################################
sub get_metrix_conf
{
	my @conf = ();
	my @tmp = ();
	my $rsrc = undef;
	my $namelist = undef;
	my $attrlist = undef;
	my $minute = undef;
	my $key = undef;
	my $value = undef;
	my $conftable = xCAT::Table->new('monsetting');
	if($conftable){
		@tmp = $conftable->getAttribs({'name'=>'rmcmon'}, ('key','value'));
		foreach (@tmp) {
			$key = $_->{key};
			$value = $_->{value};
			if($key =~ /^rmetrics_(\S+)/){
				push @conf, $1;
				if($value =~ /\]/){
					($namelist, $value) = split /\]/, $value;
					$namelist =~ s/\[//;
				} else {
					$namelist = "__ALL__";
				}
				push @conf, $namelist;

				($attrlist, $minute) = split /:/, $value;
				push @conf, $attrlist;
				push @conf, $minute;
			}
		}
		$conftable->close;
	}
	return @conf;
}

######################################
#sub get_sum_metrix
#Description:
#	Consolidates data collected by SNs and MN  and stores to local RRD
#Input:
#	$attrlist the list of attributes of the monitoring resource
#Return:
#	0 Success
#	!0 Fail
#####################################
sub get_sum_metrix
{
	my $code = undef;
	my $msg = undef;
	my ($attrlist, $minute) = @_;
	my $result = undef;
	my @rmc_nodes = ();
	my @svc_nodes = ();
	my $node = undef;
	my $temp = undef;
#	my @threads = ();
#	my $current_thread = 0;
	my $i = undef;
#	my %summary:shared; #summary{$attr}{$node}
	my %summary = {};
	my @attributes = ();
	my $attribute = undef;
	my $nodename = undef;
	my $time = undef;
#	my $end:shared;
    my %summetrix = {};
	my $end = undef;
       	$end = xCAT::Utils->runcmd("date +%s", 0);
#	my $step:shared;
	my $step = undef;
	$step = $minute * 60;
	#to share %summary
	@attributes = split /,/, $attrlist;
#	foreach $attribute (@attributes){
#		$summary{$attribute} = &share({});
#	}
	$result = `lsrsrc-api -s IBM.MngNode::::Name 2>&1`;
	chomp($result);
	@rmc_nodes=split(/\n/, $result);
	foreach $node (@rmc_nodes){
		if(xCAT::Utils->isSN($node)){
			push @svc_nodes, $node;
		}
	}
	$node = `hostname`;
	chomp($node);
	push @svc_nodes, $node;
	foreach $node (@svc_nodes){
#		$threads[$current_thread] = threads->new(\&getsum, $attrlist, $node);
#		$current_thread++;
		&getsum($attrlist, $node);
	}

	sub getsum{
		my ($attrs, $n) = @_;
		my @attr = split /,/,$attrs;
		my $a = undef;
		my $start = undef;
		my $result = undef;
		my $timestamp = undef;
		my $sum = undef;
		my $num = undef;
		my $localhost = `hostname`;
		chomp($localhost);
		foreach $a (@attr){
			if(-f "/var/rrd/cluster/$a.rrd"){
				$start = `rrdtool last /var/rrd/cluster/$a.rrd`;
				chomp($start);
			} else {
				$start = ((int $end/$step) - 244)*$step;
			}
			if($n eq $localhost){
				$result = xCAT_monitoring::rrdutil::RRD_fetch("/var/rrd/summary/$a.rrd",$start, $end);
			} else {
				$result = xCAT_monitoring::rrdutil::RRD_fetch("summary/$a.rrd",$start, $end, $n);
			}
			my $line = pop(@$result);
			if($line =~ /ERROR/){
				return (-1, $line);
			} else {
				push @$result, $line;
			}
#			$summary{$a}{$n} = &share({});
			foreach $line (@$result){
				if($line =~ /NaNQ/){
					next;
				} elsif ($line =~ /^(\d+): (\S+) (\S+)/){
					$timestamp = $1;
					$sum = $2;
					$num = $3;
#					$summary{$a}{$n}{$timestamp} = &share({});
#					$summary{$a}{$n}{$timestamp}{sum} = &share({});
#					$summary{$a}{$n}{$timestamp}{num} = &share({});
					$summetrix{$a}{$timestamp}{sum} += $sum * $num;
					$summetrix{$a}{$timestamp}{num} += $num;
				}
			}
		}
		return (0, 'Success');
	}
	
#	for($i=0; $i<$current_thread; $i++){
#		($code, $msg) = $threads[$i]->join();
#		if($code != 0){
#			warn("$msg\n");
#		}
#	}

#	my %summetrix = {};
#	foreach $attribute (keys %summary){
#		foreach $nodename (keys %{$summary{$attribute}}){
#			foreach $time (keys %{$summary{$attribute}{$nodename}}){
#				print "$attribute.$nodename.$time $summary{$attribute}{$nodename}{$time}{sum} $summary{$attribute}{$nodename}{$time}{num}\n";
#				$temp = $summary{$attribute}{$nodename}{$time}{sum} * $summary{$attribute}{$nodename}{$time}{num};
#				$summetrix{$attribute}{$time}{sum} += $temp;
#				$summetrix{$attribute}{$time}{num} += $summary{$attribute}{$nodename}{$time}{num};
#			}
#		}
		
#	}

	my $rrdcluster = "/var/rrd/cluster";
	if(! -d $rrdcluster){
		system("mkdir -p $rrdcluster");
	}
	foreach $attribute (keys %summetrix){
		my @times = keys(%{$summetrix{$attribute}});
		my @sorttimes = sort @times;
		foreach $time (@sorttimes){
			$temp = $summetrix{$attribute}{$time}{sum}/$summetrix{$attribute}{$time}{num};
			$code = xCAT_monitoring::rrdutil::push_data_to_rrd("$rrdcluster/$attribute.rrd", $temp, $summetrix{$attribute}{$time}{num}, $step, $time, 'GAUGE');
			if($code != 0){
				return($code, "Can't push data to $rrdcluster/$attribute.rrd");
			}
		}
	}

	return (0, 'Success');
}

