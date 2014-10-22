#!/usr/bin/perl
# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::RShellAPI;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::MsgUtils;
#use Data::Dumper;

#######################################################
=head3
        remote_shell_command

        This routine constructs an remote shell command using the
        given arguments
        Arguments:
        	$class - Calling module name (discarded)
        	$config - Reference to remote shell command configuration hash table
        	$exec_path - Path to ssh executable
        Returns:
        	A command array for the ssh command with the appropriate
        	arguments as defined in the $config hash table
=cut
##################################################### 
sub remote_shell_command {
	my ( $class, $config, $exec_path ) = @_;
	#print Dumper($config);

	my @command = ();

	push @command, $exec_path;

	if ( $$config{'options'} ) {
		my @options = split ' ', $$config{'options'};
		push @command, @options;
	}
	
        my @tmp;
	if ( $$config{'trace'} ) {
	    push @command, "-v";
	}
	if ( $$config{'remotecmdproto'} &&  ($$config{'remotecmdproto'} =~ /^telnet$/)) {
	    push @command, "-t";
	}
	if ($$config{'user'} && ($$config{'user'}  !~ /^none$/i)) {
	    @tmp=split(' ', "-l $$config{'user'}");
	    push @command, @tmp;
	}
	if ($$config{'password'} && ($$config{'password'} !~ /^none$/i)) {
	    @tmp=split(' ', "-p $$config{'password'}");
	    push @command, @tmp;
	}
	push @command, "$$config{'hostname'}";
	push @command, $$config{'command'};

	return @command;
}

##################################################################
=head3
        run_remote_shell_api

        This routine tried ssh then telnet to logon to a node and
        run a sequence of commands. 
        Arguments:
        	$node - node name
        	$user - user login name
                $passed - user login password
                $cmds - a list of commands seperated by semicolon.
        Returns:
        	[error code, output]
                error code: 0 sucess
                            non-zero: failed. the output contains the error message.
