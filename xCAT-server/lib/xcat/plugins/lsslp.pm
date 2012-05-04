# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::lsslp;
use lib "/opt/xcat/lib/perl";
use strict;
use Getopt::Long;
use Socket;
use xCAT::Usage;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use Time::HiRes qw(gettimeofday);
use IO::Select;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use xCAT::PPCdb;
use xCAT::NodeRange;
use xCAT::Utils;


#require xCAT::MacMap;
require xCAT_plugin::blade;
require xCAT::SLP;


#######################################
# Constants
#######################################
use constant {
    HARDWARE_SERVICE => "service:management-hardware.IBM",
    SOFTWARE_SERVICE => "service:management-software.IBM",
    WILDCARD_SERVICE => "service:management-*",
    SERVICE_FSP      => "cec-service-processor",
    SERVICE_BPA      => "bulk-power-controller",
    SERVICE_CEC      => "cec-service-processor",
    SERVICE_FRAME    => "bulk-power-controller",
    SERVICE_HMC      => "hardware-management-console",
    SERVICE_IVM      => "integrated-virtualization-manager",
    SERVICE_MM       => "management-module",
    SERVICE_CMM      => "chassis-management-module",
    SERVICE_RSA      => "remote-supervisor-adapter",
    SERVICE_RSA2     => "remote-supervisor-adapter-2",
    SLP_CONF         => "/usr/local/etc/slp.conf",
    SLPTOOL          => "/usr/local/bin/slptool",
    TYPE_MM          => "mm",
    TYPE_CMM         => "cmm",
    TYPE_RSA         => "rsa",
    TYPE_BPA         => "bpa",
    TYPE_HMC         => "hmc",
    TYPE_IVM         => "ivm",
    TYPE_FSP         => "fsp",
    TYPE_CEC         => "cec",
    TYPE_FRAME       => "frame",
    IP_ADDRESSES     => 4,
    TEXT             => 0,
    FORMAT           => 1,
    SUCCESS          => 0,
    RC_ERROR         => 1,
};

#######################################
# Globals
#######################################
my %service_slp = (
    @{[ SERVICE_FSP    ]} => TYPE_FSP,
    @{[ SERVICE_BPA    ]} => TYPE_BPA,
    @{[ SERVICE_CEC    ]} => TYPE_CEC,
    @{[ SERVICE_FRAME  ]} => TYPE_FRAME,
    @{[ SERVICE_HMC    ]} => TYPE_HMC,
    @{[ SERVICE_IVM    ]} => TYPE_IVM,
    @{[ SERVICE_MM     ]} => TYPE_MM,
    @{[ SERVICE_CMM    ]} => TYPE_CMM,
    @{[ SERVICE_RSA    ]} => TYPE_RSA,
    @{[ SERVICE_RSA2   ]} => TYPE_RSA
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
my %headertoattr = (
    "device"        =>  "type",
    "type-model"    =>  "mtm",
    "serial-number" =>  "serial",
    "side"          =>  "side",
    "ip-addresses"  =>  "ip",
    "hostname"      =>  "hostname",
);

#######################################
# Invalid IP address list
#######################################
my @invalidiplist = (
        "192.168.2.144",
        "192.168.2.145",
        "192.168.2.146",
        "192.168.2.147",
        "192.168.2.148",
        "192.168.2.149",
        "192.168.3.144",
        "192.168.3.145",
        "192.168.3.146",
        "192.168.3.147",
        "192.168.3.148",
        "192.168.3.149",
        "169.254.",
        "127.0.0.0",
        "127",
        0,
        );

#######################################
# Power methods
#######################################


my %ip4neigh;
my %ip6neigh;
my %searchmacs;
my %globalopt;
#these globals are only used in mn
my %ip_addr    = ();



#my $macmap;
my @filternodes;
my $TRACE = 0;
my $DEBUG_MATCH = 0;

my %globalhwtype = (
    fsp   => $::NODETYPE_FSP,
    bpa   => $::NODETYPE_BPA,
    lpar  => $::NODETYPE_LPAR,
    hmc   => $::NODETYPE_HMC,
    ivm   => $::NODETYPE_IVM,
    frame => $::NODETYPE_FRAME,
    cec   => $::NODETYPE_CEC,
    cmm   => $::NODETYPE_CMM,
);
my %globalnodetype = (
    fsp   => $::NODETYPE_PPC,
    bpa   => $::NODETYPE_PPC,
    cec   => $::NODETYPE_PPC,
    frame => $::NODETYPE_PPC,
    hmc   => $::NODETYPE_PPC,
    ivm   => $::NODETYPE_PPC,
    cmm   => $::NODETYPE_MP,
    lpar  =>"$::NODETYPE_PPC,$::NODETYPE_OSI",
);
my %globalmgt = (
    fsp   => "fsp",
    bpa   => "bpa",
    cec   => "fsp",
    frame => "bpa",
    mm    => "blade",
    ivm   => "ivm",
    rsa   => "blade",
    cmm   => "blade",
    hmc   => "hmc",
);
my %globalid = (
     fsp   => "cid",
     cec   => "cid",
     bpa   => "fid",
     frame => "fid"
);
##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {

    return( {lsslp=>"lsslp"} );
}

