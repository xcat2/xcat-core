# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPbootseq;
use Socket;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::NetworkUtils;
use xCAT::FSPUtils;
use xCAT::MsgUtils qw(verbose_message);

#use Data::Dumper;

##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my $node    = $request->{node};
    my $vers =
      my @VERSION = qw( 2.6 );
    my @dev = qw(hfi net);

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return ([ $_[0], $usage_string ]);
    };
    #############################################
    # Process command-line arguments
    #############################################
    if (!defined($args)) {
        return (usage("Missing command with rbootseq in DFM, net or hfi ?"));
    }

    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV                     = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("bundling");

    if (!GetOptions(\%opt, qw(h|help V|verbose v|version ))) {
        return (usage());
    }
    ####################################
    # Option -h for Help
    ####################################
    #if ( exists( $opt{h} )) {
    #    return( usage() );
    #}
    ####################################
    # Option -v for version
    ####################################
    if (exists($opt{v})) {
        return (\@VERSION);
    }
    ####################################
    # Check for "-" with no option
    ####################################
    #if ( grep(/^-$/, @ARGV )) {
    #    return(usage( "Missing option: -" ));
    #}

    ####################################
    # Check for an extra argument
    ####################################
    #if ( defined( $ARGV[0] )) {
    #    return(usage( "Invalid Argument: $ARGV[0]" ));
    #}

    my $command = grep(/^$ARGV[0]$/, @dev);
    if (!defined($command)) {
        return (usage("Invalid command: $ARGV[0]"));
    }

    if ($ARGV[0] =~ /^hfi$/) {
        $opt{hfi} = 1;
    } elsif ($ARGV[0] =~ /^net$/) {
        $opt{net} = 1;
    } else {
        return (usage("Invalid Argument: $ARGV[0]"));
    }

    shift @ARGV;
    if (defined($ARGV[0])) {
        return (usage("Invalid Argument: $ARGV[0]"));
    }


    #print "in parse_args:\n";
    #print $command;
    #print Dumper(\%opt);

    my $nodetype = xCAT::DBobjUtils->getnodetype($$node[0], "ppc");
    if ($nodetype =~ /^blade$/) {
        $request->{callback}->({ data => ["After running rebootseq on the nodes successfully, it's required to run <rpower noderange reset> to make the setting be permanent"] });
    }

    ####################################
    # Set method to invoke
    ####################################
    $request->{method} = $cmd;
    return (\%opt);
}


##########################################################################
# set hfi/eth boot string
##########################################################################
sub rbootseq {

    my $request = shift;
    my $d       = shift;
    my $opt     = $request->{opt};
    my @output;
    my $tooltype = 0;
    my $parameter;
    my $bootp_retries = 5;
    my $tftp_retries  = 5;
    my $blksize       = 512;
    my $hash;
    my $node_name = @$d[6];
    my $o         = @$d[7];

    #print "in setbootseq:\n";
    #print "request\n";
    #print Dumper($request);
    #print "d";
    #print Dumper($d);

    xCAT::MsgUtils->verbose_message($request, "rbootseq START for node:$node_name, type=$$d[4].");
    if (!($$d[4] =~ /^(lpar|blade)$/)) {
        push @output, [ $node_name, "\'boot\' command not supported for CEC or BPA", -1 ];
        return (\@output);
    }

    # add checking the power state of the cec
    xCAT::MsgUtils->verbose_message($request, "rbootseq check machine state for node:$node_name.");
    my $power_state = xCAT::FSPUtils::fsp_api_action($request, $node_name, $d, "cec_state", $tooltype);
    if (@$power_state[2] != 0) {
        push @output, [ $node_name, @$power_state[1], -1 ];
        return (\@output);
    }
    unless (@$power_state[1] and @$power_state[1] =~ /operating|standby/) {
        my $machine;
        my $state;
        if ($$d[4] eq 'blade') {
            $machine = "blade";
            $state   = "on";
        } else {
            $machine = "CEC";
            $state   = "power on";
        }

        push @output, [ $node_name, "\'boot\' command can only support while the $machine is in the \'$state\' state", -1 ];
        return (\@output);
    }
    if ($opt->{net}) {
        my $mactab = xCAT::Table->new('mac');
        unless ($mactab) {
            push @output, [ $node_name, "Cannot open mac table", -1 ];
            return (\@output);
        }

        my $mac_hash = $mactab->getNodeAttribs($node_name, [qw(mac)]);
        my $mac = $mac_hash->{mac};
        if (!defined($mac)) {
            push @output, [ $node_name, "No mac address in mac table", -1 ];
        }
        $mactab->close();

        if ($mac =~ /\| /) {

            #01:02:03:04:05:0E!node5|01:02:03:05:0F!node6-eth1
            my @mac_t = split(/\|/, $mac);
            my $m;
            my $m_t;
            foreach $m (@mac_t) {
                if (($m =~ /([\w:]{12})!$node_name/) || ($m =~ /([\w:]{17})!$node_name/)) {
                    $m_t = $1;
                    last;
                }

            }

            if (!defined($m_t)) {
                $mac = $mac_t[0];
            } else {
                $mac = $m_t;
            }
        }

        if ($mac =~ /\:/) {
            $mac =~ s/\://g;
        }

        if ($mac =~ /^(\w{12})$/) {

            $parameter = "mac=$mac:speed=auto,duplex=auto,$o->{server},,$o->{client},$o->{gateway},$bootp_retries,$tftp_retries,$o->{netmask},$blksize";
        } else {
            push @output, [ $node_name, "The mac address in mac table could NOT be used for rbootseq with -net. HFI mac , or other wrong format?", -1 ];
            return (\@output);
        }
        xCAT::MsgUtils->verbose_message($request, "rbootseq <$node_name> net=$parameter");
    }

    if ($opt->{hfi}) {

        $parameter = "/hfi-iohub/hfi-ethernet:$o->{server},,$o->{client},$o->{gateway},$bootp_retries,$tftp_retries,$o->{netmask},$blksize";

        xCAT::MsgUtils->verbose_message($request, "rbootseq <$node_name> hfi=$parameter");
    }

    xCAT::MsgUtils->verbose_message($request, "rbootseq set_lpar_bootstring for node:$node_name.");
    my $res = xCAT::FSPUtils::fsp_api_action($request, $node_name, $d, "set_lpar_bootstring", $tooltype, $parameter);

    #print "In boot, state\n";
    #print Dumper($res);
    my $Rc   = @$res[2];
    my $data = @$res[1];

    ##################################
    # Output error
    ##################################
    xCAT::MsgUtils->verbose_message($request, "rbootseq return:$Rc.");
    if ($Rc != SUCCESS) {
        push @output, [ $node_name, $data, $Rc ];
    } else {
        push @output, [ $node_name, "Success", 0 ];
    }

    return (\@output);


}

1;










