# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::MellanoxIB;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";


use IO::Socket;
use Data::Dumper;
use xCAT::NodeRange;
use xCAT::Utils;
use Sys::Syslog;
use Expect;
use Storable;
use strict;

#-------------------------------------------------------------------------------
=head1  xCAT::MellanoxIB
=head2    Package Description
  It handles Mellanox IB switch related function. It used the CLI interface of 
  Mellanox IB switch

=cut
#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    getConfigure
      It queries the info from the given swithes.      
    Arguments:
        noderange-- an array ref to switches.
        callback -- pointer for writes response back to the client.
        suncommand --- attribute to query about.
    Returns:
        0 --- sucessful
        none 0 --- unsuccessful.
=cut
#--------------------------------------------------------------------------------
sub getConfig {
    my $noderange=shift;
    if ($noderange =~ /xCAT::MellanoxIB/) {
	$noderange=shift;
    }
    my $callback=shift;
    my $subreq=shift;
    my $subcommand=shift;
    
    #handle sshcfg with expect script
    if ($subcommand eq "sshcfg") {
	return querySSHcfg($noderange,$callback,$subreq);
    }

    #get the username and the password 
    my $swstab=xCAT::Table->new('switches',-create=>1);
    my $sws_hash = $swstab->getNodesAttribs($noderange,['sshusername']);
    
    my $passtab = xCAT::Table->new('passwd');
    my $ent;
    ($ent) = $passtab->getAttribs({key => "switch"}, qw(username));

    foreach my $node (@$noderange) {
	my $cmd;
	my $username;
	if ($sws_hash->{$node}->[0]) {
	    $username=$sws_hash->{$node}->[0]->{sshusername};
	}
	if (!$username) {
	    if ($ent) {
	       $username=$ent->{username};
	    }
	}
	if (!$username) {
	    $username="xcat";
	} 
	
	if (($subcommand eq "alert") || ($subcommand eq "snmpcfg") || ($subcommand eq "community") || ($subcommand eq "snmpdest"))  {
	    $cmd='show snmp';
	} elsif ($subcommand eq "logdest")  {
	    $cmd='show logging';
	}
	else {
	    my $rsp = {};
	    $rsp->{error}->[0] = "Unsupported subcommand: $subcommand";
	    $callback->($rsp);
	    return;
	}

	#now goto the switch and get the output
	my  $output = xCAT::Utils->runxcmd({command => ["xdsh"], node =>[$node], arg => ["--devicetype", "IBSwitch::Mellanox", "$cmd"], env=>["DSH_TO_USERID=$username"]}, $subreq, -1, 1);
	if ($output) {
	    my $result=parseOutput($node, $subcommand, $output);
	    my $rsp = {};
	    my $i=-1; 
	    foreach my $o (@$result) {
		$i++;
		$rsp->{data}->[$i] = $o; 
	    }
	    $callback->($rsp);
	}

    } #end foreach
}

