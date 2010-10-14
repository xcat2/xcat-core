# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::lsslp;
use strict;
use Getopt::Long;
use Socket;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use Time::HiRes qw(gettimeofday);
use IO::Select;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use xCAT::PPCdb;

require xCAT::MacMap;
require xCAT_plugin::blade;

#######################################
# Constants
#######################################
use constant {
    HARDWARE_SERVICE => "service:management-hardware.IBM",
    SOFTWARE_SERVICE => "service:management-software.IBM",
    WILDCARD_SERVICE => "service:management-*",
    P6_SERVICE       => "service:management-hardware.IBM",
    SERVICE_FSP      => "cec-service-processor",
    SERVICE_BPA      => "bulk-power-controller",
    SERVICE_HMC      => "hardware-management-console",
    SERVICE_IVM      => "integrated-virtualization-manager",
    SERVICE_MM       => "management-module",
    SERVICE_RSA      => "remote-supervisor-adapter",
    SERVICE_RSA2     => "remote-supervisor-adapter-2",
    SLP_CONF         => "/usr/local/etc/slp.conf",
    SLPTOOL          => "/usr/local/bin/slptool",
    TYPE_MM          => "MM",
    TYPE_RSA         => "RSA",
    TYPE_BPA         => "BPA",
    TYPE_HMC         => "HMC",
    TYPE_IVM         => "IVM",
    TYPE_FSP         => "FSP",
    IP_ADDRESSES     => 4,
    TEXT             => 0,
    FORMAT           => 1,
    SUCCESS          => 0,
    RC_ERROR         => 1
};

#######################################
# Globals
#######################################
my %service_slp = (
    @{[ SERVICE_FSP  ]} => TYPE_FSP,
    @{[ SERVICE_BPA  ]} => TYPE_BPA,
    @{[ SERVICE_HMC  ]} => TYPE_HMC,
    @{[ SERVICE_IVM  ]} => TYPE_IVM,
    @{[ SERVICE_MM   ]} => TYPE_MM,
    @{[ SERVICE_RSA  ]} => TYPE_RSA,
    @{[ SERVICE_RSA2 ]} => TYPE_RSA
);

#######################################
# SLP display header
#######################################
my @header = (
    ["device",        "%-8s" ],
    ["type-model",    "%-12s"],
    ["serial-number", "%-15s"],
    ["side",          "%-6s" ],
    ["ip-addresses",  "placeholder"],
    ["hostname",      "%s"]
);

#######################################
# Hardware specific SLP attributes
#######################################
my %exattr = (
  @{[ SERVICE_FSP ]} => [
      "bpc-machinetype-model",
      "bpc-serial-number",
      "cage-number"
    ],
  @{[ SERVICE_BPA ]} => [
      "frame-number"
    ]
);

#######################################
# Power methods
#######################################
my %mgt = (
    lc(TYPE_FSP) => "fsp",
    lc(TYPE_BPA) => "bpa",
    lc(TYPE_MM)  => "blade",
    lc(TYPE_HMC) => "hmc",
    lc(TYPE_IVM) => "ivm",
    lc(TYPE_RSA) => "blade"
);

my @attribs    = qw(nodetype mtm serial side otherinterfaces groups mgt id parent mac);
my $verbose    = 0;
my %ip_addr    = ();
my %slp_result = ();
my %rsp_result = ();
my %opt        = ();
my $maxtries   = 1;
my $openSLP    = 1;
my @converge;
my $macmap;


##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {

    $macmap = xCAT::MacMap->new();
    return( {lsslp=>"lsslp"} );
}


##########################################################################
# Invokes the callback with the specified message
##########################################################################
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my %output;

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};
        $output{errorcode} = $ecode;
        $output{data} = \@_;
        $callback->( \%output );
    }
}



##########################################################################
# Parse the command line options and operands
##########################################################################
sub parse_args {

    my $request  = shift;
    my $args     = $request->{arg};
    my $cmd      = $request->{command};
    my %services = (
        HMC => SOFTWARE_SERVICE.":".SERVICE_HMC.":",
        IVM => SOFTWARE_SERVICE.":".SERVICE_IVM.":",
        BPA => HARDWARE_SERVICE.":".SERVICE_BPA,
        FSP => HARDWARE_SERVICE.":".SERVICE_FSP,
        RSA => HARDWARE_SERVICE.":".SERVICE_RSA.":",
        MM  => HARDWARE_SERVICE.":".SERVICE_MM.":"
    );
    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [$_[0], $usage_string] );
    };
    #############################################
    # No command-line arguments - use defaults
    #############################################
    if ( !defined( $args )) {
        return(0);
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    #############################################
    # Process command-line flags
    #############################################
    if (!GetOptions( \%opt,
            qw(h|help V|Verbose v|version i=s x z w r s=s e=s t=s m c n updatehosts makedhcp M=s resetnet vpdtable))) {
        return( usage() );
    }

    
    #############################################
    # Check for switch "-" with no option
    #############################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    #############################################
    # Set convergence
    #############################################
    if ( exists( $opt{c} )) {

        #################################
        # Use values set in slp.conf
        #################################
        if ( !defined( $ARGV[0] )) {
            @converge = (0);
        }
        #################################
        # Use new values
        #################################
        else {
            @converge = split /,/,$ARGV[0];
            if ( scalar( @converge ) > 5 ) {
                return(usage( "Convergence timeouts limited to 5 maximum" ));
            }
            foreach ( @converge ) {
                unless ( /^[1-9]{1}$|^[1-9]{1}[0-9]{1,4}$/) {
                    return(usage( "Invalid convergence timeout: $_" ));
                }
            }
        }
    }
    #############################################
    # Check for an argument
    #############################################
    elsif ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    #############################################
    # Option -V for verbose output
    #############################################
    if ( exists( $opt{V} )) {
        $verbose = 1;
    }
    #############################################
    # Check for mutually-exclusive formatting
    #############################################
    if ( (exists($opt{r}) + exists($opt{x}) + exists($opt{z}) + exists($opt{vpdtable}) ) > 1 ) {
        return( usage() );
    }
    #############################################
    # Command tries
    #############################################
    if ( exists( $opt{t} )) {
       $maxtries = $opt{t};

       if ( $maxtries !~ /^0?[1-9]$/ ) {
           return( usage( "Invalid command tries (1-9)" ));
       }
    }
    #############################################
    # Select SLP command
    #############################################
    if ( exists( $opt{e} )) {
       if ( $opt{e} !~ /slptool/ ) {
           $openSLP = 0;
       }
    }
    #############################################
    # Check for unsupported service type
    #############################################
    if ( exists( $opt{s} )) {
        if ( !exists( $services{$opt{s}} )) {
            return(usage( "Invalid service: $opt{s}" ));
        }
        $request->{service} = $services{$opt{s}};
    }

    #############################################
    # Check the dependency of makedhcp option
    #############################################
    if ( exists( $opt{makedhcp} ) and !exists( $opt{w} ) ) {
        return( usage("'makedhcp' should work with '-w' option"  ) );
    }

    #############################################
    # Check the validation of -M option
    #############################################
    if ( exists( $opt{M} ) and ($opt{M} !~ /^vpd$/) and ($opt{M} !~ /^switchport$/) ) {
        return( usage("Invalid value for '-M' option. Acceptable value is 'vpd' or 'switchport'") );
    }

    return(0);
}


##########################################################################
# Validate comma-seperated list of IPs
##########################################################################
sub validate_ip {

    my $request = shift;

    ###########################################
    # Option -i not specified (no IPs specified)
    ###########################################
    if ( !exists( $opt{i} )) {

        #######################################
        # Determine interfaces
        #######################################
        my $ips = $openSLP ?
                  slptool_ifconfig( $request ) : slpquery_ifconfig( $request );

        #######################################
        # Command failed
        #######################################
        if ( @$ips[0] ) {
            return( $ips );
        }
        return( [0] );
    }
    ###########################################
    # Option -i specified - validate entries
    ###########################################
    foreach ( split /,/, $opt{i} ) {
        my $ip = $_;

        ###################################
        # Length for IPv4 addresses
        ###################################
        my (@octets) = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
        if ( scalar(@octets) != 4 ) {
            return( [1,"Invalid IP address: $ip"] );
        }
        foreach my $octet ( @octets ) {
            if (( $octet < 0 ) or ( $octet > 255 )) {
                return( [1,"Invalid IP address: $ip"] );
            }
        }
        $ip_addr{$ip} = 1;
    }
    return( [0] );
}


##########################################################################
# Verbose mode (-V)
##########################################################################
sub trace {

    my $request = shift;
    my $msg     = shift;

    if ( $verbose ) {
        my ($sec,$min,$hour,$mday,$mon,$yr,$wday,$yday,$dst) = localtime(time);
        my $msg = sprintf "%02d:%02d:%02d %5d %s", $hour,$min,$sec,$$,$msg;
        send_msg( $request, 0, $msg );
    }
}


