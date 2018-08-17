# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#TODO: delete entries not being refreshed if no noderange
package xCAT_plugin::goconserver;
BEGIN {
        $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use File::Copy;
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use Getopt::Long;
use Sys::Hostname;
use xCAT::SvrUtils;
use xCAT::Goconserver;
use Data::Dumper;

my $isSN;
my $host;
my $usage_string ="   makegocons [-V|--verbose] [-d|--delete] noderange
    -h|--help                   Display this usage statement.
    -v|--version                Display the version number.
    -C|--cleanup                Remove the entries for the nodes whose definitions have been removed from xCAT db.
    -q|--query  [noderange]     Display the console connection status.";

my $version_string = xCAT::Utils->Version();

sub handled_commands {
    return {
        makegocons => "goconserver"
      }
}

sub preprocess_request {
    my $request = shift;
    if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
    $::callback = shift;
    my @requests;
    my $noderange = $request->{node};    #Should be arrayref

    #display usage statement if -h
    my $extrargs = $request->{arg};
    my @exargs   = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }
    @ARGV = @exargs;

    $isSN     = xCAT::Utils->isServiceNode();
    my @hostinfo = xCAT::NetworkUtils->determinehostname();
    my %iphash   = ();
    foreach (@hostinfo) { $iphash{$_} = 1; }

    $Getopt::Long::ignorecase = 0;

    #$Getopt::Long::pass_through=1;
    if (!GetOptions(
        'h|help'      => \$::HELP,
        'D|debug'     => \$::DEBUG,
        'v|version'   => \$::VERSION,
        'V|verbose'   => \$::VERBOSE)) {
        $request = {};
        return;
    }
    if ($::HELP) {
        $::callback->({ data => $usage_string });
        $request = {};
        return;
    }
    if ($::VERSION) {
        $::callback->({ data => $version_string });
        $request = {};
        return;
    }

    # get site master
    my $master = xCAT::TableUtils->get_site_Master();
    if (!$master) { $master = hostname(); }

    # get conserver for each node
    my %cons_hash = ();
    my $hmtab     = xCAT::Table->new('nodehm');
    my @items;
    my $allnodes = 1;
    if ($noderange && @$noderange > 0) {
        $allnodes = 0;
        my $hmcache = $hmtab->getNodesAttribs($noderange, [ 'node', 'serialport', 'cons', 'conserver' ]);
        foreach my $node (@$noderange) {
            my $ent = $hmcache->{$node}->[0]; #$hmtab->getNodeAttribs($node,['node', 'serialport','cons', 'conserver']);
            if ($ent) {
                push (@items, $ent);
            } else {
                my $rsp->{data}->[0] = $node .": ignore, cons attribute or serialport attribute is not specified.";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
            }
        }
    } else {
        $allnodes = 1;
        @items = $hmtab->getAllNodeAttribs([ 'node', 'serialport', 'cons', 'conserver' ]);
    }
    my @nodes = ();
    foreach (@items) {
        if (((!defined($_->{cons})) || ($_->{cons} eq "")) and !defined($_->{serialport})) {
            my $rsp->{data}->[0] = $_->{node} .": ignore, cons attribute or serialport attribute is not specified.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
            next;
        }
        if (defined($_->{conserver})) { push @{ $cons_hash{ $_->{conserver} }{nodes} }, $_->{node}; }
        else { push @{ $cons_hash{$master}{nodes} }, $_->{node}; }
        push @nodes, $_->{node};
    }

    # send to conserver hosts
    foreach my $host (keys %cons_hash) {
        my $reqcopy = {%$request};
        $reqcopy->{'_xcatdest'} = $host;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        $reqcopy->{'_allnodes'} = [$allnodes]; # the original command comes with nodes or not
        $reqcopy->{node} = $cons_hash{$host}{nodes};
        push @requests, $reqcopy;
    }    #end foreach

    if ($::DEBUG) {
        my $rsp;
        $rsp->{data}->[0] = "In preprocess_request, request is " . Dumper(@requests);
        xCAT::MsgUtils->message("I", $rsp, $::callback);
    }
    return \@requests;
}

sub process_request {
    my $req = shift;
    $::callback  = shift;
    my @hostinfo = xCAT::NetworkUtils->determinehostname();
    $host = $hostinfo[-1];
    $isSN = xCAT::Utils->isServiceNode();
    if ($req->{command}->[0] eq "makegocons") {
        makegocons($req, \@hostinfo);
    }
}