sub parseOutput {
    my $node=shift;
    my $subcommand=shift;
    my $input=shift; #an array pointer

    my $output;
    if ($subcommand eq "alert") {
	my $done=0;
	foreach my $tmpstr1 (@$input) {
            my @b=split("\n", $tmpstr1);
	    foreach my $tmpstr (@b) {
		if ($tmpstr =~ /Traps enabled:/) {
		    if ($tmpstr =~ /yes/) {
			$output=["$node: Switch Alerting enabled"];
		    } else {
			$output=["$node: Switch Alerting disabled"];
		    }
		    $done=1;
		    last;
		}
	    }
	   if ($done) { last;} 
	}
	if ($output) { return $output; }
    } elsif ($subcommand eq "snmpcfg") {
	my $done=0;
	foreach my $tmpstr1 (@$input) {
            my @b=split("\n", $tmpstr1);
	    foreach my $tmpstr (@b) {
		if ($tmpstr =~ /SNMP enabled:/) {
		    if ($tmpstr =~ /yes/) {
			$output=["$node: SNMP enabled"];
		    } else {
			$output=["$node: SNMP disabled"];
		    }
		    $done=1;
		    last;
		}
	    }
	   if ($done) { last;} 
	}
	if ($output) { return $output; }
    } elsif ($subcommand eq "snmpdest") {
        my $found=0;
	my $j=0;
	my $done=0;
	foreach my $tmpstr1 (@$input) {
            my @b=split("\n", $tmpstr1);
	    foreach my $tmpstr (@b) {
		if ((!$found) && ($tmpstr =~ /Trap sinks:/)) {
		    $found=1;
		    $output->[0]="$node: SNMP Destination:";
		    next;
		}

		if ($tmpstr =~ /Events for which/) {
		    if (!$found) {
			next;
		    } else {
			$done=1;
			last;
		    }
		}
		if ($found) {
		    $tmpstr =~ s/$node: //g;
		    $output->[++$j]=$tmpstr;
		}     
	    }         
	    if ($done) { last;} 
	}
	if ($output) { return $output; }
    }  elsif ($subcommand eq "community") {
	my $done=0;
	foreach my $tmpstr1 (@$input) {
            my @b=split("\n", $tmpstr1);
	    foreach my $tmpstr (@b) {
		if ($tmpstr =~ /Read-only community:/) {
		    my @a=split(':', $tmpstr);
		    my $c_str;
		    if (@a > 2) {
			$c_str=$a[2];
		    }
		    $output=["$node: SNMP Community: $c_str"];
		    $done=1;
		    last;
		}
	    }
	    if ($done) { last;} 
	}
	if ($output) { return $output; }
    }  elsif ($subcommand eq "logdest") {
	foreach my $tmpstr1 (@$input) {
            my @b=split("\n", $tmpstr1);
	    foreach my $tmpstr (@b) {
		if ($tmpstr =~ /Remote syslog receiver:/) {
		    my @a=split(':', $tmpstr);
		    my $c_str;
		    if (@a > 2) {
			for my $i (2..$#a) {
			    $c_str.= $a[$i]. ':';
			}
			chop($c_str);
		    }
		    if ($output) {
			push(@$output, "  $c_str");
		    } else {
			$output=["$node: Logging destination:\n  $c_str"];
		    }
		}
	    }
	}
	if ($output) { return $output; }
    }

    return $input #an array pointer
}


#--------------------------------------------------------------------------------
=head3    setConfigure
      It configures the the given swithes.      
    Arguments:
        noderange-- an array ref to switches.
        callback -- pointer for writes response back to the client.
        suncommand --- attribute to set.
    Returns:
        0 --- sucessful
        none 0 --- unsuccessful.