##########################################################################
# Determine adapters available - slptool always uses adapter IP
##########################################################################
sub slptool_ifconfig {

    my $request = shift;
    my $cmd     = "ifconfig -a";
    my $result  = `$cmd`;
    my $mode    = "MULTICAST";

    #############################################
    # Display broadcast IPs, but use adapter IP
    #############################################
    if ( !exists( $opt{m} )) {
        $mode = "BROADCAST";
    }
    #############################################
    # Error running command
    #############################################
    if ( !$result ) {
        return( [1, "Error running '$cmd': $!"] );
    }
    if ( $verbose ) {
        trace( $request, $cmd );
        trace( $request, "$mode Interfaces:" );
    }
    if (xCAT::Utils->isAIX()) {
        ##############################################################
        # Should look like this for AIX:
        # en0: flags=4e080863,80<UP,BROADCAST,NOTRAILERS,RUNNING,
        #      SIMPLEX,MULTICAST,GROUPRT,64BIT,PSEG,CHAIN>
        #      inet 30.0.0.1    netmask 0xffffff00 broadcast 30.0.0.255
        #      inet 192.168.2.1 netmask 0xffffff00 broadcast 192.168.2.255
        # en1: ...
        #
        ##############################################################
        my @adapter = split /\w+\d+:\s+flags=/, $result;
        foreach ( @adapter ) {
            if ( !($_ =~ /LOOPBACK/ ) and
                   $_ =~ /UP(,|>)/ and
                   $_ =~ /$mode/ ) {
                my @ip = split /\n/;
                foreach ( @ip ) {
                    if ( $mode eq "BROADCAST" ) {
                        if ( $_ =~ /^\s*inet\s+/ and
                             $_ =~ /broadcast\s+(\d+\.\d+\.\d+\.\d+)/ ) {

                            if ( $verbose ) {
                                trace( $request, "\t\t$1\tUP,$mode" );
                            }
                        }
                    }
                    if ( $_ =~ /^\s*inet\s*(\d+\.\d+\.\d+\.\d+)/ ) {
                        $ip_addr{$1} = 1;

                        if ( exists( $opt{m} )) {
                            trace( $request, "\t\t$1\tUP,$mode" );
                        }
                    }
                }
            }
        }
    }
    else {
        ##############################################################
        # Should look like this for Linux:
        # eth0 Link encap:Ethernet  HWaddr 00:02:55:7B:06:30
        #      inet addr:9.114.154.193  Bcast:9.114.154.223
        #      inet6 addr: fe80::202:55ff:fe7b:630/64 Scope:Link
        #      UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
        #      RX packets:1280982 errors:0 dropped:0 overruns:0 frame:0
        #      TX packets:3535776 errors:0 dropped:0 overruns:0 carrier:0
        #      collisions:0 txqueuelen:1000
        #      RX bytes:343489371 (327.5 MiB)  TX bytes:870969610 (830.6 MiB)
        #      Base address:0x2600 Memory:fbfe0000-fc0000080
        #
        # eth1 ...
        #
        ##############################################################
        my @adapter= split /\n{2,}/, $result;
        foreach ( @adapter ) {
            if ( !($_ =~ /LOOPBACK / ) and
                   $_ =~ /UP / and
                   $_ =~ /$mode / ) {

                my @ip = split /\n/;
                foreach ( @ip ) {
                    if ( $mode eq "BROADCAST" ) {
                        if ( $_ =~ /^\s*inet addr:/ and
                             $_ =~ /Bcast:(\d+\.\d+\.\d+\.\d+)/ ) {

                            if ( $verbose ) {
                                trace( $request, "\t\t$1\tUP,$mode" );
                            }
                        }
                    }
                    if ( $_ =~ /^\s*inet addr:\s*(\d+\.\d+\.\d+\.\d+)/ ) {
                        $ip_addr{$1} = 1;

                        if ( exists( $opt{m} )) {
                            trace( $request, "\t\t$1\tUP,$mode" );
                        }
                    }
                }
            }
        }
    }
    if ( (keys %ip_addr) == 0 ) {
        return( [1,"No adapters configured for $mode"] );
    }
    #########################
    # Log results
    #########################
    if ( $verbose ) {
        if ( (keys %ip_addr) == 0 ) {
            trace( $request, "$cmd\n$result" );
        }
    }
    return([0]);
}


##########################################################################
# Determine adapters available - slp_query always used broadcast IP
##########################################################################
sub slpquery_ifconfig {

    my $request = shift;
    my $cmd     = "ifconfig -a";
    my $result  = `$cmd`;
    my $mode    = "BROADCAST";

    ######################################
    # Error running command
    ######################################
    if ( !$result ) {
        return( [1, "Error running '$cmd': $!"] );
    }
    if ( $verbose ) {
        trace( $request, $cmd );
        trace( $request, "$mode Interfaces:" );
    }
    if (xCAT::Utils->isAIX()) {
        ##############################################################
        # Should look like this for AIX:
        # en0: flags=4e080863,80<UP,BROADCAST,NOTRAILERS,RUNNING,
        #      SIMPLEX,MULTICAST,GROUPRT,64BIT,PSEG,CHAIN>
        #      inet 30.0.0.1    netmask 0xffffff00 broadcast 30.0.0.255
        #      inet 192.168.2.1 netmask 0xffffff00 broadcast 192.168.2.255
        # en1: ...
        #
        ##############################################################
        my @adapter = split /\w+\d+:\s+flags=/, $result;
        foreach ( @adapter ) {
            if ( !($_ =~ /LOOPBACK/ ) and
                   $_ =~ /UP(,|>)/ and
                   $_ =~ /$mode/ ) {

                my @ip = split /\n/;
                foreach ( @ip ) {
                    if ( $_ =~ /^\s*inet\s+/ and
                         $_ =~ /broadcast\s+(\d+\.\d+\.\d+\.\d+)/ ) {
                        $ip_addr{$1} = 1;
                    }
                }
            }
        }
    }
    else {
        ##############################################################
        # Should look like this for Linux:
        # eth0 Link encap:Ethernet  HWaddr 00:02:55:7B:06:30
        #      inet addr:9.114.154.193  Bcast:9.114.154.223
        #      inet6 addr: fe80::202:55ff:fe7b:630/64 Scope:Link
        #      UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
        #      RX packets:1280982 errors:0 dropped:0 overruns:0 frame:0
        #      TX packets:3535776 errors:0 dropped:0 overruns:0 carrier:0
        #      collisions:0 txqueuelen:1000
        #      RX bytes:343489371 (327.5 MiB)  TX bytes:870969610 (830.6 MiB)
        #      Base address:0x2600 Memory:fbfe0000-fc0000080
        #
        # eth1 ...
        #
        ##############################################################
        my @adapter= split /\n{2,}/, $result;
        foreach ( @adapter ) {
            if ( !($_ =~ /LOOPBACK / ) and
                   $_ =~ /UP / and
                   $_ =~ /$mode / ) {

                my @ip = split /\n/;
                foreach ( @ip ) {
                    if ( $_ =~ /^\s*inet addr:/ and
                         $_ =~ /Bcast:(\d+\.\d+\.\d+\.\d+)/ ) {
                        $ip_addr{$1} = 1;
                    }
                }
            }
        }
    }
    if ( (keys %ip_addr) == 0 ) {
        return( [1,"No adapters configured for $mode"] );
    }
    #########################
    # Log results
    #########################
    if ( $verbose ) {
        foreach ( keys %ip_addr ) {
            trace( $request, "\t\t$_\tUP,BROADCAST" );
        }
        if ( (keys %ip_addr) == 0 ) {
            trace( $request, "$cmd\n$result" );
        }
    }
    return([0]);
}


##########################################################################
# Forks a process to run the slp command (1 per adapter)
##########################################################################
sub fork_cmd {

    my $request  = shift;
    my $ip       = shift;
    my $arg      = shift;
    my $services = shift;

    #######################################
    # Pipe childs output back to parent
    #######################################
    my $parent;
    my $child;
    pipe $parent, $child;
    my $pid = xCAT::Utils->xfork();

    if ( !defined($pid) ) {
        ###################################
        # Fork error
        ###################################
        send_msg( $request, 1, "Fork error: $!" );
        return undef;
    }
    elsif ( $pid == 0 ) {
        ###################################
        # Child process
        ###################################
        close( $parent );
        $request->{pipe} = $child;

        invoke_cmd( $request, $ip, $arg, $services );
        exit(0);
    }
    else {
        ###################################
        # Parent process
        ###################################
        close( $child );
        return( $parent );
    }
    return(0);
}



##########################################################################
# Run the forked command and send reply to parent
##########################################################################
sub invoke_cmd {

    my $request  = shift;
    my $ip       = shift;
    my $args     = shift;
    my $services = shift;

    ########################################
    # Telnet (rspconfig) command
    ########################################
    if ( !defined( $services )) {
        my $target_dev = $args->{$ip};
        my @cmds;
        my $result;
        if ( $verbose ) {
            trace( $request, "Forked: ($ip)->($target_dev->{args})" );
        }
        if ($target_dev->{'type'} eq 'mm')
        {
            @cmds = (
                    "snmpcfg=enable",
                    "sshcfg=enable",
                    "network_reset=$target_dev->{args}"
                    );
            $result = xCAT_plugin::blade::telnetcmds(
                    $ip,
                    $target_dev->{username},
                    $target_dev->{password},
                    0,
                    @cmds );
        }
        elsif($target_dev->{'type'} eq 'hmc')
        {
            @cmds = ("network_reset=$target_dev->{args}");
            trace( $request, "sshcmds on hmc $ip");
            $result = xCAT::PPC::sshcmds_on_hmc(
                    $ip,
                    $target_dev->{username},
                    $target_dev->{password},
                    @cmds );
       }
        else #The rest must be fsp or bpa
        {
            @cmds = ("network=$ip,$target_dev->{args}");
            trace( $request, "update config on $target_dev->{'type'} $ip");
            $result = xCAT::PPC::updconf_in_asm(
                    $ip,
                    $target_dev,
                    @cmds );
        }

        ####################################
        # Pass result array back to parent
        ####################################
        my @data = ("RSPCONFIG6sK4ci", $ip, @$result[0], @$result[2]);
        my $out = $request->{pipe};


        print $out freeze( \@data );
        print $out "\nENDOFFREEZE6sK4ci\n";
        return;
    }

    ########################################
    # SLP command
    ########################################
    my $result  = runslp( $args, $ip, $services, $request );
    my $unicast = @$result[0];
    my $values  = @$result[1];
    prt_result( $request, $values);

    ########################################
    # May have to send additional unicasts
    ########################################
    if ( keys (%$unicast) )  {
        foreach my $url ( keys %$unicast ) {
            my ($service,$addr) = split "://", $url;
            next if ($addr =~ /:/);#skip IPV6

            ####################################
            # Strip off trailing ",lifetime"
            ####################################
            $addr =~ s/,*\d*$//;
            my $sockaddr = inet_aton( $addr );
            $url =~ s/,*\d*$//;

            ####################################
            # Make sure can resolve if hostname
            ####################################
            if  ( !defined( $sockaddr )) {
                if ( $verbose ) {
                    trace( $request, "Cannot convert '$addr' to dot-notation" );
                }
                next;
            }
            $addr = inet_ntoa( $sockaddr );

            ####################################
            # Select command format
            ####################################
            if ( $openSLP ) {
                $result = runslp( $args, $ip, [$url], $request, 1 );
            } else {
                $result = runslp( $args, $addr, [$service], $request, 1 );
            }
            my $data   = @$result[1];
            my ($attr) = keys %$data;

            ####################################
            # Save results
            ####################################
            if ( defined($attr) ) {
                $values->{"URL: $url\n$attr\n"} = 1;
                prt_result( $values);
            }
        }
    }
    ########################################
    # No valid responses received
    ########################################
    if (( keys (%$values )) == 0 ) {
        return;
    }
    ########################################
    # Pass result array back to parent
    ########################################
    my @results = ("FORMATDATA6sK4ci", $values );
    my $out = $request->{pipe};

    print $out freeze( \@results );
    print $out "\nENDOFFREEZE6sK4ci\n";
}

