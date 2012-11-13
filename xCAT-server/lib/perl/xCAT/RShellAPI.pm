#!/usr/bin/perl
# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::RShellAPI;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::MsgUtils;

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

	my @command = ();

	push @command, $exec_path;

	if ( $$config{'options'} ) {
		my @options = split ' ', $$config{'options'};
		push @command, @options;
	}
	
        my @tmp;
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

sub run_remote_shell_api { 
    require xCAT::SSHInteract;
    my $node=shift;
    my $user=shift;
    my $passwd=shift;
    my $args = join(" ", @_);
    my $t;

    if(0) {
	print "start SSH session...\n";
	$t = new  xCAT::SSHInteract(
	    -username=>$user,
	    -password=>$passwd,
	    -host=>$node,
	    -nokeycheck=>1,
	    -output_record_separator=>"\r",
	    Timeout=>5, 
	    Errmode=>'return',
	    Prompt=>'/.*[\>\#]$/',
	    );
    };
    my $errmsg=$@;
    $errmsg =~ s/ at (.*) line (\d)+//g;
    print "$errmsg\n"; 

    my $rc=1;
    if (not $t) {#ssh failed.. fallback to a telnet attempt
	print "start Telnet session...\n";
	require Net::Telnet;
	$t = new Net::Telnet(
	    Timeout=>5, 
	    Errmode=>'return',
	    Prompt=>'/.*[\>\#]$/',
	    );
	$rc = $t->open($node);
	if ($rc) {
            my $pw_tried=0;
	    my ($prematch, $match)= $t->waitfor(Match => '/login[: ]*$/i',
						Match => '/username[: ]*$/i',
						Match => '/password[: ]*$/i',
						Errmode => "return");
	    if (($match =~ /username[: ]*$/i) || ($match =~ /login[: ]*$/i )) {
		# user name
		if ($user) {
		    if (! $t->put(String => "$user\n",
				  Errmode => "return")) {
			print "login disconnected\n";
			return [1, "login disconnected"];
		    }
		} else {
		    print "Username is required.\n";
		    return [1, "Username is required."];
		}
	    } elsif ($match =~ /password[: ]*$/i) {
		if ($passwd) {
		    $pw_tried=1;
		    if (! $t->put(String => "$passwd\n",
				  Errmode => "return")) {
			print "login disconnected\n";
			return [1, "login disconnected"];
		    }
		} else {
		    print "password is required.\n";
		    return [1, "Passwordis required."];
		}
	    }
	    
	    ($prematch, $match)= $t->waitfor(Match => '/login[: ]*$/i',
					     Match => '/username[: ]*$/i',
					     Match => '/password[: ]*$/i',
					     Errmode => "return");
	
	    if (($match =~ /username[: ]*$/i) || ($match =~ /login[: ]*$/i )) {
		print "Incorrect username.\n";
		return [1, "Incorrect username."];
	    } elsif ($match =~ /password[: ]*$/i) {
		if ($pw_tried) { 
		    print "Incorrect password.\n";
		    return [1, "Incorrect password."];
		}
		if ($passwd) {
		    if (! $t->put(String => "$passwd\n",
				  Errmode => "return")) {
			print "login disconnected\n";
			return [1, "login disconnected"];
		    }
		} else {
		    print "password is required.\n";
		    return [1, "Passwordis required."];
		}
	    }


	    #Wait for command prompt
	    ($prematch, $match) = $t->waitfor(Match => '/login[: ]*$/i',
						 Match => '/username[: ]*$/i',
						 Match => '/password[: ]*$/i',
						 Match => '/\>/',
						 Errmode => "return");
		
            #print "prematch=$prematch, match=$match\n";
	    if ($match =~ /login[: ]*$/i or $match =~ /username[: ]*$/i or $match =~ /password[: ]*$/i) {
		print "login failed: bad login name or password\n";
		return [1, "login failed: bad login name or password"];
   	    }
	}
    }
    if (!$rc) {
        print "Error: " . $t->errmsg . "\n";
	return([1, $t->errmsg]);
    }

    $rc = 0;
    my $output;
    my @cmd_array=split(';', $args);
    foreach my $cmd (@cmd_array) {
	#my @data = $t->cmd($cmd);
	my @data= $t->cmd(String =>$cmd);
        $output .= "command:$cmd\n@data\n";
        print "command:$cmd\n@data\n";
    }
    $t->close();
    return [0, $output];
}



1;
