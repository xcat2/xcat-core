#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#

package xCAT::LparNetbootExp;

#-----------------------------------------------------------------------------

=head1   LparNetbootExp
Usage: Install partition
        lpar_netboot [-v] [-x] [-f] [-w set_boot_order] [-A -D | [-D] | [-D] -m macaddress] -t ent -s speed -d duplex
                -S server -G gateway -C client hostname profile managed_system lparid remote_host

Usage: Return macaddress
        lpar_netboot -M -n [-v] -t ent [-f] [-x] [-D -s speed -d duplex -S server -G gateway -C client] hostname profile managed_system lparid remote_host

        -n      Do not boot partition
        -t      Specifies network type ent
        -D      Perform ping test, use adapter that successfully ping the server
        -s      Network adapter speed
        -d      Network adapter duplex
        -S      Server IP address
        -G      Gateway IP address
        -C      Client IP address
        -m      MAC Address
        -v      Verbose output
        -x      Debug output
        -f      Force close virtual terminal session
        -w      Set boot device order
                        0: Don't set boot device order
                        1: Set network as boot device
                        2: Set network as 1st boot device, disk as 2nd boot device
                        3: Set disk as 1st boot device, network as 2nd boot device
                        4: set disk as boot device
        -M      Discovery ethernet adapter mac address and location code
        --help  Prints this help


=cut

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
    $::XCATDIR  = $ENV{'XCATDIR'}  ? $ENV{'XCATDIR'}  : '/etc/xcat';
}


use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use Getopt::Long;
use xCAT::MsgUtils;
use Expect;
use strict;
use Data::Dumper;
my $adapter_found = 0;
my @adap_type;
my @full_path_name_array;
my @phandle_array;
my $macaddress;
my $phys_loc;
my $client_ip;
my $gateway_ip;
my $device_type;
my $server_ip;

# List supported network adapters here.  dev_pat is an array of regexp patterns
# the script searches for in the device tree listing.  dev_type is the type
# of device displayed in the output.
my @dev_pat = (
        "ethernet",
        "token-ring",
        "fddi"
        );
my @dev_type = (
        "ent",
        "tok",
        "fddi"
        );
my $dev_count = scalar(@dev_type); #number of supported device type


#-------------------------------------------------------------------------------

=head3    nc_msg

    PROCEDURE

    Declare procedure to write status/error messages
    We do it this way so that if /var is full (or some other error occurs)
    we can trap it in a common section of code.

=cut

#-----------------------------------------------------------------------------

sub nc_msg
{
    my $verbose = shift;
    my $msg = shift;
    my $rsp;

    if ( $verbose eq 1 ) {
        $rsp->{data}->[0] = $msg;
        xCAT::MsgUtils->message("I", $rsp ,$::CALLBACK);
    }

    if ( $verbose eq 2 ) {
        $rsp->{data}->[0] = $msg;
        xCAT::MsgUtils->message("E", $rsp ,$::CALLBACK);
    }
}
#-------------------------------------------------------------------------------

=head3    run_lssyscfg

      Procedure to run the rpower command
      test its return code and capture its output

=cut

#-----------------------------------------------------------------------------

sub run_lssyscfg
{
    my $req = shift;
    if (($req) && ($req =~ /xCAT::/))
    {
        $req = shift;
    }
    my $verbose = shift;
    my $node = shift;
    my $cmd;
    my $out;

    $out = xCAT::Utils->runxcmd(
        {
            command => ['rpower'],
            node    => [$node],
            arg     => ['state']
        },
    $req, 0, 1);
    if ($::RUNCMD_RC != 0)   {
        nc_msg($verbose, "Unable to run rpower $node state.\n");
        return undef;
    }
    my $output = join ',', @$out;
    nc_msg($verbose, "Status: run_lssyscg : partition status : $output\n");

    nc_msg($verbose, "####msg:$output#########\n" );


    ###################################################################
    # Slow down the requests speed to hcp, so that hcp will not busy on
    # query.  Instead, hcp should put more time on other activities.
    # Another reason to set this sleep is giving some time to the lpars
    # to be more stable.
    ###################################################################
    sleep 4;

    return $output;
}

#-------------------------------------------------------------------------------

=head3    usage


    PROCEDURE

    Declare procedure to write usage message and exit


=cut

#-----------------------------------------------------------------------------

sub usage {

    my $msg = "Usage: Install partition \
            \n\t \[-v\] \[-x\] \[-f\] \[-w set_boot_order\] \[-A -D | \[-D\] | \[-D\] -m macaddress\] -t ent -s speed -d duplex \
            \n\t\t-S server -G gateway -C client hostname profile managed_system lparid remote_host\
            \n \
            \nUsage: Return macaddress \
            \n\t -M -n \[-v\] -t ent \[-f] \[-x] \[-D -s speed -d duplex -S server -G gateway -C client\] hostname profile managed_system lparid remote_host\
            \n \
            \n\t-n\tDo not boot partition \
            \n\t-t\tSpecifies network type ent \
            \n\t-D\tPerform ping test, use adapter that successfully ping the server \
            \n\t-s\tNetwork adapter speed \
            \n\t-d\tNetwork adapter duplex \
            \n\t-S\tServer IP address \
            \n\t-G\tGateway IP address \
            \n\t-C\tClient IP address \
            \n\t-m\tMAC Address \
            \n\t-v\tVerbose output \
            \n\t-x\tDebug output \
            \n\t-f\tForce close virtual terminal session \
            \n\t-w\tSet boot device order \
            \n\t\t\t0: Don't set boot device order \
            \n\t\t\t1: Set network as boot device \
            \n\t\t\t2: Set network as 1st boot device, disk as 2nd boot device \
            \n\t\t\t3: Set disk as 1st boot device, network as 2nd boot device \
            \n\t\t\t4: set disk as boot device \
            \n\t-M\tDiscovery ethernet adapter mac address and location code \
            \n\t--help\tPrints this help\n";
    nc_msg(1, $msg);

    return 0;
}
#-------------------------------------------------------------------------------

=head3    ck_args

 PROCEDURE

 Check command line arguments


=cut

#-----------------------------------------------------------------------------
sub ck_args {

    my $opt = shift;
    if (($opt) && ($opt =~ /xCAT::/))
    {
        $opt = shift;
    }
    my $verbose = shift;
    my $node = $opt->{node};
    my $mtms = $opt->{fsp};
    my $hcp = $opt->{hcp};
    my $lparid = $opt->{id};
    my $profile = $opt->{pprofile};

    if (exists( $opt->{D}) and (!exists ($opt->{s}) or !exists ($opt->{d} ))) {
        nc_msg($verbose, "Speed and duplex required\n");
        usage;
        return 1;
    }

    if (exists ($opt->{D}) and !exists ($opt->{C}))  {
        nc_msg($verbose, "Client IP is required\n");
        usage;
        return 1;
    }
    if (exists( $opt->{D}) and !exists($opt->{S})) {
        nc_msg($verbose, "Server IP is required\n");
        usage;
        return 1;
    }

    if (exists( $opt->{D}) and !exists($opt->{G})) {
        nc_msg($verbose, "Gateway IP is required\n");
        usage;
        return 1;
    }

    unless($node) {
        nc_msg($verbose, "Node is required\n");
        usage;
        return 1;
    } else {
        nc_msg($verbose, "Node is $node\n");
    }

    unless($mtms) {
        nc_msg($verbose, "Managed system is required\n");
        usage;
        return 1;
    } else {
        nc_msg($verbose, "Managed system is $mtms.\n");
    }

    unless ($hcp) {
        nc_msg($verbose, "Hardware control point address is required\n");
        usage;
        return 1;
    } else {
        nc_msg($verbose, "Hardware control point address is $hcp.\n");
    }

    unless ($lparid) {
        nc_msg($verbose, "Lpar Id is required.\n");
        usage;
        return 1;
    } else {
        nc_msg($verbose, "LPAR Id is $lparid.\n");
    }

    unless ($profile) {
        nc_msg($verbose, "Profile is required.\n");
        usage;
        return 1;
    } else {
        nc_msg($verbose, "profile $profile.\n");
    }

    if ($opt->{M} and $opt->{g}) {
        nc_msg($verbose, "Can not specify -M and -g flags together.\n");
        usage;
        return 1;
    }
    if ($opt->{M} and ($opt->{m} or $opt->{l})) {
        nc_msg($verbose, "Can not specify -M and -l or -m flags together.\n");
        usage;
        return 1;
    }

    if ($opt->{m} and $opt->{l}) {
        nc_msg($verbose, "Can not specify -l and -m flags together.\n");
        usage;
        return 1;
    }

    if ($opt->{A} and ($opt->{m} or $opt->{l})) {
        nc_msg($verbose, "Can not specify -A and -m or -l flags together.\n");
        usage;
        return 1;
    }

    if ($opt->{A} and !exists($opt->{D}) and !exists($opt->{n})) {
        nc_msg($verbose, "Flag -A must be specify with flag -D for booting.\n");
        usage;
        return 1;
    }

    if ($opt->{M} and $opt->{D} and (!exists($opt->{S}) or !exists($opt->{G}) or !exists($opt->{C}) or !exists( $opt->{s}) or !exists($opt->{d}))) {
        nc_msg($verbose, "Flag -M with -D require arguments for -C, -S, -G, -s and -d.\n");
        usage;
        return 1;
    }

    if ($opt->{M} and !exists($opt->{D}) and (!exists($opt->{S}) or !exists($opt->{G}) or !exists($opt->{C}) or !exists($opt->{s}) or !exists($opt->{d}))){
        nc_msg($verbose, "Flag -M with arguments for -C, -S, -G, -s and -d require -D flag.\n");
        usage;
        return 1;
    }

    if ($opt->{M} and !exists($opt->{n})) {
        nc_msg($verbose, "-M flag requires -n.\n");
        usage;
        return 1;
    }

    if ($node =~ /(\[ ]+)-/) {
        nc_msg($verbose, "Error : $node, node is required\n");
        return 1;
    }

    if ($mtms =~ /(\[ ]+)-/) {
        nc_msg($verbose, "Error : $mtms, Managed system is required\n");
        return 1;
    }

    #if ($profile =~ /(\[ ]+)-/) {
    #    nc_msg($verbose, "Error : $profile, profile is required\n");
    #    return 1;
    #}
    return 0;
}




#-------------------------------------------------------------------------------

=head3    send_command


        PROCEDURE

        Declare procedure to send commands slowly. This is needed because
        some bytes are missed by the service processor when sent at top speed.
        The sleep was needed because a command was sent sometimes before the
        results of the previous command had been received.

        The Open Firmware is constrained on how quickly it can process input streams.
        The following code causes expect to send 10 characters and then wait 1 second
        before sending another 10 bytes.


=cut

#-----------------------------------------------------------------------------

sub send_command  {
    my $verbose = shift;
    my $rconsole = shift;
    my $cmd = shift;
    nc_msg($verbose, "sending commands $cmd to expect \n");
    my $msg;

    $msg = $rconsole->send($cmd);
    sleep 1;
    return $msg;

}


#-------------------------------------------------------------------------------

=head3    get_phandle

 PROCEDURE

 Declare procedure to parse the full device tree that is displayed as a result
 of an ls command. The information needed is the phandle and full device name
 of a supported network card found in the device tree. The phandle is used in
 other procedures to get and change properties of the network card. The full
 device name is used to network boot from the network adapter.

=cut

#-----------------------------------------------------------------------------

