#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::MsgUtils;

use strict;

use locale;
use Socket;
use File::Path;

my $msgs;
my $distro;

$::XCATLOG = "/var/log/xcat";
$::NOK     = -1;
$::OK      = 0;
umask(0022);    #  This sets umask for all files so that group and world only

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

=head1    Subroutines by Functional Group

=cut

=head3    message

    Display a msg  stdout, stderr, or a log file. 
	If callback routine is provide, the message will be returned to the callback
	routine and logged, if logging is requested.
	This function is primarily meant for commands and other code that is sending
    output directly to the user.  Even the log is really a capture of this
    interactive output. 

    Arguments:
        The arguments of the message() function are:

			if $::VERBOSE is set, the message will be displayed.

            If $::LOG_FILE_HANDLE is set, the message goes to both 
			the screen and that log file.  (Verbose msgs will be sent to 
			the log file even if $::VERBOSE is not set.)   
			A timestamp will automatically be put in front on any message
			that is logged unless the T option is specified.
            
			if address of the call_back is provided,
			then the message will be returned
			   as data to the call_back routine.

         - The  argument is the message to be displayed/logged.


            Here's the meaning of the 1st character:
                I - informational  goes to stdout
                E - error.  This type of message will be sent to stderr.
                V - verbose.  This message should only be displayed, 
				if $::VERBOSE is set.
                T - Do not log timestamp, 

            If $::LOG_FILE_HANDLE is set, the message goes to both 
			the screen and that log file.  (Verbose msgs will be sent to 
			the log file even if $::VERBOSE is not set.)   
			A timestamp will automatically be put in front on any message
			that is logged.
			Optionally a T can be put before any of the above characters
			"not" put  a timestamp on 
			before the message when it is logged.
			Note: T must be the first character. 


    Returns:
        none

    Error:
        _none

    Example:
        xCAT::MsgUtils->message('E', "Operation $value1 failed\n");
    Use of T flag
		xCAT::MsgUtils->message('TI', "Operation $value1 failed\n");
    Use of callback 
		xCAT::MsgUtils->message('I', $rsp,$call_back);
		   where $rsp is a data response structure for the callback function


    Comments:
    Returns:
        none



=cut

#--------------------------------------------------------------------------------

sub message
{

    # Process the arguments
    shift;    # get rid of the class name
    my $sevcode = shift;
    my $msg     = shift;
    my $call_back     = shift;  # optional 

    # Parse the severity code
    my $i           = 1;
    my $notimestamp = 0;
    my $sev         = substr($sevcode, 0, 1);

    # should be I, E, V, T
    if ($sev eq 'T')    # do not put timestamp
    {
        $notimestamp = 1;    # no timestamp
        $i           = 2;    # logically shift everything by 1 char
        $sev = substr($sevcode, 1, 1);    # now should be either I,E,V
    }

    my $stdouterrf = \*STDOUT;
    my $stdouterrd = '';
    if (my $sev =~ /[E]/)
    {
        $stdouterrf = \*STDERR;
        $stdouterrd = '1>&2';
    }

    if (defined($::LOG_FILE_HANDLE))
    {

        if ($notimestamp == 0)
        {    # print a timestamp
            my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
              localtime(time);
            my $time = $hour . ":" . $min . ":" . $sec . " ";
            print $::LOG_FILE_HANDLE $time;
            print $::LOG_FILE_HANDLE " ";
        }
        print $::LOG_FILE_HANDLE $msg;
    }

    # if V option and $::VERBOSE set or not V option then display
    # Note Verbose messages, will be thrown away if verbose is not
    # turned on and there is no logging.
    if (($sev eq 'V' && $::VERBOSE) || ($sev ne 'V'))
    {
        if ($::DSH_API)
        {
            $::DSH_API_MESSAGE = $::DSH_API_MESSAGE . $msg;
        }
        else
        {
			if ($call_back)  {   # callback routine provided
				$call_back->($msg);
			} else {
              print $stdouterrf $msg;    # print the message
            
            }
        }
    }
    return 0;
}

#--------------------------------------------------------------------------------

