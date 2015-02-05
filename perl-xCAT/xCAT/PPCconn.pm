# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCconn;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::NetworkUtils;
use xCAT::DBobjUtils;
use xCAT::FSPUtils;
use xCAT::MsgUtils qw(verbose_message);
##############################################
# Globals
##############################################
my %method = (
    mkhwconn => \&mkhwconn_parse_args,
    lshwconn => \&lshwconn_parse_args,
    rmhwconn => \&rmhwconn_parse_args,
    inithwpw => \&inithwpw_parse_args
);
##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my $cmd = $request->{command};
    ###############################
    # Invoke correct parse_args
    ###############################

    my $result = $method{$cmd}( $request, $request->{arg});
    return( $result );
}

##########################################################################
# Parse arguments for mkhwconn
##########################################################################
sub mkhwconn_parse_args
{
    my $request = shift;
    my $args    = shift;
    my %opt = ();

    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage("mkhwconn");
        return( [ $_[0], $usage_string] );
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return(usage( "No command specified" ));
    }

    local @ARGV = ref($args) eq 'ARRAY'? @$args:();
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose h|help t  p=s P=s  port=s  s:s) )) {
        return( usage() );
    }
    return usage() if ( exists $opt{h});

    if ( !exists $opt{t} and !exists $opt{p} and !exists $opt{s}) {
        return ( usage('Flag -t or -p or -s must be used.'));
    }

    if (( exists $opt{t} and exists $opt{p}) or (exists $opt{s} and exists $opt{p}) or (exists $opt{t} and exists $opt{p}))
    {
        return( usage('Flags -t and -p cannot be used together.'));
    }

    if ( exists $opt{P} and (!exists $opt{p} and !exists $opt{s}))
    {
        return( usage('Flags -P can only be used when flag -p is specified.'));
    }

    ##########################################
    # Find the sfp for the mkhwconn -s
    ##########################################
    $request->{sfp} = $opt{s};
    ##########################################
    # Check if CECs are controlled by a frame
    ##########################################
    my $nodes = $request->{node};
    my $ppctab  = xCAT::Table->new( 'ppc' );
    #my $nodetypetab = xCAT::Table->new( 'nodetype');
    my $vpdtab = xCAT::Table->new( 'vpd');
    my @bpa_ctrled_nodes = ();
    my @no_type_nodes    = ();
    my @frame_members    = ();
    if ( $ppctab)
    {
        for my $node ( @$nodes)
        {
            my $node_parent = undef;
            my $nodetype    = undef;
            #my $nodetype_hash    = $nodetypetab->getNodeAttribs( $node,[qw(nodetype)]);
            my $node_parent_hash = $ppctab->getNodeAttribs( $node,[qw(parent)]);
            #$nodetype    = $nodetype_hash->{nodetype};
            $nodetype = xCAT::DBobjUtils->getnodetype($node,"ppc");
            $node_parent = $node_parent_hash->{parent};
            if ( !$nodetype )
            {
                push @no_type_nodes, $node;
                next;
            } else
            {
                unless ( $nodetype =~ /^(blade|fsp|bpa|frame|cec|hmc)$/)
                {
                     return ( usage("Node type is incorrect. \n"));
                }
            }

            if ( $nodetype eq 'fsp' )
            {
                my $jr = xCAT::DBobjUtils::judge_node($node, $nodetype);
                unless ($jr)
                {
                    if ($node_parent and $node_parent ne $node )
                    {
                        push @bpa_ctrled_nodes, $node;
                    }
                }
            }

            ##########################################
            # Nothing to do with cec
            ##########################################
            #if (($nodetype eq 'cec') and
            #    $node_parent and
            #    $node_parent ne $node)
            #{
            #    push @bpa_ctrled_nodes, $node;
            #}
            ##########################################
            # Now we suppport the operation on sigal bpa
            ##########################################
            if ( $nodetype eq 'bpa')
            {
                my $jr = xCAT::DBobjUtils::judge_node($node, $nodetype);
                unless($jr)
                {
                    my $my_frame_bpa_cec = getFrameMembers( $node, $vpdtab, $ppctab);
                    push @frame_members, @$my_frame_bpa_cec;
                }
            }
            ##########################################
            # For the Frame, we will have its CEC to do
            # mkhwconn at the same time
            ##########################################
            if ( $nodetype eq 'frame')
            {
                my $my_frame_bpa_cec =  xCAT::DBobjUtils::getcecchildren( $node)                                                                             ;
                push @frame_members, @$my_frame_bpa_cec if($my_frame_bpa_cec);
                push @frame_members, $node;
            }
        }
    }

    if (scalar(@no_type_nodes))
    {
        my $tmp_nodelist = join ',', @no_type_nodes;
        return ( usage("Attribute nodetype.nodetype cannot be found for node(s) $tmp_nodelist. Please define first and try again."));
    }

    if (scalar(@bpa_ctrled_nodes))
    {
        my $tmp_nodelist = join ',', @bpa_ctrled_nodes;
        return ( usage("Node(s) $tmp_nodelist is(are) controlled by BPA."));
    }

    if ( scalar( @frame_members))
    {
        my @all_nodes = xCAT::Utils::get_unique_members( @$nodes, @frame_members);
        $request->{node} = \@all_nodes;
    }
    # Set HW type to 'hmc' anyway, so that this command will not going to
    # PPCfsp.pm
    $request->{ 'hwtype'} = 'hmc';
    $request->{hcp} = 'hmc';
    if( ! exists $opt{port} )
    {
        $opt{port} = "0";
    }
    if( $opt{port} ne "0" and $opt{port} ne "1")
    {
        return( usage('Wrong value of  --port option. The value can be 0 or 1, and the default value is 0.'));
    }
    $request->{method} = 'mkhwconn';
    
    if ( scalar( @ARGV)) {
        return(usage( "No additional flag is support by this command" ));
    }

    return( \%opt);
}