sub get_phandle {
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    my $timeout = 30;
    my $done = 0;
    my @result;
    my $expect_out;
    my $retry_count;
    my %path;
    my $rc = 0;


    # This is the first procedure entered after getting to the ok prompt. On entry
    # the current device is not root. The command 'dev /' is sent to get to the
    # root of the device tree. There is no output from the dev command. The expected
    # output is the ok prompt ('>').
    #
    # The pwd command can be used to determine what the current device is.
    #

    send_command($verbose, $rconsole,  "dev /\r");

    @result = $rconsole->expect(
        $timeout,
        [qr/ok/=>
        sub {
            nc_msg($verbose, "Status: at root\n");
            $rconsole->clear_accum();
            }
        ],
        [qr/]/=>
        sub {
            nc_msg($verbose, "Unexpected prompt\n");
            $rconsole->clear_accum();
            $rc = 1;
            }
        ],
        [timeout =>
        sub {
            $rconsole->send("\r");
            $rconsole->clear_accum();
            $rc = 1;
            }
        ],
        [eof =>
        sub {
            nc_msg($verbose, "Cannot connect to $node");
            $rconsole->clear_accum();
            $rc = 1;
            }
        ],
    );
    return 1 if ($rc eq 1);
    # Next, the 'ls' command is sent. The result is a display of the entire
    # device tree. The code then looks at the
    # output from the ls command one line at a time, trying to match it with the
    # regexp pattern in dev_pat, an array that contains all the supported network
    # adapters. When found, the adapter type, the phandle and path name are saved
    # in array variables.
    #
    # The complicated part is that the full path name may be spread over more than
    # one line. Each line contains information about a node. If the supported
    # network adapter is found on an nth level node, the full path name is the
    # concatenation of the node information from the 0th level to the nth level.
    # Hence, the path name from each level of the device tree needs to be saved.
    #
    # The pattern "\n(\[^\r]*)\r" is worth a second look. It took
    # many hours of debug and reading the expect book to get it right. When more
    # than one line of data is returned to expect at once, it is tricky getting
    # exactly one line of data to look at. This pattern works because it looks
    # for a newline(\n), any character other than a carriage return(\[^\r]*), and
    # then for a carriage return. This causes expect to match a single line.
    # If (.*) is used instead of (\[^\r]*), multiple lines are matched. (that was
    # attempt number 1)
    #
    # Once a single line is found, it tries to determine what level in the device
    # tree this line is.
    # searching through subsequent lines and subsequent levels until an
    # adapter is found.
    # The level of the current line, which
    # is calculated based on the assumption of "Level = (Leading Spaces - 1)/2".
    # Leading Spaces is the number of spaces between the first colon ':' and the
    # first non-space character of each line.
    #
    # Using the -d flag helped a lot in finding the correct pattern.
    #

    send_command($verbose, $rconsole,  "ls \r");

    $timeout = 60;
    $done = 0;
    while (!$done) {
        # this expect call isolates single lines
        # This code uses the tcl regexp to parse the single line
        # isolated by expect.
        #
        # When the ok prompt ('>') is matched, this indicates the end of
        # the ls output, at which point the done variable is set, to break
        # out of the loop.
        #
        # All other lines are ignored.
        #
        @result = ();
        @result = $rconsole->expect(
            $timeout,
            [qr/(\n)([^\r]*)(\r)/=>
            sub {
                nc_msg($verbose, "Parsing network adapters... \n");
                #$rconsole->clear_accum();
                }
            ],
            [qr/>/=>
            sub {
                nc_msg($verbose, "finished \n");
                $rconsole->clear_accum();
                $done = 1;
                }
            ],
            [timeout=>
            sub {
                nc_msg($verbose, "Timeout isolating single line of ls output\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [eof =>
            sub {
                nc_msg($verbose, "Cannot connect to $node");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
        );
        return 1 if ($rc eq 1);
        if ($result[2] =~ /(\w*)\:(\s*)\/(\S*)/) {

            my $x1 = $1;
            my $x2 = $2; #number of space
            my $x3 = $3; #device
            # Each level is inspected for a match
            my $level = (length($x2)-1)/2;
            $path{$level} = $x3;
            my $j = 0;

            for ($j = 0; $j < $dev_count; $j++) {
                if ($x3 =~ /$dev_pat[$j]/) {
                    if ( $x3 =~ /hfi-ethernet/ and $dev_pat[$j] eq "ethernet" ){
                        next;
                    }
                    my $i = 0;
                    for ($i = 0; $i <= $level; $i++)
                    {
                        $full_path_name_array[$adapter_found] .= "/" . $path{$i};
                    }
                    $phandle_array[$adapter_found] = $x1;
                    $adap_type[$adapter_found] = $dev_type[$j];
                    $adapter_found ++;
                    last;
                }
            }
        }
    }
    # Did we find one or more adapters?
    if ( $adapter_found > 0 ) {
        return 0;
    } else {
        nc_msg($verbose, "No network adapters found\n" );
        return 1;
    }

}
#-------------------------------------------------------------------------------

=head3    get_adap_prop

 PROCEDURE

 Declare procedure to obtain the list of valid adapter connector properties
 from the adapter card.  Connector types can be rj45, sc, 9pin, aui,
 bnc, or mic.  Speeds can be 10, 100, or 1000.  Duplex can be half or
 full.  This procedure will use the "supported-network-types"
 argument to the get-package-property command to get the list of
 properties for the given adapter.

=cut

#-----------------------------------------------------------------------------
sub  get_adap_prop    {
    my $phandle = shift;
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    my $timeout = 120;
    my $rc = 0;
    my $state = 0;
    my @cmd;
    my @done;
    my @msg;
    my @pattern;
    my @newstate;
    my @result;
    my @adap_prop_array;
    my $nw_type;
    my $nw_speed;
    my $nw_conn;
    my $nw_duplex;

    nc_msg($verbose, " Status: get_adap_prop start\n");

    # state 0, stack count 0
    $done[0] = 0;
    $cmd[0] = "\" supported-network-types\" " . $phandle . " get-package-property\r";
    $msg[0] = "Status: rc and all supported network types now on stack\n";
    #$pattern[0] = "(.*)3 >(.*)";
    $pattern[0] = "3 >";
    $newstate[0] = 1;

    # state 1, return code and string on stack
    $done[1] = 0;
    $cmd[1] = ".\r";
    $msg[1] = "Status: All supported network types now on stack\n";
    #$pattern[1] = "(.*)2 >(.*)";
    $pattern[1] = "2 >";
    $newstate[1] = 2;

    # state 2, data ready to decode
    $done[2] = 0;
    $cmd[2] = "decode-string\r";
    $msg[2] = "Status: supported network type isolated on stack\n";
    #$pattern[2] = "(.*)ok(.*)4 >(.*)";
    $pattern[2] = "4 >";
    $newstate[2] = 3;

    # state 3, decoded string on stack
    $done[3]= 0;
    $cmd[3] = "dump\r";
    $msg[3] = "Status: supported network type off stack\n";
    #$pattern[3] = ".*:.*:(.*):.*:.*:(.*):.*(2 >)(.*)";
    $pattern[3] = "ok";
    $newstate[3] = 4;

    # state 4, need to check for more data to decode
    $done[4] = 0;
    $cmd[4] = ".s\r";
    $msg[4] = "Status: checking for more supported network types\n";
    #$pattern[4] = ".s (\[0-9a-f]* )(.*)>";
    $pattern[4] = "ok";
    $newstate[4]= 5;

    # state 5, done decoding string, clear stack
    $done[5] = 0;
    $cmd[5]  = ".\r";
    $msg[5]  = "Status: one entry on stack cleared\n";
    #$pattern[5] = "(.*)ok(.*)1 >(.*)";
    $pattern[5] = "ok";
    $newstate[5] = 6;

    # state 6, finish clearing stack, choose correct adapter type
    $done[6]= 0;
    $cmd[6] = ".\r";
    $msg[6] = "Status: finished clearing stack\n";
    #$pattern[6] = "(.*)ok(.*)0 >(.*)";
    $pattern[6] = "ok";
    $newstate[6]= 7;

    # state 7, done
    $done[7] = 1;

    while($done[$state] eq 0) {
        nc_msg($verbose, "Status: command is $cmd[$state]\n");
        send_command($verbose, $rconsole, $cmd[$state]);
        @result = ();
        @result = $rconsole->expect(
        $timeout,
        [ qr/$pattern[$state]/i,
            sub {
                nc_msg($verbose, $msg[$state]);
                $state = $newstate[$state];
                $rconsole->clear_accum();
            }
        ],
        [ qr/]/,
            sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
        [ qr/(.*)DEFAULT(.*)/,
            sub {
                nc_msg($verbose, " Default catch error\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
        [ timeout=>
            sub {
                nc_msg($verbose, "Timeout in getting adapter properpties\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
        [ eof =>
            sub {
                nc_msg($verbose, "Cannot connect to $node\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ]
        );
        return 1 if ($rc eq 1);
        # After state 3, the network type is parsed and the connector
        # type extracted.  If the type hasn't been found, add it to
        # the list of supported connector types.
        if ( $state eq 4 ) {
            #  Build the adapter properties from the string
            #regexp .*,(.*),(.*),(.*) $nw_type dummy nw_speed nw_conn nw_duplex
            #set adap_prop "$nw_speed,$nw_conn,$nw_duplex"
            #nc_msg "Status: Adapter properties are $adap_prop\n"

            # if it's not in the list, add it, otherwise continue
            if ( $result[3] =~ /(\w*):(.*):(\w*)\,(\w*)\,(\w*):/) {
                $nw_type = $3;
                $nw_speed = $4;
                $nw_conn = $5;
                nc_msg($verbose, "nwtype is $3, nwspeed is $4, nwconn is $5\n");
            }
            if ( $result[3] =~ /(\w*):(.*):(\w*)\,(\w*):/) {
                $nw_duplex = $4;
                nc_msg($verbose, "nwduplex is $4\n");
            }
        }

        #push @adap_prop_array, $nw_type.",".$nw_speed.",".$nw_conn.",".$nw_duplex;
        push @adap_prop_array, $nw_speed.",".$nw_conn.",".$nw_duplex;
        nc_msg($verbose, "Status: Adding adapter properties to list\n");

        # After state 4, a test is done to see if all of the supported
        # network types have been decoded. If they have been, the
        # state variable is left alone. if not, the state variable is
        # set to 2, causing a loop back to the step where the
        # decode-string command is sent.
        if ( $state eq 5 ) {
            if ($result[3] =~/2 > \.s \w+ (\w*)/) {
                $state = 2 if ($1 != 0);
            }
        }
    }
    if (scalar(@adap_prop_array) != 0) {
        return \@adap_prop_array;
    } else {
        return 0;
    }
}

#-------------------------------------------------------------------------------

=head3    get_mac_addr


  PROCEDURE

  Declare procedure to obtain the ethernet or mac address property from the
  ethernet card.

  3 commands lines containing a total of 6 commands are used.

  The get-package-property command is an example of a command
  that takes it's arguments off the stack and puts the results back onto the
  stack. Because of this, the arguments for the get-package-property command
  are in front of the command verb.


  The only reason this procedure is implemented in a loop is to avoid coding
  3 expect commands.

=cut

#-----------------------------------------------------------------------------
sub get_mac_addr {
    my $phandle = shift;
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    my $timeout = 60;
    my $state = 0;
    my @result;
    my $mac_rc;
    my @cmd;
    my @done;
    my @msg;
    my @pattern;
    my @newstate;
    my $mac_address;
    my $rc = 0;


    nc_msg($verbose, "Status: get_mac_addr start\n");

    # cmd(0) could have been sent as 3 commands. " mac-address" (tcl forces
    # the use of \") is the first command on this line. The result of entering
    # " mac-address" is that 2 stack entries are created, and address and a length.
    #
    # The next command in cmd(0) is the phandle with no quotes. This results in
    # one stack entry because the phandle is an address.
    #
    # the third command in cmd(0) is get-package-property. After this command, there
    # are 3 stack entries (return code, address and length of mac-address).
    # state 0, stack count 0, send command
    $done[0] = 0;
    $cmd[0] = "\" local-mac-address\" ". $phandle . " get-package-property\r";
    $msg[0] = "Status: return code and mac-address now on stack\n";
    $pattern[0] = "local-mac-address.*ok";#"\s*3 >";
    $newstate[0] = 1;

    # cmd(1) is a dot (.). This is a stack manipulation command that removes one
    # thing from the stack. pattern(1) is looking for a prompt with the 2 indicating
    # that there are 2 things left on the stack.
    # state 1, return code and mac-address on stack
    $done[1]= 0;
    $cmd[1] = ".\r";
    $msg[1] = "Status: mac-address now on stack\n";
    #$pattern[1] = "(.*)2 >(.*)";
    $pattern[1] = "ok"; #"2 >";
    $newstate[1]= 2;

    # cmd(2) is the dump command. This takes an address and a length off the stack
    # and displays the contents of that storage in ascii and hex. The long pattern
    # puts the hex into the variable expect_out(3,string). The tcl verb 'join' is
    # used to eliminate the spaces put in by the dump command.
    # state 2, mac-address on stack
    $done[2] = 0;
    $cmd[2] = ": dump-mac ( prop-addr prop-len -- ) \
                cr  \
                dup decode-bytes  2swap 2drop   ( data-addr data-len ) \
                ( data-len ) 0 ?do \
                    dup c@ 2 u.r                  ( data-addr ) \
                    char+                        ( data-addr' ) \
                loop \
                drop \
                cr \
                ; \r";
    $msg[2] = "Status: set command\n";
    $pattern[2] = "ok";
    $newstate[2]= 3;

    $done[3]= 0;
    $cmd[3] = "dump-mac\r";
    $msg[3] = "Status: mac-address displayed, stack empty\n";
    $pattern[3] = "dump-mac(\\s*)(\\w*)(\\s*)ok";
    $newstate[3] = 4 ;


    # state 4, all done
    $done[4] = 1;

    while($done[$state] eq 0) {
        @result = ();
        send_command($verbose, $rconsole, $cmd[$state]);
        @result = $rconsole->expect(
            $timeout,
            [qr/$pattern[$state]/=>
            sub {
                nc_msg($verbose, $msg[$state]);
                $state = $newstate[$state];
                $rconsole->clear_accum();
                }
            ],
            [qr/1 > /=>
            sub {
                $rconsole->clear_accum();
                if( $state eq 0 ) {
                    # An error occurred while obtaining the mac address.  Log the error,
                    # but don't quit nodecond.  instead, return NA for the address
                    #
                    send_command($verbose, $rconsole, ".\r");
                    $rconsole->expect(
                        $timeout,
                        #[ qr/(-*\[0-9\]*)  ok(.*)0 >(.*)/i,
                        [ qr/0 >/i,
                            sub {
                                #$mac_rc = $expect_out;
                                nc_msg($verbose, "Status: Error getting MAC address for phandle=$phandle. RC=$mac_rc.\n");
                                nc_msg($verbose, "Could not obtain MAC address; setting MAX to NA\n" );
                                $rconsole->clear_accum();
                                $rc = 1;
                            }
                        ],
                        [ timeout=>
                            sub {
                                nc_msg($verbose, "Timeout when getting mac address\n");
                                $rconsole->clear_accum();
                                $rc = 1;
                            }
                        ],
                        [ eof =>
                            sub {
                                nc_msg($verbose, " Cannot connect to $node\n");
                                $rconsole->clear_accum();
                                $rc = 1;
                            }
                        ]
                    );
                }
            }
            ],
            [qr/]/=>
            sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [qr/(.*)DEFAULT(.*)/=>
            sub {
                nc_msg($verbose, "Default catch error\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [timeout=>
            sub {
                nc_msg($verbose, "Timeout in getting mac address\n");
                nc_msg($verbose, "timeout state is $state\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [eof =>
            sub {
                nc_msg($verbose, "Cannot connect to $node");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
        );
        return undef if ($rc eq 1);
    }
    # if the state is 0, 1, or 2, an error occurred and the join will fail
    if ($state eq 4) {
        if ($result[2] =~ /dump-mac\s*(\w*)\s*ok/) {
            $mac_address = $1;
        }
        return $mac_address;
    } else {
        return undef;
    }

}


#-------------------------------------------------------------------------------

=head3    get_adaptr_loc


  PROCEDURE

  Declare procedure to obtain the list of ethernet adapters, their physical
  location codes and MAC addresses.

  The get-package-property command is an example of a command
  that takes it's arguments off the stack and puts the results back onto the
  stack. Because of this, the arguments for the get-package-property command
  are in front of the command verb.

  The only reason this procedure is implemented in a loop is to avoid coding
  3 expect commands.

=cut

#-----------------------------------------------------------------------------
 sub get_adaptr_loc {
    my $phandle = shift;
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    my @cmd;
    my @done;
    my @msg;
    my @pattern;
    my @newstate;
    my $state = 0;
    my $timeout = 60; # shouldn't take long
    my @result;
    my @path;
    my $loc_code;
    my $rc = 0;

    nc_msg($verbose, "Status: get_adaptr_loc start\n");
    # cmd(0) could have been sent as 3 commands. " ibm,loc-code" (tcl forces
    # the use of \") is the first command on this line. The result of entering
    # " ibm,loc-code" is that 2 stack entries are created, and address and a length.
    #
    # The next command in cmd(0) is the phandle with no quotes. This results in
    # one stack entry because the phandle is an address.
    #
    # the third command in cmd(0) is get-package-property. After this command, there
    # are 3 stack entries (return code, address and length of mac-address).
    # state 0, stack count 0, send command
    $done[0] = 0;
    $cmd[0] = "\" ibm,loc-code\" $phandle get-package-property\r";
    $msg[0] = "Status:  return code and loc-code now on stack\n";
    #$pattern[0] = "(.*)3 >(.*)";
    $pattern[0] = "3 >";
    $newstate[0] = 1;

    # cmd(1) is a dot (.). This is a stack manipulation command that removes one
    # thing from the stack. pattern(1) is looking for a prompt with the 2 indicating
    # that there are 2 things left on the stack.
    # state 1, return code and loc-code on stack
    $done[1]= 0;
    $cmd[1] = ".\r";
    $msg[1] = "Status: loc-code now on stack\n";
    #$pattern[1] = "(.*)2 >(.*)";
    $pattern[1] = "ok"; #"2 >";
    $newstate[1]= 2;

    # state 2, loc-code on stack
    $done[2]= 0;
    $cmd[2] = "dump\r";
    $msg[2] = "Status: loc-code displayed, stack empty\n";
    #$pattern[2] = "(.*)(: )(.*)( :)(.*)(\.: ok)";
     $pattern[2] = "ok";
    $newstate[2]= 3;

    # state 3, all done
    $done[3] = 1;

    while($done[$state] eq 0) {
        @result = ();
        nc_msg($verbose, "PROGRAM Status: command is $cmd[$state]\n");
        send_command($verbose, $rconsole, $cmd[$state]);
        @result = $rconsole->expect(
            $timeout,
            [qr/$pattern[$state]/=>
            sub {
                nc_msg($verbose, $msg[$state]);
                $rconsole->clear_accum();
                $state = $newstate[$state];
            }
            ],
            [qr/1 >/=>
            sub {
                $rconsole->clear_accum();
                my $exp = shift;
                if($state eq 0) {
                    send_command($verbose, $rconsole, ".\r");
                    $exp->expect(
                        #[qr/(-*\[0-9\]*)  ok(.*)0 >(.*)/=>
                        [qr/0 >/=>
                        sub {
                            $rconsole->clear_accum();
                            my $loc_rc = shift;
                            nc_msg($verbose, "Error getting adapter physical location.\n");
                            nc_msg($verbose, "Status: Error getting physical location for phandle=$phandle. RC=$loc_rc.\n");
                            $rc = 1;
                            }
                        ],
                        [timeout=>
                        sub {
                            $rconsole->clear_accum();
                            nc_msg($verbose, "Timeout when openning console\n");
                            $rc = 1;
                            }
                        ],
                        [eof=>
                        sub {
                            $rconsole->clear_accum();
                            nc_msg($verbose, "Cannot connect to the $node\n");
                            $rc = 1;
                            }
                        ],
                    );

                }
            }
            ],
            [qr/]/=>
            sub {
                $rconsole->clear_accum();
                nc_msg($verbose, "Unexpected prompt\n");
                $rc = 1;
                }
            ],
            [qr/(.*)DEFAULT(.*)/=>
            sub {
                $rconsole->clear_accum();
                nc_msg($verbose, "Default catch error\n");
                $rc = 1;
                }
            ],
            [timeout=>
            sub {
                $rconsole->clear_accum();
                nc_msg($verbose, "Timeout when openning console\n");
                $rc = 1;
                }
            ],
            [eof =>
            sub {
                $rconsole->clear_accum();
                nc_msg($verbose, "Cannot connect to the $node\n");
                $rc = 1;
                }
            ],
        );
        return undef if ($rc eq 1);
    }
    # Did we find one or more adapters?

    if ($result[3] =~ /(\w*):(.*):(\w*\.\w*\.\w*):/) {
        $loc_code = $3;
    }else {
        return undef;
    }
}

#-------------------------------------------------------------------------------

=head3    ping_server



 PROCEDURE

 Declare procedure to obtain the list of valid adapter connector properties
 from the adapter card.  Connector types can be rj45, sc, 9pin, aui,
 bnc, or mic.  Speeds can be 10, 100, or 1000.  Duplex can be half or
 full.  This procedure will use the "supported-network-types"
 argument to the get-package-property command to get the list of
 properties for the given adapter.


=cut

#-----------------------------------------------------------------------------
sub  ping_server{
    my $phandle = shift;
    my $full_path_name = shift;
    my $rconsole = shift;
    my $node = shift;
    my $mac_address = shift;
    my $verbose = shift;
    my $adap_speed = shift;
    my $adap_duplex = shift;
    my $list_type = shift;
    my $server_ip = shift;
    my $client_ip = shift;
    my $gateway_ip = shift;
    my $adap_prop_list_array;
    #my %env = shift;
    my $command;
    my $linklocal_ip;
    my @result;
    my @done;
    my @cmd;
    my @msg;
    my @pattern;
    my @newstate;
    my $state = 0;
    my $timeout;

    nc_msg($verbose, "Status: ping_server start\n");

    #if (exists($env{'FIRMWARE_DUMP'})) {
    #    $full_path_name = Firmware_Dump($phandle);
    #}
    my $j = 0;
    my $tty_do_ping = 0;
    my $stack_level = 0;
    my $properties_matched = 0;
    my $adap_conn;
    my $speed_list;
    my $duplex_list;
    my @adap_conn_list;
    my $i;
    my $ping_debug;
    my $ping_rc;
    my $rc = 0;

    # If the adapter type chosen is ethernet, need to set the speed and duplex
    # of the adapter before we perform the ping.  If token ring or fddi,
    # this is not required, so begin with state 2.
    #
    # cmd(0) sets the given adapter as active, to allow setting of speed
    # and duplex
    #
    # cmd(1) writes the settings to the current adapter
    #
    # cmd(2) selects the /packages/net node as the active package to access the
    # ping command.
    #
    # The next command in cmd(3) is the ping command. This places the return code
    # on the stack. A return code of 0 indicates success.
    #
    # state 0, set the current adapter
    $done[0] = 0;
    $cmd[0] = "dev $full_path_name\r";
    $msg[0] = "Status: selected $full_path_name as the active adapter\n";
    #$pattern[0] = ".*dev(.*)0 >(.*)";
    $pattern[0] = "0 >";
    $newstate[0] = 1;

    # state 1, send property command to $selected type;
    $done[1] = 0;
    $cmd[1] = "\" ethernet,$adap_speed,$adap_conn,$adap_duplex\" encode-string \" chosen-network-type\" property\r";
    $msg[1] = "Status: chosen network type set\n";
    #$pattern[1] =".*ethernet(.*)0 >(.*)";
    $pattern[1] ="0 >";
    $newstate[1]= 2;

    # state 2, activate /packages/net
    $done[2] = 0;
    $cmd[2] = "dev /packages/net\r";
    $msg[2] = "Status: selected the /packages/net node as the active package\n";
    $pattern[2] = ".*dev.*packages.*net(.*)ok(.*)0 >(.*)";
    #$pattern[2] = "ok";
    $newstate[2]= 3;

    # state 3, ping the server
    $done[3] = 0;
    $msg[3] = "Status: ping return code now on stack\n";
    $newstate[3] = 4;

    #IPv6
    if ( $server_ip =~ /:/ ) {
        #::1, calculate link local address
        if ($client_ip eq "::1") {
            my $command = "/opt/xcat/share/xcat/tools/mac2linklocal -m $mac_address";
            $linklocal_ip = $rconsole->send($command);
        } else {
            $linklocal_ip = $client_ip;
        }
        $cmd[3] = "ping $full_path_name:ipv6,$server_ip,$linklocal_ip,$gateway_ip\r";
    } else {
        $cmd[3] = "ping $full_path_name:$server_ip,$client_ip,$gateway_ip\r";
    }
    $pattern[3] = ".*ping(.*)ok(.*)0 >(.*)";

    # state 4, all done
    $done[4] = 0;
    $cmd[4] = "0 to my-self\r";
    $msg[4] = "Status: resetting pointer\n";
    #$pattern[4] = "(.*)ok(.*)0 >(.*)";
    $pattern[4] = "ok";
    $newstate[4] = 5;

    # state 5, all done
    $done[5] = 1;


    # for ping, only need to set speed and duplex for ethernet adapters
    #
    if ( $list_type eq "ent" ) {
        $state = 0;

        # Get the list of properties for this adapter
        #
        $adap_prop_list_array = get_adap_prop($phandle, $rconsole, $node, $verbose);
        if ( $adap_prop_list_array eq 1 ) {
            nc_msg($verbose, "ERROR return from get_adap_prop\n");
            return 1;
        }

        if ( $adap_prop_list_array eq 0 ) {
            nc_msg($verbose, "No properties found for adapter '$full_path_name'\n");
            return 1;
        }

        # Now need to verify that the network params we were passed are valid for
        # the given adapter
        #
        my $a_speed;
        my $a_conn;
        my $a_duplex;
        for my $prop (@$adap_prop_list_array) {
            if( $prop =~ /(.*),(.*),(.*)/) {
                $a_speed = $1;
                $a_conn = $2;
                $a_duplex = $3;
                if ( ( $a_speed eq $adap_speed ) && ( $a_duplex eq $adap_duplex ) ) {
                    $properties_matched = 1;
                    if ( grep {$_ eq $a_conn } @adap_conn_list) {
                        push @adap_conn_list, $a_conn;
                    }
                }
            }
        }

        if ( $properties_matched eq 0 ) {
            $adap_speed = $a_speed;
            $adap_duplex = $a_duplex;
            $properties_matched = 1;
            push @adap_conn_list, $a_conn;
        }

        $i = scalar(@adap_conn_list);

        if ( $properties_matched eq 0 ) {
            nc_msg($verbose, "'$adap_speed/$adap_duplex' settings are not supported on this adapter\n");
            return 1;
        }
    } else {
        $state = 2;
    }

    $timeout = 300;
    while ( $done[$state] eq 0 ) {

        send_command($verbose, $rconsole, $cmd[$state]);
        @result = $rconsole->expect(

            $timeout,
            [qr/$pattern[$state]/s=>
            sub {
                nc_msg($verbose, $msg[$state]);
                $rconsole->clear_accum();
                $state = $newstate[$state];
                }
            ],
            [qr/]/=>
            sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [qr/(.*)DEFAULT(.*)/=>
            sub {
                nc_msg($verbose, "Default catch error\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [timeout=>
            sub {
                nc_msg($verbose, "Timeout when openning console\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [eof=>
            sub {
                nc_msg($verbose, "Cannot connect to the $node\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
        );

       return 1 if ($rc eq 1);

        if ( $state eq 1 ) {
            $adap_conn = $adap_conn_list[$j];
            $cmd[1] = "\" ethernet,$adap_speed,$adap_conn,$adap_duplex\" encode-string \" chosen-network-type\" property\r";
            nc_msg($verbose, "Status: Trying connector type $adap_conn\n");
            $j++;
        }
        if ((($tty_do_ping eq 1) && ($state eq 4)) || ($tty_do_ping != 1) && ($state eq 3) ) {
            $ping_debug = $result[2];
        }
        if ( ( ($tty_do_ping eq 1) && ($state eq 5) ) || ($tty_do_ping != 1) && ($state eq 4) ) {
            if ( ($tty_do_ping eq 1) && ($state eq 5) ) {
                #$ping_rc = $result[2];
                $stack_level = length($result[4]);
            } elsif ( ($state eq 4) && ($tty_do_ping != 1) && ($result[2] =~ /PING SUCCESS/)) {
                $ping_rc = 0;
            #} elsif ( $result[2] =~ /unknown word/ ) {
            #    nc_msg($verbose, "Status: try tty-do-ping.\n");
            #    $ping_rc = 1;
            #    $tty_do_ping = 1;
            #    $state = 3 ;
            #    $cmd[3] = "\"" . $full_path_name . ":" . $client_ip . "," . $server_ip . "," . $gateway_ip . "\" tty-do-ping\r";
            #    $pattern[3] = "(.*)ok(.*)(\[1-2\]) >(.*)";
            #
            #    # state 4, get the return code off the stack
            #    $done[4] = 0;
            #    $cmd[4] = ".\r";
            #    $msg[4] = "Status: return code displayed, stack empty\n";
            #    $pattern[4] = "(\[0-9\]*)  ok(.*)(\[0-1\]) >(.*)";
            #    $newstate[4] = 5;
            #
            #    # this command is used to work around a default catch problem in open
            #    # firmware.  Without it, a default catch occurs if we try to set
            #    # adapter properties again after a ping
            #    #
            #    # state 5, re$pointer
            #    $done[5] = 0;
            #    $cmd[5] = "0 to my-self\r";
            #    $msg[5] = "Status: resetting pointer\n" ;
            #    $pattern[5] = "(.*)ok(.*)0 >(.*)";
            #    $newstate[5] = 6 ;
            #
            #    # state 6, all done
            #    $done[6] = 1;
            } else {
                $ping_rc = 1;
            }

            if ( $ping_rc eq 0 ) {
                nc_msg($verbose, "# $full_path_name ping successful.\n");
            } elsif ( $ping_rc eq  1 ) {
                nc_msg($verbose, "# $full_path_name ping unsuccessful.\n");
                nc_msg($verbose, "# $full_path_name ping unsuccessful.\n");
                nc_msg($verbose, "$ping_debug\n");

                # An unsuccessful return may leave another item on the stack to
                # be removed.  Check for it, and remove if necessary
                my $matchexp = 0;
                my @exp_out;
                while ( $stack_level != 0 ) {
                    @exp_out = ();
                    send_command($verbose, $rconsole, ".\r");
                    @exp_out = $rconsole->expect(
                        [qr/(\[0-9\]*)  ok(.*)(\[0-1\]) >(.*)/s=>
                        sub {
                            $rconsole->clear_accum();
                            $matchexp = 1;
                            }
                        ],
                        [qr/]/=>
                        sub {
                            nc_msg($verbose, "Unexpected prompt\n");
                            $rconsole->clear_accum();
                            $rc = 1;
                            }
                        ],
                        [qr/(.*)DEFAULT(.*)/=>
                        sub {
                            nc_msg($verbose, "Default catch error\n");
                            $rconsole->clear_accum();
                            $rc = 1;
                            }
                        ],
                        [timeout=>
                        sub {
                            nc_msg($verbose, "Timeout in ping server\n");
                            $rconsole->clear_accum();
                            $rc = 1;
                            }
                        ],
                        [eof =>
                        sub {
                            nc_msg($verbose, "Cannot connect to $node\n");
                            $rconsole->clear_accum();
                            $rc = 1;
                            }
                        ],
                    );
                    if ($matchexp) {
                        $matchexp = 0;
                        $stack_level = length($exp_out[4]);
                        nc_msg($verbose, "Status: stack_level is <$stack_level>\n");
                    }
                }
                # Check if there are any more adapter connector types
                # to try
                #
                if ( ( $list_type eq "ent" ) && ( $j < $i ) ) {
                    $adap_conn = $adap_conn_list[$j];
                    nc_msg($verbose, "Status: Trying connector type $adap_conn\n");
                    $j++;

                    # Need to work around a default catch problem in open
                    # firmware by sending a "0 to my-self" instruction
                    # following the ping.  To make sure this happens in
                    # this rare case where we have an adapter with multiple connectors,
                    # we have to force the instruction into the 0th slot in
                    # the array.  This is OK, since we only set the current
                    # adapter once, upon entering this procedure.
                    #
                    $done[0] = 0;
                    $cmd[0] = "0 to my-self\r";
                    $msg[0] = "Status: resetting pointer\n";
                    $pattern[0] = "(.*)ok(.*)0 >(.*)";
                    $newstate[0] = 1;

                    $state = 0;
                }
            } else {
                nc_msg($verbose, "Unexpected ping return code\n");
                return 1;
            }
        }
    }
    return $ping_rc;
}


#-------------------------------------------------------------------------------

=head3    set_disk_boot



 PROCEDURE

 Declare procedure to obtain the list of valid adapter connector properties
 from the adapter card.  Connector types can be rj45, sc, 9pin, aui,
 bnc, or mic.  Speeds can be 10, 100, or 1000.  Duplex can be half or
 full.  This procedure will use the "supported-network-types"
 argument to the get-package-property command to get the list of
 properties for the given adapter.


=cut

#-----------------------------------------------------------------------------
sub set_disk_boot {
    my @expect_out = shift;
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    my $x0;
    my $x1;
    my $x2;
    my $command;
    my @done;
    my @cmd;
    my @msg;
    my @pattern;
    my @newstate;
    my $timeout;
    my $state;
    my $rc = 0;

    # state 0, get SMS screen
    $done[0] = 0;
    if($expect_out[0] =~ /(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)Select Boot Options(\r)/){
        $x0 = $1;
        $x1 = $2;
        $x2 = $3;
        $command = $4;
    }
    $cmd[0] = "$command\r";
    $msg[0] = "Status: sending return to repaint SMS screen\n";
    $pattern[0] = "(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)Configure Boot Device Order(\r)";
    $newstate[0] = 1;

    # state 1, Multiboot
    $done[1] = 0;
    $msg[1] = "Status: Multiboot\n";
    $pattern[1] = "(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)Select 1st Boot Device(\r)";
    $newstate[1] = 2;

    # state 2, Configure Boot Device Order
    $done[2] = 0;
    $msg[2] = "Status: Configure Boot Device Order";
    $pattern[2] = "(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)Hard Drive(.*)";
    $newstate[2] = 3;

    # state 3, Select Device Type
    $done[3] = 0;
    $msg[3] = "Status: Select Device Type";
    $pattern[3] = "(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)SCSI(.*)";
    $newstate[3] = 4;

    # state 4, Select Media Type
    $done[4] = 0;
    $msg[4] = "Status: Select Media Type";
    $pattern[4] = "(\n)(\[ ])(\[1])(\[.])(\[ ]+)(\\S+)(.*)";
    $newstate[4] = 5 ;

    # state 5, Select Media Adapter
    $done[5] = 0;
    $msg[5] = "Status: Select Media Adapter";
    $pattern[5] = "(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)(\\S)(\[ ]+)SCSI (\[0-9]+) MB Harddisk(.*)loc=(.*)\[)]";
    $newstate[5] = 6;

    # state 6, Select Device
    $done[6] = 0;
    $msg[6] = "Status: Select Device";
    $pattern[6] = "(\n)(\[ ])(\[0-9])(\[.])(\[ ]+)Set Boot Sequence(.*)";
    $newstate[6] = 7;

    # state 7, Select Task
    $done[7] = 0;
    $msg[7] = "Status: Select Task";
    $pattern[7] = "(.*)Current Boot Sequence(.*)";
    $newstate[7] = 8 ;

    # state 8, Return to Main Menu
    $done[8] = 0;
    $cmd[8] = "M";
    $msg[8] = "Status: Restored Default Setting.\n" ;
    $pattern[8] = "(.*)Navigation key(.*)";
    $newstate[8] = 9;

    # state 9, Getting to SMS Main Menu
    $done[9] = 0;
    $cmd[9] = "0\r";
    $msg[9] = "Status: Getting to SMS Main Menu.\n";
    $pattern[9] = "(.*)Exit SMS(.*)Prompt?(.*)";
    $newstate[9] = 10;

    # state 10, Exiting SMS
    $done[10] = 0;
    $cmd[10] = "Y";
    $msg[10] = "Status: Exiting SMS.\n";
    $pattern[10] = "(.*)ok(.*)0 >(.*)";
    $newstate[10] = 11;

    # state 11, all done
    $done[11] = 1;

    $timeout = 30;
    $state = 0;

    while ( $done[$state] eq 0 ) {
        send_command($verbose, $rconsole, $cmd[$state]);
        $rconsole->expect(
            [qr/$pattern[$state]/=>
                sub {
                    $rconsole->clear_accum();
                    if ( $state eq 4 ) {
                        if ( $expect_out[6] eq "None" ) {
                            $state = 8;
                        }
                    }
                    $state = $newstate[$state];
                    if ( ($state != 8) && ($state != 9) && ($state != 10) ) {
                        $cmd[$state] = "$expect_out[3]\r";
                    }
                }
            ],
            [qr/THE SELECTED DEVICES WERE NOT DETECTED IN THE SYSTEM/=>
                sub {
                    $rconsole->clear_accum();
                    nc_msg($verbose, " Status: THE hard disk WERE NOT DETECTED IN THE SYSTEM!\n");
                    $rc = 1;
                 }
            ],
            [timeout =>
                sub {
                    $rconsole->clear_accum();
                    nc_msg($verbose, "Timeout in settin boot order\n");
                    $rc = 1;
                }
            ],
            [eof =>
                sub {
                    $rconsole->clear_accum();
                    nc_msg($verbose, "Cannot connect to $node\n");
                    $rc = 1;
                }
            ],
        );
        if ($rc eq 1) {
            return 1;
        } else {
            return 0;
        }
    }
    return 0;

}


###################################################################
#
# PROCEDURE
#
# Declare procedure to boot the system from the selected ethernet card.
#
# This routine does the following:
# 1. Initiates the boot across the network. (state 0 or 1)
#
# state 99 is normal exit and state -1 is error exit.
###################################################################
sub boot_network {
    my $rconsole = shift;
    if (($rconsole) && ($rconsole =~ /xCAT::/))
    {
        $rconsole = shift;
    }
    my $full_path_name = shift;
    my $speed = shift;
    my $duplex = shift;
    my $chosen_adap_type = shift;
    my $server_ip = shift;
    my $client_ip = shift;
    my $gateway_ip = shift;
    my $netmask = shift;
    my $dump_target = shift;
    my $dump_lun = shift;
    my $dump_port = shift;
    my $verbose = shift;
    my $extra_args = shift;
    my $node = shift;
    my $set_boot_order = shift;
    my @net_device;
    my @pattern;
    my @cmd;
    my @msg;
    my @newstate;
    my @done;
    my $state = 0;
    my $timeout;
    my $boot_device_bk;
    my $rc = 0;


    nc_msg($verbose, "Status: boot_network start\n");
    ###################################################################
    # Variables associated with each of the commands sent by this routine
    # are defined below.
    #
    # The done variable is flag that is set to 1 to break out of the loop
    #
    # The cmd variable is the command to be sent to the chrp interface.
    #     In one case it set in the special processing code because the
    #     ihandle is not available then this code is executes.
    #
    # The msg variable contains the message sent after a successful pattern match
    #
    # The pattern variable is the pattern passed to expect
    #
    # The newstate variable indicates what command is to be issued next
    ###################################################################

    # If the install adapter is Ethernet or Token Ring, set the speed and
    # duplex during boot.
    # state 0, stack count 0
    $done[0] = 0;
    if ($dump_target ne "") {
        $net_device[0] = "$full_path_name:iscsi,ciaddr=$client_ip,subnet-mask=$netmask,itname=dummy,iport=$dump_port,ilun=$dump_lun,iname=$dump_target,siaddr=$server_ip,2";
        $pattern[0] = "iSCSI";
    } else {
        if ($extra_args ne "" ) {
            if ( $server_ip =~ /:/ ) { #ipv6
                $net_device[0] = "$full_path_name:ipv6,speed=$speed,duplex=$duplex,siaddr=$server_ip,ciaddr=$client_ip,giaddr=$gateway_ip,filename=$node,$extra_args";
            } else {
                $net_device[0] = "$full_path_name:speed=$speed,duplex=$duplex,bootp,$server_ip,,$client_ip,$gateway_ip $extra_args";
            }
        } else {
            if ( $server_ip =~ /:/ ) { #ipv6
                $net_device[0] = "$full_path_name:ipv6,speed=$speed,duplex=$duplex,siaddr=$server_ip,ciaddr=$client_ip,giaddr=$gateway_ip,filename=$node";
            } else {
                $net_device[0] = "$full_path_name:speed=$speed,duplex=$duplex,bootp,$server_ip,,$client_ip,$gateway_ip";
            }
        }
        $pattern[0] = "BOOTP";
    }

    $cmd[0] = "boot $net_device[0]\r";
    $msg[0] = "Status: network boot initiated\n";
    $newstate[0] = 99;

    # If the install adapter is FDDI, don't set the speed and duplex
    # state 1
    $done[1] = 0;
    $net_device[1] = "$full_path_name:bootp,$server_ip,,$client_ip,$gateway_ip";
    $cmd[1] = "boot $net_device[1]\r";
    $msg[1] = "Status: network boot initiated\n";
    $pattern[1] = "BOOTP";
    $newstate[1] = 99;

    # state 99, all done
    $done[99] = 1;

    # state -1, all done
    $done[100] = 1; #-1???

    if ($chosen_adap_type eq  "fddi" ) {
        $state = 1;
    } else {
        if ($speed eq "" || $duplex eq "" ) {
            nc_msg($verbose, "Cannot set speed or duplex for network boot\n");
            return 1;
        }
        $state = 0;
    }
    ##################################################################
    # Set the boot device order.
    ##################################################################
    if ( $set_boot_order > 0 ) {
        $done[2] =  0;
        $msg[2] =  "Status: read original boot-device\n";
        $cmd[2] =  "printenv boot-device\r";
        $pattern[2] =  ".*boot-device\\s+(\\S+)(.*)ok(.*)";
        $newstate[2] =  3;

        $done[3] =  0;
        $msg[3] =  "Status: set the environment variable boot-device\n";
        $pattern[3] =  "(.*)ok(.*)(\[0-9]) >(.*)";
        if (  $state eq 0 ) {
            $newstate[3] =  0;
        } else {
            $newstate[3] =  1;
        }
        $state = 2;
    }

    $timeout = 30;        # shouldn't take long
    while ( $done[$state] eq 0 ) {
        send_command($verbose, $rconsole, $cmd[$state]);
        $rconsole->expect(
            [qr/$pattern[$state]/=>
                sub {
                    $rconsole->clear_accum();
                    my @expect_out = shift;
                    if ( $state eq 2 ) {
                        if ( $set_boot_order eq 1 ) {
                            ########################################
                            # Set network as boot device
                            ########################################
                            $cmd[3] = "setenv boot-device $net_device[$newstate[3]]\r";
                        } elsif ( $set_boot_order eq 2 ) {
                            ########################################
                            # Set network as 1st boot device,disk as 2nd boot device
                            ########################################
                            $boot_device_bk = $expect_out[1];
                            $cmd[3] =  "setenv boot-device $net_device[$newstate[3]] $boot_device_bk\r";
                        } elsif ( $set_boot_order eq 3 ) {
                            ########################################
                            # Set disk as 1st boot device,network as 2nd boot device
                            ########################################
                            $boot_device_bk = $expect_out[1];
                            $cmd[3] =  "setenv boot-device $boot_device_bk $net_device[$newstate[3]]\r";
                        } elsif ( $set_boot_order eq 4 ) {
                            ########################################
                            # set disk as boot device
                            ########################################
                            $boot_device_bk = $expect_out[1];
                            $cmd[3] =  "setenv boot-device $boot_device_bk\r";
                        }
                    }
                    nc_msg($verbose, $msg[$state]);
                    $state = $newstate[$state];
                }
            ],
            [qr/----/=>
                sub {
                nc_msg ($verbose, $msg[$state]);
                $rconsole->clear_accum();
                $state = $newstate[$state];
                }
            ],
            # For some old firmware, does not output "----"
            [qr/BOOTP/=>
                sub {
                nc_msg ($verbose, $msg[$state]);
                $rconsole->clear_accum();
                $state = $newstate[$state];
                }
            ],
            [qr/]/=>
                sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [qr/(.*)DEFAULT(.*)/=>
                sub {
                    nc_msg($verbose, "Default catch error\n");
                    $rconsole->clear_accum();
                    $rc = 1;
                }
            ],
            [timeout=>
                sub {
                    nc_msg($verbose, "Timeout when openning console\n");
                    $rconsole->clear_accum();
                    $rc = 1;
                }
            ],
            [eof=>
                sub {
                    nc_msg($verbose, "Cannot connect to the $node\n");
                    $rconsole->clear_accum();
                    $rc = 1;
                }
            ],
        );
        return 1 if ($rc eq 1);
    }
    return 0;
}
#
# PROCEDURE
#
#
sub Boot {
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    #my @expect_out = shift;
    my $rc = 0;
    my $timeout;
    my $state;

    nc_msg($verbose, "Status: waiting for the boot image to boot up.\n");

    $timeout = 1200;      # could take a while depending on configuration
    $rconsole->expect(
        [qr/RESTART-CMD/=>
            sub {
                # If we see a "problem doing RESTART-CMD" message, we re-hit the OPEN-DEV
                # issue after firmware rebooted itself and we need to retry the netboot once more
                nc_msg($verbose, "The network boot ended in an error.\nError : RESTART-CMD\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
        #[!(qr/[0-9A-F]+/)=>
        #    sub {
        #        nc_msg($verbose, "The network boot ended in an error.\n");
        #        #nc_msg($verbose, $expect_out[buffer]);
        #        $rc = 1;
        #     }
        #],
        [qr/BOOTP/=>      #-ex
            sub {
                nc_msg($verbose, "# Network boot proceeding - matched BOOTP, exiting.\n");
                $rconsole->clear_accum();
            }
        ],
        # Welcome to AIX - some old firmware does not output BOOTP or ----
        [qr/Welcome/=>      #-ex
            sub {
                nc_msg($verbose, "# Network boot proceeding - matched Welcome, exiting.\n");
                $rconsole->clear_accum();
            }
        ],
        # tftp file download - some old firmware does not output BOOTP or ----
        [qr/FILE/=>      #-ex
            sub {
                nc_msg($verbose, "# Network boot proceeding - matched FILE.\n");
                $rconsole->clear_accum();
            }
        ],
        # some old firmware does not output BOOTP or ----
        [qr/Elapsed/=>      #-ex
            sub {
                nc_msg($verbose, "# Network boot proceeding - matched Elapsed, exiting.\n");
                $rconsole->clear_accum();
            }
        ],
        [qr/------/=>      #-ex
            sub {
                nc_msg($verbose, "# Network boot proceeding, exiting.\n");
                $rconsole->clear_accum();
            }
        ],
        [timeout=>
        sub {
            my $mins = $timeout/60;
            nc_msg($verbose, "Timeout waiting for the boot image to boot up. \
                  \n waited '$mins' minutes for the boot image to boot. \
                  \nEither the boot up has taken longer than expected or \
                  \nthere is a problem with system boot.  Check the boot \
                  \nof the node to determine if there is a problem.\n");
            $rconsole->clear_accum();
            #nc_msg($verbose, $expect_out[buffer]);
            $rc = 1;
            }
        ],
        [eof=>
        sub {
            nc_msg($verbose, "Port closed waiting for boot image to boot.\n");
            $rconsole->clear_accum();
            $rc = 1;
            }
        ],
    );
    return $rc;
}


###################################################################
#
# PROCEDURE
#
# Create multiple open-dev function in Open Firmware to try open
# a device.  The original problem is a firmware issue which fails
# to open a device.  This procedure will create multiple sub
# function in firmware to circumvent the problem.
#
###################################################################
sub multiple_open_dev {
    my $rconsole = shift;
    if (($rconsole) && ($rconsole =~ /xCAT::/))
    {
        $rconsole = shift;
    }
    my $node = shift;
    my $verbose = shift;
    my $expect_out;
    my $command;
    my $timeout;
    my $rc = 0;

    send_command($verbose, $rconsole, "dev /packages/net \r");
    send_command($verbose, $rconsole, "FALSE value OPEN-DEV_DEBUG \r");

    if (exists $ENV{'OPEN_DEV_DEBUG'}) {
       send_command($verbose, $rconsole, "TRUE to OPEN-DEV_DEBUG \r");
    }

    $command = ": new-open-dev ( str len -- true|false ) \
                  open-dev_debug if cr .\" NEW-OPEN-DEV: Entering, Device : \" 2dup type cr then \
                  { _str _len ; _n } \
                  0 -> _n \
                  get-msecs dup d# 60000 + ( start timeout ) \
                  begin \
                     ( start timeout ) get-msecs over > if \
                        open-dev_debug if \
                           ( start timeout ) drop get-msecs swap - \
                           cr .\" FAILED TO OPEN DEVICE\" \
                           cr .\" NUMBER OF TRIES \" _n .d \
                           cr .\" TIME ELAPSED \" ( time ) .d .\"  MSECONDS\" cr \
                        else \
                           ( start timout ) 2drop \
                        then \
                        false exit \
                     else \
                        true \
                     then \
                     while \
                        ( start timeout ) \
                        _n 1 + -> _n \
                        _str _len open-dev ( ihandle|false ) ?dup if \
                        -rot ( ihandle start timeout ) \
                        open-dev_debug if \
                           ( start timeout ) drop get-msecs swap - \
                           cr .\" SUCCESSFULLY OPENED DEVICE\" \
                           cr .\" NUMBER OF TRIES \" _n .d \
                           cr .\" TIME ELAPSED \" ( time ) .d .\" MSECONDS\" cr \
                        else \
                           ( start timeout ) 2drop \
                        then \
                        ( ihandle ) exit \
                 then \
                 ( start timeout ) \
                 repeat \
                 ; \r";
    send_command($verbose, $rconsole, $command);

    $timeout = 30;
    $rconsole->expect(
        $timeout,
        [qr/new-open-dev(.*)ok/=>
        #[qr/>/=>
            sub {
                nc_msg($verbose, "Status: at End of multiple_open_dev \n");
                $rconsole->clear_accum();
             }
        ],
        [qr/]/=>
            sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
             }
        ],
        [timeout =>
            sub {
                send_user(2, "Timeout\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
        [eof =>
            sub {
                send_user(2, "Cannot connect to $node\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
    );

    $command = "patch new-open-dev open-dev net-ping \r";
    send_command($verbose, $rconsole, $command);

    $rconsole->expect(
        $timeout,
        [qr/patch new-open-dev(.*)ok/=>
        #[qr/>/=>
            sub {
                nc_msg($verbose, "Status: at End of multiple_open_dev \n");
                $rconsole->clear_accum();
                return 0;
             }
        ],
        [qr/]/=>
            sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
             }
        ],
        [timeout =>
            sub {
                send_user(2, "Timeout\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
        [eof =>
            sub {
                send_user(2, "Cannot connect to $node\n");
                $rconsole->clear_accum();
                $rc = 1;
            }
        ],
    );

    return $rc;
}
###################################################################
#
# PROCEDURE
#
# Declare procedure to get additional firmware debug statement.
#
###################################################################
sub  Firmware_Dump {
    my $rconsole = shift;
    my $node = shift;
    my $verbose = shift;
    my $device_path = shift;
    my $phandle = shift;
    my $expect_out;
    my @done;
    my @cmd;
    my @msg;
    my @pattern;
    my @newstate;
    my $timeout;
    my $state = 0;
    my $rc = 0;

    nc_msg($verbose,"Status: Firmware_Dump start\n");

    # state 0
    $done[0] = 0;
    $cmd[0] = "dev /packages/obp-tftp\r";
    $msg[0] = "Status: selected /packages/obp_tftp\n";
    $pattern[0] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[0] = 1;

    # state 1
    $done[1] = 0;
    $cmd[1] = ": testing1 .\" OBP-TFTP entry\" cr init-nvram-adptr-parms ;\r";
    $msg[1] = "Status: running test - OBP-TFTP entry\n";
    $pattern[1] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[1] = 2;

    # state 2
    $done[2] = 0;
    $cmd[2] = ": testing2 .\" OBP-TFTP exit, TRUE\" cr true ;\r";
    $msg[2] = "Status: running test - OBP-TFTP exit\n";
    $pattern[2] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[2] = 3;

    # state 3
    $done[3] = 0;
    $cmd[3] = "patch testing1 init-nvram-adptr-parms open\r";
    $msg[3] = "Status: running test - patch testing1\n";
    $pattern[3] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[3] = 4;

    # state 4
    $done[4] = 0;
    $cmd[4] = "patch testing2 true open\r";
    $msg[4] = "Status: running test - patch testing2\n";
    $pattern[4] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[4] = 5;

    # state 5
    $done[5] = 0;
    $cmd[5] = "dev $device_path\r";
    $msg[5] = "Status: running test - dev $device_path\n";
    $pattern[5] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[5] = 6;

    # state 6
    $done[6] = 0;
    $cmd[6] = "true to debug-init\r";
    $msg[6] = "Status: running test - true to debug-init\n";
    $pattern[6] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[6] = 7;

    # state 7
    $done[7] = 0;
    $cmd[7] = "true to debug-error\r";
    $msg[7] = "Status: running test - true to debug-error\n";
    $pattern[7] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[7] = 8;

    # state 8
    $done[8] = 0;
    $cmd[8] = "$phandle to active-package\r";
    $msg[8] = "Status: running $phandle to active-package\n";
    $pattern[8] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[8] = 9;

    # state 9
    $done[9] = 0;
    $cmd[9] = ".properties\r";
    $msg[9] = "Status: running .properies\n";
    $pattern[9] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[9] = 10;

    # state 10
    $done[10] = 0;
    $cmd[10] = "clear\r";
    $msg[10] = "Status: running clear\n";
    $pattern[10] = "(.*)ok(.*)(\[0-9]) >(.*)";
    $newstate[10] = 11;

    # state 11, all done
    $done[11] = 1;

    $state = 0;
    $timeout = 30;       # shouldn't take long
    while ($done[$state] == 0) {
        send_command($verbose, $rconsole, $cmd[$state]);
        $rconsole->expect(
            [qr/$pattern[$state]/ =>
            sub {
                nc_msg($verbose, $msg[$state]);
                $rconsole->clear_accum();
                $state = $newstate[$state];
                }
            ],
            [qr/]/=>
            sub {
                nc_msg($verbose, "Unexpected prompt\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [qr/(.*)DEFAULT(.*)/=>
            sub {
                nc_msg($verbose, "Default catch error\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [timeout=>
                sub {
                nc_msg($verbose, "Timeout\n");
                nc_msg($verbose, "Status: timeout state is $state\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
            [eof =>
                sub {
                nc_msg($verbose, "Cannot connect to $node\n");
                $rconsole->clear_accum();
                $rc = 1;
                }
            ],
        );
        return 1 if ($rc eq 1);
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3    lparnetbootexp

    Function:
      Same function as the lpar_netboot.exp

    Return:
        0  - good
        1  - abort
        2  - usage error

=cut
#-----------------------------------------------------------------------------
sub lparnetbootexp
{
    my $opt = shift;
    if (($opt) && ($opt =~ /xCAT::/))
    {
        $opt = shift;
    }
    my $CONSOLEBIN = "/opt/xcat/bin/rcons";
    my $PROGRAM = "lpar_netboot";
    my $noboot = 0;   #default is to boot
    my $Boot_timeout = 3000;
    my @expect_out;
    my $req = shift;
    my $cmd;
    my $timeout;
    my $output;
    my $done;
    my $retry_count;
    my $query_count;
    my $match_pat;
    my $loc_code;
    my $ping_rc;
    my $ping_result;
    my $chosen_adap_type;
    my $i;
    my $phandle;
    my $match;
    my $list_type;
    my $sysoutput;
    my $exp_internal;
# Flags and initial variable
    my $discovery = 0;
    my $discover_all = 0;
    my $verbose = 0;
    my $discover_macaddr = 0;
    my $rc = 0;
    my $debug_flag = 0;
    my $rmvterm_flag = 0;
    my $immed_flag = 0;
    my $from_of = 0;
    my $dev_type_found = 0;
    my $list_physical = 0;
    my $set_boot_order = 0;
    my $colon = 0;
    my $choice = 0;
    my $full_path_name;
    my $adap_speed;
    my $adap_duplex;
    my $client_ip;
    my $server_ip;
    my $gateway_ip;
    my $extra_args;
    my $macaddress;
    my $netmask;
    my $dump_target;
    my $dump_lun;
    my $dump_port;
    my $phys_loc;
    my $userid;
    my $passwd;
    my $prompt = "\\\$ \$";
    my $ssh_spawn_id = 0;
    my $mac_address;
    my @outputarray;
    my $outputarrayindex = 0;

    $::CALLBACK = $req->{callback};
#
# Log the process id
#
    my $proc_id = getppid;
    nc_msg($verbose, "$PROGRAM Status: process id is $proc_id\n");

#
#
# Process command line options and parameters
#
#
#done==

    if ( exists ($opt->{A})) {
        $discover_all = 1;
    }

    if ( exists ($opt->{C})) {
        $client_ip = $opt->{C};
    }

    if ( exists ($opt->{D})) {
        $discovery = 1;
    }

    if ( exists ($opt->{G})) {
        $gateway_ip = $opt->{G};
    }

    if ( exists ($opt->{P})) {
        $list_physical = 1;
    }

    if ( exists ($opt->{M})) {
        $discover_macaddr = 1;
    }

    if ( exists ($opt->{N})) {
        $netmask = $opt->{N};
    }

    if ( exists ($opt->{S})) {
        $server_ip = $opt->{S};
    }

    if ( exists ($opt->{c})) {
        $colon = 1;
    }

    if ( exists ($opt->{d})) {
        $adap_duplex = $opt->{d};
    }

    if ( exists ($opt->{f})) {
        $rmvterm_flag = 1;
    }

    if ( exists ($opt->{g})) {
        $extra_args = $opt->{g};
    }

    if ( exists ($opt->{i})) {
        $immed_flag = 1;
    }

    if ( exists ($opt->{o})) {
        $from_of = 1;
    }

    if ( exists ($opt->{w})) {
        $set_boot_order = $opt->{w};
    }
     if ( exists ($opt->{L})) {
        $dump_lun = $opt->{L};
    }

    if ( exists ($opt->{l})) {
        $phys_loc = $opt->{l};
    }

    if ( exists ($opt->{m})) {
        $macaddress = $opt->{m};
    }

    if ( exists ($opt->{n})) {
        $noboot = 1;
    }

    if ( exists ($opt->{p})) {
        $dump_port = $opt->{p};
    }

    if ( exists ($opt->{s})) {
        $adap_speed = $opt->{s};
    }

    if ( exists ($opt->{T})) {
        $dump_target = $opt->{T};
    }

    if ( exists ($opt->{t})) {
        $list_type = $opt->{t};
        if ( $list_type eq "hfi-ent" ) {
            $dev_pat[0] = "hfi-ethernet";
            $dev_type[0] = "hfi-ent";
        }
        #
        # Validate the argument
        #
        $dev_type_found = 0;
        foreach my $dev (@dev_type) {
            if ( $dev eq $list_type) {
                $dev_type_found = 1;
                last;
            }
        }

        if ( $dev_type_found eq 0 ) {
           nc_msg($verbose, "$PROGRAM:$dev_type_found, '$list_type' is not a valid adapter choice\n");
           return [1];
        }
    }

    if ( exists ($opt->{v})) {
        $verbose = 1;
    } else {
        $verbose = 0;
    }
    if ( exists ($opt->{x})) {
        $debug_flag = 1;
    }
    if ( exists ($opt->{help})) {
        usage;
    }
    #set arg0 [lindex $argv 0]
    #set arg1 [lindex $argv 1]
    #if ( scalar(%$opt) > 10 ) {
    #    nc_msg($verbose, "$PROGRAM: Extraneous parameter(s)\n");
    #    usage;
    #}

    if ( $list_physical eq 0 ) {
        $dev_pat[3] = "l-lan";
        $dev_type[3] = "ent";
        $dev_count = scalar(@dev_pat);
    } else {
        $dev_pat[3] = "";
        $dev_type[3] = "";
        $dev_count = scalar(@dev_pat);
    }

    if ( $set_boot_order > 1 ) {
        $dev_pat[4] = "scsi";
        $dev_type[4] = "disk";
        $dev_count = scalar(@dev_pat);
    }
    my $node = $opt->{node};
    my $profile = $opt->{pprofile};
    my $manage = $opt->{fsp};
    my $lparid = $opt->{id};
    my $hcp = $opt->{hcp};



    if ($dev_type_found)    { nc_msg($verbose, "$PROGRAM Status: List only $list_type adapters\n");               }
    if ($noboot)            { nc_msg($verbose, "$PROGRAM Status: -n (no boot) flag detected\n");                  }
    if ($discovery)         { nc_msg($verbose, "$PROGRAM Status: -D (discovery) flag detected\n");                }
    if ($discover_all)      { nc_msg($verbose, "$PROGRAM Status: -A (discover all) flag detected\n" );            }
    if ($verbose)           { nc_msg($verbose, "$PROGRAM Status: -v (verbose debug) flag detected\n");            }
    if ($discover_macaddr)  { nc_msg($verbose, "$PROGRAM Status: -M (discover mac address) flag detected\n");     }
    if ($immed_flag)        { nc_msg($verbose, "$PROGRAM Status: -i (force immediate shutdown) flag detected\n"); }
    if ($list_physical)     { nc_msg($verbose, "$PROGRAM Status: -P (list only phsical network) flag detected\n");}
    if ($colon)             { nc_msg($verbose, "$PROGRAM Status: -c (list colon separated ) flag detected\n" );   }
    if ($debug_flag)        {
        nc_msg($verbose, "$PROGRAM Status: -d (debug) flag detected\n");
        #$exp_internal = 1;
        #$log_user = 1;
    }
    if ($discovery and $adap_speed )  { nc_msg($verbose, "$PROGRAM Status: using adapter speed of $adap_speed\n" );       }
    if ($discovery and $adap_duplex ) { nc_msg($verbose, "$PROGRAM Status: using adapter duplex of $adap_duplex\n" );     }
    if ($discovery and $server_ip )   { nc_msg($verbose, "$PROGRAM Status: using server IP address of $server_ip\n");     }
    if ($discovery and $client_ip)    { nc_msg($verbose, "$PROGRAM Status: using client IP address of $client_ip\n" );    }
    if ($discovery and $gateway_ip)   { nc_msg($verbose, "$PROGRAM Status: using gateway IP address of $gateway_ip\n");   }
    if ($discovery and $macaddress)   { nc_msg($verbose, "$PROGRAM Status: using macaddress of $macaddress\n"  );         }
    if ($discovery and $phys_loc )    { nc_msg($verbose, "$PROGRAM Status: using physical location code of $phys_loc\n"); }
    nc_msg($verbose, "node:".$node);
    ####################################
    # process the arguments
    ####################################
    $rc = xCAT::LparNetbootExp->ck_args($opt, $node, $verbose);
    if ($rc != 0) {
        nc_msg($verbose, "ck_args failed. \n");
        return [1];
    }

    ####################################
    # decide if need to do the connect
    ####################################


    ####################################
    # open the console
    ####################################
    nc_msg($verbose, "open port\n");
    $cmd = $::XCATROOT . '/bin/rcons ' . $node . ' -f';
    my $rconsole = Expect->new;
    ##################################################
    # raw_pty() disables command echoing and CRLF
    # translation and gives a more pipe-like behaviour.
    # Note that this must be set before spawning
    # the process. Unfortunately, this does not work
    # with AIX (IVM). stty(qw(-echo)) will at least
    # disable command echoing on all platforms but
    # will not suppress CRLF translation.
    ##################################################
    #$rconsole->raw_pty(1);
    #$rconsole->slave->stty(qw(sane -echo));        #hidden information return from rcons

    ##################################################
    # exp_internal(1) sets exp_internal debugging
    # to STDERR.
    ##################################################
    #$rconsole->exp_internal( $verbose );          #hidden information return from rcons

    ##################################################
    # log_stdout(0) disables logging to STDOUT.
    # This corresponds to the Tcl log_user variable.
    ##################################################
    #$rconsole->log_stdout( $verbose );           #hidden information return from rcons
    $rconsole->log_stdout(0);           #hidden information return from rcons

    my $consolefork = $rconsole->spawn($cmd);
    #$rconsole->log_file("/tmp/consolelog");
    my $console_pid = $rconsole->pid;
    unless ($console_pid) {
        nc_msg($verbose, "Unable to open console.\n");
        return [1];
    }
    nc_msg($verbose, "spawn_id is $console_pid.\n");
    ####################################
    #kill the process after received the signal
    ####################################

    ####################################
    # check the result of rcons
    ####################################
    nc_msg($verbose, "Connecting to the $node.\n");
    sleep 3;
    $timeout = 10;
    $rconsole->expect(
        $timeout,
        [ qr/Enter.* for help.*/i =>
            sub {
                $rc = 0;
                $rconsole->clear_accum();
                nc_msg($verbose, "Connected.\n");
            }
        ],
        [ timeout =>
            sub {
                $rc = 1;
                $rconsole->clear_accum();
                nc_msg($verbose, "Timeout waiting for console connection.\n");
            }
        ],
        [ eof =>
            sub {
                $rc = 2;
                $rconsole->clear_accum();
                nc_msg($verbose, "Please make sure rcons $node works.\n");
            }
        ],
    );

    unless ($rc eq 0) {
        return [1];
    }
    ####################################
    # check the node state
    ####################################
    nc_msg($verbose, "Checking for power off.\n");
    my $subreq = $req->{subreq};
    $output = xCAT::LparNetbootExp->run_lssyscfg($subreq, $verbose, $node);
    if ($output =~ /Not Available/) {
        nc_msg($verbose, "LPAR is Not Available. Please make sure the CEC's state.\n");
        return [1];
    } else {
        nc_msg($verbose, "The lpar state is $output.\n");
    }

    if ($from_of) {
        unless($output =~ /open firmware/i){
            nc_msg(2, "You are using the -o option. Please make sure the LPAR's initial state is open firmware.\n");
            return [1];
        }

    }

    ####################################
    # if -o is not used, power node of
    ####################################
    unless ($from_of) {
        if (($output =~ /^off$/i) or ($output =~ /Not Activated/i) ) {
            nc_msg($verbose, "# Power off complete.\n");
        } else {
            nc_msg($verbose, "# Begin to Power off the node.\n");
            $sysoutput = xCAT::Utils->runxcmd(
                {
                    command => ['rpower'],
                    node    => [$node],
                    arg     => ['off']
                },
            $subreq, 0, 1);
            $output = join ',', @$sysoutput;
            if ($::RUNCMD_RC != 0) {    #$::RUNCMD_RC  will get its value from runxcmd_output
                nc_msg($verbose, "Unable to run rpower $node off.\n");
                return [1];
            }

            unless ($output =~ /Success/) {
                nc_msg($verbose, "Power off failed.\n");
                return [1];
            } else {
                nc_msg($verbose, "Wait for power off.\n");
            }

            $done = 0;
            $query_count = 0;
            while (!$done) {
                $output = xCAT::LparNetbootExp->run_lssyscfg($subreq, $verbose, $node);
                if (($output =~ /^off$/i) or ($output =~ /Not Activated/)) {
                    nc_msg($verbose, "Power off complete.\n");
                    $done = 1;
                    next;
                }
                $query_count++;
                if ($query_count > 300) {
                    nc_msg($verbose, "Power off failed.\n");
                    return [1];
                }
                sleep 1;
            }
        }



        #################################################
        # if set_boot_order is set, set the boot order
        # if not set, power the node to open firmware
        #################################################
        $done = 0;
        $retry_count = 0;
        if ($set_boot_order > 1) {
            nc_msg($verbose, "Power on $node to SMS.\n");
            while (!$done) {
                $sysoutput = xCAT::Utils->runxcmd(
                    {
                        command => ['rpower'],
                        node    => [$node],
                        arg     => ['sms']
                    },
                $subreq, 0, 1);
                $output = join ',', @$sysoutput;
                nc_msg($verbose, "Waiting for power on...\n");

                if ($::RUNCMD_RC != 0) {
                    nc_msg($verbose, "Unable to run rpower $node sms\n");
                    return [1];
                }
                unless ($output =~ /Success/) {
                    if ($retry_count eq 3) {
                        nc_msg($verbose, "Power off failed, msg is $output.\n");
                        return [1];
                    }
                    sleep 1;
                    $retry_count ++;
                } else {
                    $done = 1;
                }
            }
        } else {
            nc_msg($verbose, "Power on the $node to the Open Firmware.\n");
            while (!$done) {
                $sysoutput = xCAT::Utils->runxcmd(
                    {
                        command => ['rpower'],
                        node    => [$node],
                        arg     => ['of']
                    },
                $subreq, 0, 1);
                $output = join ',', @$sysoutput;
                nc_msg($verbose, "Waiting for power on...\n");

                if ($::RUNCMD_RC != 0) {
                    nc_msg($verbose, "Unable to run rpower $node open firmware.\n");
                    return [1];
                }
                unless ($output =~ /Success/) {
                    if ($retry_count eq 3) {
                        nc_msg($verbose, "Power off failed, msg is $output.\n");
                        return [1];
                    }
                    sleep 1;
                    $retry_count ++;
                } else {
                    $done = 1;
                }
            }
        }


        ###########################
        # Check the node state
        ###########################
        $done = 0;
        $query_count = 0;
        $timeout = 1;
        nc_msg($verbose, "Check the node state again;");
        while(!$done) {
            $output = xCAT::LparNetbootExp->run_lssyscfg($subreq, $verbose, $node);
            nc_msg($verbose, "The node state is $output.\n");
            if ($output =~ /Open Firmware/i) {
                nc_msg($verbose, "Power on complete.\n");
                $done = 1;
                next;
            }

            $query_count++;
            # if the node is not in openfirmware state, just wait for it
            my @result = $rconsole->expect(
                $timeout,
                [ qr/(.*)elect this consol(.*)/=>
                sub {
                    $rconsole->send("0\r");
                    $rconsole->clear_accum();
                    #$rconsole->exp_continue();
                    }
                ],
            );

            if ($query_count > 300 ) {
                nc_msg($verbose, "Timed out waiting for power on of $node");
                nc_msg($verbose, "error from rpower command : \"$output\" \n");
                return [1];
            }
            sleep 1;
        }
    }


    ##############################
    # Check for active console
    ##############################
    nc_msg($verbose, "Check for active console.\n");
    $done = 0;
    $retry_count = 0;

    $timeout = 10;

    while (!$done) {
        my @result = $rconsole->expect(
            $timeout,
            #[qr/ok(.*)0 >/=>
            [qr/0(.*)ok/=>
            sub {
                nc_msg($verbose, " at ok prompt\n");
                $rconsole->clear_accum();
                $done = 1;
                }
            ],
            [qr/(.*)elect this consol(.*)/=>
            sub {
                nc_msg($verbose, " selecting active console\n");
                $rconsole->clear_accum();
                $rconsole->send("0\r");
                }
            ],
            [qr/English|French|German|Italian|Spanish|Portuguese|Chinese|Japanese|Korean/=>
            sub {
                nc_msg($verbose, "Languagae Selection Panel received\n");
                $rconsole->clear_accum();
                $rconsole->send("2\r");
                }
            ],
            [qr/admin/=>
            sub {
                nc_msg($verbose, "No password specified\n");
                $rconsole->soft_close();
                $rc = 1;
                }
            ],
            [qr/Invalid Password/=>
            sub {
                nc_msg($verbose, "FSP password is invalid.\n");
                $rconsole->soft_close();
                $rc = 1;
                }
            ],
            [qr/SMS(.*)Navigation Keys/=>
            sub {
                nc_msg($verbose, "SMS\n");
                $rconsole->clear_accum();
                $done = 1;
                }
            ],
            [timeout=>
            sub {
                $rconsole->send("\r");
                $retry_count++;
                if ($retry_count eq 9) {
                    nc_msg($verbose, "Timeout waiting for ok prompt; exiting.\n");
                    $rconsole->soft_close();
                    $rc = 1;
                    }
                }
            ],
            [eof =>
            sub {
                nc_msg($verbose, "Cannot connect to $node");
                $rconsole->soft_close();
                $rc = 1;
                }
            ],
        );
        return [1] if ($rc eq 1);
    }




    ##############################
    # Set the node boot order
    ##############################
    if ($set_boot_order) {            #rnetboot node will not go here
        nc_msg($verbose, "begin to set disk boot");
        my $result = set_disk_boot( $rconsole, $node, $verbose);#@expect_out, $rconsole, $node, $verbose);
        unless( $result ) {
            nc_msg($verbose, "Unable to set $node boot order");
        }
    }

    sleep 1;

    ##############################
    # Call get_phandle to gather
    # information for all the
    # supported network adapters
    # in the device tree.
    ##############################
    $done = 0;
    $retry_count = 0;
    nc_msg($verbose, "begin to run get_phandle");
    while (!$done) {
        my $result = get_phandle($rconsole, $node, $verbose);
        if ( $result eq 1) {
            $retry_count++;
            $rconsole->send("\r");
            if ( $retry_count eq 3) {
                nc_msg($verbose, "Unable to obtain network adapter information.  Quitting.\n");
                return [1];
            }
        } else {
            $done = 1;
        }
    }


    ##############################
    # Call multiple_open_dev to
    # circumvent firmware OPEN-DEV
    # failure
    ##############################
    nc_msg($verbose, "begin to run multiple_open_dev");
    my $result = xCAT::LparNetbootExp->multiple_open_dev($rconsole, $node, $verbose);
    if ( $result eq 1) {
       nc_msg($verbose, "Unable to obtain network adapter information.  Quitting.\n");
       return [1];
    }

    ##############################
    #
    ##############################
    nc_msg($verbose, "begin to process opt-discovery");
    if ($discovery) {              #rnetboot node will not go here
        nc_msg($verbose, "# Client IP address is $client_ip\n");
        nc_msg($verbose, "# Server IP address is $server_ip\n");
        nc_msg($verbose, "# Gateway IP address is $gateway_ip\n");
    }


    ##############################
    # Display information for all
    # supported adapters
    ##############################
    if ($noboot) {  #if not do net boot
        if ($list_type) {
            $match_pat = $list_type;
        } else {
            $match_pat = ".*";
        }


        if($colon) {
            nc_msg($verbose, "#Type:Location_Code:MAC_Address:Full_Path_Name:Ping_Result:Device_Type:Size_MB:OS:OS_Version:\n");
            $outputarrayindex++;  # start from 1, 0 is used to set as 0
            $outputarray[$outputarrayindex] = "#Type:Location_Code:MAC_Address:Full_Path_Name:Ping_Result:Device_Type:Size_MB:OS:OS_Version:";
        } else {
            nc_msg($verbose, "# Type \tLocation Code \tMAC Address\t Full Path Name\t Ping Result\n");
            $outputarrayindex++;
            $outputarray[$outputarrayindex] = "# Type \tLocation Code \tMAC Address\t Full Path Name\t Ping Result";
        }

        if ( $discover_all ) {    #getmacs here
            for( $i = 0; $i < $adapter_found; $i++) {
                if ($adap_type[$i] =~ /$match_pat/) {
                    if (!($adap_type[$i] eq "hfi-ent")) {
                        $mac_address = get_mac_addr($phandle_array[$i], $rconsole, $node, $verbose);
                        $loc_code = get_adaptr_loc($phandle_array[$i], $rconsole, $node, $verbose);
                    }
                    $ping_result = "";
                    if ($discovery) {
                        $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);
                        nc_msg($verbose, "ping_server returns $ping_rc\n");
                        unless( $ping_rc eq 0) {
                            $ping_result = "unsuccessful";
                        } else {
                            $ping_result = "successful";
                        }
                    }

                    if ( $adap_type[$i] eq "hfi-ent") {
                        $mac_address = get_mac_addr($phandle_array[$i], $rconsole, $node, $verbose);
                        $loc_code = get_adaptr_loc($phandle_array[$i], $rconsole, $node, $verbose);
                    }

                    if ($full_path_name_array[$i] =~ /vdevice/)  {
                        $device_type = "virtual";
                    } else {
                        $device_type = "physical";
                    }

                    if($colon) {
                        nc_msg($verbose, "$adap_type[$i]\:$loc_code\:$mac_address\:$full_path_name_array[$i]\:$ping_result\:$device_type\:\:\:\:\n");
                        $outputarrayindex++;
                        $outputarray[$outputarrayindex] = "$adap_type[$i]\:$loc_code\:$mac_address\:$full_path_name_array[$i]\:$ping_result\:$device_type\:\:\:\:";
                    } else {
                        nc_msg($verbose, "$adap_type[$i] $loc_code $mac_address $full_path_name_array[$i] $ping_result $device_type\n");
                        $outputarrayindex++;
                        $outputarray[$outputarrayindex] = "$adap_type[$i] $loc_code $mac_address $full_path_name_array[$i] $ping_result $device_type";
                    }
                }
            }
        } else {
            for( $i = 0; $i < $adapter_found; $i++) {
                if ($adap_type[$i] =~ /$match_pat/) {
                    if (!($adap_type[$i] eq "hfi-ent")) {
                        $mac_address = get_mac_addr($phandle_array[$i], $rconsole, $node, $verbose);
                        $loc_code = get_adaptr_loc($phandle_array[$i], $rconsole, $node, $verbose);
                    }
                    $ping_result = "";
                    if ($discovery) {
                        $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);
                        nc_msg($verbose, "ping_server returns $ping_rc\n");
                        unless( $ping_rc eq 0) {
                            $ping_result = "unsuccessful";
                        } else {
                            $ping_result = "successful";
                        }
                    }

                    if ( $adap_type[$i] eq "hfi-ent") {
                        $mac_address = get_mac_addr($phandle_array[$i], $rconsole, $node, $verbose);
                        $loc_code = get_adaptr_loc($phandle_array[$i], $rconsole, $node, $verbose);
                    }

                    if ($full_path_name_array[$i] =~ /vdevice/)  {
                        $device_type = "virtual";
                    } else {
                        $device_type = "physical";
                    }

                    if($colon) {
                        nc_msg($verbose, "$adap_type[$i]\:$loc_code\:$mac_address\:$full_path_name_array[$i]\:$ping_result\:$device_type\:\:\:\:\n");
                    } else {
                        nc_msg($verbose, "$adap_type[$i] $loc_code $mac_address $full_path_name_array[$i] $ping_result $device_type\n");
                    }
                    last;
                }
            }
        }
        if ($from_of != 1) {
            nc_msg($verbose, "power off the node after noboot eq 1\n");
            $sysoutput = xCAT::Utils->runxcmd(
                {
                    command => ['rpower'],
                    node    => [$node],
                    arg     => ['off']
                },
            $subreq, 0, 1);
            $output = join ',', @$sysoutput;
            if ($::RUNCMD_RC != 0) {
                nc_msg($verbose, "Unable to run rpower $node sms.\n");
                nc_msg($verbose, "Status: error from rpower command\n");
                nc_msg($verbose, "Error : $output\n");
                return [1];
            }
        }
    } else { # Do a network boot
    # Loop throught the adapters and perform a ping test to discover an
    # adapter that pings successfully, then use that adapter to network boot.
        if ($discover_all) {  #rnetboot should not use -A
            for ($i = 0; $i < $adapter_found; $i++) {
                $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);


                if ( $ping_rc eq 0) {
                    $phandle = $phandle_array[$i];
                    $full_path_name = $full_path_name_array[$i];
                    $chosen_adap_type = $adap_type[$i];
                    last;
                }
            }
        } elsif ( $macaddress ne "" ) {          #rnetboot here     
            $match = 0;
            for ($i = 0; $i < $adapter_found; $i++) {
                if ($adap_type[$i] =~ /hfi-ent/) {
                    $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);
                }
                $mac_address = get_mac_addr($phandle_array[$i], $rconsole, $node, $verbose);
                if ( $macaddress =~ /$mac_address/ ) {
                    if ($discovery eq 1) {
                        unless ( $adap_type[$i] eq "hfi-ent" ) {
                           $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);
                        }
                        unless ( $ping_rc eq 0) {
                            nc_msg($verbose, "Unable to boot network adapter.\n" );
                            return [1];
                        }
                    }
                $phandle =  $phandle_array[$i];
                $full_path_name = $full_path_name_array[$i];
                $chosen_adap_type = $adap_type[$i];
                $match = 1;
                last;
                }
            }
            unless($match) {
                nc_msg($verbose, "Can not find mac address '$macaddress'\n");
                return [1];
            }
        } elsif ( $phys_loc ne "") {
            $match = 0;
            for ($i = 0; $i < $adapter_found; $i++) {
                $loc_code = get_adaptr_loc($phandle_array[$i], $rconsole, $node, $verbose);
                if ($loc_code =~ /$phys_loc/) {
                    if ($discovery) {
                        $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);
                        unless ($ping_rc eq 0) {
                            nc_msg($verbose, "Unable to boot network adapter.\n");
                            return [1];
                        }
                    }
                    $phandle =  $phandle_array[$i];
                    $full_path_name = $full_path_name_array[$i];
                    $chosen_adap_type = $adap_type[$i];
                    $match = 1;
                    last;
                }
            }
            if (!$match) {
                nc_msg($verbose, "Can not find physical location '$phys_loc'\n");
                return [1];
            }
        } else {
        #
        # Use the first ethernet adapter in the
        # device tree.
        #
            for ($i = 0; $i < $adapter_found; $i++) {
            nc_msg($verbose, " begint to boot from first adapter in the device tree \n");
                if ($adap_type[$i] eq $list_type ) {
                    if ( $discovery eq 1 ){
                        $ping_rc = ping_server($phandle_array[$i], $full_path_name_array[$i], $rconsole, $node, $mac_address, $verbose, $adap_speed, $adap_duplex, $list_type, $server_ip, $client_ip, $gateway_ip);
                        unless ($ping_rc eq 0) {
                            return [1];
                        }
                    }
                    $phandle = $phandle_array[$i];
                    $full_path_name = $full_path_name_array[$i];
                    $chosen_adap_type = $adap_type[$i];
                    last;
                }
            }
        }
        my $result;
        if ($full_path_name eq "") {
            nc_msg($verbose, "Unable to boot network adapter.\n");
            return [1];
        } else {
            nc_msg($verbose, "# Network booting install adapter.\n");
            $result = xCAT::LparNetbootExp->boot_network($rconsole, $full_path_name, $adap_speed, $adap_duplex , $chosen_adap_type, $server_ip, $client_ip, $gateway_ip, $netmask, $dump_target, $dump_lun, $dump_port, $verbose, $extra_args, $node, $set_boot_order );
        }


        if ($result eq 0) {
            nc_msg($verbose, "bootp sent over netowrk.\n");
            my $res = Boot($rconsole, $node, $verbose);#, @expect_out);
            unless ($res eq 0) {
                nc_msg($verbose, "Can not boot, result = $res. \n");
            }
        } else {
            nc_msg($verbose, "return code $result from boot_network\n");
        }

        ###########################################################################
        # Need to retry network boot because of intermittant network failure
        # after partition reboot.  Force partition to stop at Open Firmware prompt.
        ###########################################################################
        if ($result eq 5) {

            $timeout = 300;
            $rconsole->expect(
                $timeout,
                [ qr/keyboard/i,
                    sub {
                        $rconsole->send("8\r");
                        $rconsole->clear_accum();
                        sleep 10;
                    }
                ],
                [ qr/timeout/i,
                    sub {
                        nc_msg($verbose, "Timeout; exiting.\n");
                        $rconsole->clear_accum();
                        $rc = 1;
                    }
                ],
                [ eof =>
                    sub {
                        nc_msg($verbose, "cannot connect to $node.\n");
                        $rconsole->clear_accum();
                        $rc = 1;
                    }
                ],
                [
                    sub {
                        nc_msg($verbose, "# Network booting install adapter.\n");
                        nc_msg($verbose, "Retrying network-boot from RESTART-CMD error.\n");
                        $done = 0;
                        while (! $done ) {
                            my $res = xCAT::LparNetbootExp->boot_network($node,);
                            if ($res eq 0) {
                                $done = 1;
                            } else {
                                sleep 10;
                            }
                        }
                    }
                ],
            );
            return [1] if ($rc eq 1);
            nc_msg($verbose, "# bootp sent over network.\n");
            $rc = Boot($rconsole, $node, $verbose);#, @expect_out);
            unless ($rc eq 0) {
                nc_msg($verbose, "Can't boot here. \n");
            }
        }
    }

    ################################################
    # mission accomplished, beam me up scotty.
    #################################################
    unless ($noboot) {  #if do the rnetboot, just return
        if ( $rc eq 0) {
            nc_msg($verbose, "# Finished.\n" );
            $outputarrayindex++;
            $outputarray[$outputarrayindex] = "Finished.";
        } else {
            nc_msg($verbose, "# Finished in an error.\n");
            $outputarrayindex++;
            $outputarray[$outputarrayindex] = "Finished in an error.";
        }
    } else {   #if not rnetboot, for example, getmacs, power off the node
        $done = 0;
        $query_count = 0;
        while(!$done) {
            $output = xCAT::LparNetbootExp->run_lssyscfg($subreq, $verbose, $node);

            ##############################################
            # separate the nodename from the query status
            ##############################################
            if ($from_of != 1) {
                if (( $output =~ /^off$/i ) or ($output =~ /Not Activated/i)) {
                    $done = 1;
                }
            } else {
                if ( $output =~ /firmware/i ) {
                    $done = 1;
                }
            }
            $query_count++;
            if ( $query_count > 60 ){
                $done = 1;
            }
            sleep 1;
        }
    }
    $cmd = "~.";
    send_command($verbose, $rconsole, $cmd);

    $outputarray[0] = 0;
    return \@outputarray;

}

