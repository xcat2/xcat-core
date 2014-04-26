#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::DSHCore;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use locale;
use strict;
use Socket;

use xCAT::MsgUtils;
use xCAT::Utils;

#---------------------------------------------------------------------------

=head3
        fork_no_output

        Forks a process for the given command array and returns the process
        ID for the forked process.  Since no I/O is needed for the pipes, no
        STDOUT/STDERR pipes are returned to the caller.

        Arguments:
        	$fork_id - unique identifer to use for tracking the forked process
        	@command - command and parameter array to execute in the forkec process

        Returns:
        	$pid - process identifer for the forked process
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	$pid = xCAT::DSHCore->fork_no_output('hostname1PID', @command_array);

        Comments:

=cut

#---------------------------------------------------------------------------

sub fork_no_output
{
    my ($class, $fork_id, @command) = @_;

    my $pid;

    if ($pid = xCAT::Utils->xfork)
    {

    }
    elsif (defined $pid)
    {
        open(STDOUT, ">/dev/null");
        open(STDERR, ">/dev/null");

        select(STDOUT);
        $| = 1;
        select(STDERR);
        $| = 1;

        if (!(exec {$command[0]} @command))
        {
            return (-4, undef);
        }

    }
    else
    {
        return (-3, undef);
    }

    return ($pid, undef, undef, undef, undef);
}

#---------------------------------------------------------------------------

=head3
        fork_output

        Forks a process for the given command array and returns the process
        ID for the forked process and references to all I/O pipes for STDOUT
        and STDERR.

        Arguments:
        	$fork_id - unique identifer to use for tracking the forked process
        	@command - command and parameter array to execute in the forkec process

        Returns:
        	$pid - process identifer for the forked process
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	$pid = xCAT::DSHCore->fork_no_output('hostname1PID', @command_array);

        Comments:

=cut

#---------------------------------------------------------------------------

sub fork_output
{
    my ($class, $fork_id, @command) = @_;
no strict;
    my $pid;
    my %pipes = ();

    my $rout_fh = "rout_$fork_id";
    my $rerr_fh = "rerr_$fork_id";
    my $wout_fh = "wout_$fork_id";
    my $werr_fh = "werr_$fork_id";

    (pipe($rout_fh, $wout_fh) == -1) && return (-1, undef);
    (pipe($rerr_fh, $werr_fh) == -1) && return (-2, undef);

    if ($pid = fork)
    {
        close($wout_fh);
        close($werr_fh);
    }

    elsif (defined $pid)
    {
        close($rout_fh);
        close($rerr_fh);

        !(open(STDOUT, ">&$wout_fh")) && return (-5, undef);
        !(open(STDERR, ">&$werr_fh")) && return (-6, undef);

        select(STDOUT);
        $| = 1;
        select(STDERR);
        $| = 1;

        if (!(exec {$command[0]} @command))
        {
            return (-4, undef);
        }

    }
    else
    {
        return (-3, undef);
    }

    return ($pid, *$rout_fh, *$rerr_fh, *$wout_fh, *$werr_fh);
use strict;
}


#---------------------------------------------------------------------------

=head3
        fork_output_for_commands

        Forks a process for the given command array and returns the process
        ID for the forked process and references to all I/O pipes for STDOUT
        and STDERR. In the child process, it will invoke the xCAT::DSHCore->fork_no_output()
        for the first command which is a no-output command and waitpid(). And then execute 
        the left commands in the child process.

        Arguments:
        	$fork_id - unique identifer to use for tracking the forked process
        	@command - command and parameter array to execute in the forkec process

        Returns:
        	$pid - process identifer for the forked process
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	$pid = xCAT::DSHCore->fork_output_for_commands('hostname1PID', @command_array);

        Comments:

=cut

#---------------------------------------------------------------------------


sub fork_output_for_commands
{
    my ($class, $fork_id, @commands) = @_;
no strict;
    my $pid;
    my %pipes = ();

    my $rout_fh = "rout_$fork_id";
    my $rerr_fh = "rerr_$fork_id";
    my $wout_fh = "wout_$fork_id";
    my $werr_fh = "werr_$fork_id";

    (pipe($rout_fh, $wout_fh) == -1) && return (-1, undef);
    (pipe($rerr_fh, $werr_fh) == -1) && return (-2, undef);

    if ($pid = fork)
    {
        close($wout_fh);
        close($werr_fh);
    }

    elsif (defined $pid)
    {
        close($rout_fh);
        close($rerr_fh);

        !(open(STDOUT, ">&$wout_fh")) && return (-5, undef);
        !(open(STDERR, ">&$werr_fh")) && return (-6, undef);

        select(STDOUT);
        $| = 1;
        select(STDERR);
        $| = 1;
        if ( @commands > 1 )  {
            my $command0 = shift(@commands);       
            my @exe_command0_process = xCAT::DSHCore->fork_no_output($fork_id, @$command0); 
            waitpid($exe_command0_process[0], undef);
        }
       
        my $t_command = shift(@commands);
        my @command = @$t_command; 
        if (!(exec {$command[0]} @command))
        {
            return (-4, undef);
        }

    }
    else
    {
        return (-3, undef);
    }

    return ($pid, *$rout_fh, *$rerr_fh, *$wout_fh, *$werr_fh);
use strict;
}