#########################################################
# print the slp result
#########################################################
sub prt_result
{
    my $request = shift;
    my $values = shift;
    my $nets = xCAT::Utils::my_nets();
    for my $v (keys %$values)
    {
        if ( $v =~ /ip-address=([^\)]+)/g)
        {
            my $iplist = $1;
            my $ip = getip_from_iplist( $iplist, $nets, $opt{i});
            if ( $ip)
            {
#                send_msg($request, "Received SLP response from $ip.");
#print "Received SLP response from $ip.\n";
                xCAT::MsgUtils->message("I", "Received SLP response from $ip.", $::callback);
            }
        }
    }
}

##########################################################################
# Run the SLP command, process the response, and send to parent
##########################################################################
sub runslp {

    my $slpcmd   = shift;
    my $ip       = shift;
    my $services = shift;
    my $request  = shift;
    my $attreq   = shift;
    my %result   = ();
    my %unicast  = ();
    my $cmd;

    foreach my $type ( @$services ) {
        my $try = 0;

        ###########################################
        # OpenSLP - slptool command
        ###########################################
        if ( $openSLP ) {
            $cmd = $attreq ?
               "$slpcmd findattrsusingiflist $ip $type" :
               "$slpcmd findsrvsusingiflist $ip $type";
        }
        ###########################################
        # IBM SLP - slp_query command
        ###########################################
        else {
            $cmd = $attreq ?
               "$slpcmd --address=$ip --type=$type" :
               "$slpcmd --address=$ip --type=$type --converge=1";
        }

        ###########################################
        # Run the command
        ###########################################
        while ( $try++ < $maxtries ) {
            if ( $verbose ) {
                trace( $request, $cmd );
                trace( $request, "Attempt $try of $maxtries\t( $ip\t$type )" );
            }
            #######################################
            # Serialize transmits out each adapter
            #######################################
            if ( !open( OUTPUT, "$cmd 2>&1 |")) {
                send_msg( $request, 1, "Fork error: $!" );
                return undef;
            }
            ###############################
            # Get command output
            ###############################
            my $rsp;
            while ( <OUTPUT> ) {
                $rsp.=$_;
            }
            close OUTPUT;

            ###############################
            # No replies
            ###############################
            if ( !$rsp ) {
                if ( $verbose ) {
                    trace( $request, ">>>>>> No Response" );
                }
                next;
            }
            ###########################################
            # For IVM, running AIX 53J (6/07) release,
            # there is an AIX SLP bug where IVM will
            # respond to SLP service-requests with its
            # URL only and not its attributes. An SLP
            # unicast to the URL address is necessary
            # to acquire the attributes. This was fixed
            # in AIX 53L (11/07).
            #
            ###########################################

            ###########################################
            # OpenSLP response format:
            #   service:management-software.IBM...
            #   (type=hardware-management-cons...
            #   (serial-number=KPHHK24),(name=c76v2h...
            #   1ab1dd89ca8e0763e),(ip-address=192.1...
            #   0CR3*KPHHK24),(web-management-interf...
            #   2.ppd.pok.ibm.com:8443),(cimom-port=...
            #   ...
            ###########################################
            if ( $openSLP ) {
                my @data = split /\n/,$rsp;
                my $length = scalar( @data );
                my $i = 0;

                while ($i < $length ) {
                    ###################################
                    # Service-Request response
                    ###################################
                    if ( $data[$i] =~
                        /^service\:management-(software|hardware)\.IBM\:([^\:]+)/) {

                        ###############################
                        # Invalid service-type
                        ###############################
                        if ( !exists( $service_slp{$2} )) {
                            if ( $verbose ) {
                                trace( $request, "DISCARDING: $data[$i]" );
                            }
                            $i++;
                            next;
                        }
                        my $url  = $data[$i++];
                        my $attr = $data[$i];

                        #Give some intermediate output
                        my ($url_ip) = $url =~ /:\/\/(\d+\.\d+\.\d+\.\d+)/;
                        if ( ! $::DISCOVERED_HOST{$url_ip})
                        {
                            $::DISCOVERED_HOST{$url_ip} = 1;
                        }
                        if ( $verbose ) {
                            trace( $request, ">>>> SrvRqst Response" );
                            trace( $request, "URL: $url" );
                        }
                        ###############################
                        # No "ATTR" - have to unicast
                        ###############################
                        if ( $attr !~ /^(\(type=.*)$/ ) {
                           $unicast{$url} = $url;
                        }
                        ###############################
                        # Response has "ATTR" field
                        ###############################
                        else {
                            if ( $verbose ) {
                                trace( $request, "ATTR: $attr\n" );
                            }
                            my $val = "URL: $url\nATTR: $attr";
                            $result{$val} = 1;
                            $i++;
                        }
                    }
                    ###################################
                    # Attribute-Request response
                    ###################################
                    elsif ( $data[$i] =~ /(\(type=.*)$/ ) {
                        my $attr = "ATTR: $data[$i++]";

                        if ( $verbose ) {
                            trace( $request, ">>>> AttrRqst Response" );
                            trace( $request, $attr );
                        }
                        $result{$attr} = 1;
                    }
                    ###################################
                    # Unrecognized response
                    ###################################
                    else {
                        if ( $verbose ) {
                            trace( $request, "DISCARDING: $data[$i]" );
                        }
                        $i++;
                    }
                }
            }
            ###########################################
            # IBM SLP response format:
            #   0
            #   1
            #   75
            #   URL: service:management-software.IBM...
            #   ATTR: (type=hardware-management-cons...
            #   (serial-number=KPHHK24),(name=c76v2h...
            #   1ab1dd89ca8e0763e),(ip-address=192.1...
            #   0CR3*KPHHK24),(web-management-interf...
            #   2.ppd.pok.ibm.com:8443),(cimom-port=...
            #
            #   0
            #   1
            #   69
            #   URL:...
            #   ATTR:..
            #   ..
            ###########################################
            else {
                foreach ( split /\n{2,}/,$rsp ) {
                    if ( $_ =~ s/(\d+)\n(\d+)\n(\d+)\n// ) {
                        if ( $verbose ) {
                            trace( $request, "SrvRqst Response ($1)($2)($3)" );
                            trace( $request, "$_\n" );
                        }
                        ###############################
                        # Response has "ATTR" field
                        ###############################
                        if ( /ATTR: /  ) {
                            $result{$_} = 1;
                        }
                        ###############################
                        # No "ATTR" - have to unicast
                        ###############################
                        elsif ( /.*URL: (.*)/ ) {
                            $unicast{$1} = $1;
                        }
                    }
                    elsif ( $verbose ) {
                        trace( $request, "DISCARDING: $_" );
                    }
                }
            }
        }
    }
    return( [\%unicast,\%result] );
}



##########################################################################
# Formats slp responses
##########################################################################
sub format_output {

    my $request = shift;
    my $values  = shift;
    my $length  = length( $header[IP_ADDRESSES][TEXT] );
    my $result;

    ###########################################
    # Parse responses and add to hash
    ###########################################
    my $outhash = parse_responses( $request, $values, \$length );

    ###########################################
    # No responses
    ###########################################
    if (( keys %$outhash ) == 0 ){
        send_msg( $request, 0, "No responses" );
        return;
    }
    ###########################################
    # -w flag for write to xCat database
    ###########################################
    if ( exists( $opt{w} )) {
        xCATdB( $outhash );
    }

    ###########################################
    # --makedhcp flag to issue xCAT command
    # makedhcp internally.
    ###########################################
    if ( exists( $opt{makedhcp} ) ) {
        do_makedhcp( $request, $outhash );
    }

    ###########################################
    # --resetnet flag to reset the network 
    # interface of the node
    ###########################################
    if ( exists( $opt{resetnet} ) ) {
        do_resetnet( $request, $outhash );
    }

    ###########################################
    # -r flag for raw response format
    ###########################################
    if ( exists( $opt{r} )) {
        foreach ( keys %$outhash ) {
            $result .= "@{ $outhash->{$_}}[9]\n";
        }
        send_msg( $request, 0, $result );
        return;
    }
    ###########################################
    # -x flag for xml format
    ###########################################
    if ( exists( $opt{x} )) {
        send_msg( $request, 0, format_xml( $outhash ));
        return;
    }
    ###########################################
    # -z flag for stanza format
    ###########################################
    if ( exists( $opt{z} )) {
        send_msg( $request, 0, format_stanza( $outhash ));
        return;
    }

    ###########################################
    # -T flag for vpd table format
    ###########################################
    if ( exists( $opt{vpdtable} ) ) {
        send_msg( $request, 0, format_table( $outhash ) );
        return;
    }

    ###########################################
    # Get longest IP for formatting purposes
    ###########################################
    my $format = sprintf "%%-%ds", ( $length + 2 );
    $header[IP_ADDRESSES][FORMAT] = $format;

    ###########################################
    # Display header
    ###########################################
    foreach ( @header ) {
        $result .= sprintf @$_[1], @$_[0];
    }
    $result .= "\n";

    ###########################################
    # Display response attributes
    ###########################################
    foreach my $hostname ( sort keys %$outhash ) {
        my $data = $outhash->{$hostname};
        my $i = 0;

        foreach ( @header ) {
            if ( @$_[0] =~ /^hostname$/ ) {
                $result .= sprintf @$_[1], $hostname;
            } else {
                $result .= sprintf @$_[1], @$data[$i++];
            }
        }
        $result .= "\n";
    }
    send_msg( $request, 0, $result );
}


##########################################################################
# Get IP from SLP URL response
##########################################################################
sub getip_from_url {

    my $request = shift;
    my $url     = shift;

    ######################################################################
    # Extract the IP from the URL. Generally, the URL
    # should be in the following format (the ":0" port number
    # may or may not be present):
    # service:management-hardware.IBM:management-module://9.114.113.78:0
    # service:management-software.IBM:integrated-virtualization-manager://zd21p1.rchland.ibm.com
    ######################################################################
    if (($url !~ /service:.*:\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}).*/ )) {
        return undef;
    }
    return( $1 );
}



