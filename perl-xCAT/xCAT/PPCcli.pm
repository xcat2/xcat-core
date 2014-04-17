# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCcli;
use strict;
require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(SUCCESS RC_ERROR EXPECT_ERROR NR_ERROR);  
use Expect;
use xCAT::NetworkUtils;

#############################################
# Removes Ctrl characters from term output
#############################################
$ENV{'TERM'} = "vt100";

##############################################
# Constants 
##############################################
use constant {
  SUCCESS      => 0,
  RC_ERROR     => 1,
  EXPECT_ERROR => 2,
  NR_ERROR     => 3,
  DEFAULT_TIMEOUT => 60
};

##############################################
# lssyscfg supported formats 
##############################################
my %lssyscfg = (
  fsp    =>"lssyscfg -r sys -m %s -F %s",
  cec    =>"lssyscfg -r sys -m %s -F %s",
  fsps   =>"lssyscfg -r sys -F %s",
  node   =>"lssyscfg -r lpar -m %s -F %s --filter lpar_ids=%s",
  lpar   =>"lssyscfg -r lpar -m %s -F %s",
  lpar2  =>"lssyscfg -r lpar -m %s --filter %s",
  bpa    =>"lssyscfg -r frame -e %s -F %s",
  frame  =>"lssyscfg -r frame -e %s -F %s",
  bpas   =>"lssyscfg -r frame -F %s",
  prof   =>"lssyscfg -r prof -m %s --filter %s",
  profs  =>"lssyscfg -r prof -m %s -F %s --filter %s",
  cage   =>"lssyscfg -r cage -e %s -F %s"
);

my %chsyscfg = (
  prof   =>"chsyscfg -r prof -m %s -i %s",
  bpa    =>"chsyscfg -r frame -e %s -i %s",
  fsp    =>"chsyscfg -r sys -m %s -i %s",
  frame  =>"chsyscfg -r frame -e %s -i %s",
  cec    =>"chsyscfg -r sys -m %s -i %s",
);

##############################################
# Power control supported formats 
##############################################
my %powercmd = (
  lpar => { 
      on    =>"chsysstate -r %s -m %s -o on -b norm --id %s -f %s",
      of    =>"chsysstate -r %s -m %s -o on --id %s -f %s -b of",
      sms   =>"chsysstate -r %s -m %s -o on --id %s -f %s -b sms",
      reset =>"chsysstate -r %s -m %s -o shutdown --id %s --immed --restart",
      off   =>"chsysstate -r %s -m %s -o shutdown --id %s --immed",
      softoff   =>"chsysstate -r %s -m %s -o shutdown --id %s",
      boot  =>"undetermined" },
  sys  => { 
      reset =>"chsysstate -r %s -m %s -o off --immed --restart",
      on    =>"chsysstate -r %s -m %s -o on",
      onstandby =>"chsysstate -r %s -m %s -o onstandby",
      off   =>"chsysstate -r %s -m %s -o off",
      boot  =>"undetermined" }
);

##############################################
# lsrefcode supported formats
##############################################
my %lsrefcode = (
  fsp => {
      pri =>"lsrefcode -r sys -m %s -s p",
      sec =>"lsrefcode -r sys -m %s -s s",
  },
  cec => {
      pri =>"lsrefcode -r sys -m %s -s p",
      sec =>"lsrefcode -r sys -m %s -s s",
  },  
  lpar   =>"lsrefcode -r lpar -m %s --filter lpar_ids=%s",
);

##############################################
# mksysconn support formats
##############################################
my %mksysconn = (
    fsp   => "mksysconn --ip %s -r sys --passwd %s",
    cec   => "mksysconn --ip %s -r sys --passwd %s",
    bpa   => "mksysconn --ip %s -r frame --passwd %s",
    frame => "mksysconn --ip %s -r frame --passwd %s",
);

##############################################
# rmsysconn support formats
##############################################
my %rmsysconn = (
    fsp   => "rmsysconn -o remove --ip %s",
    cec   => "rmsysconn -o remove --ip %s",
    bpa   => "rmsysconn -o remove --ip %s",
    frame => "rmsysconn -o remove --ip %s",
);

##############################################
# lssysconn support formats
##############################################
my %lssysconn = (
    all  => "lssysconn -r all",
    alls => "lssysconn -r all -F %s"
);

##############################################
# Change IP address for managed systems
# or frames
##############################################
my %chsyspwd = (
    fsp   => "chsyspwd -t %s -m %s --passwd %s --newpasswd %s",
    bpa   => "chsyspwd -t %s -e %s --passwd %s --newpasswd %s",
    cec   => "chsyspwd -t %s -m %s --passwd %s --newpasswd %s",
    frame => "chsyspwd -t %s -e %s --passwd %s --newpasswd %s",
);