=cut
#########################################################################
sub run_remote_shell_api { 
    require xCAT::SSHInteract;
    my $node=shift;
    my $user=shift;
    my $passwd=shift;
    my $telnet=shift;
    my $verbose=shift;
    my $args = join(" ", @_);
    my $t;
    my $prompt='.*[\>\#\$]\s*$';
    my $more_prompt='(.*key to continue.*|.*--More--\s*|.*--\(more.*\)--.*$)';
    my $output;
    my $errmsg;
    my $ssh_tried=0;
    my $nl_tried=0;

    if (!$telnet) { 
	eval {
	    $output="start SSH session...\n";
	    $ssh_tried=1;
	    $t = new  xCAT::SSHInteract(
		-username=>$user,
		-password=>$passwd,
		-host=>$node,
		-nokeycheck=>1,
		-output_record_separator=>"\r",
		Timeout=>10, 
		Errmode=>'return',
		Prompt=>"/$prompt/",
		);
	};
	$errmsg=$@;
	$errmsg =~ s/ at (.*) line (\d)+//g;
	$output.="$errmsg\n";
    }

    my $rc=1;
    if ($t) {
	#Wait for command prompt
    $t->print("\t");
	my ($prematch, $match) = $t->waitfor(Match => '/login[: ]*$/i',
					     Match => '/username[: ]*$/i',
					     Match => '/password[: ]*$/i',
					     Match => "/$prompt/",
					     Errmode => "return");
	if ($verbose) {
	    print "0. prematch=$prematch\n match=$match\n";
	}

	if ($match !~ /$prompt/) {
	    return [1, $output];
	}

    } else {
        #ssh failed.. fallback to a telnet attempt
	if ($ssh_tried) {
	    $output.="Warning: SSH failed, will try Telnet. Please set switches.protocol=telnet next time if you wish to use telnet directly.\n";
	}
	$output.="start Telnet session...\n";
	require Net::Telnet;
	$t = new Net::Telnet(
	    Timeout=>10, 
	    Errmode=>'return',
	    Prompt=>"/$prompt/",
	    );
	$rc = $t->open($node);
	if ($rc) {
            my $pw_tried=0;
            my $login_done=0;
	    my ($prematch, $match)= $t->waitfor(Match => '/login[: ]*$/i',
						Match => '/username[: ]*$/i',
						Match => '/User Name[: ]*$/i',
						Match => '/password[: ]*$/i',
						Match => "/$prompt/",
						Errmode => "return");
	    if ($verbose) {
		print "1. prematch=$prematch\n match=$match\n";
	    }
            if ($match =~ /$prompt/) {
 		$login_done=1;
	    } elsif (($match =~ /User Name[: ]*$/i) || ($match =~ /username[: ]*$/i) || ($match =~ /login[: ]*$/i )) {
		# user name
		if ($user) {
		    if (! $t->put(String => "$user\n",
				  Errmode => "return")) {
			$output.="login disconnected\n";
			return [1, $output];
		    }
		} else {
		    $output.="Username is required.\n";
		    return [1, $output];
		}
	    } elsif ($match =~ /password[: ]*$/i) {
		if ($passwd) {
		    $pw_tried=1;
		    if (! $t->put(String => "$passwd\n",
				  Errmode => "return")) {
			$output.="Login disconnected\n";
			return [1, $output];
		    }
		} else {
		    $output.="Password is required.\n";
		    return [1, $output];
		}
	    }
	   
            if (!$login_done) {
		($prematch, $match)= $t->waitfor(Match => '/login[: ]*$/i',
					     Match => '/username[: ]*$/i',
					     Match => '/password[: ]*$/i',
					     Match => "/$prompt/",
					     Errmode => "return");
	
		if ($verbose) {
		    print "2. prematch=$prematch\n match=$match\n";
		}
		if ($match =~ /$prompt/) {
		    $login_done=1;
		} elsif (($match =~ /username[: ]*$/i) || ($match =~ /login[: ]*$/i )) {
		    $output.="Incorrect username.\n";
		    return [1, $output];
		} elsif ($match =~ /password[: ]*$/i) {
		    if ($pw_tried) { 
			$output.="Incorrect password.\n";
			return [1, $output];
		    }
		    if ($passwd) {
			if (! $t->put(String => "$passwd\n",
				      Errmode => "return")) {
			    $output.="Login disconnected\n";
			    return [1, $output];
			}
		    } else {
			$output.="Password is required.\n";
			return [1, $output];
		    }
		} else {
                    # for some switches like BNT, user has to type an extra new line 
                    # in order to get the prompt. 
		    if ($verbose) {
			print " add a newline\n";
		    }
		    $nl_tried=1;
		    if (! $t->put(String => "\n",
				  Errmode => "return")) {
			$output.="Login disconnected\n";
			return [1, $output];
		    }
		}
		
		if (!$login_done) {
		    #Wait for command prompt
		    ($prematch, $match) = $t->waitfor(Match => '/login[: ]*$/i',
						      Match => '/username[: ]*$/i',
						      Match => '/password[: ]*$/i',
						      Match => "/$prompt/",
						      Errmode => "return");
		    if ($verbose) {
			print "3. prematch=$prematch\n match=$match\n";
		    }
		    
		    if ($match =~ /$prompt/) {
			$login_done=1;
		    } elsif ($match =~ /login[: ]*$/i or $match =~ /username[: ]*$/i or $match =~ /password[: ]*$/i) {
			$output.="Login failed: bad login name or password\n";
			return [1, $output];
		    } else {
			if (!$nl_tried) {
			    # for some switches like BNT, user has to type an extra new line 
			    # in order to get the prompt. 
			    if ($verbose) {
				print " add a newline\n";
			    }
			    $nl_tried=1;
			    if (! $t->put(String => "\n",
					  Errmode => "return")) {
				$output.="Login disconnected\n";
				return [1, $output];
			    }
			}
			else {
			    if ($t->errmsg) {
				$output.= $t->errmsg . "\n";
				return [1, $output];
				
			    }
			}
		    }
		}

                #check if the extra newline helps or not
		if (!$login_done) {
		    #Wait for command prompt
		    ($prematch, $match) = $t->waitfor(Match => "/$prompt/",
						      Errmode => "return");
		    if ($verbose) {
			print "4. prematch=$prematch\n match=$match\n";
		    }
		    
		    if ($match =~ /$prompt/) {
			$login_done=1;
		    } else {
			if ($t->errmsg) {
			    $output.= $t->errmsg . "\n";
			    return [1, $output];
			}
		    }
		}

	    }
	}
    }

    if (!$rc) {
        $output.=$t->errmsg . "\n";
	return [1, $output];
    }

    $rc = 0;
    my $try_more=0;
    my @cmd_array=split(';', $args);
    
    foreach my $cmd (@cmd_array) {
	if ($verbose) {
	    print "command:$cmd\n";
	}
        
	while (1) {
	    if ($try_more) {                 
                #This is for second and consequent pages.
		#if the user disables the paging, then this code will never run.
                #To disable paging (which is recommended), 
                #they need to add a command before any other commands
                #For Cisco switch: terminal length 0
                #For BNT switch: terminal-length 0
                #For example: 
                #   xdsh <swname> --type EthSwitch "terminal length 0;show vlan"
		if (! $t->put(String => " ",
			      Errmode => "return")) {
		    $output.="Command $cmd failed: " . $t->errmsg() . "\n";
		    return [1, $output];
		}
		if ($verbose) {
		    my $lastline=$t->lastline();
		    print "---lastline=$lastline\n";
		}
		($prematch, $match) = $t->waitfor(Match => "/$more_prompt/i",
						  Match => "/$prompt/",
						  Errmode => "return",
						  Timeout=>10);
	    } else {
                # for the first page which may contian all
		if (! $t->put(String => "$cmd\n",
			      Errmode => "return")) {
		    $output.="Command $cmd failed." . $t->errmsg() . "\n";
		    return [1, $output];
		}
		if ($verbose) {
		    my $lastline=$t->lastline();
		    print "lastline=$lastline\n";
		}
		($prematch, $match) = $t->waitfor(Match => "/$more_prompt/i",
						  Match => "/$prompt/",
						  Match => '/password:\s*$/i',
						  Errmode => "return",
						  Timeout=>10);
	    }

	    if ($verbose) {
		print "-----prematch=$prematch\nmatch=$match\n";
            }

            my $error=$t->errmsg();
	    if ($error) {
	    	$output.="Command $cmd failed: $error\n";
	    	return [1, $output];
	    }
            
            # 
            if ($try_more) {
		#my @data=split("\n", $prematch);
		#shift @data;
		#shift @data;
		#shift @data;
		#$prematch=join("\n", @data);
		#add a newline at the end if not there
		my $lastchar=substr($prematch, -1, 1);
		if ($lastchar ne "\n") {
		    $prematch .= "\n";
		}
	    }
	    $output .= $prematch;

	    if ($match =~ /$more_prompt/i) {
		$try_more=1;
	    } else {
		last;
	    }
	}
    }
    $t->close();
    return [0, $output];
}





1;