##########################################################################
# Get hostname from SLP URL response
##########################################################################
sub gethost_from_url {

    my $request = shift;
    my $rsp     = shift;
    my $type    = shift;
    my $mtm     = shift;
    my $sn      = shift;
    my $side    = shift;
    my $iplist  = shift;
    my $bpc_machinetype = shift;
    my $bpc_serial      = shift;
    my $frame_number    = shift;
    my $cage_number     = shift;
    my $host;

    if ( $side =~ /^N\/A$/ ) {
        $side = undef;
    }

    #######################################
    # Extract IP from URL
    #######################################
    my $nets = xCAT::Utils::my_nets();
    my $ip = getip_from_iplist( $iplist, $nets, $opt{i});
    if ( !defined( $ip )) {
        return undef;
    }

    #######################################
    # Check if valid IP
    #######################################
    my $packed = inet_aton( $ip );
    if ( length( $packed ) != 4 ) {
        if ( $verbose ) {
            trace( $request, "Invalid IP address in URL: $ip" );
        }
        return undef;
    }

    #######################################
    # Get hostname from vpd table
    #######################################
    if ( exists($opt{M}) and ($opt{M} =~ /^vpd$/) ) {
        $host = match_vpdtable($type, $mtm, $sn, $side, $bpc_machinetype, $bpc_serial, $frame_number, $cage_number);
    }

    if ( !$host ) {
        $host = getFactoryHostname($type,$mtm,$sn,$side,$ip,$rsp);
        #######################################
        # Convert hostname to short-hostname
        #######################################
        if ( $host =~ /([^\.]+)\./ ) {
            $host = $1;
        }
    }

    return( "$host($ip)" );

}

##########################################################################
# Match hostnames in vpd table
##########################################################################
sub match_vpdtable
{
    my $type    = shift;
    my $mtm     = shift;
    my $sn      = shift;
    my $side    = shift;
    my $bpc_machinetype = shift;
    my $bpc_serial      = shift;
    my $frame_number    = shift;
    my $cage_number     = shift;
    my $host;

    #######################################
    # Cache ppc table
    #######################################
    if ( !%::PPC_TAB_CACHE) {
        my $ppctab = xCAT::Table->new( 'ppc' );
        my @entries = $ppctab->getAllNodeAttribs(['node','parent','id']);
        for my $entry ( @entries ) {
            if ( $entry->{mtm} and $entry->{serial} and defined( $entry->{side} ) ) {
            }
        }
    }

    #######################################
    # Cache vpd table
    #######################################
    if ( !%::VPD_TAB_CACHE ) {
        my $vpdtab  = xCAT::Table->new( 'vpd' );
        my @entries = $vpdtab->getAllNodeAttribs(['node','mtm','serial','side']);
        #Assuming IP is unique in hosts table
        for my $entry ( @entries ) {
            if ( $entry->{mtm} and $entry->{serial} and defined( $entry->{side} ) ) {
                $::VPD_TAB_CACHE{$entry->{mtm} . '*' . $entry->{serial} . '-' . $entry->{side}} = $entry->{ 'node'};

            }
        }
    }

    if ( exists( $::VPD_TAB_CACHE{$mtm . '*' . $sn . '-' . $side} ) ) {
        $host = $::VPD_TAB_CACHE{$mtm . '*' . $sn . '-' . $side};
        return( "$host" );
    }
}

##########################################################################
# Match hostnames in switch table
##########################################################################
sub match_switchtable
{
    my $ip   = shift;
    my $mac  = shift;
    my $type = shift;
    my $bpc_model    = shift;
    my $bpc_serial   = shift;
    my $frame_number = shift;
    my $cage_number  = shift;
    my $side   = shift;
    my $mtm    = shift;
    my $serial = shift;
    my $name;

    #######################################
    # Find the nodenames that match the
    # port on switch to their mac
    #######################################
    my $names = $macmap->find_mac( $mac );
    if ( $names =~ /,/ ) {
        #######################################
        # For High end machines, only BPA have
        # connections to switch, FSPs shared the 
        # port with BPA.  So need to distiguish
        # the FSPs on the same port
        #######################################
        $name = disti_multi_node( $names, $type, $bpc_model, $bpc_serial, $frame_number, $cage_number, $side, $mtm, $serial );
        if ( ! $name ) {
            return undef;
        }
    } elsif ( !$names ) {
        return undef;
    } else {
        $name = $names;
    }

    return $name;
}

sub getFactoryHostname
{
    my $type = shift;
    my $mtm  = shift;
    my $sn   = shift;
    my $side = shift;
    my $ip   = shift;
    my $rsp  = shift;
    my $host = undef;

    if ( $rsp =~ /\(name=([^\)]+)/ ) {
        $host = $1;

    ###################################
    # Convert to short-hostname
    ###################################
        if ( $host =~ /([^\.]+)\./ ) {
            $host = $1;
        }
    }

    if ( $type eq SERVICE_FSP or $type eq SERVICE_BPA or $type eq SERVICE_MM )
    {
        $host = "Server-$mtm-SN$sn-$side";
    }

    if ( $ip ) {
        my $hname = gethostbyaddr( inet_aton($ip), AF_INET );
        if ( $hname ) {
            $host = $hname;
        }
    }
    if ( !$host ) {
        my $hoststab = xCAT::Table->new( 'hosts' );
        my @entries = $hoststab->getAllNodeAttribs(['node','ip']);
        foreach my $entry ( @entries ) {
            if ( $entry->{ip} and $entry->{ip} eq $ip ) {
                $host = $entry->{node};
            }
        }
    }

    return $host;
}

##########################################################################
# Get correct IP from ip list in SLP Attr
##########################################################################
sub getip_from_iplist
{
    my $iplist  = shift;
    my $nets    = shift;
    my $inc     = shift;
    
    my @ips = split /,/, $iplist;
    if ( $inc)
    {
        for my $net (keys %$nets)
        {
            delete $nets->{$net} if ( $nets->{$net} ne $inc);
        }
    }
    
    for my $ip (@ips)
    {
        next if ( $ip =~ /:/); #skip IPV6 addresses
        for my $net ( keys %$nets)
        {
            my ($n,$m) = split /\//,$net;
            if ( xCAT::Utils::isInSameSubnet( $n, $ip, $m, 1) and
                 xCAT::Utils::isPingable( $ip))
            {
                return $ip;
            }
        }
    }
    return undef;
}

##########################################################################
# Match IP addresses to MAC in arp table
##########################################################################
sub match_ip_mac
{
    my $ips = shift;

    ######################################################
    # Cache ARP table entries
    ######################################################
    if ( !%::ARP_CACHE ) {
        my $arp;
        if ( $^O eq 'aix' ) {
            $arp = `/usr/sbin/arp -a`;
        } else {
            $arp = `/sbin/arp -n`;
        }

        my @arpents = split /\n/, $arp;


        foreach my $arpent ( @arpents ) {
            my ($ip, $mac);
            if ( $^O eq 'aix' && $arpent =~ /\((\S+)\)\s+at\s+(\S+)/ ) {
                ($ip, $mac) = ($1,$2);
                ######################################################
                # Change mac format to be same as linux. For example:
                # '0:d:60:f4:f8:22' to '00:0d:60:f4:f8:22'
                ######################################################
                if ( $mac ) {
                    my @mac_sections = split /:/, $mac;
                    for (@mac_sections ) {
                        $_ = "0$_" if ( length($_) == 1) ;
                    }
                    $mac = join '', @mac_sections;
                }
            } elsif ( $arpent =~ /^(\S+)+\s+\S+\s+(\S+)\s/ ) {
                ($ip, $mac) = ($1,$2);
            } else {
                ($ip, $mac) = (undef,undef);
            }
           
            if ( defined($ip) and defined($mac) ) {
                $::ARP_CACHE{$ip} = $mac;
            }
        }
    }

    if ( exists($::ARP_CACHE{$ips}) ) {
        return( $::ARP_CACHE{$ips} );
    }

    return undef;
}