##########################################################################
# Logon to remote server
##########################################################################
sub connect {

    my $req        = shift;
    my $hwtype     = shift;
    my $server     = shift;
    my $pwd_prompt = 'assword: $';
    my $continue   = 'continue connecting (yes/no)?';
    my $retry      = $req->{ppcretry};
    my $timeout    = $req->{ppctimeout};
    my $verbose    = $req->{verbose};
    my $ssh;
    my $expect_log = "/dev/null";
    my $errmsg;
	
    if ($req->{command} eq 'rflash') {
	$verbose = 0;
    }

    ##################################################
    # Use timeout from site table (if defined) 
    ##################################################
    if ( !$timeout ) {
        $timeout = DEFAULT_TIMEOUT; 
    }
    ##################################################
    # Shell prompt regexp based on HW Type 
    ##################################################
    my %prompt = (
        hmc => "~>\\s*\$",
        ivm => "\\\$ \$"
    );
    ##################################################
    # Get userid/password  
    ##################################################
    my $cred = $req->{$server}{cred};
    my $parameters = "@$cred[0]\@$server";

    ##################################################
    # Redirect STDERR to variable
    ##################################################
    if ( $verbose ) {
        close STDERR;
        if ( !open( STDERR, '>', $expect_log )) {
             return( "Unable to redirect STDERR: $!" );
        }
    }
    ##################################################
    # Redirect STDOUT to variable
    ##################################################
    if ( $verbose ) {
        close STDOUT;
        if ( !open( STDOUT, '>', $expect_log )) {
             return( "Unable to redirect STDOUT: $!" );
        }
    }
    ######################################################
    # -re $continue
    #  "The authenticity of host can't be established
    #   RSA key fingerprint is ....
    #   Are you sure you want to continue connecting (yes/no)?"
    #
    # -re pwd_prompt
    #   If the keys have already been transferred, we
    #   may already be at the command prompt without
    #   sending the password.
    #
    ######################################################
    while ( $retry-- ) {
        my $success  = 0;
        my $pwd_sent = 0;
        $expect_log  = undef;

        $ssh = new Expect;

        ##################################################
        # raw_pty() disables command echoing and CRLF
        # translation and gives a more pipe-like behaviour.
        # Note that this must be set before spawning
        # the process. Unfortunately, this does not work
        # with AIX (IVM). stty(qw(-echo)) will at least
        # disable command echoing on all platforms but
        # will not suppress CRLF translation.
        ##################################################
        #$ssh->raw_pty(1);
        $ssh->slave->stty(qw(sane -echo));

        ##################################################
        # exp_internal(1) sets exp_internal debugging
        # to STDERR.
        ##################################################
        $ssh->exp_internal( $verbose );

        ##################################################
        # log_stdout(0) disables logging to STDOUT.
        # This corresponds to the Tcl log_user variable.
        ##################################################
        $ssh->log_stdout( $verbose );

        unless ( $ssh->spawn( "ssh", $parameters )) {
            return( $expect_log."Unable to spawn ssh connection to server");
        }
        my @result = $ssh->expect( $timeout,
            [ $continue,
               sub {
                 $ssh->send( "yes\r" );
                 $ssh->clear_accum();
                 $ssh->exp_continue();
               } ],
            [ $pwd_prompt,
               sub {
                 if ( ++$pwd_sent ) {
                   $ssh->send( "@$cred[1]\r" );
                   $ssh->exp_continue();
                 }
               } ],
            [ $prompt{$hwtype},
               sub {
                 $success = 1;
               } ]
        );
        ##########################################
        # Expect error - retry
        ##########################################
        if ( defined( $result[1] )) {
            $errmsg = $expect_log.expect_error(@result);
            sleep(1);
            next;
        }
        ##########################################
        # Successful logon....
        # Return:
        #    Expect
        #    HW Shell Prompt regexp
        #    HW Type (hmc/ivm)
        #    Server hostname
        #    UserId
        #    Password
        #    Redirected STDERR/STDOUT
        #    Connect/Command timeout
        ##########################################
        if ( $success ) {
            return( $ssh,
                    $prompt{$hwtype},
                    $hwtype,
                    $server,
                    @$cred[0],
                    @$cred[1],
                    \$expect_log,
                    $timeout );
        }
        ##########################################
        # Failed logon - kill ssh process
        ##########################################
        $ssh->hard_close();
        return( $expect_log."Invalid userid/password" );
    }
    $ssh->hard_close();
    return( $errmsg );
}


