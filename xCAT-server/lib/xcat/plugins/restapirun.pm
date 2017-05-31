# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle system command
=cut

#-------------------------------------------------------
package xCAT_plugin::restapirun;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use Getopt::Long;
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;


my $debianflag = 0;
my $tempstring = xCAT::Utils->osver();
if ( $tempstring =~ /debian/ || $tempstring =~ /ubuntu/ ){
    $debianflag = 1;
}

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            restapirun => "restapirun",
	   };
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $request_command = shift;
    $::CALLBACK = $callback;


    my $command  = $request->{command}->[0];
    my $rc;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "Usage: restapirun - Execute for restapi.";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    };

    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            $xusage->(1);
            return;
    }

    if ($command eq "restapirun"){
        $rc = restapirun($request, $callback, $request_command);
    } else{
        $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
        return 1;
    }
}

#----------------------------------------------------------------------------

=head3  restapirun

        To run sub command
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------

sub restapirun {
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;
    my $subcmd = shift @ARGV;
    if (defined(&$subcmd)){
        if ( $subcmd eq "syscmd" ) {
            $rc = syscmd($request, $callback, $request_command);
        }else{
            $callback->({error=>["Error: sub-command $subcmd not found in this module."],errorcode=>[1]});
            return 1;
        }
    }
        
}

#----------------------------------------------------------------------------

=head3  syscmd

        Execute system command
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub syscmd {

    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;


    my $ccmd = shift @ARGV;
    if ( defined($ccmd) ) {
        $rc=execute_cmd($ccmd);
    }
    return $rc;

}


#----------------------------------------------------------------------------

=head3  execute_cmd

        Execute system command
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub execute_cmd {

    my $cmd_string = shift;
    my $callback = $::CALLBACK;
  
    my @cmd_array = split / /, $cmd_string;
    my $ccmd = $cmd_array[0];
    my @validcmd_array = ("ls");

    if ( $ccmd && grep { $_ eq $ccmd } @validcmd_array ){
        my @cmd_result = xCAT::Utils->runcmd($cmd_string, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp = {};
            push @{ $rsp->{data} }, "$cmd_string is failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 1;
        } else {
            
            my $rsp = {};
            #push @{ $rsp->{data} }, $cmd_result;
            foreach my $f (@cmd_result)
            {
                    push(@{ $rsp->{data} }, $f);
            }

            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
            return 0;
        }
    } else {
        my $rsp = {};
        push @{ $rsp->{data} }, "Command $ccmd is not supported.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;

    }
}

1;
