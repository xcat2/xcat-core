#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::MsgUtils;

use strict;
use Sys::Syslog;
use locale;
use Socket;
use File::Path;

$::NOK = -1;
$::OK  = 0;

#--------------------------------------------------------------------------------

=head1    xCAT::MsgUtils


=head2    Package Description


This program module file, supports the xcat messaging and logging



=cut

#--------------------------------------------------------------------------------

=head2    Package Dependancies

    use strict;
    use Fcntl qw(:flock);
    use File::Basename;
    use File::Find;
    use File::Path;    # Provides mkpath()


=cut

#--------------------------------------------------------------------------------

=head1    Subroutines

=cut

=head3    message

    Display a msg  STDOUT,STDERR or return to callback function.
	If callback routine is provide, the message will be returned to the callback
	routine.

	If callback routime is not provide, the message is displayed to STDOUT or
	STDERR.


    Arguments:
        The arguments of the message() function are:


			If address of the callback is provided,
			then the message will be returned either
			as data to the client's callback routine or to the
			xcat daemon or Client.pm ( bypass) for display/logging.
			See flags below.

			If address of the callback is not provide, then
			the message will be displayed to STDERR or STDOUT or
			added to SYSLOG.  See flags below.

			For compatibility with existing code, the message routine will
			move the data into the appropriate callback structure, if required.
			See example below, if the input to the message routine
			has the "data" structure  filled in for an error message, then
			the message routine will move the $rsp->{data}->[0] to
			$rsp->{error}->[0]. This will allow xcatd/Client.pm will process
			all but "data" messages.

			The current client code should not have to change.

		      my %rsp;
		         $rsp->{data}->[0] = "Job did not run. \n";
	             xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

               Here the message routine will move $rsp->{data}->[0] to
			   $rsp->{error}->[0], to match the "E"message code.
			   Note the message
			   routine will only check for the data to either exist in
			   $rsp->{error}->[0] already, or to exist in $rsp->{data}->[0].

            Here's the meaning of the 1st character, if a callback specified:

                D - DATA this is returned to the client callback routine
                E - error this is displayed/logged by daemon/Client.pm.
                I - informational this is displayed/logged by daemon/Client.pm.
                S - Message will be logged to syslog ( severe error)
					 syslog  facily (local4) and priority (err) will be used.
					 See /etc/syslog.conf file for the destination of the
					 messages.
                     Note S can be combined with other flags for example
					 SE logs message to syslog to also display the
					 message by daemon/ Client.pm.
                V - verbose.  This flag is not valid, the calling routine
				should check for verbose mode before calling the message
				routine and only use the I flag for the message.
				If V flag is detected, it will be changed to an I flag.
                W - warning this is displayed/logged by daemon/Client.pm.


            Here's the meaning of the 1st character, if no callback specified:

                D - DATA  goes to STDOUT
                E - error.  This type of message will be sent to STDERR.
                I - informational  goes to STDOUT
                S - Message will be logged to syslog ( severe error)
                     Note S can be combined with other flags for example
					 SE logs message to syslog and is sent to STDERR.
                V - verbose.  This flag is not valid, the calling routine
				should check for verbose mode before calling the message
				routine and only use the I flag for the message.
				If V flag is detected, it will be changed to an I flag.
                W - warning goes to STDOUT.

    Returns:
        none

    Error:
        none

    Example:

    Use with no callback
        xCAT::MsgUtils->message('E', "Operation $value1 failed\n");
        xCAT::MsgUtils->message('S', "Host $host not responding\n");
        xCAT::MsgUtils->message('SI', "Host $host not responding\n");

    Use with callback
		my %rsp;
		$rsp->{data}->[0] = "Job did not run. \n";
	    xCAT::MsgUtils->message("D", $rsp, $::CALLBACK);

		my %rsp;
		$rsp->{error}->[0] = "No hosts in node list\n";
	    xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);


		my %rsp;
		$rsp->{info}->[0] = "No hosts in node list\n";
	    xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);


		my %rsp;
		$rsp->{warning}->[0] = "No hosts in node list\n";
	    xCAT::MsgUtils->message("W", $rsp, $::CALLBACK);

		my %rsp;
		$rsp->{error}->[0] = "Host not responding\n";
	    xCAT::MsgUtils->message("S", $rsp, $::CALLBACK);


		my %rsp;
		$rsp->{error}->[0] = "Host not responding\n";
	    xCAT::MsgUtils->message("SE", $rsp, $::CALLBACK);

		my %rsp;
		$rsp->{info}->[0] = "Host not responding\n";
	    xCAT::MsgUtils->message("SI", $rsp, $::CALLBACK);


    Comments:


    Returns:
        none



=cut

#--------------------------------------------------------------------------------

sub message
{

    # Process the arguments
    shift;    # get rid of the class name
    my $sev       = shift;
    my $rsp       = shift;
    my $call_back = shift;    # optional
    my $exitcode  = shift;    # optional

    # should be I, D, E, S, W
    #  or S(I, D, E, S, W)

    my $stdouterrf = \*STDOUT;
    my $stdouterrd = '';
    if ($sev =~ /[E]/)
    {
        $stdouterrf = \*STDERR;
        $stdouterrd = '1>&2';
    }

    if ($sev eq 'V')
    {    # verbose should have been handled in calling routine
        $sev = "I";
    }
    if ($sev eq 'SV')
    {    # verbose should have been handled in calling routine
        $sev = "SI";
    }

    # Check that correct structure is filled in. If the data is not in the
    # structure corresponding to the $sev,  then look for it in "data"
    #TODO: this is not really right for a couple reasons:  1) all the fields in the
    #		response structure are arrays, so can handle multiple lines of text.  We
    #		should not just be check the 0th element.  2) a cmd may have both error
    #		text and data text.  3) this message() function should just take in a plain
    #		string and put it in the correct place based on the severity.
    if ($call_back) {    # callback routine provided
    	my $sevkey;
    	if ($sev =~ /I/) { $sevkey = 'info'; }
    	if ($sev =~ /W/) { $sevkey = 'warning'; }
    	if ($sev =~ /E/) {
    		$sevkey = 'error';
            if (!defined($exitcode)) { $exitcode = 1; }   # default to something non-zero
    	}
    	if (defined($sevkey)) {
            if (!defined ($rsp->{$sevkey}) || !scalar(@{$rsp->{$sevkey}})) {   # did not pass the text in in the severity-specific field
            	if (defined ($rsp->{data}) && scalar(@{$rsp->{data}})) {
                	push @{$rsp->{$sevkey}}, shift @{$rsp->{data}};    # assume they passed in the text in the data field instead
            	}
            }
    	}
    	if (!defined ($rsp->{$sevkey}) || !scalar(@{$rsp->{$sevkey}})) { return; }      # if still nothing in the array, there is nothing to print out

        if ($sev ne 'S')      # if sev is anything but only-syslog, print the msg
        {                                   # not just syslog
    		if ($exitcode) { $rsp->{errorcode}->[0] = $exitcode; }
            $call_back->($rsp); # send message to daemon/Client.pm
            shift @{$rsp->{$sevkey}};         # clear out the rsp structure in case they use it again
            if ($exitcode) { shift @{$rsp->{errorcode}}; }
        }
    }
    else                        # no callback provided
    {
        if ($sev ne 'S')        # syslog only
        {
            print $stdouterrf $rsp;    # print the message

        }
    }
    if ($sev =~ /[S]/)
    {

        # need to syslog , the message
        openlog("xCAT", '', 'local4');

        syslog("err", $rsp);
        closelog();
    }
    return 0;
}

1;