=cut
#--------------------------------------------------------------------------------
sub setConfig {
    my $noderange=shift;
    if ($noderange =~ /xCAT::MellanoxIB/) {
	$noderange=shift;
    }
    my $callback=shift;
    my $subreq=shift;
    my $subcommand=shift;
    my $argument=shift;

    #handle sshcfg with expect script
    if ($subcommand eq "sshcfg") {
	if($argument eq "on" or $argument =~ /^en/ or $argument =~ /^enable/) {
	    return setSSHcfg($noderange, $callback, $subreq, 1);
	}
	elsif ($argument eq "off" or $argument =~ /^dis/ or $argument =~ /^disable/) {
	    return setSSHcfg($noderange, $callback, $subreq, 0);
	} else {
	    my $rsp = {};
	    $rsp->{error}->[0] = "Unsupported argument for sshcfg: $argument";
	    $callback->($rsp);
	    return;
	}	
    }

    #get the username and the password 
    my $swstab=xCAT::Table->new('switches',-create=>1);
    my $sws_hash = $swstab->getNodesAttribs($noderange,['sshusername']);
    
    my $passtab = xCAT::Table->new('passwd');
    my $ent;
    ($ent) = $passtab->getAttribs({key => "switch"}, qw(username));

    foreach my $node (@$noderange) {
	my @cfgcmds;
	my $username;
	if ($sws_hash->{$node}->[0]) {
	    $username=$sws_hash->{$node}->[0]->{sshusername};
	}
	if (!$username) {
	    if ($ent) {
	       $username=$ent->{username};
	    }
	}
	if (!$username) {
	    $username="xcat"; #default ssh username
	} 

	if ($subcommand eq "alert") {
	    if($argument eq "on" or $argument =~ /^en/ or $argument =~ /^enable/) {
		$cfgcmds[0]="snmp-server enable traps";
	    }
	    elsif ($argument eq "off" or $argument =~ /^dis/ or $argument =~ /^disable/) {
		$cfgcmds[0]="no snmp-server enable traps";
	    } else {
		my $rsp = {};
		$rsp->{error}->[0] = "Unsupported argument for $subcommand: $argument";
		$callback->($rsp);
		return;
	    }
	}
	elsif ($subcommand eq "snmpcfg") { 
	    if($argument eq "on" or $argument =~ /^en/ or $argument =~ /^enable/) {
		$cfgcmds[0]="snmp-server enable";
	    }
	    elsif ($argument eq "off" or $argument =~ /^dis/ or $argument =~ /^disable/) {
		$cfgcmds[0]="no snmp-server enable";
	    } else {
		my $rsp = {};
		$rsp->{error}->[0] = "Unsupported argument for $subcommand: $argument";
		$callback->($rsp);
		return;
	    }
	}
	elsif ($subcommand eq "community") { 
	    $cfgcmds[0]="snmp-server community $argument";
	} 
	elsif ($subcommand eq "snmpdest") { 
	    my @a=split(' ', $argument);
	    if (@a>1) {
		if ($a[1] eq 'remove') {
		    $cfgcmds[0]="no snmp-server host $a[0]";
		} else {
		    my $rsp = {};
		    $rsp->{error}->[0] = "Unsupported action for $subcommand: $a[1]\nThe valide action is: remove.";
		    $callback->($rsp);
		    return;
		}
	    } else {
		$cfgcmds[0]="snmp-server host $a[0] traps version 2c public";
	    }
	} 
	elsif ($subcommand eq "logdest") {
            #one can run rspconfig <switch> logdest=<ip> level
            # where level can be:
            #    remove           Remove this ip from receiving logging
            #    none             Disable logging
            #    emerg            Emergency: system is unusable
            #    alert            Action must be taken immediately
            #    crit             Critical conditions
            #    err              Error conditions
            #    warning          Warning conditions
            #    notice           Normal but significant condition
            #    info             Informational messages
            #    debug            Debug-level messages
 
	    my @a=split(' ', $argument);
	    if ((@a>1) && ($a[1] eq 'remove')) {
		$cfgcmds[0]="no logging $a[0]";
	    } else { 
		if (@a>1) { 
		    if ($a[1] eq "none" || 
			$a[1] eq "emerg" ||
			$a[1] eq "alert" ||
			$a[1] eq "crit" ||
			$a[1] eq "err" ||
			$a[1] eq "warning" || 
			$a[1] eq "notice" ||
			$a[1] eq "info" ||
			$a[1] eq "debug") {
			$cfgcmds[0]="logging $a[0] trap $a[1]";
		    } else {
			my $rsp = {};
			$rsp->{error}->[0] = "Unsupported loging level for $subcommand: $a[1].\nThe valid levels are: emerg, alert, crit, err, warning, notice, info, debug, none, remove";
			$callback->($rsp);
			return;
		    }
		} else {
		    $cfgcmds[0]="logging $a[0]";
		}
	    }
	} 
	else {
	    my $rsp = {};
	    $rsp->{error}->[0] = "Unsupported subcommand: $subcommand";
	    $callback->($rsp);
	    return;
	}

	#now do the real bussiness
	my $cmd="enable;configure terminal";
	    foreach (@cfgcmds) {
		$cmd .= ";$_";
	}
	my  $output = xCAT::Utils->runxcmd({command => ["xdsh"], node =>[$node], arg => ["--devicetype", "IBSwitch::Mellanox", "$cmd"], env=>["DSH_TO_USERID=$username"]}, $subreq, -1, 1);
	
        #only print out the error
	if ($::RUNCMD_RC != 0) {
	    if ($output) {
		my $rsp = {};
		my $i=-1; 
		foreach my $o (@$output) {
		    $i++;
		    $rsp->{data}->[$i] = $o; 
		}
		$callback->($rsp);
	    }
	}

	#now qerry
	return getConfig($noderange, $callback, $subreq, $subcommand); 
    }  
}



#--------------------------------------------------------------------------------
=head3    querySSHcfg
      It checks if the current host can ssh to the given switches without password.      
    Arguments:
        noderange-- an array ref to switches.
        callback -- pointer for writes response back to the client.
    Returns:
        0 --- sucessful
        none 0 --- unsuccessful.
