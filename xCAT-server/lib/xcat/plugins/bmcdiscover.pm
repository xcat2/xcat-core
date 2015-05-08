# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle BMC discovery
=cut

#-------------------------------------------------------
package xCAT_plugin::bmcdiscover;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use File::Path;
use Cwd;


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
            bmcdiscover => "bmcdiscover",
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
    $::args     = $request->{arg};


    my $command  = $request->{command}->[0];
    my $rc;

    if ($command eq "bmcdiscover"){
        $rc = bmcdiscovery($request, $callback, $request_command);
    } else{
        $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
        return 1;
    }

}


#----------------------------------------------------------------------------

=head3  bmcdiscover_usage

        Display the bmcdiscover usage
=cut

#-----------------------------------------------------------------------------

sub bmcdiscovery_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: bmcdiscover - discover bmc using scan method,now scan_method can be nmap .\n";
    push @{ $rsp->{data} }, "\tbmcdiscover [-h|--help|-?]\n";
    push @{ $rsp->{data} }, "\tbmcdiscover [-v|--version]\n ";
    push @{ $rsp->{data} }, "\tbmcdiscover [-m|--method] scan_method [-r|--range] ip_range \n ";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
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
sub bmcdiscovery_processargs {
    if ( defined ($::args) && @{$::args} ){
        @ARGV = @{$::args};
    }

    # parse the options
    # options can be bundled up like -v, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    my $getopt_success = Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'method|m=s' => \$::opt_M,
                              'range|r=s' => \$::opt_R,
                              #'user|U=s' => \$::opt_U,
                              #'password|P=s' => \$::opt_P,
                              'version|v' => \$::opt_v,
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
        return 2;
    }

    #########################################
    # Option -v for version
    #########################################
    if ( defined($::opt_v) ) {
        create_version_response('bmcdiscover');
        # no usage - just exit
        return 1;    
    }

    #########################################
    # Option -m -r are must
    ######################################33
    if ( defined($::opt_M) && defined($::opt_R) ) {
        print "This is framework!"
    }

    #########################################
    # Other attributes are not allowed
    #########################################
    my $more_input = shift(@ARGV);
    if ( defined($more_input) ) {
        create_error_response("Invalid input: $more_input \n");
        return 3;
    } 

    return 0;
}

#----------------------------------------------------------------------------

=head3  split_comma_delim_str

        Split comma-delimited list of strings into an array.

        Arguments: comma-delimited string
        Returns:   Returns list of strings (ref)

=cut

#-----------------------------------------------------------------------------
sub split_comma_delim_str {
    my $input_str = shift;

    my @result = split(/,/, $input_str);
    return \@result;
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

=head3  create_error_response

        Create a response containing a single error message
        Arguments:  error message
=cut

#-----------------------------------------------------------------------------
sub create_error_response {
    my $error_msg = shift;
    my $rsp;
    push @{ $rsp->{data} }, $error_msg;
    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
}


#----------------------------------------------------------------------------

=head3  bmcdiscovery

        Support for discovering bmc
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------
sub bmcdiscovery {

    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $rc = 0;
    # process the command line
    # 0=success, 1=version, 2=help, 3=error

    $rc = bmcdiscovery_processargs(@_);
    if ( $rc != 0 ) {
       if ( $rc != 1) {
           bmcdiscovery_usage(@_);
       }
       return ( $rc - 1 );
    }


   return 0;

}





#----------------------------------------------------------------------------

=head3  bmcdiscovery_nmap

        Support for discovering bmc using nmap

        Arguments:
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------

sub bmcdiscovery_namp {

    print "hello world";

}



1;
