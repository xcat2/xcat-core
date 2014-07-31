# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCfsp;
use strict;
use Getopt::Long;
use LWP;
use HTTP::Cookies;
use HTML::Form;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use Socket;
use xCAT::PPCdb; 
use xCAT::MsgUtils qw(verbose_message);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
##########################################
# Globals
##########################################
my %cmds = ( 
  rpower => {
     state         => ["Power On/Off System",           \&state],
     powercmd      => ["Power On/Off System",           \&powercmd],
     powercmd_boot => ["Power On/Off System",           \&boot], 
     reset         => ["System Reboot",                 \&reset] }, 
  reventlog => { 
     all           => ["Error/Event Logs",              \&all],
     all_clear     => ["Error/Event Logs",              \&all_clear],
     entries       => ["Error/Event Logs",              \&entries],
     clear         => ["Error/Event Logs",              \&clear] },
  rspconfig => {
     memdecfg      => ["Memory Deconfiguration",        \&memdecfg],
     decfg         => ["Deconfiguration Policies",      \&decfg],
     procdecfg     => ["Processor Deconfiguration",     \&procdecfg],
     iocap         => ["I/O Adapter Enlarged Capacity", \&iocap],
     time          => ["Time Of Day",                   \&time], 
     date          => ["Time Of Day",                   \&date], 
     autopower     => ["Auto Power Restart",            \&autopower],
     sysdump       => ["System Dump",                   \&sysdump],
     spdump        => ["Service Processor Dump",        \&spdump],
     network       => ["Network Configuration",         \&netcfg],
     dev           => ["Service Processor Command Line",  \&devenable],
     celogin1      => ["Service Processor Command Line",  \&ce1enable]},
);


##########################################################################
# FSP command handler through HTTP interface
##########################################################################
sub handler {

    my $server  = shift;
    my $request = shift;
    my $exp     = shift;
    my $flag    = shift;

    #####################################
    # Convert command to correct format
    #####################################
    if ( ref($request->{method}) ne "HASH" ) {
        $request->{method} = [{$request->{method}=>undef}]; 
    }
    #####################################
    # Process FSP command 
    #####################################
    my @outhash;
    my $result = process_cmd( $exp, $request );

    foreach ( @$result ) {
        my %output;
        $output{node}->[0]->{name}->[0] = $request->{host};
        $output{node}->[0]->{data}->[0]->{contents}->[0] = $server. ": ".@$_[1];
        $output{node}->[0]->{cmd}->[0] = @$_[2];
        $output{errorcode} = @$_[0];
        push @outhash, \%output;
    }
    #####################################
    # Disconnect from FSP 
    #####################################
    unless ($flag) {
    xCAT::PPCfsp::disconnect( $exp );
    }    
    return( \@outhash );

}


##########################################################################
# Logon through remote FSP HTTP-interface
##########################################################################
sub connect {

    my $req     = shift;
    my $server  = shift;
    my $verbose = $req->{verbose};
    my $timeout = $req->{fsptimeout};
    my $lwp_log;

    ##################################
    # Use timeout from site table 
    ##################################
    if ( !$timeout ) {
        $timeout = 30;
    }
    ##################################
    # Get userid/password 
    ##################################
    my $cred = undef;
    if (($req->{dev} eq '1') or ($req->{command} eq 'rpower')) {
        my @cred_array = xCAT::PPCdb::credentials($server, $req->{hwtype}, "celogin");
        $cred = \@cred_array;
    } else {
        $cred = $req->{$server}{cred};
    }
    ##################################
    # Redirect STDERR to variable 
    ##################################
    if ( $verbose ) {
        close STDERR;
        if ( !open( STDERR, '>', \$lwp_log )) {
             return( "Unable to redirect STDERR: $!" );
        }
    }
    $IO::Socket::SSL::VERSION = undef;
    eval { require Net::SSL };

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
    #my $hosttab  = xCAT::Table->new( 'hosts' );
    #if ( $hosttab) {
    #    my $hostshash = $hosttab->getNodeAttribs( $server, [qw(ip otherinterfaces)]);
    #    if ( $hostshash ) {
    #        $server = $hostshash->{ip};
    #    }
    #}
    $server = xCAT::NetworkUtils::getNodeIPaddress( $server );
    unless ($server) {
             return( "Unable to get IP address for $server" );
    }
#    my $serverip = inet_ntoa(inet_aton($server));
    my $url = "https://$server/cgi-bin/cgi?form=2";
    $ua->cookie_jar( $cookie );
    $ua->timeout( $timeout );

    ##################################
    # Submit logon
    ##################################
    my $res = $ua->post( $url,
       [ user     => @$cred[0],
         password => @$cred[1],
         lang     => "0",
         submit   => "Log in" ]
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
                @$cred[0],
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
    if ( $res->content =~ /(Invalid user ID or password|Too many users)/i ) {
        return( $lwp_log.$1 . ". Please check node attribute hcp and its password settings.");
    }
    return( $lwp_log."Logon failure" );

}
sub ce1enable {
    return &loginenable($_[0], $_[1], $_[2], "celogin1");
}

sub devenable {
    return &loginenable($_[0], $_[1], $_[2], "dev");
}
my %cmdline_for_log = (
    dev => {
        enable => "registry -Hw nets/DevEnabled 1",
        disable => "registry -Hw nets/DevEnabled 0",
        check_pwd => "registry -l DevPwdFile",
        create_pwd => "netsDynPwdTool --create dev FipSdev",
        password => "FipSdev"
    },
    celogin1 => {
        enable => "registry -Hw nets/CE1Enabled 1",
        disable => "registry -Hw nets/CE1Enabled 0",
        check_pwd => "registry -l Ce1PwdFile",
        create_pwd => "netsDynPwdTool --create celogin1 FipSce1",
        password => "FipSce1"
    },
    );
sub send_command {
    my $ua     = shift;
    my $server = shift;
    my $id = shift;
    my $log_name = shift;
    my $cmd = shift;
    my $cmd_line = $cmdline_for_log{$log_name}{$cmd};
    if (!defined($cmd_line)) {
        return undef;
    }
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
            [ form   => $id,
            cmd   => $cmd_line,
            submit => "Execute" ]
            );

    if ( !$res->is_success() ) {
        return undef;
    }
    if ( $res->content =~ /(not allowed.*\.|Invalid entry)/ ) {
        return undef;
    } 
    return $res->content;
}
sub loginstate {
    my $ua = shift;
    my $server = shift;
    my $log_name = shift;
    my $url = "https://$server/cgi-bin/cgi?form=4";
    my $res = $ua->get($url);
    if (!$res->is_success()) {
        return ([RC_ERROR, $res->status_line]);
    }
    if ($res->content =~ m#[\d\D]+Status[\d\D]+$log_name</td><td[^\>]*>(\w+)</td>#) {
        my $out = sprintf("%9s: %8s", $log_name, $1);
        return ( [SUCCESS, $out]);
    } else {
        return ( [RC_ERROR, "not found status for $log_name"]);
    }
}

