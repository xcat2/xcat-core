# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#TODO: delete entries not being refreshed if no noderange
package xCAT_plugin::goconserver;
BEGIN {
        $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
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
my $bmc_cons_port = "2200";
my $usage_string ="   makegocons [-V|--verbose] [-d|--delete] noderange
    -h|--help                   Display this usage statement.
    -v|--version                Display the version number.
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

sub get_cons_map {
    my ($req, $iphashref) = @_;
    my %cons_map;
    my %iphash = %{$iphashref};
    my $hmtab = xCAT::Table->new('nodehm');
    my @cons_nodes;

    if (($req->{node} and @{$req->{node}} > 0) or $req->{noderange}->[0]) {
        # Note: do not consider terminal server currently
        @cons_nodes = $hmtab->getNodesAttribs($req->{node}, [ 'node', 'cons', 'serialport', 'mgt', 'conserver', 'consoleondemand' ]);
        # Adjust the data structure to make the result consistent with the getAllNodeAttribs() call we make if a noderange was not specified
        my @tmpcons_nodes;
        foreach my $ent (@cons_nodes)
        {
            foreach my $nodeent (keys %$ent)
            {
                push @tmpcons_nodes, $ent->{$nodeent}->[0];
            }
        }
        @cons_nodes = @tmpcons_nodes

    } else {
        @cons_nodes = $hmtab->getAllNodeAttribs([ 'cons', 'serialport', 'mgt', 'conserver', 'consoleondemand' ]);
    }
    $hmtab->close();
    my $rsp;

    foreach (@cons_nodes) {
        if ($_->{cons} or defined($_->{'serialport'})) {
            unless ($_->{cons}) { $_->{cons} = $_->{mgt}; } #populate with fallback
            if ($isSN && $_->{conserver} && exists($iphash{ $_->{conserver} }) || !$isSN) {
                $cons_map{ $_->{node} } = $_; # also put the ref to the entry in a hash for quick look up
            } else {
                $rsp->{data}->[0] = $_->{node} .": ignore, the host for conserver could not be determined.";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
            }
        } else {
            $rsp->{data}->[0] = $_->{node} .": ignore, cons attribute or serialport attribute is not specified.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
    }
    return %cons_map;
}

sub gen_request_data {
    my ($cons_map, $siteondemand) = @_;
    my (@openbmc_nodes, $data);
    while (my ($k, $v) = each %{$cons_map}) {
        my $ondemand;
        if ($siteondemand) {
            $ondemand = \1;
        } else {
            $ondemand = \0;
        }
        my $cmd;
        my $cmeth  = $v->{cons};
        if ($cmeth eq "openbmc") {
            push @openbmc_nodes, $k;
        }  else {
            $cmd = $::XCATROOT . "/share/xcat/cons/$cmeth"." ".$k;
            if (!(!$isSN && $v->{conserver} && xCAT::NetworkUtils->thishostisnot($v->{conserver}))) {
                my $env;
                my $locerror = $isSN ? "PERL_BADLANG=0 " : '';
                if (defined($ENV{'XCATSSLVER'})) {
                    $env = "XCATSSLVER=$ENV{'XCATSSLVER'} ";
                }
                $cmd = $locerror.$env.$cmd;
            }
            $data->{$k}->{driver} = "cmd";
            $data->{$k}->{params}->{cmd} = $cmd;
            $data->{$k}->{name} = $k;
        }
        if (defined($v->{consoleondemand})) {
            # consoleondemand attribute for node can be "1", "yes", "0" and "no"
            if (($v->{consoleondemand} eq "1") || lc($v->{consoleondemand}) eq "yes") {
                $ondemand = \1;
            }
            elsif (($v->{consoleondemand} eq "0") || lc($v->{consoleondemand}) eq "no") {
                $ondemand = \0;
            }
        }
        $data->{$k}->{ondemand} = $ondemand;
    }
    if (@openbmc_nodes) {
        my $passwd_table = xCAT::Table->new('passwd');
        my $passwd_hash = $passwd_table->getAttribs({ 'key' => 'openbmc' }, qw(username password));
        $passwd_table->close();
        my $openbmc_table = xCAT::Table->new('openbmc');
        my $openbmc_hash = $openbmc_table->getNodesAttribs(\@openbmc_nodes, ['bmc','consport', 'username', 'password']);
        $openbmc_table->close();
        foreach my $node (@openbmc_nodes) {
            if (defined($openbmc_hash->{$node}->[0])) {
                if (!$openbmc_hash->{$node}->[0]->{'bmc'}) {
                    xCAT::SvrUtils::sendmsg("Error: Unable to get attribute bmc", $::callback, $node);
                    delete $data->{$node};
                    next;
                }
                $data->{$node}->{params}->{host} = $openbmc_hash->{$node}->[0]->{'bmc'};
                if ($openbmc_hash->{$node}->[0]->{'username'}) {
                    $data->{$node}->{params}->{user} = $openbmc_hash->{$node}->[0]->{'username'};
                } elsif ($passwd_hash and $passwd_hash->{username}) {
                    $data->{$node}->{params}->{user} = $passwd_hash->{username};
                } else {
                    xCAT::SvrUtils::sendmsg("Error: Unable to get attribute username", $::callback, $node);
                    delete $data->{$node};
                    next;
                }
                if ($openbmc_hash->{$node}->[0]->{'password'}) {
                    $data->{$node}->{params}->{password} = $openbmc_hash->{$node}->[0]->{'password'};
                } elsif ($passwd_hash and $passwd_hash->{password}) {
                    $data->{$node}->{params}->{password} = $passwd_hash->{password};
                } else {
                    xCAT::SvrUtils::sendmsg("Error: Unable to get attribute password", $::callback, $node);
                    delete $data->{$node};
                    next;
                }
                if ($openbmc_hash->{$node}->[0]->{'consport'}) {
                    $data->{$node}->{params}->{consport} = $openbmc_hash->{$node}->[0]->{'consport'};
                } else {
                    $data->{$node}->{params}->{port} = $bmc_cons_port;
                }
                $data->{$node}->{name} = $node;
                $data->{$node}->{driver} = "ssh";
            }
        }
    }
    return $data;
}

sub start_goconserver {
    my ($rsp, $running, $ready, $ret);
    unless (-x "/usr/bin/goconserver") {
        $rsp->{data}->[0] = "goconserver is not installed.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    # if goconserver is installed, check the status of conserver service.
    if (xCAT::Goconserver::is_conserver_running()) {
        $rsp->{data}->[0] = "conserver is started, please stop it at first.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
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
            $rsp->{data}->[0] = "Failed to create configuration file for goconserver.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;
        }
    }
    $ret = xCAT::Goconserver::restart_service();
    if ($ret) {
        $rsp->{data}->[0] = "Failed to start goconserver service.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    $rsp->{data}->[0] = "Starting goconserver service ...";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
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
    my ($delmode, $querymode);
    GetOptions('d|delete' => \$delmode,
        'q|query' => \$querymode,
    );

    my $svboot = 0;
    if (exists($req->{svboot})) {
        $svboot = 1;
    }
    my %iphash   = ();
    foreach (@$hostinfo) { $iphash{$_} = 1; }
    my %cons_map = get_cons_map($req, \%iphash);
    if (! %cons_map) {
        xCAT::SvrUtils::sendmsg([ 1, "Could not get any console request entry" ], $::callback);
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
            xCAT::SvrUtils::sendmsg([ 1, "Unexpected value $site_entry for consoleondemand attribute in site table" ], $::callback);
        }
    }
    my (@nodes);
    my $data = gen_request_data(\%cons_map, $siteondemand);
    if (! $data) {
        xCAT::SvrUtils::sendmsg([ 1, "Could not generate the request data" ], $::callback);
        return 1;
    }
    $ret = xCAT::Goconserver::delete_nodes($api_url, $data, $delmode, $::callback);
    if ($delmode) {
        return $ret;
    }
    $ret = xCAT::Goconserver::create_nodes($api_url, $data, $::callback);
    if ($ret != 0) {
        xCAT::SvrUtils::sendmsg([ 1, "Failed to create console entry in goconserver. "], $::callback);
        return $ret;
    }
    return 0;
}

1;