package xCAT::Scope;

use xCAT::Utils;
use xCAT::Table;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils qw(getSNList);


#-----------------------------------------------------------------------------

=head3 split_node_array

    Split a node array into multiple subsets in case to handle them in parallel.

    Arguments:
       Reference of source array
       Maximum subset number
       Default element capacity in each subset
    Returns: An array of all subsets
    Error:
        none
    Example:
        my $subsets = split_node_array(\@nodes, 5, 250);
=cut

#-----------------------------------------------------------------------------
sub split_node_array {
    my $source = shift;
    if ($source =~ /xCAT::Scope/) {
        $source = shift;
    }
    my $max_sub = shift;
    my $capacity = shift;

    if ($max_sub < 2) {return [$source];}
 
    my @dest = ();
    my $total = $#{$source} + 1;
    my $n_sub = int ($total / $capacity);
    unless ($n_sub * $capacity == $total) { $n_sub++;} #POSIX::ceil

    if ( $n_sub <= 1 ) {
        # Only 1 subset is enough
        $dest[0] = $source;

    } elsif ( $n_sub > $max_sub ) {
        # Exceed, then to recaculate the capacity of each subset as we only allow max_sub
        $capacity = int ($total / $max_sub);
        if ( $total % $max_sub > 0 ) {
            $capacity += 1;
        }
        my $start = $end = 0;
        for (1..$max_sub) {
            $end = $start + $capacity - 1;
            if ( $end > $total - 1 ) {
                $end = $total - 1
            }

            my @temp = @$source[$start..$end];
            $dest[$_-1]=\@temp;
            $start = $end + 1;
        }

    } else {
        # Only n_sub subsets are required, split the noderange into each subset
        my $start = $end = 0;
        for (1..$n_sub) {
            $end = $start + $capacity - 1;
            if ( $end > $total - 1 ) {
                $end = $total - 1
            }
            #print "subset #$_: $start to $end";
            my @temp = @$source[$start..$end];
            $dest[$_-1]=\@temp;
            $start = $end + 1;
        }
    }

    return \@dest;
}

#-----------------------------------------------------------------------------

=head3 get_parallel_scope

    Convert a request object to an array of multiple requests according to the 
    splitted node range.

    Arguments:
       Reference of request
       Maximum subset number: Optional, default is 5
       Default element capacity in each subset: Optional, default is 250
    Returns: An array of requests
    Error:
        none
    Example:
        my $reqs = xCAT::Scope->get_parallel_scope($request);
=cut