####################################################
# Get frame members
####################################################
#ppc/vpd nodes cache
my @all_ppc_nodes;
my @all_vpd_nodes;
sub getFrameMembers
{
    my $node = shift; #this a BPA node
    my $vpdtab = shift;
    my $ppctab = shift;
    my @frame_members = ();
    my @bpa_nodes     = ();
    my $vpdhash = $vpdtab->getNodeAttribs( $node, [qw(mtm serial)]);
    my $mtm = $vpdhash->{mtm};
    my $serial = $vpdhash->{serial};
    if ( scalar( @all_vpd_nodes) == 0)
    {
        @all_vpd_nodes = $vpdtab->getAllNodeAttribs( ['node', 'mtm', 'serial']);
    }
    for my $vpd_node (@all_vpd_nodes)
    {
        if ( $vpd_node->{'mtm'} eq $mtm and $vpd_node->{'serial'} eq $serial)
        {
            push @frame_members, $vpd_node->{'node'};
            push @bpa_nodes, $vpd_node->{'node'};
        }
    }

    if ( scalar( @all_ppc_nodes) == 0)
    {
        @all_ppc_nodes = $ppctab->getAllNodeAttribs( ['node', 'parent']);
    }
    for my $bpa_node (@bpa_nodes)
    {
        for my $ppc_node (@all_ppc_nodes)
        {
            if ( $ppc_node->{parent} eq $bpa_node)
            {
                push @frame_members, $ppc_node->{'node'};
            }
        }
    }
    return \@frame_members;
}

##########################################################################
# Parse arguments for lshwconn
##########################################################################
sub lshwconn_parse_args
{
    my $request = shift;
    my $args    = shift;
    my %opt = ();

    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage("lshwconn");
        return( [ $_[0], $usage_string] );
    };