=head2    Message Logging Routines

=cut

#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------

=head3    backup_logfile

        Backup the current logfile. Move logfile to logfile.1. Shift all other logfiles
        (logfile.[1-3]) up one number. The original logfile.4 is removed as in a FIFO.   

        Arguments:
                $logFileName
        Returns:
                $::OK
        Error:
                undefined
        Example:
                xCAT::MsgUtils->backup_logfile($logfile);
        Comments:
                Never used outside of ServerUtils.

=cut

#--------------------------------------------------------------------------------

sub backup_logfile
{
    my ($class, $logfile) = @_;

    my ($logfile1) = $logfile . ".1";
    my ($logfile2) = $logfile . ".2";
    my ($logfile3) = $logfile . ".3";
    my ($logfile4) = $logfile . ".4";

    if (-f $logfile)
    {
        rename($logfile3, $logfile4) if (-f $logfile3);
        rename($logfile2, $logfile3) if (-f $logfile2);
        rename($logfile1, $logfile2) if (-f $logfile1);
        rename($logfile,  $logfile1);
    }
    return $::OK;
}

#--------------------------------------------------------------------------------

=head3 start_logging

        Start logging messages to a logfile. Return the log file handle so it
        can be used to close the file when done logging.

        Arguments:
                $logFile
        Returns:
                $::LOG_FILE_HANDLE
        Globals:
                $::LOG_FILE_HANDLE
                $::XCATLOG
        Error:
                $::NOK
        Example:
                xCAT::MsgUtils->start_logging($cfmupdatenode.log);
        Comments:
                Common method for logging script runtime output.

=cut

#--------------------------------------------------------------------------------

sub start_logging
{
    my ($class, $logfile) = @_;
    my ($cmd, $rc);
    xCAT::MsgUtils->backup_logfile($logfile);

    # create the log directory if it's not already there
    if (!-d $::XCATLOG)
    {
	    mkdir($::XCATLOG, 0755);
    }

    # open the log file
    unless (open(LOGFILE, ">>$logfile"))
    {

        # Cannot open file
        xCAT::MsgUtils->message("E", "Cannot open file: $logfile.\n");
        return $::NOK;
    }

    $::LOG_FILE_HANDLE = \*LOGFILE;

    # Print the date to the top of the logfile
    my $sdate = localtime(time);
    chomp $sdate;
    my $program = xCAT::Utils->programName();
    xCAT::MsgUtils->message(
        "TV",
        "#--------------------------------------------------------------------------#\n"
        );
    xCAT::MsgUtils->message("TV", "$program: Logging Started:$sdate\n");
    xCAT::MsgUtils->message("TV", "Input: $::command_line\n");
    xCAT::MsgUtils->message(
        "TV",
        "#--------------------------------------------------------------------------#\n"
        );

    return ($::LOG_FILE_HANDLE);
}

#--------------------------------------------------------------------------------

=head3 stop_logging

        Turn off message logging close file. Routine expects to have a file handle
        passed in via the global $::LOG_FILE_HANDLE.

        Arguments:
               
        Returns:
                $::OK
        Globals:
                $::LOG_FILE_HANDLE
        Error:
                none
        Example:
                xCAT::MsgUtils->stop_logging($cfmupdatenode.log);
        Comments:
                closes the logfile and undefines $::LOG_FILE_HANDLE
                even on error.

=cut

#--------------------------------------------------------------------------------

sub stop_logging
{
    my ($class) = @_;
    if (defined($::LOG_FILE_HANDLE))
    {

        my $sdate = localtime(time);
        chomp $sdate;
        my $program = xCAT::Utils->programName();
        xCAT::MsgUtils->message(
            "TV",
            "#--------------------------------------------------------------------------#\n"
            );
        xCAT::MsgUtils->message("TV", "$program: Logging Stopped: $sdate\n");
        xCAT::MsgUtils->message(
            "TV",
            "#--------------------------------------------------------------------------#\n"
            );

        close($::LOG_FILE_HANDLE);
        undef $::LOG_FILE_HANDLE;
    }
    return $::OK;
}

1;

