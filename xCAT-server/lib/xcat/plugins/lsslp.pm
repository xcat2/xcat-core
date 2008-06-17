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
if ($^O =~ /^linux/i) {
 $XML::Simple::PREFERRED_PARSER='XML::Parser';
}
use xCAT::PPCdb;

#######################################
# Perl::SNMP not working on AIX yet
#######################################
if ($^O =~ /^linux/i) {
  eval { require xCAT::MacMap };
  eval { require xCAT_plugin::blade };
}


#######################################
# Constants
#######################################
use constant {
    HARDWARE_SERVICE => "service:management-hardware.IBM",
    SOFTWARE_SERVICE => "service:management-software.IBM",
    WILDCARD_SERVICE => "service:management-*.IBM:",
    SERVICE_FSP      => "cec-service-processor",
    SERVICE_BPA      => "bulk-power-controller",
    SERVICE_HMC      => "hardware-management-console",
    SERVICE_IVM      => "integrated-virtualization-manager",
    SERVICE_MM       => "management-module",
    SERVICE_RSA      => "remote-supervisor-adapter",
    TYPE_MM          => "MM",
    TYPE_RSA         => "RSA",
    TYPE_BPA         => "BPA",
    TYPE_HMC         => "HMC",
    TYPE_IVM         => "IVM",
    TYPE_FSP         => "IVM",
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
    @{[ SERVICE_FSP ]} => TYPE_FSP,
    @{[ SERVICE_BPA ]} => TYPE_BPA,
    @{[ SERVICE_HMC ]} => TYPE_HMC,
    @{[ SERVICE_IVM ]} => TYPE_IVM,
    @{[ SERVICE_MM  ]} => TYPE_MM,
    @{[ SERVICE_RSA ]} => TYPE_RSA 
);

#######################################
# Basic SLP attributes
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
my $macmap;


