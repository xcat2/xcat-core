# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCconn;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;

##############################################
# Globals
##############################################
my %method = (
    mkconn => \&mkconn_parse_args,
    lsconn => \&lsconn_parse_args,
    rmconn => \&rmconn_parse_args
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
# Parse arguments for mkconn
##########################################################################
sub mkconn_parse_args
{
    my $request = shift;
    my $args    = shift;
    my %opt = ();

    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage("mkconn");
        return( [ $_[0], $usage_string] );
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return(usage( "No command specified" ));
    }

    local @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose t p=s P=s) )) {
        return( usage() );
    }

    if ( exists $opt{t} and exists $opt{p})
    {
        return( usage('Flags -t and -p cannot be used together.'));
    }

    if ( exists $opt{P} and ! exists $opt{p})
    {
        return( usage('Flags -P can only be used when flag -p is specified.'));
    }

    ##########################################
    # Check if CECs are controlled by a frame
    ##########################################
    my $nodes = $request->{node};
    my $ppctab  = xCAT::Table->new( 'ppc' );
    my $nodetypetab = xCAT::Table->new( 'nodetype');
    my @bpa_ctrled_nodes = ();
    my @no_type_nodes    = ();
    if ( $ppctab)
    {
        for my $node ( @$nodes)
        {
            my $node_parent = undef;
            my $nodetype    = undef;
            my $nodetype_hash    = $nodetypetab->getNodeAttribs( $node,[qw(nodetype)]);
            my $node_parent_hash = $ppctab->getNodeAttribs( $node,[qw(parent)]);
            $nodetype    = $nodetype_hash->{nodetype};
            $node_parent = $node_parent_hash->{parent};
            if ( !$nodetype)
            {
                push @no_type_nodes, $node;
                next;
            }
            
            if ( $nodetype eq 'fsp' and 
                $node_parent and 
                $node_parent ne $node)
            {
                push @bpa_ctrled_nodes, $node;
            }
        }
    }
    if (scalar(@no_type_nodes))
    {
        my $tmp_nodelist = join ',', @no_type_nodes;
        return ( usage("Attribute nodetype.nodetype cannot be found for node(s) $tmp_nodelist"));
    }
    if (scalar(@bpa_ctrled_nodes))
    {
        my $tmp_nodelist = join ',', @bpa_ctrled_nodes;
        return ( usage("Node(s) $tmp_nodelist is(are) controlled by BPA."));
    }
    
    $request->{method} = 'mkconn';
    return( \%opt);
}

##########################################################################
# Parse arguments for lsconn
##########################################################################
sub lsconn_parse_args
{
    my $request = shift;
    my $args    = shift;
    my %opt = ();

    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage("lsconn");
        return( [ $_[0], $usage_string] );
    };
#############################################
# Get options in command line
#############################################
    local @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose) )) {
        return( usage() );
    }

    #############################################
    # Process command-line arguments
    #############################################
    if ( scalar @$args) {
        return(usage( "No additional flag is support by this command" ));
    }
    $request->{method} = 'lsconn';
    return( \%opt);
}

##########################################################################
# Parse arguments for rmconn
##########################################################################
sub rmconn_parse_args
{
    my $request = shift;
    my $args    = shift;
    my %opt = ();

    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage("rmconn");
        return( [ $_[0], $usage_string] );
    };
#############################################
# Get options in command line
#############################################
    local @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose) )) {
        return( usage() );
    }

    #############################################
    # Process command-line arguments
    #############################################
    if ( scalar @$args) {
        return(usage( "No additional flag is support by this command" ));
    }
    $request->{method} = 'rmconn';
    return( \%opt);
}
##########################################################################
# Create connection for CECs/BPAs
##########################################################################
sub mkconn
{
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @value   = ();
    my $Rc      = undef;

    for my $cec_bpa ( keys %$hash)
    {
        my $node_hash = $hash->{$cec_bpa};
        my ($node_name) = keys %$node_hash;
        my $d = $node_hash->{$node_name};

        ############################
        # Get IP address
        ############################
        my $hosttab  = xCAT::Table->new( 'hosts' );
        my $node_ip = undef;
        if ( $hosttab)
        {
            my $node_ip_hash = $hosttab->getNodeAttribs( $node_name,[qw(ip)]);
            $node_ip = $node_ip_hash->{ip};
        }
        if (!$node_ip)
        {
            my $ip_tmp_res  = xCAT::Utils::toIP($node_name);
            ($Rc, $node_ip) = @$ip_tmp_res;
            if ( $Rc ) 
            {
                push @value, [$node_name, $node_ip, $Rc];
                next;
            }
        }

        
        my ( undef,undef,undef,undef,$type) = @$d;
        my ($user, $passwd) = xCAT::PPCdb::credentials( $node_name, $type);

        my $res = xCAT::PPCcli::mksysconn( $exp, $node_ip, $type, $passwd);
        $Rc = shift @$res;
        push @value, [$node_name, @$res[0], $Rc];
    }
    return \@value;
}
##########################################################################
# List connection status for CECs/BPAs
##########################################################################
sub lsconn
{
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @value   = ();
    my $Rc      = undef;

    my $res = xCAT::PPCcli::lssysconn( $exp);
    $Rc = shift @$res;
    for my $cec_bpa ( keys %$hash)
    {
        my $node_hash = $hash->{$cec_bpa};
        my ($node_name) = keys %$node_hash;
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
        # Search node in result
        ############################
        my $d = $node_hash->{$node_name};
        my ( undef,undef,undef,undef,$type) = @$d;
        if ( $type eq 'bpa')
        {
            $type='frame';
        }
        elsif ( $type eq 'fsp')
        {
            $type='sys';
        }
        else
        {
            push @value, [$node_name, 'Unsupported node type', 1];
            next;
        }
        
        if ( my @res_matched = grep /\Qtype_model_serial_num=$cec_bpa,\E/, @$res)
        {
            for my $r ( @res_matched)
            {
                $r =~ s/\Qtype_model_serial_num=$cec_bpa,\E//;
                $r =~ s/\Qresource_type=$type,\E//;
                $r =~ s/sp=.*?,//;
                $r =~ s/sp_phys_loc=.*?,//;
                push @value, [$node_name, $r, $Rc];
            }
        }
        else
        {
            push @value, [$node_name, 'Connection not found', 1];
        }
    }
    return \@value;
}

##########################################################################
# Remove connection for CECs/BPAs to HMCs
##########################################################################
sub rmconn
{
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @value   = ();
    my $Rc      = undef;

    for my $cec_bpa ( keys %$hash)
    {
        my $node_hash = $hash->{$cec_bpa};
        my ($node_name) = keys %$node_hash;
        my $d = $node_hash->{$node_name};

        my ( undef,undef,undef,undef,$type) = @$d;

        my $res = xCAT::PPCcli::mksysconn( $exp, $type, $cec_bpa);
        $Rc = shift @$res;
        push @value, [$node_name, @$res[0], $Rc];
    }
    return \@value;
}
1;
