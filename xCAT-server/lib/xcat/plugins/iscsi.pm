package xCAT_plugin::iscsi;
use strict;
use xCAT::Table;
use xCAT::TableUtils;
use Socket;
use File::Path;
use File::Basename;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");


sub handled_commands {
    return {
        "setupiscsidev" => "iscsi",
    };
}

sub get_tid {

    #generate a unique tid given a node for tgtadm to use
    my $node = shift;
    my $tid = unpack("N", inet_aton($node));
    $tid = $tid & ((2**31) - 1);
    return $tid;
}

sub preprocess_request {
    my $request  = shift;
    my $callback = shift;
    my @requests = ();
    my %iscsiserverhash;
    if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
    my $iscsitab = xCAT::Table->new('iscsi');
    foreach my $node (@{ $request->{node} }) {
        my $tent = $iscsitab->getNodeAttribs($node, ['server']);
        if ($tent and $tent->{server}) {
            $iscsiserverhash{ $tent->{server} }->{$node} = 1;
        } else {
            $callback->({ error => ["No iscsi.server for $node, aborting request"] });
            return [];
        }
    }
    foreach my $iscsis (keys %iscsiserverhash) {
        my $reqcopy = {%$request};
        $reqcopy->{'_xcatdest'} = $iscsis;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        $reqcopy->{node} = [ keys %{ $iscsiserverhash{$iscsis} } ];
        push @requests, $reqcopy;
    }
    return \@requests;
}

sub process_request {
    my $request  = shift;
    my $callback = shift;
    unless (-x "/usr/sbin/tgtadm") {
        $callback->({ error => "/usr/sbin/tgtadm does not exist, iSCSI plugin currently requires it, please install scsi-target-utils package under CentOS, RHEL, or Fedora.  SLES support is not yet implemented", errorcode => [1] });
        return;
    }
    my $lunsize = 4096;
    if ($request->{arg}) {
        @ARGV = @{ $request->{arg} };
        GetOptions(
            "size|s=i" => \$lunsize,
        );
    }
    my $iscsitab = xCAT::Table->new('iscsi');
    my @nodes    = @{ $request->{node} };

    my $nd          = xCAT::NetworkUtils->getNodeDomains(\@nodes);
    my %nodedomains = %{$nd};

    my $iscsiprefix;
    my @entries = xCAT::TableUtils->get_site_attribute("iscsidir");
    my $t_entry = $entries[0];
    if (defined($t_entry)) {
        $iscsiprefix = $t_entry;
    }
    foreach my $node (@nodes) {
        my $fileloc;
        my %rsp;
        %rsp = (name => [$node]);
        my $iscsient = $iscsitab->getNodeAttribs($node, ['file']);
        if ($iscsient and $iscsient->{file}) {
            $fileloc = $iscsient->{file};
            unless ($fileloc =~ /^\//) {
                unless ($iscsiprefix) {
                    $rsp{error} = ["$node: Unable to identify file to back iSCSI LUN, no iscsidir in site table and iscsi.file entry for node is a relative path"];
                    $rsp{errorcode} = [1];
                    $callback->({ node => [ \%rsp ] });
                    %rsp = (name => [$node]);
                    next;
                }
                $fileloc = $iscsiprefix . "/" . $iscsient->{file};
            }
        } else {
            unless ($iscsiprefix) {
                $rsp{error} = ["$node: Unable to identify file to back iSCSI LUN, no iscsidir in site table nor iscsi.file entry for node  (define at least either)"];
                $rsp{errorcode} = [1];
                $callback->({ node => [ \%rsp ] });
                %rsp = (name => [$node]);
                next;
            }
            $fileloc = "$iscsiprefix/$node";
            $iscsitab->setNodeAttribs($node, { file => $fileloc });
        }
        unless (-d dirname($fileloc)) {
            mkpath dirname($fileloc);
        }
        unless (-f $fileloc) {
            $rsp{name} = [$node];
            $rsp{data} = ["Creating $fileloc ($lunsize MB)"];
            $callback->({ node => [ \%rsp ] });
            %rsp = (name => [$node]);
            $lunsize -= 1;
            my $rc = system("dd if=/dev/zero of=$fileloc bs=1M count=1 seek=$lunsize");
            $lunsize += 1;
            if ($rc) {
                $rsp{error}     = ["dd process exited with return code $rc"];
                $rsp{errorcode} = [1];
                $callback->({ node => [ \%rsp ] });
                %rsp = (name => [$node]);
                next;
            }
        }
        my $targname;
        my $lun;
        $iscsient = $iscsitab->getNodeAttribs($node, [ 'target', 'lun' ]);
        if ($iscsient and $iscsient->{target}) {
            $targname = $iscsient->{target};
        }
        if ($iscsient and defined($iscsient->{lun})) {
            $lun = $iscsient->{lun};
        } else {
            $lun = '1';
            $iscsitab->setNodeAttribs($node, { lun => $lun });
        }
        unless ($targname) {
            my @date   = localtime;
            my $year   = 1900 + $date[5];
            my $month  = $date[4];
            my $domain = $nodedomains{$node};
            $targname = "iqn.$year-$month.$domain:$node";
            $iscsitab->setNodeAttribs($node, { target => $targname });
        }
        system("tgtadm --lld iscsi --mode target --op delete --tid " . get_tid($node) . " -T $targname");
        my $rc = system("tgtadm --lld iscsi --mode target --op new --tid " . get_tid($node) . " -T $targname");
        if ($rc) {
            $rsp{error} = [ "tgtadm --lld iscsi --mode target --op new --tid " . get_tid($node) . " -T $targname returned $rc" ];
            if ($rc == 27392) {
                push @{ $rsp{error} }, "This likely indicates the need to do /etc/init.d/tgtd start";
            }
            $rsp{errorcode} = [1];
            $callback->({ node => [ \%rsp ] });
            %rsp = (name => [$node]);
            next;
        }
        $rc = system("tgtadm --lld iscsi --mode logicalunit --op new --tid " . get_tid($node) . " --lun 1 --backing-store $fileloc --device-type disk");
        if ($rc) {
            $rsp{error} = [ "tgtadm --lld iscsi mode logicalunit --op new --tid " . get_tid($node) . " --lun 1 --backing-store $fileloc returned $rc" ];
            $rsp{errorcode} = [1];
            $callback->({ node => [ \%rsp ] });
            %rsp = (name => [$node]);
            next;
        }
        $rc = system("tgtadm --lld iscsi --mode target --op bind --tid " . get_tid($node) . " -I " . inet_ntoa(inet_aton($node)));
        if ($rc) {
            $rsp{error} = [ "tgtadm --lld iscsi --mode target --op bind --tid " . get_tid($node) . " -I " . inet_ntoa(inet_aton($node)) . " returned $rc" ];
            $rsp{errorcode} = [1];
            $callback->({ node => [ \%rsp ] });
            %rsp = (name => [$node]);
        } else {
            $rsp{data} = ["iSCSI LUN configured"];
            $callback->({ node => [ \%rsp ] });
            %rsp = (name => [$node]);
        }
    }
}

1;
