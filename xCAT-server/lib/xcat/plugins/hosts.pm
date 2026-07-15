# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::hosts;
use strict;
use warnings;
use xCAT::Table;
use xCAT::TableUtils;
use xCAT::Utils;
use xCAT::NetworkUtils;
require xCAT::MsgUtils;
use Data::Dumper;
use File::Copy;
use Getopt::Long;
use Fcntl ':flock';

my @hosts;    #Hold /etc/hosts data to be written back
my %host_indexes_by_ip;
my %host_indexes_by_node;
my $LONGNAME;
my $OTHERNAMESFIRST;
my $ADDNAMES;
my $MACTOLINKLOCAL;


#############   TODO - add return code checking !!!!!


sub handled_commands
{
    return { makehosts => "hosts", };
}

sub _host_line_index_values
{
    my $line = shift;
    return unless defined($line);

    my ($ip) = $line =~ /^(\S+)\s/;
    return unless defined($ip);

    my @nodes;
    if ($ip =~ /^\d+\.\d+\.\d+\.\d+$/)
    {
        my ($primary_name) = $line =~ /^\S+\s+(\S+)/;
        if (defined($primary_name))
        {
            # Preserve matching a short node against an FQDN-first entry.
            my $offset = 0;
            while ((my $dot = index($primary_name, '.', $offset)) >= 0)
            {
                push @nodes, substr($primary_name, 0, $dot);
                $offset = $dot + 1;
            }
            push @nodes, $primary_name;
        }
    }

    return ($ip, \@nodes);
}

sub _index_host_line
{
    my $idx = shift;
    my ($ip, $nodes) = _host_line_index_values($hosts[$idx]);
    return unless defined($ip);

    $host_indexes_by_ip{$ip}{$idx} = 1;
    foreach my $node (@{$nodes})
    {
        $host_indexes_by_node{$node}{$idx} = 1;
    }
}

sub _unindex_host_line
{
    my $idx = shift;
    my ($ip, $nodes) = _host_line_index_values($hosts[$idx]);
    return unless defined($ip);

    if (exists($host_indexes_by_ip{$ip}))
    {
        delete $host_indexes_by_ip{$ip}{$idx};
        delete $host_indexes_by_ip{$ip} unless keys %{ $host_indexes_by_ip{$ip} };
    }
    foreach my $node (@{$nodes})
    {
        if (exists($host_indexes_by_node{$node}))
        {
            delete $host_indexes_by_node{$node}{$idx};
            delete $host_indexes_by_node{$node} unless keys %{ $host_indexes_by_node{$node} };
        }
    }
}