#############################################
# Get options in command line
#############################################
    local @ARGV = ref($args) eq 'ARRAY'? @$args:();
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose h|help s) )) {
        return( usage() );
    }
    return usage() if ( exists $opt{h});

    #############################################
    # Process command-line arguments
    #############################################
    if ( scalar( @ARGV)) {
        unless( $opt{s}) {
        return(usage( "No additional flag is support by this command" ));
      }
    }
    #my $nodetypetab = xCAT::Table->new('nodetype');
    #if (! $nodetypetab)
    #{
    #    return( ["Failed to open table 'nodetype'.\n"]);
    #}
    my $nodehmtab = xCAT::Table->new('nodehm');
    if (! $nodehmtab)
    {
        return( ["Failed to open table 'nodehm'.\n"]);
    }

    my $nodetype;
    my @no_type_nodes = ();
    my @no_mgt_nodes = ();
    my @error_type_nodes = ();
    for my $node ( @{$request->{node}})
    {
        #my $ent = $nodetypetab->getNodeAttribs( $node, [qw(nodetype)]);
        my $ttype = xCAT::DBobjUtils->getnodetype($node);
        my $nodehm = $nodehmtab->getNodeAttribs( $node, [qw(mgt)]);
        if ( ! $ttype)
        {
            push @no_type_nodes, $node;
            next;
        }
        if ( ! $nodehm)
        {
            push @no_mgt_nodes, $node;
            next;
        }
        elsif ( $nodehm->{mgt} ne 'hmc')
        {
            return( ["lshwconn can only support HMC nodes, or nodes managed by HMC, i.e. nodehm.mgt should be 'hmc'. Please make sure node $node has correect nodehm.mgt and ppc.hcp value.\n"]);
        }
        if ( $ttype ne 'hmc'
                and $ttype ne 'fsp' and $ttype ne 'cec'
                and $ttype ne 'bpa' and $ttype ne 'frame')
        {
            push @error_type_nodes, $node;
            next;
        }
        if ( ! $nodetype)
        {
            $nodetype = $ttype;
        }
        else
        {
            if ( $nodetype ne $ttype)
            {
                return( ["Cannot support multiple node types in this command line.\n"]);
            }
        }
    }
    if (scalar(@no_type_nodes)) {
        my $tmp_nodelist = join ',', @no_type_nodes;
        return( ["Failed to get node type for node(s) $tmp_nodelist. Please define first and try again\n"]);
    }
    if (scalar(@no_mgt_nodes)) {
        my $tmp_nodelist = join ',', @no_mgt_nodes;
            return( ["Failed to get nodehm.mgt value for node(s) $tmp_nodelist. Please define first and try again.\n"]);
    }
    if (scalar(@error_type_nodes)) {
        my $tmp_nodelist = join ',', @error_type_nodes;
        my $link = (scalar(@error_type_nodes) eq '1')? 'is':'are';
        return( ["Node type of node(s) $tmp_nodelist $link not supported for this command.\n"]);
    }
    $request->{nodetype} = $nodetype;

    $request->{method} = 'lshwconn';
    return( \%opt);
}