#-----------------------------------------------------------------------------
sub get_parallel_scope {
    my $req = shift;
    if ($req =~ /xCAT::Scope/) {
        $req = shift;
    }
    my ($max_sub, $capacity) = @_;
    #TODO, make the value configurable
    unless ($max_sub) { $max_sub = 5; }
    unless ($capacity) { $capacity = 250; }

    my $subsets = split_node_array(\@{$req->{node}}, $max_sub, $capacity);
    # Just return the origin one if node range is not big enough.
    if ($#{$subsets} < 1) { return [$req]; }

    my @requests = (); 
    foreach (@$subsets) {
        my $reqcopy = {%$req};
        $reqcopy->{node} = $_;
        push @requests, $reqcopy;
    }
    return \@requests;
}

#-----------------------------------------------------------------------------

=head3 get_broadcast_scope_with_parallel

    Convert a request object to an array of multiple requests according to the 
    splitted node range.

    Arguments:
       Reference of request
       SN list: Array of target service nodes
    Returns: An array of requests
    Error:
        none
    Example:
        my $reqs = xCAT::Scope->get_broadcast_scope_with_parallel($request, \@snlist);
=cut

#-----------------------------------------------------------------------------
sub get_broadcast_scope_with_parallel {
    my $req = shift;
    if ($req =~ /xCAT::Scope/) {
        $req = shift;
    }
    #Exit if the packet has been preprocessed in its history
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $snlist = shift;
    my @reqs = ();
    $req->{_xcatpreprocessed}->[0] = 1;
    my $isMN = xCAT::Utils->isMN();
    #Handle the one for current management/service node
    if ( $isMN ) {
        $reqs = get_parallel_scope($req);
    } else {
        # get site.master and broadcast to it as MN will not be in SN list or defined in noderes.servicenode.
        my @entries = xCAT::TableUtils->get_site_attribute("master");
        my $master = $entries[0];
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $master;
        $reqs = get_parallel_scope($reqcopy);
    }
    my @requests = @$reqs;

    #Broadcast the request to other management/service nodes
    foreach (@$snlist) {
        my $xcatdest = $_;
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $xcatdest;

        $reqs = get_parallel_scope($reqcopy);
        foreach (@$reqs) {
            push @requests, {%$_};
        }
    }
    return \@requests;
}

#-----------------------------------------------------------------------------

=head3 get_broadcast_disjoint_scope_with_parallel

    Convert a request object to an array of multiple requests according to the 
    splitted node range. (Work under disjoint mode)

    Arguments:
       Reference of request
       SN hash: Hash of target service nodes => Managed CNs
    Returns: An array of requests
    Error:
        none
    Example:
        my $reqs = xCAT::Scope->get_broadcast_disjoint_scope_with_parallel($request, \@snhash);
=cut

#-----------------------------------------------------------------------------
sub get_broadcast_disjoint_scope_with_parallel {
    my $req = shift;
    if ($req =~ /xCAT::Scope/) {
        $req = shift;
    }
    #Exit if the packet has been preprocessed in its history
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $sn_hash = shift;
    my @reqs = ();
    $req->{_xcatpreprocessed}->[0] = 1;
    my $isMN = xCAT::Utils->isMN();
    #Handle the one for current management/service node
    if ( $isMN ) {
        $reqs = get_parallel_scope($req);
    } else {
        # get site.master and broadcast to it as MN will not be in SN list or defined in noderes.servicenode.
        my @entries = xCAT::TableUtils->get_site_attribute("master");
        my $master = $entries[0];
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $master;
        $reqs = get_parallel_scope($reqcopy);
    }
    my @requests = @$reqs;

    my $handled4me = 0;
    #Broadcast the request to other management/service nodes
    foreach (keys %$sn_hash) {
        my $xcatdest = $_;
        if (xCAT::NetworkUtils->thishostisnot($xcatdest)) {
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $xcatdest;
            $reqcopy->{'node'} = $sn_hash->{$xcatdest};

            $reqs = get_parallel_scope($reqcopy);
            foreach (@$reqs) {
                push @requests, {%$_};
            }
        } elsif ($isMN == 0) {
            # avoid handle myself multiple times when different IP address used in `noderes.servicenode`.
            next if $handled4me;
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $xcatdest;
            $reqcopy->{'node'} = $sn_hash->{$xcatdest};

            $reqs = get_parallel_scope($reqcopy);
            foreach (@$reqs) {
                push @requests, {%$_};
            }
            $handled4me = 1;
        }
    }

    return \@requests;
}


sub get_broadcast_scope {
    my $req = shift;
    if ($req =~ /xCAT::Scope/) {
        $req = shift;
    }
    $callback = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    #Exit if the packet has been preprocessed in its history
    my @requests = ({%$req}); #Start with a straight copy to reflect local instance
    foreach (xCAT::ServiceNodeUtils->getSNList()) {
        if (xCAT::NetworkUtils->thishostisnot($_)) {
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $_;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;
        }
    }
    return \@requests;

    #my $sitetab = xCAT::Table->new('site');
    #(my $ent) = $sitetab->getAttribs({key=>'xcatservers'},'value');
    #$sitetab->close;
    #if ($ent and $ent->{value}) {
    #   foreach (split /,/,$ent->{value}) {
    #      if (xCAT::NetworkUtils->thishostisnot($_)) {
    #         my $reqcopy = {%$req};
    #         $reqcopy->{'_xcatdest'} = $_;
    #         push @requests,$reqcopy;
    #      }
    #   }
    #}
    #return \@requests;
}

1;