#---------------------------------------------------------------------------

=head3
        pipe_handler

        Handles and processes dsh output from a given read pipe handle.  The output
        is immediately written to each output file handle as it is available.

        Arguments:
	        $options - options hash table describing dsh configuration options
	        $target_properties - property information of the target related to the pipe handle
	        $read_fh - reference to the read pipe handle
	        $buffer_size - local buffer size to read data from the handle
	        $label - prefix label to use for dsh output
	        $write_buffer - buffer of data that is yet to be written (must wait until \n is read)
	        @write_fhs - array of output file handles where output will be written

        Returns:
        	1 if the EOF reached on $read_fh
        	undef otherwise
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:

        Comments:

=cut

#---------------------------------------------------------------------------
# NOTE: global environment $::__DSH_LAST_LINE} only can be used in DSHCore::pipe_handler and DSHCore::pipe_handler_buffer
$::__DSH_LAST_LINE  = undef;
sub pipe_handler
{
    my ($class, $options, $target_properties, $read_fh, $buffer_size, $label,
        $write_buffer, @write_fhs)
      = @_;

    my $line;
    my $target_hostname;
    my $eof_reached = undef;
    my $cust_rc_deal =0;

    if ($::USER_POST_CMD)
    {
        # If user provide post-command to display return code,
        # the keyword 'DSH_RC' will be searched,
        # the return code is gotten in another way as shown like below:
        # ...
        # <output>
        # <return_code>
        # DSH_RC
        #
        # The last two lines are needed to be moved out from output
        $cust_rc_deal = 1;
    }

    while (sysread($read_fh, $line, $buffer_size) != 0
           || ($eof_reached = 1))
    {
        last if ($eof_reached && (!defined($::__DSH_LAST_LINE->{$label})));

        if ($line =~ /^\n$/ && scalar(@$write_buffer) == 0)
        {

            # need to preserve blank lines in the output.
            $line = $label . $line;
        }

        my @lines = split "\n", $line;

        if (@$write_buffer)
        {
            my $buffered_line = shift @$write_buffer;
            my $next_line     = shift @lines;
            $next_line = $buffered_line . $next_line;
            unshift @lines, $next_line;
        }

        if ($line !~ /\n$/)
        {
            push @$write_buffer, (pop @lines);
        }

        if (@lines)
        {
            if ($cust_rc_deal)
            {
                # Dump the last line at the beginning of current buffer
                if ($::__DSH_LAST_LINE->{$label})
                {
                    unshift @lines, "$::__DSH_LAST_LINE->{$label}" ;
                }
                # Pop current buffer to $::__DSH_LAST_LINE->{$label}
                if($line) 
                {
                    $::__DSH_LAST_LINE->{$label} = $lines[scalar @lines - 1];
                    pop @lines;
                    # Skip this loop if array @lines is empty.
                    if (scalar @lines == 0)
                    {
                        next;
                    }
                }
            }

            $line = join "\n", @lines;
            $line .= "\n";

            if ($line =~ /:DSH_TARGET_RC=/)
            {
                my $start_offset = index($line, ':DSH_TARGET_RC');
                my $end_offset = index($line, ':', $start_offset + 1);
                my $target_rc_string =
                  substr($line, $start_offset, $end_offset - $start_offset);
                my ($discard, $target_rc) = split '=', $target_rc_string;
                $line =~ s/:DSH_TARGET_RC=$target_rc:\n//g;
                $$target_properties{'target-rc'} = $target_rc;
            }
            if ( $::__DSH_LAST_LINE->{$label} =~ /DSH_RC/ && $cust_rc_deal) {
                my $target_rc = undef;
                # Get the number in the last line
                $line =~ /[\D]*([0-9]+)\s*$/ ;
                $target_rc = $1;
                $$target_properties{'target-rc'} = $target_rc;
                # Remove the last line
                $line =~ s/$target_rc\s*\n$//g;
                #$line = $line . "## ret=$target_rc";
                # Clean up $::__DSH_LAST_LINE->{$label}
                undef $::__DSH_LAST_LINE->{$label} ;
                # when '-z' is specified, display return code
                $::DSH_EXIT_STATUS &&
                    ($line .="Remote_command_rc = $target_rc");
            }

            if ($line ne '')
            {
                if ($line !~ /^$label\n$/)
                {
                    $line = $label . $line;
                }
                $line =~ s/$/\n/ if $line !~ /\n$/;
            }

            $line =~ s/\n/\n$label/g;
            ($line =~ /\n$label$/) && ($line =~ s/\n$label$/\n/);
            chomp $line;

            my @output_files    = ();
            my @output_file_nos = ();

            foreach my $write_fh (@write_fhs)
            {
                my $file_no = fileno($write_fh);
                if (grep /$file_no/, @output_file_nos)
                {
                    $line =~ s/$label//g;
                }

                my $rsp={};
                $rsp->{data}->[0] = $line;
                xCAT::MsgUtils->message("D", $rsp, $::CALLBACK);
                #print $write_fh $line;
            }

            if (@output_files)
            {
                foreach my $output_file (@output_files)
                {
                    pop @write_fhs;
                    close $output_file
                      || print STDOUT
                      "dsh>  Error_file_closed $$target_properties{hostname} $output_file\n";
                    my $rsp={};
                    $rsp->{error}->[0] =
                      "Error_file_closed $$target_properties{hostname $output_file}.\n";
                    xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                    ($output_file == $$target_properties{'output-fh'})
                      && delete $$target_properties{'output-fh'};
                    ($output_file == $$target_properties{'output-fh'})
                      && delete $$target_properties{'error-fh'};
                }
            }

            my $rin = '';
            vec($rin, fileno($read_fh), 1) = 1;
            my $fh_count = select($rin, undef, undef, 0);
            last if ($fh_count == 0);
        }
    }

    return $eof_reached;
}

