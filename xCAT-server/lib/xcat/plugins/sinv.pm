# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle sinv 

   Supported command:
         sinv - software/firmware inventory program
                run xdsh or rinv.  See man sinv.

=cut

#-------------------------------------------------------
package xCAT_plugin::sinv;
use strict;

require xCAT::Utils;

require xCAT::MsgUtils;
require xCAT::SINV;
use Getopt::Long;


#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {sinv => "sinv",};
}

#-------------------------------------------------------

=head3  preprocess_request ( handles hierachy,  TBD)


=cut

#-------------------------------------------------------
#sub preprocess_request
#{
#    my $req = shift;
#    my $cb  = shift;
#     $::CALLBACK = $cb;
#    my %sn;
#    my $sn;
#    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
#    my $nodes    = $req->{node};
#    my $service  = "xcat";
#    my @requests;
#    #display usage statement if -h and version if -v
#    my $extrargs = $req->{arg};
#    my @exargs=($req->{arg});
#    if (ref($extrargs)) {
#      @exargs=@$extrargs;
#    }
#    @ARGV=@exargs;
#  $Getopt::Long::ignorecase=0;
#  if(!GetOptions(
#      'h|help'     => \$::HELP,
#      'v|version'  => \$::VERSION)) {
#    $req= {};
#    #return;
#  }
#  if ($::HELP) {
#    xCAT::SINV->usage();
#    $req = {};
#    return;
#  }
#  if ($::VERSION) {
#     my $version = xCAT::Utils->Version();
#     $version .= "\n";
#     my $rsp = {};
#     $rsp->{data}->[0] = $version;
#     xCAT::MsgUtils->message("I", $rsp, $cb);
#    $req= {};
#    return;
#  }
#  if ($nodes) {
#    # find service nodes for requested nodes
#    # build an individual request for each service node
#    $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");
#
#    # build each request for each service node
#
#    foreach my $snkey (keys %$sn)
#    {
#            my $reqcopy = {%$req};
#            $reqcopy->{node} = $sn->{$snkey};
#            $reqcopy->{'_xcatdest'} = $snkey;
#            $reqcopy->{_xcatpreprocessed}->[0] = 1
#            push @requests, $reqcopy;
#
#    }
#  } else {   # no nodes
#        my $rsp = {};
#        $rsp->{data}->[0] = "No noderange specified on the command.\n";
#        xCAT::MsgUtils->message("E", $rsp, $cb);
#        $req= {};
#        return;
#
#  }
#    return \@requests;
# }
#
#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $sub_req = shift;

    sinv($request, $callback,$sub_req);
}

#-------------------------------------------------------

=head3  sinv 

   Parses Builds and runs the sinv 


=cut

#-------------------------------------------------------
sub sinv
{
    my ($request, $callback, $sub_req) = @_;


    # parse  input  and run dsh
    my @local_results =
      xCAT::SINV->parse_and_run_sinv($request, $callback,
                                      $sub_req);
    my $rsp = {};
    push @{$rsp->{data}}, @local_results;

    xCAT::MsgUtils->message("I", $rsp, $callback);

    return;
}
1;