##########################################################################
# Parse arguments for rmhwconn
##########################################################################
sub rmhwconn_parse_args
{
    my $request = shift;
    my $args    = shift;
    my %opt = ();

    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage("rmhwconn");
        return( [ $_[0], $usage_string] );
    };
    #############################################
    # Get options in command line
    #############################################
    local @ARGV = ref($args) eq 'ARRAY'? @$args:();
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose h|help s) )) {
        return( usage() );
    }
    return usage() if ( exists $opt{h});

    #############################################
    # Process command-line arguments
    #############################################
    if ( scalar (@ARGV)) {
        unless( $opt{s}) {
        return(usage( "No additional flag is support by this command" ));
        }
    }
    ##########################################
    # Check if CECs are controlled by a frame
    ##########################################
    my $nodes = $request->{node};
    my $ppctab  = xCAT::Table->new( 'ppc' );
    return( ["Failed to open table 'ppc'.\n"]) if ( ! $ppctab);
    my $vpdtab = xCAT::Table->new( 'vpd');
    return( ["Failed to open table 'vpd'.\n"]) if ( ! $vpdtab);
    my @bpa_ctrled_nodes = ();
    my @no_type_nodes    = ();
    my @frame_members    = ();
    for my $node ( @$nodes)
    {
        my $node_parent = undef;
        my $node_parent_hash = $ppctab->getNodeAttribs( $node,[qw(parent)]);
        $node_parent = $node_parent_hash->{parent};
        my $newtype = xCAT::DBobjUtils::getnodetype($node);
        unless ($newtype) {
            push @no_type_nodes, $node;
            next;
        }

        if ($newtype =~ /^(fsp|bpa)$/ )
        {
            ##########################################
            # We should judge if the node is defined in xCAT 2.5
            # If it is, it should really be a cec or frame
            # If not, we will do nothing to it,
            # which means we support remove a sigal connection
            ##########################################
            my $jr = xCAT::DBobjUtils::judge_node($node, $newtype);
            #$jr is defined by the xCAT2.5

            unless ($jr)
            {
                if ( ($newtype eq 'fsp') and $node_parent and $node_parent ne $node)
                {
                    push @bpa_ctrled_nodes, $node;
                }

                if ( $newtype eq 'bpa')
                {
                    my $my_frame_bpa_cec = getFrameMembers( $node, $vpdtab, $ppctab);
                    push @frame_members, @$my_frame_bpa_cec;
                }
            }
        }
        if (( $newtype eq 'cec') and  $node_parent and  $node_parent ne $node)
        {
            #push @bpa_ctrled_nodes, $node;
        }

        if ( $newtype eq 'frame')
        {
            my $my_frame_bpa_cec = xCAT::DBobjUtils::getcecchildren($node);
            push @frame_members, @$my_frame_bpa_cec;
            push @frame_members, $node;
        }
    }

    if (scalar(@no_type_nodes))
    {
        my $tmp_nodelist = join ',', @no_type_nodes;
        return ( usage("Attribute nodetype.nodetype cannot be found for node(s) $tmp_nodelist. Please define first and try again.\n"));
    }

    if (scalar(@bpa_ctrled_nodes))
    {
        my $tmp_nodelist = join ',', @bpa_ctrled_nodes;
        return ( usage("Node(s) $tmp_nodelist is(are) controlled by BPA."));
    }

    if ( scalar( @frame_members))
    {
        my @all_nodes = xCAT::Utils::get_unique_members( @$nodes, @frame_members);
        $request->{node} = \@all_nodes;
    }
    $request->{method} = 'rmhwconn';
    return( \%opt);
}
##########################################################################
# Create connection for CECs/BPAs
##########################################################################
sub mkhwconn
{
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @value   = ();
    my $Rc      = undef;

    xCAT::MsgUtils->verbose_message($request, "mkhwconn START."); 
    for my $cec_bpa ( keys %$hash)
    {
        my $node_hash = $hash->{$cec_bpa};
        for my $node_name ( keys %$node_hash)
        {
            my $d = $node_hash->{$node_name};

            ############################
            # Get IP address
            ############################
            my $cnode;
            #my $ntype = xCAT::DBobjUtils::getnodetype($node_name);
            my $ntype = $$d[4];
            if ($ntype =~ /^(cec|frame|blade)$/)
            {
                if ($ntype eq "blade") {
                    delete $opt->{port};
                }
                $cnode = xCAT::DBobjUtils::getchildren($node_name, $opt->{port});
            } else {
                $cnode = $node_name;
            }

            my @newnodes = ();
            if ( $cnode =~ /ARRAY/ )
            {
                foreach (@$cnode) {
                    push @newnodes, $_;
                }
            } else {
                push @newnodes,$cnode;
            }
            xCAT::MsgUtils->verbose_message($request, "mkhwconn :mksysconn for node:$node_name."); 
            for my $nn ( @newnodes )
            {
                my $node_ip;
                unless ( xCAT::NetworkUtils->isIpaddr($nn) ) {
                    $node_ip = xCAT::NetworkUtils::getNodeIPaddress( $nn );
                } else {
                    $node_ip = $nn;
                }
                unless($node_ip)
                {
                    push @value, [$node_name, "Cannot get IP address. Please check table 'hosts' or name resolution", 1];
                    next;
                }

                my ( undef,undef,$mtms,undef,$type,$bpa) = @$d;
                my ($user, $passwd);
                if ( exists $opt->{P})
                {
                    ($user, $passwd) = ('HMC', $opt->{P});
                }
                elsif ($type eq "blade") {
                    $user = "USERID";
                    ($user, $passwd) = xCAT::PPCdb::credentials( $bpa, $type, $user);
                    $type = "cec";
                }
                else
                {
                    ($user, $passwd) = xCAT::PPCdb::credentials( $node_name, $type,'HMC');
                    if ( !$passwd)
                    {
                        push @value, [$node_name, "Cannot get password of userid 'HMC'. Please check table 'passwd' or 'ppcdirect'.",1];
                        next;
                    }

                }
                my $res = xCAT::PPCcli::mksysconn( $exp, $node_ip, $type, $passwd);
                $Rc = shift @$res;
                push @value, [$node_name, @$res[0], $Rc];
                if ( !$Rc and !(exists $opt->{s}))
                {
                    sethmcmgt( $node_name, $exp->[3]);
                }
            }

#            if ( exists $opt->{N} )
#            {
#                my $newpwd = $opt->{N};
#                my $Res = xCAT::PPCcli::chsyspwd( $exp, "access", $type, $mtms, $passwd, $newpwd );
#                $Rc = shift @$Res;
#                push @value, [$node_name, @$Res[0], $Rc];
#            }
        }
    }
    xCAT::MsgUtils->verbose_message($request, "mkhwconn END."); 
    return \@value;
}
##########################################################################
# List connection status for CECs/BPAs
##########################################################################
sub lshwconn
{
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @value   = ();
    my $Rc      = undef;


    my $hosttab  = xCAT::Table->new( 'hosts' );
    my $res = xCAT::PPCcli::lssysconn( $exp, "all" );
    $Rc = shift @$res;
    if ( $request->{nodetype} eq 'hmc')
    {
        if ( $Rc)
        {
            push @value, [$exp->[3], $res->[0], $Rc];
            return \@value;
        }
        my $vpdtab = xCAT::Table->new('vpd');
        my @vpdentries = $vpdtab->getAllAttribs(qw(node serial mtm));
        my %node_vpd_hash;
        for my $vpdent ( @vpdentries)
        {
            if ( $vpdent->{node} and $vpdent->{serial} and $vpdent->{mtm})
            {
                $node_vpd_hash{"$vpdent->{mtm}*$vpdent->{serial}"} = $vpdent->{node};
            }
        }
        my %node_ppc_hash;
        my $ppctab =  xCAT::Table->new('ppc');
        for my $node ( values %node_vpd_hash)
        {
            my $node_parent_hash = $ppctab->getNodeAttribs( $node, [qw(parent)]);
            $node_ppc_hash{$node} = $node_parent_hash->{parent};
        }

        for my $r ( @$res)
        {
            $r =~ s/type_model_serial_num=([^,]*),//;
            my $mtms = $1;
            $r =~ s/resource_type=([^,]*),//;
            $r =~ s/sp=.*?,//;
            $r =~ s/sp_phys_loc=.*?,//;
            my $node_name;
            if ( exists $node_vpd_hash{$mtms})
            {
                $node_name = $node_vpd_hash{$mtms};
                $r = "hcp=$exp->[3],parent=$node_ppc_hash{$node_name}," . $r;
            }
            else
            {
                $node_name = $mtms;
                $r = "hcp=$exp->[3],parent=," . $r;
            }
            push @value, [ $node_name, $r, $Rc];
        }
    }
    else
    {
        for my $cec_bpa ( keys %$hash)
        {
            my $node_hash = $hash->{$cec_bpa};
            for my $node_name (keys %$node_hash)
            {
                ############################################
                # If lssysconn failed, put error into all
                # nodes' return values
                ############################################
                if ( $Rc ) 
                {
                    push @value, [$node_name, @$res[0], $Rc];
                    next;
                }

                ############################
                # Get IP address
                ############################
                my $node_ip = undef;
                if ( $hosttab)
                {
                    #my $node_ip_hash = $hosttab->getNodeAttribs( $node_name,[qw(ip)]);
                    #$node_ip = $node_ip_hash->{ip};
                    #$node_ip = xCAT::NetworkUtils::getNodeIPaddress( $node_name );
		    my $d = $node_hash->{$node_name};
                    $node_ip = xCAT::FSPUtils::getIPaddress($request, $$d[4], $node_name );
                }
                if (!$node_ip || ($node_ip == -3))
                {
                    push @value, [$node_name, "Failed to get IP address.", $Rc];
                    next;
                }

                my @nodes_ip = split(/,/, $node_ip);
                for my $ip  (@nodes_ip)
                {
                    if ( my @res_matched = grep /\Qipaddr=$ip,\E/, @$res)
                    {
                        for my $r ( @res_matched)
                        {
                            $r =~ s/\Qtype_model_serial_num=$cec_bpa,\E//;
                            #$r =~ s/\Qresource_type=$type,\E//;
                            $r =~ s/sp=.*?,//;
                            $r =~ s/sp_phys_loc=.*?,//;
                            my $new_name = $node_name."(".$ip. ")";
                            push @value, [$new_name, $r, $Rc];
                        }
                    }
                    else
                    {
                        my $new_name = $node_name."(".$ip. ")";
                        push @value, [$new_name, 'Connection not found', 1];
                    }
                }
            }
        }
    }
    return \@value;
}