#---------------------------------------------------------------------------

=head3
        pipe_handler_buffer

        Handles and processes dsh output from a given read pipe handle.  The output
        is stored in a buffer supplied by the caller.

        Arguments:
	        $target_properties - property information of the target related to the pipe handle
	        $read_fh - reference to the read pipe handle
	        $buffer_size - local buffer size to read data from the handle
	        $label - prefix label to use for dsh output
	        $write_buffer - buffer of data that is yet to be written (must wait until \n is read)
	        $output_buffer - buffer where output will be written

        Returns:
        	1 if the EOF reached on $read_fh
        	undef otherwise
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:

        Comments:

=cut

#---------------------------------------------------------------------------
# NOTE: global environment $::__DSH_LAST_LINE only can be used in DSHCore::pipe_handler and DSHCore::pipe_handler_buffer

sub pipe_handler_buffer
{
    my ($class, $target_properties, $read_fh, $buffer_size, $label,
        $write_buffer, $output_buffer)
      = @_;

    my $line;
    my $eof_reached = undef;

    my $cust_rc_deal =0;
    if ($::USER_POST_CMD)
    {
        # If user provide post-command to display return code,
        # the keyword 'DSH_RC' will be searched,
        # the return code is gotten in another way as shown like below:
        # ...
        # <output>
        # <return_code>
        # DSH_RC
        #
        # The last two lines are needed to be moved out from output
        $cust_rc_deal = 1;
    }

    while (   (sysread($read_fh, $line, $buffer_size) != 0)
           || ($eof_reached = 1))
    {
        last if ($eof_reached && (!defined($::__DSH_LAST_LINE->{$label})));
        if ($line =~ /^\n$/ && scalar(@$write_buffer) == 0)
        {

            # need to preserve blank lines in the output.
            $line = $label . $line;
        }

        my @lines = split "\n", $line;

        if (@$write_buffer)
        {
            my $buffered_line = shift @$write_buffer;
            my $next_line     = shift @lines;
            $next_line = $buffered_line . $next_line;
            unshift @lines, $next_line;
        }

        if ($line !~ /\n$/)
        {
            push @$write_buffer, (pop @lines);
        }

        if (@lines || $::__DSH_LAST_LINE->{$label})
        {
            if ($cust_rc_deal)
            {
                # Dump the last line at the beginning of current buffer
                if ($::__DSH_LAST_LINE->{$label})
                {
                    unshift @lines, "$::__DSH_LAST_LINE->{$label}" ;
                    undef $::__DSH_LAST_LINE->{$label}
                }
                if ($line) {
                    # Pop current buffer to $::__DSH_LAST_LINE->{$label}
                    $::__DSH_LAST_LINE->{$label} = $lines[scalar @lines - 1];
                    pop @lines;
                    # Skip this loop if array @lines is empty.
                    if (scalar @lines == 0)
                    {
                        next;
                    }
                }
            }

            $line = join "\n", @lines;
            $line .= "\n";

            if ($line =~ /:DSH_TARGET_RC=/)
            {
                my $start_offset = index($line, ':DSH_TARGET_RC');
                my $end_offset = index($line, ':', $start_offset + 1);
                my $target_rc_string =
                  substr($line, $start_offset, $end_offset - $start_offset);
                my ($discard, $target_rc) = split '=', $target_rc_string;
                $line =~ s/:DSH_TARGET_RC=$target_rc:\n//g;
                $$target_properties{'target-rc'} = $target_rc;
            }
            if ( $::__DSH_LAST_LINE->{$label} =~ /DSH_RC/ && $cust_rc_deal) {
                my $target_rc = undef;
                # Get the number in the last line
                $line =~ /[\D]*([0-9]+)\s*$/ ;
                $target_rc = $1;
                $$target_properties{'target-rc'} = $target_rc;
                # Remove the last line
                $line =~ s/$target_rc\s*\n$//g;
                #$line = $line . "## ret=$target_rc";
                # Clean up $::__DSH_LAST_LINE->{$label}
                undef $::__DSH_LAST_LINE->{$label} ;
                # when '-z' is specified, display return code
                $::DSH_EXIT_STATUS &&
                    ($line .="Remote_command_rc = $target_rc");
            }

            if ($line ne '')
            {
                if ($line !~ /^$label\n$/)
                {
                    $line = $label . $line;
                }
                $line =~ s/$/\n/ if $line !~ /\n$/;
            }

            $line =~ s/\n/\n$label/g;
            ($line =~ /\n$label$/) && ($line =~ s/\n$label$/\n/);

            push @$output_buffer, $line;

            my $rin = '';
            vec($rin, fileno($read_fh), 1) = 1;
            my $fh_count = select($rin, undef, undef, 0);
            last if ($fh_count == 0);
        }
    }
    return $eof_reached;
}


