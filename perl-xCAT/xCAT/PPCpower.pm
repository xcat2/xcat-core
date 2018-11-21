# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCpower;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::MsgUtils;
use xCAT::FSPpower;

use xCAT::GlobalDef;

##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {
    my $request = shift;
    my $command = $request->{command};
    my $args    = $request->{arg};
    my %opt     = ();
    my @rpower = qw(on onstandby off softoff stat state reset boot of sms rackstandby exit_rackstandby lowpower resetsp cycle);

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($command);
        return ([ $_[0], $usage_string ]);
    };
    #############################################
    # Process command-line arguments
    #############################################
    if (!defined($args)) {
        return (usage("No command specified"));
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV                     = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("bundling");

    if (!GetOptions(\%opt, qw(V|verbose m:s@ t=s T=s r=s nodeps))) {
        return (usage());
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if (grep(/^-$/, @ARGV)) {
        return (usage("Missing option: -"));
    }
    ####################################
    # Unsupported commands
    ####################################
    my ($cmd) = grep(/^$ARGV[0]$/, @rpower);
    if (!defined($cmd)) {
        return (usage("Invalid command: $ARGV[0]"));
    }
    ####################################
    # Check for an extra argument
    ####################################
    shift @ARGV;
    if (defined($ARGV[0])) {
        return (usage("Invalid Argument: $ARGV[0]"));
    }
    ####################################
    # Change "stat" to "state"
    ####################################
    $request->{op} = $cmd;
    $cmd =~ s/^stat$/state/;

    ####################################
    # Power commands special case
    ####################################
    if ($cmd ne "state") {
        $cmd = ($cmd eq "boot") ? "powercmd_boot" : "powercmd";
    }
    $request->{method} = $cmd;

    if (exists($opt{m})) {
        my $res = xCAT::Utils->check_deployment_monitoring_settings($request, \%opt);
        if ($res != SUCCESS) {
            return (usage());
        }
    }

    if (!exists $opt{T})
    {
        $opt{T} = "lpar";    #defaut value is lpar.
    }

    if ($opt{T} eq "lpar") {
        $opt{T} = 0;
    } elsif ($opt{T} eq "fnm") {
        $opt{T} = 1;
        if ($request->{op} !~ /^(onstandby|state|stat)$/) {
            return (usage("The tooltype fnm only could be used with onstandby/state/stat action."));
        }
    } else {
        return (usage('Wrong value of  -T option. The value can be lpar or fnm. The defaut value is lpar.'));
    }


    return (\%opt);
}


##########################################################################
# Builds a hash of CEC/LPAR information returned from HMC/IVM
##########################################################################
sub enumerate {

    my $exp     = shift;
    my $node    = shift;
    my $mtms    = shift;
    my %outhash = ();
    my %cmds    = ();

    ######################################
    # Check for CEC/LPAR/BPAs in list
    ######################################
    while (my ($name, $d) = each(%$node)) {
        my $type = @$d[4];
        $cmds{$type} = ($type =~ /^lpar$/) ? "state,lpar_id" : "state";
    }
    foreach my $type (keys %cmds) {
        my $filter = $cmds{$type};
        my $values = xCAT::PPCcli::lssyscfg($exp, $type, $mtms, $filter);
        my $Rc     = shift(@$values);

        ##################################
        # Return error
        ##################################
        if ($Rc != SUCCESS) {
            return ([ $Rc, @$values[0] ]);
        }
        ##################################
        # Save LPARs by id
        ##################################
        foreach (@$values) {
            my ($state, $lparid) = split /,/;

            ##############################
            # No lparid for fsp/bpa
            ##############################
            if ($type =~ /^(fsp|bpa|cec|frame)$/) {
                $lparid = $type;
            }
            $outhash{$lparid} = $state;
        }
    }
    return ([ SUCCESS, \%outhash ]);
}


##########################################################################
# Performs boot operation (Off->On, On->Reset)
##########################################################################
sub powercmd_boot {

    my $request  = shift;
    my $hash     = shift;
    my $exp      = shift;
    my @output   = ();
    my $callback = $request->{'callback'};


    ######################################
    # Power commands are grouped by CEC
    # not Hardware Control Point
    ######################################

    ######################################
    # Get CEC MTMS
    ######################################
    my ($name) = keys %$hash;
    my $mtms = @{ $hash->{$name} }[2];

    ######################################
    # Build CEC/LPAR information hash
    ######################################
    my $stat = enumerate($exp, $hash, $mtms);
    my $Rc   = shift(@$stat);
    my $data = @$stat[0];

    my $newstat;
    my %newnodestatus = ();

    while (my ($name, $d) = each(%$hash)) {
        ##################################
        # Look up by lparid
        ##################################
        my $type = @$d[4];
        my $id = ($type =~ /^(fsp|bpa|frame|cec)$/) ? $type : @$d[0];

        ##################################
        # Output error
        ##################################
        if ($Rc != SUCCESS) {
            push @output, [ $name, $data, $Rc ];
            next;
        }

        ##################################
        # Node not found
        ##################################
        if (!exists($data->{$id})) {
            push @output, [ $name, "Node not found", 1 ];
            next;
        }
        ##################################
        # Convert state to on/off
        ##################################
        my $state = power_status($data->{$id});
        my $op = ($state =~ /^off$/) ? "on" : "reset";

        if ($state =~ /^off$/) {
            $newstat = $::STATUS_POWERING_ON;
        }

        # Attribute powerinterval in site table,
        # to control the rpower forking speed
        if ((defined($request->{op})) && ($request->{op} ne 'stat') && ($request->{op} ne 'status')
            && ($request->{op} ne 'state') && ($request->{op} ne 'off') && ($request->{op} ne 'softoff')) {
            if (defined($request->{'powerinterval'}) && ($request->{'powerinterval'} ne '')) {
                Time::HiRes::sleep($request->{'powerinterval'});
            }
        }
        ##############################
        # Send power command
        ##############################
        my $result = xCAT::PPCcli::chsysstate(
            $exp,
            $op,
            $d);
        unless (@$result[0] != SUCCESS) {
            if ($newstat) {
                push @{ $newnodestatus{$newstat} }, $name;
            }
        }
        push @output, [ $name, @$result[1], @$result[0] ];
    }
    if (defined($request->{opt}->{m})) {

        my $retries  = 0;
        my @monnodes = keys %$hash;
        my $monsettings = xCAT::Utils->generate_monsettings($request, \@monnodes);
        xCAT::Utils->monitor_installation($request, $monsettings);
        while ($retries++ < $monsettings->{'retrycount'} && scalar(keys %{ $monsettings->{nodes} }) > 0) {

            #The nodes that need to retry
            my @nodesretry = keys %{ $monsettings->{'nodes'} };
            my $nodes      = join ',', @nodesretry;
            my $rsp        = {};
            $rsp->{data}->[0] = "$nodes: Reinitializing the installation: $retries retry";
            xCAT::MsgUtils->message("I", $rsp, $callback);


            foreach my $node (keys %$hash)
            {
                # The installation for this node has been finished
                if (!grep(/^$node$/, @nodesretry)) {
                    delete($hash->{$node});
                }
            }
            while (my ($name, $d) = each(%$hash)) {
                my $type = @$d[4];
                my $id = ($type =~ /^(fsp|bpa)$/) ? $type : @$d[0];

                if ($Rc != SUCCESS) {
                    push @output, [ $name, $data, $Rc ];
                    next;
                }
                if (!exists($data->{$id})) {
                    push @output, [ $name, "Node not found", 1 ];
                    next;
                }
                my $state = power_status($data->{$id});
                my $op = ($state =~ /^off$/) ? "on" : "reset";

                my $result = xCAT::PPCcli::chsysstate(
                    $exp,
                    $op,
                    $d);
                push @output, [ $name, @$result[1], @$result[0] ];
            }
            my @monnodes = keys %{ $monsettings->{nodes} };
            xCAT::Utils->monitor_installation($request, $monsettings);
        }

        #failed after retries
        if (scalar(keys %{ $monsettings->{'nodes'} }) > 0) {
            foreach my $node (keys %{ $monsettings->{nodes} }) {
                my $rsp = {};
                $rsp->{data}->[0] = "The node \"$node\" can not reach the expected status after $monsettings->{'retrycount'} retries, the installation for this done failed";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
        }
    }

    require xCAT_monitoring::monitorctrl;
    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
    return (\@output);
}


##########################################################################
# Performs power control operations (on,off,reboot,etc)
##########################################################################
sub powercmd {

    my $request  = shift;
    my $hash     = shift;
    my $exp      = shift;
    my @result   = ();
    my $callback = $request->{'callback'};

    my ($name) = keys %$hash;
    my $mtms = @{ $hash->{$name} }[2];
    my $stat = enumerate($exp, $hash, $mtms);
    my $Rc   = shift(@$stat);
    my $data = @$stat[0];

    my $newstat;
    my %newnodestatus = ();

    ####################################
    # Power commands are grouped by CEC
    # not Hardware Control Point
    ####################################

    while (my ($name, $d) = each(%$hash)) {
        $newstat = "";

        # Attribute powerinterval in site table,
        # to control the rpower forking speed
        if ((defined($request->{op})) && ($request->{op} ne 'stat') && ($request->{op} ne 'status')
            && ($request->{op} ne 'state') && ($request->{op} ne 'off') && ($request->{op} ne 'softoff')) {
            if (defined($request->{'powerinterval'}) && ($request->{'powerinterval'} ne '')) {
                Time::HiRes::sleep($request->{'powerinterval'});
            }
        }
        if (($request->{op} eq 'off') || ($request->{op} ne 'softoff')) {
            $newstat = $::STATUS_POWERING_OFF;
        }
        if ($request->{op} eq 'on') {
            $newstat = $::STATUS_POWERING_ON;
        }

        if ($request->{op} eq 'reset') {
            my $type  = @$d[4];
            my $id    = ($type =~ /^(fsp|bpa|frame|cec)$/) ? $type : @$d[0];
            my $state = power_status($data->{$id});
            if ($state !~ /^off$/) {
                $newstat = $::STATUS_POWERING_ON;
            }
        }
        ################################
        # Send command to each LPAR
        ################################
        my $values = xCAT::PPCcli::chsysstate(
            $exp,
            $request->{op},
            $d);
        my $Rc = shift(@$values);

        unless ($Rc != SUCCESS) {
            if ($newstat) {
                push @{ $newnodestatus{$newstat} }, $name;
            }
        }

        ################################
        # Return result
        ################################
        push @result, [ $name, @$values[0], $Rc ];
    }

    if (defined($request->{opt}->{m})) {

        my $retries  = 0;
        my @monnodes = keys %$hash;
        my $monsettings = xCAT::Utils->generate_monsettings($request, \@monnodes);
        xCAT::Utils->monitor_installation($request, $monsettings);
        while ($retries++ < $monsettings->{'retrycount'} && scalar(keys %{ $monsettings->{nodes} }) > 0) {

            #The nodes that need to retry
            my @nodesretry = keys %{ $monsettings->{'nodes'} };
            my $nodes = join ',', @nodesretry;

            my $rsp = {};
            $rsp->{data}->[0] = "$nodes: Reinitializing the installation: $retries retry";
            xCAT::MsgUtils->message("I", $rsp, $callback);

            foreach my $node (keys %$hash)
            {
                # The installation for this node has been finished
                if (!grep(/^$node$/, @nodesretry)) {
                    delete($hash->{$node});
                }
            }
            while (my ($name, $d) = each(%$hash)) {
                my $values = xCAT::PPCcli::chsysstate(
                    $exp,
                    $request->{op},
                    $d);
                my $Rc = shift(@$values);

                push @result, [ $name, @$values[0], $Rc ];
            }
            my @monnodes = keys %{ $monsettings->{nodes} };
            xCAT::Utils->monitor_installation($request, $monsettings);
        }

        #failed after retries
        if (scalar(keys %{ $monsettings->{'nodes'} }) > 0) {
            foreach my $node (keys %{ $monsettings->{nodes} }) {
                my $rsp = {};
                $rsp->{data}->[0] = "The node \"$node\" can not reach the expected status after $monsettings->{'retrycount'} retries, the installation for this done failed";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
        }
    }
    require xCAT_monitoring::monitorctrl;
    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
    return (\@result);
}


##########################################################################
# Queries CEC/LPAR power status (On or Off)
##########################################################################
sub power_status {

    my @states = (
        "Operating",
        "Running",
        "Open Firmware"
    );
    foreach (@states) {
        if (/^$_[0]$/) {
            return ("on");
        }
    }
    return ("off");
}


##########################################################################
# Queries CEC/LPAR power state
##########################################################################
sub state {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $prefix  = shift;
    my $convert = shift;
    my @result  = ();


    if (!defined($prefix)) {
        $prefix = "";
    }
    while (my ($mtms, $h) = each(%$hash)) {
        ######################################
        # Build CEC/LPAR information hash
        ######################################
        my $stat = enumerate($exp, $h, $mtms);
        my $Rc   = shift(@$stat);
        my $data = @$stat[0];

        while (my ($name, $d) = each(%$h)) {
            ##################################
            # Look up by lparid
            ##################################
            my $type = @$d[4];
            my $id = ($type =~ /^(fsp|bpa|cec|frame)$/) ? $type : @$d[0];

            ##################################
            # Output error
            ##################################
            if ($Rc != SUCCESS) {
                push @result, [ $name, "$prefix$data", $Rc ];
                next;
            }
            ##################################
            # Node not found
            ##################################
            if (!exists($data->{$id})) {
                push @result, [ $name, $prefix . "Node not found", 1 ];
                next;
            }
            ##################################
            # Output value
            ##################################
            my $value = $data->{$id};

            ##############################
            # Convert state to on/off
            ##############################
            if (defined($convert)) {
                $value = power_status($value);
            }
            push @result, [ $name, "$prefix$value", $Rc ];
        }
    }
    return (\@result);
}



1;