##########################################################################
# Example OpenSLP slptool "service-request" output. The following
# attributes can be returned in any order within an SLP response.
#
# service:management-hardware.IBM:management-module://192.20.154.19,48659
# (type=management-module),(level=3),(serial-number= K10WM39916W),
# (fru=73P9297     ),(name=WMN315724834),(ip-address=192.20.154.19),
# (enclosure-serial-number=78AG034),(enclosure-fru=59P6609     ),
# (enclosure-machinetype-model=86772XX),(status=0),(enclosure-uuid=
#  \ff\e6\4f\0b\41\de\0d\11\d7\bd\be\b5\3c\ab\f0\46\04),
# (web-url=http://192.20.154.19:80),(snmp-port=161),(slim-port=6090),
# (ssh-port=22),(secure-slim-port=0),(secure-slim-port-enabled=false),
# (firmware-image-info=BRET86P:16:01-29-08,BRBR82A:16:06-01-05),
# (telnet-port=23),(slot=1),0
#  ...
#
# Example OpenSLP slptool "attribute-request" output. The following
# attributes can be returned in any order within an SLP response.
#
# (type=integrated-virtualization-manager),(level=3),(machinetype-model=911051A),
# (serial-number=1075ECF),(name=p510ivm.clusters.com)(ip-address=192.168.1.103),
# (web-url=http://p510ivm.clusters.com/),(mtms=911051A*1075ECF),
# (web-management-interface=TRUE),(secure-web-url=https://p510ivm.clusters.com/),
# (cimom-port=5988),(secure-cimom-port=5989),(lparid=1)
#  ...
#
#------------------------------------------------------------------------
#
# Example IBM SLP slp_query command "service-request" output. The following
# attributes can be returned in any order within an SLP response.
# Note: The leading 3 numbers preceeding the URL: and ATTR: fields
# represent:
#        error code,
#        URL count,
#        URL length, respectively.
# 0
# 1
# 75
# URL: service:management-software.IBM:hardware-management-console://192.168.1.110
# ATTR: (type=hardware-management-console),(level=3),(machinetype-model=7310CR3),
# (serial-number=KPHHK24),(name=c76v2hmc02.ppd.pok.ibm.com),(uuid=de335adf051eb21
# 1ab1dd89ca8e0763e),(ip-address=192.168.1.110,9.114.47.154),(web-url=),(mtms=731
# 0CR3*KPHHK24),(web-management-interface=true),(secure-web-url=https://c76v2hmc0
# 2.ppd.pok.ibm.com:8443),(cimom-port=),(secure-cimom-port=5989)
#
# 0
# 1
# 69
# ...
#
# Example IBM SLP slp_query command "attribute-request" output. The following
# attributes can be returned in any order within an SLP response.
# Note: The leading 3 numbers preceeding the URL: and ATTR: fields
# represent:
#        error code,
#        0, (hardcoded)
#        ATTR  length, respectively.
# 0
# 0
# 354
# ATTR: (type=integrated-virtualization-manager),(level=3),(machinetype-model=911051A),
# (serial-number=1075ECF),(name=p705ivm.clusters.com),(ip-address=192.168.1.103),
# (web-url=http://p705ivm.clusters.com/),(mtms=911051A*1075ECF),(web-management-
# interface=TRUE),(secure-web-url=https://p705ivm.clusters.com/),(cimom-port=5988),
# (secure-cimom-port=5989),(lparid=1)
#
#########################################################################
sub parse_responses {

    my $request = shift;
    my $values  = shift;
    my $length  = shift;

    my %outhash = ();
    my @attrs   = (
        "type",
        "machinetype-model",
        "serial-number",
        "slot",
        "ip-address",
        "bpc-machinetype-model",
        "bpc-serial-number",
        "frame-number",
        "cage-number" );

    #######################################
    # RSA/MM Attributes
    #######################################
    my @xattrs = (
       "type",
       "enclosure-machinetype-model",
       "enclosure-serial-number",
       "slot",
       "ip-address" );

    foreach my $rsp ( @$values ) {
        ###########################################
        # Get service-type from response
        ###########################################
        my @result = ();
        my $host;

        ###########################################
        # service-type attribute not found
        ###########################################
        if ( $rsp !~ /\(type=([^\)]+)/ ) {
            if ( $verbose ) {
                trace( $request, "(type) attribute not found: $rsp" );
            }
            next;
        }
        ###########################################
        # Valid service-type attribute
        ###########################################
        my $type = $1;

        ###########################################
        # Unsupported service-type
        ###########################################
        if ( !exists($service_slp{$type} )) {
            if ( $verbose ) {
                trace( $request, "Discarding unsupported type: $type" );
            }
            next;
        }
        ###########################################
        # RSA/MM - slightly different attributes
        ###########################################
        my $attr = \@attrs;
        if (( $type eq SERVICE_RSA ) or ( $type eq SERVICE_RSA2 ) or
            ( $type eq SERVICE_MM )) {
            $attr = \@xattrs;
        }

        ###########################################
        # Extract the attributes
        ###########################################
        foreach ( @$attr ) {
            unless ( $rsp =~ /\($_=([^\)]+)/ ) {
                if ( $verbose ) {
                    trace( $request, "Attribute not found: [$_]->($rsp)" );
                } 
                push @result, "N/A";
                next;
            } 
            my $val = $1;
            if (( $_ =~ /^slot$/ ) and ( $val == 0 )) {
                push @result, "B";
            } elsif (( $_ =~ /^slot$/ ) and ( $val == 1 )) {
                push @result, "A";
            } else {
                push @result, $val; 
            }
        }

        ###########################################
        # Get host directly from URL
        ###########################################
        if ( $type eq SERVICE_HMC or $type eq SERVICE_BPA 
                or $type eq SERVICE_FSP or $type eq SERVICE_MM ) {
            $host = gethost_from_url( $request, $rsp, @result);
            if ( !defined( $host )) {
                next;
            }
        }

        ###########################################
        # Strip commas from IP list
        ###########################################
        $result[4] =~ s/,/ /g;
        my $ip     = $result[4];

        ###########################################
        # Save longest IP for formatting purposes
        ###########################################
        if ( length( $ip ) > $$length ) {
            $$length = length( $ip );
        }

        push @result, $rsp;
 
        $result[0] = $service_slp{$type};
        $outhash{$host} = \@result;
    }
    
    ##########################################################
    # Correct BPA node name because both side
    # have the same MTMS and may get the same factory name
    # If there are same factory name for 2 BPA (should be 2 sides
    # on one frame), change them to like <bpa>_1 and <bpa>_2
    # Also, remove those nodes that have same IP addresses and
    # give a warning message.
    ##########################################################
    my %ip_record;
    for my $h ( keys %outhash ) {
        my ($name, $ip);
        if ( $h =~ /^([^\(]+)\(([^\)]+)\)$/ ) {
            $name = $1;
            $ip   = $2;

        } else {
            next;
        }

        if ( ! $ip_record{$ip} ) {
            $ip_record{$ip} = $h;
        } else {
            my $response;
            $response->{data}->[0] =  "IP address of node $h is conflicting to node $ip_record{$ip}. Remove node $h from discovery result.";
            xCAT::MsgUtils->message("W", $response, $request->{callback});
            delete $outhash{$h};
        }
    }

    my %vpd_table_hash;
    my $vpdtab  = xCAT::Table->new( 'vpd' );
    my @entries = $vpdtab->getAllNodeAttribs(['node','mtm','serial','side']);
    for my $entry ( @entries ) {
        if ( $entry->{mtm} and $entry->{serial} ) {
            $vpd_table_hash{$entry->{mtm} . '*' . $entry->{serial} . '-' . $entry->{side}} = $entry->{ 'node'};
        }
    }

    my %nodehm_table_hash;
    my $nodehm_tab  = xCAT::Table->new('nodehm');
    my @nodehm_entries = $nodehm_tab->getAllNodeAttribs(['node','mgt']);
    for my $entry ( @nodehm_entries ) {
        if ( $entry->{'mgt'} ) {
            $nodehm_table_hash{$entry->{'node'}} = $entry->{ 'mgt'};
        }
    }

    my %hash = ();
    for my $h ( keys %outhash ) {
        my $data = $outhash{$h};
        my $type = @$data[0];
        my $mtm  = @$data[1];
        my $sn   = @$data[2];
        my $side = @$data[3];
        my $frame;

        my ($name, $ip);
        if ( $h =~ /^([^\(]+)\(([^\)]+)\)$/ ) {
            $name = $1;
            $ip   = $2;
        } else {
            $name = $h;
            $ip   = @$data[4];
        }

        ############################################################
        # -n flag to skip the existing node
        ############################################################
        if ( exists( $opt{n} ) ) {
            if ( exists $vpd_table_hash{$mtm . '*' . $sn . '-' . $side} ) {
                my $existing_node = $vpd_table_hash{$mtm . '*' . $sn . '-' . $side};
                if ( exists $nodehm_table_hash{$existing_node} ) {
                    next;
                }
            }
        }

        if ( $type =~ /^FSP$/ ) {
            ############################################################
            # For HE machine, there are 2 FSPs, but only one FSP have the
            # BPA information. We need to go through the outhash and
            # find its BPA
            ############################################################
            if ((@$data[5] eq "0" ) and ( @$data[6] eq "0" )) {
                for my $he_node ( keys %outhash ) {
                    if ( $mtm eq $outhash{$he_node}->[1] and
                         $sn eq $outhash{$he_node}->[2] and
                         $outhash{$he_node}->[5] and
                         $outhash{$he_node}->[6]
                        ) {
                        @$data[5] = $outhash{$he_node}->[5];
                        @$data[6] = $outhash{$he_node}->[6];
                        @$data[8] = $outhash{$he_node}->[8];
                    }
                }
            }

            ########################################
            # Find the parent for this FSP
            ########################################
            if (( @$data[5] ne "0" ) and ( @$data[6] ne "0" )) {
                if ( exists $vpd_table_hash{@$data[5] . '*' . @$data[6] . '-A'} ) {
                    $frame = $vpd_table_hash{@$data[5] . '*' . @$data[6] . '-A'};
                } elsif ( exists $vpd_table_hash{@$data[5] . '*' . @$data[6] . '-B'} ) {
                    $frame = $vpd_table_hash{@$data[5] . '*' . @$data[6] . '-B'};
                } elsif ( exists $vpd_table_hash{@$data[5] . '*' . @$data[6] . '-'} ) {
                    $frame = $vpd_table_hash{@$data[5] . '*' . @$data[6] . '-'};
                } else {
                    $frame = "Server-@$data[5]-SN@$data[6]";
                }
            } else {
                $frame = undef;
            }
        } elsif ( $type =~ /^BPA$/ ) {
            $frame = undef;
        }

        push @$data, $frame;

        ########################################
        # Get the Mac address
        ########################################
        my $mac = match_ip_mac( $ip );
        push @$data, $mac;

        #######################################
        # Get hostname from switch table
        #######################################
        my $host;
        if ( $mac and exists($opt{M}) and ($opt{M} =~ /^switchport$/) ) {
            my $type       = @$data[0];
            my $mtm        = @$data[1];
            my $serial     = @$data[2];

            if ( $type =~ /^BPA$/ or $type =~ /^FSP$/ ) {
                my $bpc_model  = @$data[5];
                my $bpc_serial = @$data[6];
                my $frame_number = @$data[7];
                my $cage_number  = @$data[8];
                my $side         = @$data[3];

                $host = match_switchtable($ip, $mac, $type, $bpc_model, $bpc_serial, $frame_number, $cage_number, $side, $mtm, $serial);
            } else {
                my $bpc_model  = undef;
                my $bpc_serial = undef;
                my $frame_number = undef;
                my $cage_number  = undef;
                my $side         = @$data[3];

                $host = match_switchtable($ip, $mac, $type, $bpc_model, $bpc_serial, $frame_number, $cage_number, $side, $mtm, $serial);
            }
 
            if ( $host ) {
                $h = "$host($ip)";
            }
        }

        $hash{$h} = $data;
    }

    return( \%hash );
}

##########################################################################
# Write result to xCat database
##########################################################################
sub xCATdB {
    my $outhash = shift;
    my %keyhash = ();
    my %updates = ();
    my %sn_node = ();

    foreach my $hostname ( keys %$outhash ) {
        my $data = $outhash->{$hostname};
        my $type = @$data[0];
        my $ip   = @$data[4];
        my $name = $hostname;
        if ( $hostname =~ /^([^\(]+)\(([^\)]+)\)$/)
        {
            $name = $1;
            $ip  = $2;
        }

        ########################################
        # Write result to hosts table
        ########################################
        if ( exists($opt{updatehosts}) ) {
            my $hostip = writehost($name,$ip);
        }

        if ( $type =~ /^BPA$/ ) {
            my $model  = @$data[1];
            my $serial = @$data[2];
            my $side   = @$data[3];
            my $id     = @$data[7];
            my $mac    = @$data[11];

            ####################################
            # N/A Values
            ####################################
            my $prof  = "";
            my $frame = "";

            my $values = join( ",",
               lc($type),$name,$id,$model,$serial,$side,$name,$prof,$frame,$ip,$mac );
            xCAT::PPCdb::add_ppc( lc($type), [$values], 0, 1 );
        } elsif ( $type =~ /^(HMC|IVM)$/ ) {
            my $mac    = @$data[11];

            xCAT::PPCdb::add_ppchcp( lc($type), "$name,$mac,$ip",1 );
        }
        elsif ( $type =~ /^FSP$/ ) {
            ########################################
            # BPA frame this CEC is in
            ########################################
            my $frame      = "";
            my $model      = @$data[1];
            my $serial     = @$data[2];
            my $side       = @$data[3];
            my $bpc_model  = @$data[5];
            my $bpc_serial = @$data[6];
            my $cageid     = @$data[8];
            my $frame      = @$data[10];
            my $mac        = @$data[11];

            ########################################
            # N/A Values
            ########################################
            my $prof   = "";
            my $server = "";

            my $values = join( ",",
               lc($type),$name,$cageid,$model,$serial,$side,$name,$prof,$frame,$ip,$mac );
            xCAT::PPCdb::add_ppc( "fsp", [$values], 0, 1 );
        }
        elsif ( $type =~ /^(RSA|MM)$/ ) {
            xCAT::PPCdb::add_systemX( $type, $name, $data );
        }
    }
}

