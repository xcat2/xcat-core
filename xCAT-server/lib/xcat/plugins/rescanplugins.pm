# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to tell xcatd daemon to rescan plugin directory

   Supported command:
         rescanplugins->rescanplugins

=cut

#-------------------------------------------------------
package xCAT_plugin::rescanplugins;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
use strict;
1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {rescanplugins => "rescanplugins"};
}

#-------------------------------------------------------

=head3  preprocess_request

   If hierarchy, send request to xcatd on service nodes

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req  = shift;
    my $callback = shift;
    my $subreq    = shift;
    $::CALLBACK=$callback; 
    my $args     = $req->{arg};
    my $envs     = $req->{env};


  #if already preprocessed, go straight to request
    if (($req->{_xcatpreprocessed}) and 
        ($req->{_xcatpreprocessed}->[0] == 1) ) { return [$req]; }


    # do your processing here
    # return info
   if ($args) {
        @ARGV = @{$args};    # get arguments
    }
    Getopt::Long::Configure("posix_default");
    Getopt::Long::Configure("no_gnu_compat");
    Getopt::Long::Configure("bundling");
    my %options = ();
    if (
        !GetOptions(
            'h|help'                   => \$options{'help'},
            's|servicenodes'           => \$options{'servicenodes'},
            'v|version'                => \$options{'version'},
            'V|Verbose'                => \$options{'verbose'}
        )
      )
    {  
        &usage;
        exit 1;
    }

    if ($options{'help'})
    {
        &usage;
        exit 0;
    }

   if ($options{'version'})
    {
        my $version = xCAT::Utils->Version();
        #$version .= "\n";
        my $rsp={};
        $rsp->{data}->[0] = $version;        
        xCAT::MsgUtils->message("I",$rsp,$callback, 0);
        exit 0;
    }


    if ( @ARGV && $ARGV[0] ) {
        my $rsp={};
        $rsp->{data}->[0] = "Ignoring arguments ". join(',',@ARGV);
        xCAT::MsgUtils->message("I",$rsp,$callback, 0);
    }

    if ( $req->{node} && $req->{node}->[0] ) {
        my $rsp={};
        $rsp->{data}->[0] = "Ignoring nodes ". join(',',@{$req->{node}});
        xCAT::MsgUtils->message("I",$rsp,$callback, 0);
        $req->{node}=[];
    }

    if ($options{'servicenodes'}) {

    # Run rescanplugins on MN and all service nodes
    # build an individual request for each service node
        my @requests;
            my $MNreq = {%$req};
            $MNreq->{_xcatpreprocessed}->[0] = 1;
            push @requests, $MNreq;
 
        foreach my $sn (xCAT::ServiceNodeUtils->getAllSN())
        {
            my $SNreq = {%$req};
            $SNreq->{'_xcatdest'} = $sn;
            $SNreq->{_xcatpreprocessed}->[0] = 1;
            push @requests, $SNreq;

        }
        return \@requests;  # return requests for all Service nodes
    } 

  return [$req];
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{
    my $req  = shift;
    my $callback = shift;
    my $subreq    = shift;

    # The xcatd daemon should intercept this command and process it directly

    print "in rescanplugins->process_request -- xcatd should process this request directly.  WE SHOULD NEVER GET HERE \n";
    my $rsp={};
    $rsp->{data}->[0] = "in rescanplugins->process_request:  xcatd should process this request directly. WE SHOULD NEVER GET HERE";
    xCAT::MsgUtils->message("I", $rsp, $callback, 0);
    return;

}
#-------------------------------------------------------------------------------

=head3
      usage

        puts out  usage message  for help

        Arguments:
          None

        Returns:

        Globals:

        Error:
                None


=cut

#-------------------------------------------------------------------------------

sub usage
{
## usage message
      my $usagemsg  = " rescanplugins [-h|--help] \n rescanplugins [-v|--version] \n rescanplugins [-s|--servicenodes]\n";
###  end usage mesage
        my $rsp = {};
        $rsp->{data}->[0] = $usagemsg;
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
  return;
}
