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
use xCAT::DiscoveryUtils;
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
    my $i     = 1;
    my @nodes = @$nodes;

    # do your processing here
    # return info


    my $client;
    if ($::XCATSITEVALS{nodeauthentication}) { #if requiring node authentication, this request will have a certificate associated with it, use it instead of name resolution
        unless (ref $request->{username}) { return; } #TODO: log an attempt without credentials?
        ($client) = noderange($request->{username}->[0]);
        unless ($client) {
            xCAT::MsgUtils->trace(0, "E", "Received getpostscript from $request->{username}->[0], which couldn't be correlated to a node (domain mismatch?)");
            return;
        }
    } else {
        my @candidates = xCAT::DiscoveryUtils::request_client_names($request);
        unless (@candidates) {
            xCAT::MsgUtils->trace(0, 'E', "Received getpostscript from a client this request does not identify: it carries no peer name and no client certificate name. Ignoring it.");
            return;
        }
        $client = xCAT::DiscoveryUtils::request_client_node($request, \&noderange);
        unless ($client) {    #Not able to do identify the host in question
            xCAT::MsgUtils->trace(0, "E", "Received getpostscript from " . join(', ', @candidates) . ", none of which could be correlated to a node (domain mismatch?)");
            return;
        }
    }
    my $state;
    if ($request->{scripttype}) { $state = $request->{scripttype}->[0]; }

    require xCAT::Postage;
    my $args = $request->{arg};
    my @scriptcontents;
    my $version = 0;
    if (defined($args) && grep(/version2/, @$args)) {
        $version = 2
    }
    my $notmpfiles;
    my $nofiles;

    # If not version=2, then we return the mypostscript file in an array.
    if ($version != 2) {
        $notmpfiles = 1;    # no tmp files and no files
        $nofiles = 1; # do not create /tftpboot/mypostscript/mypostscript.<nodename>
        @scriptcontents = xCAT::Postage::makescript([$client], $state, $callback, $notmpfiles, $nofiles);
        xCAT::MsgUtils->trace(0, "I", "getpostscript: Sending scripts data to $client...");
        $rsp->{data} = \@scriptcontents;
        $callback->($rsp);
    } else {          # version 2, make files, do not return array
        #  make the mypostscript.<nodename> file
        # or the mypostscript.<nodename>.tmp file if precreatemypostscripts=0
        # xcatdsklspost will wget the file
        $notmpfiles = 0;
        $nofiles    = 0;
        xCAT::Postage::makescript([$client], $state, $callback, $notmpfiles, $nofiles);
    }
    return 0;
}

