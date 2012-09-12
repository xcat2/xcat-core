#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle commands that manage the xCAT os distro updates
#
#####################################################

package xCAT_plugin::osdistroupdate;

#use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use xCAT::Utils;
use strict;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;

#------------------------------------------------------------------------------

=head1    osdistroupdate

This program module file supports the management of the xCAT os distro updates.

Supported xCAT OS distro updates functions:
    1.Create os distro update from network 
    2.Create os distro update from local
    3.List the distro update on the management node
    4.Delete the distro update     

Syntax:
     osdistroupdate [-h|--help|-v|--version]
     osdistroupdate -l [<osdistro-name>]
     osdistroupdate -d <osdistroupdate-name>
     osdistroupdate -c <osdistro-name> [-p <package directory>]

Options:
     -h   Show the help message
     -v   Show the version.
     -l   List OS distro update with specified OS distro name, if no OS distro specified, 
          all OS distro updates in system will be listed. The osdistro-name value will 
          be <osver>-<arh>, such as rhels6.2-x86_64 .
     -d   Delete an OS distro update in system
     -c   Create an OS distro updates in system
     -p   Specify local directory which contains packages downloaded from distro official site. This option is used to create OS update from local.

=cut

#------------------------------------------------------------------------------

=head2  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------

sub handled_commands
{
    return {
            osdistroupdate => "osdistroupdate",
            };
}


##########################################################################
# Pre-process request from xCat daemon. Send the request to the the service
# nodes of the HCPs.
##########################################################################
sub preprocess_request {

    my $req      = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1 ) { return [$req]; }
    my $callback = shift;
    my @result;

    # process the command line
    my $rc = &parse_args($req, $callback);
    if ($rc != 0)
    {
        if( $rc == 1) {
           #version
           return 0;
        }
	&osdistroupdate_usage($callback);
	return -1;
    }
    
    my $mncopy = {%$req};
    push @result, $mncopy;

    #print Dumper(\@result);
    return \@result;
}





#----------------------------------------------------------------------------

=head2   process_request

        Check for xCAT command and call the appropriate subroutine.

        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub process_request
{

    my $request  = shift;
    my $callback = shift;

    &osdistroupdate($request,$callback);
}

#----------------------------------------------------------------------------

=head2   parse_args

        Process the command line. Covers all four commands.

        Also - Process any input files provided on cmd line.

        Arguments:

        Returns:
                0 - OK
                1 - just return
                2 - just print usage
                3 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub parse_args
{
    my $request = shift;
    my $callback = shift; 
    my $args = $request->{arg};
    my $gotattrs = 0;
    my %opt      =();

    if (defined(@{$args})) {
        @ARGV = @{$args};
    } else {
        return 2;
    }

    if (scalar(@ARGV) <= 0) {
        return 2;
    }

    # parse the options - include any option from all 4 cmds
    Getopt::Long::Configure("no_pass_through");
    if ( !GetOptions( \%opt, qw(h|help v|version l c=s d=s p=s ) )) {
         return 2;
    }

    if ( exists( $opt{v}) || exists( $opt{version} )) {
         my $rsp = {};
         $rsp->{data}->[0] = xCAT::Utils->Version();
         $callback->($rsp);
         return 1;
    }

    if ( exists( $opt{h}) || exists( $opt{help})) {
         return 2;
    }

    if ( exists( $opt{l}) &&  exists( $opt{c}))  {
         my $rsp;
         $rsp->{data}->[0] = "The flags \'-l'\ and \'-c'\ cannot be used together.";
         xCAT::MsgUtils->message("E", $rsp, $callback);
         return 2; 
    }

    if (  exists( $opt{l}) &&  exists( $opt{d})){
         my $rsp;
         $rsp->{data}->[0] = "The flags \'-l'\ and \'-d'\ cannot be used together.";
         xCAT::MsgUtils->message("E", $rsp, $callback);
         return 2; 
    }

    if ( exists( $opt{c}) &&  exists( $opt{d}) ) {
         my $rsp;
         $rsp->{data}->[0] = "The flags \'-c'\ and \'-d'\ cannot be used together.";
         xCAT::MsgUtils->message("E", $rsp, $callback);
         return 2; 
    }

    if ( exists( $opt{p}) &&  (exists( $opt{l}) || exists( $opt{d})) ) {
         my $rsp;
         $rsp->{data}->[0] = "The flags \'-p'\ only could be used with -c";
         xCAT::MsgUtils->message("E", $rsp, $callback);
         return 2; 
    }

      
    if(exists( $opt{l}) ) {
        $opt{osdistroupdate_name} = $ARGV[0]; 
    } 
    
    $request->{opt} = \%opt;    
    
    return 0;
}