##########################################################################
# Run makedhcp internally
##########################################################################
sub do_makedhcp {

    my $request = shift;
    my $outhash = shift;
    my @nodes;
    my $string;

    my @tabs   = qw(hosts mac);
    my %db     = ();
        
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>1 );
            if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }

    $string = "\nStart to do makedhcp..\n";
    send_msg( $request, 0, $string );

    #####################################
    # Collect nodenames
    #####################################
    foreach my $name ( keys %$outhash ) {
        if ( $name =~ /^([^\(]+)\(([^\)]+)\)$/) {
            $name = $1;
        }
        
        #####################################
        # Check if IP and mac are both
        # existing for this node
        #####################################
        my ($hostsent) = $db{hosts}->getNodeAttribs( $name, [qw(ip)] );
        if ( !$hostsent or !$hostsent->{ip} ) {
            $string = "Cannot find IP address for node $name during makedhcp, skip";
            send_msg( $request, 0, $string );
            next;
        }

        my ($macent) = $db{mac}->getNodeAttribs( $name, [qw(mac)] );
        if ( !$macent or !$macent->{mac} ) {
            $string = "Cannot find MAC address for node $name during makedhcp, skip";
            send_msg( $request, 0, $string );
            next;
        }

        push @nodes, $name;
    }

    my $node = join ",", @nodes;

    $string = "Adding following nodes to dhcp server: \n$node\n";
    send_msg( $request, 0, $string );

    my $line = `/opt/xcat/sbin/makedhcp $node 2>&1`;
    send_msg( $request, 0, $line);

    send_msg( $request, 0, "\nMakedhcp finished.\n" );

    return undef;
}

##########################################################################
# Reset the network interfraces if necessary
##########################################################################
sub do_resetnet {

    my $req     = shift;
    my $outhash = shift;
    my $reset_all = 1;
    my $namehash;
    my $targets;
    my $result;

    if ( $outhash ) {
        $reset_all = 0;
        foreach my $name ( keys %$outhash ) {
            my $data = $outhash->{$name};
            my $ip = @$data[4];
            if ( $name =~ /^([^\(]+)\(([^\)]+)\)$/) {
                $name = $1;
                $ip = $2;
            }
            $namehash->{$name} = $ip;
        }
    }

    my $hoststab = xCAT::Table->new( 'hosts' ); 
    if ( !$hoststab ) {
        send_msg( $req, 1, "Error open hosts table" );
        return( [RC_ERROR] );
    }

    my $nodetypetab = xCAT::Table->new( 'nodetype' );
    if ( !$nodetypetab ) {
        send_msg( $req, 1, "Error open nodetype table" );
        return( [RC_ERROR] );
    }

    my $mactab = xCAT::Table->new( 'mac' );
    if ( !$mactab ) {
        send_msg( $req, 1, "Error open mac table" );
        return( [RC_ERROR] );
    } 

    send_msg( $req, 0, "\nStart to reset network..\n" );

    my $ip_host;
    my @hostslist = $hoststab->getAllNodeAttribs(['node','ip','otherinterfaces']);
    foreach my $host ( @hostslist ) {
        my $name = $host->{node};
        my $ip   = $host->{ip};
        my $oi;

        #####################################
        # Skip the node if the IP attributes
        # is same as otherinterfaces or ip
        # discovered
        #####################################
        if ( $namehash->{$name} ) {
            $oi = $namehash->{$name};
            $hoststab->setNodeAttribs( $name,{otherinterfaces=>$namehash->{$name}} );
        } else {
            $oi = $host->{otherinterfaces};
        }

        if ( !$reset_all ) {
            if ( $namehash->{$name} ) {
                if ( !$ip or $ip eq $namehash->{$name} ) {
                    send_msg( $req, 0, "$name: same ip address, skipping network reset" );
                    next;
                }
            } else {
                next;
            }
        } elsif (!$ip or !$oi or $ip eq $oi) {
            send_msg( $req, 0, "$name: same ip address, skipping network reset" );
            next;
        }

        my $type = $nodetypetab->getNodeAttribs( $name, [qw(nodetype)]);
        if ( !$type or !$type->{nodetype} ) {
            send_msg( $req, 0, "$name: no nodetype defined, skipping network reset" );
            next;
        }

        my $mac = $mactab->getNodeAttribs( $name, [qw(mac)]);
        if ( !$mac or !$mac->{mac} ) {
            send_msg( $req, 0, "$name: no mac defined, skipping network reset" );
            next;
        }

        #####################################
        # Make the target that will reset its
        # network interface
        #####################################
        $targets->{$type->{nodetype}}->{$namehash->{$name}}->{'args'} = "0.0.0.0,$name";
        $targets->{$type->{nodetype}}->{$namehash->{$name}}->{'mac'} = $mac->{mac};
        $targets->{$type->{nodetype}}->{$namehash->{$name}}->{'name'} = $name;
        $targets->{$type->{nodetype}}->{$namehash->{$name}}->{'ip'} = $namehash->{$name};
        $targets->{$type->{nodetype}}->{$namehash->{$name}}->{'type'} = $type->{nodetype};
        if ( $type->{nodetype} !~ /^mm$/ ) {
            my %netinfo = xCAT::DBobjUtils->getNetwkInfo( [$namehash->{$name}] );
            $targets->{$type->{nodetype}}->{$namehash->{$name}}->{'args'} .= ",$netinfo{$namehash->{$name}}{'gateway'},$netinfo{$oi}{'mask'}";
        }
        $ip_host->{$namehash->{$name}} = $name;
    }

    $result = undef;
    ###########################################
    # Update target hardware w/discovery info
    ###########################################
    my ($fail_nodes,$succeed_nodes) = rspconfig( $req, $targets );
    $result = "\nReset network failed nodes:\n";
    foreach my $ip ( @$fail_nodes ) {
        if ( $ip_host->{$ip} ) {
            $result .= $ip_host->{$ip} . ",";
        }
    }
    $result .= "\nReset network succeed nodes:\n";
    foreach my $ip ( @$succeed_nodes ) {
        if ( $ip_host->{$ip} ) {
            $result .= $ip_host->{$ip} . ",";
            my $new_ip = $hoststab->getNodeAttribs( $ip_host->{$ip}, [qw(ip)]);
            $hoststab->setNodeAttribs( $ip_host->{$ip},{otherinterfaces=>$new_ip->{ip}} );
        }
    }
    $result .= "\nReset network finished.\n";
    $hoststab->close();

    send_msg( $req, 0, $result );

    return undef;
}

##########################################################################
# Stanza formatting
##########################################################################
sub format_stanza {

    my $outhash = shift;
    my $result;

    #####################################
    # Write attributes
    #####################################
    foreach my $name ( keys %$outhash ) {
        my @data = @{$outhash->{$name}};
        my $type = lc($data[0]);
        my $ip   = $data[4];
        my $i = 0;

        if ( $name =~ /^([^\(]+)\(([^\)]+)\)$/) {
            $name = $1;
            $ip  = $2;
        }

        #################################
        # Node attributes
        #################################
        $result .= "$name:\n\tobjtype=node\n";

        #################################
        # Add each attribute
        #################################
        $result .= "\thcp=$name\n";
        foreach ( @attribs ) {
            my $d = $data[$i++];

            if ( /^nodetype$/ ) {
                $d = $type;
            } elsif ( /^groups$/ ) {
                $d = "$type,all";
            } elsif ( /^mgt$/ ) {
                $d = $mgt{$type};
            } elsif ( /^id$/ ) {
                if ( $type =~ /^fsp$/ ) {
                    $d = $data[$i++]; 
                } elsif ( $type =~ /^bpa$/ ) {
                    $i++;
                } else {
                    $i++;
                    next;
                }
                $i++;
            } elsif ( /^side$/ or /^parent$/ ) {
                if ( $type !~ /^(fsp|bpa)$/ ) {
                    next;
                }
            } elsif ( /^otherinterfaces$/ ) {
                $d = $ip;
            }

            if ( !defined($d) ) {
                next;
            }

            $result .= "\t$_=$d\n";
        }
        if ( exists($opt{updatehosts}) ) {
            $result .= "\tip=$ip\n";
        }
    }
    return( $result );
}



##########################################################################
# XML formatting
##########################################################################
sub format_xml {

    my $outhash = shift;
    my $xml;

    #####################################
    # Create XML formatted attributes
    #####################################
    foreach my $name ( keys %$outhash ) {
        my @data = @{ $outhash->{$name}};
        my $type = lc($data[0]);
        my $ip   = $data[4];
        my $i = 0;

        if ( $name =~ /^([^\(]+)\(([^\)]+)\)$/) {
            $name = $1;
            $ip  = $2;
        }

        #################################
        # Initialize hash reference
        #################################
        my $href = {
            Node => { }
        };
        $href->{Node}->{node} = $name;
        if ( exists($opt{updatehosts}) ) {
            $href->{Node}->{ip} = $ip;
        }
        #################################
        # Add each attribute
        #################################
        $href->{Node}->{"hcp"} = $name;
        foreach ( @attribs ) {
            my $d = $data[$i++];

            if ( /^nodetype$/ ) {
                $d = $type;
            } elsif ( /^groups$/ ) {
                $d = "$type,all";
            } elsif ( /^mgt$/ ) {
                $d = $mgt{$type};
            } elsif ( /^id$/ ) {
                if ( $type =~ /^fsp$/ ) {
                    $d = $data[$i++];
                } elsif ( $type =~ /^bpa$/ ) {
                    $i++;
                } else {
                    $i++;
                    next;
                }
                $i++;
            } elsif ( /^side$/ or /^parent$/ ) {
                if ( $type !~ /^(fsp|bpa)$/ ) {
                    next;
                }
            } elsif ( /^otherinterfaces$/ ) {
                $d = $ip;
            }

            if ( !defined($d) ) {
                next;
            }
            $href->{Node}->{$_} = $d;
        }
        #################################
        # XML encoding
        #################################
        $xml.= XMLout($href,
                     NoAttr   => 1,
                     KeyAttr  => [],
                     RootName => undef );
    }
    return( $xml );
}

