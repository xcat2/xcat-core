# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to non xcat resource

=cut

#-------------------------------------------------------
package xCAT_plugin::localrest;

BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Utils;
use xCAT::MsgUtils;
use File::Basename;
use strict;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
        localrest => "localrest",
    };
}

#-------------------------------------------------------

=head3  process_request

  Process the command.

=cut

#-------------------------------------------------------
sub process_request
{
    my $request = shift;
    $::callback = shift;
    my $subreq  = shift;
    my $command = $request->{command}->[0];

    if ($command eq "localrest") {
        return handle_rest_request($request, $subreq);
    }
}

#-------------------------------------------------------

=head3  handle_rest_request

  This function check the command option, then call the
  related function to complete the request.

  Usage example:
        This function is called from process_request,
        do not call it directly.
=cut

#-------------------------------------------------------

sub handle_rest_request {
    my ($request, $subreq) = @_;
    my ($method, $resource, @params, $subroutine, $rsp, $rc);
    require JSON;
    my $JSON = JSON->new();

    my @args = @{ $request->{arg} };
    if (scalar(@args) < 2) {
        $rsp->{data}->[0] = "Local rest api take at least two parameter.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    $method     = shift @args;
    $resource   = shift @args;
    $subroutine = $method . '_' . $resource;
    @params     = @args;

    # if related subroutine found, call it
    # subroutine for rest handler must return a ref to HASH or ARRAY
    # comtaining the data that should be return to the CGI
    if (__PACKAGE__->can({$subroutine})) {
        $rsp->{data}->[0] = "Unsupported request: $subroutine.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    no strict 'refs';
    my $result = $subroutine->(@params);

    # handle the result from the rest subroutine
    if (ref($result) eq 'HASH') {
        if (defined($result->{'type'}) && $result->{'type'} eq 'stream'
            && defined($result->{'filename'})) {
            $rsp->{data}->[0] = "stream";
            $rsp->{data}->[1] = $result->{'filename'};
            $rsp->{data}->[2] = $result->{'data'};
        } else {
            my $json = $JSON->encode($result);
            $rsp->{data}->[0] = "json";
            $rsp->{data}->[1] = $json;
        }
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        $rc = 0;
    } elsif (ref($result) eq 'ARRAY') {
        my $json = $JSON->encode($result);
        $rsp->{data}->[0] = "json";
        $rsp->{data}->[1] = $json;
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        $rc = 0;
    } elsif ($result == 1 || $result == 0) {
        $rc = $result;
    } else {
        $rc = 1;
        $rsp->{data}->[0] = "Internal error, result value is unacceptable";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
    }
    return $rc;
}

#-------------------------------------------------------

=head3  handler to list network adapters

  Subroutine to handle rest request
  GET /localres/adapter/

  Usage example:
        This function is called from handle_rest_request,
        do not call it directly.
=cut

#-------------------------------------------------------
sub list_adapter {
    my ($rsp, $result, $i);
    if (!opendir DIR, "/sys/class/net") {
        $rsp->{data}->[0] = "Unable open /sys/class/net dir.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    my @dir = readdir(DIR);
    closedir(DIR);
    $i = 0;
    foreach my $item (@dir) {
        if ($item eq '.' || $item eq '..') {
            next;
        }
        $result->[ $i++ ] = $item;
    }
    return $result;
}

#-------------------------------------------------------

=head3  handler to list network adapter first ip

  Subroutine to handle rest request
  GET /localres/netip/<iface>

  Usage example:
        This function is called from handle_rest_request,
        do not call it directly.
=cut

#-------------------------------------------------------
sub list_netip {
    my @params = @_;
    my ($rsp, $result, $iface, $cmd);
    if (!@params) {
        $rsp->{data}->[0] = "Argmument error.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    $iface = shift @params;
    $cmd = "ip addr show dev $iface |grep inet|head -1|awk '{print \$2}'|awk -F/ '{print \$1}'";

    $result->[ 0 ] = xCAT::Utils->runcmd("$cmd", -1);

    return $result;
}


#-------------------------------------------------------

=head3  handler to download credential files

  Subroutine to handle rest request
  GET /localres/credential/conserver/file
  GET /localres/credential/ca/file

  Usage example:
        This function is called from handle_rest_request,
        do not call it directly.
=cut

#-------------------------------------------------------
sub download_credential {
    my @params = @_;
    my ($rsp, $buf, $fpath, $fd, $data, $result, $n);
    if (!@params) {
        $rsp->{data}->[0] = "Argmument error.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    my %filemap = (
        'conserver' => "/home/conserver/.xcat/client-cred.pem",
        'ca'        => "/home/conserver/.xcat/ca.pem",
    );
    $fpath = $filemap{ $params[0] };
    if (!$fpath || !-e $fpath) {
        $rsp->{data}->[0] = "File resource for " . $params[0] . " unavailable.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }

    if (!($n = open($fd, '<', $fpath))) {
        $rsp->{data}->[0] = "Coundn't open file $fpath.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    while ($n = read($fd, $buf, 8192)) {
        $data .= $buf;
    }
    close($fd);
    $result->{'type'}     = 'stream';
    $result->{'filename'} = basename($fpath);
    $result->{'data'}     = $data;
    return $result;
}
1;