sub start_goconserver {
    my ($rsp, $running, $ready, $ret);
    unless (-x "/usr/bin/goconserver") {
        xCAT::MsgUtils->error_message("goconserver is not installed.", $::callback);
        return 1;
    }
    # if goconserver is installed, check the status of conserver service.
    if (xCAT::Goconserver::is_conserver_running()) {
        xCAT::MsgUtils->error_message("conserver is started, please stop it at first.", $::callback);
        return 1;
    }
    xCAT::Goconserver::switch_goconserver($::callback);
    $running = xCAT::Goconserver::is_goconserver_running();
    $ready = xCAT::Goconserver::is_xcat_conf_ready();
    if ( $running && $ready ) {
        # Already started by xcat
        return 0;
    }
    # user could customize the configuration, do not rewrite the configuration if this file has been
    # generated by xcat
    if (!$ready) {
        $ret = xCAT::Goconserver::build_conf();
        if ($ret) {
            xCAT::MsgUtils->error_message("Failed to create configuration file for goconserver.", $::callback);
            return 1;
        }
        if (!copy($::XCATROOT."/share/xcat/conf/goconslogrotate", "/etc/logrotate.d/goconserver")) {
            xCAT::MsgUtils->warn_message("Failed to create logrotate configuration for goconserver.", $::callback);
        }
    }
    $ret = xCAT::Goconserver::restart_service();
    if ($ret) {
        xCAT::MsgUtils->error_message("Failed to start goconserver service.", $::callback);
        return 1;
    }
    xCAT::MsgUtils->info_message("Starting goconserver service ...", $::callback);
    sleep(3);
    return 0;
}

sub makegocons {
    my $req = shift;
    my $hostinfo = shift;
    my $extrargs = $req->{arg};
    my @exargs   = ($req->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }
    @ARGV = @exargs;
    $Getopt::Long::ignorecase = 0;
    my ($delmode, $querymode, $cleanupmode);
    GetOptions('d|delete' => \$delmode,
        'q|query' => \$querymode,
        'C|cleanup' => \$cleanupmode,
    );

    my $svboot = 0;
    my $rsp;
    if (exists($req->{svboot})) {
        $svboot = 1;
    }
    if ($cleanupmode) {
        if (exists($req->{_allnodes}) && $req->{_allnodes}->[0] != 1) {
            xCAT::MsgUtils->error_message("Can not specify noderange together with -C|--cleanup.", $::callback);
            return 1;
        }
        return xCAT::Goconserver::cleanup_nodes($::callback);
    }
    my %cons_map = xCAT::Goconserver::get_cons_map($req);
    if (! %cons_map) {
        xCAT::MsgUtils->error_message("Could not get any console request entry.", $::callback);
        return 1;
    }
    my $api_url = "https://$host:". xCAT::Goconserver::get_api_port();
    if ($querymode) {
        return xCAT::Goconserver::list_nodes($api_url, \%cons_map, $::callback)
    }

    my $ret = start_goconserver();
    if ($ret != 0) {
        return 1;
    }
    my @entries    = xCAT::TableUtils->get_site_attribute("consoleondemand");
    my $site_entry = $entries[0];
    my $siteondemand = 0;
    if (defined($site_entry)) {
        if (lc($site_entry) eq "yes") {
            $siteondemand = 1;
        }
        elsif (lc($site_entry) ne "no") {
            # consoleondemand attribute is set, but it is not "yes" or "no"
            xCAT::MsgUtils->error_message("Unexpected value $site_entry for consoleondemand attribute in site table.", $::callback);
        }
    }
    my (@nodes);
    my $data = xCAT::Goconserver::gen_request_data(\%cons_map, $siteondemand, $::callback);
    if (! $data) {
        xCAT::MsgUtils->error_message("Could not generate the request data.", $::callback);
        return 1;
    }
    $ret = xCAT::Goconserver::delete_nodes($api_url, $data, $delmode, $::callback);
    if ($delmode) {
        return $ret;
    }
    $ret = xCAT::Goconserver::create_nodes($api_url, $data, $::callback);
    if ($ret != 0) {
        xCAT::MsgUtils->error_message("Failed to create console entry in goconserver.", $::callback);
        return $ret;
    }
    return 0;
}

1;