##########################################################################
# VPD table formatting
##########################################################################
sub format_table {

    my $outhash = shift;
    my $result;

    $result = "\n#node,serial,mtm,side,asset,comments,disable\n";
    #####################################
    # Create XML formatted attributes
    #####################################
    foreach my $name ( keys %$outhash ) {
        my @data = @{ $outhash->{$name}};
        my $type = lc($data[0]);        
        my $mtm  = $data[1];
        my $serial = $data[2];
        my $side = $data[3];
        if ( $side =~ /^N\/A$/ ) {
            $result .= ",\"$serial\",\"$mtm\",,,\"$type\",\n";
        } else {
            $result .= ",\"$serial\",\"$mtm\",\"$side\",,\"$type\",\n";
        }
    }

    return( $result );
}


##########################################################################
# OpenSLP running on:
#     P6 FSP
#     P6 BPA
# IBM SLP running on:
#     P5 FSP
#     P5 BPA
#     HMC
#     MM
#     RSA
# AIX SLP
#     IVM
#
# Notes:
# IBM SLP requires trailing ':' (i.e. service:management-hardware.IBM:)
# There is one exception to this rule when dealing with FSP
# concrete" service types, it will work with/without the trailing ':'
# (i.e. "service:management-hardware.IBM:cec-service-processor[:]")
#
# OpenSLP does not support ':' at the end of services
# (i.e. service:management-hardware.IBM:). Unfortunately, IBM SLP
# requires it.
#
# Given the above, to collect all the above service types, it is
# necessary to multicast:
# (1) "service:management-*" for all IBM SLP hardware
# (2) "service:management-hardware.IBM" for OpenSLP hardware (P6 FSP/BPA)
#      (IBM SLP hardware will not respond to this since there is no trailing ":")
#
# * One exception to the above rule is when using FSP concrete
#   service type, it will work with/without the trailing ":"
#   (i.e. "service:management-hardware.IBM:cec-service-processor[:]"
#
##########################################################################


##########################################################################
# Run IBM SLP version
##########################################################################
sub slp_query {

    my $request  = shift;
    my $callback = $request->{callback};
    my $cmd      = $opt{e};

    #############################################
    # slp_query not installed
    #############################################
    if ( !-x $cmd ) {
        send_msg( $request, 1, "Command not found: $cmd" );
        return( [RC_ERROR] );
    }
    #############################################
    # slp_query runnable - dependent on libstdc++
    # Test for usage statement.
    #############################################
    my $output = `$cmd 2>&1`;
    if ( $output !~ /slp_query --type=service-type-string/ ) {
        send_msg( $request, 1, $output );
        return( [RC_ERROR] );
    }
    my $result = runcmd( $request, $cmd );
    return( $result );
}


##########################################################################
# Run OpenSLP version
##########################################################################
sub slptool {

    my $request = shift;
    my $cmd     = SLPTOOL;
    my $start;

    #########################################
    # slptool not installed
    #########################################
    if ( !-x $cmd ) {
        send_msg( $request, 1, "Command not found: $cmd" );
        return( [RC_ERROR] );
    }
    #########################################
    # slptool runnable - test for version
    #########################################
    my $output = `$cmd -v 2>&1`;
    if ( $output !~ /^slptool version = 1.2.1\nlibslp version = 1.2.1/ ) {
        send_msg( $request, 1, "Incorrect 'slptool' command installed" );
        return( [RC_ERROR] );
    }
    #########################################
    # Select broadcast, convergence, etc
    #########################################
    my $mode = selectmode( $request );
    if ( defined($mode) ) {
        return( $mode );
    }
    my $result = runcmd( $request, $cmd );
    return( $result );
}


##########################################################################
# Select OpenSLP slptool broadcast convergence, etc
##########################################################################
sub selectmode {

    my $request = shift;
    my $fname   = SLP_CONF;
    my $mode;
    my $maxtimeout;
    my $converge;

    ##################################
    # Select convergence
    ##################################
    if ( exists( $opt{c} )) {
        $converge = join( ',',@converge );

        ##############################
        # Maximum timeout
        ##############################
        foreach ( @converge ) {
            $maxtimeout += $_;
        }
    }
    ##################################
    # Select multicast or broadcast
    ##################################
    if ( !exists( $opt{m} )) {
        $mode = "true";
    }

    ##################################
    # slp.conf attributes
    ##################################
    my %attr = (
        "net.slp.multicastTimeouts"    => $converge,
        "net.slp.isBroadcastOnly"      => $mode,
        "net.slp.multicastMaximumWait" => $maxtimeout
    );

    if ( $verbose ) {
        my $msg = !defined($mode) ? "Multicasting SLP...":"Broadcasting SLP...";
        trace( $request, $msg );
    }
    ##################################
    # Open/read slp.conf
    ##################################
    unless ( open( CONF, $fname )) {
        send_msg( $request, 1, "Error opening: '$fname'" );
        return( [RC_ERROR] );
    }
    my @raw_data = <CONF>;
    close( CONF );

    ##################################
    # Find attribute
    ##################################
    foreach my $name ( keys %attr ) {
        my $found = 0;

        foreach ( @raw_data ) {
            if ( /^;*$name\s*=/ ) {
                if ( !defined( $attr{$name} )) {
                    s/^;*($name\s*=\s*[\w,]+)/;$1/;
                } elsif ( $attr{$name} == 0 ) {
                    s/^;*($name\s*=\s*[\w,]+)/$1/;
                } else {
                    s/^;*$name\s*=\s*[\w,]+/$name = $attr{$name}/;
                }
                $found = 1;
                last;
            }
        }
        if ( !$found ) {
            send_msg( $request, 1, "'$name' not found in '$fname'" );
            return( [RC_ERROR] );
        }
    }
    ##################################
    # Rewrite file contents
    ##################################
    unless ( open( CONF, "+>$fname" )) {
        send_msg( $request, 1, "Error opening: '$fname'" );
        return( [RC_ERROR] );
    }
    print CONF @raw_data;
    close( CONF );
    return undef;
}


##########################################################################
# Run the SLP command
##########################################################################
sub runcmd {

    my $request  = shift;
    my $cmd      = shift;
    my $services = shift;
    my $callback = $request->{callback};
    my @services = ( WILDCARD_SERVICE, P6_SERVICE );
    my $start;

    ###########################################
    # Query specific service; otherwise,
    # query all hardware/software services
    ###########################################
    if ( exists( $opt{s} )) {
        @services = $request->{service};
    }

    if ( $verbose ) {
        #######################################
        # Write header for trace
        #######################################
        my $tm  = localtime( time );
        my $msg = "\n--------  $tm\nTime     PID";
        trace( $request, $msg );
    }
    ###########################################
    # Get/validate broadcast IPs
    ###########################################
    my $result = validate_ip( $request );
    my $Rc = shift(@$result);

    if ( $Rc ) {
        send_msg( $request, 1, @$result[0] );
        return( [RC_ERROR] );
    }
    if ( $verbose ) {
        $start = Time::HiRes::gettimeofday();
    }
    ###########################################
    # Fork one process per adapter
    ###########################################
    my $children = 0;
    $SIG{CHLD} = sub { 
       my $rc_bak = $?; 
       while (waitpid(-1, WNOHANG) > 0) { $children--; } 
       $? = $rc_bak;
    };
    my $fds = new IO::Select;

    foreach ( keys %ip_addr ) {
        my $pipe = fork_cmd( $request, $_, $cmd, \@services );
        if ( $pipe ) {
            $fds->add( $pipe );
            $children++;
        }
    }
    ###########################################
    # Process slp responses from children
    ###########################################
    while ( $children > 0 ) {
        child_response( $callback, $fds );
    }
    while (child_response($callback,$fds)) {}

    if ( $verbose ) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $msg = sprintf( "Total SLP Time: %.3f sec\n", $elapsed );
        trace( $request, $msg );
    }
    ###########################################
    # Combined responses from all children
    ###########################################
    my @all_results = keys %slp_result;
    format_output( $request, \@all_results );
    return( [SUCCESS,\@all_results] );
}


##########################################################################
# Collect output from the child processes
##########################################################################
sub child_response {

    my $callback = shift;
    my $fds = shift;
    my @ready_fds = $fds->can_read(1);

    foreach my $rfh (@ready_fds) {
        my $data = <$rfh>;

        #################################
        # Read from child process
        #################################
        if ( defined( $data )) {
            while ($data !~ /ENDOFFREEZE6sK4ci/) {
                $data .= <$rfh>;
            }
            my $responses = thaw($data);

            #############################
            # Formatted SLP results
            #############################
            if ( @$responses[0] =~ /^FORMATDATA6sK4ci$/ ) {
                my $result = @$responses[1];
                foreach ( keys %$result ) {
                    $slp_result{$_} = 1;
                }
                next;
            }
            #############################
            # rspconfig results
            #############################
            if ( @$responses[0] =~ /^RSPCONFIG6sK4ci$/ ) {
                shift @$responses;
                my $ip = shift(@$responses);

                $rsp_result{$ip} = $responses;
                next;
            }
            #############################
            # Message or verbose trace
            #############################
            foreach ( @$responses ) {
                $callback->( $_ );
            }
            next;
        }
        #################################
        # Done - close handle
        #################################
        $fds->remove($rfh);
        close($rfh);
    }
}



#############################################################################
# Preprocess request from xCat daemon and send request to service nodes
#############################################################################
sub preprocess_request {

    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my @requests;

    ####################################
    # Prompt for usage if needed
    ####################################
    my $noderange = $req->{node}; #Should be arrayref
    my $command = $req->{command}->[0];
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }
    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }
    ###########################################
    # find all the service nodes for xCAT cluster
    # build an individual request for each service node
    ###########################################
    my %sv_hash=();
    my @all = xCAT::Utils::getAllSN();
    foreach (@all) {
	    $sv_hash{$_}=1;
    }
    ###########################################
    # build each request for each service node
    ###########################################
    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    foreach my $sn (keys (%sv_hash)) {
      my $reqcopy = {%$req};
      $reqcopy->{_xcatdest} = $sn;
      $reqcopy->{_xcatpreprocessed}->[0] = 1;
      push @result, $reqcopy;
    }
    return \@result;
}