##########################################################################
# Remove connection for CECs/BPAs to HMCs
##########################################################################
sub rmhwconn
{
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @value   = ();
    my $Rc      = undef;

    my $nodes_found = xCAT::PPCcli::lssysconn ($exp, "all");
    if ( @$nodes_found[0] eq SUCCESS ) {
        $Rc = shift(@$nodes_found);
    } else { 
        return undef;
    }    
    for my $cec_bpa ( keys %$hash)
    {
        my $node_hash = $hash->{$cec_bpa};
        for my $node_name (keys %$node_hash)
        {
            my $d = $node_hash->{$node_name};

            my ( undef,undef,undef,undef,$type) = @$d;
            if ($type eq "blade") {$type = "cec";}
            ############################
            # Get IP address
            ############################
            #get node ip from hmc
            #my $node_ip = xCAT::PPCcli::getHMCcontrolIP($node_name, $exp);
            my $tab = xCAT::Table->new("vpd");
            my $ent;
            if ($tab) {
               $ent = $tab->getNodeAttribs($node_name, ['serial', 'mtm']);	
            }
            my $serial = $ent->{'serial'};
            my $mtm  = $ent->{'mtm'};
            my $node_ip;

            my @ips;
            foreach my $entry ( @$nodes_found ) {
                if ($entry =~ /type_model_serial_num=([^,]*),/) {
                    my $match_mtm1 = $1;
                    my $match_mtm2 = $match_mtm1;
                    $match_mtm2 =~ s/\-//;
                    if ($match_mtm1 =~ /$mtm\*$serial/ || $match_mtm2 =~ /$mtm\*$serial/) {
                        $entry =~ /ipaddr=(\d+\.\d+\.\d+\.\d+),/;
                        push @ips, $1;
                    }
                }
            #if ( $entry =~ /$mtm\*$serial/)   {
            #    $entry =~ /ipaddr=(\d+\.\d+\.\d+\.\d+),/;
            #    push @ips, $1;
            #}
            } 
            if (!@ips)
            {
                push @value, [$node_name, $node_ip, $Rc];
                next;
            }
            for my $nn ( @ips )
            {
                my $res = xCAT::PPCcli::rmsysconn( $exp, $type, $nn);
                $Rc = shift @$res;
                push @value, [$node_name, @$res[0], $Rc];
                if ( !$Rc and !$opt->{s})
                {
                    rmhmcmgt( $node_name, $type);
                }
            }
        }
    }
    return \@value;
}

