# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle getpostscript command

=cut

#-------------------------------------------------------
package xCAT_plugin::getpostscript;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::NodeRange;
1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return { 
               'getpostscript' => "getpostscript",
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
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    my $rsp;
    my $i = 1;
    my @nodes=@$nodes; 
    # do your processing here
    # return info
    

    my $client;
    if ($::XCATSITEVALS{nodeauthentication}) { #if requiring node authentication, this request will have a certificate associated with it, use it instead of name resolution
	unless (ref $request->{username}) { return; } #TODO: log an attempt without credentials? 
	$client = $request->{username}->[0];
    } else {
	    unless ($request->{'_xcat_clienthost'}->[0]) {
	      #ERROR? malformed request
	      return; #nothing to do here...
	    }
	    $client = $request->{'_xcat_clienthost'}->[0];
    }

    my $origclient = $client;
    if ($client) { ($client) = noderange($client) };
    unless ($client) { #Not able to do identify the host in question
       xCAT::MsgUtils->message("S","Received getpostscript from $origclient, which couldn't be correlated to a node (domain mismatch?)");
      return;
    }
    my $state;
    if ($request->{scripttype}) { $state = $request->{scripttype}->[0];}

    require xCAT::Postage;
    my $args = $request->{arg};
    my @scriptcontents;
    my $version =0;
    #  make the mypostscript.<nodename> file 
    # or the mypostscript.<nodename>.tmp file if precreatemypostscripts=0
    # right now @scriptcontents is null 
    @scriptcontents = xCAT::Postage::makescript([$client],$state,$callback);
    if( defined($args) && grep(/version2/, @$args)) {
        $version =2 
    }
    # for version=2, we do not return the created mypostscript file.
    # xcatdsklspost  must wget
    # If not version=2, then we return the mypostscript file buffer.
    if ($version != 2) {    
        my $filename="mypostscript.$client";
        my $cmd;
        if (!(-e $filename)) {
            $filename="mypostscript.$client.tmp";
        }
        $cmd="cat /tftpboot/mypostscripts/$filename";
        @scriptcontents = xCAT::Utils->runcmd($cmd,0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{error}->[0] = "Command: $cmd failed.";
            xCAT::MsgUtils->message("S", $rsp, $::CALLBACK);
        }
 
       `logger -t xCAT -p local4.info "getpostscript: sending data"` ;
       $rsp->{data} = \@scriptcontents;
       $callback->($rsp);
    }
    return 0;
}

