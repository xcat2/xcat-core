# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCfsp;
use strict;
use Getopt::Long;
use LWP;
use HTTP::Cookies;
use HTML::Form;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);


##########################################
# Globals
##########################################
my %cmds = ( 
  rpower => {
     state        => ["Power On/Off System",    \&state],
     on           => ["Power On/Off System",    \&on],
     off          => ["Power On/Off System",    \&off],
     reset        => ["System Reboot",          \&reset], 
     boot         => ["Power On/Off System",    \&boot] }, 
  reventlog => { 
     all          => ["Error/Event Logs",       \&all],
     all_clear    => ["Error/Event Logs",       \&all_clear],
     entries      => ["Error/Event Logs",       \&entries],
     clear        => ["Error/Event Logs",       \&clear] },
  rfsp => {
     iocap        => ["I/O Adapter Enlarged Capacity", \&iocap],
     time         => ["Time Of Day",            \&time], 
     date         => ["Time Of Day",            \&date], 
     autopower    => ["Auto Power Restart",     \&autopower],
     sysdump      => ["System Dump",            \&sysdump],
     spdump       => ["Service Processor Dump", \&spdump] },
);



##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my $args    = $request->{arg};
    my @rsp     = keys %{$cmds{rfsp}};
    my $cmd     = join('|',@rsp);
    my %opt     = ();
    my @VERSION = qw( 2.0 );
 
    #############################################
    # Modify usage statement 
    #############################################
    $cmd =~ s/time/time [hh:mm:ss]/;
    $cmd =~ s/date/date [mm-dd-yyy]/;
    $cmd =~ s/autopower/autopower [enable|disable]/;
    $cmd =~ s/iocap/iocap [enable|disable]/;

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],
            "rfsp -h|--help",
            "rfsp -v|--version",
            "rfsp [-V|--verbose] noderange ". $cmd,
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output"] );
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return(usage( "No command specified" ));
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );
    $request->{method} = undef;

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version) )) {
        return( usage() );
    }
    ####################################
    # Option -h for Help
    ####################################
    if ( exists( $opt{h} )) {
        return( usage() );
    }
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        return( \@VERSION );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Check for unsupported commands
    ####################################
    if ( !defined( $request->{method} )) { 
        my ($cmd) = grep(/^$ARGV[0]$/, @rsp );
        if ( !defined( $cmd )) {
            return(usage( "Invalid command: $ARGV[0]" ));
        }
        $request->{method} = $cmd;
    }
    ####################################
    # Check command arguments 
    ####################################
    if ( $request->{method} =~ /^date|time|iocap|autopower$/ ) {
        shift @ARGV;

        if ( defined( $ARGV[0] )) {
            if ( $request->{method} =~ /^time$/ ) { 
                if ( $ARGV[0] !~ 
                   /^([0-1]?[0-9]|2[0-3]):(0?[0-9]|[1-5][0-9]):(0?[0-9]|[1-5][0-9])$/ ) {
                    return( usage("Invalid time format '$ARGV[0]'") ); 
                }
                $request->{op} = "$1-$2-$3";
            }
            if ( $request->{method} =~ /^date$/ ) { 
                if ( $ARGV[0] !~ 
                  /^(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])-(20[0-9]{2})$/){
                    return( usage("Invalid date format '$ARGV[0]'") ); 
                }
                $request->{op} = "$1-$2-$3";
            }
            if ( $request->{method} =~ /^autopower|iocap$/ ) { 
                if ( $ARGV[0] !~ /^enable|disable$/ ) {
                    return( usage("Invalid argument '$ARGV[0]'") ); 
                }
                $request->{op} = $ARGV[0];
            }
        }
    } 
    ####################################
    # Check for an extra argument
    ####################################
    shift @ARGV;
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    return( \%opt );
}



