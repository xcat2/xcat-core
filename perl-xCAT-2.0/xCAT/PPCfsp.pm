# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCfsp;
use strict;
use LWP;
use HTTP::Cookies;


##########################################
# Globals
##########################################
my %cmds = ( 
  rpower => {
     state     => ["Power On/Off System", \&state],
     on        => ["Power On/Off System", \&on],
     off       => ["Power On/Off System", \&off],
     reset     => ["System Reboot",       \&reset], 
     boot      => ["Power On/Off System", \&boot] }, 
  reventlog => { 
     all       => ["Error/Event Logs",    \&all],
     all_clear => ["Error/Event Logs",    \&all_clear],
     entries   => ["Error/Event Logs",    \&entries],
     clear     => ["Error/Event Logs",    \&clear] }
);



##########################################################################
# FSP command handler through HTTP interface
##########################################################################
sub handler {

    my $server  = shift;
    my $request = shift;
    my $command = $request->{command};
    my $verbose = $request->{verbose};
    my $method  = $request->{method};
    my $start;

    ##################################
    # Check command 
    ##################################
    if ( !exists( $cmds{$command}{$method} )) {
        my %output;
        $output{node}->[0]->{name}->[0] = $server;
        $output{node}->[0]->{data}->[0]->{contents}->[0]= "Unsupported command";
        return( [\%output] );
    }
    ##################################
    # Start timer 
    ##################################
    if ( $verbose ) {
        $start = Time::HiRes::gettimeofday();
    }
    ##################################
    # Connect to remote FSP 
    ##################################
    my @exp = xCAT::PPCfsp::connect( $server, $verbose );

    if ( ref($exp[0]) ne "LWP::UserAgent" ) {
        my %output;
        $output{node}->[0]->{name}->[0] = $server;
        $output{node}->[0]->{data}->[0]->{contents}->[0] = $exp[0];
        return( [\%output] );
    }
    ##################################
    # Process FSP command 
    ##################################
    my $result = process_cmd( \@exp, $request );

    my %output;
    $output{node}->[0]->{name}->[0] = $server;
    $output{node}->[0]->{data}->[0]->{contents}->[0] = $result;

    ##################################
    # Disconnect from FSP 
    ##################################
    xCAT::PPCfsp::disconnect( \@exp );

    ##################################
    # Record Total time 
    ##################################
    if ( $verbose ) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $total   = sprintf( "Total Elapsed Time: %.3f sec\n", $elapsed );
        print STDERR $total;
    }
    return( [\%output] );

}


##########################################################################
# Logon through remote FSP HTTP-interface
##########################################################################
sub connect {

    my $server  = shift;
    my $verbose = shift;

    ##################################
    # Get userid/password 
    ##################################
    my @cred = xCAT::PPCdb::credentials( $server, "fsp" );

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
        return( $res->status_line );
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
        ##############################
       return( $ua,
                $server,
                $cred[0] );
    }
    ##############################
    # Logon error 
    ##############################
    $res = $ua->get( $url );

    if ( !$res->is_success() ) {
        return( $res->status_line );
    }
    ##############################
    # Check for specific failures
    ##############################
    my @error = ( 
        "Invalid user ID or password",
        "Too many users"
    );
    foreach ( @error ) {
        if ( $res->content =~ /$_/i ) {
            return( $_ );
        }
    }
    return( "Logon failure" );

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
    my $url = "https://$server/cgi-bin/cgi";
    my $res = $ua->post( $url,
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
        print STDERR $res->status_line();
        return;
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
    # Send Clear command 
    ##################################
    my $url = "https://$server/cgi-bin/cgi";
    my $res = $ua->post( $url,
         [form   => $form,
          submit => "Clear all error/event log entries" ]
    );
    ##################################
    # Return error
    ##################################
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
    my $url = "https://$server/cgi-bin/cgi?form=$form";
    my $res = $ua->get( $url );
  
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
        "#Log ID   Time                 Failing subsystem           Severity             SRC\n" :
        "No entries";
     
    ##################################
    # Parse log entries 
    ##################################
    foreach ( @entries ) {
        if ( /tabindex=[\d]+><\/td><td>(.*)<\/td><td / ) {
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
