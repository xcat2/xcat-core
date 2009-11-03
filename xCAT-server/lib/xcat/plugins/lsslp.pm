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
    IP_ADDRESSES     => 3,
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
    lc(TYPE_FSP) => "hmc",
    lc(TYPE_HMC) => "hmc",
    lc(TYPE_MM)  => "blade",
    lc(TYPE_HMC) => "hmc",
    lc(TYPE_IVM) => "ivm",
    lc(TYPE_RSA) => "blade"
);

my @attribs    = qw(nodetype model serial groups node mgt mpa id);
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
            qw(h|help V|Verbose v|version i=s x z w r s=s e=s t=s m c u H))) {
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
    if ( (exists($opt{r}) + exists($opt{x}) + exists($opt{z})) > 1 ) {
        return( usage() );
    }
    if ( (exists($opt{u}) + exists($opt{H})) > 1 ) {
        return( usage("Cannot use flags -u and -H together"));
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
    my $pid = fork;

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
        if ($target_dev->{'type'} eq 'MM')
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
        elsif($target_dev->{'type'} eq 'HMC')
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
    # Query switch ports
    ###########################################
    my $rsp_targets = undef;
    if ( $opt{u} or $opt{H})
    {
        $rsp_targets = switch_cmd( $request, $values );
    }

    ###########################################
    # Parse responses and add to hash
    ###########################################
    my $outhash = parse_responses( $request, $values, $rsp_targets, \$length );

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
    # -r flag for raw response format
    ###########################################
    if ( exists( $opt{r} )) {
        foreach ( keys %$outhash ) {
            $result .= "@{ $outhash->{$_}}[5]\n";
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
    foreach ( sort keys %$outhash ) {
        my $data = $outhash->{$_};
        my $i = 0;

        foreach ( @header ) {
            $result .= sprintf @$_[1], @$data[$i++];
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
    my $iplist  = shift;

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
    # Get host from vpd table
    #######################################
    if ( !%::VPD_TAB_CACHE)
    {
        my $vpdtab  = xCAT::Table->new( 'vpd' );
        my @entries = $vpdtab->getAllNodeAttribs(['node','mtm','serial']);
        #Assuming IP is unique in hosts table
        for my $entry ( @entries)
        {
            if ( $entry->{mtm} and $entry->{serial})
            {
                $::VPD_TAB_CACHE{$entry->{ 'node'}} = $entry->{mtm} . '*' . $entry->{serial};
            }
        }
    }
    if ( $rsp =~ /\(machinetype-model=(.*?)\)/ )
    {
        my $mtm = $1;
        if ( $rsp =~ /\(serial-number=(.*?)\)/)
        {
            my $sn = $1;
            foreach my $node ( keys %::VPD_TAB_CACHE ) {
                if ( $::VPD_TAB_CACHE{$node} eq $mtm . '*' . $sn ) {

                    delete $::VPD_TAB_CACHE{$node};
                    return $node . "($ip)";
                }
            }
        }
    }

    #######################################
    # Read host from hosts table
    #######################################
    if ( ! %::HOST_TAB_CACHE)
    {
        my $hosttab  = xCAT::Table->new( 'hosts' );
        my @entries = $hosttab->getAllNodeAttribs(['node','ip']);
        #Assuming IP is unique in hosts table
        for my $entry ( @entries)
        {
            if ( defined $entry->{ 'ip'})
            {
                $::HOST_TAB_CACHE{$entry->{ 'ip'}} = $entry->{ 'node'};
            }
        }
    }
    if ( exists $::HOST_TAB_CACHE{ $ip})
    {
        return $::HOST_TAB_CACHE{ $ip} ."($ip)";
    }

    ###############################################################
    # Convert IP to hostname (Accoording to  DNS or /etc/hosts
    ###############################################################
    my $host = gethostbyaddr( $packed, AF_INET );
    if ( !$host or $! ) {
#Tentative solution
return undef if ($opt{H});
        $host = getFactoryHostname($type,$mtm,$sn,$rsp);
#return( $ip );
    }
    #######################################
    # Convert hostname to short-hostname
    #######################################
    if ( $host =~ /([^\.]+)\./ ) {
        $host = $1;
    }
    return( "$host($ip)" );

#    ###########################################
#    #  Otherwise, URL is not in IP format
#    ###########################################
#    if ( !($url =~ /service:.*:\/\/(.*)/  )) {
#        if ( $verbose ) {
#            trace( $request, "Invalid URL: $_[0]" );
#        }
#        return undef;
#    }
#    return( $1 );

}

sub getFactoryHostname
{
    my $type = shift;
    my $mtm  = shift;
    my $sn   = shift;
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

    if ( $type eq SERVICE_FSP or $type eq SERVICE_BPA)
    {
        $host = "Server-$mtm-SN$sn";
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
    my $mm      = shift;
    my $length  = shift;

    my %outhash = ();
    my @attrs   = (
       "type",
       "machinetype-model",
       "serial-number",
       "ip-address" );

    #######################################
    # RSA/MM Attributes
    #######################################
    my @xattrs = (
       "type",
       "enclosure-machinetype-model",
       "enclosure-serial-number",
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
                next; 
            } 
            push @result, $1; 
        }

        ###########################################
        # Get host directly from URL
        ###########################################
        if ( $type eq SERVICE_HMC or $type eq SERVICE_BPA 
                or $type eq SERVICE_FSP) {
            $host = gethost_from_url( $request, $rsp, @result);
            if ( !defined( $host )) {
                next;
            }
        }
        ###########################################
        # Seperate ATTR and URL portions:
        # URL: service:management-software.IBM...
        # ATTR: (type=hardware-management-cons...
        # (serial-number=KPHHK24),(name=c76v2h...
        # 1ab1dd89ca8e0763e),(ip-address=192.1...
        # 0CR3*KPHHK24),(web-management-interf...
        # 2.ppd.pok.ibm.com:8443),(cimom-port=...
        #
        ###########################################
        $rsp =~ /.*URL: (.*)\nATTR: +(.*)/;

        ###########################################
        # If MM, use the discovered host
        ###########################################
        if (!$host and ( $type eq SERVICE_MM ) and ( defined( $mm ))) {
            my $ip = getip_from_url( $request, $1 );

            if ( defined( $ip )) {
                if ( exists( $mm->{$ip}->{args} )) {
                    $mm->{$ip}->{args} =~ /^.*,(.*)$/;
                    $host = $1;
                }
            }
        }

        push @result, $host;
        ###################################
        # Strip off trailing ",lifetime"
        ###################################
        my $at = $2;
        $at =~ s/,\d+$//;
        push @result, $at;

        ###########################################
        # Strip commas from IP list
        ###########################################
        $result[3] =~ s/,/ /g;
        my $ip     = $result[3];

        ###########################################
        # Process any extra attributes
        ###########################################
        foreach ( @{$exattr{$type}} ) {
             push @result, ($rsp =~ /\($_=([\w\-\.,]+)\)/) ? $1 : "0";
        }
        ###########################################
        # Save longest IP for formatting purposes
        ###########################################
        if ( length( $ip ) > $$length ) {
            $$length = length( $ip );
        }
        $result[0] = $service_slp{$type};
        $outhash{$host} = \@result;
    }
    
    ##########################################################
    # Correct BPA node name because both side
    # have the same MTMS and may get the same factory name
    # If there are same factory name for 2 BPA (should be 2 sides
    # on one frame), change them to like <bpa>_1 and <bpa>_2
    ##########################################################
    my %hostname_record;
    for my $h ( keys %outhash)
    {
        my ($name, $ip);
        if ( $h =~ /^([^\(]+)\(([^\)]+)\)$/)
        {
            $name = $1;
            $ip   = $2;
        }
        else
        {
            next;
        }

        if (exists $hostname_record{$name})
        {
            #Name is duplicated
            my ($old_h, $old_ip) = @{$hostname_record{$name}};
            #if the node has been defined, keep one for old node name
            #otherwise create new node name
            $outhash{$old_h}->[4] = $name . "-1" . "($old_ip)";
            $outhash{$name . "-1" . "($old_ip)"} = $outhash{$old_h};
            delete $outhash{$old_h};

            $outhash{$h}->[4] = $name . "-2" . "($ip)";
            $outhash{$name . "-2" . "($ip)"} = $outhash{$h};
            delete $outhash{$h};
        }
        else
        {
            $hostname_record{$name} = [$h,$ip];
        }
    }

    return( \%outhash );
}

##########################################################################
# Write result to xCat database
##########################################################################
sub xCATdB {

    my $outhash = shift;
    my %keyhash = ();
    my %updates = ();
    my %sn_node = ();
    my %host_ip = ();
    ############################
    # Cache vpd table
    ############################
    my $vpdtab  = undef;
    $vpdtab = xCAT::Table->new('vpd');
    if ($vpdtab)
    {
        my @ents=$vpdtab->getAllNodeAttribs(['serial','mtm']);
        for my $ent ( @ents)
        {
            if ( $ent->{mtm} and $ent->{serial})
            {
                # if there is no BPA, or there is the second BPA, change it
                if ( ! exists $sn_node{"Server-" . $ent->{mtm} . "-SN" . $ent->{serial}} or 
                     $sn_node{"Server-" . $ent->{mtm} . "-SN" . $ent->{serial}} =~ /-2$/
                   )
                {
                    $sn_node{"Server-" . $ent->{mtm} . "-SN" . $ent->{serial}} = $ent->{node};
                }
            }
        }
    }

    foreach ( keys %$outhash ) {
        my $data = $outhash->{$_};
        my $type = @$data[0];
        my $nameips = @$data[4];
        my ($name,$ips);
        if ( $nameips =~ /^([^\(]+)\(([^\)]+)\)$/)
        {
            $name = $1;
            $ips  = $2;
            $host_ip{$name} = $ips;
        }

        if ( $type =~ /^BPA$/ ) {
            my $model  = @$data[1];
            my $serial = @$data[2];
            $ips    = @$data[3] if ( !$ips);
            $name   = @$data[4] if ( !$name);
            my $id     = @$data[6];

            ####################################
            # N/A Values
            ####################################
            my $prof  = "";
            my $frame = "";

            my $values = join( ",",
               lc($type),$name,$id,$model,$serial,$name,$prof,$frame,$ips );
            xCAT::PPCdb::add_ppc( lc($type), [$values],1 );
        }
        elsif ( $type =~ /^(HMC|IVM)$/ ) {
            xCAT::PPCdb::add_ppchcp( lc($type), $name,1 );
        }
        elsif ( $type =~ /^FSP$/ ) {
            ########################################
            # BPA frame this CEC is in
            ########################################
            my $frame      = "";
            my $model      = @$data[1];
            my $serial     = @$data[2];
            $ips        = @$data[3] if ( !$ips);
            $name       = @$data[4] if ( !$name);
            my $bpc_model  = @$data[6];
            my $bpc_serial = @$data[7];
            my $cageid     = @$data[8];

            ############################################################
            # For HE machine, there are 2 FSPs, but only one FSP have the 
            # BPA information. We need to go through the outhash and
            # find its BPA
            ############################################################
            if (($bpc_model eq "0" ) and ( $bpc_serial eq "0" )) 
            {
                for my $he_node ( keys %$outhash )
                {
                    if ( $model eq $outhash->{$he_node}->[1] and
                         $serial eq $outhash->{$he_node}->[2] and
                         $outhash->{$he_node}->[6] and
                         $outhash->{$he_node}->[7]
                        )
                    {
                        $bpc_model = $outhash->{$he_node}->[6];
                        $bpc_serial = $outhash->{$he_node}->[7];
                        $cageid = $outhash->{$he_node}->[8];
                    }
                }
            }

            ########################################
            # May be no Frame with this FSP
            ########################################
            if (( $bpc_model ne "0" ) and ( $bpc_serial ne "0" )) {
                if ( exists $sn_node{"Server-$bpc_model-SN$bpc_serial"})
                {
                    $frame = $sn_node{"Server-$bpc_model-SN$bpc_serial"};
                }
                else
                {
                    $frame = "Server-$bpc_model-SN$bpc_serial";
                }
            }

            ########################################
            # "Factory-default" FSP name format:
            # Server-<type>-<model>-<serialnumber>
            # ie. Server-9117-MMA-SN10F6F3D
            #
            # If the IP address cannot be converted
            # to a shirt-hostname use the following:
            #
            # Note that this may not be the name
            # that the user (or the HMC) knows this
            # CEC as. This is the "factory-default"
            # CEC name. SLP does not return the
            # user- or system-defined CEC name and
            # FSPs are assigned dynamic hostnames
            # by DHCP so there is no point in using
            # the short-hostname as the name.
            ########################################
            if ( $name =~ /^[\d]{1}/ ) {
                $name = "Server-$model-$serial";
            }
            ########################################
            # N/A Values
            ########################################
            my $prof   = "";
            my $server = "";

            my $values = join( ",",
               lc($type),$name,$cageid,$model,$serial,$name,$prof,$frame,$ips );
            xCAT::PPCdb::add_ppc( "fsp", [$values],1 );
        }
        elsif ( $type =~ /^(RSA|MM)$/ ) {
            xCAT::PPCdb::add_systemX( $type, $data );
        }
    }
    xCAT::Utils::updateEtcHosts(\%host_ip);
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
    foreach ( keys %$outhash ) {
        my @data = @{$outhash->{$_}};
        my $type = lc($data[0]);
        my $name = $data[4];
        my $i = 0;

        #################################
        # Node attributes
        #################################
        $result .= "$name:\n\tobjtype=node\n";

        #################################
        # Add each attribute
        #################################
        foreach ( @attribs ) {
            my $d = $data[$i++];

            if ( /^node$/ ) {
                next;
            } elsif ( /^nodetype$/ ) {
                $d = $type;
            } elsif ( /^groups$/ ) {
                $d = "$type,all";
            } elsif ( /^mgt$/ ) {
                $d = $mgt{$type};
            } elsif ( /^(id|mpa)$/ ) {
                if ( $type =~ /^(mm|rsa)$/ ) {
                    $d = (/^id$/) ? "0" : $name;
                } else {
                    next;
                }
            }
            $result .= "\t$_=$d\n";
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
    foreach ( keys %$outhash ) {
        my @data = @{ $outhash->{$_}};
        my $type = lc($data[0]);
        my $name = $data[4];
        my $i = 0;

        #################################
        # Initialize hash reference
        #################################
        my $href = {
            Node => { }
        };
        #################################
        # Add each attribute
        #################################
        foreach ( @attribs ) {
            my $d = $data[$i++];

            if ( /^nodetype$/ ) {
                $d = $type;
            } elsif ( /^groups$/ ) {
                $d = "$type,all";
            } elsif ( /^mgt$/ ) {
                $d = $mgt{$type};
            } elsif ( /^(id|mpa)$/ ) {
                if ( $type =~ /^(mm|rsa)$/ ) {
                    $d = (/^id$/) ? "0" : $name;
                } else {
                    next;
                }
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
                shift @$responses;
                foreach ( keys %$responses ) {
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
	    if ($_->{servicenode}) {$sv_hash{$_->{servicenode}}=1;}
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
# Match SLP IP/ARP MAC/Switch table port to actual switch data
##########################################################################
sub switch_cmd {

    my $req = shift;
    my $slp = shift;
    my $slp_all = undef;
    my %hosts;
    my @entries;
    my $targets = {};
    my $hosttab  = xCAT::Table->new( 'hosts' );
    my $swtab    = xCAT::Table->new( 'switch' );

    ###########################################
    # No tables
    ###########################################
    if ( !defined($swtab)) {
    #if ( !defined($swtab) or !defined($hosttab) ) {
        return;
    }
    ###########################################
    # Any MMs/HMCs/FSPs/BPAs in SLP response
    ###########################################
    foreach my $slp_entry ( @$slp ) {
        my $slp_hash = get_slp_attr( $slp_entry);
        $slp_all->{$slp_hash->{'ip-address'}} = $slp_hash if ($slp_hash);
    }
    ###########################################
    # No MMs/HMCs/FSPs/BPAs in response
    ###########################################
    if ( !$slp_all ) {
        return;
    }

    ###########################################
    # Any entries in switch table
    ###########################################
    foreach ( $swtab->getAllNodeAttribs([qw(node)]) ) {
        push @entries, $_->{node};
    }
    ###########################################
    # Any entries in hosts table
    ###########################################
    if ( $verbose ) {
        trace( $req, "SWITCH/HOSTS TABLE:" );
    }
    if ( $opt{u})
    {
        foreach my $nodename ( @entries ) {
            my $ent = undef;
            if ( $hosttab)
            {
                my $enthash = $hosttab->getNodeAttribs( $nodename,[qw(ip)]);
                $ent = $enthash->{ip};
            }
            if (!$ent)
            {
                my $net_bin = inet_aton($nodename);
                $ent = inet_ntoa($net_bin) if ($net_bin);
            }

            if ( !$ent ) {
                next;
            }

            $hosts{ $nodename} = $ent;
            if ( $verbose ) {
                trace( $req, "\t\t($nodename)->($ent)" );
            }
        }
        ###########################################
        # No MMs/HMCs in hosts/switch table
        ###########################################
        if ( !%hosts ) {
            return undef;
        }
    }
    ###########################################
    # Ping each MM/HMCs to update arp table
    ###########################################
    my %internal_ping_catch;
    foreach my $ips ( keys %$slp_all ) {
        my @all_ips = split /,/, $ips;
        my $rc = 0;
        for my $single_ip (@all_ips)
        {
            my $rc;
            if ( exists $internal_ping_catch{ $single_ip})
            {
                 $rc = $internal_ping_catch{ $single_ip};
            }
            else
            {
                trace ($req, "Trying ping $single_ip");
                #$rc = system("ping -c 1 -w 1 $single_ip 2>/dev/null 1>/dev/null");
                my $res = `LANG=C ping -c 1 -w 1 $single_ip 2>&1`;
                if ( $res =~ /100% packet loss/g)
                { 
                    $rc = 1;
                }
                else
                {
                    $rc = 0;
                }
		#$rc = $?;
                $internal_ping_catch{ $single_ip} = $rc;
            }
            if ( !$rc )
            {
                $slp_all->{$single_ip} = $slp_all->{ $ips};
                delete $slp_all->{ $ips};
                last;
            }
        }
        if ( $rc)
        {
            trace( $req, "Cannot ping any IP of $ips, it's because the network is too slow?");
            delete $slp_all->{ $ips};
        }
    }
    ###########################################
    # Match discovered IP to MAC in arp table
    ###########################################
    return undef if ( ! scalar( keys %$slp_all));
    my $arp;
    if ( $^O eq 'aix')
    {
        $arp = `/usr/sbin/arp -a`;
    }
    else
    {
        $arp = `/sbin/arp -n`;
    }

    my @arpents = split /\n/, $arp;

    if ( $verbose ) {
        trace( $req, "ARP TABLE:" );
    }
    my $isMacFound = 0;
    foreach my $arpent ( @arpents ) {
        my ($ip, $mac);
        if ( $^O eq 'aix' && $arpent =~ /\((\S+)\)\s+at\s+(\S+)/)
        {
            ($ip, $mac) = ($1,$2);
            ######################################################
            # Change mac format to be same as linux. For example:
            # '0:d:60:f4:f8:22' to '00:0d:60:f4:f8:22'
            ######################################################
            if ( $mac)
            {
                my @mac_sections = split /:/, $mac;
                for (@mac_sections)
                {
                    $_ = "0$_" if ( length($_) == 1);
                }
                $mac = join ':', @mac_sections;
            }
        }
        elsif ( $arpent =~ /^(\S+)+\s+\S+\s+(\S+)\s/)
        {
            ($ip, $mac) = ($1,$2);
        }
        else
        {
             ($ip, $mac) = (undef,undef);
        }
        if ( exists( $slp_all->{$ip} )) {
            if ( $verbose ) {
                trace( $req, "\t\t($ip)->($mac)" );
            }
            $slp_all->{$ip}->{'mac'} = $mac;
            $isMacFound = 1;
        }
    }
    ###########################################
    # No discovered IP - MAC matches
    ###########################################
    if ( ! $isMacFound) {
        return;
    }
    if ( $verbose ) {
        trace( $req, "getting switch information...." );
    }
    foreach my $ip ( sort keys %$slp_all ) {
        #######################################
        # Not in SLP response
        #######################################
        if ( !defined( $slp_all->{$ip}->{'mac'} ) or !defined( $macmap )) {
            next;
        }
        #######################################
        # Get node from switch
        #######################################
        my $names = $macmap->find_mac( $slp_all->{$ip}->{'mac'} );
        if ( !defined( $names )) {
            if ( $verbose ) {
                trace( $req, "\t\t($slp_all->{$ip}->{'mac'})-> NOT FOUND" );
            }
            next;
        }
        
        #######################################
        # Identify multiple nodes
        #######################################
        my $name;
        if ( $names =~/,/ ) {
            $name = disti_multi_node( $req, $names, $slp_all->{$ip});
            if ( ! $name)
            {
                trace( $req, "\t\tCannot identify node $ip.");
                next;
            }
            
        }
        else
        {
            $name = $names;
        }
        if ( $verbose ) {
            trace( $req, "\t\t($slp_all->{$ip}->{'mac'})-> $name" );
        }
        #######################################
        # In hosts table
        #######################################
        if ( $opt{u})
        {
            if ( defined( $hosts{$name} )) {
                if ( $ip eq $hosts{$name} ) {
                    if ( $verbose ) {
                        trace( $req, "\t\t\t$slp_all->{$ip}->{'type'} already set '$ip' - skipping" );

                    }
                }
                else
                {
                    $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'args'} = "$hosts{$name},$name";
                    if ( $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'type'} ne 'MM')
                    {
                        my %netinfo = xCAT::DBobjUtils->getNetwkInfo([$hosts{$name}]);
                        $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'args'} .= ",$netinfo{$hosts{$name}}{'gateway'},$netinfo{$hosts{$name}}{'mask'}";
                    }
                    $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'mac'}  = $slp_all->{$ip}->{'mac'};
                    $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'name'} = $name;
                    $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'ip'}   = $hosts{$name};
                    $targets->{$slp_all->{$ip}->{'type'}}->{$ip}->{'type'} = $slp_all->{$ip}->{'type'};
                }
            }
        }
        else 
        {
            #An tentative solution. The final solution should be
            #if there is any conflicting, remove this entry
            $hosts{$name} = $ip if ( ! $hosts{$name});
        }
    }
    ###########################################
    # No rspconfig target found
    ###########################################
    if (( $opt{u} and !%$targets) or ( $opt{H} and !%hosts)) {
        if ( $verbose ) {
            trace( $req, "No ARP-Switch-SLP matches found" );
        }
        return undef;
    }
    ###########################################
    # Update target hardware w/discovery info
    ###########################################
    return rspconfig( $req, $targets ) if ($opt{u});
    ###########################################
    # Update hosts table
    ###########################################
     send_msg( $req, 0, "Updating hosts table...");
    return update_hosts( $req, \%hosts);
}

###########################################
# Update hosts table
###########################################
sub update_hosts
{
    my $req = shift;
    my $hosts = shift;
    my $hoststab = xCAT::Table->new( 'hosts', -create=>1, -autocommit=>0 );
    if ( !$hoststab)
    {
        send_msg( $req, 1,  "Cannot open hosts table");
        return undef;
    }
    for my $node (keys %$hosts)
    {
        send_msg( $req, 0, "\t$node => $hosts->{$node}");
        $hoststab->setNodeAttribs( $node, {ip=>$hosts->{$node}});
    }
    $hoststab->commit;
    return SUCCESS;
}
##########################################################################
# Distinguish 
##########################################################################
sub disti_multi_node
{
    my $req = shift;
    my $names = shift;
    my $slp = shift;

    return undef if ( $slp->{'type'} eq 'FSP' and ! exists $slp->{'cage-number'});    
    return undef if ( $slp->{'type'} eq 'BPA' and ! exists $slp->{'frame-number'});

    my $ppctab = xCAT::Table->new( 'ppc');
    return undef if ( ! $ppctab);
    my $nodetypetab = xCAT::Table->new( 'nodetype');
    return undef if ( ! $nodetypetab);

    my $vpdtab = xCAT::Table->new( 'vpd');
    my @nodes = split /,/, $names;
    my $correct_node = undef;
    for my $node ( @nodes)
    {
        my $id_parent = $ppctab->getNodeAttribs( $node, ['id','parent']);
        next if (! defined $id_parent or ! exists $id_parent->{'id'});
        my $nodetype = $nodetypetab->getNodeAttribs($node, ['nodetype']);
	next if (! defined $nodetype or ! exists $nodetype->{'nodetype'});
        next if ( $nodetype->{'nodetype'} ne lc($slp->{type}));
        if ( ($nodetype->{'nodetype'} eq 'fsp' and $id_parent->{'id'} eq $slp->{'cage-number'}) or
             ($nodetype->{'nodetype'} eq 'bpa' and $id_parent->{'id'} eq $slp->{
 'frame-number'}))
        {
            my $vpdnode = undef;
            if ( defined $id_parent->{ 'parent'})#if no parent defined, take it as is.  
            {
                if( $vpdtab
                        and $vpdnode = $vpdtab->getNodeAttribs($id_parent->{ 'parent'}, ['serial','mtm'])
                        and exists $vpdnode->{'serial'}
                        and exists $vpdnode->{'mtm'})
                {
                    if ( $vpdnode->{'serial'} ne $slp->{'bpc-serial-number'} 
                            or $vpdnode->{'mtm'} ne $slp->{'bpc-machinetype-model'})
                    {
                        next;
                    }
                }
                elsif ( "$slp->{'bpc-machinetype-model'}*$slp->{'bpc-serial-number'}" ne $id_parent->{ 'parent'})
                {
                    next;
                }
                    
            }
            return undef if ( $correct_node);#had matched another node before
            $correct_node = $node;
        }
    }
    return $correct_node;    
}
##########################################################################
# Run rspconfig against targets
##########################################################################
sub get_slp_attr
{
    my $slp_entry = shift;
    my $slp_hash  = undef;

    $slp_entry =~ s/^[^\(]*?\((.*)\)[^\)]*?$/$1/;
    
    my @entries = split /\),\(/, $slp_entry;
    for my $entry ( @entries)
    {
        if ( $entry =~ /^(.+?)=(.*)$/)
        {
            $slp_hash->{$1} = $2;
        }
    }
    
    if ( $slp_hash->{'type'})
    {
        $slp_hash->{'type'} = 'MM'  if ($slp_hash->{'type'} eq SERVICE_MM);
        $slp_hash->{'type'} = 'FSP' if ($slp_hash->{'type'} eq SERVICE_FSP);
        $slp_hash->{'type'} = 'BPA' if ($slp_hash->{'type'} eq SERVICE_BPA);
        $slp_hash->{'type'} = 'HMC' if ($slp_hash->{'type'} eq SERVICE_HMC);
    }
    
    return $slp_hash;
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

    foreach my $ip ( keys %rsp_result ) {
        #################################
        # Error logging on to MM
        #################################
        my $result = $rsp_result{$ip};
        my $Rc = shift(@$result);

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
    ######################################
    # Update etc/hosts
    ######################################
    my $fname = "/etc/hosts";
    if ( $verbose ) {
        trace( $request, "updating /etc/hosts...." );
    }
    unless ( open( HOSTS,"<$fname" )) {
        if ( $verbose ) {
            trace( $request, "Error opening '$fname'" );
        }
        return( \%rsp_dev );
    }
    my @rawdata = <HOSTS>;
    close( HOSTS );

    ######################################
    # Remove old entry
    ######################################
    foreach ( keys %rsp_dev) {
        my ($ip,$host) = split /,/,$rsp_dev{$_}->{args};
        foreach ( @rawdata ) {
            if ( /^#/ or /^\s*\n$/ ) {
                next;
            } elsif ( /\s+$host\s+$/ ) {
                s/$_//;
            }
        }
        push @rawdata,"$ip\t$host\n";
    }
    ######################################
    # Rewrite file
    ######################################
    unless ( open( HOSTS,">$fname" )) {
        if ( $verbose ) {
            trace( $request, "Error opening '$fname'" );
        }
        return( \%rsp_dev );
    }
    print HOSTS @rawdata;
    close( HOSTS );
    return( \%rsp_dev );
}

#############################################
# Get rsp devices and their logon info
#############################################
sub get_rsp_dev
{
    my $request = shift;
    my $targets = shift;

    my $mm  = $targets->{'MM'}  ? $targets->{'MM'} : {};
    my $hmc = $targets->{'HMC'} ? $targets->{'HMC'}: {};
    my $fsp = $targets->{'FSP'} ? $targets->{'FSP'}: {};
    my $bpa = $targets->{'BPA'} ? $targets->{'BPA'}: {};

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
            ( $hmc->{$_}->{username}, $hmc->{$_}->{password}) = xCAT::PPCdb::credentials( $_, lc($hmc->{$_}->{'type'})); 
            trace( $request, "user/passwd for $_ is $hmc->{$_}->{username} $hmc->{$_}->{password}");
        }
    }

    if ( %$fsp)
    {
        #############################################
        # Get FSP userid/password
        #############################################
        foreach ( keys %$fsp ) {
            ( $fsp->{$_}->{username}, $fsp->{$_}->{password}) = xCAT::PPCdb::credentials( $_, lc($fsp->{$_}->{'type'})); 
            trace( $request, "user/passwd for $_ is $fsp->{$_}->{username} $fsp->{$_}->{password}");
        }
    }

    if ( %$bpa)
    {
        #############################################
        # Get BPA userid/password
        #############################################
        foreach ( keys %$bpa ) {
            ( $bpa->{$_}->{username}, $bpa->{$_}->{password}) = xCAT::PPCdb::credentials( $_, lc($bpa->{$_}->{'type'})); 
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
    ###########################################
    # SLP service-request - select program
    ###########################################
    $result = $openSLP ? slptool( \%request ) : slp_query( \%request );
    my $Rc  = shift(@$result);

    return( $Rc );
}


1;