sub loginenable {
    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $log_name = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    
    my $value = $request->{method}{$log_name};
    if (!defined($value)) {
        return &loginstate($ua, $server, $log_name);
       }
    my $url = "https://$server/cgi-bin/cgi?form=$id";
    my $res = $ua->get( $url );
    if (!$res->is_success()) {
        return( [RC_ERROR,$res->status_line] );
    }

    $res = &send_command($ua, $server, $id, $log_name, $value);
    if (!defined($res)) {
        return ([RC_ERROR, "Send command Failed"]);
    }
    if ( $value =~ m/^disable$/ ) {
        my $out = sprintf("%9s: Disabled", $log_name);
        return( [SUCCESS, $out] );
    }
#check password#
    $res = &send_command($ua, $server, $id, $log_name, "check_pwd");
    if (!defined($res)) {
        return ([RC_ERROR, "Send command Failed"]);
    }
    my $password = undef; 
    if ($res =~ m/\[\d+([a-zA-Z]+)\d+\]/) {
        $password = $1;
    } else {
# create password #
        $res = &send_command($ua, $server, $id, $log_name, "create_pwd");
        if (!defined($res)) {
            return ([RC_ERROR, "Send command Failed"]);
        }
        $password = $cmdline_for_log{$log_name}{password};
        print "create password for $log_name is '$cmdline_for_log{$log_name}{password}'\n";
    }
    my $out = sprintf("%9s:  Enabled, password: $password", $log_name);
    return( [SUCCESS, $out] );
}
sub disconnect {

    my $exp    = shift;
    my $ua     = @$exp[0];
    my $server = @$exp[1];
    my $uid    = @$exp[2];

    ##################################
    # POST Logoff
    ##################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi?form=1", 
                  [ submit => "Log out" ]
    );
    ##################################
    # Logoff failed
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    return( [SUCCESS,"Success"] );
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
    my $methods = $request->{method};   
    my %menu    = ();
    my @result;

    ##################################
    # We have to expand the main
    # menu since unfortunately, the
    # the forms numbers are not the
    # same across FSP models/firmware
    # versions.
    ##################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
         [ form => "2",
           e    => "1" ]
    );
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        my @tmpres = (RC_ERROR, $res->status_line);
        my @rs;
        push @rs, \@tmpres;
        return(\@rs );
    }
    ##################################
    # Build hash of expanded menus
    ##################################
    foreach ( split /\n/, $res->content ) {
        if ( /form=(\d+).*window.status='(.*)'/ ) {
            $menu{$2} = $1;
        }
    }
    foreach ( keys %$methods ) {
        ##############################
        # Get form id  
        ##############################
        my $form = $menu{$cmds{$command}{$_}[0]};
        if ( !defined( $form )) {
        my @tmpres = (RC_ERROR, "Cannot find '$cmds{$command}{$_}[0]' menu");
        my @rs;
        push @rs, \@tmpres;
        return(\@rs );
        }
        ##################################
        # Run command 
        ##################################
        xCAT::MsgUtils->verbose_message($request, "$command :$_ for node:$server."); 
        my $res = $cmds{$command}{$_}[1]($exp, $request, $form, \%menu);
        push @$res, $_;
        push @result, $res;
    }
    return( \@result );
}


##########################################################################
# Returns current power state
##########################################################################
sub state {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##################################
    # Get current power status 
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ##################################
    # Get power state
    ##################################
    if ( $res->content =~ /Current system power state: (.*)<br>/) {
        return( [SUCCESS,$1] );
    }
    return( [RC_ERROR,"unknown"] );    
}


##########################################################################
# Powers FSP On/Off
##########################################################################
sub powercmd {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $op      = $request->{op};
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##################################
    # Get Power On/Off System URL 
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ##################################
    # Get current power state
    ##################################
    if ( $res->content !~ /Current system power state: (.*)<br>/) {
        return( [RC_ERROR,"Unable to determine current power state"] );
    }
    my $state = $1;

    ##################################
    # Already in that state
    ##################################
    if ( $op =~ /^$state$/i ) {
        return( [SUCCESS,"Success"] );
    }
    ##################################
    # Get "Power On/Off System" form 
    ##################################
    my $form = HTML::Form->parse( $res->content, $res->base );

    ##################################
    # Return error
    ##################################
    if ( !defined( $form )) {
        return( [RC_ERROR,"'Power On/Off System' form not found"] );
    }
    ##################################
    # Get "Save and Submit" button
    ##################################
    my $button = ($op eq "on") ? "on" : "of"; 
    my @inputs = $form->inputs();

    if ( !grep( $_->{name} eq $button, @inputs )) {
        return( [RC_ERROR,"Unable to power $op from state: $state"] );
    } 
    ##################################
    # Send command 
    ##################################
    my $data = $form->click( $button );
    $res = $ua->request( $data );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content =~ /(not allowed.*\.)/ ) {
        return( [RC_ERROR,$1] );
    }
    ##################################
    # Success 
    ##################################
    if ( $res->content =~ /(Operation completed successfully)/ ) {
        return( [SUCCESS,"Success"] );
    }
    return( [RC_ERROR,"Unknown error"] );
}