##########################################################################
# Logoff to remote server
##########################################################################
sub disconnect {

    my $exp = shift;
    my $ssh = @$exp[0];

    if ( defined( $ssh )) {
        $ssh->send( "exit\r" );
        $ssh->hard_close();
        @$exp[0] = undef;
    }
}


##########################################################################
# List attributes for resources (lpars, managed system, etc)
##########################################################################
sub lssyscfg {

    my $exp = shift;
    my $res = shift;
    my $d1  = shift;
    my $d2  = shift;
    my $d3  = shift;

    ###################################
    # Select command  
    ###################################
    my $cmd = sprintf( $lssyscfg{$res}, $d1, $d2, $d3 );

    ###################################
    # Send command
    ###################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}


##########################################################################
# Changes a logical partition configuration data
##########################################################################
sub chsyscfg {

    my $exp     = shift;
    my $res     = shift;
    my $d       = shift;
    my $cfgdata = shift;

    #####################################
    # Select command
    #####################################
    my $cmd = sprintf( $chsyscfg{$res}, @$d[2], $cfgdata ); 

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}

##########################################################################
# List reference codes for resources (lpars, managed system, etc)
##########################################################################
sub lsrefcode {

    my $exp = shift;
    my $res = shift;
    my $d1  = shift;
    my $d2  = shift;
    my $cmd = undef;
    my @cmds = undef;
    my $result = undef;
    my @values;

    ###################################
    # Select command  
    ###################################
    if($res =~ /^(fsp|cec)$/) {
        $cmds[0] = sprintf($lsrefcode{$res}{pri}, $d1);
        $cmds[1] = sprintf($lsrefcode{$res}{sec}, $d1);
    } elsif($res eq 'lpar'){
        $cmds[0] = sprintf($lsrefcode{$res}, $d1, $d2);
    }
    else
    {
        return [[0,'Not available']];
    }

    ###################################
    # Send command
    ###################################
    foreach $cmd (@cmds){
        $result = send_cmd( $exp, $cmd );
        push @values, $result;
    }
    return \@values;
}

##########################################################################
# Creates a logical partition on the managed system 
##########################################################################
sub mksyscfg {

    my $exp     = shift;
    my $res     = shift;
    my $d       = shift;
    my $cfgdata = shift;

    #####################################
    # Command only support on LPARs 
    #####################################
    if ( @$d[4] ne "lpar" ) {
        return( [RC_ERROR,"Command not supported on '@$d[4]'"] );
    }
    #####################################
    # Format command based on CEC name
    #####################################
    my $cmd = "mksyscfg -r $res -m @$d[2] -i \"$cfgdata\""; 

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}


##########################################################################
# Removes a logical partition on the managed system
##########################################################################
sub rmsyscfg {

    my $exp     = shift;
    my $d       = shift;

    #####################################
    # Command only supported on LPARs 
    #####################################
    if ( @$d[4] ne "lpar" ) {
        return( [RC_ERROR,"Command not supported on '@$d[4]'"] );
    }
    #####################################
    # Format command based on CEC name
    #####################################
    my $cmd = "rmsyscfg -r lpar -m @$d[2] --id @$d[0]";

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}


##########################################################################
# Lists environmental information 
##########################################################################
sub lshwinfo {

    my $exp    = shift;
    my $res    = shift;
    my $frame  = shift;
    my $filter = shift;

    #####################################
    # Format command based on CEC name
    #####################################
    my $cmd = "lshwinfo -r $res -e $frame -F $filter";

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}


##########################################################################
# Changes the state of a partition or managed system
##########################################################################
sub chsysstate {

    my $exp = shift;
    my $op  = shift;
    my $d   = shift;

    #####################################
    # Format command based on CEC name
    #####################################
    my $cmd = power_cmd( $op, $d );
    if ( !defined( $cmd )) {
        return( [RC_ERROR,"'$op' command not supported"] );
    }
    #####################################
    # Special case - return immediately 
    #####################################
    if ( $cmd =~ /^reboot$/ ) {
        my $ssh = @$exp[0];

        $ssh->send( "$cmd\r" );
        return( [SUCCESS,"Success"] );
    }
    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}



##########################################################################
# Opens a virtual terminal session
##########################################################################
sub mkvterm { 

    my $exp     = shift;
    my $type    = shift;
    my $lparid  = shift;
    my $mtms    = shift;
    my $ssh     = @$exp[0];
    my $hwtype  = @$exp[2];
    my $failed  = 0;
    my $timeout = 3;

    ##########################################
    # Format command based on HW Type
    ##########################################
    my %mkvt = (
        hmc =>"mkvterm --id %s -m %s",
        ivm =>"mkvt -id %s" 
    );
    ##########################################
    # HMC returns:
    #  "A terminal session is already open
    #   for this partition. Only one open
    #   session is allowed for a partition.
    #   Exiting...."
    #
    # HMCs may also return:
    #  "The open failed. 
    #  "-The session may already be open on 
    #  another management console"
    #
    # But Expect (for some reason) sees each
    # character preceeded with \000 (blank??)
    #
    ##########################################
    my $fail_msg  = "HSCL";
    my $ivm_open  = "Virtual terminal is already connected";
    my $hmc_open  = "\000o\000p\000e\000n\000 \000f\000a\000i\000l\000e\000d"; 
    my $hmc_open2 =
        "\000a\000l\000r\000e\000a\000d\000y\000 \000o\000p\000e\000n";

    ##########################################
    # Set command based on HW type
    #   mkvterm -id lparid -m cecmtms 
    ##########################################
    my $cmd = sprintf( $mkvt{$hwtype}, $lparid, $mtms );
    if ( $type ne "lpar" ) {
        return( [RC_ERROR,"Command not supported on '$type'"] );
    }

    ##########################################
    # Close the old sessions
    ##########################################
    if ( $hwtype eq "ivm" ) {
        rmvterm( $exp, $lparid, $mtms );
        sleep 1;
    } else {
        rmvterm_noforce( $exp, $lparid, $mtms );
        sleep 1;
    }

    ##########################################
    # Send command
    ##########################################
    $ssh->clear_accum();
    $ssh->send( "$cmd\r" );

    ##########################################
    # Expect result 
    ##########################################
    my @result = $ssh->expect( $timeout,
        [ "$hmc_open|$hmc_open2|$ivm_open|$fail_msg",
           sub {
               $failed = 1; 
           } ]
    );

    if ( $failed ) {
        $ssh->hard_close();
	if (grep(/$fail_msg/, @result)) {
		return( [RC_ERROR, "mkvterm returns the unsuccessful value, please check your entry and retry the command."] );
	} else {
        	return( [RC_ERROR,"Virtual terminal is already connected"] );
	}
    }

    ##########################################
    # Success...
    # Give control to the user and intercept
    # the Ctrl-X (\030).
    ##########################################
    my $escape = "\030";
    $ssh->send( "\r" );
    $ssh->interact( \*STDIN, $escape );
    
    ##########################################
    # Close session
    ##########################################
    rmvterm( $exp, $lparid, $mtms );
    $ssh->hard_close();

    return( [SUCCESS,"Success"] );
}


##########################################################################
# Force close a virtual terminal session
##########################################################################
sub rmvterm {

    my $exp    = shift;
    my $lparid = shift;
    my $mtms   = shift;
    my $ssh    = @$exp[0];
    my $hwtype = @$exp[2];

    #####################################
    # Format command based on HW Type
    #####################################
    my %rmvt = (
        hmc =>"rmvterm --id %s -m %s",
        ivm =>"rmvt -id %s" 
    );
    #####################################
    # Set command based on HW type
    #   rmvt(erm) -id lparid -m cecmtms 
    #####################################
    my $cmd = sprintf( $rmvt{$hwtype}, $lparid, $mtms );

    #####################################
    # Send command
    #####################################
    $ssh->clear_accum();
    $ssh->send( "$cmd\r" );
}

##########################################################################
# Force close a virtual terminal session
##########################################################################
sub rmvterm_noforce {

    my $exp    = shift;
    my $lparid = shift;
    my $mtms   = shift;
    my $ssh    = @$exp[0];
    my $hwtype = @$exp[2];

    #####################################
    # Format command based on HW Type
    #####################################
    my %rmvt = (
        hmc =>"rmvterm --id %s -m %s",
        ivm =>"rmvt -id %s"
    );
    #####################################
    # Set command based on HW type
    #   rmvt(erm) -id lparid -m cecmtms
    #####################################
    my $cmd = sprintf( $rmvt{$hwtype}, $lparid, $mtms );

    #####################################
    # Send command
    #####################################
    send_cmd( $exp, $cmd );

}


##########################################################################
# Lists the hardware resources of a managed system 
##########################################################################
sub lshwres {

    my $exp      = shift;
    my $d        = shift;
    my $mtms     = shift;
    my $cmd      = "lshwres -r @$d[1] -m $mtms";
    my $level    = @$d[0];
    my $Filter   = @$d[2];
    my $rsubtype = @$d[3];

    #####################################
    # Specify Filters
    #####################################
    if ( $Filter ) {
        $cmd .=" -F $Filter";
    } 
 
    #####################################
    # level may be "sys" or "lpar" 
    #####################################
    if ( defined( $level )) {
        $cmd .=" --level $level";
    }

    #####################################
    # Specify subtype
    #####################################
    if ( $rsubtype ) {
        $cmd .=" --rsubtype $rsubtype"
    }

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd );
    return( $result );
}