#################################################################
# set node mgt to hmc, and hcp to the hmc node name
#################################################################
sub sethmcmgt
{
    my $node = shift;
    my $hcp  = shift;

    my $nodehm_tab = xCAT::Table->new('nodehm', -create=>1);
    my $ppc_tab = xCAT::Table->new('ppc', -create=>1);    
    my @nodes;
    push @nodes, $node;
    my $ntype = xCAT::DBobjUtils->getnodetype($node);
    if ( $ntype =~ /^(cec|frame)$/ )  {
        my $cnodep = xCAT::DBobjUtils->getchildren($node);
        if ($cnodep) {
            push @nodes, @$cnodep;
        }    
    }            
    for my $n (@nodes) {
        my $ent = $nodehm_tab->getNodeAttribs( $n, ['mgt']);
        if ( !$ent or $ent->{mgt} ne 'hmc') {
            $nodehm_tab->setNodeAttribs( $n, { mgt=>'hmc'});
        }
        my $ent = $ppc_tab->getNodeAttribs( $n, ['hcp']);
        if ( !$ent or $ent->{hcp} ne $hcp) {
            $ppc_tab->setNodeAttribs( $n, { hcp=>$hcp});
        }        
    }
}
#################################################################
# set node as the standalone fsp/bpa node
#################################################################
sub rmhmcmgt
{
    my $node = shift;
    my $hwtype = shift;

    my $nodehm_tab = xCAT::Table->new('nodehm', -create=>1);
    my $ppc_tab = xCAT::Table->new('ppc', -create=>1);
    my @nodes;
    push @nodes, $node;
    my $ntype = xCAT::DBobjUtils->getnodetype($node);
    if ( $ntype =~ /^(cec|frame)$/ )  {
        my $cnodep = xCAT::DBobjUtils->getchildren($node);
        if ($cnodep) {
            push @nodes, @$cnodep;
        }    
    }
    for my $n (@nodes) {
        my $ent = $nodehm_tab->getNodeAttribs( $n, ['mgt']);
        if ( !$ent or $ent->{mgt} ne $hwtype) {
            if ($hwtype eq "cec" || $hwtype eq "frame") {
                $nodehm_tab->setNodeAttribs( $n, { mgt=>"fsp"});
            } else {    
                $nodehm_tab->setNodeAttribs( $n, { mgt=>$hwtype});
            }    
        }
        my $ent = $ppc_tab->getNodeAttribs( $n, ['hcp']);
        if ( !$ent or $ent->{hcp} ne $n) {
            $ppc_tab->setNodeAttribs( $n, { hcp=>$n});
        }
    }    
}

1;