##########################################################################
# Reset FSP
##########################################################################
sub reset {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ##################################
    # Send Reset command 
    ##################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
         [ form   => $id,
           submit => "Continue" ]
    );
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success()) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content =~ /(This feature is only available.*)/ ) { 
        return( [RC_ERROR,$1] );
    }
    ##################################
    # Success
    ##################################
    if ( $res->content =~ /(Operation completed successfully)/ ) {
        return( [SUCCESS,"Success"] );
    }
    return( [RC_ERROR,"Unknown error"] );
}


##########################################################################
# Boots FSP (Off->On, On->Reset)
##########################################################################
sub boot {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
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
    my $Rc = shift(@$state);

    ##################################
    # Return error 
    ##################################
    if ( $Rc != SUCCESS ) {
        return( [$Rc,@$state[0]] );
    }
    if ( @$state[0] !~ /^(on|off)$/i ) {
        return( [RC_ERROR,"Unable to boot in state: '@$state[0]'"] );
    }
    ##################################
    # Get command 
    ##################################
    $request->{op} = "on"; 
    my $method = ( $state =~ /^on$/i ) ? "reset" : "powercmd"; 
  
    ##################################
    # Get command form id
    ##################################
    $id = $menu->{$cmds{$command}{$method}[0]};

    ##################################
    # Run command
    ##################################
    my $result = $cmds{$command}{$method}[1]( $exp, $request, $id );
    return( $result );    
}


##########################################################################
# Clears Error/Event Logs         
##########################################################################
sub clear {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
 
    ##################################
    # Get Error/Event Logs URL 
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
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
        return( [RC_ERROR,"'Error/Event Logs' form not found"] );
    }
    ##################################
    # Send Clear to JavaScript 
    ##################################
    my $data = $form->click( 'clear' );
    $res = $ua->request( $data );

    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    return( [SUCCESS,"Success"] );
}


##########################################################################
# Gets the number of Error/Event Logs entries specified
##########################################################################
sub entries {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $opt     = $request->{opt};
    my $count   = (exists($opt->{e})) ? $opt->{e} : -1; 
    my $result;
    my $i = 1;

    ##################################
    # Get log entries
    ##################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );
  
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
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
        if ( /tabindex=(\d+)><\/td><td>(.*)<\/td><\/tr>/ ){
            my $values = $2;
            $values =~ s/<\/td><td>/  /g;
            $result.= "$values\n";

            if ( $i++ == $count ) {
                last;
            }
        }
    }
    return( [SUCCESS,$result] );
}


##########################################################################
# Gets/Sets system time of day 
##########################################################################
sub time {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $value   = $request->{method}{time};

    ##############################
    # Send command 
    ##############################
    my $result = xCAT::PPCfsp::timeofday( $exp, $request, $id ); 
    my $Rc = shift(@$result);

    ##############################
    # Return error
    ##############################
    if ( $Rc != SUCCESS ) {
        return( [$Rc,"Time: @$result[0]"] );
    }
    ##############################
    # Get time
    ##############################
    if ( !defined( $value )) {
        @$result[0] =~ /(\d+) (\d+) (\d+) $/; 
        return( [SUCCESS,sprintf( "Time: %02d:%02d:%02d UTC",$1,$2,$3 )] );
    }
    ##############################
    # Set time 
    ##############################
    my @t   = split / /, @$result[0];
    my @new = split /:/, $value;
    splice( @t,3,3,@new );

    ##############################
    # Send command 
    ##############################
    my $time = xCAT::PPCfsp::timeofday( $exp, $request, $id, \@t ); 
    $Rc = shift(@$time);
    return( [$Rc,"Time: @$time[0]"] );
}


##########################################################################
# Gets/Sets system date 
##########################################################################
sub date {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $value   = $request->{method}{date};

    ##############################
    # Send command 
    ##############################
    my $result = xCAT::PPCfsp::timeofday( $exp, $request, $id ); 
    my $Rc = shift(@$result);

    ##############################
    # Return error
    ##############################
    if ( $Rc != SUCCESS ) {
        return( [$Rc,"Date: @$result[0]"] );
    }
    ##############################
    # Get date
    ##############################
    if ( !defined( $value )) {
       @$result[0] =~ /^(\d+) (\d+) (\d+)/; 
       return( [SUCCESS,sprintf( "Date: %02d-%02d-%4d",$1,$2,$3 )] );
    }
    ##############################
    # Set date
    ##############################
    my @t   = split / /, @$result[0];
    my @new = split /-/, $value;
    splice( @t,0,3,@new ); 

    ##############################
    # Send command
    ##############################
    my $date = xCAT::PPCfsp::timeofday( $exp, $request, $id, \@t );
    $Rc = shift(@$date);
    return( [$Rc,"Date: @$date[0]"] );
}