##########################################################################
# Retrieve MAC-address from network adapter or network boots an LPAR
##########################################################################
sub lpar_netboot {

    my $exp     = shift;
    my $verbose = shift;
    my $name    = shift;
    my $d       = shift;
    my $opt     = shift;
    my $timeout = my $t = @$exp[7]*10;
    my $cmd     = "lpar_netboot -t ent -f";
    my $gateway = $opt->{G};
    my $node    = @$d[6];

    #####################################
    # Power6 HMCs (V7) do not support 
    # 0.0.0.0 gateway.  
    #####################################
    if ( $gateway =~ /^0.0.0.0$/ ) {
        my $fw = lshmc( $exp, "RM" );
        my $Rc = shift(@$fw);
    
        if ( $Rc == SUCCESS ) {
            if ( @$fw[0] =~ /^V(\d+)/ ) {
                #########################
                # Power4 not supported
                #########################
                if ( $1 < 6 ) {
                    return( [RC_ERROR,"Command not supported on V$1 HMC"] );
                } 
                #########################
                # Use server for gateway 
                #########################
                elsif ( $1 >= 7 ) {
                    $opt->{G} = $opt->{S};
                }
            }
        }
    }
    #####################################
    # Verbose output 
    #####################################
    if ( $verbose ) {
        $cmd.= " -x -v";
    }
    #####################################
    # Force LPAR shutdown if -f specified
    #####################################
    if ( exists( $opt->{f} )) {
        $cmd.= " -i";
    } else {
        #################################
        # Force LPAR shutdown if LPAR is
        # running Linux
        #################################
        my $table = "nodetype";
        my $intable = 0;
        my @TableRowArray = xCAT::DBobjUtils->getDBtable($table);
        if ( @TableRowArray ) {
            foreach ( @TableRowArray ) {
                my @nodelist = split(',', $_->{'node'});
                my @oslist = split(',', $_->{'os'});
                my $osname = "AIX";
                if ( grep(/^$node$/, @nodelist) ) {
                    if ( !grep(/^$osname$/, @oslist) ) {
                        $cmd.= " -i";
                    }
                    $intable = 1;
                    last;
                }
            }
        }
        #################################
        # Force LPAR shutdown if LPAR OS
        # type is not assigned in table 
        # but mnt node is running Linux
        #################################
        if ( xCAT::Utils->isLinux() && $intable == 0 ) {
            $cmd.= " -i";
        }
    }

    #####################################
    # Get MAC-address or network boot
    #####################################
    my $mac = $opt->{m};
    $cmd.= ( defined( $mac )) ? " -m $mac" : " -M -A -n";
   
    #####################################
    # Command only supported on LPARs
    #####################################
    if ( @$d[4] ne "lpar" ) {
        return( [RC_ERROR,"Command not supported on '@$d[4]'"] );
    }
    #####################################
    # Network specified (-D ping test)
    #####################################
    if ( exists( $opt->{S} )) {
        my %nethash   = xCAT::DBobjUtils->getNetwkInfo( [$node] );
        #####################################
        # Network attributes undefined
        #####################################
        if ( !%nethash ) {
            return( [RC_ERROR,"Cannot get network information for $node"] );
        }
        my $netmask = $nethash{$node}{mask};
        $cmd.= (!defined( $mac )) ? " -D" : "";
        $cmd.= " -s auto -d auto -S $opt->{S} -G $opt->{G} -C $opt->{C} -K $netmask";
    }
    #####################################
    # Add lpar name, profile, CEC name 
    #####################################
    $cmd.= " \"$name\" \"@$d[1]\" \"@$d[2]\"";

    #####################################
    # Send command
    #####################################

    my $result = send_cmd( $exp, $cmd, $timeout );
    return( $result );
}


