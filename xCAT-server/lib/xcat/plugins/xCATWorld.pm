# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xCATWorld

   Supported command:
         xCATWorld->xCATWorld
         xCATWorld->xCATWorld

=cut

#-------------------------------------------------------
package xCAT_plugin::xCATWorld;
use Sys::Hostname;
use xCAT::Table;

use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
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
    return {xCATWorld => "xCATWorld"};
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy , if your command must run
  on service nodes. Otherwise preprocess_request not necessary   

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $callback  = shift;
    my $subreq = shift;
     $::CALLBACK = $callback;
    #if already preprocessed, go straight to request
    if (($req->{_xcatpreprocessed}) and ($req->{_xcatpreprocessed}->[0] == 1) ) { return [$req]; }
    my $nodes    = $req->{node};
    my $service  = "xcat";

    # find service nodes for requested nodes
    # build an individual request for each service node
    if ($nodes) {
     my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($nodes, $service, "MN");
     my @requests;
      # build each request for each service node

      foreach my $snkey (keys %$sn)
      {
            my $n=$sn->{$snkey};
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;

      }
      return \@requests;  # return requests for all Service nodes
    } else {
      return [$req];   # just return original request
    }
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
    my $subreq    = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    my %rsp;
    my @nodes=@$nodes; 
    @ARGV = @{$args};    # get arguments
    $::CALLBACK=$callback; 
    # do your processing here
    # return info
    Getopt::Long::Configure("posix_default");
    Getopt::Long::Configure("no_gnu_compat");
    Getopt::Long::Configure("bundling");
    my %options = ();
if (
        !GetOptions(
            'h|help'                   => \$options{'help'},
            'v|version'                => \$options{'version'},
            'V|Verbose'                => \$options{'verbose'}
        )
      )
    {  
        xCAT::DSHCLI->usage_dsh;
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
    # Here you call plugin to plugin
    # call another plugin
    # save your callback function

   my $out=xCAT::Utils->runxcmd( { command => ['xdsh'],
                                    node    => \@nodes,
                                    arg     => [ "-v","ls /tmp" ]
                             }, $subreq, 0,1);


    my $host=hostname();
    my $rsp={};
    $rsp->{data}->[0] = "Hello World from $host! I can process the following nodes:";
    xCAT::MsgUtils->message("I", $rsp, $callback, 0);
    foreach my $node (@nodes)
    {
        $rsp->{data}->[0] .= "$node\n";
    }
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
      my $usagemsg  = " xCATWorld -h \n xCATWorld -v \n xCATWorld -V \n";
      $usagemsg .= " xCATWorld  <noderange> ";
###  end usage mesage
        my $rsp = {};
        $rsp->{data}->[0] = $usagemsg;
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
  return;
}