##########################################################################
# FSP command handler through HTTP interface
##########################################################################
sub handler {

    my $server  = shift;
    my $request = shift;
    my $exp     = shift;

    ##################################
    # Process FSP command 
    ##################################
    my $result = process_cmd( $exp, $request );

    my %output;
    $output{node}->[0]->{name}->[0] = $server;
    $output{node}->[0]->{data}->[0]->{contents}->[0] = $result;

    ##################################
    # Disconnect from FSP 
    ##################################
    xCAT::PPCfsp::disconnect( $exp );

    return( [\%output] );

}


##########################################################################
# Logon through remote FSP HTTP-interface
##########################################################################
sub connect {

    my $request = shift;
    my $server  = shift;
    my $command = $request->{command};
    my $verbose = $request->{verbose};
    my $method  = $request->{method};
    my $lwp_log;

    ##################################
    # Check command
    ##################################
    if ( !exists( $cmds{$command}{$method} )) {
        return( "$server: Unsupported command" );
    }
    ##################################
    # Get userid/password 
    ##################################
    my @cred = xCAT::PPCdb::credentials( $server, "fsp" );

    ##################################
    # Redirect STDERR to variable 
    ##################################
    if ( $verbose ) {
        close STDERR;
        if ( !open( STDERR, '>', \$lwp_log )) {
             return( "Unable to redirect STDERR: $!" );
        }
    }
    ##################################
    # Turn on tracing
    ##################################
    if ( $verbose ) {
        LWP::Debug::level( '+' );
    }
    ##################################
    # Create cookie
    ##################################
    my $cookie = HTTP::Cookies->new();
    $cookie->set_cookie( 0,'asm_session','0','cgi-bin','','443',0,0,3600,0 );

    ##################################
    # Create UserAgent
    ##################################
    my $ua = LWP::UserAgent->new();

    ##################################
    # Set options
    ##################################
    my $url = "https://$server/cgi-bin/cgi?form=2";
    $ua->cookie_jar( $cookie );
    $ua->timeout(30);

    ##################################
    # Submit logon
    ##################################
    my $res = $ua->post( $url,
       [ user     => $cred[0],
         password => $cred[1],
         lang     => "0",
         submit   => "Log in"
       ]
    );

    ##################################
    # Logon failed
    ##################################
    if ( !$res->is_success() ) {
        return( $lwp_log.$res->status_line );
    }
    ##################################
    # To minimize number of GET/POSTs,
    # if we successfully logon, we should 
    # get back a valid cookie:
    #    Set-Cookie: asm_session=3038839768778613290
    #
    ##################################

    if ( $res->as_string =~ /Set-Cookie: asm_session=(\d+)/ ) {   
        ##############################
        # Successful logon....
        # Return:
        #    UserAgent 
        #    Server hostname
        #    UserId
        #    Redirected STDERR/STDOUT
        ##############################
        return( $ua,
                $server,
                $cred[0],
                \$lwp_log );
    }
    ##############################
    # Logon error 
    ##############################
    $res = $ua->get( $url );

    if ( !$res->is_success() ) {
        return( $lwp_log.$res->status_line );
    }
    ##############################
    # Check for specific failures
    ##############################
    if ( $res->content =~ /(Invalid user ID or password|Too many users)/ ) {
        return( $lwp_log.$1 );
    }
    return( $lwp_log."Logon failure" );

}


##########################################################################
# Logoff through remote FSP HTTP-interface
##########################################################################
sub disconnect {

    my $exp    = shift;
    my $ua     = @$exp[0];
    my $server = @$exp[1];
    my $uid    = @$exp[2];

    ##################################
    # POST Logoff
    ##################################
    my $res = $ua->post( 
            "https://$server/cgi-bin/cgi?form=1",
             [submit => "Log out"]);

    ##################################
    # Logoff failed
    ##################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
}