##########################################################################
# List Hardware Management Console configuration information 
##########################################################################
sub lshmc {

    my $exp    = shift;
    my $attr   = shift;
    my $hwtype = @$exp[2];

    #####################################
    # Format command based on HW Type
    #####################################
    my %cmd = (
        hmc =>"lshmc -v",
        ivm =>"lsivm"
    );

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd{$hwtype} );

    #####################################
    # Return error
    #####################################
    if ( @$result[0] != SUCCESS ) {
        return( $result );
    }   
    #####################################
    # Only return attribute requested
    #####################################
    if ( defined( $attr )) {
        if ( my ($vpd) = grep( /^\*$attr\s/, @$result )) { 
            $vpd =~ s/\*$attr\s+//;
            return( [SUCCESS, $vpd ] );
        }
        return( [RC_ERROR, "'$attr' not found"] ); 
    }
    #####################################
    # IVM returns:
    #   9133-55A,10B7D1G,1
    #
    # HMC returns: 
    #   "vpd=*FC ????????
    #   *VC 20.0
    #   *N2 Mon Sep 24 13:54:00 GMT 2007
    #   *FC ????????
    #   *DS Hardware Management Console
    #   *TM 7310-CR4
    #   *SE 1017E6B
    #   *MN IBM
    #   *PN Unknown
    #   *SZ 1058721792
    #   *OS Embedded Operating Systems
    #   *NA 9.114.222.111
    #   *FC ????????
    #   *DS Platform Firmware
    #   *RM V7R3.1.0.1
    #####################################
    if ( $hwtype eq "ivm" ) {
        my ($model,$serial,$lparid) = split /,/, @$result[1];
        return( [SUCCESS,"$model,$serial"] );
    }
    my @values;
    my $vpd = join( ",", @$result );

    #####################################
    # Power4 (and below) HMCs unsupported
    #####################################
    if ( $vpd =~ /\*RM V(\d+)/ ) {
        if ( $1 <= 5 ) {
            return( [RC_ERROR,"Command not supported on V$1 HMC"] );
        }
    }
    #####################################
    # Type-Model may be in the formats:
    #  "eserver xSeries 336 -[7310CR3]-"
    #  "7310-CR4"
    #####################################
    if ( $vpd =~ /\*TM ([^,]+)/ ) {
        my $temp  = $1;
        my $model = ($temp =~ /\[(.*)\]/) ? $1 : $temp; 
        push @values, $model;
    }
    #####################################
    # Serial number
    #####################################
    if ( $vpd =~ /\*SE ([^,]+)/ ) {
        push @values, $1;
    }
    return( [SUCCESS,join( ",",@values)] );

}


