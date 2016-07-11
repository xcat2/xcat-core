# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle system command
=cut

#-------------------------------------------------------
package xCAT_plugin::runsyscmd;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use IO::Socket;
use Thread qw(yield);
use POSIX "WNOHANG";
use Storable qw(store_fd fd_retrieve);
use strict;
use warnings "all";
use Getopt::Long;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use File::Path;
use Cwd;

my $nmap_path;

my $debianflag = 0;
my $tempstring = xCAT::Utils->osver();
if ( $tempstring =~ /debian/ || $tempstring =~ /ubuntu/ ){
    $debianflag = 1;
}
my $parent_fd;
my $bmc_user;
my $bmc_pass;
#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            runsyscmd => "runsyscmd",
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

    unless(defined($request->{arg})){
        runsyscmd_usage();
        return 2; 
    }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            return 2;
    }


    my $command  = $request->{command}->[0];
    my $rc;

    if ($command eq "runsyscmd"){
        $rc = runsyscmd($request, $callback, $request_command);
    } else{
        $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
        return 1;
    }

}


#----------------------------------------------------------------------------

=head3  runsyscmd_usage

        Display the runsyscmd usage
=cut

#-----------------------------------------------------------------------------

sub runsyscmd_usage {
    my $rsp;
    push @{ $rsp->{data} }, "\nrunsyscomd - Execute system command\n";
    push @{ $rsp->{data} }, "Usage:";
    push @{ $rsp->{data} }, "\trunsyscmd [-?|-h|--help]";
    push @{ $rsp->{data} }, "\trunsyscmd [-v|--version]";
    push @{ $rsp->{data} }, "\trunsyscmd [-c command]\n";

    push @{ $rsp->{data} }, "\tExecute system command:";
    push @{ $rsp->{data} }, "\t\trunsyscmd -c command";

    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    #return 0;
}

#----------------------------------------------------------------------------

=head3   bmcdiscovery_processargs

        Process the bmcdiscovery command line
        Returns:
                0 - OK
                1 - just print version
                2 - just print help
                3 - error
=cut

#-----------------------------------------------------------------------------
sub runsyscmd_processargs {

    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;

    
    # parse the options
    # options can be bundled up like -v, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    my $getopt_success = Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'c=s' => \$::opt_C,
                              'version|v' => \$::opt_v
    );

    if (!$getopt_success) {
        return 3;
    }


    #########################################
    # This command is for linux
    #########################################
    if ($^O ne 'linux') {
        my $rsp = {};
        push @{ $rsp->{data}}, "The bmcdiscovery command is only supported on Linux.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    ##########################################
    # Option -h for Help
    ##########################################
    if ( defined($::opt_h) ) {
          runsyscmd_usage;   
          return 0; 
    }

    #########################################
    # Option -v for version
    #########################################
    if ( defined($::opt_v) ) {
        create_version_response('runsyscmd');
        # no usage - just exit
        return 1;    
    }

    if ( defined($::opt_C) ) {
        my $rc=execute_cmd($::opt_C);
        return $rc;
    } 

    #########################################
    # Other attributes are not allowed
    #########################################

    return 4;
}


#----------------------------------------------------------------------------

=head3  runsyscmd

        Support for discovering bmc
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------
sub runsyscmd {

    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;

    ##############################################################
    # process the command line
    # 0=success, 1=version, 2=error 
    ##############################################################
    $rc = runsyscmd_processargs($request,$callback,$request_command);
    if ( $rc != 0 ) {
       if ( $rc != 1 ) 
       {
               runsyscmd_usage(@_);
       }
       return ( $rc - 1 );
    }

   return $rc;

}

#----------------------------------------------------------------------------

=head3  create_version_response

        Create a response containing the command name and version

=cut

#-----------------------------------------------------------------------------
sub create_version_response {
    my $command = shift;
    my $rsp;
    my $version = xCAT::Utils->Version();
    push @{ $rsp->{data} }, "$command - xCAT $version";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
}

#----------------------------------------------------------------------------

=head3  execute_cmd

        Execute system command

=cut

#-----------------------------------------------------------------------------
sub execute_cmd {

    my $cmd_string = shift;
    my $callback = $::CALLBACK;
  
    my @cmd_array = split / /, $cmd_string;
    my $ccmd = $cmd_array[0];
    if ( $ccmd && $ccmd =~ "ls" ){
        my $cmd_result = xCAT::Utils->runcmd($cmd_string, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp = {};
            push @{ $rsp->{data} }, "$cmd_string is failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return 2;
        } else {
            my $rsp = {};
            push @{ $rsp->{data} }, "$cmd_result";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
            return 0;
        }
    } else {

        my $rsp = {};
        push @{ $rsp->{data} }, "Command $ccmd is not supported.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 2;

    }
}

1;