##########################################################################
# Execute FSP command
##########################################################################
sub process_cmd {

    my $exp     = shift;
    my $request = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $uid     = @$exp[2];
    my $command = $request->{command};   
    my $method  = $request->{method};   
    my %menu    = ();

    ##################################
    # We have to expand the main
    # menu since unfortunately, the
    # the forms numbers are not the
    # same across FSP models/firmware
    # versions.
    ##################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
         [form => "2",
          e    => "1" ]
    );
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    ##################################
    # Build hash of expanded menus
    ##################################
    foreach ( split /\n/, $res->content ) {
        if ( /form=(\d+).*window.status='(.*)'/ ) {
            $menu{$2} = $1;
        }
    }
    ##################################
    # Get form id  
    ##################################
    my $form = $menu{$cmds{$command}{$method}[0]};

    if ( !defined( $form )) {
        return( "Cannot find '$cmds{$command}{$method}[0]' menu" );
    }
    ##################################
    # Run command 
    ##################################
    my $result = $cmds{$command}{$method}[1]($exp, $request, $form, \%menu);
    return( $result );
}


##########################################################################
# Returns current power state
##########################################################################
sub state {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##################################
    # Get current power status 
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$form" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    ##################################
    # Get power state
    ##################################
    if ( $res->content =~ /Current system power state: (.*)<br>/) {
        return( $1 );
    }
    return( "unknown" );    
}


##########################################################################
# Powers FSP On
##########################################################################
sub on {
    return( power(@_,"on","on") );
}


##########################################################################
# Powers FSP Off
##########################################################################
sub off {
    return( power(@_,"off","of") );
}


##########################################################################
# Powers FSP On/Off
##########################################################################
sub power {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $state   = shift;
    my $button  = shift;
    my $command = $request->{command};
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##################################
    # Send Power On command 
    ##################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
         [form    => $form,
          sp      => "255",  # System boot speed: Fast
          is      => "1",    # Firmware boot side for the next boot: Temporary
          om      => "4",    # System operating mode: Normal
          ip      => "2",    # Boot to system server firmware: Running 
          plt     => "3",    # System power off policy: Stay on 
          $button => "Save settings and power $state"]
    );
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    if ( $res->content =~ 
            /(Powering on or off not allowed: invalid system state)/) {
        
        ##############################
        # Check current power state
        ##############################
        my $state = xCAT::PPCfsp::state(
                             $exp, 
                             $request, 
                             $menu->{$cmds{$command}{state}[0]},
                             $menu );

        if ( $state eq $state ) {
            return( "Success" );
        }
        return( $1 );
    }
    ##################################
    # Success 
    ##################################
    if ( $res->content =~ /(Operation completed successfully)/ ) {
        return( $1 );
    }
    return( "Unknown error" );
}


##########################################################################
# Reset FSP
##########################################################################
sub reset {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##################################
    # Send Reset command 
    ##################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
         [form   => $form,
          submit => "Continue" ]
    );
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success()) {
        return( $res->status_line );
    }
    if ( $res->content =~ 
        /(This feature is only available when the system is powered on)/ ) {
        return( $1 );
    }
    ##################################
    # Success
    ##################################
    if ( $res->content =~ /(Operation completed successfully)/ ) {
        return( $1 );
    }
    return( "Unknown error" );
}


##########################################################################
# Boots FSP (Off->On, On->Reset)
##########################################################################
sub boot {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $command = $request->{command};

    ##################################
    # Check current power state
    ##################################
    my $state = xCAT::PPCfsp::state( 
                             $exp, 
                             $request, 
                             $menu->{$cmds{$command}{state}[0]},
                             $menu );

    if ( $state !~ /^on|off$/ ) {
        return( "Unable to boot in state: '$state'" );
    }
    ##################################
    # Get command 
    ##################################
    my $method = ($state eq "on") ? "reset" : "off";

    ##################################
    # Get command form id
    ##################################
    $form = $menu->{$cmds{$command}{$method}[0]};

    ##################################
    # Run command
    ##################################
    my $result = $cmds{$method}[1]( $exp, $state, $form );
    return( $result );    
}