##########################################################################
# Updates authorized_keys2 file on the HMC/IVM
##########################################################################
sub mkauthkeys {

    my $exp    = shift;
    my $option = shift;
    my $logon  = shift;
    my $sshkey = shift;
    my $ssh    = @$exp[0];
    my $hwtype = @$exp[2];
    my $userid = @$exp[4];

    #########################################
    # On IVM-based systems, the mkauthkeys 
    # command does not exist, so we have to 
    # include the generated key at 
    # /home/<userid>/.ssh/authorized_keys2 
    # manually.    
    #########################################
    if ( $hwtype =~ /^ivm$/ ) {
        my @authkey; 
        my $auth   = "/home/$userid/.ssh/authorized_keys2";
        my $result = send_cmd( $exp, "cat $auth" );
        my $Rc = shift(@$result);

        #####################################
        # Return error
        #####################################
        if ( $Rc != SUCCESS ) {
            return( $result );
        }
        #####################################
        # When adding, remove old keys first
        #####################################
        foreach ( @$result ) {
            unless ( /$logon$/ ) {
                push @authkey, $_;
            }
        }
        #####################################
        # Add new key 
        #####################################
        if ( $option =~ /^enable$/i ) {
            push @authkey, $sshkey;
        }
        #####################################
        # Rewrite the key file 
        #####################################
        my $keys = join( "\n", @authkey );
        $result = send_cmd( $exp,"echo \"$keys\" | tee $auth" );
        return( $result );
    }
    #########################################
    # When adding, remove old keys first
    #########################################
    my $result = send_cmd( $exp,"mkauthkeys --remove '$logon'" ); 
        
    if ( $option =~ /^enable$/i ) {
        $result = send_cmd( $exp,"mkauthkeys --add '$sshkey'" ); 
    }
    return( $result );
}


##########################################################################
# List Licensed Internal Code levels on HMC for FSP/BPAs
##########################################################################
sub lslic {

    my $exp = shift;
    my $d   = shift;
    my $timeout = shift;
    my $cmd = "lslic ";
    
    ##########################################
    # Use timeout from site table (if defined) 
    ##########################################
    if ( !defined( $timeout ) || $timeout == 0 ) {
        $timeout = @$exp[7] * 3;
    }

    #####################################
    # Command only support on CEC/BPAs
    #####################################
    if ( @$d[4] !~ /^(fsp|bpa)$/ ) {
        return( [RC_ERROR,"Command not supported on '@$d[4]'"] );
    }
    #####################################
    # Format command based on name
    #####################################
    $cmd.= (@$d[4] =~ /^fsp$/) ? "-t sys -m " : "-t power -e ";
    $cmd.= @$d[2];

    #####################################
    # Send command
    #####################################
    my $result = send_cmd( $exp, $cmd , $timeout);
    return( $result );

}