##########################################################################
# Invokes the callback with the specified message
##########################################################################
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my $msg     = shift;
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
        $output{data} = $msg;
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
    my %opt;
    my %services = (
        HMC   => SOFTWARE_SERVICE.":".SERVICE_HMC.":",
        IVM   => SOFTWARE_SERVICE.":".SERVICE_IVM.":",
        BPA   => HARDWARE_SERVICE.":".SERVICE_BPA,
        FSP   => HARDWARE_SERVICE.":".SERVICE_FSP,
        CEC   => HARDWARE_SERVICE.":".SERVICE_CEC,
        FRAME => HARDWARE_SERVICE.":".SERVICE_FRAME,
        RSA   => HARDWARE_SERVICE.":".SERVICE_RSA.":",
        CMM   => HARDWARE_SERVICE.":".SERVICE_CMM,
        MM    => HARDWARE_SERVICE.":".SERVICE_MM.":"
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
            qw(h|help V|Verbose v|version i=s x z w r s=s e=s t=s m c n C=s T=s I updatehosts makedhcp resetnet vpdtable))) {
        return( usage() );
    }

    #############################################
    # Check for node range
    #############################################
    if ( scalar(@ARGV) eq 1 ) {
        my @nodes = xCAT::NodeRange::noderange( @ARGV );
        foreach (@nodes)  {
            push @filternodes, $_;
        }
        unless (@filternodes) {
            return(usage( "Invalid Argument: $ARGV[0]" ));
        }
    } elsif ( scalar(@ARGV) > 1 ) {
        return(usage( "Invalid flag, please check and retry." ));
    }

    #############################################
    # Option -V for verbose output
    #############################################
    if ( exists( $opt{V} )) {
        $globalopt{verbose} = 1;
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
       $globalopt{maxtries} = $opt{t};

       if ( $globalopt{maxtries} !~ /^0?[1-9]$/ ) {
           return( usage( "Invalid command tries (1-9)" ));
       }
    }

    #############################################
    # Check for unsupported service type
    #############################################
    if ( exists( $opt{s} )) {
        if ( !exists( $services{$opt{s}} )) {
            return(usage( "Invalid service: $opt{s}" ));
        }
        $globalopt{service} = $services{$opt{s}};
    }
    #############################################
    # Check the validation of -T option
    #############################################
    if ( exists( $opt{T} )) {
        $globalopt{time_out} = $opt{T};
        if ( $globalopt{time_out} !~ /^\d+$/ ) {
            return( usage( "Invalid timeout value, should be number" ));
        }
        if (!exists( $opt{C} )) {
            return ( usage( "-T should be used with -C" ));
        }
    }

    #############################################
    # Check the validation of -C option
    #############################################
    if ( exists( $opt{C} )) {
        $globalopt{C} = $opt{C};

        if ( $globalopt{C} !~ /^\d+$/ ) {
            return( usage( "Invalid expect entries, should be number" ));
        }
        if ( !exists($opt{i} )) {
            return( usage( "-C should be used with -i" ));
        }
    }

    #############################################
    # Check the validation of -i option
    #############################################
    if ( exists( $opt{i} )) {
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
                    return( usage( "Invalid IP address: $ip") );
                }
            }
        }
        $globalopt{i} = $opt{i};
    }

    #############################################
    # write to the database
    #############################################
    if ( exists( $opt{w} )) {
        $globalopt{w} = 1;
    }

    #############################################
    # list the raw information
    #############################################
    if ( exists( $opt{r} )) {
        $globalopt{r} = 1;
    }

    #############################################
    # list the xml formate data
    #############################################
    if ( exists( $opt{x} )) {
        $globalopt{x} = 1;
    }

    #############################################
    # list the stanza formate data
    #############################################
    if ( exists( $opt{z} )) {
        $globalopt{z} = 1;
    }

    #############################################
    # match vpd table
    #############################################
    if ( exists( $opt{vpdtable} )) {
        $globalopt{vpdtable} = 1;
    }
    #########################################################
    # only list the nodes that discovered for the first time
    #########################################################
    if ( exists( $opt{n} )) {
        $globalopt{n} = 1;
    }

    ##############################################
    # warn for no discovered nodes in database
    ##############################################
    if ( exists( $opt{I} )) {
        $globalopt{I} = 1;
    }
    return (0);
}