##########################################################################
# Distinguish 
##########################################################################
sub disti_multi_node
{
    my $names = shift;
    my $type  = shift;
    my $bpc_model    = shift;
    my $bpc_serial   = shift;
    my $frame_number = shift;
    my $cage_number  = shift;
    my $side   = shift;
    my $mtm    = shift;
    my $serial = shift;

    return undef if ( $type eq 'FSP' and !defined $cage_number );    
    return undef if ( $type eq 'BPA' and !defined $frame_number );

    my $ppctab = xCAT::Table->new( 'ppc' );
    return undef if ( ! $ppctab );
    my $nodetypetab = xCAT::Table->new( 'nodetype' );
    return undef if ( ! $nodetypetab );

    my $vpdtab = xCAT::Table->new( 'vpd' );
    return undef if ( ! $vpdtab );
 
    my @nodes = split /,/, $names;
    my $correct_node = undef;
    foreach my $node ( @nodes ) {
        my $id_parent = $ppctab->getNodeAttribs( $node, ['id','parent'] );
        my $nodetype = $nodetypetab->getNodeAttribs($node, ['nodetype'] );
	    next if ( !defined $nodetype or !exists $nodetype->{'nodetype'} );
        next if ( $nodetype->{'nodetype'} ne lc($type) );

        if ( $nodetype->{'nodetype'} eq 'fsp' ) {
            if ( (exists $id_parent->{'id'}) and (exists $id_parent->{'parent'}) ) {
                ###########################################
                # For high end machines.
                # Check if this node's parent and id is the
                # same in SLP response.
                ###########################################
                if ( $id_parent->{'id'} eq $cage_number ) {
                    my $vpdnode = $vpdtab->getNodeAttribs($id_parent->{'parent'}, ['serial','mtm']);
                    if ( (exists $vpdnode->{'serial'}) and ($vpdnode->{'serial'} ne $bpc_serial) ) {
                        next;
                    }
                    if ( (exists $vpdnode->{'mtm'}) and ($vpdnode->{'mtm'} ne $bpc_model) ) {
                        next;
                    }
                } else {
                    next;
                }
            } else {
                ###########################################
                # For low end machines.
                # If there is hub to connect several FSPs
                # with the same switch port, check node's
                # mtms
                ###########################################
                my $vpdnode = $vpdtab->getNodeAttribs($node, ['serial','mtm']); 
                if ( (exists $vpdnode->{'serial'}) and ($vpdnode->{'serial'} ne $serial) ) {
                    next;
                }
                if ( (exists $vpdnode->{'mtm'}) and ($vpdnode->{'mtm'} ne $mtm) ) {
                    next;
                }
            }

            ###########################################
            # Check if the side attribute for this node
            # is the same in SLP response
            # For FSP redundancy.
            ###########################################
            my $nodeside = $vpdtab->getNodeAttribs($node, ['side']);
            if ( (exists $nodeside->{'side'}) and ($nodeside->{'side'} ne $side) ) {
                next;
            }
        }

        if ( $nodetype->{'nodetype'} eq 'bpa' or $nodetype->{'nodetype'} eq 'mm' ) {
            ###########################################
            # If there is a hub to connect several BPAs
            # with the same switch port, check this
            # node's mtms and side
            ###########################################
            my $vpdnode = $vpdtab->getNodeAttribs( $node, ['serial','mtm','side'] );

            if ( (exists $vpdnode->{'serial'}) and ($vpdnode->{'serial'} ne $serial) ) {
                next;
            }
            if ( (exists $vpdnode->{'mtm'}) and ($vpdnode->{'mtm'} ne $mtm) ) {
                next;
            }
            if ( (exists $vpdnode->{'side'}) and ($vpdnode->{'side'} ne $side) ) {
                next;
            }
        }
        return $node;
    }

    return undef;    
}

##########################################################################
# Run rspconfig against targets
##########################################################################
sub rspconfig {

    my $request   = shift;
    my $targets   = shift;
    my $callback  = $request->{callback};
    my $start = Time::HiRes::gettimeofday();

    my %rsp_dev = get_rsp_dev( $request, $targets);
    #############################################
    # Fork one process per MM/HMC
    #############################################
    my $children = 0;
    $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
    my $fds = new IO::Select;

    foreach my $ip ( keys %rsp_dev) {
        my $pipe = fork_cmd( $request, $ip, \%rsp_dev);
        if ( $pipe ) {
            $fds->add( $pipe );
            $children++;
        }
    }
    #############################################
    # Process responses from children
    #############################################
    while ( $children > 0 ) {
        child_response( $callback, $fds );
    }
    while (child_response($callback,$fds)) {}

    if ( $verbose ) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $msg = sprintf( "Total rspconfig Time: %.3f sec\n", $elapsed );
        trace( $request, $msg );
    }

    my $result;
    my @failed_node;
    my @succeed_node;
    foreach my $ip ( keys %rsp_result ) {
        #################################
        # Error logging on to MM
        #################################
        my $result = $rsp_result{$ip};
        my $Rc = shift(@$result);

        if ( $Rc != SUCCESS ) {
            push @failed_node, $ip;
        } else { 
            push @succeed_node, $ip;
        }

        if ( $Rc != SUCCESS ) {
            #############################
            # MM connect error
            #############################
            if ( ref(@$result[0]) ne 'ARRAY' ) {
                if ( $verbose ) {
                    trace( $request, "$ip: @$result[0]" );
                }
                delete $rsp_dev{$ip};
                next;
            }
        }

        ##################################
        # Process each response
        ##################################
        if ( defined(@$result[0]) ) {
            foreach ( @{@$result[0]} ) {
                if ( $verbose ) {
                    trace( $request, "$ip: $_" );
                }
                /^(\S+)\s+(\d+)/;
                my $cmd = $1;
                $Rc = $2;

                if ( $cmd =~ /^network_reset/ ) {
                    if ( $Rc != SUCCESS ) {
                        delete $rsp_dev{$ip};
                        next;
                    }
                    if ( $verbose ) {
                        trace( $request,"Resetting management-module ($ip)...." );
                    }
                }
            }
        }
    }

    return( \@failed_node, \@succeed_node );
}

#############################################
# Get rsp devices and their logon info
#############################################
sub get_rsp_dev
{
    my $request = shift;
    my $targets = shift;

    my $mm  = $targets->{'mm'}  ? $targets->{'mm'} : {};
    my $hmc = $targets->{'hmc'} ? $targets->{'hmc'}: {};
    my $fsp = $targets->{'fsp'} ? $targets->{'fsp'}: {};
    my $bpa = $targets->{'bpa'} ? $targets->{'bpa'}: {};

    if (%$mm)
    {
        my $bladeuser = 'USERID';
        my $bladepass = 'PASSW0RD';
        if ( $verbose ) {
            trace( $request, "telneting to management-modules....." );
        }
        #############################################
        # Check passwd table for userid/password
        #############################################
        my $passtab = xCAT::Table->new('passwd');
        if ( $passtab ) {
            my ($ent) = $passtab->getAttribs({key=>'blade'},'username','password');
            if ( defined( $ent )) {
                $bladeuser = $ent->{username};
                $bladepass = $ent->{password};
            }
        }
        #############################################
        # Get MM userid/password
        #############################################
        my $mpatab = xCAT::Table->new('mpa');
        foreach ( keys %$mm ) {
            my $user = $bladeuser;
            my $pass = $bladepass;

            if ( defined( $mpatab )) {
                my ($ent) = $mpatab->getAttribs({mpa=>$_},'username','password');
                if ( defined( $ent->{password} )) { $pass = $ent->{password}; }
                if ( defined( $ent->{username} )) { $user = $ent->{username}; }
            }
            $mm->{$_}->{username} = $user;
            $mm->{$_}->{password} = $pass;
        }
    }
    if (%$hmc )
    {
        #############################################
        # Get HMC userid/password
        #############################################
        foreach ( keys %$hmc ) {
            ( $hmc->{$_}->{username}, $hmc->{$_}->{password}) = xCAT::PPCdb::credentials( $hmc->{$_}->{name}, lc($hmc->{$_}->{'type'}), "hscroot" ); 
            trace( $request, "user/passwd for $_ is $hmc->{$_}->{username} $hmc->{$_}->{password}");
        }
    }

    if ( %$fsp)
    {
        #############################################
        # Get FSP userid/password
        #############################################
        foreach ( keys %$fsp ) {
            ( $fsp->{$_}->{username}, $fsp->{$_}->{password}) = xCAT::PPCdb::credentials( $fsp->{$_}->{name}, lc($fsp->{$_}->{'type'}), "admin"); 
            trace( $request, "user/passwd for $_ is $fsp->{$_}->{username} $fsp->{$_}->{password}");
        }
    }

    if ( %$bpa)
    {
        #############################################
        # Get BPA userid/password
        #############################################
        foreach ( keys %$bpa ) {
            ( $bpa->{$_}->{username}, $bpa->{$_}->{password}) = xCAT::PPCdb::credentials( $bpa->{$_}->{name}, lc($bpa->{$_}->{'type'}), "admin"); 
            trace( $request, "user/passwd for $_ is $bpa->{$_}->{username} $bpa->{$_}->{password}");
        }
    }
    
    return (%$mm,%$hmc,%$fsp,%$bpa);
}

##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {

    my $req      = shift;
    my $callback = shift;
    my $doreq    = shift;

    ###########################################
    # Build hash to pass around
    ###########################################
    my %request;
    $request{arg}      = $req->{arg};
    $request{callback} = $callback;
    $request{command}  = $req->{command}->[0];

    ####################################
    # Process command-specific options
    ####################################
    my $result = parse_args( \%request );

    ####################################
    # Return error
    ####################################
    if ( ref($result) eq 'ARRAY' ) {
        send_msg( \%request, 1, @$result );
        return(1);
    }

    if ( exists($opt{resetnet}) and scalar(keys %opt) eq 1 ) {
        $result = do_resetnet( \%request );
    } else {
        ###########################################
        # SLP service-request - select program
        ###########################################
        $result = $openSLP ? slptool( \%request ) : slp_query( \%request );
    }
    my $Rc  = shift(@$result);

    return( $Rc );
}

##########################################################################
# Write hostnames and IP address to host table.  If an existing entry 
# with same IP address can be found, return the existing hostname and IP
##########################################################################
sub writehost {

    my $hostname = shift;
    my $ip       = shift;

    my $hoststab = xCAT::Table->new( "hosts", -create=>1, -autocommit=>1 );
    if ( !$hoststab ) {
        return( [[$hostname,"Error opening 'hosts' table",RC_ERROR]] );
    }

    $hoststab->setNodeAttribs( $hostname,{ip=>$ip} );
    $hoststab->close();
}


1;