##########################################################################
# Sends command and waits for response 
##########################################################################
sub send_cmd {

    my $exp     = shift;
    my $cmd     = shift;
    my $timeout = shift;
    my $ssh     = @$exp[0];
    my $prompt  = @$exp[1];

    ##########################################
    # Use timeout from site table (if defined) 
    ##########################################
    if ( !defined( $timeout )) {
        $timeout = @$exp[7];
    }

    ##########################################
    # Send command 
    ##########################################
    $ssh->clear_accum();
    $ssh->send( "$cmd; echo Rc=\$\?\r" );
    ##########################################
    # The first element is the number of the
    # pattern or string that matched, the
    # same as its return value in scalar
    # context. The second argument is a
    # string indicating why expect returned.
    # If there were no error, the second
    # argument will be undef. Possible errors
    # are 1:TIMEOUT, 2:EOF, 3:spawn id(...)died,
    # and "4:..." (see Expect (3) manpage for
    # the precise meaning of these messages)
    # The third argument of expects return list
    # is the string matched. The fourth argument
    # is text before the match, and the fifth
    # argument is text after the match.
    ##########################################
    my @result = $ssh->expect( $timeout, "-re", "(.*$prompt)" );
    
    ##########################################
    # Expect error 
    ##########################################
    if ( defined( $result[1] )) {
        return( [EXPECT_ERROR,expect_error( @result )] );
    } 
    ##########################################
    # Extract error code
    ##########################################
    if ( $result[3] =~ s/Rc=([0-9])+\r\n// ) {
        if ( $1 != 0 ) { 
            return( [RC_ERROR,$result[3]] );
        }
    }
    ##########################################
    # No data found - return error
    ##########################################
    if ( $result[3] =~ /No results were found/ ) {
        return( [NR_ERROR,"No results were found"] );
    }
    ##########################################
    # If no command output, return "Success" 
    ##########################################
    if ( length( $result[3] ) == 0 ) {
        $result[3] = "Success";
    }
    ##########################################
    # Success 
    ##########################################
    my @values = ( SUCCESS );
    push @values, split /\r\n/, $result[3];
    return( \@values );
}


##########################################################################
# Return Expect error
##########################################################################
sub expect_error {

    my @error = @_;
    
    ##########################################
    # The first element is the number of the
    # pattern or string that matched, the
    # same as its return value in scalar
    # context. The second argument is a
    # string indicating why expect returned.
    # If there were no error, the second
    # argument will be undef. Possible errors 
    # are 1:TIMEOUT, 2:EOF, 3:spawn id(...)died, 
    # and "4:..." (see Expect (3) manpage for
    # the precise meaning of these messages)
    # The third argument of expects return list
    # is the string matched. The fourth argument
    # is text before the match, and the fifth
    # argument is text after the match.
    ##########################################
    if ( $error[1] eq "1:TIMEOUT" ) {
        return( "Timeout waiting for prompt" );
    }
    if ( $error[1] eq "2:EOF" ) {
        if ( $error[3] ) {
            return( $error[3] );
        }
        return( "ssh connection terminated unexpectedly" );
    }
    return( "Logon failed" );
}



##########################################################################
# Returns built command based on CEC/LPAR action
##########################################################################
sub power_cmd {

    my $op   = shift;  
    my $d    = shift;
    #my $type = (@$d[4] eq "fsp") ? "sys" : @$d[4];
    my $type = ( @$d[4] =~ /^(fsp|cec)$/ ) ? "sys" : @$d[4];

    ##############################
    # Build command 
    ##############################
    my $cmd = $powercmd{$type}{$op};

    if ( defined( $cmd )) {
        return( sprintf( $cmd, $type, @$d[2],@$d[0],@$d[1] ));
    }
    ##############################
    # Command not supported
    ##############################
    return undef;
}