##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {

    if ($^O =~ /^linux/i) {
        $macmap = xCAT::MacMap->new();
    } 
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
    my @VERSION  = qw( 2.0 );
    my %services = (
        HMC => SOFTWARE_SERVICE.":".SERVICE_HMC.":",
        IVM => SOFTWARE_SERVICE.":".SERVICE_IVM.":",
        BPA => HARDWARE_SERVICE.":".SERVICE_BPA,
        FSP => HARDWARE_SERVICE.":".SERVICE_FSP,
        RSA => HARDWARE_SERVICE.":".SERVICE_RSA.":",
        MM  => HARDWARE_SERVICE.":".SERVICE_MM.":" 
    );
    my $types = join( "|", keys %services );
    my $args  = $request->{arg};

    #############################################
    # Responds with usage statement                   
    #############################################
    local *usage = sub {
        my @msg = ( $_[0],
          "lsslp  -h|--help",
          "lsslp  -v]--version",
          "lsslp [-V|--verbose][-b ip[,ip..]][-w][-r|-x|-z][-s $types]",
          "    -b   IP(s) the command will broadcast out.",
          "    -h   writes usage information to standard output.",
          "    -r   raw slp response.",
          "    -s   service type interested in discovering.",
          "    -v   command version.",
          "    -V   verbose output.",
          "    -w   writes output to xCat database.",
          "    -x   xml formatted output.",
          "    -z   stanza formatted output.");
        send_msg( $request, 1, @msg );
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
    if (!GetOptions(\%opt, qw(h|help V|Verbose v|version b=s x z w r s=s))) { 
        usage();
        return(1);
    }
    #############################################
    # Option -h for Help
    #############################################
    if ( exists( $opt{h} )) {
        usage();
        return(1);
    }
    #############################################
    # Option -v for version
    #############################################
    if ( exists( $opt{v} )) {
        send_msg( $request, 0, @VERSION );
        return(1);
    }
    #############################################
    # Check for switch "-" with no option
    #############################################
    if ( grep(/^-$/, @ARGV )) {
        usage( "Missing option: -" );
        return(1);
    }
    #############################################
    # Check for an argument
    #############################################
    if ( defined( $ARGV[0] )) {
        usage( "Invalid Argument: $ARGV[0]" );
        return(1);
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
        usage();
        return(1);
    }
    #############################################
    # Check for unsupported service type 
    #############################################
    if ( exists( $opt{s} )) {
        if ( !exists( $services{$opt{s}} )) {
            usage( "Invalid service: $opt{s}" );
            return(1);
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
    # Option -b specified - validate entries 
    ###########################################
    if ( exists( $opt{b} )) {
        foreach ( split /,/, $opt{b} ) {
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
    }
    ###########################################
    # Option -b not specified - determine IPs 
    ###########################################
    else {
        my $result = ifconfig( $request );

        ###########################
        # Command failed 
        ###########################
        if ( @$result[0] ) {
            return( $result );
        }
        if ( (keys %ip_addr) == 0 ) {
            return( [1,"No adapters configured for broadcast"] );
        }
    }
    return( [0] );
}


##########################################################################
# Determine adapters available for broadcast
##########################################################################
sub ifconfig {
    
    my $request = shift;
    my $cmd     = "ifconfig -a";
    my $result  = `$cmd`;

    ######################################
    # Error running command
    ######################################
    if ( !$result ) {
        return( [1, "Error running '$cmd': $!"] );
    }
    if ( $verbose ) {
        trace( $request, $cmd );
        trace( $request, "Broadcast Interfaces:" );
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
                   $_ =~ /BROADCAST/ ) {

                my @ip = split /\n/;
                foreach ( @ip ){
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
                   $_ =~ /BROADCAST / ) {

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
# Forks a process to run the slp command (1 per broadcast adapter) 
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
    my $converge = 1;
    my $tries    = 5;

    ########################################
    # Telnet (rspconfig) command  
    ########################################
    if ( !defined( $services )) {
        my $mm = $args->{$ip};
        my @cmds = (
            "snmpcfg=enable",
            "sshcfg=enable",
            "network_reset=$mm->{args}"
        );
        if ( $verbose ) {
            trace( $request, "Forked: ($ip)->($mm->{args})" );
        }
        my $result = xCAT_plugin::blade::telnetcmds(
                          $ip,
                          $mm->{username},
                          $mm->{password},
                          0,
                          @cmds );
 
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
    # SLP broadcast command  
    ########################################
    my $result = runslp($args, $ip, $services, $request, $tries, $converge);
    my $unicast = @$result[0];
    my $values  = @$result[1];

    ########################################
    # May have to send additional unicasts  
    ########################################
    if ( keys (%$unicast) )  { 
        foreach my $url ( keys %$unicast ) {
            my ($service,$addr) = split "://", $url;
            my $sockaddr = inet_aton( $addr );

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
            $result = runslp( $args, $addr, [$service], $request, 1 );
            my $data  = @$result[1];
            my ($key) = keys %$data;

            if ( defined($key) ) {
                $values->{"URL: $url\n$data->{$key}\n"} = 1;
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



##########################################################################
# Run the SLP command, process the response, and send to parent  
##########################################################################
sub runslp {

    my $slpcmd   = shift;
    my $ip       = shift;
    my $services = shift;
    my $request  = shift;
    my $max      = shift;
    my $converge = shift;
    my %result   = ();
    my %unicast  = ();

    foreach my $type ( @$services ) {
        my $try = 0;
        my $cmd = "$slpcmd --address=$ip --type=$type";

        ###############################################
        # If --converge is specified, slp_query will
        # broadcast a service-request to the broadcast
        # address specified by --address. If not
        # specified, slp_query will unicast an attribute
        # request to the URL specified by --type to  
        # the remote target specified by --address.
        ###############################################
        if ( defined($converge) ) {
            $cmd .= " --converge=$converge";
        }
        while ( $try++ < $max ) {
            if ( $verbose ) {
                trace( $request, $cmd );
                trace( $request, "Attempt $try of $max\t( $ip\t$type )" );
            }
            ###########################################
            # Serialize broadcasts out each adapter 
            ###########################################
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
            # split into array of individual responses:
            # 0
            # 1
            # 75
            # URL: service:management-software.IBM...
            # ATTR: (type=hardware-management-cons...
            # (serial-number=KPHHK24),(name=c76v2h...
            # 1ab1dd89ca8e0763e),(ip-address=192.1...
            # 0CR3*KPHHK24),(web-management-interf...
            # 2.ppd.pok.ibm.com:8443),(cimom-port=...
            #
            # 0
            # 1
            # 69
            # URL: 
            # ATTR:
            # ...
            #
            # For IVM, running AIX 53J (6/07) release,
            # there is an AIX SLP bug where IVM will 
            # respond to SLP broadcasts with its URL
            # only and not its attributes. An SLP
            # unicast to the URL address is necessary  
            # to acquire the attributes. This was fixed 
            # in AIX 53L (11/07).
            #
            ###########################################
            foreach ( split /\n{2,}/,$rsp ) {
                if ( $_ =~ s/(\d+)\n(\d+)\n(\d+)\n// ) {
                    if ( $verbose ) {
                        trace( $request, "SrvRqst Response ($1)($2)($3)" );
                        trace( $request, "$_\n" );
                    }
                    ###################################
                    # Response has "ATTR" field 
                    ###################################
                    if ( /ATTR: /  ) {
                        $result{$_} = 1;
                    }
                    ###################################
                    # No "ATTR" - have to unicast
                    ###################################
                    elsif ( /.*URL: (.*)/ ) {
                        $unicast{$1} = $1;
                    }
                } elsif ( $verbose ) {
                    trace( $request, "DISCARDING: $_" );
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
    my $rsp     = shift;
    my $length  = length( $header[IP_ADDRESSES][TEXT] );
    my $result;

    ###########################################
    # Query switch ports
    ###########################################
    my $mm = switch_cmd( $request, $values );

    ###########################################
    # Parse responses and add to hash
    ###########################################
    my $outhash = parse_responses( $request, $values, $mm, \$length );

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
    my $url     = shift;

    #######################################
    # Extract IP from URL 
    #######################################
    my $ip = getip_from_url( $request, $url );
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
    # Convert IP to hostname
    #######################################
    my $host = gethostbyaddr( $packed, AF_INET );
    if ( !$host or $! ) {
        return( $ip );
    }
    #######################################
    # Convert hostname to short-hostname
    #######################################
    if ( $host =~ /([^\.]+)\./ ) {
        $host = $1;
    }
    return( $host );
  
    ###########################################
    #  Otherwise, URL is not in IP format
    ###########################################
    if ( !($url =~ /service:.*:\/\/(.*)/  )) {
        if ( $verbose ) {
            trace( $request, "Invalid URL: $_[0]" );
        }
        return undef;
    }
    return( $1 );

}


##########################################################################
# Example slp_query command "service-request" output. The following 
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
# Example slp_query command "attribute-request" output. The following 
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
    my @attr    = (
       "type",
       "machinetype-model",
       "serial-number",
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
        if ( $rsp !~ /\(type=([\w\-\.,]+)\)/ ) {
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
        if (( $type eq SERVICE_RSA ) or ( $type eq SERVICE_MM )) {
            $attr[1] = "enclosure-machinetype-model";
            $attr[2] = "enclosure-serial-number";
        }

        ###########################################
        # Extract the attributes
        ###########################################
        foreach ( @attr ) {
            $rsp =~ /\($_=([\w\-\.,]+)\)/; 
            push @result, $1;
        }
        ###########################################
        # Use the IP/Hostname contained in the URL
        # not the (ip-address) field since for FSPs
        # it may contain default IPs which could  
        # all be the same. If the response contains 
        # a "name" attribute as the HMC does, use
        # that instead of the URL.
        #
        ###########################################
        if (( $type eq SERVICE_HMC ) or ( $type eq SERVICE_IVM )) {
            if ( $rsp =~ /\(name=([\w\-\.,]+)\)/ ) {
                $host = $1;

                ###################################
                # Convert to short-hostname
                ###################################
                if ( $host =~ /([^\.]+)\./ ) {
                    $host = $1;
                }
            }
        }
        ###########################################
        # Seperate ATTR and URL portions:
        # 0
        # 1
        # 75
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
        if (( $type eq SERVICE_MM ) and ( defined( $mm ))) {
            my $ip = getip_from_url( $request, $1 );

            if ( defined( $ip )) {
                if ( exists( $mm->{$ip}->{args} )) {
                    $mm->{$ip}->{args} =~ /^.*,(.*)$/; 
                    $host = $1;
                }
            }   
        }
        ###########################################
        # Get host directly from URL
        ###########################################
        if ( !defined($host) ) {
            $host = gethost_from_url( $request, $1 );
            if ( !defined( $host )) {
                next;
            }
        }
        push @result, $host;
        push @result, $2;

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
    return( \%outhash );
}



##########################################################################
# Write result to xCat database 
##########################################################################
sub xCATdB {

    my $outhash = shift;
    my %keyhash = ();
    my %updates = ();
  
    foreach ( keys %$outhash ) {
        my $data = $outhash->{$_};
        my $type = @$data[0];

        if ( $type =~ /^BPA$/ ) {
            my $model  = @$data[1];
            my $serial = @$data[2];
            my $ips    = @$data[3];
            my $name   = @$data[4];
            my $id     = @$data[6];

            ####################################
            # N/A Values
            ####################################
            my $prof  = "";
            my $frame = "";

            my $values = join( ",",
               lc($type),$name,$id,$model,$serial,$name,$prof,$frame,$ips );
            xCAT::PPCdb::add_ppc( $type, [$values] );
        }
        elsif ( $type =~ /^(HMC|IVM)$/ ) {
            xCAT::PPCdb::add_ppchcp( $type, $data );
        }
        elsif ( $type =~ /^FSP$/ ) {
            ########################################
            # BPA frame this CEC is in 
            ########################################
            my $frame      = "";
            my $model      = @$data[1];
            my $serial     = @$data[2];
            my $ips        = @$data[3];
            my $name       = @$data[4];
            my $bpc_model  = @$data[6];
            my $bpc_serial = @$data[7];
            my $cageid     = @$data[8];

            ########################################
            # May be no Frame with this FSP
            ########################################
            if (( $bpc_model ne "0" ) and ( $bpc_serial ne "0" )) {
                $frame = "$bpc_model*$bpc_serial";
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
               $type,$name,$cageid,$model,$serial,$server,$prof,$frame,$ips );
            xCAT::PPCdb::add_ppc( "fsp", [$values] );
        }
        elsif ( $type =~ /^(RSA|MM)$/ ) {
            xCAT::PPCdb::add_systemX( $type, $data );
        }
    }
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
# OpenSLP is running on:
#     p6 FSP
#     p6 BPA
# IBM SLP is running on:
#     p5 FSP
#     p5 BPA
#     HMC
#     MM
#     RSA
# AIX SLP
#     IVM
#
# OpenSLP v. IBM SLP
# (1) OpenSLP does not support wildcards (i.e. service:management-*.IBM: )
# (2) OpenSLP does not support ':' at the end of services
#     (i.e. service:management-hardware.IBM:). Unfortunately, IBM SLP
#     requires it.
#
# Given the above, to collect all the above service types, it is 
# necesary to broadcast:
# (1) service:management-*.IBM: for all IBM SLP hardware
# (2) service:management-hardware.IBM for OpenSLP hardware (p6 FSP/BPA)
#      (IBM SLP hardware will not respond since there is no trailing ":")
# (3) IBM SLP does not require a trailing ':' with "cec-service-processor"
#     concrete type only.
#
##########################################################################
sub slp_query {

    my $request  = shift;
    my $callback = $request->{callback};
    my $slpcmd   = "/usr/sbin/slp_query";
    my $start;
    my @services = (
        HARDWARE_SERVICE,
        WILDCARD_SERVICE
    );

    #############################################
    # slp_query not installed   
    #############################################
    if ( !-x $slpcmd ) {
        send_msg( $request, 1, "Command not installed: $slpcmd" );
        return( [RC_ERROR] );
    }
    #############################################
    # slp_query runnable - dependent on libstdc++ 
    # Test for usage statement.
    #############################################
    my $output = `$slpcmd 2>&1`;
    if ( $output !~ /slp_query --type=service-type-string/ ) {
        send_msg( $request, 1, $output );
        return( [RC_ERROR] );
    }
    #############################################
    # Query specific service; otherwise, 
    # query all hardware/software services
    #############################################
    if ( exists( $opt{s} )) {
        @services = $request->{service};
    }

    if ( $verbose ) {
        #########################################
        # Write header for trace
        #########################################
        my $tm  = localtime( time );
        my $msg = "\n--------  $tm\nTime     PID";
        trace( $request, $msg );
    }
    #############################################
    # Get/validate broadcast IPs
    #############################################
    my $result = validate_ip( $request );
    my $Rc = shift(@$result);

    if ( $Rc ) {
        send_msg( $request, 1, @$result[0] );
        return( [RC_ERROR] );
    }
    if ( $verbose ) {
        $start = Time::HiRes::gettimeofday(); 
    }
    #############################################
    # Fork one process per broadcast adapter 
    #############################################
    my $children = 0;
    $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
    my $fds = new IO::Select;
    
    foreach ( keys %ip_addr ) {
        my $pipe = fork_cmd( $request, $_, $slpcmd, \@services );
        if ( $pipe ) {
            $fds->add( $pipe );
            $children++;
        }
    }
    #############################################
    # Process slp responses from children 
    #############################################
    while ( $children > 0 ) {
        child_response( $callback, $fds );
    }
    while (child_response($callback,$fds)) {}

    if ( $verbose ) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $msg = sprintf( "Total SLP Time: %.3f sec\n", $elapsed );
        trace( $request, $msg ); 
    }
    #############################################
    # Combined responses from all children 
    #############################################
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
    my $cb  = shift;
    if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed

    ###########################################
    # Parse command-line options
    ###########################################
    my %request;
    $request{arg} = $req->{arg};
    $request{callback} = $cb;
    if ( parse_args( \%request )) {
        return(1);
    }

    ###########################################
    # find all the service nodes for xCAT cluster
    # build an individual request for each service node
    ###########################################
    my $nrtab=xCAT::Table->new("noderes", -create =>0);  
    my @all=$nrtab->getAllNodeAttribs(['servicenode']);
    my %sv_hash=();
    foreach (@all) {
      if ($_->{servicenode}) {$sv_hash{$_->{servicenode}}=1;}
    }
    ###########################################
    # build each request for each service node
    ###########################################
    my @requests=();
    foreach my $sn (keys (%sv_hash)) {
      my $reqcopy = {%$req};
      $reqcopy->{_xcatdest} = $sn;
      push @requests, $reqcopy;
    }
    return \@requests;
}


##########################################################################
# Match SLP IP/ARP MAC/Switch table port to actual switch data 
##########################################################################
sub switch_cmd {

    my $req = shift;
    my $slp = shift;
    my %mm;
    my %slp;
    my %hosts;
    my @entries;
    my $hosttab  = xCAT::Table->new( 'hosts' );
    my $swtab    = xCAT::Table->new( 'switch' );

    ###########################################
    # No tables
    ###########################################
    if ( !defined($swtab) or !defined($hosttab) ) {
        return;
    }
    ###########################################
    # Any MMs in SLP response
    ###########################################
    foreach ( @$slp ) {
        if ( /\(type=management-module\)/ and /\(ip-address=([^\),]+)/) {
           $slp{$1} = undef;
        }
    }
    ###########################################
    # No MMs in response
    ###########################################
    if ( !%slp ) {
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
    foreach ( @entries ) {
        my $ent = $hosttab->getNodeAttribs($_,[qw(ip)]);
        if ( !$ent ) {
            next;
        }
        $hosts{$_} = $ent->{ip};
        if ( $verbose ) {
            trace( $req, "\t\t($_)->($ent->{ip})" );
        }
    }
    ###########################################
    # No MMs in hosts/switch table 
    ###########################################
    if ( !%hosts ) {
        return;
    }
    ###########################################
    # Ping each MM to update arp table 
    ###########################################
    foreach my $ip ( keys %slp ) {
        my $cmd = `ping -c 1 -w 0 $ip`;
    }    
    ###########################################
    # Match discovered IP to MAC in arp table
    ###########################################
    my $arp = `/sbin/arp -n`;
    my @arpents = split /\n/, $arp;

    if ( $verbose ) {
        trace( $req, "ARP TABLE:" );
    }
    foreach ( @arpents ) {
        /^(\S+)+\s+\S+\s+(\S+)\s/;
        if ( exists( $slp{$1} )) {
            if ( $verbose ) {
                trace( $req, "\t\t($1)->($2)" );
            }
            $slp{$1} = $2;
        }
    }
    ###########################################
    # No discovered IP - MAC matches 
    ###########################################
    if ( !grep( defined($_), values %slp )) {
        return;
    }
    if ( $verbose ) {
        trace( $req, "getting switch information...." );
    }
    foreach my $ip ( keys %slp ) {
        #######################################
        # Not in SLP response
        #######################################
        if ( !defined( $slp{$ip} ) or !defined( $macmap )) { 
            next;
        }
        #######################################
        # Get node from switch 
        #######################################
        my $name = $macmap->find_mac( $slp{$ip} );
        if ( !defined( $name )) {
            if ( $verbose ) {
                trace( $req, "\t\t($slp{$ip})-> NOT FOUND" ); 
            }
            next;
        }
        if ( $verbose ) {
            trace( $req, "\t\t($slp{$ip})-> $name" ); 
        }
        #######################################
        # In hosts table 
        #######################################
        if ( defined( $hosts{$name} )) {
            if ( $ip eq $hosts{$name} ) {
                if ( $verbose ) {
                    trace( $req, "MM already set '$ip' - skipping" );
                }
                next;
            }
            $mm{$ip}->{args} = "$hosts{$name},$name";
        }
    }
    ###########################################
    # No MMs   
    ###########################################
    if ( !%mm ) {
        if ( $verbose ) {
            trace( $req, "No ARP-Switch-SLP matches found" ); 
        }
        return;
    }
    ###########################################
    # Update MM hardware w/discovery info
    ###########################################
    my $result = rspconfig( $req, \%mm );
    return( $result );
}



##########################################################################
# Run rspconfig against MMs
##########################################################################
sub rspconfig {

    my $request   = shift;
    my $mm        = shift;
    my $callback  = $request->{callback};
    my $bladeuser = 'USERID';
    my $bladepass = 'PASSW0RD';
    my $start;

    if ( $verbose ) {
        trace( $request, "telneting to management-modules....." );
        $start = Time::HiRes::gettimeofday();
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
    
    #############################################
    # Fork one process per MM 
    #############################################
    my $children = 0;
    $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
    my $fds = new IO::Select;
   
    foreach my $ip ( keys %$mm ) {
        my $pipe = fork_cmd( $request, $ip, $mm );
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
                delete $mm->{$ip};
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
                    delete $mm->{$ip};
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
        return( $mm );
    } 
    my @rawdata = <HOSTS>;
    close( HOSTS );

    ######################################
    # Remove old entry 
    ######################################
    foreach ( keys %$mm) {
        my ($ip,$host) = split /,/,$mm->{$_}->{args};
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
        return( $mm );
    }
    print HOSTS @rawdata;
    close( HOSTS );
    return( $mm );
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
   
    ###########################################
    # Broadcast SLP
    ###########################################
    my $result = slp_query( \%request );

    my $Rc = shift(@$result);
    return( $Rc );
}


1;