##########################################################################
# Clears Error/Event Logs         
##########################################################################
sub clear {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
 
    ##################################
    # Get Error/Event Logs URL 
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$form" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    ##################################
    # Clear all error/event log entries:
    # Are you sure? (OK/Cancel)
    ##################################
    my $form = HTML::Form->parse( $res->content, $res->base );
 
    ##################################
    # Return error
    ##################################
    if ( !defined( $form )) {
        return( "No Error/Event Logs form found" );
    }
    ##################################
    # Send Clear to JavaScript 
    ##################################
    my $request = $form->click( 'clear' );
    $res = $ua->request( $request );

    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    return( "Success" );
}


##########################################################################
# Gets the number of Error/Event Logs entries specified
##########################################################################
sub entries {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $opt     = $request->{opt};
    my $count   = (exists($opt->{e})) ? $opt->{e} : 9999;
    my $result;
    my $i = 1;

    ##################################
    # Get log entries
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$form" );
  
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    my @entries = split /\n/, $res->content;

    ##################################
    # Prepend header
    ##################################
    $result = (@entries) ?
        "\n#Log ID   Time                 Failing subsystem           Severity             SRC\n" :
        "No entries";
     
    ##################################
    # Parse log entries 
    ##################################
    foreach ( @entries ) {
        if ( /tabindex=\d+><\/td><td>(.*)<\/td><td / ) {
            my $values = $1;
            $values =~ s/<\/td><td>/  /g;
            $result.= "$values\n";

            if ( $i++ == $count ) {
                last;
            }
        }
    }
    return( $result );
}


##########################################################################
# Gets/Sets system time of day 
##########################################################################
sub time {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $option  = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##############################
    # Send command 
    ##############################
    my $result = xCAT::PPCfsp::tod( $exp, $request, $form ); 
    my $Rc = shift(@$result);

    ##############################
    # Return error
    ##############################
    if ( $Rc != SUCCESS ) {
        return( @$result[0] );
    }
    ##############################
    # Get time
    ##############################
    if ( !defined( $request->{op} )) {
        @$result[0] =~ /(\d+) (\d+) (\d+) $/; 
        return( "$1:$2:$3 UTC" );
    }
    ##############################
    # Set time 
    ##############################
    my @t   = split / /, @$result[0];
    my @new = split /-/, $request->{op};
    splice( @t,3,3,@new );

    ##############################
    # Send command 
    ##############################
    my $result = xCAT::PPCfsp::tod( $exp, $request, $form, \@t ); 
    my $Rc = shift(@$result);

    return( @$result[0] );
}


##########################################################################
# Gets/Sets system date 
##########################################################################
sub date {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $option  = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##############################
    # Send command 
    ##############################
    my $result = xCAT::PPCfsp::tod( $exp, $request, $form ); 
    my $Rc = shift(@$result);

    ##############################
    # Return error
    ##############################
    if ( $Rc != SUCCESS ) {
        return( @$result[0] );
    }
    ##############################
    # Get date
    ##############################
    if ( !defined( $request->{op} )) {
       @$result[0] =~ /^(\d+) (\d+) (\d+)/; 
       return( "$1-$2-$3" );
    }
    ##############################
    # Set date
    ##############################
    my @t   = split / /, @$result[0];
    my @new = split /-/, $request->{op};
    splice( @t,0,3,@new ); 

    ##############################
    # Send command
    ##############################
    my $result = xCAT::PPCfsp::tod( $exp, $request, $form, \@t );
    my $Rc = shift(@$result);

    return( @$result[0] );
}