#####################################
# Reset HMC network (hostname & IP)
#####################################
sub network_reset {

    my $exp    = shift;
    my $current_ip   = shift;
    my $hostname_ip  =shift;
    my $hwtype = @$exp[2];

    my ($ip,$hostname) = split /,/, $hostname_ip;
    if ( !$hostname || !$ip)
    {
        return ( [RC_ERROR,"No valid hostname or IP find. This could be a internal bug of xCAT."] );
    }
#####################################
# Format command based on HW Type
#####################################
    my %cmd = (
            hmc =>"lshmc -n -F hostname:ipaddr",
            ivm =>"lsivm" #just for future consideration
            );

#####################################
# Get current hostname and IP
#####################################
    my $result = send_cmd( $exp, $cmd{$hwtype} );
    if ( @$result[0] != SUCCESS ) {
        return( $result );
    }
    my ($current_hostname,$current_all_ip) = split /:/, @$result[1];

#####################################
# Find the correct interface
#####################################
    my @eth_ip = split /,/,$current_all_ip;
    my $i;
    my $matched = 0;
    for( $i=0; $i < scalar(@eth_ip); $i++)
    {
        if ($eth_ip[$i] eq $current_ip)
        {
            $matched = 1;
            last;
        }
    }
    if ( !$matched )
    {
# What's happen?
        return ( [RC_ERROR,"No appropriate IP addresses to be updated. This could be a internal bug of xCAT."]);
    }

    %cmd = (
# probably need update netmask also
            hmc => "chhmc -c network  -s modify -h $hostname -i eth$i -a $ip",
            ivm => "nothing"
           );
    $result = send_cmd( $exp, $cmd{$hwtype} );
#####################################
# Return error
#####################################
    return( $result );

}

##########################################################################
# List connection for CEC/BPA
##########################################################################
sub lssysconn
{
    my $exp    = shift;
    my $res    = shift;
    my $filter = shift;
    my $cmd = sprintf( $lssysconn{$res}, $filter );
    my $result = send_cmd( $exp, $cmd);
    return ( $result);
}

##########################################################################
# Create connection for CEC/BPA
##########################################################################
sub mksysconn
{
    my $exp    = shift;
    my $ip     = shift;
    my $type   = shift;
    my $passwd = shift;
    
    my $cmd = sprintf( $mksysconn{$type}, $ip, $passwd);
    my $result = send_cmd( $exp, $cmd);
    return ( $result);
}

##########################################################################
# Change IP address for managed systems or frames
##########################################################################
sub chsyspwd
{
    my $exp    = shift;
    my $user   = shift;
    my $type   = shift;
    my $mtms   = shift;
    my $passwd = shift;
    my $newpwd = shift;

    my $cmd = sprintf( $chsyspwd{$type}, $user, $mtms, $passwd, $newpwd );
    my $result = send_cmd( $exp, $cmd);
    return ( $result );
}

##########################################################################
# Remove connection for CEC/BPA
##########################################################################
sub rmsysconn
{
    my $exp    = shift;
    my $type   = shift;
    my $name   = shift;
    
    my $cmd = sprintf( $rmsysconn{$type}, $name);
    my $result = send_cmd( $exp, $cmd);
    return ( $result);
}
##########################################################################
# Get FSP/BPA IP address for the redundancy FSP/BPA from HMC
##########################################################################
sub getHMCcontrolIP
{
    my $node = shift;

    if (($node) && ($node =~ /xCAT::/))
    {
        $node = shift;
    }
    my $exp = shift;

    #get node type first
    my $type =  xCAT::DBobjUtils::getnodetype($node, "ppc");
    unless ($type)
    {
        return undef;
    }


    #get node ip from hmc
    my $tab = xCAT::Table->new("vpd");
    my $ent;
    if ($tab) {
       $ent = $tab->getNodeAttribs($node, ['serial', 'mtm']);	
    }
    my $serial = $ent->{'serial'};
    my $mtm  = $ent->{'mtm'};
    #my $mtms = $mtm . '*' . $serial;
    #my $nodes_found = lssyscfg( $exp, "$type", "$mtms");
    my $nodes_found = lssysconn ($exp, "all");
    my @ips;
    my $ip_result;
    if ( @$nodes_found[0] eq SUCCESS ) {
        my $Rc = shift(@$nodes_found);
        #my @newnodes = split(/,/, $nodes_found->[0]);
        #$Rc = shift(@newnodes);
        #for my $entry (@newnodes) {
        #    if(xCAT::NetworkUtils->isIpaddr($entry)) {
        #        push @ips,$entry;
        #    }    
        #    $ip_result = join( ",", @ips );
        #} 
        foreach my $entry ( @$nodes_found ) {
            if ( $entry =~ /$mtm\*$serial/)   {
                $entry =~ /ipaddr=(\d+\.\d+\.\d+\.\d+),/;
                push @ips, $1;
            }
        } 
        $ip_result = join( ",", @ips );        
    }
    return $ip_result;
}



1;