sub osdistroupdate
{
    my $request = shift; 
    my $callback = shift;
    my $opt = $request->{opt};
    my $rsp_info;
    my $rc;
    my $result;
    my $data;
    my @attribs= qw(osdistroname dirpath downloadtime comments disable);

    # For list the os distro updates 
    if( $opt->{l} ) {
       $result = &list_updates($request, $callback);
       $rc = shift(@$result);
       $data = $result;
       if( $rc != 0) { 
           my $msg = join("\n", @$data); 
           #foreach my $a (@$data)  {
           #    push (@{$rsp_info->{data}->[$n]}, "$a");
           #}
           $rsp_info->{data}->[0] = $msg;  
           $rsp_info->{errorcode}->[0] = $rc;
           $callback->($rsp_info);
           return ;
       }

       #rc=0, success
       foreach my $a (@$data) {
            if( $a->{osupdatename} ) {
               push (@{$rsp_info->{data}}, "osdistroupdate name: $a->{osupdatename}");
            }     
            foreach my $at ( @attribs ) {
               if( defined( $a->{$at}) ) {
                   push (@{$rsp_info->{data}}, "    $at=$a->{$at}");
               }           
            }     
       }
       if (defined($rsp_info->{data}) && scalar(@{$rsp_info->{data}}) > 0) {
            xCAT::MsgUtils->message("I", $rsp_info, $callback);
       }
       return;
    }
    
    #Create os distro updates
    if( $opt->{c} ) {
       $result = &create_updates($request, $callback);
    }
    #delete os distro updates
    if( $opt->{d} ) {
       $result = &delete_update($request, $callback);
    }
       
    $rc = shift(@$result);
    $data = $result;
    my $msg = join("\n", @$data); 
    $rsp_info->{data}->[0] = $msg;  
    $rsp_info->{errorcode}->[0] = $rc;
    $callback->($rsp_info);
   
    return ;

}

#example of list_updates. This should be replaced.
sub list_updates
{
    my $request =shift;
    my $callback=shift;
    my @result;

    #my $rc = 1;
    #push(@result, $rc); 
    #push(@result, "msg1"); 
    #push(@result, "msg2"); 
    #push(@result, "msg3"); 
    
    my %h;
    my $rc = 0;
    push(@result, $rc);
    %h = (
          'osupdatename' => 'rhels6.2-x86_64-update12125',
          'osdistroname' => 'rhels6.2-x86_64',
          'dirpath' => '/install/osdistroupdates/rhels6.2-x86_64-20120228-update12125/',
          'downloadtime' => '1330402626',
          'comments' => undef,
          'disable' => '0',
          );
 
    push(@result, \%h);

    return \@result;
}

#example of create_updates. This should be replaced.
sub create_updates
{
    my $request =shift;
    my $callback=shift;
    my $opt=$request->{opt};
    my $rsp_info;
    my @result;

    push (@{$rsp_info->{data}}, "Starting... waiting...");
   
    xCAT::MsgUtils->message("I", $rsp_info, $callback);

    sleep(10);
 
    my $rc = 0;
    push(@result, $rc); 
    push(@result, "creating msg1"); 
    push(@result, "creating msg2"); 
    push(@result, "creating msg3"); 
    push(@result, "done"); 
   
    return \@result;
}

#example of delete_update. This should be replaced.
sub delete_update
{
    my $request =shift;
    my $callback=shift;
    my $opt=$request->{opt};
    my $rsp_info;
    my @result;

    push (@{$rsp_info->{data}}, "Starting deleting... waiting...");
   
    xCAT::MsgUtils->message("I", $rsp_info, $callback);

    sleep(10);
 
    my $rc = 0;
    push(@result, $rc); 
    push(@result, "deleting msg1"); 
    push(@result, "deleting msg2"); 
    push(@result, "deleting msg3"); 
    push(@result, "done"); 
   
    return \@result;
}



#----------------------------------------------------------------------------

=head3  osdistroupdate_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub osdistroupdate_usage
{
    my $callback = shift;
    my $rsp;
    $rsp->{data}->[0] = "\nUsage: osdistroupdate - creating/deleting/listing os distro update\n";
    $rsp->{data}->[1] = "  osdistroupdate  [-h | --help | -v | --version]";
    $rsp->{data}->[2] =
      "  osdistroupdate -l [<osdistro-name>]";
    $rsp->{data}->[3] =
      "  osdistroupdate -d <osdistroupdate-name>";
    $rsp->{data}->[4] =
      "  osdistroupdate -c <osdistro-name> [-p <package directory>]\n";
    $rsp->{data}->[5] = "-h   Show the help message";
    $rsp->{data}->[6] = "-v   Show the version.";
    $rsp->{data}->[7] = "-l   List OS distro update with specified OS distro name, if no OS distro specified, all OS distro updates in system will be listed. The osdistro-name value will be <osver>-<arh>, such as rhels6.2-x86_64.";
    $rsp->{data}->[8] = "-d   Delete an OS distro update in system";
    $rsp->{data}->[8] = "-c   Create an OS distro updates in system";
    $rsp->{data}->[8] = "-p   Specify local directory which contains packages downloaded from distro official site. This option is used to create OS update from local.";

    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

1;