##########################################################################
# Verbose mode (-V)
##########################################################################
sub trace {

    my $request = shift;
    my $msg     = shift;
    my $sig     = shift;

    if ($sig) {
        if ($TRACE) {
            my ($sec,$min,$hour,$mday,$mon,$yr,$wday,$yday,$dst) = localtime(time);
            my $msg = sprintf "%02d:%02d:%02d %5d %s", $hour,$min,$sec,$$,$msg;
            send_msg( $request, 0, $msg );
        }
    } else {
        if ( exists($globalopt{verbose}) ) {
            my ($sec,$min,$hour,$mday,$mon,$yr,$wday,$yday,$dst) = localtime(time);
            my $msg = sprintf "%02d:%02d:%02d %5d %s", $hour,$min,$sec,$$,$msg;
            send_msg( $request, 0, $msg );
        }
    }
}
##########################################################################
# Forks a process to run the slp command (1 per adapter)
##########################################################################
sub fork_cmd {

    my $request  = shift;

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

        invoke_dodiscover($request);
        ########################################
        # Pass result array back to parent
        ########################################
        my @results = ("FORMATDATA6sK4ci");
        my $out = $request->{pipe};

        print $out freeze( \@results );
        print $out "\nENDOFFREEZE6sK4ci\n";
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
sub invoke_dodiscover {

    my $request  = shift;

    ########################################
    # SLP command
    ########################################
    my $services;
    my $maxt;
    if ($globalopt{service}) {
        $services = $globalopt{service};
    } else {
        $services = [WILDCARD_SERVICE,HARDWARE_SERVICE,SOFTWARE_SERVICE];
    }
    if ($globalopt{maxtries}) {
        $maxt = $globalopt{maxtries};
    } else {
        $maxt = 0;
    }

    
    my %arg;
   $arg{SrvTypes} = $services;
   $arg{Callback} = \&handle_new_slp_entity;
   $arg{Ip} = $globalopt{i} if($globalopt{i});
   $arg{Retry} = $maxt;
   $arg{Count} = $globalopt{C} if($globalopt{C});
   $arg{Time} = $globalopt{T} if($globalopt{T});
   
   my $result  = xCAT::SLP::dodiscover(%arg);


    #########################################
    ## Need to check if the result is enough
    #########################################
    #if ( $request->{C} != 0) {
    #    send_msg( $request, 0, "\n Begin to try again, this may takes long time \n" );
    #    my %val_tmp = %$values;
    #    my %found_cec;
    #    for my $v (keys %val_tmp) {
    #        $v =~ /type=([^\)]+)\)\,\(serial-number=([^\)]+)\)\,\(machinetype-model=([^\)]+)\)\,/;
    #        if ( $found_cec{$2.'*'.$3} ne 1 and $1  eq SERVICE_FSP)  {
    #            $found_cec{$2.'*'.$3} = 1;
    #        }
    #    }
    #
    #    my $rlt;
    #    my $val;
    #    my $start_time = Time::HiRes::gettimeofday();
    #    my $elapse;
    #    my $found = scalar(keys %found_cec);
    #    while ( $found < $globalopt{C} ) {
    #        $rlt = xCAT::SLP::dodiscover(SrvTypes=>$services,Callback=>sub { print Dumper(@_) });
    #        $val =  @$rlt[1];
    #        for my $v (keys %$val) {
    #            $v =~ /type=([^\)]+)\)\,\(serial-number=([^\)]+)\)\,\(machinetype-model=([^\)]+)\)\,/;
    #            if ( $found_cec{$2.'*'.$3} ne 1 and $1  eq SERVICE_FSP)  {
    #                $found_cec{$2.'*'.$3} = 1;
    #                $val_tmp{$v} = 1;
    #            }
    #        }
    #        $found = scalar(keys %val_tmp);
    #        $elapse = Time::HiRes::gettimeofday() - $start_time;
    #        if ( $elapse > $globalopt{time_out} ) {
    #            send_msg( $request, 0, "Time out, Force return.\n" );
    #            last;
    #        }
    #    }
    #    send_msg( $request, 0, "Discovered $found nodes \n" );
    #    $values = \%val_tmp;
    #}

}


##########################################################################
# Formats slp responses
##########################################################################
sub format_output {

    my $request = shift;
    my $length  = length( $header[IP_ADDRESSES][TEXT] );
    my $result;
    
    ###########################################
    # No responses
    ###########################################
    if ( keys %searchmacs  == 0 ){
        send_msg( $request, 0, "No responses" );
        return;
    }

    ###########################################
    # Check -C -T
    ###########################################
    if ($globalopt{C}){
        if (scalar(keys %searchmacs) ne $globalopt{C}) {
            send_msg( $request, 0, "Timeout...Fource to return" );
        }    
    }
    ###########################################
    # Read table to get exists data
    ###########################################
    my $errcode = read_from_table();
    if ($errcode) {
        send_msg( $request, 0, "Can't open $errcode table" );
        return;
    }
    ###########################################
    # Parse responses and add to hash
    ###########################################
    my $outhash = parse_responses( $request, \$length );

    ###########################################
    # filter the result and keep the specified nodes
    ###########################################
    if ( scalar(@filternodes)) {
        my $outhash1 = filter( $outhash );
        $outhash = $outhash1;
    }

    ###########################################
    # -w flag for write to xCat database
    ###########################################
    if ( $globalopt{w} ) {
        send_msg( $request, 0, "Begin to write into Database, this may change node name" );
        xCATdB( $outhash );
    }



    ###########################################
    # -r flag for raw response format
    ###########################################
    my %rawhash;
    if ( $globalopt{r} ) {
        foreach ( keys %$outhash ) {
            my $raw = ${$outhash->{$_}}{url};
            $rawhash{$raw} = 1;
        }
        foreach ( keys %rawhash ) {
            $result .= "$_\n";
        }

        send_msg( $request, 0, $result );
        return;
    }
    ###########################################
    # -x flag for xml format
    ###########################################
    if ( $globalopt{x} ) {
        send_msg( $request, 0, format_xml( $outhash ));
        return;
    }
    ###########################################
    # -z flag for stanza format
    ###########################################
    if ( $globalopt{z} ) {
        send_msg( $request, 0, format_stanza( $outhash ));
        return;
    }

    ###########################################
    # -T flag for vpd table format
    ###########################################
    if ( $globalopt{vpdtable} ) {
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
    foreach my $nameentry ( sort keys %$outhash ) {
        my $hostname= ${$outhash->{$nameentry}}{hostname};

        foreach ( @header ) {
            my $attr = $headertoattr{@$_[0]};
            $result .= sprintf @$_[1], ${$outhash->{$nameentry}}{$attr};

        }
        $result .= "\n";
    }
    send_msg( $request, 0, $result );
}

##########################################################################
# Read the table and cache the data that will be used frequently
##########################################################################
sub read_from_table {
    my %vpdhash;
    my @nodelist;
    my %ppchash;
    my %iphash;

    if ( !defined(%::OLD_DATA_CACHE))
    {
        #find out all the existed nodes
        my $nodelisttab  = xCAT::Table->new('nodelist');
        if ( $nodelisttab ) {
            my @typeentries = $nodelisttab->getAllNodeAttribs( ['node'] );
            for my $typeentry ( @typeentries) {
                push @nodelist, $typeentry->{node};
            }
        } else {
            return "nodelist";
        }

        #find out all the existed nodes
        my $hoststab  = xCAT::Table->new('hosts');
        if ( $hoststab ) {
            my @hostsentries = $hoststab->getAllNodeAttribs( ['node','ip'] );
            for my $hostsentry ( @hostsentries) {
                $iphash{$hostsentry->{node}} = $hostsentry->{ip};
            }
        } else {
            return "hosts";
        }

        #find out all the existed nodes' type
        my $typehashref = xCAT::DBobjUtils->getnodetype(\@nodelist, "ppc");

        # find out all the existed nodes' mtms and side
        my $vpdtab  = xCAT::Table->new( 'vpd' );
        if ( $vpdtab )  {
            my @vpdentries = $vpdtab->getAllNodeAttribs(['node','mtm','serial','side']);
            for my $entry ( @vpdentries ) {
                @{$vpdhash{$entry->{node}}}[0] = $entry->{mtm};
                @{$vpdhash{$entry->{node}}}[1] = $entry->{serial};
                @{$vpdhash{$entry->{node}}}[2] = $entry->{side};
            }
        } else {
            return "vpd";
        }

        # find out all the existed nodes' attributes
        my $ppctab  = xCAT::Table->new('ppc');
        if ( $ppctab ) {
            my @identries = $ppctab->getAllNodeAttribs( ['node','id','parent'] );
            for my $entry ( @identries ) {
                next if ($entry->{nodetype} =~ /lpar/);
                @{$ppchash{$entry->{node}}}[0] = $entry->{id};#id
                @{$ppchash{$entry->{node}}}[1] = $entry->{parent};#parent
            }
        } else {
            return "ppc";
        }

        foreach my $node (@nodelist) {
            my $type = $$typehashref{$node};
            my $mtm = @{$vpdhash{$node}}[0];
            my $sn = @{$vpdhash{$node}}[1];
            my $side = @{$vpdhash{$node}}[2];
            my $id = $ppchash{$node}[0];
            my $parent = $ppchash{$node}[1];
            my $ip = $iphash{$node};
            if ($type =~ /frame/){
                $::OLD_DATA_CACHE{"frame*".$mtm."*".$sn} = $node;
            }elsif ($type =~ /cec/) {
                $::OLD_DATA_CACHE{"cec*".$mtm."*".$sn} = $node;
                $::OLD_DATA_CACHE{"cec*".$parent."*".$id} = $node;
            }elsif ($type =~ /^fsp|bpa$/) {
                $::OLD_DATA_CACHE{$type."*".$mtm."*".$sn."*".$side} = $node;
            }elsif ($type =~ /hmc/) {
                $::OLD_DATA_CACHE{"hmc*".$ip} = $node;
            }else {
                $::OLD_DATA_CACHE{$type."*".$mtm."*".$sn} = $node;
            }
        }
    }
    return undef;
}
##########################################################################
# Makesure the ip in SLP URL is valid
# return 1 if valid, 0 if invalid
##########################################################################
sub check_ip {
    my $myip = shift;
    $myip =~ s/^(\d+)\..*/$1/;
    if ($myip >= 224 and $myip <= 239){
        return 0;
    }
    foreach (@invalidiplist){
        if ( $myip =~ /^($_)/ ){
            return 0;
        }
    }

    return 1;
}
##########################################################################
# Get hostname from SLP URL response
##########################################################################
sub get_host_from_url {

    my $request = shift;
    my $attr    = shift;
    my $vip;
    my $host;

    #######################################
    # Extract IP from URL
    #######################################
    my $nets = xCAT::Utils::my_nets();
    my $inc = $globalopt{i};
    my @ips = @{$attr->{'ip-address'}};

    my @ips2 = split /,/, $inc;
    my @validip;
    if ( $inc) {
        for my $net (keys %$nets) {
            my $fg = 1;
            for my $einc (@ips2) {
                if ( $nets->{$net} eq $einc) {
                    $fg = 0;
                }
            }
            delete $nets->{$net} if ($fg) ;
        }
    }
    #######################################
    # Check if valid IP
    #######################################
    for my $tip (@ips) {
        next if ( $tip =~ /:/); #skip IPV6 addresses
        for my $net ( keys %$nets) {
            my ($n,$m) = split /\//,$net;
            if ( #xCAT::Utils::isInSameSubnet($n, $tip, $m, 1) and
                 xCAT::Utils::isPingable($tip) and (length(inet_aton($tip)) == 4)) {
                push @validip, $tip;
            }
        }
    }


    if (scalar(@validip) == 0) {
                if ($globalopt{verbose}) {
                    trace( $request, "Invalid IP address in URL" );
        }
            return undef;
        }


    #######################################
    # Get Factory Hostname
    #######################################
    if ( ${$attr->{'hostname'}}[0] ) {
        $host = ${$attr->{'hostname'}}[0];

    } else {
        $host = "Server-".${$attr->{'machinetype-model'}}[0]."-SN".${$attr->{'serial-number'}}[0];
        foreach my $ip (@validip) {
            my $hname = gethostbyaddr( inet_aton($ip), AF_INET );
            if($hname) {
                            $host = $hname;
                                $vip = $ip;
                                last;

                    }
        }
        foreach my $ip (@validip) {
            my $hoststab = xCAT::Table->new( 'hosts' );
            my @entries = $hoststab->getAllNodeAttribs(['node','ip']);
            foreach my $entry ( @entries ) {
                if ( $entry->{ip} and $entry->{ip} eq $ip ) {
                    $host = $entry->{node};
                    $vip = $ip;

                }
            }
        }
    }
    if ( $host =~ /([^\.]+)\./ ) {
            $host = $1;
    }
    return $host;

}

##########################################################################
#
#########################################################################
sub parse_responses {

    my $request = shift;
    my $length  = shift;
    my $matchflag;
    my %outhash;
    my $host;
    my @matchnode;


   #get networks information for defining HMC
    my %net;
    my %addr;
    my $nettab = xCAT::Table->new('networks');
    my @nets = $nettab->getAllAttribs('netname', 'net','mask','mgtifname');
    if (scalar(@nets) == 0) {
        trace( $request, "Can't get networks information from networks table" , 1);
    } else {
        foreach my $enet (@nets) {
            next if ($enet->{'net'} =~ /:/);
            $net{$enet->{'mgtifname'}}{subnet} = $enet->{'net'};
            $net{$enet->{'mgtifname'}}{netmask} = $enet->{'mask'};
        }
    }
    my $netref = xCAT::NetworkUtils->get_nic_ip();
    for my $entry (keys %$netref) {
        $addr{$netref->{$entry}}{subnet} = $net{$entry}{subnet};
        $addr{$netref->{$entry}}{netmask} = $net{$entry}{netmask};
    }

    trace( $request, "Now lsslp begin to parse its response: " , 1);
    foreach my $rsp ( keys(%searchmacs) ) {
        ###########################################
        # attribute not found
        ###########################################
        if ( !exists(${$searchmacs{$rsp}}{attributes} )) {
            if ( $globalopt{verbose}  ) {
                trace( $request, "Attribute not found for: $rsp" );
            }
            next;
        }
        ###########################################
        # Valid service-type attribute
        ###########################################
        my $attributes = ${$searchmacs{$rsp}}{attributes};
        my $type = ${$attributes->{'type'}}[0] ;
        if ( !exists($service_slp{$type} )) {
            if ( $globalopt{verbose}  ) {
                trace( $request, "Discarding unsupported type: $type" );
            }
            next;
        }
        ###########################################
        # Define nodes
        ###########################################
        my %atthash;
        if (( $type eq SERVICE_RSA ) or ( $type eq SERVICE_RSA2 ) or
            ( $type eq SERVICE_MM )) {
            $atthash{type} = $service_slp{$type};
            $atthash{mtm} = ${$attributes->{'enclosure-machinetype-model'}}[0];
            $atthash{serial} = ${$attributes->{'enclosure-serial-number'}}[0];
            $atthash{slot} = int(${$attributes->{'slot'}}[0]);
            $atthash{ip} = ${$attributes->{'ip-address'}}[0];
            $atthash{mac} = $rsp;
            $atthash{hostname} = get_host_from_url($request, $attributes);
            $atthash{otherinterfaces} = ${$attributes->{'ip-address'}}[0];
                        $atthash{url} =  ${$searchmacs{$rsp}}{payload};
            $outhash{'Server-'.$atthash{mtm}.'-SN'.$atthash{serial}} = \%atthash;
            $$length = length( $atthash{ip}) if ( length( $atthash{ip} ) > $$length );
        } elsif ($type eq SERVICE_CMM) {
            $atthash{type} = $service_slp{$type};
            $atthash{mtm} = ${$attributes->{'enclosure-machinetype-model'}}[0];
            $atthash{serial} = ${$attributes->{'enclosure-serial-number'}}[0];
            $atthash{slot} = int(${$attributes->{'slot'}}[0]);
            $atthash{ip} = ${$attributes->{'ip-address'}}[0];
            $atthash{mac} = $rsp;
            $atthash{mname} = ${$attributes->{'mm-name'}}[0];
                        $atthash{url} =  ${$searchmacs{$rsp}}{payload};
            $atthash{hostname} = get_host_from_url($request, $attributes);
            $atthash{otherinterfaces} = ${$attributes->{'ip-address'}}[0];
            $outhash{'Server-'.$atthash{mtm}.'-SN'.$atthash{serial}} = \%atthash;
            $$length = length( $atthash{ip}) if ( length( $atthash{ip} ) > $$length );
        } elsif ($type eq SERVICE_HMC) {
            $atthash{type} = $service_slp{$type};
            $atthash{mtm} = ${$attributes->{'machinetype-model'}}[0];
            $atthash{serial} = ${$attributes->{'serial-number'}}[0];
            $atthash{ip} = ${$attributes->{'ip-address'}}[0];
            $atthash{hostname} = get_host_from_url($request, $attributes);
                        my @ips = @{$attributes->{'ip-address'}};
                        foreach my $tmpip (@ips) {
                if (exists($::OLD_DATA_CACHE{"hmc*".$tmpip})){
                    $atthash{hostname} = $::OLD_DATA_CACHE{"hmc*".$tmpip};
                    push  @matchnode, 'Server-'.$atthash{mtm}.'-SN'.$atthash{serial};
                    $atthash{ip} = $tmpip;
                }
                    }
            $atthash{mac} = $rsp;
                        $atthash{url} =  ${$searchmacs{$rsp}}{payload};
            $atthash{otherinterfaces} = ${$attributes->{'ip-address'}}[0];
            $outhash{'Server-'.$atthash{mtm}.'-SN'.$atthash{serial}} = \%atthash;
            $$length = length( $atthash{ip}) if ( length( $atthash{ip} ) > $$length );
        }else {
            #begin to define fsp and bpa
            my %tmphash;
            $tmphash{type} = ($type eq SERVICE_BPA) ? TYPE_BPA : TYPE_FSP;
            $tmphash{mtm} = ${$attributes->{'machinetype-model'}}[0];
            $tmphash{serial} = ${$attributes->{'serial-number'}}[0];
            $tmphash{ip} = ${$searchmacs{$rsp}}{peername};
            my $loc = ($tmphash{ip} =~ ${$attributes->{'ip-address'}}[0]) ? 0:1; #every entry has two ip-addresses
            $tmphash{side} = (int(${$attributes->{'slot'}}[0]) == 0) ? 'B-'.$loc:'A-'.$loc;
            $tmphash{mac} = $rsp;
            $tmphash{parent} =  'Server-'.$tmphash{mtm}.'-SN'.$tmphash{serial};
            $tmphash{hostname} = $tmphash{ip};
            $tmphash{otherinterfaces} = ${$searchmacs{$rsp}}{peername};
            $tmphash{bpcmtm} = ${$attributes->{'bpc-machinetype-model'}}[0];
            $tmphash{bpcsn} = ${$attributes->{'bpc-serial-number'}}[0];
            $tmphash{fid} = int(${$attributes->{'frame-number'}}[0]);
            $tmphash{cid} = int(${$attributes->{'cage-number'}}[0]);
            $outhash{$tmphash{ip}} = \%tmphash;
            $$length = length( $tmphash{ip}) if ( length( $tmphash{ip} ) > $$length );
            #begin to define frame and cec
            $atthash{type} = $service_slp{$type};
            $atthash{mtm} = ${$attributes->{'machinetype-model'}}[0];
            $atthash{serial} = ${$attributes->{'serial-number'}}[0];
            my $name = 'Server-'.$atthash{mtm}.'-SN'.$atthash{serial};
            unless (exists $outhash{$name} ){
                $atthash{slot} = '';
                $atthash{ip} = '';
                $atthash{hostname} = 'Server-'.$atthash{mtm}.'-SN'.$atthash{serial};;
                $atthash{mac} = $rsp;
                $atthash{bpcmtm} = ${$attributes->{'bpc-machinetype-model'}}[0];
                $atthash{bpcsn} = ${$attributes->{'bpc-serial-number'}}[0];
                $atthash{fid} = int(${$attributes->{'frame-number'}}[0]);
                $atthash{cid} = int(${$attributes->{'cage-number'}}[0]);
                $atthash{parent} = 'Server-'.$atthash{bpcmtm}.'-SN'.$atthash{bpcsn} if ($type eq SERVICE_FSP);
                $atthash{children} = ${$attributes->{'ip-address'}}[0].",".${$attributes->{'ip-address'}}[1];
                $atthash{url} =  ${$searchmacs{$rsp}}{payload};
                $outhash{'Server-'.$atthash{mtm}.'-SN'.$atthash{serial}} = \%atthash;
			} else {
			    #update frameid and cageid to fix the firmware mistake
			    ${$outhash{$name}}{fid} = int(${$attributes->{'frame-number'}}[0]) if(int(${$attributes->{'frame-number'}}[0]) != 0);
			    ${$outhash{$name}}{cid} = int(${$attributes->{'cage-number'}}[0]) if(int(${$attributes->{'cage-number'}}[0]) != 0);       
            }
        }
    }

    ###########################################################
    # find frame's hostname first, then use find the cec's parent
    # until then can begin with finding cec's hostname
    # the order of finding PPC nodes' hostname can't be wrong
    # and can't be done together
    ###########################################################
    my $newhostname;
    trace( $request, "\n\n\nBegin to find find frame's hostname", 1);
    foreach my $h ( keys %outhash ) {
        if(${$outhash{$h}}{type} eq TYPE_FRAME) {
            $newhostname = $::OLD_DATA_CACHE{"frame*".${$outhash{$h}}{mtm}."*".${$outhash{$h}}{serial}};
            if ($newhostname) {
                ${$outhash{$h}}{hostname} = $newhostname ;
                push  @matchnode, $h;
            }
        }
    }
    trace( $request, "\n\n\nBegin to find cec's parent, adjust cec id", 1);
    foreach my $h ( keys %outhash ) {
        next unless (${$outhash{$h}}{type} eq TYPE_CEC);
        my $parent;
        #find parent in the discovered nodes
        foreach my $h1 ( keys %outhash ) {
            if (${$outhash{$h1}}{type} eq "frame" and ${$outhash{$h}}{bpcmtm} eq ${$outhash{$h1}}{mtm} and ${$outhash{$h}}{bpcsn} eq ${$outhash{$h1}}{serial} ) {
                $parent = ${$outhash{$h1}}{hostname};
                last;
            }
        }
        #find parent in database
        if (!defined($parent)) {
            my $existing_node = $::OLD_DATA_CACHE{"frame*".${$outhash{$h}}{bpcmtm}.'*'.${$outhash{$h}}{bpcsn}};
            $parent = $existing_node if ($existing_node);
        }
        ${$outhash{$h}}{parent} = $parent;

        }

    trace( $request, "\n\n\nBegin to find cec hostname", 1);
    foreach my $h ( keys %outhash ) {
        if(${$outhash{$h}}{type} eq TYPE_CEC) {
            my $newhostname1 = $::OLD_DATA_CACHE{"cec*".${$outhash{$h}}{mtm}.'*'.${$outhash{$h}}{serial}};
            if ($newhostname1) {
                ${$outhash{$h}}{hostname} = $newhostname1;
                push  @matchnode, $h;
            }
            my $newhostname2 = $::OLD_DATA_CACHE{"cec*".${$outhash{$h}}{parent}.'*'.${$outhash{$h}}{id}};
            if ($newhostname2) {
                ${$outhash{$h}}{hostname} = $newhostname2;
                push  @matchnode, $h;
            }
        }
    }

    trace( $request, "\n\n\nBegin to find fsp/bpa's hostname and parent", 1);
    foreach my $h ( keys %outhash ) {
        if(${$outhash{$h}}{type} eq TYPE_FSP or ${$outhash{$h}}{type} eq TYPE_BPA) {
            $newhostname = $::OLD_DATA_CACHE{${$outhash{$h}}{type}."*".${$outhash{$h}}{mtm}.'*'.${$outhash{$h}}{serial}.'*'.${$outhash{$h}}{side}};
            if ($newhostname){
                ${$outhash{$h}}{hostname} = $newhostname ;
                push  @matchnode, $h;
            }
            my $ptmp = ${$outhash{$h}}{parent};
            ${$outhash{$h}}{parent} = ${$outhash{$ptmp}}{hostname};
            #check if fsp/bpa's ip is valid
            my $vip = check_ip(${$outhash{$h}}{ip});
            unless ( $vip )   { #which means the ip is a valid one
                delete $outhash{$h};
            }
        }
    }

    ##########################################################
    # If there is -n flag, skip the matched nodes
    ##########################################################
    if (exists($globalopt{n})) {
        trace( $request, "\n\n\nThere is -n flag, skip these nodes:\n", 1);
        for my $matchednode (@matchnode) {
            if ($outhash{$matchednode}) {
                trace( $request, "$matchednode,", 1);
                delete $outhash{$matchednode};
            }
        }
    } 
        if (exists($globalopt{I})) {
	    my %existsnodes;
    	my $nodelisttab = xCAT::Table->new('nodelist');
        unless ( $nodelisttab ) {
            return( "Error opening 'nodelisttable'" );
        }
        my @nodes = $nodelisttab->getAllNodeAttribs([qw(node)]);
		my $notdisnode;
        for my $enode (@nodes) {
		    for my $mnode (@matchnode) {
			    if ($enode->{node} eq ${$outhash{$mnode}}{hostname}) {
				    $existsnodes{$enode->{node}} = 1;
					last;
				}
            }				
		}
		
        for my $enode (@nodes) {
			unless ($existsnodes{$enode->{node}}) {
				$notdisnode .= $enode->{node}.",";
			}	
		}
        trace ( $request, "These nodes defined in database but can't be discovered: $notdisnode  \n", 1); 	
	
	}	

    return \%outhash;
}
##########################################################################
# Write result to xCat database
##########################################################################
sub xCATdB {
    my $outhash = shift;

    ########################################
    # Update database if the name changed
    ########################################
    my %db       = ();
    my @tabs     = qw(nodelist ppc vpd nodehm nodetype ppcdirect hosts mac mp);
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_);
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }

    ########################################
    # Begin to write each node
    ########################################
    foreach my $nodeentry ( keys %$outhash ) {
        my $type       = ${$outhash->{$nodeentry}}{type};
        my $model      = ${$outhash->{$nodeentry}}{mtm};
        my $serial     = ${$outhash->{$nodeentry}}{serial};
        my $side       = ${$outhash->{$nodeentry}}{side};
        my $ip         = ${$outhash->{$nodeentry}}{ip};
        my $frameid    = ${$outhash->{$nodeentry}}{fid};
        my $cageid     = ${$outhash->{$nodeentry}}{cid};
        my $parent     = ${$outhash->{$nodeentry}}{parent};
        my $mac        = ${$outhash->{$nodeentry}}{mac};
        my $otherif    = ${$outhash->{$nodeentry}}{otherinterfaces};
        my $hostname   = ${$outhash->{$nodeentry}}{hostname};

        my $id = ($type =~ /bpa|frame/) ? $frameid:$cageid;
        my $hidden = ($type =~ /bpa|fsp/)? 1:0;
        ########################################
        # Write result to every tables,
        ########################################
        if ( $type =~ /^bpa|fsp|cec|frame$/ ) {
            $db{nodelist}->setNodeAttribs($hostname,{node=>$hostname, groups=>"$type,all", hidden=>$hidden});
            $db{ppc}->setNodeAttribs($hostname,{node=>$hostname, id=>$id, parent=>$parent, hcp=>$hostname, nodetype=>$globalhwtype{$type}});
            $db{vpd}->setNodeAttribs($hostname,{mtm=>$model, serial=>$serial, side=>$side});
            $db{nodehm}->setNodeAttribs($hostname,{mgt=>$globalmgt{$type}});
            $db{nodetype}->setNodeAttribs($hostname,{nodetype=>$globalnodetype{$type}});
            $db{hosts}->setNodeAttribs($hostname,{otherinterfaces=>$otherif}) if ($type =~ /fsp|bpa/);
            $db{mac}->setNodeAttribs($hostname,{mac=>$mac}) if ($type =~ /^fsp|bpa$/);
        } elsif ( $type =~ /^(rsa|mm)$/ ) {
            my @data = ($type, $model, $serial, $side, $ip, $frameid, $cageid, $parent, $mac);
            xCAT::PPCdb::add_systemX( $type, $hostname, \@data );
        } elsif ( $type =~ /^(hmc|ivm)$/ ) {
            $db{nodelist}->setNodeAttribs($hostname,{node=>$hostname, groups=>"$type,all", hidden=>$hidden});
            $db{ppc}->setNodeAttribs($hostname,{node=>$hostname, nodetype=>$globalhwtype{$type}});
            $db{vpd}->setNodeAttribs($hostname,{mtm=>$model, serial=>$serial});
            $db{nodetype}->setNodeAttribs($hostname,{nodetype=>$globalnodetype{$type}});
            $db{nodehm}->setNodeAttribs($hostname,{mgt=>$globalmgt{$type}});
            $db{hosts}->setNodeAttribs($hostname,{ip=>$ip});
            $db{mac}->setNodeAttribs($hostname,{mac=>$mac});
        }elsif ($type =~ /^cmm$/){
            $db{nodelist}->setNodeAttribs($hostname,{node=>$hostname, groups=>"cmm,all", hidden=>$hidden});
            $db{vpd}->setNodeAttribs($hostname,{mtm=>$model, serial=>$serial});
            $db{nodetype}->setNodeAttribs($hostname,{nodetype=>$globalnodetype{$type}});
            $db{nodehm}->setNodeAttribs($hostname,{mgt=>"blade"});
            $db{mp}->setNodeAttribs($hostname,{nodetype=>$globalhwtype{$type}, mpa=>$hostname, id=>$side});
            $db{hosts}->setNodeAttribs($hostname,{otherinterfaces=>$otherif});
        }
    }
    foreach ( @tabs ) {
        $db{$_}->close();
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
    foreach my $name ( keys %$outhash ) {
        my $hostname = ${$outhash->{$name}}{hostname};
        my $ip = ${$outhash->{$name}}{ip};
        if ( $hostname =~ /^([^\(]+)\(([^\)]+)\)$/) {
            $hostname = $1;
            $ip  = $2;
        }
        my $type = ${$outhash->{$name}}{type};

        #################################
        # Node attributes
        #################################
        $result .= "$hostname:\n\tobjtype=node\n";
        if ($type =~ /^cmm$/){
            $result .= "\tmpa=${$outhash->{$name}}{hostname}\n";
        }else{
            $result .= "\thcp=${$outhash->{$name}}{hostname}\n";
        }
        $result .= "\tnodetype=$globalnodetype{$type}\n";
        $result .= "\tmtm=${$outhash->{$name}}{mtm}\n";
        $result .= "\tserial=${$outhash->{$name}}{serial}\n";
        if ($type =~ /^fsp|bpa|cmm$/) {
            $result .= "\tside=${$outhash->{$name}}{side}\n";
        }
        $result .= "\tgroups=$type,all\n";
        $result .= "\tmgt=$globalmgt{$type}\n";
        if ($type =~ /^fsp|bpa|frame|cec$/) {
            $result .= "\tid=${$outhash->{$name}}{$globalid{$type}}\n";
        }
        if ($type =~ /^fsp|bpa|cec$/ and exists(${$outhash->{$name}}{parent})) {
            $result .= "\tparent=${$outhash->{$name}}{parent}\n";
        }
        unless ($type =~ /^frame|cec$/){
            $result .= "\tmac=${$outhash->{$name}}{mac}\n";
        }
        if ($type =~ /^fsp|bpa$/){
            $result .= "\thidden=1\n";
        }else {
            $result .= "\thidden=0\n";
        }
        #unless ($type =~ /^cmm$/) {
        #    $result .= "\tip=$ip\n";
        #}
        if ($type =~ /^fsp|bpa|cmm$/){
            $result .= "\totherinterfaces=${$outhash->{$name}}{otherinterfaces}\n";
        }
        $result .= "\thwtype=$globalhwtype{$type}\n";
    }
    return( $result );
}



##########################################################################
# XML formatting
##########################################################################
sub format_xml {

    my $outhash = shift;
    my $xml;

    my $result = format_stanza($outhash);
    my @nodeentry = split 'objtype=', $result;
    foreach my $entry (@nodeentry) {
        my $href = {
            Node => { }
        };
        my @attr = split '\\n\\t', $entry;
        $href->{Node}->{node} = $attr[0];
        for (my $i = 1; $i < scalar(@attr); $i++ ){
            if( $attr[$i] =~ /(\w+)\=(.*)/){
                $href->{Node}->{$1} = $2;
            }
        }
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

    #####################################
    # Create XML formatted attributes
    #####################################
    foreach my $name ( keys %$outhash ) {
        my $type = ${$outhash->{$name}}{type};
        next if ($type =~ /^(fsp|bpa)$/);
        $result .= "${$outhash->{$name}}{hostname}:\n";
        $result .= "\tobjtype=node\n";
        $result .= "\tmtm=${$outhash->{$name}}{mtm}\n";
        $result .= "\tserial=${$outhash->{$name}}{serial}\n";
    }
    return( $result );
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
                    #$slp_result{$_} = 1;
                }
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
# Preprocess request from xCAT daemon and send request to service nodes
#############################################################################
sub preprocess_request {

    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my @requests;

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
    #my @all = xCAT::Utils::getAllSN();
    #foreach (@all) {
    #    $sv_hash{$_}=1;
    #}
    ###########################################
    # build each request for each service node
    ###########################################
    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    #foreach my $sn (keys (%sv_hash)) {
    #  my $reqcopy = {%$req};
    #  $reqcopy->{_xcatdest} = $sn;
    #  $reqcopy->{_xcatpreprocessed}->[0] = 1;
    #  push @result, $reqcopy;
    #}
    return \@result;
}

##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {

    my $req      = shift;
    my $callback = shift;
    #unless ($macmap) { $macmap = xCAT::MacMap->new(); }

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
    # do discover
    ###########################################
    my $start;

    if ( exists($globalopt{verbose}) ) {
        #######################################
        # Write header for trace
        #######################################
        my $tm  = localtime( time );
        my $msg = "\n--------  $tm\nTime     PID";
        trace( $req, $msg );
    }


    ###########################################
    # Record begin time
    ###########################################
    if ( exists($globalopt{verbose}) ) {
        $start = Time::HiRes::gettimeofday();
    }
    ############################################
    ## Fork one process per adapter
    ############################################
    #my $children = 0;
    #$SIG{CHLD} = sub {
    #   my $rc_bak = $?;
    #   while (waitpid(-1, WNOHANG) > 0) { $children--; }
    #   $? = $rc_bak;
    #};
    #my $fds = new IO::Select;
    #
    #foreach ( keys %ip_addr ) {
    #    my $pipe = fork_cmd( $req, $_);
    #    if ( $pipe ) {
    #        $fds->add( $pipe );
    #        $children++;
    #    }
    #}
    ############################################
    ## Process slp responses from children
    ############################################
    #while ( $children > 0 ) {
    #    child_response( $callback, $fds );
    #}
    #while (child_response($callback,$fds)) {}

    invoke_dodiscover();

    ###########################################
    # Record ending time
    ###########################################
    if ( exists($globalopt{verbose}) ) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $msg = sprintf( "Total SLP Time: %.3f sec\n", $elapsed );
        trace( $req, $msg );
    }
    ###########################################
    # Combined responses from all children
    ###########################################
    format_output( \%request );

    return( SUCCESS );
}