#---------------------------------------------------------------------------

=head3
        ping_hostnames

        Executes ping on a given list of hostnames and returns a list of those
        hostnames that did not respond

        Arguments:
        	@hostnames - list of hostnames to execute for fping

        Returns:
        	@no_response - list of hostnames that did not respond
        	undef if fping is not installed
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	@bad_hosts = xCAT::DSHCore->ping_hostnames(@host_list);

        Comments:

=cut

#---------------------------------------------------------------------------

sub ping_hostnames
{
    my ($class, @hostnames) = @_;

    my $ping = (($^O eq 'aix') && '/usr/sbin/ping')
      || (($^O eq 'linux') && '/bin/ping')
      || undef;
    !$ping && return undef;

    my @no_response = ();
    foreach my $hostname (@hostnames)
    {
        (system("$ping -c 1 -w 1 $hostname > /dev/null 2>&1") != 0)
          && (push @no_response, $hostname);
    }

    return @no_response;
}


#---------------------------------------------------------------------------

=head3
        pping_hostnames

        Executes pping on a given list of hostnames and returns a list of those
        hostnames that did not respond

        Arguments:
                @hostnames - list of hostnames to execute for fping

	        Returns:
                @no_response - list of hostnames that did not respond

        Globals:
                None

        Error:
                None

        Example:
                @bad_hosts = xCAT::DSHCore->pping_hostnames(@host_list);

        Comments:

=cut

#---------------------------------------------------------------------------

sub pping_hostnames
{
    my ($class, @hostnames) = @_;

    my $hostname_list = join ",", @hostnames;
    # read site table, usefping attribute
    # if set then run pping -f to use fping
    # this fixes a broken nmap in Redhat 6.2 with ip alias (3512)
    my $cmd="$::XCATROOT/bin/pping $hostname_list";  # default
    my @usefping=xCAT::TableUtils->get_site_attribute("usefping");
    if ((defined($usefping[0])) && ($usefping[0] eq "1")) {
       $cmd = "$::XCATROOT/bin/pping -f  $hostname_list";
    }
    #my $rsp={};
    #$rsp->{data}->[0] = "running command $cmd";
    #xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);

    my @output =
      xCAT::Utils->runcmd($cmd, -1);
      if ($::RUNCMD_RC !=0) {
        my $rsp={};
        $rsp->{error}->[0] = "Error from pping";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
      }
     $::RUNCMD_RC =0; # reset
    my @no_response = ();
    foreach my $line (@output)
    {
        my ($hostname, $result) = split ':', $line;
        my ($token,    $status) = split ' ', $result;
        chomp($token);
       if ($token ne 'ping') {
          push @no_response, $hostname;
       }
    }

    return @no_response;
}

1;