##########################################################################
# Gets/Sets system time/date 
##########################################################################
sub timeofday {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $d       = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ######################################
    # Get time/date 
    ######################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content =~ /(only when the system is powered off)/ ) {
        return( [RC_ERROR,$1] );
    }
    ##################################
    # Get "Power On/Off System" form
    ##################################
    my $form = HTML::Form->parse( $res->content, $res->base );

    ##################################
    # Return error
    ##################################
    if ( !defined( $form )) {
        return( [RC_ERROR,"'Time Of Day' form not found"] );
    }
    ######################################
    # Get time/date fields  
    ######################################
    my $result;
    my @option = qw(omo od oy oh omi os);
   
    foreach ( @option ) {
        if ( $res->content !~ /name='$_' value='(\d+)'/ ) {
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
    $res = $ua->post( "https://$server/cgi-bin/cgi",
        [ form   => $id,
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
    if ( $res->content =~ /(not allowed.*\.|Invalid entry)/ ) {
        return( [RC_ERROR,$1] );
    } 
    return( [SUCCESS,"Success"] );
}


##########################################################################
# Gets/Sets I/O Adapter Enlarged Capacity
##########################################################################
sub iocap {

    my $result = option( @_,"iocap" );
    @$result[1] = "iocap: @$result[1]";
    return( $result );
}


##########################################################################
# Gets/Sets Auto Power Restart 
##########################################################
sub autopower {

    my $result = option( @_,"autopower" );
    @$result[1] = "autopower: @$result[1]";
    return( $result );
}


##########################################################################
# Gets/Sets options 
##########################################################################
sub option {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;  
    my $menu    = shift;
    my $command = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $option  = ($command =~ /^iocap$/) ? "pe" : "apor";  
    my $value   = $request->{method}{$command};

    ######################################
    # Get option URL
    ######################################
    if ( !defined( $value )) {
        my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );

        ##################################
        # Return errors
        ##################################
        if ( !$res->is_success() ) {
            return( [RC_ERROR,$res->status_line] );
        }
        if ( $res->content !~ /selected value='\d+'>(\w+)</ ) {
            return( [RC_ERROR,"Unknown"] );
        }
        return( [SUCCESS,$1] );
    }
    ######################################
    # Set option
    ######################################
    my $res = $ua->post( "https://$server/cgi-bin/cgi",
        [ form    => $id,
          $option => ($value =~ /^disable$/i) ? "0" : "1",
          submit  => "Save settings" ]
    );
    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content !~ /Operation completed successfully/i ) {
        return( [RC_ERROR,"Error setting option"] );
    }
    return( [SUCCESS,"Success"] );
}


##########################################################################
# Gets/Sets Memory Deconfiguration
##########################################################################
sub memdecfg {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $values  = $request->{method}{memdecfg};

    ##################################
    # Get settings
    ##################################
    if ( !defined( $values )) {
        return( readdecfg( $exp, $request, $id ));
    }
    ##################################
    # Set settings
    ##################################
    $values =~ /^(configure|deconfigure):(\d+):(unit|bank):(all|[\d,]+)$/i;
    return( writedecfg( $exp, $request, $id, $1, $2, $3, $4 ));
}


##########################################################################
# Gets/Sets Processor Deconfiguration
##########################################################################
sub procdecfg {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $values  = $request->{method}{procdecfg};

    ##################################
    # Get settings
    ##################################
    if ( !defined( $values )) {
        return( readdecfg( $exp, $request, $id ));
    }
    ##################################
    # Set settings
    ##################################
    $values =~ /^(configure|deconfigure):(\d+):(all|[\d,]+)$/i;
    return( writedecfg( $exp, $request, $id, $1, $2, "Processor ID",$3 ));
}



##########################################################################
# Sets Deconfiguration settings
##########################################################################
sub writedecfg {

    my $exp     = shift;
    my $request = shift;
    my $formid  = shift;
    my $state   = shift;
    my $unit    = shift;
    my $type    = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ######################################
    # Command-line parameter specified 
    ######################################
    my @ids    = split /,/, $id;
    my $select = ($state =~ /^configure$/i) ? 0 : 1; 

    ######################################
    # Get Deconfiguration URL
    ######################################
    my $url = "https://$server/cgi-bin/cgi?form=$formid";
    my $res = $ua->get( $url );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ######################################
    # Find unit specified by user 
    ######################################
    my $html = $res->content;
    my $value;

    while ( $html =~
       s/<input type=radio name=(\w+) value=(\w+)[^>]+><\/td><td>(\d+)<// ) {
       if ( $unit eq $3 ) {
           $value = $2;
       }
    }
    if ( !defined( $value )) {
        return( [RC_ERROR,"Processing unit=$unit not found"] );
    }
    ######################################
    # Get current settings
    ######################################
    my $form = HTML::Form->parse( $res->content, $res->base );
    my @inputs = $form->inputs();

    ######################################
    # Return error
    ######################################
    if ( !defined( $form )) {
        return( [RC_ERROR,"'Deconfiguration' form not found"] );
    }
    ######################################
    # Find radio button
    ######################################
    my ($radio) = grep($_->{type} eq "radio", @inputs );
    if ( !defined( $radio )) {
        return( [RC_ERROR,"Radio button not found"] );
    }
    ######################################
    # Select radio button
    ######################################
    $radio->value( $value );

    ######################################
    # Send command
    ######################################
    my $data = $form->click( "submit" );
    $res = $ua->request( $data );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ######################################
    # Get current settings
    ######################################
    $form = HTML::Form->parse( $res->content, $res->base );
    @inputs = $form->inputs();

    ######################################
    # Return error
    ######################################
    if ( !defined( $form )) {
        return( [RC_ERROR,"'Deconfiguration' form not found"] );
    }
    ######################################
    # Get options 
    ######################################
    my %options = ();
    my %key     = ();
    my $setall  = 0;

    foreach ( @inputs ) {
        if ( $_->type eq "option" ) {
            push @{$options{$_->name}}, $_->value;
        }
    }
    my @units = split /<thead align=left><tr><th>/, $res->content;
    shift(@units);
    $html = undef;

    ######################################
    # Break into unit types 
    ######################################
    foreach ( @units ) {
        /([\w\s]+)<\/th><th>/;
        if ( $1 =~ /$type/i ) {
            $html = $_;
            last;
        }
    }
    ######################################
    # Look for unit type 
    ######################################
    if ( !defined( $html )) {
        return( [RC_ERROR,"unit=$unit '$type' not found"] );
    }
    ######################################
    # Set all IDs 
    ######################################
    if ( $ids[0] eq "all" ) {
       @ids = ();
       $setall = 1;
    }
    ######################################
    # Associate 'option' name with ID 
    ######################################
    foreach ( keys %options ) {
        if ( $html =~ /\n<tr><td>(\d+)<\/td><td>.*name='$_'/ ) {
            if ( $setall ) {
                push @ids, $1;
            }
            push @{$options{$_}}, $1;
        }
    }
    ######################################
    # Check if each specified ID exist 
    ######################################
    foreach ( @ids ) {
        foreach my $name ( keys %options ) {
            my $id = @{$options{$name}}[1];
            
            if ( $_ eq $id ) {
                my $value = @{$options{$name}}[0];
                $key{$id} = [$value,$name];
            }
        }
    }
    ######################################
    # Check if ID exists 
    ######################################
    foreach ( @ids ) {
        if ( !exists( $key{$_} )) {
            return( [RC_ERROR,"Processing unit=$unit $type=$_ not found"] );
        }
        my $value = @{$key{$_}}[0];
        if ( $value == $select ) {
           delete $key{$_};
        }
    }
    ######################################
    # Check in already in that state 
    ######################################
    if ( !scalar( keys %key )) {
        return( [RC_ERROR,"All $type(s) specified already in '$state' state"]); 
    } 
    ######################################
    # Make changes to form  
    ######################################
    foreach ( keys %key ) {
        my $name = @{$key{$_}}[1];
        my ($button) = grep($_->{name} eq $name, @inputs );
        if ( !defined( $button )) {
            return( [RC_ERROR,"Option=$name not found"] );
        }
        $button->value( $select );
    }
    ##################################
    # Send command
    ##################################
    $data = $form->click( "submit" );
    $res = $ua->request( $data );

    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    if ( $res->content =~ /\n(.*Operation not allowed.*\.)/ ) {
        my $result = $1;
        $result =~ s/<br><br>/\n/g;
        return( [RC_ERROR,$result] ); 
    }
    return( [SUCCESS,"Success"] );       
}


##########################################################################
# Gets Deconfiguration settings
##########################################################################
sub readdecfg {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $result  = "\n";

    ######################################
    # Get Deconfiguration URL
    ######################################
    my $url = "https://$server/cgi-bin/cgi?form=$id";
    my $res = $ua->get( $url );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ######################################
    # Get current settings
    ######################################
    my $form = HTML::Form->parse( $res->content, $res->base );
    my @inputs = $form->inputs();
    my $html   = $res->content;
    my $unit;

    ######################################
    # Return error
    ######################################
    if ( !defined( $form )) {
        return( [RC_ERROR,"'Deconfiguration' form not found"] );
    }
    ######################################
    # Find radio button
    ######################################
    my ($radio) = grep($_->{type} eq "radio", @inputs );
    if ( !defined( $radio )) {
        return( [RC_ERROR,"Radio button not found"] ); 
    }
    ######################################
    # Find unit identifier
    ######################################
    if ( $html =~ /<thead align=left><tr><th><\/th><th>([\w\s]+)</ ) {
        $unit = $1;
    }
    foreach ( @{$radio->{menu}} ) {
        ##################################
        # Select radio button
        ##################################
        my $value = ( ref($_) eq 'HASH' ) ? $_->{value} : $_;
        $radio->value( $value );

        ##################################
        # Send command
        ##################################
        my $request = $form->click( "submit" );
        $res = $ua->request( $request );

        ##################################
        # Return error
        ##################################
        if ( !$res->is_success() ) {
            return( [RC_ERROR,$res->status_line] );
        }
        $html = $res->content;

        ##################################
        # Find unit identifier
        ##################################
        if ( $html =~ /<p>([\w\s:]+)</ ) {
            $result.= "$1\n";
        }   
        my @group = split /<thead align=left><tr><th>/, $res->content;
        shift(@group);

        foreach ( @group ) {
            my @maxlen = ();
            my @values = ();

            ##############################
            # Entry heading
            ##############################
            /(.*)<\/th><\/tr><\/thead>/;
            my @heading = split /<\/th><th>/, $1;
            pop(@heading);
            pop(@heading);

            foreach ( @heading ) {
                push @maxlen, length($_);
            }
            ##############################
            # Entry values
            ##############################
            foreach ( split /\n/ ) {
                if ( s/^<tr><td>// ) {
                    s/<br>/ /g;

                    my $i = 0;
                    my @d = split /<\/td><td>/;
                    pop(@d);
                    pop(@d);

                    ######################
                    # Length formatting
                    ######################
                    foreach ( @d ) {
                        if ( length($_) > $maxlen[$i] ) {
                            $maxlen[$i] = length($_);
                        }
                        $i++;
                    }
                    push @values, [@d];
                }
            }
            ##############################
            # Output header
            ##############################
            my $i = 0;
            foreach ( @heading ) {
                my $format = sprintf( "%%-%ds",$maxlen[$i++]+2 );
                $result.= sprintf( $format, $_ );
            }
            $result.= "\n";

            ##############################
            # Output values
            ##############################
            foreach ( @values ) {
                $i = 0;
                foreach ( @$_ ) {
                    my $format = sprintf( "%%-%ds",$maxlen[$i++]+2 );
                    $result.= sprintf( $format, $_ );
                }
                $result.= "\n";
            }
            $result.= "\n";
        }
    }
    return( [SUCCESS,$result] );
}


##########################################################################
# Gets/sets Deconfiguration Policies
##########################################################################
sub decfg {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $value   = $request->{method}{decfg};

    ######################################
    # Get Deconfiguration Policy URL
    ######################################
    my $res = $ua->get( "https://$server/cgi-bin/cgi?form=$id" );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    my %d    = ();
    my $len  = 0;
    my $i    = 0;
    my $html = $res->content;
    my $result;

    while ( $html =~ s/<br>(.*:)\s+<// ) {
        my $desc  = $1;
        my $value = "unknown";
        my $name;

        ##################################
        # Get values
        ##################################
        if ( $html =~ s/selected value='\d+'>(\w+)<// ) {
            $value = $1;
        }
        ##################################
        # Get name 
        ##################################
        if ( $html =~ s/select name='(\w+)'// ) {
            $name = $1;
        }
        ##################################
        # Save for formatting output 
        ##################################
        if ( length( $desc ) > $len ) {
            $len = length( $desc );
        }
        $d{$desc} = [$value,$name];
    }

    ######################################
    # Get Deconfiguration Policy
    ######################################
    if ( !defined( $value )) {
        my $format = sprintf( "\n%%-%ds %%s",$len );
        foreach ( keys %d ) {
            $result.= sprintf( $format,$_,$d{$_}[0] );
        }
        return( [SUCCESS,$result] );
    }
    ######################################
    # Set Deconfiguration Policy
    ######################################
    my ($op,$names) = split /:/, $value;
    my @policy      = split /,/, $names;
    my $state       = ($op =~ /^enable$/i) ? 0 : 1;

    ######################################
    # Check for duplicate policies
    ######################################
    foreach my $name ( @policy ) {
        if ( grep( /^$name$/, @policy ) > 1 ) {
            return( [RC_ERROR,"Duplicate policy specified: $name"] );
        }
    }
    ######################################
    # Get Deconfiguration Policy form 
    ######################################
    my $form = HTML::Form->parse( $res->content, $res->base );

    ######################################
    # Return error
    ######################################
    if ( !defined( $form )) {
        return( [RC_ERROR,"'Deconfiguration Policies' form not found"] );
    }
    ######################################
    # Get hidden inputs 
    ######################################
    my @inputs = $form->inputs();

    my (@hidden) = grep( $_->{type} eq "hidden", @inputs );
    if ( !@hidden ) {
        return( [RC_ERROR,"<input type='hidden'> not found"] );
    }
    ######################################
    # Check for invalid policies
    ######################################
    foreach my $name ( @policy ) {
        my @p = grep( $_->{value_name}=~/\b$name\b/i, @hidden );

        if ( @p > 1 ) {
            return( [RC_ERROR,"Ambiguous policy: $name"] );
        } elsif ( !@p ) {
            return( [RC_ERROR,"Invalid policy: $name"] );
        }
        my $value_name = $p[0]->{value_name};
        $policy[$i++] = @{$d{$value_name}}[1]; 
    }
    ######################################
    # Select option 
    ######################################
    foreach my $name ( @policy ) {
        my ($in) = grep( $_->{name} eq $name, @inputs );
        $in->value( $state );
    }
    ######################################
    # Send command
    ######################################
    my $data = $form->click( "submit" );
    $res = $ua->request( $data );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    return( [SUCCESS,"Success"] );
}


##########################################################################
# Performs a System Dump
##########################################################################
sub sysdump {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];

    ######################################
    # Get Dump URL
    ######################################
    my $url = "https://$server/cgi-bin/cgi?form=$id";
    my $res = $ua->get( $url );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ######################################
    # Possible errors: 
    # not allowed when a dump of this type exists.
    # not allowed when system is powered off.
    ######################################
    if ( $res->content =~ /(not allowed.*\.)/ ) {
        return( [RC_ERROR,$1] );
    }
    my @d;
    my $html = $res->content;

    ######################################
    # Get current dump settings 
    ######################################
    foreach ( my $i=0; $i<3; $i++ ) {
	if ($i == 0) {
            if ($html !~ /Dump policy:\s+(\w+)/) {
                goto ERROR;
            }
        }

        if ($i != 0) {
	    if ($html !~ s/selected value='(\d+)'//) {
ERROR:
                return( [RC_ERROR,"Error getting dump settings"] );
	    }
        }

        push @d, $1;
    }
    ######################################
    # Send dump command
    ######################################
    $res = $ua->post( "https://$server/cgi-bin/cgi",
         [ form     => $id,
           policy   => $d[0],
           content  => $d[1],
           phyp     => $d[2],
           page     => "1",
           takedump => "Save settings and initiate dump" ]
    );
    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ######################################
    # Continue ? 
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    $res = $ua->post( "https://$server/cgi-bin/cgi",
         [ form     => $id,
           policy   => $d[0],
           content  => $d[1],
           phyp     => $d[2],
           page     => "2",
           takedump => "Save settings and initiate dump",
           submit   => "Continue"]
    );
    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    return( [SUCCESS,"Success"] );
}