=cut
#--------------------------------------------------------------------------------
sub querySSHcfg {    

    my $noderange=shift;
    if ($noderange =~ /xCAT::MellanoxIB/) {
	$noderange=shift;
    }
    my $callback=shift;
    my $subreq=shift;
    
    #get the username and the password 
    my $swstab=xCAT::Table->new('switches',-create=>1);
    my $sws_hash = $swstab->getNodesAttribs($noderange,['sshusername']);
    
    my $passtab = xCAT::Table->new('passwd');
    my $ent;
    ($ent) = $passtab->getAttribs({key => "switch"}, qw(username));

    #get the ssh public key from this host
    my $fname = ((xCAT::Utils::isAIX()) ? "/.ssh/":"/root/.ssh/")."id_rsa.pub";
    unless ( open(FH,"<$fname") ) {
	$callback->({error=>["Error opening file $fname."],errorcode=>[1]});
	return 1;
    }
    my ($sshkey) = <FH>;
    close(FH);
    chomp($sshkey);

    my $cmd="enable;show ssh client";
    foreach my $node (@$noderange) {
	my $username;
	if ($sws_hash->{$node}->[0]) {
	    $username=$sws_hash->{$node}->[0]->{sshusername};
	}
	if (!$username) {
	    if ($ent) {
	       $username=$ent->{username};
	    }
	}
	if (!$username) {
	    $username="xcat";
	} 
	

	#now goto the switch and get the output
	my  $output = xCAT::Utils->runxcmd({command => ["xdsh"], node =>[$node], arg => ["--devicetype", "IBSwitch::Mellanox", "$cmd"], env=>["DSH_TO_USERID=$username"]}, $subreq, -1, 1);
	if ($output) {
	    my $keys=getMatchingKeys($node, $username, $output, $sshkey); 
	    my $rsp = {};
	    if (@$keys > 0) {
		$rsp->{data}->[0] = "$node: SSH enabled"; 
	    } else {
		$rsp->{data}->[0] = "$node: SSH disabled"; 
	    }
	    $callback->($rsp);
	}
    } #end foreach node
}


#--------------------------------------------------------------------------------
=head3   getMatchingKeys
      It checks if the given outout contians the given ssh key for the given user.

    Returns:
        An array pointer to the matching keys.
=cut
#--------------------------------------------------------------------------------
sub getMatchingKeys {
    my $node=shift;
    my $username=shift;
    my $output=shift;
    my $sshkey=shift;

    my @keys=();
    my $user_found=0;
    my $start=0;
    my $end=0;
    foreach my $tmpstr1 (@$output) {
	my @b=split("\n", $tmpstr1);
	foreach my $o (@b) {
	    #print "o=$o\n";
	    $o =~ s/$node: //g;
	    if ($o =~ /SSH authorized keys:/) {
		$start=1;
		next;
	    }
	    if ($start) {
		if ($o =~ /User $username:/) {
		    $user_found=1;
		    next;
		} 
		
		if ($user_found) {
		    if ($o =~ /Key (\d+): (.*)$/) {
			my $key=$1;
			my $key_value=$2;
			#print "key=$key\n";
			#print "key_value=$key_value\n";
			chomp($key_value);
			if ("$sshkey" eq "$key_value") {
			    push(@keys, $key);
			}
			next;
		    } elsif ($o =~ /^(\s*)$/) { 
			next;
		    }
		    else { 
			$end=1; 
		    }
		}
	    }
	}
	if ($end) { last; }
    }

    return \@keys;
}


#--------------------------------------------------------------------------------
=head3    setSSHcfg
      It enables/diables the current host to ssh to the given switches without password.      
    Arguments:
        noderange-- an array ref to switches.
        callback -- pointer for writes response back to the client.
    Returns:
        0 --- sucessful
        none 0 --- unsuccessful.