sub _rebuild_host_indexes
{
    %host_indexes_by_ip   = ();
    %host_indexes_by_node = ();
    foreach my $idx (0 .. $#hosts)
    {
        _index_host_line($idx);
    }
}

sub _set_host_lines
{
    my $lines = shift;
    @hosts = @{$lines};
    _rebuild_host_indexes();
    return \@hosts;
}

sub _set_host_line
{
    my ($idx, $line) = @_;
    _unindex_host_line($idx);
    $hosts[$idx] = $line;
    _index_host_line($idx);
}

sub _push_host_line
{
    my $line = shift;
    push @hosts, $line;
    _index_host_line($#hosts);
}

sub _matching_host_indexes
{
    my ($node, $ip) = @_;
    my %matches;

    if (exists($host_indexes_by_ip{$ip}))
    {
        $matches{$_} = 1 foreach keys %{ $host_indexes_by_ip{$ip} };
    }
    if (exists($host_indexes_by_node{$node}))
    {
        $matches{$_} = 1 foreach keys %{ $host_indexes_by_node{$node} };
    }

    my @indexes = sort { $a <=> $b } keys %matches;
    return @indexes;
}

sub delnode
{
    my $node = shift;
    my $ip   = shift;

    unless ($node and $ip)
    {
        return;
    }    #bail if requested to do something that could zap /etc/hosts badly

    my $othernames = shift;
    my $domain     = shift;

    foreach my $idx (_matching_host_indexes($node, $ip))
    {
        _set_host_line($idx, "");
    }
}

sub addnode
{
    my $callback = shift;
    my $node     = shift;
    my $ip       = shift;

    unless ($node and $ip)
    {
        return;
    }    #bail if requested to do something that could zap /etc/hosts badly

    my $othernames = shift;
    my $domain     = shift;
    my $nics       = shift;

    # if this ip was already added then just update the entry
    my @matches = _matching_host_indexes($node, $ip);
    if (@matches)
    {
        my $idx = shift @matches;
        my $line;
        if ($nics)
        {
            # we're processing the nics table and we found an
            #   existing entry for this ip so just add this
            # node name as an alias for the existing entry
            my $existing_line = $hosts[$idx];
            chomp($existing_line);
            my ($hip, $hnode, $hdom, $hother) = split(/ /, $existing_line);

            $line = build_line($callback, $ip, $hnode, $domain, $othernames);
        }
        else
        {
            # otherwise just try to completely update the existing entry
            $line = build_line($callback, $ip, $node, $domain, $othernames);
        }
        _set_host_line($idx, $line);
        foreach my $duplicate_idx (@matches)
        {
            _set_host_line($duplicate_idx, "");
        }
        return;
    }

    my $line = build_line($callback, $ip, $node, $domain, $othernames);
    if ($line) {
        _push_host_line($line);
    }
}

sub build_line
{
    my $callback   = shift;
    my $ip         = shift;
    my $node       = shift;
    my $domain     = shift;
    my $othernames = shift;
    my @o_names    = ();
    my @n_names    = ();

    if (defined $othernames)
    {
        # Trim spaces from the beginning and end from $othernames
        $othernames =~ s/^\s+|\s+$//g;

        # the "hostnames" attribute can be a list delimited by
        #  either a comma or a space
        @o_names = split(/,| /, $othernames);
    }
    my $longname;
    foreach (@o_names)
    {
        if (($_ eq $node) || ($domain && ($_ eq "$node.$domain")))
        {
            $longname = "$node.$domain";
            $_        = "";
        }
        elsif ($_ =~ /\./)
        {
            if (!$longname)
            {
                $longname = $_;
                $_        = "";
            }
        }
        elsif ($ADDNAMES)
        {
            unshift(@n_names, "$_.$domain");
        }
    }
    unshift(@o_names, @n_names);

    my $shortname = $node;

    if ($node =~ m/\.$domain$/i)
    {
        $longname = $node;
        ($shortname = $node) =~ s/\.$domain$//;
    }
    elsif ($domain && !$longname)
    {
        $shortname = $node;
        $longname  = "$node.$domain";
    }

    # if shortname contains a dot then we have a bad syntax for name
    if ($shortname =~ /\./) {
        my $rsp;
        push @{ $rsp->{data} }, "Invalid short node name \'$shortname\'. The short node name may not contain a dot. The short node name is considered to be anything preceeding the network domain name in the fully qualified node name \'$longname\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    $othernames = join(' ', @o_names);
    if ($LONGNAME) { return "$ip $longname $shortname $othernames\n"; }
    elsif ($OTHERNAMESFIRST) { return "$ip $othernames $longname $shortname\n"; }
    else { return "$ip $shortname $longname $othernames\n"; }
}

sub addotherinterfaces
{
    my $callback        = shift;
    my $node            = shift;
    my $otherinterfaces = shift;
    my $domain          = shift;

    my @itf_pairs = split(/,/, $otherinterfaces);
    foreach (@itf_pairs)
    {
        my ($itf, $ip);
        if ($_ =~ /!/) {
            ($itf, $ip) = split(/!/, $_);
        } else {
            ($itf, $ip) = split(/:/, $_);
        }
        if ($ip && xCAT::NetworkUtils->isIpaddr($ip))
        {
            if ($itf =~ /^-/)
            {
                $itf = $node . $itf;
            }

            #lookup the domain for the ip address
            #if failed, use the domain passed in
            my ($mydomain,$mynet)=getIPdomain($ip);
            if($mydomain){
               $domain=$mydomain;
            }
            addnode $callback, $itf, $ip, '', $domain;
        }
    }
}

sub delotherinterfaces
{
    my $node            = shift;
    my $otherinterfaces = shift;
    my $domain          = shift;

    my @itf_pairs = split(/,/, $otherinterfaces);
    foreach (@itf_pairs)
    {
        my ($itf, $ip);
        if ($_ =~ /!/) {
            ($itf, $ip) = split(/!/, $_);
        } else {
            ($itf, $ip) = split(/:/, $_);
        }
        if ($ip && xCAT::NetworkUtils->isIpaddr($ip))
        {
            if ($itf =~ /^-/)
            {
                $itf = $node . $itf;
            }
            delnode $itf, $ip, '', $domain;
        }
    }
}


##!!!!!!!!!!!!!!!!!!!
# NOTE FOR CHANGING #
# This subroutine is called in ddns.pm, please take care the calling in ddns.pm
# for your changes, especially the change upon the subroutine interface
##!!!!!!!!!!!!!!!!!!!
sub add_hosts_content {
    my %args     = @_;
    my $nodelist = $args{nodelist};
    my $callback = $args{callback};
    my $DELNODE  = $args{delnode};
    my $domain   = $args{domain};
    my $hoststab = xCAT::Table->new('hosts', -create => 0);
    my $hostscache;
    if ($hoststab) {
        $hostscache = $hoststab->getNodesAttribs($nodelist,
            [qw(ip node hostnames otherinterfaces)]);
    }
    foreach (@{$nodelist}) {
        my $ref      = $hostscache->{$_}->[0];
        my $nodename = $_;
        my $ip       = $ref->{ip};
        if (not $ip) {
            $ip = xCAT::NetworkUtils->getipaddr($nodename);    #attempt lookup
        }

        my $netn;
        ($domain, $netn) = &getIPdomain($ip, $callback);
        if (!$domain) {
            if ($::sitedomain) {
                $domain = $::sitedomain;
            } elsif ($::XCATSITEVALS{domain}) {
                $domain = $::XCATSITEVALS{domain};
            } else {
                my $rsp;
                push @{ $rsp->{data} }, "No domain can be determined for node \'$nodename\'. The domain of the xCAT node must be provided in an xCAT network definition or the xCAT site definition.\n";

                xCAT::MsgUtils->message("W", $rsp, $callback);
                next;
            }
        }

        if ($DELNODE)
        {
            delnode $nodename, $ip, $ref->{hostnames}, $domain;
            if (defined($ref->{otherinterfaces}))
            {
                delotherinterfaces $nodename, $ref->{otherinterfaces}, $domain;
            }
        }
        else
        {
            if (xCAT::NetworkUtils->isIpaddr($ip))
            {
                addnode $callback, $nodename, $ip, $ref->{hostnames}, $domain;
            }
            else
            {
                my $rsp;
                if (!$ip)
                {
                    push @{ $rsp->{data} }, "Ignoring node \'$nodename\', it can not be resolved.";
                }
                else
                {
                    push @{ $rsp->{data} }, "Ignoring node \'$nodename\', its ip address \'$ip\' is not valid.";
                }
                xCAT::MsgUtils->message("W", $rsp, $callback);
            }

            if (defined($ref->{otherinterfaces}))
            {
                addotherinterfaces $callback, $nodename, $ref->{otherinterfaces}, $domain;
            }
        }
    }    #end foreach
    if ($args{hostsref}) {
        @{ $args{hostsref} } = @hosts;
    }
}

sub process_request
{
    Getopt::Long::Configure("bundling");
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("no_pass_through");

    my $req       = shift;
    my $callback  = shift;
    my $dr        = shift;
    my %extraargs = @_;

    my $HELP;
    my $VERSION;
    my $REMOVE;
    my $DELNODE;

    my $usagemsg =
"Usage: makehosts <noderange> [-d] [-n] [-l] [-a] [-o] [-m]\n       makehosts -h\n       makehosts -v";

    # parse the options
    if   ($req && $req->{arg}) { @ARGV = @{ $req->{arg} }; }
    else                       { @ARGV = (); }

    # print "argv=@ARGV\n";
    if (
        !GetOptions(
            'h|help'                 => \$HELP,
            'n'                      => \$REMOVE,
            'd'                      => \$DELNODE,
            'o|othernamesfirst'      => \$OTHERNAMESFIRST,
            'a|adddomaintohostnames' => \$ADDNAMES,
            'm|mactolinklocal'       => \$MACTOLINKLOCAL,
            'l|longnamefirst'        => \$LONGNAME,
            'v|version'              => \$VERSION,
        )
      )
    {
        if ($callback)
        {
            my $rsp = {};
            $rsp->{data}->[0] = $usagemsg;
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {
            xCAT::MsgUtils->message("I", $usagemsg . "\n");
        }
        return;
    }

    # display the usage if -h
    if ($HELP)
    {
        if ($callback)
        {
            my $rsp = {};
            $rsp->{data}->[0] = $usagemsg;
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {
            xCAT::MsgUtils->message("I", $usagemsg . "\n");
        }
        return;
    }
    if ($VERSION)
    {
        my $version = xCAT::Utils->Version();
        if ($callback)
        {
            my $rsp = {};
            $rsp->{data}->[0] = $version;
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {
            xCAT::MsgUtils->message("I", $version . "\n");
        }
        return;
    }

    # get site FQDNfirst(Fully Qualified Domian Name)
    my @FQDNfirst = xCAT::TableUtils->get_site_attribute("FQDNfirst");
    if ((defined($FQDNfirst[0])) && ($FQDNfirst[0] =~ /^(1|yes|enable)$/i)) { $LONGNAME = "1"; }

    # get site domain for backward compatibility
    my @domain = xCAT::TableUtils->get_site_attribute("domain");
    if ($domain[0]) {
        $::sitedomain = $domain[0];
    }

    my $hoststab = xCAT::Table->new('hosts');
    my $domain;
    my $lockh;

    # lockfile to prevent concurrent executions
    open($lockh, ">", "/tmp/xcat/hostsfile.lock");
    flock($lockh, LOCK_EX);

    # save a backup copy
    my $bakname = "/etc/hosts.xcatbak";
    copy("/etc/hosts", $bakname);

    my @host_lines;
    if ($REMOVE)
    {
        # add the localhost entry if trying to create the /etc/hosts from scratch
        if ($^O =~ /^aix/i)
        {
            push @host_lines, "127.0.0.1 loopback localhost\n";
        }
        else
        {
            push @host_lines, "127.0.0.1 localhost\n";
        }
    }
    else
    {
        #  the contents of the /etc/hosts file is saved in the @hosts array
        #    the @hosts elements are updated and used to re-create the
        #    /etc/hosts file at the end by the writeout subroutine.
        my $rconf;
        open($rconf, "/etc/hosts");    # Read file into memory
        if ($rconf)
        {
            while (<$rconf>)
            {
                push @host_lines, $_;
            }
            close($rconf);
        }
    }
    _set_host_lines(\@host_lines);

    if ($req->{node})
    {
        if ($MACTOLINKLOCAL)
        {
            my $mactab = xCAT::Table->new("mac");
            my $machash = $mactab->getNodesAttribs($req->{node}, ['mac']);

            foreach my $node (keys %{$machash})
            {

                my $mac = $machash->{$node}->[0]->{mac};
                if (!$mac)
                {
                    next;
                }
                my $linklocal = xCAT::NetworkUtils->linklocaladdr($mac);

                my $netn;
                ($domain, $netn) = &getIPdomain($linklocal, $callback);

                if (!$domain) {
                    if ($::sitedomain) {
                        $domain = $::sitedomain;
                    } elsif ($::XCATSITEVALS{domain}) {
                        $domain = $::XCATSITEVALS{domain};
                    } else {
                        my $rsp;
                        push @{ $rsp->{data} }, "No domain can be determined for node \'$node\'.  The domain of the xCAT node must be provided in an xCAT network definition or the xCAT site definition.\n";
                        xCAT::MsgUtils->message("W", $rsp, $callback);
                        next;
                    }
                }

                if ($DELNODE)
                {
                    delnode $node, $linklocal, $node, $domain;
                }
                else
                {
                    addnode $callback, $node, $linklocal, $node, $domain;
                }
            }
        }
        else
        {
            add_hosts_content(nodelist => $req->{node}, callback => $callback, delnode => $DELNODE, domain => $domain);
        }    # end else

        # do the other node nics - if any
        &donics(nodes => $req->{node}, callback => $callback, delnode => $DELNODE);
    }
    else
    {
        if ($DELNODE)
        {
            return;
        }
        my @hostents =
          $hoststab->getAllNodeAttribs(
            [ 'ip', 'node', 'hostnames', 'otherinterfaces' ]);

        my @allnodes;
        foreach (@hostents)
        {

            push @allnodes, $_->{node};

            my $netn;
            ($domain, $netn) = &getIPdomain($_->{ip});
            if (!$domain) {
                $domain = $::sitedomain;
            }
            if (!$domain) {
                $domain = $::XCATSITEVALS{domain};
            }

            if (xCAT::NetworkUtils->isIpaddr($_->{ip}))
            {
                addnode $callback, $_->{node}, $_->{ip}, $_->{hostnames}, $domain;
            }
            else
            {
                my $rsp;
                push @{ $rsp->{data} }, "Invalid IP Addr \'$_->{ip}\' for node \'$_->{node}\'.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }

            if (defined($_->{otherinterfaces}))
            {
                addotherinterfaces $callback, $_->{node}, $_->{otherinterfaces}, $domain;
            }
        }

        # also do nics table
        &donics(nodes => \@allnodes, callback => $callback, delnode => $DELNODE);
    }

    writeout();

    if ($lockh)
    {
        flock($lockh, LOCK_UN);
    }
}

sub writeout
{
    my $targ;
    open($targ, '>', "/etc/hosts");
    foreach (@hosts)
    {
        print $targ $_;
    }
    close($targ);
}

#-------------------------------------------------------------------------------

=head3    donics

           Add the additional network interfaces for a list of nodes as
           indicated in the nics table

        Arguments:
           node name
        Returns:
            0 - ok
            1 - error

        Globals:

        Example:
                my $rc = &donics(nodes=>\@allnodes, callback=>$callback, delnode=>$DELNODE);

        Comments:
                none
=cut

#-------------------------------------------------------------------------------

##!!!!!!!!!!!!!!!!!!!
# NOTE FOR CHANGING #
# This subroutine is called in ddns.pm, please take care the calling in ddns.pm
# for your changes, especially the change upon the subroutine interface
##!!!!!!!!!!!!!!!!!!!
sub donics
{
    my %args     = @_;
    my $nodes    = $args{nodes};
    my $callback = $args{callback};
    my $delnode  = $args{delnode};

    my @nodelist = @{$nodes};

    my $nicstab = xCAT::Table->new('nics');
    my $nettab  = xCAT::Table->new('networks');

    foreach my $node (@nodelist)
    {
        my $nich;
        my %nicindex;

        # get the nic info
        my $et =
          $nicstab->getNodeAttribs(
            $node,
            [
                'nicips', 'nichostnamesuffixes',
                'nichostnameprefixes',
                'nicnetworks', 'nicaliases'
            ]
          );

        # only require IP for nic
        if (!($et->{nicips})) {
            next;
        }

        # gather nics info
        # delimiter could be ":" or "!"
        # new  $et->{nicips} looks like
        # "eth0!11.10.1.1,eth1!60.0.0.5|60.0.0.250..."
        my @nicandiplist = split(',', $et->{'nicips'});

        foreach (@nicandiplist)
        {
            my ($nicname, $nicip);

            # if it contains a "!" then split on "!"
            if ($_ =~ /!/) {
                ($nicname, $nicip) = split('!', $_);
            } else {
                ($nicname, $nicip) = split(':', $_);
            }

            $nicindex{$nicname} = 0;

            if (!$nicip) {
                next;
            }
            #Only support format for nicips is :<nic1>!<ip1>|<ip2>|... or <nic1>!<one regular expression>
            if ($nicip =~ /^\|\S*\|$/) {
                $nicip = xCAT::Table::transRegexAttrs($node, $nicip);
            }
            if ($nicip =~ /\|/) {
                my @ips = split(/\|/, $nicip);
                foreach my $ip (@ips) {
                    $nich->{$nicname}->{nicip}->[ $nicindex{$nicname} ] = $ip;
                    $nicindex{$nicname}++;
                }
            } else {
                $nich->{$nicname}->{nicip}->[ $nicindex{$nicname} ] = $nicip;
                $nicindex{$nicname}++;
            }
        }

        my @nicandsufx = split(',', $et->{'nichostnamesuffixes'});
        my @nicandprfx = split(',', $et->{'nichostnameprefixes'});

        foreach (@nicandsufx)
        {
            my ($nicname, $nicsufx);
            if ($_ =~ /!/) {
                ($nicname, $nicsufx) = split('!', $_);
            } else {
                ($nicname, $nicsufx) = split(':', $_);
            }

            if ($nicsufx =~ /\|/) {
                my @sufs = split(/\|/, $nicsufx);
                my $index = 0;
                foreach my $suf (@sufs) {
                    $nich->{$nicname}->{nicsufx}->[$index] = $suf;
                    $index++;
                }
            } else {
                $nich->{$nicname}->{nicsufx}->[0] = $nicsufx;
            }
        }
        foreach (@nicandprfx)
        {
            my ($nicname, $nicprfx);
            if ($_ =~ /!/) {
                ($nicname, $nicprfx) = split('!', $_);
            } else {
                ($nicname, $nicprfx) = split(':', $_);
            }

            if (defined($nicprfx) && $nicprfx =~ /\|/) {
                my @prfs = split(/\|/, $nicprfx);
                my $index = 0;
                foreach my $prf (@prfs) {
                    $nich->{$nicname}->{nicprfx}->[$index] = $prf;
                    $index++;
                }
            } else {
                $nich->{$nicname}->{nicprfx}->[0] = $nicprfx;
            }
        }

        # see if we need to fill in a default suffix
        # nich has all the valid nics - ie. that have IPs provided!
        foreach my $nic (keys %{$nich}) {
            unless (defined($nicindex{$nic})) {
                $nicindex{$nic} = 0;
            }
            for (my $i = 0 ; $i < $nicindex{$nic} ; $i++) {
                if (!$nich->{$nic}->{nicsufx}->[$i] && !$nich->{$nic}->{nicprfx}->[$i]) {

                    if ($nic =~ /\./) {
                         my $rsp;
                         push @{ $rsp->{data} }, "$node: since \'$nic\' contains dot, nics.nichostnamesuffixes.$nic should be configured without dot for \'$nic\' interface.";
                         xCAT::MsgUtils->message("E", $rsp, $callback);
                         next;
                    }
                    # then we have no suffix at all for this
                    # so set a default
                    $nich->{$nic}->{nicsufx}->[$i] = "-$nic";

                } elsif ($nich->{$nic}->{nicsufx}->[$i] && $nich->{$nic}->{nicsufx}->[$i] =~ /\./) {
                    my $rsp;
                    push @{ $rsp->{data} }, "$node: the value \'$nich->{$nic}->{nicsufx}->[$i]\' of nics.nichostnamesuffixes.$nic should not contain dot.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    delete $nich->{$nic}->{nicsufx}->[$i];
                    next;
                } elsif ($nich->{$nic}->{nicprfx}->[$i] && $nich->{$nic}->{nicprfx}->[$i] =~ /\./) {
                    my $rsp;
                    push @{ $rsp->{data} }, "$node: the value \'$nich->{$nic}->{nicprfx}->[$i]\' of nics.nichostnameprefixes.$nic should not contain dot.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    delete $nich->{$nic}->{nicprfx}->[$i];
                    next;
                }
            }
        }

        my @nicandnetwrk = split(',', $et->{'nicnetworks'});
        foreach (@nicandnetwrk)
        {
            my ($nicname, $netwrk);
            if ($_ =~ /!/) {
                ($nicname, $netwrk) = split('!', $_);
            } else {
                ($nicname, $netwrk) = split(':', $_);
            }

            if (!$netwrk) {
                next;
            }

            if ($netwrk =~ /\|/) {
                my @nets = split(/\|/, $netwrk);
                my $index = 0;
                foreach my $net (@nets) {
                    $nich->{$nicname}->{netwrk}->[$index] = $net;
                    $index++;
                }
            } else {
                $nich->{$nicname}->{netwrk}->[0] = $netwrk;
            }
        }

        my @nicandnicalias;
        if (defined($et->{'nicaliases'})) {
            @nicandnicalias = split(',', $et->{'nicaliases'});
        }
        foreach (@nicandnicalias)
        {
            my ($nicname, $aliases);
            if ($_ =~ /!/) {
                ($nicname, $aliases) = split('!', $_);
            } else {
                ($nicname, $aliases) = split(':', $_);
            }
            if (!$aliases) {
                next;
            }

            # for example: nicaliases.ib0=|maestro-(\d+)$|m($1)-ib0|
            if ($aliases =~ /^\|\S*\|$/) {
                $aliases = xCAT::Table::transRegexAttrs($node, $aliases);
            }

            if ($aliases =~ /\|/) {
                my @names = split(/\|/, $aliases);
                my $index = 0;
                foreach my $alias (@names) {
                    $nich->{$nicname}->{nicaliases}->[$index] = $alias;
                    $index++;
                }
            } else {
                $nich->{$nicname}->{nicaliases}->[0] = $aliases;
            }
        }

        # end gather nics info

        # add or delete nic entries in the hosts file
        foreach my $nic (keys %{$nich}) {

            # make sure we have the short hostname
            my $shorthost;
            ($shorthost = $node) =~ s/\..*$//;
            for (my $i = 0 ; $i < $nicindex{$nic} ; $i++) {
                my $nicip       = "";
                my $nicsuffix   = "";
                my $nicprefix   = "";
                my $nicnetworks = "";
                my $nicaliases  = "";

                $nicip = $nich->{$nic}->{nicip}->[$i] if (defined($nich->{$nic}->{nicip}->[$i]));
                $nicsuffix = $nich->{$nic}->{nicsufx}->[$i] if (defined($nich->{$nic}->{nicsufx}->[$i]));
                $nicprefix = $nich->{$nic}->{nicprfx}->[$i] if (defined($nich->{$nic}->{nicprfx}->[$i]));
                $nicnetworks = $nich->{$nic}->{netwrk}->[$i] if (defined($nich->{$nic}->{netwrk}->[$i]));
                $nicaliases = $nich->{$nic}->{nicaliases}->[$i] if (defined($nich->{$nic}->{nicaliases}->[$i]));

                if (!$nicip) {
                    next;
                }

                # construct hostname for nic
                my $nichostname = "$nicprefix$shorthost$nicsuffix";

                # get domain from network def provided by nic attr
                my $nt = $nettab->getAttribs({ netname => "$nicnetworks" }, 'domain');

                # look up the domain as a check or if it's not provided
                my ($ndomain, $netn) = &getIPdomain($nicip, $callback);

                if ($nt->{domain} && $ndomain) {

                    # if they don't match we may have a problem.
                    if ($nicnetworks ne $netn) {
                        my $rsp;
                        push @{ $rsp->{data} }, "The xCAT network name listed for
\'$nichostname\' is \'$nicnetworks\' however the nic IP address \'$nicip\' seems to be in the \'$netn\' network.\nIf there is an error then makes corrections to the database definitions and re-run this command.\n";
                        xCAT::MsgUtils->message("W", $rsp, $callback);
                    }
                }

                # choose a domain
                my $nicdomain;
                if ($ndomain) {

                    # use the one based on the ip address
                    $nicdomain = $ndomain;
                } elsif ($nt->{domain}) {

                    # then try the one provided in the nics entry
                    $nicdomain = $nt->{domain};
                } elsif ($::sitedomain) {

                    # try the site domain for backward compatibility
                    $nicdomain = $::sitedomain;
                } elsif ($::XCATSITEVALS{domain}) {
                    $nicdomain = $::XCATSITEVALS{domain};
                } else {
                    my $rsp;
                    push @{ $rsp->{data} }, "No domain can be determined for the NIC IP value of \'$nicip\'. The network domains must be provided in an xCAT network definition or the xCAT site definition.\n";
                    xCAT::MsgUtils->message("W", $rsp, $callback);
                    next;
                }

                if ($delnode)
                {
                    delnode $nichostname, $nicip, '', $nicdomain;
                }
                else
                {
                    addnode $callback, $nichostname, $nicip, $nicaliases, $nicdomain, 1;
                }
            }    # end for each index
        }    # end for each nic
    }    # end for each node

    if ($args{hostsref}) {
        @{ $args{hostsref} } = @hosts;
    }

    $nettab->close;
    $nicstab->close;

    return 0;
}

#-------------------------------------------------------------------------------

=head3    getIPdomain

        Find the xCAT network definition match the IP and then return the
        domain value from that network def.

        Arguments:
           node IP
           callback
        Returns:
            domain and netname - ok
            undef - error

        Globals:

        Example:
                my $rc = &getIPdomain($nodeIP, $callback);

        Comments:
                none
=cut

#-------------------------------------------------------------------------------
sub getIPdomain
{
    my $nodeIP   = shift;
    my $callback = shift;

    # get the network defs
    my $nettab = xCAT::Table->new('networks');
    my @nets = $nettab->getAllAttribs('netname', 'net', 'mask', 'domain');

    # foreach network def
    foreach my $enet (@nets)
    {
        my $NM  = $enet->{'mask'};
        my $net = $enet->{'net'};
        if (xCAT::NetworkUtils->ishostinsubnet($nodeIP, $NM, $net))
        {
            return ($enet->{'domain'}, $enet->{'netname'});
            last;
        }
    }

    # could not find the network domain for this IP address
    return undef;
}

1;