##########################################################################
# Performs a Service Processor Dump
##########################################################################
sub spdump {

    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    my $ua      = @$exp[0];
    my $server  = @$exp[1];
    my $button  = "Save settings and initiate dump";
    my $dump_setting = 1;

    ######################################
    # Get Dump URL
    ######################################
    my $url = "https://$server/cgi-bin/cgi?form=$id";
    my $res = $ua->get( $url );

    ######################################
    # Return error
    ######################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }
    ######################################
    # Dump disabled - enable it 
    ######################################
    if ( $res->content =~ /selected value='0'>Disabled/ ) {
        $res = $ua->post( "https://$server/cgi-bin/cgi",
            [ form  => $id,
              bdmp  => "1",
              save  => "Save settings" ]
        );
        ##################################
        # Return error
        ##################################
        if ( !$res->is_success() ) {
            return( [RC_ERROR,$res->status_line] );
        }
        if ( $res->content !~ /Operation completed successfully/ ) {
            return( [RC_ERROR,"Error enabling dump setting"] );
        }
        ##################################
        # Get Dump URL again
        ##################################
        $res = $ua->get( $url );

        if ( !$res->is_success() ) {
            return( [RC_ERROR,$res->status_line] );
        }
        ##################################
        # Restore setting after dump 
        ##################################
        $dump_setting = 0;
    }
    if ( $res->content !~ /$button/ ) {
        #################################################################
        # For some firmware levels, button is changed to "initiate dump"
        #################################################################
        $button = "Initiate dump";
        if ( $res->content !~ /$button/ ) {
            return( [RC_ERROR,"'$button' button not found"] );
        }
    }
    ######################################
    # We will lose conection after dump 
    ######################################
    $ua->timeout(10);

    ######################################
    # Send dump command 
    ######################################
    $res = $ua->post( "https://$server/cgi-bin/cgi",
         [ form => $id,
           bdmp => $dump_setting,
           dump => $button ]
    );
    ######################################
    # Will lose connection on success -500 
    ######################################
    if ( !$res->is_success() ) {
        if ( $res->code ne "500" ) {
            return( [RC_ERROR,$res->status_line] );
        }
    }
    return( [SUCCESS,"Success"] );
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

##########################################################################
# Gets and set network configuration
##########################################################################
sub netcfg
{
    my $exp     = shift;
    my $request = shift;
    my $id      = shift;
    
    ######################################
    # Parsing arg
    ######################################
    my $set_config = 0;
    my ($inc_name, $inc_ip, $inc_host, $inc_gateway, $inc_netmask) = ();
    my $real_inc_name = undef;
    if ( $request->{'method'}->{'network'})
    {
        $set_config = 1;
    }
    
    my $interfaces = undef;
    my $form = undef;
    
    my $res = get_netcfg( $exp, $request, $id, \$interfaces, \$form);
    return $res if ( $res->[0] == RC_ERROR);
		
    my $output = "";
    #######################################
    # Set configuration
    #######################################
    if ( $set_config)
    {
        return set_netcfg( $exp, $request, $interfaces, $form);
    }
    #######################################
    # Get configuration and format output
    #######################################
    else
    {
        return format_netcfg( $interfaces);
    }
    
}

##########################################################################
# Gets network configuration
##########################################################################
sub get_netcfg
{
    my $exp        = shift;
    my $request    = shift;
    my $id         = shift;
    my $interfaces = shift;
    my $form       = shift;
    my $ua         = @$exp[0];
    my $server     = @$exp[1];

	######################################
    # Get Network Configuration URL
    ######################################
    my $url = "https://$server/cgi-bin/cgi?form=$id";
    my $res = $ua->get( $url );
   
    ##################################
    # Return error
    ##################################
    if ( !$res->is_success() ) {
        return( [RC_ERROR,$res->status_line] );
    }

    ##################################
    # Get "Network Configuraiton" form 
    ##################################
    $$form = HTML::Form->parse( $res->content, $res->base );

    ##################################
    # Return error
    ##################################
    if ( !defined( $$form )) {
        return( [RC_ERROR,"'Network Configuration' form not found at parse"] );
    } 

    ##################################
    # For some P6 machines
    ##################################
    if ( $$form->find_input('ip', 'radio', 1))
    {    
        my $ipv4Radio = $$form->find_input('ip', 'radio', 1);
        if (!$ipv4Radio)
        {
            print "Cannot find IPv4 option\n";
            exit;
        }
        #$ipv4Radio->check();

        my $data = $$form->click('submit');
        $res = $ua->request( $data);
        $$form = HTML::Form->parse( $res->content, $res->base );
        if ( !defined( $$form )) {
            return( [RC_ERROR,"'Network Configuration' form not found at submit"] );
        } 
   } elsif ( $$form->find_input('submit', 'submit', 1) ) {
        my $data = $$form->click('submit');
        sleep 5;
        $res = $ua->request( $data);
        $$form = HTML::Form->parse( $res->content, $res->base );
        if ( !defined( $$form )) {
            return( [RC_ERROR,"'Network Configuration' form not found at submit2"] );
        }
        if ( $$form->find_input('ip', 'radio', 1))
        {
            my $ipv4Radio = $$form->find_input('ip', 'radio', 1);
            if (!$ipv4Radio)
            {
                print "Cannot find IPv4 option\n";
                exit;
            }
            #$ipv4Radio->check();
    
            my $data = $$form->click('submit');
            $res = $ua->request( $data);
            $$form = HTML::Form->parse( $res->content, $res->base );
            if ( !defined( $$form )) {
                return( [RC_ERROR,"'Network Configuration' form not found at submit3"] );
            }
        }
     }    
    #######################################
    # Parse the form to get the inc input
    #######################################
    my $has_found_all = 0;
    my $i = 0;
    while ( not $has_found_all)
    {
        my $input = $$form->find_input( "interface$i", 'checkbox');
        if ( ! $input)
        {
            $has_found_all = 1;
        }
        else
        {
            $$interfaces->{"interface$i"}->{'selected'} = $input;
            $$interfaces->{"interface$i"}->{'type'}     = $$form->find_input("ip$i", 'option');
            $$interfaces->{"interface$i"}->{'hostname'} = $$form->find_input("host$i", 'text');
            $$interfaces->{"interface$i"}->{'ip'}       = $$form->find_input("static_ip$i", 'text');
            $$interfaces->{"interface$i"}->{'gateway'}  = $$form->find_input("gateway$i", 'text');
            $$interfaces->{"interface$i"}->{'netmask'}  = $$form->find_input("subnet$i", 'text');
            #we do not support dns yet, just in case of future support
            $$interfaces->{"interface$i"}->{'dns0'}     = $$form->find_input("dns0$i", 'text');
            $$interfaces->{"interface$i"}->{'dns1'}     = $$form->find_input("dns1$i", 'text');
            $$interfaces->{"interface$i"}->{'dns2'}     = $$form->find_input("dns2$i", 'text');
            $i++;
        }
    }
    return ( [RC_ERROR,"Cannot find any network interface on $server"]) if ( ! $$interfaces);
    
    return ( [SUCCESS, undef]);
}

##########################################################################
# Set network configuration
##########################################################################
sub set_netcfg
{
    my $exp         = shift;
    my $request     = shift;
    my $interfaces  = shift;
    my $form        = shift;
    my $ua          = @$exp[0];

    my $real_inc_name;
    my ($inc_name, $inc_ip, $inc_host, $inc_gateway, $inc_netmask) = split /,/, $request->{'method'}->{'network'};

    chomp ($inc_name, $inc_ip, $inc_host, $inc_gateway, $inc_netmask);
    if ( $inc_name =~ /^eth(\d)$/)
    {
        $real_inc_name = "interface$1";
    }
    elsif ( $inc_name =~/(\d+)\.(\d+)\.(\d+)\.(\d+)/)
    {
        for my $inc (keys %$interfaces)
        {
            if ($interfaces->{ $inc}->{'ip'}->value() eq $inc_name)
            {
                $real_inc_name = $inc;
                last;
            }
        }
    }
    else
    {
        return( [RC_ERROR, "Incorrect network interface name $inc_name"] );
    }

    return ( [RC_ERROR,"Cannot find interface $inc_name"]) if ( ! exists ($$interfaces{ $real_inc_name}));
    my $inc_type;
    my @set_entries = ();
    if ( $inc_ip eq '0.0.0.0')
    {
        $inc_type = 'Dynamic';
        push @set_entries, 'IP type to dynamic.';
    }
    elsif ( $inc_ip eq '*')
    {
        $inc_type = 'Static';
        ($inc_ip, $inc_host, $inc_gateway, $inc_netmask) = xCAT::NetworkUtils::getNodeNetworkCfg(@$exp[1]);
    }
    else
    {
        $inc_type = 'Static';
    }

#not work on AIX
#    $interfaces->{ $real_inc_name}->{'selected'}->check();
    my @tmp_options = $interfaces->{ $real_inc_name}->{'selected'}->possible_values();
    $interfaces->{ $real_inc_name}->{'selected'}->value(@tmp_options[1] );
    if ( $interfaces->{ $real_inc_name}->{'type'})
    {
        my @type_options = @{$interfaces->{ $real_inc_name}->{'type'}->{'menu'}};
	if (ref( $type_options[0]) eq 'HASH')
        {
            for my $typeopt ( @type_options)
            {
                if ( $typeopt->{'name'} eq $inc_type)
                {
                    $interfaces->{ $real_inc_name}->{'type'}->value($typeopt->{'value'});
                    last;
                }
            }
        }
        else #AIX made the things more complicated, it didn't ship the
             #last HTML::Form. So let's take a guess of the type value
             #Not sure if it can work for all AIX version
        {
            my @types = $interfaces->{ $real_inc_name}->{'type'}->possible_values();
            if ( $inc_type eq 'Dynamic')
            {
                $interfaces->{ $real_inc_name}->{'type'}->value(@types[0]);
            }
            else
            {
                $interfaces->{ $real_inc_name}->{'type'}->value(@types[1]);
            }
        }
#not work on AIX
#        $interfaces->{ $real_inc_name}->{'type'}->value('Static');
    }
    else
    {
        return ( [RC_ERROR,"Cannot change interface type"]);
    }
    if ( $inc_type eq 'Static')
    {
        if ( $inc_ip)
        {
            return ( [RC_ERROR,"Cannot set IP address to $inc_ip"]) if (! $interfaces->{ $real_inc_name}->{'ip'});
            $interfaces->{ $real_inc_name}->{'ip'}->value( $inc_ip);
            push @set_entries, 'IP address';
        }
        if ( $inc_host)
        {
            return ( [RC_ERROR,"Cannot set hostname to $inc_host"]) if (! $interfaces->{ $real_inc_name}->{'hostname'});
            $interfaces->{ $real_inc_name}->{'hostname'}->value( $inc_host);
            push @set_entries, 'hostname';
            if( ! $interfaces->{ $real_inc_name}->{'hostname'}->value())
            {
                $inc_host = $exp->[1];
            }
        }
        if ( $inc_gateway)
        {
            return ( [RC_ERROR,"Cannot set gateway to $inc_gateway"]) if (! $interfaces->{ $real_inc_name}->{'gateway'});
            $interfaces->{ $real_inc_name}->{'gateway'}->value( $inc_gateway);
            push @set_entries, 'gateway';
        }
        if ( $inc_netmask)
        {
            return ( [RC_ERROR,"Cannot set netmask to $inc_netmask"]) if (! $interfaces->{ $real_inc_name}->{'netmask'});
            $interfaces->{ $real_inc_name}->{'netmask'}->value( $inc_netmask);
            push @set_entries, 'netmask';
        }
    }

    #Click "Continue" button
    sleep 2;
    my $data = $form->click('save');
    my $res = $ua->request( $data);
    if (!$res->is_success())
    {
        return ( [RC_ERROR, "Failed to set " . join ',', @set_entries]);
    }

    #Go to the confirm page
    if ( $res->content !~ /<input type=\'submit\'/) #If there is no submit button,get the error message and return
    {
        my @page_lines = split /\n/, $res->content;
        my @lines_to_print;
        for my $page_line (@page_lines)
        {
            chomp $page_line;
            if ( $page_line =~ s/<br>$//)
            {
                push @lines_to_print, $page_line;
            }
        }
        return ( [RC_ERROR,join "\n", @lines_to_print]);
    }

    $ua->timeout( 2 );

    $form = HTML::Form->parse( $res->content, $res->base );
    $data = $form->click('submit');
    $res = $ua->request( $data);
    ##############################################################
    # We cannot get the result of this update, since the network
    # is updated, the old URI is invalid anymore
    # Return success directory
    ##############################################################
    return ( [SUCCESS, "Success to set " . join ',', @set_entries]);
}

##########################################################################
# Format the output of network configuration
##########################################################################
sub format_netcfg
{
    my $interfaces  = shift;
    my $output      = undef;
    for my $inc ( sort keys %$interfaces)
    {
#improve needed: need to make the output consistent to MM            
        $output .= "\n\t" . $inc . ":\n";
        $output =~ s/interface(\d)/eth$1/;
        # There are 2 possible value for $type, 
        # the first means "Dynamic", 2nd means "Static"
        # Now to find the correct type name
	my $curr_type = $interfaces->{$inc}->{'type'}->value();
        my @possible_values = $interfaces->{$inc}->{'type'}->possible_values();
        my $type;
        if ($curr_type == @possible_values[0])
        {
            $type = "Dynamic";
        }
        else
        {
            $type = "Static";
        } 
#not work on AIX
        #my @possible_names  = $interfaces->{$inc}->{'type'}->value_names();
        #my %value_names = {};
        #for ( my $i = 0; $i < scalar( @possible_values); $i++)
        #{
        #    $value_names{ @possible_values[$i]} = @possible_names[$i];
        #}
        #my $type = $interfaces->{$inc}->{'type'} ? $value_names{ $interfaces->{$inc}->{'type'}->value()} : undef;;
        $type = "Static" if ( $type == 2);
        my $ip = $interfaces->{$inc}->{'ip'} ? $interfaces->{$inc}->{'ip'}->value() : undef;
        my $hostname = $interfaces->{$inc}->{'hostname'} ? $interfaces->{$inc}->{'hostname'}->value() : undef;
        my $gateway = $interfaces->{$inc}->{'gateway'} ? $interfaces->{$inc}->{'gateway'}->value() : undef;
        my $netmask = $interfaces->{$inc}->{'netmask'} ? $interfaces->{$inc}->{'netmask'}->value() : undef;

        $output .= "\t\tIP Type: "    . $type     . "\n";
        $output .= "\t\tIP Address: " . $ip       . "\n";
        $output .= "\t\tHostname: "   . $hostname . "\n";
        $output .= "\t\tGateway: "    . $gateway  . "\n";
        $output .= "\t\tNetmask: "    . $netmask  . "\n";
    }
    return( [SUCCESS,$output] );
}

1;