=cut
#--------------------------------------------------------------------------------
sub setSSHcfg {
    my $noderange=shift;
    if ($noderange =~ /xCAT::MellanoxIB/) {
	$noderange=shift;
    }
    my $callback=shift;
    my $subreq=shift;
    my $enable=shift;

    my $mysw;
    my $enable_cmd="enable\r";
    my $config_cmd="configure terminal\r";
    my $exit_cmd="exit\r";

    my $pwd_prompt   = "Password: ";
    my $sw_prompt = "^.*\] > ";
    my $enable_prompt="^.*\] \#";
    my $config_prompt="^.*\\\(config\\\) \#";


    my $debug  = 0;
    if ($::VERBOSE)
    {
        $debug = 1;
    }

    #get the username and the password 
    my $swstab=xCAT::Table->new('switches',-create=>1);
    my $sws_hash = $swstab->getNodesAttribs($noderange,['sshusername','sshpassword']);
    
    my $passtab = xCAT::Table->new('passwd');
    my $ent;
    ($ent) = $passtab->getAttribs({key => "switch"}, qw(username password));

    #get the ssh public key from this host
    my $fname = ((xCAT::Utils::isAIX()) ? "/.ssh/":"/root/.ssh/")."id_rsa.pub";
    unless ( open(FH,"<$fname") ) {
	$callback->({error=>["Error opening file $fname."],errorcode=>[1]});
	return 1;
    }
    my ($sshkey) = <FH>;
    close(FH);
    #remove the userid@host part
    #my @tmpa=split(' ', $sshkey);
    #if (@tmpa > 2) {
    #	$sshkey=$tmpa[0] . ' ' . $tmpa[1];
    #}

    foreach my $node (@$noderange) {
	my $username;
	my $passwd;
	if ($sws_hash->{$node}->[0]) {
	    #print "got to switches table\n";
	    $username=$sws_hash->{$node}->[0]->{sshusername};
	    $passwd=$sws_hash->{$node}->[0]->{sshpassword};
	}
	if (!$username) {
	    #print "got to passwd table\n";
	    if ($ent) {
	       $username=$ent->{username};
	       $passwd=$ent->{password};
	    }
	}
	
	unless ($username) {
	    $callback->({error=>["Unable to get the username and the password for node $node. Please fill the switches table or the password table."],errorcode=>[1]});
	    next;
	} 


	   
	#print "username=$username, password=$passwd\n";
	
	if($enable > 0) {	
	    $mysw = new Expect;
	    $mysw->exp_internal($debug);
	    #
	    # log_stdout(0) prevent the program's output from being shown.
	    #  turn on if debugging error
	    $mysw->log_stdout($debug);
	    
	    my @cfgcmds=();
	    $cfgcmds[0]="ssh client user $username authorized-key sshv2 \"$sshkey\"\r";
	    my $login_cmd = "ssh -l $username $node\r";
	    my $passwd_cmd="$passwd\r";
	    unless ($mysw->spawn($login_cmd))
	    {
		$mysw->soft_close();
		my $rsp;
		$rsp->{data}->[0]="Unable to run $login_cmd.";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		next;
	    }
	    
	    my @result = $mysw->expect(
		10,
		[
		 $pwd_prompt,
		 sub {
		     $mysw->clear_accum();
		     $mysw->send($passwd_cmd);
		     #print "$node: password sent\n";
		     $mysw->exp_continue();
		 }
		],
		[
		 "-re", $sw_prompt,
		 sub {
		     #print "$node: sending command: $enable_cmd\n";
		     $mysw->clear_accum();
		     $mysw->send($enable_cmd);
		     $mysw->exp_continue();
		 }
		],
		[
		 "-re", $enable_prompt,
		 sub {
		     #print "$node: sending command: $config_cmd\n";
		     $mysw->clear_accum();
		     $mysw->send($config_cmd);
		     $mysw->exp_continue();
		 }
		],
		[
		 "-re", $config_prompt,
		 sub {
		     #print "$node: sending command: $cfgcmds[0]\n";
		     $mysw->clear_accum();
		     $mysw->send($cfgcmds[0]);
		     sleep 1;
		     $mysw->send($exit_cmd);
		 }
		],
		);
	    
	    if (defined($result[1]))
	    {
		my $errmsg = $result[1];
		$mysw->soft_close();
		my $rsp;
		$rsp->{data}->[0]="$node: command error: $result[1]";	
		$callback->($rsp);
		next;
		
	    }
	    $mysw->soft_close();
	} else {
	    #now goto the switch and get the matching keys
	    my  $output = xCAT::Utils->runxcmd({command => ["xdsh"], node =>[$node], arg => ["--devicetype", "IBSwitch::Mellanox", "enable;show ssh client"], env=>["DSH_TO_USERID=$username"]}, $subreq, -1, 1);
	    if ($output) {
		chomp($sshkey);
		my $keys=getMatchingKeys($node, $username, $output, $sshkey);
		if (@$keys > 0) {
		    my $cmd="enable;configure terminal";
		    foreach my $key (@$keys) {
			$cmd .= ";no ssh client user admin authorized-key sshv2 $key";
		    }
		    #now remove the keys
		    $output = xCAT::Utils->runxcmd({command => ["xdsh"], node =>[$node], arg => ["--devicetype", "IBSwitch::Mellanox", $cmd], env=>["DSH_TO_USERID=$username"]}, $subreq, -1, 1);
		}
	    }
	}
	#now query again
	querySSHcfg( [$node], $callback, $subreq);
    }
}


1;