##########################################################################
# Gets/Sets system time/date 
##########################################################################
sub tod {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $d       = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ######################################
    # Get time/date 
    ######################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$form" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content =~ /(only when the system is powered off)/ ) {
        return( [RC_ERROR,$1] );
    }
    ######################################
    # Get time/date fields  
    ######################################
    my $result;
    my @regex = (
        "name='omo' value='(\\d+)'",
        "name='od' value='(\\d+)'",
        "name='oy' value='(\\d+)'",
        "name='oh' value='(\\d+)'",
        "name='omi' value='(\\d+)'",
        "name='os' value='(\\d+)'",
    );
    foreach ( @regex ) {
        if ( $res->content !~ /$_/ ) {
            return( [RC_ERROR,"Error getting time of day"] );
        }
        $result.= "$1 ";
    }
    ######################################
    # Return time/date 
    ######################################
    if ( !defined( $d )) {
        return( [SUCCESS,$result] );
    }
    ######################################
    # Set time/date 
    ######################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
        [ form   => $form,
          mo     => @$d[0],
          d      => @$d[1],
          y      => @$d[2],
          h      => @$d[3],
          mi     => @$d[4],
          s      => @$d[5],
          submit => "Save settings" ]
    );
    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content =~ /(not allowed when the system is powered on)/ ) {
        return( [RC_ERROR,$1] );
    } 
    if ( $res->content =~ /(Invalid entry)/ ) {
        return( [RC_ERROR,$1] );
    } 
    return( [SUCCESS,"Success"] );
}



##########################################################################
# Gets/Sets I/O Adapter Enlarged Capacity
##########################################################################
sub iocap {
    return( option( @_,"pe" ));
}


##########################################################################
# Gets/Sets Auto Power Restart 
##########################################################
sub autopower {
    return( option( @_,"apor" ));
}


##########################################################################
# Gets/Sets options 
##########################################################################
sub option {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $option  = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $op      = $request->{op};

    ######################################
    # Get option URL
    ######################################
    if ( !defined( $op )) {
        my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$form" );

        ##################################
        # Return errors
        ##################################
        if ( !$res->is_success() ) {
            return( $res->status_line );
        }
        if ( $res->content !~ /selected value='\d+'>(Enabled|Disabled)</ ) {
            return( "Unknown" );
        }
        return($1);
    }
    ######################################
    # Set option
    ######################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
        [form    => $form,
         $option => ($op eq "disable") ? "0" : "1",
         submit  => "Save settings" ]
    );
    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    if ( $res->content !~ /Operation completed successfully/ ) {
        return( "Error setting option" );
    }
    return( "Success" );
}


##########################################################################
# Performs a Service Processor Dump
##########################################################################
sub spdump {

    my $exp     = shift;
    my $request = shift;
    my $form    = shift;
    my $menu    = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $dump_setting = 1;

    ######################################
    # Get Dump URL
    ######################################
    my $url = "https://$server/cgi-bin/cgi?form=$form";
    my $res = $ua->get( $url );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    ######################################
    # Dump disabled - enable it 
    ######################################
    if ( $res->content =~ /<option selected value='0'>Disabled/ ) {
        $res = $ua->post( "https://$server/cgi-bin/cgi",
            [ form  => $form,
              bdmp  => "1",
              save  => "Save settings" ]
        );
        ##################################
        # Return error
        ##################################
        if ( !$res->is_success() ) {
            return( $res->status_line );
        }
        if ( $res->content !~ /Operation completed successfully/ ) {
            return( "Error enabling dump setting" );
        }
        ##################################
        # Get Dump URL again
        ##################################
        $res = $ua->get( $url );

        if ( !$res->is_success() ) {
            return( $res->status_line );
        }
        ##################################
        # Restore setting after dump 
        ##################################
        $dump_setting = 0;
    }
    if ( $res->content !~ /(Save settings and initiate dump)/ ) {
        return( "'$1' button not found" );
    }
    ######################################
    # We will lose conection after dump 
    ######################################
    $ua->timeout(5);

    ######################################
    # Send dump command 
    ######################################
    $res = $ua->post( "https://$server/cgi-bin/cgi",
         [form => $form,
          bdmp => $dump_setting,
          dump => "Save settings and initiate dump"]
    );
    if ( !$res->is_success() ) {
        if ( $res->code ne "500" ) {
            return( $res->status_line );
        }
    }
    return( "Success" );
}


##########################################################################
# Gets all Error/Event Logs entries
##########################################################################
sub all {
    return( entries(@_) );
}


##########################################################################
# Gets all Error/Event Logs entries then clears the logs
##########################################################################
sub all_clear {

    my $result = entries( @_ );
    clear( @_);
    return( $result );
}


1;