###########################################
# Get ipv6 mac addresses
###########################################
sub get_ipv6_neighbors {
        #TODO: something less 'hacky'
        my @ipdata = `ip -6 neigh`;
        %ip6neigh=();
        foreach (@ipdata) {
                if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
                        $ip6neigh{$1}=$2;
                }
        }
}


##########################################################################
# Filter nodes the user specified
##########################################################################
sub filter {
    my $oldhash = shift;
    my $newhash;
    # find HMC/CEC/Frame that the user want to find
    foreach my $n(@filternodes) {
        for my $foundnode ( keys %$oldhash ) {
            if ( ${$oldhash->{$foundnode}}{hostname} =~ /^(\w+)\(.*\)/ )  {
                if ( $1 eq $n ) {
                    $newhash->{$foundnode} = $oldhash->{$foundnode};
                                        if (${$oldhash->{$foundnode}}{type} eq TYPE_CEC or ${$oldhash->{$foundnode}}{type} eq  TYPE_FRAME) {
                                            my @ips =  split /,/, ${$oldhash->{$foundnode}}{children};
                                            $newhash->{$ips[0]} = $oldhash->{$ips[0]};
                                                $newhash->{$ips[1]} = $oldhash->{$ips[1]};
                                        }
                }
            } elsif ( ${$oldhash->{$foundnode}}{hostname} eq $n )  {
                $newhash->{$foundnode} = $oldhash->{$foundnode};
                                if (${$oldhash->{$foundnode}}{type} eq TYPE_CEC or ${$oldhash->{$foundnode}}{type} eq  TYPE_FRAME) {
                                    my @ips =  split /,/, ${$oldhash->{$foundnode}}{children};
                                    $newhash->{$ips[0]} = $oldhash->{$ips[0]};
                                        $newhash->{$ips[1]} = $oldhash->{$ips[1]};
                                }
            }
        }
    }
    return $newhash;
}
##########################################################################
# Filter nodes not in the user specified vlan
##########################################################################
sub filtersamevlan {
    my $request = shift;
    my $oldhash = shift;
    my $newhash;
    my $nets = xCAT::Utils::my_nets();
    my $validnets;
    for my $net ( keys %$nets) {
        for my $nic ( split /,/, $globalopt{i} ) {
            if ( $nets->{$net} eq $nic ) {
                $validnets->{$net} = $nic;
            }
        }
    }
    foreach my $name ( keys %$oldhash ) {
        if ($name->{type} =~ /^(fsp|bpa)$/) {
            my $ip = $name->{ip};
            for my $net ( keys %$validnets){
                my ($n,$m) = split /\//,$net;
                if ( xCAT::Utils::isInSameSubnet( $n, $ip, $m, 1) and xCAT::Utils::isPingable( $ip)) {
                    $newhash->{$name} = ${$oldhash->{$name}}{hostname};
                }
            }
        } else {
            $newhash->{$name} = $oldhash->{$name};
        }
    }
    return $newhash;
}

###########################################
# Parse the slp resulte data
###########################################
sub handle_new_slp_entity {
        my $data = shift;
        delete $data->{sockaddr}; #won't need it
        my $mac = get_mac_for_addr($data->{peername});
        unless ($mac) { return; }
        $searchmacs{$mac} = $data;
}
###########################################
# Get mac addresses
###########################################
sub get_mac_for_addr {
        my $neigh;
        my $addr = shift;
        if ($addr =~ /:/) {
                get_ipv6_neighbors();
                return $ip6neigh{$addr};
        } else {
                get_ipv4_neighbors();
                return $ip4neigh{$addr};
        }
}

###########################################
# Get ipv4 mac addresses
###########################################
sub get_ipv4_neighbors {
        #TODO: something less 'hacky'
        my @ipdata = `ip -4 neigh`;
        %ip6neigh=();
        foreach (@ipdata) {
                if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
                        $ip4neigh{$1}=$2;
                }
        }
}