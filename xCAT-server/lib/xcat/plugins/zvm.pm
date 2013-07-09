# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    xCAT plugin to support z/VM (s390x)
    
=cut

#-------------------------------------------------------
package xCAT_plugin::zvm;
use xCAT::Client;
use xCAT::zvmUtils;
use xCAT::zvmCPUtils;
use xCAT::MsgUtils;
use Sys::Hostname;
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::NetworkUtils;
use XML::Simple;
use File::Basename;
use File::Copy;
use File::Path;
use Time::HiRes;
use POSIX;
use Getopt::Long;
use strict;

# If the following line is not included, you get:
# /opt/xcat/lib/perl/xCAT_plugin/zvm.pm did not return a true value
1;

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        rpower   => 'nodehm:power,mgt',
        rinv     => 'nodehm:mgt',
        mkvm     => 'nodehm:mgt',
        rmvm     => 'nodehm:mgt',
        lsvm     => 'nodehm:mgt',
        chvm     => 'nodehm:mgt',
        rscan    => 'nodehm:mgt',
        nodeset  => 'noderes:netboot',
        getmacs  => 'nodehm:getmac,mgt',
        rnetboot => 'nodehm:mgt',
        rmigrate => 'nodehm:mgt',
        chhypervisor => ['hypervisor:type', 'nodetype:os=(zvm.*)'],
        revacuate => 'hypervisor:type',
        reventlog => 'nodehm:mgt',
    };
}

#-------------------------------------------------------

=head3  preprocess_request

    Check and setup for hierarchy

=cut

#-------------------------------------------------------
sub preprocess_request {
    my $req      = shift;
    my $callback = shift;

    # Hash array
    my %sn;

    # Scalar variable
    my $sn;

    # Array
    my @requests;

    # If already preprocessed, go straight to request
    if ( $req->{_xcatpreprocessed}->[0] == 1 ) {
        return [$req];
    }
    my $nodes   = $req->{node};
    my $service = "xcat";

    # Find service nodes for requested nodes
    # Build an individual request for each service node
    if ($nodes) {
        $sn = xCAT::ServiceNodeUtils->get_ServiceNode( $nodes, $service, "MN" );

        # Build each request for each service node
        foreach my $snkey ( keys %$sn ) {
            my $n = $sn->{$snkey};
            print "snkey=$snkey, nodes=@$n\n";
            my $reqcopy = {%$req};
            $reqcopy->{node}                   = $sn->{$snkey};
            $reqcopy->{'_xcatdest'}            = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;
        }

        return \@requests;
    }
    else {

        # Input error
        my %rsp;
        my $rsp;
        $rsp->{data}->[0] = "Input noderange missing. Useage: zvm <noderange> \n";
        xCAT::MsgUtils->message( "I", $rsp, $callback, 0 );
        return 1;
    }
}

#-------------------------------------------------------

=head3  process_request

    Process the command.  This is the main call.

=cut

#-------------------------------------------------------
sub process_request {
    my $request  = shift;
    my $callback = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    $::STDIN     = $request->{stdin}->[0];
    my %rsp;
    my $rsp;
    my @nodes = @$nodes;
    my $host  = hostname();

    # Directory where executables are on zHCP
    $::DIR = "/opt/zhcp/bin";
    
    # Directory where system config is on zHCP
    $::SYSCONF = "/opt/zhcp/conf";
    
    # Directory where zFCP disk pools are on zHCP
    $::ZFCPPOOL = "/var/opt/zhcp/zfcp";

    # Use sudo or not
    # This looks in the passwd table for a key = sudoer
    ($::SUDOER, $::SUDO) = xCAT::zvmUtils->getSudoer();
    
    # Process ID for xfork()
    my $pid;

    # Child process IDs
    my @children;

    #*** Power on or off a node ***
    if ( $command eq "rpower" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                powerVM( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if ( !( @children % 10 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Hardware and software inventory ***
    elsif ( $command eq "rinv" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                if (xCAT::zvmUtils->isHypervisor($_)) {
                    inventoryHypervisor( $callback, $_, $args );
                } else {
                    inventoryVM( $callback, $_, $args );
                }
                
                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    #*** Migrate a virtual machine ***
    elsif ( $command eq "rmigrate" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                migrateVM( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case
    
    #*** Evacuate all virtual machines off a hypervisor ***
    elsif ( $command eq "revacuate" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                evacuate( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    #*** Create a virtual server ***
    elsif ( $command eq "mkvm" ) {

        # Determine if the argument is a node
        my $clone = 0;
        if ( $args->[0] ) {
            $clone = xCAT::zvmUtils->isZvmNode( $args->[0] );
        }

        #*** Clone virtual server ***
        if ( $clone ) {
            cloneVM( $callback, \@nodes, $args );
        }

        #*** Create user entry ***
        # Create node based on directory entry
        # or create a NOLOG if no entry is provided
        else {
            foreach (@nodes) {
                $pid = xCAT::Utils->xfork();

                # Parent process
                if ($pid) {
                    push( @children, $pid );
                }

                # Child process
                elsif ( $pid == 0 ) {

                    makeVM( $callback, $_, $args );

                    # Exit process
                    exit(0);
                }    # End of elsif
                else {

                    # Ran out of resources
                    die "Error: Could not fork\n";
                }
            }    # End of foreach
        }    # End of else
    }    # End of case

    #*** Remove a virtual server ***
    elsif ( $command eq "rmvm" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                removeVM( $callback, $_ );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if ( !( @children % 10 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Print the user entry ***
    elsif ( $command eq "lsvm" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                listVM( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if ( !( @children % 10 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Change the user entry ***
    elsif ( $command eq "chvm" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                changeVM( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if ( !( @children % 10 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Collect node information from zHCP ***
    elsif ( $command eq "rscan" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                scanVM( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    #*** Set the boot state for a node ***
    elsif ( $command eq "nodeset" ) {
        foreach (@nodes) {

            # Only one file can be punched to reader at a time
            # Forking this process is not possible
            nodeSet( $callback, $_, $args );

        }    # End of foreach
    }    # End of case

    #*** Get the MAC address of a node ***
    elsif ( $command eq "getmacs" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                getMacs( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    #*** Boot from network ***
    elsif ( $command eq "rnetboot" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                netBoot( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if ( !( @children % 10 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case
    
    #*** Configure the virtualization hosts ***
    elsif ( $command eq "chhypervisor" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                changeHypervisor( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if ( !( @children % 10 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case
    
    #*** Retrieve or clear event logs ***
    elsif ( $command eq "reventlog" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                eventLog( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    #*** Update the node (no longer supported) ***
    elsif ( $command eq "updatenode" ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                updateNode( $callback, $_, $args );

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    # Wait for all processes to end
    foreach (@children) {
        waitpid( $_, 0 );
    }

    return;
}

#-------------------------------------------------------

=head3   removeVM

    Description  : Delete the user from user directory
    Arguments    : Node to remove
    Returns      : Nothing
    Example      : removeVM($callback, $node);
    
=cut

#-------------------------------------------------------
sub removeVM {

    # Get inputs
    my ( $callback, $node ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Power off user ID
    my $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId -f IMMED"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId -f IMMED");

    # Delete user entry
    $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Delete_DM -T $userId -e 1"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Delete_DM -T $userId -e 1");
    xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    
    # Check for errors
    my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
    if ( $rc == -1 ) {
        return;
    }
    
    # Go through each pool and free zFCP devices belonging to node
    my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
    my $pool;
    my @luns;
    my $update;
    my $expression;
    foreach (@pools) {
        $pool = xCAT::zvmUtils->replaceStr( $_, ".conf", "" );
        
        @luns = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$_" | egrep -i $node`);
        foreach (@luns) {
            # Update entry: status,wwpn,lun,size,range,owner,channel,tag
            my @info = split(',', $_);   
            $update = "free,$info[1],$info[2],$info[3],$info[4],,,";
            $expression = "'s#" . $_ . "#" .$update . "#i'";
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e $expression $::ZFCPPOOL/$pool.conf"`;
        }
        
        if (@luns) {
            xCAT::zvmUtils->printLn($callback, "$node: Updating FCP device pool $pool... Done");
        }
    }

    # Check for errors
    $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
    if ( $rc == -1 ) {
        return;
    }

    # Remove node from 'zvm', 'nodelist', 'nodetype', 'noderes', and 'nodehm' tables
    # Save node entry in 'mac' table
    xCAT::zvmUtils->delTabEntry( 'zvm',      'node', $node );
    xCAT::zvmUtils->delTabEntry( 'hosts',    'node', $node );
    xCAT::zvmUtils->delTabEntry( 'nodelist', 'node', $node );
    xCAT::zvmUtils->delTabEntry( 'nodetype', 'node', $node );
    xCAT::zvmUtils->delTabEntry( 'noderes',  'node', $node );
    xCAT::zvmUtils->delTabEntry( 'nodehm',   'node', $node );

    # Erase old hostname from known_hosts
    $out = `ssh-keygen -R $node`;
    
    # Erase hostname from /etc/hosts
    $out = `sed -i /$node./d /etc/hosts`;

    return;
}

#-------------------------------------------------------

=head3   changeVM

    Description  : Change a virtual machine's configuration
    Arguments    : Node
                   Option         
    Returns      : Nothing
    Example      : changeVM($callback, $node, $args);
         
=cut

#-------------------------------------------------------
sub changeVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Output string
    my $out = "";

    # add3390 [disk pool] [device address] [size] [mode] [read password (optional)] [write password (optional)] [multi password (optional)]
    if ( $args->[0] eq "--add3390" ) {
        my $pool    = $args->[1];
        my $addr    = $args->[2];
        my $cyl     = $args->[3];
        
        
        # If the user specifies auto as the device address, then find a free device address
        if ($addr eq "auto") {
            $addr = xCAT::zvmUtils->getFreeAddress($::SUDOER, $node, "smapi");
        }
        
        my $mode = "MR";
        if ($args->[4]) {
            $mode = $args->[4];
        }
        
        my $readPw  = "''";
        if ($args->[5]) {
            $readPw = $args->[5];
        }
        
        my $writePw = "''";
        if ($args->[6]) {
            $writePw = $args->[6];
        }
        
        my $multiPw = "''";
        if ($args->[7]) {
            $multiPw = $args->[7];
        }
        
        # Convert to cylinders if size is given as M or G
        # Otherwise, assume size is given in cylinders
        # Note this is for a 4096 block size ECKD disk, where 737280 bytes = 1 cylinder
        if ($cyl =~ m/M/i) {
            $cyl =~ s/M//g;
            $cyl = xCAT::zvmUtils->trimStr($cyl);
            $cyl = sprintf("%.4f", $cyl);
            $cyl = ($cyl * 1024 * 1024)/737280;
            $cyl = ceil($cyl);
        } elsif ($cyl =~ m/G/i) {
            $cyl =~ s/G//g;
            $cyl = xCAT::zvmUtils->trimStr($cyl);
            $cyl = sprintf("%.4f", $cyl);
            $cyl = ($cyl * 1024 * 1024 * 1024)/737280;
            $cyl = ceil($cyl);
        } elsif ($cyl =~ m/[a-zA-Z]/) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Size can be Megabytes (M), Gigabytes (G), or number of cylinders" );
            return;
        }
        
        # Add to directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $readPw -W $writePw -M $multiPw"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $userId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $readPw -W $writePw -M $multiPw");
        
        # Add to active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create -T $userId -v $addr -m $mode");
        }
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # add3390active [device address] [mode]
    elsif ( $args->[0] eq "--add3390active" ) {
        my $addr = $args->[1];
        my $mode = $args->[2];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create -T $userId -v $addr -m $mode");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # add9336 [disk pool] [virtual device address] [size] [mode] [read password (optional)] [write password (optional)] [multi password (optional)]
    elsif ( $args->[0] eq "--add9336" ) {
        my $pool    = $args->[1];
        my $addr    = $args->[2];
        my $blks    = $args->[3];
        
        # If the user specifies auto as the device address, then find a free device address
        if ($addr eq "auto") {
            $addr = xCAT::zvmUtils->getFreeAddress($::SUDOER, $node, "smapi");
        }
        
        my $mode = "MR";
        if ($args->[4]) {
            $mode = $args->[4];
        }
        
        my $readPw  = "''";
        if ($args->[5]) {
            $readPw = $args->[5];
        }
        
        my $writePw = "''";
        if ($args->[6]) {
            $writePw = $args->[6];
        }
        
        my $multiPw = "''";
        if ($args->[7]) {
            $multiPw = $args->[7];
        }
        
        # Convert to blocks if size is given as M or G
        # Otherwise, assume size is given in blocks
        # Note this is for a 4096 block size ECKD disk, where 737280 bytes = 1 cylinder
        if ($blks =~ m/M/i) {
            $blks =~ s/M//g;
            $blks = xCAT::zvmUtils->trimStr($blks);
            $blks = sprintf("%.4f", $blks);
            $blks = ($blks * 1024 * 1024)/512;
            $blks = ceil($blks);
        } elsif ($blks =~ m/G/i) {
            $blks =~ s/G//g;
            $blks = xCAT::zvmUtils->trimStr($blks);
            $blks = sprintf("%.4f", $blks);
            $blks = ($blks * 1024 * 1024 * 1024)/512;
            $blks = ceil($blks);
        } elsif ($blks =~ m/[a-zA-Z]/) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Size can be Megabytes (M), Gigabytes (G), or number of blocks" );
            return;
        }

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 9336 -a AUTOG -r $pool -u 2 -z $blks -m $mode -f 1 -R $readPw -W $writePw -M $multiPw"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $userId -v $addr -t 9336 -a AUTOG -r $pool -u 2 -z $blks -m $mode -f 1 -R $readPw -W $writePw -M $multiPw");
        
        # Add to active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create -T $userId -v $addr -m $mode");
        }
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # adddisk2pool [function] [region] [volume] [group]
    elsif ( $args->[0] eq "--adddisk2pool" ) {
        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor( $callback, $node, $args );
    }
    
    # addzfcp2pool [pool] [status] [wwpn] [lun] [size] [owner (optional)]
    elsif ( $args->[0] eq "--addzfcp2pool" ) {
        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor( $callback, $node, $args );
    }
    
    # addnic [address] [type] [device count]
    elsif ( $args->[0] eq "--addnic" ) {
        my $addr     = $args->[1];
        my $type     = $args->[2];
        my $devcount = $args->[3];

        # Add to active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out = `ssh $::SUDOER\@$node "/sbin/vmcp define nic $addr type $type"`;
        }
        
        # Translate QDIO or Hipersocket into correct type
        if ($type =~m/QDIO/i) {
            $type = 2;
        } elsif ($type =~m/HIPER/i) {
            $type = 1;
        } 

        # Add to directory entry
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Create_DM -T $userId -v $addr -a $type -n $devcount"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Create_DM -T $userId -v $addr -a $type -n $devcount");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # addpagespool [vol_addr] [volume_label] [volume_use] [system_config_name (optional)] [system_config_type (optional)] [parm_disk_owner (optional)] [parm_disk_number (optional)] [parm_disk_password (optional)]
    elsif ( $args->[0] eq "--addpagespool" ) {
        my $argsSize = @{$args};

        my $i;
        my @options = ("", "vol_addr=", "volume_label=", "volume_use=", "system_config_name=", "system_config_type=", "parm_disk_owner=", "parm_disk_number=", "parm_disk_password=");
        my $argStr = "";
        foreach $i ( 1 .. $argsSize ) {
            if ( $args->[$i] ) {
                $argStr .= " -k $args->[$i]"; 
            }
        }

        # Add a full volume page or spool disk to the system
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Page_or_Spool_Volume_Add -T $userId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Page_or_Spool_Volume_Add -T $userId $argStr");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # addprocessor [address]
    elsif ( $args->[0] eq "--addprocessor" ) {
        my $addr = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_CPU_Define_DM -T $userId -v $addr -b 0 -d 1 -y 0"`;
        xCAT::zvmUtils->printSyslog("smcli Image_CPU_Define_DM -T $userId -v $addr -b 0 -d 1 -y 0");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # addprocessoractive [address] [type]
    elsif ( $args->[0] eq "--addprocessoractive" ) {
        my $addr = $args->[1];
        my $type = $args->[2];

        $out = xCAT::zvmCPUtils->defineCpu( $::SUDOER, $node, $addr, $type );
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # addvdisk [device address] [size]
    elsif ( $args->[0] eq "--addvdisk" ) {
        my $addr = $args->[1];
        my $size = $args->[2];
        my $mode = $args->[3];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t FB-512 -a V-DISK -r NONE -u 2 -z $size -m $mode -f 0"`;
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # addzfcp [pool] [device address (or auto)] [loaddev (0 or 1)] [size] [tag (optional)] [wwpn (optional)] [lun (optional)]
    elsif ( $args->[0] eq "--addzfcp" ) {
        my $argsSize = @{$args};
        if ( ($argsSize != 5) && ($argsSize != 6) && ($argsSize != 8) ) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $pool = lc($args->[1]);
        my $device = $args->[2];
        my $loaddev = int($args->[3]);
        if ($loaddev != 0 && $loaddev != 1) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) The loaddev can be 0 or 1" );
            return;
        }
        my $size = $args->[4];        
        # Tag specifies what to replace in the autoyast/kickstart template, e.g. $root_device$
        # This argument is optional
        my $tag = $args->[5];
        
        # Check if WWPN and LUN are given
        # WWPN can be given as a semi-colon separated list
        my $wwpn = "";
        my $lun = "";
        my $useWwpnLun = 0;
        if ($argsSize == 8) {
            $useWwpnLun = 1;            
            $wwpn = $args->[6];
            $lun = $args->[7];
        }
                
        # Find a suitable SCSI/FCP device in the zFCP storage pool
        my %criteria;
        my $resultsRef;
        if ($useWwpnLun) {
        	%criteria = (
               'status' => 'used',
               'fcp' => $device,
               'wwpn' => $wwpn,
               'lun' => $lun,
               'size' => $size, 
               'owner' => $node, 
               'tag' => $tag
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        } else {
        	# Do not know the WWPN or LUN in this case
        	%criteria = (
               'status' => 'used',
               'fcp' => $device,
               'size' => $size, 
               'owner' => $node, 
               'tag' => $tag
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        }
        
        my %results = %$resultsRef;
        if ($results{'rc'} == -1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to add zFCP device");
            return;
        }
        
        # Obtain the device assigned by xCAT
        $device = $results{'fcp'};
        $wwpn = $results{'wwpn'};
        $lun = $results{'lun'};
        
        # Get user directory entry
        my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
        
        # Find DEDICATE statement in the entry (dedicate one if one does not exist)
        my $dedicate = `echo "$userEntry" | egrep -i "DEDICATE $device"`;
        if (!$dedicate) {
            $out = `/opt/xcat/bin/chvm $node --dedicatedevice $device $device 0`;
            xCAT::zvmUtils->printLn($callback, "$out");
            if (xCAT::zvmUtils->checkOutput($callback, $out) == -1) {
            	# Exit if dedicate failed
                return;
            }
        }
                
        # Configure native SCSI/FCP inside node (if online)
        my $cmd;
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
        	# Add the dedicated device to the active config
        	# Ignore any errors since it might be already dedicated
        	$out = `ssh $::SUDOER\@$node "$::SUDO $::DIR/smcli Image_Device_Dedicate -T $userId -v $device -r $device -R MR"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Device_Dedicate -T $userId -v $device -r $device -R MR");
           
            # Online device
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $node, "-e", "0.0." . $device);
            if (xCAT::zvmUtils->checkOutput( $callback, $out ) == -1) {
                xCAT::zvmUtils->printLn($callback, "$node: $out");
                return;
            }
            
            # Set WWPN and LUN in sysfs
            $device = lc($device);
            $wwpn = lc($wwpn);
            
            # For the version above RHEL6 or SLES11, the port_add is removed
            # Keep the code here for lower editions, of course, ignore the potential errors 
            $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo 0x$wwpn > /sys/bus/ccw/drivers/zfcp/0.0.$device/port_add");            
            $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo 0x$lun > /sys/bus/ccw/drivers/zfcp/0.0.$device/0x$wwpn/unit_add");
            
            # Get source node OS
            my $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node);
            
            # Set WWPN and LUN in configuration files
            #   RHEL: /etc/zfcp.conf
            #   SLES 10: /etc/sysconfig/hardware/hwcfg-zfcp-bus-ccw-*
            #   SLES 11: /etc/udev/rules.d/51-zfcp*
            my $tmp;
            if ( $os =~ m/sles10/i ) {
                $out = `ssh $::SUDOER\@$node "$::SUDO /sbin/zfcp_host_configure 0.0.$device 1"`;
                if ($out) {
                    xCAT::zvmUtils->printLn($callback, "$node: $out");
                }
                
                $out = `ssh $::SUDOER\@$node "$::SUDO /sbin/zfcp_disk_configure 0.0.$device $wwpn $lun 1"`;
                if ($out) {
                    xCAT::zvmUtils->printLn($callback, "$node: $out");
                }
                
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo 0x$wwpn:0x$lun >> /etc/sysconfig/hardware/hwcfg-zfcp-bus-ccw-0.0.$device");
            } elsif ( $os =~ m/sles11/i ) {
                $out = `ssh $::SUDOER\@$node "$::SUDO /sbin/zfcp_host_configure 0.0.$device 1"`;
                if ($out) {
                    xCAT::zvmUtils->printLn($callback, "$node: $out");
                }
                
                $out = `ssh $::SUDOER\@$node "$::SUDO /sbin/zfcp_disk_configure 0.0.$device $wwpn $lun 1"`;
                if ($out) {
                    xCAT::zvmUtils->printLn($callback, "$node: $out");
                }

                # Configure zFCP device to be persistent                
                $out = `ssh $::SUDOER\@$node "$::SUDO touch /etc/udev/rules.d/51-zfcp-0.0.$device.rules"`;
                
                # Check if the file already contains the zFCP channel
                $out = `ssh $::SUDOER\@$node "$::SUDO cat /etc/udev/rules.d/51-zfcp-0.0.$device.rules" | egrep -i "ccw/0.0.$device]online"`;
                if (!$out) {                
                    $tmp = "'ACTION==\"add\", SUBSYSTEM==\"ccw\", KERNEL==\"0.0.$device\", IMPORT{program}=\"collect 0.0.$device \%k 0.0.$device zfcp\"'";
                    $tmp = xCAT::zvmUtils->replaceStr($tmp, '"', '\\"');
                    $out = `ssh $::SUDOER\@$node "echo $tmp | $::SUDO tee -a /etc/udev/rules.d/51-zfcp-0.0.$device.rules"`;
                    
                    $tmp = "'ACTION==\"add\", SUBSYSTEM==\"drivers\", KERNEL==\"zfcp\", IMPORT{program}=\"collect 0.0.$device \%k 0.0.$device zfcp\"'";
                    $tmp = xCAT::zvmUtils->replaceStr($tmp, '"', '\\"');
                    $out = `ssh $::SUDOER\@$node "echo $tmp | $::SUDO tee -a /etc/udev/rules.d/51-zfcp-0.0.$device.rules"`;
                    
                    $tmp = "'ACTION==\"add\", ENV{COLLECT_0.0.$device}==\"0\", ATTR{[ccw/0.0.$device]online}=\"1\"'";
                    $tmp = xCAT::zvmUtils->replaceStr($tmp, '"', '\\"');
                    $out = `ssh $::SUDOER\@$node "echo $tmp | $::SUDO tee -a /etc/udev/rules.d/51-zfcp-0.0.$device.rules"`;
                }
                
                $tmp = "'ACTION==\"add\", KERNEL==\"rport-*\", ATTR{port_name}==\"0x$wwpn\", SUBSYSTEMS==\"ccw\", KERNELS==\"0.0.$device\", ATTR{[ccw/0.0.$device]0x$wwpn/unit_add}=\"0x$lun\"'";
                $tmp = xCAT::zvmUtils->replaceStr($tmp, '"', '\\"');
                $out = `ssh $::SUDOER\@$node "echo $tmp | $::SUDO tee -a /etc/udev/rules.d/51-zfcp-0.0.$device.rules"`;
            } elsif ( $os =~ m/rhel/i ) {
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo \"0.0.$device 0x$wwpn 0x$lun\" >> /etc/zfcp.conf");
                
                if ($os =~ m/rhel6/i) {
                    $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo add > /sys/bus/ccw/devices/0.0.$device/uevent");
                }
            }
            
            xCAT::zvmUtils->printLn($callback, "$node: Configuring FCP device to be persistent... Done");
            $out = "";
        }
        
        # Set loaddev statement in directory entry
        if ($loaddev) {
            $out = `/opt/xcat/bin/chvm $node --setloaddev $wwpn $lun`;
            xCAT::zvmUtils->printLn($callback, "$out");
            if (xCAT::zvmUtils->checkOutput( $callback, $out ) == -1) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to set LOADDEV statement in the directory entry");
                return;
            }
            $out = "";
        }
        
        xCAT::zvmUtils->printLn($callback, "$node: Adding zFCP device $device/$wwpn/$lun... Done");
    }
    
    # connectnic2guestlan [address] [lan] [owner]
    elsif ( $args->[0] eq "--connectnic2guestlan" ) {
        my $addr  = $args->[1];
        my $lan   = $args->[2];
        my $owner = $args->[3];
                
        # Connect to LAN in active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_LAN -T $userId -v $addr -l $lan -o $owner"`;
            xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_LAN -T $userId -v $addr -l $lan -o $owner");
        }
        
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_LAN_DM -T $userId -v $addr -n $lan -o $owner"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_LAN_DM -T $userId -v $addr -n $lan -o $owner");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # connectnic2vswitch [address] [vSwitch]
    elsif ( $args->[0] eq "--connectnic2vswitch" ) {
        my $addr    = $args->[1];
        my $vswitch = $args->[2];

        # Grant access to VSWITCH for Linux user
        $out = xCAT::zvmCPUtils->grantVSwitch( $callback, $::SUDOER, $hcp, $userId, $vswitch );
        xCAT::zvmUtils->printLn( $callback, "$node: Granting VSwitch ($vswitch) access for $userId... $out" );

        # Connect to VSwitch in directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_Vswitch_DM -T $userId -v $addr -n $vswitch"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_Vswitch_DM -T $userId -v $addr -n $vswitch");
        
        # Connect to VSwitch in active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_Vswitch -T $userId -v $addr -n $vswitch"`;
            xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_Vswitch -T $userId -v $addr -n $vswitch");
        }
        
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # copydisk [target address] [source node] [source address]
    elsif ( $args->[0] eq "--copydisk" ) {
        my $tgtNode   = $node;
        my $tgtUserId = $userId;
        my $tgtAddr   = $args->[1];
        my $srcNode   = $args->[2];
        my $srcAddr   = $args->[3];

        # Get source userID
        @propNames = ( 'hcp', 'userid' );
        $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $srcNode, @propNames );
        my $sourceId = $propVals->{'userid'};
        
        # Assume flashcopy is supported (via SMAPI)
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying $sourceId disk ($srcAddr) to $tgtUserId disk ($srcAddr) using FLASHCOPY" );
        if (xCAT::zvmUtils->smapi4xcat($::SUDOER, $hcp)) {
             $out = xCAT::zvmCPUtils->smapiFlashCopy($::SUDOER, $hcp, $sourceId, $srcAddr, $tgtUserId, $srcAddr);
             xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
             
             # Exit if flashcopy completed successfully
             # Otherwsie, try CP FLASHCOPY
             if ( $out =~ m/Done/i ) {
                 return;
             }
        }

        #*** Link and copy disk ***
        my $rc;
        my $try;
        my $srcDevNode;
        my $tgtDevNode;

        # Link source disk to HCP
        my $srcLinkAddr;
        $try = 5;
        while ( $try > 0 ) {
            # New disk address
            $srcLinkAddr = $srcAddr + 1000;

            # Check if new disk address is used (source)
            $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $srcLinkAddr );

            # If disk address is used (source)
            while ( $rc == 0 ) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $srcLinkAddr = $srcLinkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $srcLinkAddr );
            }

            # Link source disk
            # Because the zHCP has LNKNOPAS, no disk password is required
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking source disk ($srcAddr) as ($srcLinkAddr)" );
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $sourceId $srcAddr $srcLinkAddr RR"`;

            # If link fails
            if ( $out =~ m/not linked/i ) {

                # Wait before trying again
                sleep(5);

                $try = $try - 1;
            } else {
                last;
            }
        }    # End of while ( $try > 0 )
                
        # If source disk is not linked
        if ( $out =~ m/not linked/i ) {
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link source disk ($srcAddr)" );
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );

            # Exit
            return;
        }

        # Link target disk to HCP
        my $tgtLinkAddr;
        $try = 5;
        while ( $try > 0 ) {

            # New disk address
            $tgtLinkAddr = $tgtAddr + 2000;

            # Check if new disk address is used (target)
            $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $tgtLinkAddr );

            # If disk address is used (target)
            while ( $rc == 0 ) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $tgtLinkAddr = $tgtLinkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $tgtLinkAddr );
            }

            # Link target disk
            # Because the zHCP has LNKNOPAS, no disk password is required
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking target disk ($tgtAddr) as ($tgtLinkAddr)" );
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $tgtAddr $tgtLinkAddr MR"`;

            # If link fails
            if ( $out =~ m/not linked/i ) {

                # Wait before trying again
                sleep(5);

                $try = $try - 1;
            } else {
                last;
            }
        }    # End of while ( $try > 0 )

        # If target disk is not linked
        if ( $out =~ m/not linked/i ) {
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link target disk ($tgtAddr)" );
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );
            
            # Detatch disks from HCP
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

            # Exit
            return;
        }        

        #*** Use flashcopy ***
        # Flashcopy only supports ECKD volumes
        # Assume flashcopy is supported and use Linux DD on failure
        my $ddCopy = 0;
        
        # Check for CP flashcopy lock
        my $wait = 0;
        while ( `ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"` && $wait < 90 ) {

            # Wait until the lock dissappears
            # 90 seconds wait limit
            sleep(2);
            $wait = $wait + 2;
        }

        # If flashcopy locks still exists
        if (`ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"`) {

            # Detatch disks from HCP
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

            xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Flashcopy lock is enabled" );
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Solution) Remove lock by deleting /tmp/.flashcopy_lock on the zHCP. Use caution!" );
            return;
        } else {

            # Enable lock
            $out = `ssh $::SUDOER\@$hcp "$::SUDO touch /tmp/.flashcopy_lock"`;

            # Flashcopy source disk
            $out = xCAT::zvmCPUtils->flashCopy( $::SUDOER, $hcp, $srcLinkAddr, $tgtLinkAddr );
            $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );

                # Try using Linux DD
                $ddCopy = 1;

                # Remove lock
                $out = `ssh $::SUDOER\@$hcp "$::SUDO rm -f /tmp/.flashcopy_lock"`;
            }

            # Remove lock
            $out = `ssh $::SUDOER\@$hcp "$::SUDO rm -f /tmp/.flashcopy_lock"`;
        }
        
        # Flashcopy not supported, use Linux dd
        if ($ddCopy) {
            #*** Use Linux dd to copy ***
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: FLASHCOPY not working. Using Linux DD" );

            # Enable disks
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", $tgtLinkAddr );
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", $srcLinkAddr );

            # Determine source device node
            $srcDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $srcLinkAddr);

            # Determine target device node
            $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtLinkAddr);

            # Format target disk
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Formating target disk ($tgtDevNode)" );
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

            # Check for errors
            $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
                
                # Detatch disks from HCP
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;
                
                return;
            }

            # Sleep 2 seconds to let the system settle
            sleep(2);

            # Automatically create a partition using the entire disk
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Creating a partition using the entire disk ($tgtDevNode)" );
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdasd -a /dev/$tgtDevNode"`;
            
            # Copy source disk to target disk (4096 block size)
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcDevNode) to target disk ($tgtDevNode)" );
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=4096 oflag=sync"`;

            # Disable disks
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-d", $tgtLinkAddr );
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-d", $srcLinkAddr );

            # Check for error
            $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );

                # Detatch disks from HCP
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

                return;
            }

            # Sleep 2 seconds to let the system settle
            sleep(2);
        }

        # Detatch disks from HCP
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Detatching target disk ($tgtLinkAddr)" );
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Detatching source disk ($srcLinkAddr)" );
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

        $out = "$tgtNode: Done";
    }
    
    # createfilesysnode [source file] [target file]
    elsif ( $args->[0] eq "--createfilesysnode" ) {
        my $srcFile = $args->[1];
        my $tgtFile = $args->[2];
    
        my $argsSize = @{$args};
        if ($argsSize != 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }
        
        $out = `ssh $::SUDOER\@$node "$::SUDO /usr/bin/stat --printf=%n $tgtFile"`;
        if ($out eq $tgtFile) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) $tgtFile already exists");
            return;
        }
        
        $out = `ssh $::SUDOER\@$node "$::SUDO /usr/bin/stat --printf=%n $srcFile"`;
        if ($out ne $srcFile) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) $srcFile does not exist");
            return;
        }
    
        $out = `ssh $::SUDOER\@$node  "$::SUDO /usr/bin/stat -L --printf=%t:%T $srcFile"`;
        if ($out != '') {
            my @device = split(":", $out);
            my $major = sprintf("%d", hex($device[0]));
            my $minor = sprintf("%d", hex($device[1]));
            $out = `ssh $::SUDOER\@$node "$::SUDO /bin/mknod $tgtFile b $major $minor "`;
        }
    }
    
    # dedicatedevice [virtual device] [real device] [mode (1 or 0)]
    elsif ( $args->[0] eq "--dedicatedevice" ) {
        my $vaddr = $args->[1];
        my $raddr = $args->[2];
        my $mode  = $args->[3];
        
        # Dedicate device to directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Dedicate_DM -T $userId -v $vaddr -r $raddr -R $mode"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Device_Dedicate_DM -T $userId -v $vaddr -r $raddr -R $mode");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        
        # Dedicate device to active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Dedicate -T $userId -v $vaddr -r $raddr -R $mode"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Device_Dedicate -T $userId -v $vaddr -r $raddr -R $mode");
            xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        }
        
        $out = "";
    }

    # deleteipl
    elsif ( $args->[0] eq "--deleteipl" ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_IPL_Delete_DM -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_IPL_Delete_DM -T $userId");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # formatdisk [address] [multi password]
    elsif ( $args->[0] eq "--formatdisk" ) {
        my $tgtNode   = $node;
        my $tgtUserId = $userId;
        my $tgtAddr   = $args->[1];

        #*** Link and format disk ***
        my $rc;
        my $try;
        my $tgtDevNode;

        # Link target disk to zHCP
        my $tgtLinkAddr;
        $try = 5;
        while ( $try > 0 ) {

            # New disk address
            $tgtLinkAddr = $tgtAddr + 1000;

            # Check if new disk address is used (target)
            $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $tgtLinkAddr );

            # If disk address is used (target)
            while ( $rc == 0 ) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $tgtLinkAddr = $tgtLinkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $tgtLinkAddr );
            }

            # Link target disk
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking target disk ($tgtAddr) as ($tgtLinkAddr)" );
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $tgtAddr $tgtLinkAddr MR"`;
            
            # If link fails
            if ( $out =~ m/not linked/i || $out =~ m/DASD $tgtLinkAddr forced R\/O/i ) {
                # Detatch link because only linked as R/O
                `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;

                # Wait before trying again
                sleep(5);

                $try = $try - 1;
            } else {
                last;
            }
        }    # End of while ( $try > 0 )

        # If target disk is not linked
        if ( $out =~ m/not linked/i || $out =~ m/DASD $tgtLinkAddr forced R\/O/i ) {                
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link target disk ($tgtAddr)" );
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );
            
            # Detatch link because only linked as R/O
            `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;

            # Exit
            return;
        }

        #*** Format disk ***
        my @words;
        if ( $rc == -1 ) {

            # Enable disk
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", $tgtLinkAddr );

            # Determine target device node
            $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtLinkAddr);

            # Format target disk
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Formating target disk ($tgtDevNode)" );
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

            # Check for errors
            $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
                return;
            }
        }

        # Disable disk
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-d", $tgtLinkAddr );

        # Detatch disk from HCP
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Detatching target disk ($tgtLinkAddr)" );
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;

        $out = "$tgtNode: Done";
    }

    # grantvswitch [VSwitch]
    elsif ( $args->[0] eq "--grantvswitch" ) {
        my $vsw = $args->[1];

        $out = xCAT::zvmCPUtils->grantVSwitch( $callback, $::SUDOER, $hcp, $userId, $vsw );
        $out = xCAT::zvmUtils->appendHostname( $node, "Granting VSwitch ($vsw) access for $userId... $out" );
    }

    # disconnectnic [address]
    elsif ( $args->[0] eq "--disconnectnic" ) {
        my $addr = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Disconnect_DM -T $userId -v $addr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Disconnect_DM -T $userId -v $addr");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # punchfile [file path] [class (optional)] [remote host (optional)]
    elsif ( $args->[0] eq "--punchfile" ) {
        # Punch a file to a the node reader
        my $argsSize = @{$args};
        if (($argsSize < 2) || ($argsSize > 4)) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $filePath = $args->[1];
        my $class = "A";  # Default spool class should be A 
        my $remoteHost;
        if ($argsSize > 2) {
            $class = $args->[2];
        } if ($argsSize > 3) {
            $remoteHost = $args->[3];  # Must be specified as user@host
        }
        
        # Obtain file name
        my $fileName = basename($filePath);
        
        # Validate class
        if ($class !~ /^[a-zA-Z0-9]$/) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid spool class: $class. It should be 1-character alphanumeric" );
            return;
        }
                
        # If a remote host is specified, obtain the file from the remote host
        # The xCAT public SSH key must have been already setup if this is to work
        my $rc;
        if (defined $remoteHost) {
	        $rc = `/usr/bin/scp $remoteHost:$filePath /tmp/$fileName 2>/dev/null; echo $?`;
        } else {
        	$rc = `/bin/cp $filePath /tmp/$fileName 2>/dev/null; echo $?`;
        }
        
        if ($rc != '0') {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to copy over source file" );
            return;
        }
                
        # Set up punch device and class
        $rc = `ssh $::SUDOER\@$hcp "$::SUDO cio_ignore -r d"`;
        xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "d");        
        $rc = `ssh $::SUDOER\@$hcp "$::SUDO vmcp spool punch class $class"`;
        
        # Send over file to zHCP and punch it to the node reader
        $filePath = "/tmp/$fileName";
        xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $filePath, $filePath);
        $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $filePath, $fileName, "");
        
        # No extra steps are needed if the punch succeeded or failed, just output the results
        xCAT::zvmUtils->printLn( $callback, "$node: Punching $fileName to reader... $out" );
        
        # Remove temporary file and restore punch class
        `rm -rf $filePath`;
        `ssh $::SUDOER\@$hcp "$::SUDO rm -f /tmp/$fileName"`;
        `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp spool punch class A"`;
        $out = "";
    }
    
    # purgerdr
    elsif ( $args->[0] eq "--purgerdr" ) {
        # Purge the reader of node
        $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
        $out = xCAT::zvmUtils->appendHostname( $node, "$out" );
    }

    # removediskfrompool [function] [region] [group]
    elsif ( $args->[0] eq "--removediskfrompool" ) {
        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor( $callback, $node, $args );
    }
    
    # removezfcpfrompool [pool] [lun]
    elsif ( $args->[0] eq "--removezfcpfrompool" ) {
        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor( $callback, $node, $args );
    }
    
    # removedisk [virtual address]
    elsif ( $args->[0] eq "--removedisk" ) {
        my $addr = $args->[1];
        
        # Remove from active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $node, "-d", $addr );
            $out = `ssh $node "/sbin/vmcp det $addr"`;
        }

        # Remove from user directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Delete_DM -T $userId -v $addr -e 0"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Delete_DM -T $userId -v $addr -e 0");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # removefilesysnode [target file]
    elsif ( $args->[0] eq "--removefilesysnode" ) {
        my $tgtFile = $args->[1];
    
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Unmount this disk, but ignore the output
        $out = `ssh $::SUDOER\@$node  "$::SUDO umount $tgtFile"`;
        $out = `ssh $::SUDOER\@$node  "$::SUDO rm -f $tgtFile"`;
        
        xCAT::zvmUtils->printLn($callback, "$node: Removing file system node $tgtFile... Done");
    }
    
    # removenic [address]
    elsif ( $args->[0] eq "--removenic" ) {
        my $addr = $args->[1];
        
        # Remove from active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out = `ssh $node "/sbin/vmcp det nic $addr"`;
        }

        # Remove from user directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Delete_DM -T $userId -v $addr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Delete_DM -T $userId -v $addr");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # removeprocessor [address]
    elsif ( $args->[0] eq "--removeprocessor" ) {
        my $addr = $args->[1];
        
        # Remove from user directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_CPU_Delete_DM -T $userId -v $addr"`;
        xCAT::zvmUtils->printSyslog("smcli Image_CPU_Delete_DM -T $userId -v $addr");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # removeloaddev [wwpn] [lun]
    elsif ( $args->[0] eq "--removeloaddev" ) {
        my $wwpn = $args->[1];
        my $lun = $args->[2];
        
        xCAT::zvmUtils->printLn($callback, "$node: Removing LOADDEV directory statements");
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr( $wwpn, "0x", "" );
        $lun = xCAT::zvmUtils->replaceStr( $lun, "0x", "" );
        
        # Get user directory entry
        my $updateEntry = 0;
        my $userEntryFile = "/tmp/$node.txt";
        my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $userId | sed '\$d'");
        chomp($userEntry);
        if (!$wwpn && !$lun) {
            # If no WWPN or LUN is provided, delete all LOADDEV statements
            `echo "$userEntry" | grep -v "LOADDEV" > $userEntryFile`;
            $updateEntry = 1;
        } else {
            
            # Delete old directory entry file
            `rm -rf $userEntryFile`;
            
            # Remove LOADDEV PORTNAME and LUN statements in directory entry            
            my @lines = split( '\n', $userEntry );
            foreach (@lines) {
                # Check if LOADDEV PORTNAME and LUN statements are in the directory entry
                if ($_ =~ m/LOADDEV PORTNAME $wwpn/i) {
                    $updateEntry = 1;
                    next;
                } elsif ($_ =~ m/LOADDEV LUN $lun/i) {
                    $updateEntry = 1;
                    next;
                } else {
                    # Write directory entry to file            
                    `echo "$_" >> $userEntryFile`;
                }
            }
        }
        
        # Replace user directory entry (if necessary)
        if ($updateEntry) {
            $out = `/opt/xcat/bin/chvm $node --replacevs $userEntryFile`;
            xCAT::zvmUtils->printLn($callback, "$out");
            
            # Delete directory entry file
            `rm -rf $userEntryFile`;
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: No changes required in the directory entry");
        }
        
        $out = "";
    }
    
    # removezfcp [device address] [wwpn] [lun] [persist (0 or 1)]
    elsif ( $args->[0] eq "--removezfcp" ) {
        my $device = $args->[1];
        my $wwpn = $args->[2];
        my $lun = $args->[3];
        my $persist = "0";  # Optional
        
        # Delete 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
                
        my $argsSize = @{$args};
        if ($argsSize != 4 && $argsSize != 5) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }
        
        if ($argsSize == 5) {
        	$persist = $args->[4];
        }
        
        # Check the value of persist
        if ($persist !~ /^[01]$/) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Persist can only be 0 or 1");
            return;
        }
        $persist = int($persist);
        
        # Find the pool that contains the SCSI/FCP device
        my $pool = xCAT::zvmUtils->findzFcpDevicePool($::SUDOER, $hcp, $wwpn, $lun);
        if (!$pool) {
        	# Continue to try and remove the SCSI/FCP device even when it is not found in a storage pool 
        	xCAT::zvmUtils->printLn( $callback, "$node: Could not find FCP device in any FCP storage pool" );
        } else {
        	xCAT::zvmUtils->printLn( $callback, "$node: Found FCP device in $pool" );
        	
        	# If the device is not known, try to find it in the storage pool
	        if ($device !~ /^[0-9a-f]/i) {
	            my $select = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf" | grep -i "$wwpn,$lun"`;
	            chomp($select);
	            my @info = split(',', $select);
	            if ($device) {
	                $device = $info[6];
	            }
	        }
	        
	        my $status = "free";
	        my $owner = "";
	        if ($persist) {
	            # Keep the device reserved if persist = 1
	            $status = "reserved";
	            $owner = $node;
	        }
	        
	        my %criteria = (
	           'status' => $status,
	           'wwpn' => $wwpn,
	           'lun' => $lun,
	           'owner' => $owner,
	        );
	        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
	        my %results = %$resultsRef;
	        
	        if ($results{'rc'} == -1) {
	            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find zFCP device");
	            return;
	        }
	        
	        # Obtain the device assigned by xCAT
	        $wwpn = $results{'wwpn'};
	        $lun = $results{'lun'};
        }

        # De-configure SCSI over FCP inside node (if online)
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            # Delete WWPN and LUN from sysfs
            $device = lc($device);
            $wwpn = lc($wwpn);
            
            # unit_remove does not exist on SLES 10!
            $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo 0x$lun > /sys/bus/ccw/drivers/zfcp/0.0.$device/0x$wwpn/unit_remove");
            
            # Get source node OS
            my $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node);
            
            # Delete WWPN and LUN from configuration files
            #   RHEL: /etc/zfcp.conf
            #   SLES 10: /etc/sysconfig/hardware/hwcfg-zfcp-bus-ccw-*
            #   SLES 11: /etc/udev/rules.d/51-zfcp*
            my $expression = "";
            if ( $os =~ m/sles10/i ) {
                $expression = "/$lun/d";
                $out = `ssh $::SUDOER\@$node "$::SUDO sed -i -e $expression /etc/sysconfig/hardware/hwcfg-zfcp-bus-ccw-0.0.$device"`;
            } elsif ( $os =~ m/sles11/i ) {
                $expression = "/$lun/d";
                $out = `ssh $::SUDOER\@$node "$::SUDO sed -i -e $expression /etc/udev/rules.d/51-zfcp-0.0.$device.rules"`;
            } elsif ( $os =~ m/rhel/i ) {
                $expression = "/$lun/d";
                $out = `ssh $::SUDOER\@$node "$::SUDO sed -i -e $expression /etc/zfcp.conf"`;
            }
            
            xCAT::zvmUtils->printLn($callback, "$node: De-configuring FCP device on host... Done");
        }
        
        $out = "";
    }

    # replacevs [file]
    elsif ( $args->[0] eq "--replacevs" ) {
        my $argsSize = @{$args};
        my $file;
        if ($argsSize == 2) {
            $file = $args->[1];
        }
        
        if ($file) {
            if (-e $file) {
                # Target system (zHCP), e.g. root@gpok2.endicott.ibm.com
                my $target = "$::SUDOER@";
                $target .= $hcp;
        
                # SCP file over to zHCP
                $out = `scp $file $target:$file`;
                
                # Lock image
                `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Lock_DM -T $userId"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Lock_DM -T $userId");
                
                # Replace user directory entry
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Replace_DM -T $userId -f $file"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Replace_DM -T $userId -f $file");
                
                # Unlock image
                `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Unlock_DM -T $userId"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Unlock_DM -T $userId");
                
                # Delete file on zHCP
                `ssh $::SUDOER\@$hcp "rm -rf $file"`;
            } else {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) File does not exist" );
                return;
            }
        } elsif ($::STDIN) {
            # Create a temporary file to contain directory on zHCP
            $file = "/tmp/" . $node . ".direct";
            my @lines = split("\n", $::STDIN);
            
            # Delete existing file on zHCP (if any)
            `ssh $::SUDOER\@$hcp "rm -rf $file"`;
            
            # Write directory entry into temporary file
            # because directory entry cannot be remotely echoed into stdin          
            foreach (@lines) {
                if ($_) {
                    $_ = "'" . $_ . "'";
                    `ssh $::SUDOER\@$hcp "echo $_ >> $file"`;
                }
            }
            
            # Lock image
            `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Lock_DM -T $userId"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Lock_DM -T $userId");
            
            # Replace user directory entry
            $out = `ssh $::SUDOER\@$hcp "cat $file | $::SUDO $::DIR/smcli Image_Replace_DM -T $userId -s"`;
            xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp cat $file | $::SUDO $::DIR/smcli Image_Replace_DM -T $userId -s");
            
            # Unlock image
            `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Unlock_DM -T $userId"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Unlock_DM -T $userId");
            
            # Delete created file on zHCP
            `ssh $::SUDOER\@$hcp "rm -rf $file"`;
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) No directory entry file specified" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Specify a text file containing the updated directory entry" );
            return;
        }
        
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # resetsmapi
    elsif ( $args->[0] eq "--resetsmapi" ) {
        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor( $callback, $node, $args );
    }
    
    # setipl [ipl target] [load parms] [parms]
    elsif ( $args->[0] eq "--setipl" ) {
        my $trgt = $args->[1];
        
        my $loadparms = "''";
        if ($args->[2]) {
            $loadparms = $args->[2];
        }
        
        my $parms = "''";
        if ($args->[3]) {
            $parms = $args->[3];
        }

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_IPL_Set_DM -T $userId -s $trgt -l $loadparms -p $parms"`;
        xCAT::zvmUtils->printSyslog("smcli Image_IPL_Set_DM -T $userId -s $trgt -l $loadparms -p $parms");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }

    # setpassword [password]
    elsif ( $args->[0] eq "--setpassword" ) {
        my $pw = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Password_Set_DM -T $userId -p $pw"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Password_Set_DM -T $userId -p $pw");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # setloaddev [wwpn] [lun]
    elsif ( $args->[0] eq "--setloaddev" ) {
        my $wwpn = $args->[1];
        my $lun = $args->[2];
        
        if (!$wwpn || !$lun) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr( $wwpn, "0x", "" );
        $lun = xCAT::zvmUtils->replaceStr( $lun, "0x", "" );
            
        xCAT::zvmUtils->printLn($callback, "$node: Setting LOADDEV directory statements");
                
        # Get user directory entry
        my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $userId | sed '\$d'");
        
        # Delete old directory entry file
        my $userEntryFile = "/tmp/$node.txt";
        `rm -rf $userEntryFile`;
        
        # Append LOADDEV PORTNAME and LUN statements in directory entry
        # These statements go before DEDICATE statements
        my $containsPortname = 0;
        my $containsLun = 0;
        my $updateEntry = 0;
        my @lines = split( '\n', $userEntry );
        foreach (@lines) {
            # Check if LOADDEV PORTNAME and LUN statements are in the directory entry
            # This should be hit before any DEDICATE statements
            if ($_ =~ m/LOADDEV PORTNAME $wwpn/i) {
                $containsPortname = 1;
            } if ($_ =~ m/LOADDEV LUN $lun/i) {
                $containsLun = 1;
            }
            
            if ($_ =~ m/DEDICATE/i) {
                # Append LOADDEV PORTNAME statement
                if (!$containsPortname) {
                    `echo "LOADDEV PORTNAME $wwpn" >> $userEntryFile`;
                    $containsPortname = 1;
                    $updateEntry = 1;
                }
                    
                # Append LOADDEV LUN statement
                if (!$containsLun) {
                    `echo "LOADDEV LUN $lun" >> $userEntryFile`;
                    $containsLun = 1;
                    $updateEntry = 1;
                }
            }
            
            # Write directory entry to file
            `echo "$_" >> $userEntryFile`;
        }
        
        # Replace user directory entry (if necessary)
        if ($updateEntry) {
            $out = `/opt/xcat/bin/chvm $node --replacevs $userEntryFile`;
            xCAT::zvmUtils->printLn( $callback, "$out");
            
            # Delete directory entry file
            `rm -rf $userEntryFile`;
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: No changes required in the directory entry");
        }
        
        $out = "";
    }
    
    # undedicatedevice [virtual device]
    elsif ( $args->[0] eq "--undedicatedevice" ) {
        my $vaddr = $args->[1];

        # Undedicate device in directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Undedicate_DM -T $userId -v $vaddr"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Device_Undedicate_DM -T $userId -v $vaddr");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        
        # Undedicate device in active configuration
        my $ping = `/opt/xcat/bin/pping $node`;
        if (!($ping =~ m/noping/i)) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Undedicate -T $userId -v $vaddr"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Device_Undedicate -T $userId -v $vaddr");
            xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        }
        
        $out = "";
    }
    
    # sharevolume [vol_addr] [share_enable (YES or NO)]
    elsif ( $args->[0] eq "--sharevolume" ) {
        my $volAddr = $args->[1];
        my $share = $args->[2];

        # Add disk to running system
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Share -T $userId -k img_vol_addr=$volAddr -k share_enable=$share"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Volume_Share -T $userId -k img_vol_addr=$volAddr -k share_enable=$share");
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
    }
    
    # setprocessor [count]
    elsif($args->[0] eq "--setprocessor") {
        my $cpuCount = $args->[1];
        my @allCpu;
        my $count = 0;
        my $newAddr;
        my $cpu;
        my @allValidAddr = ('00','01','02','03','04','05','06','07','09','09','0A','0B','0C','0D','0E','0F',
                            '10','11','12','13','14','15','16','17','19','19','1A','1B','1C','1D','1E','1F',
                            '20','21','22','23','24','25','26','27','29','29','2A','2B','2C','2D','2E','2F',
                            '30','31','32','33','34','35','36','37','39','39','3A','3B','3C','3D','3E','3F');
                       
        # Get current CPU count and address
        my $proc = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $userId -k CPU" | grep CPU=`;
        xCAT::zvmUtils->printSyslog("smcli Image_Definition_Query_DM -T $userId -k CPU | grep CPU=");
        while ( index( $proc, "CPUADDR" ) != -1) {
            my $position = index($proc, "CPUADDR");
            my $address = substr($proc, $position + 8, 2);
            push( @allCpu, $address );
            $proc = substr( $proc, $position + 10 );
        }
        
        # Find free valid CPU address
        my %allCpu = map { $_=>1 } @allCpu;
        my @addrLeft = grep ( !defined $allCpu{$_}, @allValidAddr );
        
        # Add new CPUs
        if ( $cpuCount > @allCpu ) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k CPU_MAXIMUM=COUNT=$cpuCount -k TYPE=ESA"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k CPU_MAXIMUM=COUNT=$cpuCount -k TYPE=ESA");
            while ( $count < $cpuCount - @allCpu ) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k CPU=CPUADDR=$addrLeft[$count]"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k CPU=CPUADDR=$addrLeft[$count]");
                $count++;
            }
        # Remove CPUs
        } else { 
            while ( $count <= @allCpu - $cpuCount ) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_CPU_Delete_DM -T $userId -v $allCpu[@allCpu-$count]"`;
                xCAT::zvmUtils->printSyslog("smcli Image_CPU_Delete_DM -T $userId -v $allCpu[@allCpu-$count]");
                $count++;
            }
        }       
                
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        $out = "";
    }
    
    # setmemory [size]
    elsif ($args->[0] eq "--setmemory") {
        # Memory hotplug not supported, just change memory size in user directory
        my $size = $args->[1];
        
        if (!($size =~ m/G/i || $size =~ m/M/i)) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Size can be Megabytes (M) or Gigabytes (G)" );
            return;
        }
        
        # Set initial memory to 1M first, make this function able to increase/descrease the storage
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=1M"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=1M");
        
        # Set both initial memory and maximum memory to be the same
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=$size -k STORAGE_MAXIMUM=$size"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=$size -k STORAGE_MAXIMUM=$size");
        
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        $out = "";
    }
    
    # Otherwise, print out error
    else {
        $out = "$node: (Error) Option not supported";
    }

    # Only print if there is content
    if ($out) {
        xCAT::zvmUtils->printLn( $callback, "$out" );
    }
    return;
}

#-------------------------------------------------------

=head3   powerVM

    Description  : Power on or off a given node
    Arguments    :   Node
                     Option [on|off|reboot|reset|stat]
    Returns      : Nothing
    Example      : powerVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub powerVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Output string
    my $out;

    # Power on virtual server
    if ( $args->[0] eq 'on' ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $userId");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }

    # Power off virtual server
    elsif ( $args->[0] eq 'off' ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId -f IMMED"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }
    
    # Power off virtual server (gracefully)
    elsif ( $args->[0] eq 'softoff' ) {
        if (`/opt/xcat/bin/pping $node` !~ m/noping/i) {
            $out = `ssh -o ConnectTimeout=10 $::SUDOER\@$node "shutdown -h now"`;
            sleep(15);    # Wait 15 seconds before logging user off
        }
        
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }

    # Get the status (on|off)
    elsif ( $args->[0] eq 'stat' ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/off/' | sed 's/$userId.*/on/'`;
        
        # Wait for output
        my $max = 0;
        while ( !$out && $max < 10 ) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/off/' | sed 's/$userId.*/on/'`;
            $max++;
        }

        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }

    # Reset a virtual server
    elsif ( $args->[0] eq 'reset' ) {

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );

        # Wait for output
        while ( `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/Done/'` != "Done" ) {
            # Do nothing
        }

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $userId");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }
    
    # Reboot a virtual server
    elsif ( $args->[0] eq 'reboot' ) {
        my $timeout = 0;
        $out = `ssh -o ConnectTimeout=10 $::SUDOER\@$node "shutdown -r now &>/dev/null && echo Done"`;
        if (!($out =~ m/Done/)) {
            xCAT::zvmUtils->printLn( $callback, "$node: Connecting to $node... Failed\n" );
            return;
        }
              
        # Wait until node is down or 180 seconds
        while ((`/opt/xcat/bin/pping $node` !~ m/noping/i) && $timeout < 180) {
            sleep(1);
            $timeout++;
        }
        if ($timeout >= 180) {
            xCAT::zvmUtils->printLn( $callback, "$node: Shuting down $userId... Failed\n" );
            return;
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Shuting down $userId... Done\n" );
        
        # Wait until node is up or 180 seconds
        $timeout = 0;
        while ((`/opt/xcat/bin/pping $node` =~ m/noping/i) && $timeout < 180) {
            sleep(1);
            $timeout++;
        }        
        if ($timeout >= 180) {
            xCAT::zvmUtils->printLn( $callback, "$node: Rebooting $userId... Failed\n" );
            return;
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Rebooting $userId... Done\n" );
    }
    
    # Pause a virtual server
    elsif ( $args->[0] eq 'pause' ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Pause -T $userId -k PAUSE=YES"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Pause -T $userId -k PAUSE=YES");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }
    
    # Unpause a virtual server
    elsif ( $args->[0] eq 'unpause' ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Pause -T $userId -k PAUSE=NO"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Pause -T $userId -k PAUSE=NO");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }

    else {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Option not supported" );
    }
    return;
}

#-------------------------------------------------------

=head3   scanVM

    Description : Get node information from zHCP
    Arguments   : zHCP
    Returns     : Nothing
    Example     : scanVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub scanVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;
    my $write2db = '';
    if ($args) {
        @ARGV = @$args;
        
        # Parse options
        GetOptions( 'w' => \$write2db );
    }
    
    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Exit if node is not a HCP
    if ( !( $hcp =~ m/$node/i ) ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) $node is not a hardware control point" );
        return;
    }

    # Print output string
    # [Node name]:
    #   objtype=node
    #   id=[userID]
    #   arch=[Architecture]
    #   hcp=[HCP node name]
    #   groups=[Group]
    #   mgt=zvm
    #
    # gpok123:
    #   objtype=node
    #   id=LINUX123
    #   arch=s390x
    #   hcp=gpok456.endicott.ibm.com
    #   groups=all
    #   mgt=zvm

    # Output string
    my $str = "";

    # Get nodes managed by this zHCP
    # Look in 'zvm' table
    my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );
    my @entries = $tab->getAllAttribsWhere( "hcp like '%" . $hcp . "%'", 'node', 'userid' );

    my $out;
    my $node;
    my $id;
    my $os;
    my $arch;
    my $groups;
    
    # Get node hierarchy from /proc/sysinfo
    my $hierarchy;
    my $host = xCAT::zvmCPUtils->getHost($::SUDOER, $hcp);
    my $sysinfo = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO cat /proc/sysinfo"`;

    # Get node CEC
    my $cec = `echo "$sysinfo" | grep "Sequence Code"`;
    my @args = split( ':', $cec );
    # Remove leading spaces and zeros
    $args[1] =~ s/^\s*0*//;
    $cec = xCAT::zvmUtils->trimStr($args[1]);
    
    # Get node LPAR
    my $lpar = `echo "$sysinfo" | grep "LPAR Name"`;
    @args = split( ':', $lpar );
    $lpar = xCAT::zvmUtils->trimStr($args[1]);
    
    # Save CEC, LPAR, and zVM to 'zvm' table
    my %propHash;
    if ($write2db) {
        # Save CEC to 'zvm' table
        %propHash = (
            'nodetype'  =>     'cec',
            'parent'    =>     ''
        );
        xCAT::zvmUtils->setNodeProps( 'zvm', $cec, \%propHash );
    
        # Save LPAR to 'zvm' table
        %propHash = (
            'nodetype'  =>     'lpar',
            'parent'    =>     $cec
        );
        xCAT::zvmUtils->setNodeProps( 'zvm', $lpar, \%propHash );
        
        # Save zVM to 'zvm' table
        %propHash = (
            'nodetype'  =>     'zvm',
            'parent'    =>     $lpar
        );
        xCAT::zvmUtils->setNodeProps( 'zvm', lc($host), \%propHash );
    }
        
    # Search for nodes managed by given zHCP
    # Get 'node' and 'userid' properties
    %propHash = ();
    foreach (@entries) {
        $node = $_->{'node'};

        # Get groups
        @propNames = ('groups');
        $propVals  = xCAT::zvmUtils->getNodeProps( 'nodelist', $node, @propNames );
        $groups    = $propVals->{'groups'};

        # Load VMCP module
        xCAT::zvmCPUtils->loadVmcp($::SUDOER, $node);

        # Get user ID
        @propNames = ('userid');
        $propVals  = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
        $id = $propVals->{'userid'};
        if (!$id) {
            $id = xCAT::zvmCPUtils->getUserId($::SUDOER, $node);
        }

        # Get architecture
        $arch = `ssh -o ConnectTimeout=2 $::SUDOER\@$node "uname -p"`;
        $arch = xCAT::zvmUtils->trimStr($arch);
        if (!$arch) {
            # Assume arch is s390x
            $arch = 's390x';
        }
        
        # Get OS
        $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node);
        
        # Save node attributes
        if ($write2db) {
            
            # Do not save if node = host
            if (!(lc($host) eq lc($node))) {                
                # Save to 'zvm' table
                %propHash = (
                    'hcp'       => $hcp,
                    'userid'    => $id,
                    'nodetype'  => 'vm',
                    'parent'    => lc($host)
                );                        
                xCAT::zvmUtils->setNodeProps( 'zvm', $node, \%propHash );
                
                # Save to 'nodetype' table
                %propHash = (
                    'arch'  => $arch,
                    'os'    => $os
                );                        
                xCAT::zvmUtils->setNodeProps( 'nodetype', $node, \%propHash );
            }
        }
        
        # Create output string
        $str .= "$node:\n";
        $str .= "  objtype=node\n";
        $str .= "  arch=$arch\n";
        $str .= "  os=$os\n";
        $str .= "  hcp=$hcp\n";
        $str .= "  userid=$id\n";
        $str .= "  nodetype=vm\n";
        $str .= "  parent=$host\n";
        $str .= "  groups=$groups\n";
        $str .= "  mgt=zvm\n\n";
    }

    xCAT::zvmUtils->printLn( $callback, "$str" );
    return;
}

#-------------------------------------------------------

=head3   inventoryVM

    Description : Get hardware and software inventory of a given node
    Arguments   :   Node
                    Type of inventory (config|all)
    Returns     : Nothing
    Example     : inventoryVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub inventoryVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;
    
    # Output string
    my $str = "";
    
    # Check if node is pingable
    if (`/opt/xcat/bin/pping $node | egrep -i "noping"`) {
        $str = "$node: (Error) Host is unreachable";
        xCAT::zvmUtils->printLn( $callback, "$str" );
        return;
    }

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;   
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Load VMCP module
    xCAT::zvmCPUtils->loadVmcp($::SUDOER, $node);

    # Get configuration
    if ( $args->[0] eq 'config' ) {

        # Get z/VM host for specified node
        my $host = xCAT::zvmCPUtils->getHost($::SUDOER, $node);

        # Get architecture
        my $arch = xCAT::zvmUtils->getArch($::SUDOER, $node);

        # Get operating system
        my $os = xCAT::zvmUtils->getOs($::SUDOER, $node);

        # Get privileges
        my $priv = xCAT::zvmCPUtils->getPrivileges($::SUDOER, $node);

        # Get memory configuration
        my $memory = xCAT::zvmCPUtils->getMemory($::SUDOER, $node);
        
        # Get max memory
        my $maxMem = xCAT::zvmUtils->getMaxMemory($::SUDOER, $hcp , $node);

        # Get processors configuration
        my $proc = xCAT::zvmCPUtils->getCpu($::SUDOER, $node);

        $str .= "z/VM UserID: $userId\n";
        $str .= "z/VM Host: $host\n";
        $str .= "Operating System: $os\n";
        $str .= "Architecture: $arch\n";
        $str .= "HCP: $hcp\n";
        $str .= "Privileges: \n$priv\n";
        $str .= "Total Memory: $memory\n";
        $str .= "Max Memory: $maxMem\n";
        $str .= "Processors: \n$proc\n";
    } elsif ( $args->[0] eq 'all' ) {

        # Get z/VM host for specified node
        my $host = xCAT::zvmCPUtils->getHost($::SUDOER, $node);

        # Get architecture
        my $arch = xCAT::zvmUtils->getArch($::SUDOER, $node);

        # Get operating system
        my $os = xCAT::zvmUtils->getOs($::SUDOER, $node);

        # Get privileges
        my $priv = xCAT::zvmCPUtils->getPrivileges($::SUDOER, $node);

        # Get memory configuration
        my $memory = xCAT::zvmCPUtils->getMemory($::SUDOER, $node);

         # Get max memory
        my $maxMem = xCAT::zvmUtils->getMaxMemory($::SUDOER, $hcp , $node);

        # Get processors configuration
        my $proc = xCAT::zvmCPUtils->getCpu($::SUDOER, $node);

        # Get disks configuration
        my $storage = xCAT::zvmCPUtils->getDisks($::SUDOER, $node);

        # Get NICs configuration
        my $nic = xCAT::zvmCPUtils->getNic($::SUDOER, $node);
        
        # Get zFCP device info
        my $zfcp = xCAT::zvmUtils->getZfcpInfo($::SUDOER, $node);
        
        # Get OS system up time
        my $uptime = xCAT::zvmUtils->getUpTime($::SUDOER, $node);
        
        # Get instance CPU used time
        my $cputime = xCAT::zvmUtils->getUsedCpuTime($::SUDOER, $hcp , $node); 

        # Create output string
        $str .= "z/VM UserID: $userId\n";
        $str .= "z/VM Host: $host\n";
        $str .= "Operating System: $os\n";
        $str .= "Architecture: $arch\n";
        $str .= "HCP: $hcp\n";
        $str .= "Uptime: $uptime\n";
        $str .= "CPU Used Time: $cputime\n";
        $str .= "Privileges: \n$priv\n";
        $str .= "Total Memory: $memory\n";
        $str .= "Max Memory: $maxMem\n";
        $str .= "Processors: \n$proc\n";
        $str .= "Disks: \n$storage\n";
        if ($zfcp) {
            $str .= "zFCP: \n$zfcp\n";
        }
        $str .= "NICs: \n$nic\n";
    } elsif ( $args->[0] eq '--freerepospace' ) {
    
        # Get /install available disk size
        my $freespace = xCAT::zvmUtils->getFreeRepoSpace($::SUDOER, $node);

        # Create output string
        if ($freespace) {
            $str .= "Free Image Repository: $freespace\n";
        } else {
            return;
        }
    } else {
        $str = "$node: (Error) Option not supported";
        xCAT::zvmUtils->printLn( $callback, "$str" );
        return;
    }

    # Append hostname (e.g. gpok3) in front
    $str = xCAT::zvmUtils->appendHostname( $node, $str );

    xCAT::zvmUtils->printLn( $callback, "$str" );
    return;
}

#-------------------------------------------------------

=head3   listVM

    Description : Show the info for a given node
    Arguments   : Node
                  Option        
    Returns     : Nothing
    Example     : listVM($callback, $node);
    
=cut

#-------------------------------------------------------
sub listVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Set cache directory
    my $cache = '/var/opt/zhcp/cache';

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    my $out;

    # Get disk pool configuration
    if ( $args->[0] eq "--diskpool" ) {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }
    
    # Get disk pool names
    elsif ( $args->[0] eq "--diskpoolnames" ) {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }
    
    # Get network names
    elsif ( $args->[0] eq "--getnetworknames" ) {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }

    # Get network
    elsif ( $args->[0] eq "--getnetwork" ) {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }
    
    # Get the status of all DASDs accessible to a virtual image
    elsif ( $args->[0] eq "--querydisk" ) {
        my $vdasd = $args->[1];
        
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Query -T $userId -k $vdasd"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Query -T $userId -k $vdasd");
    }
    
    # Get user profile names
    elsif ( $args->[0] eq "--userprofilenames" ) {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }

    # Get zFCP disk pool configuration
    elsif ( $args->[0] eq "--zfcppool" ) {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }
    
    # Get zFCP disk pool names
    elsif ( $args->[0] eq "--zfcppoolnames") {
        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor( $callback, $node, $args );
    }
    
    # Get user entry
    elsif ( !$args->[0] ) {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $userId | sed '\$d'");
    } else {
        $out = "$node: (Error) Option not supported";
    }

    # Append hostname (e.g. gpok3) in front
    $out = xCAT::zvmUtils->appendHostname( $node, $out );
    xCAT::zvmUtils->printLn( $callback, "$out" );

    return;
}

#-------------------------------------------------------

=head3   makeVM

    Description : Create a virtual machine
                   * A unique MAC address will be assigned
    Arguments   :  Node
                   Directory entry text file (optional)
    Returns     : Nothing
    Example     : makeVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub makeVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }
    
    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Find the number of arguments
    my $argsSize = @{$args};
    
    # Create a new user in zVM without user directory entry file
    my $out;
    my $stdin;
    my $password = "";
    my $memorySize = "";
    my $privilege = "";
    my $profileName = ""; 
    my $cpuCount = 1;
    my $diskPool = "";
    my $diskSize = "";
    my $diskVdev = "";
    if ($args) {
        @ARGV = @$args;
        
        # Parse options
        GetOptions(
            's|stdin' => \$stdin,  # Directory entry contained in stdin
            'p|profile=s' => \$profileName,
            'w|password=s' => \$password, 
            'c|cpus=i' => \$cpuCount,  # Optional
            'm|mem=s' => \$memorySize, 
            'd|diskpool=s' => \$diskPool, 
            'z|size=s' => \$diskSize, 
            'v|diskvdev=s' => \$diskVdev,  # Optional
            'r|privilege=s' => \$privilege);  # Optional
    }

    # If one of the options above are given, create the user without a directory entry file
    if ($profileName || $password || $memorySize) {        
        if (!$profileName || !$password || !$memorySize) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing one or more required parameter(s)" );
            return;
        }
        
        # Default privilege to G if none is given
        if (!$privilege) {
            $privilege = 'G';
        }

        # Generate temporary user directory entry file
        my $userEntryFile = xCAT::zvmUtils->generateUserEntryFile($userId, $password, $memorySize, $privilege, $profileName, $cpuCount);        
        if ( $userEntryFile == -1 ) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to generate user directory entry file" );
            return;
        }
                
        # Create a new user in z/VM without disks
        $out = `/opt/xcat/bin/mkvm $node $userEntryFile`;
        xCAT::zvmUtils->printLn( $callback, "$out");
        if (xCAT::zvmUtils->checkOutput($callback, $out) == -1) {
            # The error would have already been printed under mkvm
            return;
        }
        
        # If one of the disk operations are given, add disk(s) to this new user
        if ($diskPool || $diskSize) {
            if (!$diskPool || !$diskSize) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing one or more required parameter(s) for adding disk" );
                return;
            }
            
            # Default disk virtual device to 0100 if none is given
            if (!$diskVdev) {
                $diskVdev = "0100";
            }
            
            $out = `/opt/xcat/bin/chvm $node --add3390 $diskPool $diskVdev $diskSize`;
            xCAT::zvmUtils->printLn( $callback, "$out");
            if (xCAT::zvmUtils->checkOutput($callback, $out) == -1) {
                # The error would have already been printed under chvm
                return;
            }
        }
        
        # Remove the temporary file
        $out = `rm -f $userEntryFile`;
        return;
    }
    
    # Get user entry file (if any)
    my $userEntry;
    if (!$stdin) {
        $userEntry = $args->[0];
    }

    # Get MAC address in 'mac' table
    my $macId;
    my $generateNew = 1;
    @propNames = ('mac');
    $propVals = xCAT::zvmUtils->getNodeProps( 'mac', $node, @propNames );
        
    # If MAC address exists
    my @lines;
    my @words;
    if ( $propVals->{'mac'} ) {

        # Get MAC suffix (MACID)
        $macId = $propVals->{'mac'};
        $macId = xCAT::zvmUtils->replaceStr( $macId, ":", "" );
        $macId = substr( $macId, 6 );
    } else {
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;
        
        # Get USER Prefix
        my $prefix = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q vmlan" | egrep -i "USER Prefix:"`;
        $prefix =~ s/(.*?)USER Prefix:(.*)/$2/;
        $prefix =~ s/^\s+//;
        $prefix =~ s/\s+$//;
                        
        # Get MACADDR Prefix instead if USER Prefix is not defined
        if (!$prefix) {
            $prefix = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q vmlan" | egrep -i "MACADDR Prefix:"`;
            $prefix =~ s/(.*?)MACADDR Prefix:(.*)/$2/;
            $prefix =~ s/^\s+//;
            $prefix =~ s/\s+$//;
        
            if (!$prefix) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Could not find the MACADDR/USER prefix of the z/VM system" );
                xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Verify that the node's zHCP($hcp) is correct, the node is online, and the SSH keys are setup for the zHCP" );
                return;
            }
        }
        
        # Generate MAC address
        my $mac;
        while ($generateNew) {
                    
            # If no MACID is found, get one
            $macId = xCAT::zvmUtils->getMacID($::SUDOER, $hcp);
            if ( !$macId ) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Could not generate MACID" );
                return;
            }

            # Create MAC address
            $mac = $prefix . $macId;
                        
            # If length is less than 12, append a zero
            if ( length($mac) != 12 ) {
                $mac = "0" . $mac;
            }
        
            # Format MAC address
            $mac =
                substr( $mac, 0, 2 ) . ":"
              . substr( $mac, 2,  2 ) . ":"
              . substr( $mac, 4,  2 ) . ":"
              . substr( $mac, 6,  2 ) . ":"
              . substr( $mac, 8,  2 ) . ":"
              . substr( $mac, 10, 2 );
                    
            # Check 'mac' table for MAC address
            my $tab = xCAT::Table->new( 'mac', -create => 1, -autocommit => 0 );
            my @entries = $tab->getAllAttribsWhere( "mac = '" . $mac . "'", 'node' );
                    
            # If MAC address exists
            if (@entries) {
                # Generate new MACID
                $out = xCAT::zvmUtils->generateMacId($::SUDOER, $hcp);
                $generateNew = 1;
            } else {
                $generateNew = 0;
                        
                # Save MAC address in 'mac' table
                xCAT::zvmUtils->setNodeProp( 'mac', $node, 'mac', $mac );
                    
                # Generate new MACID
                $out = xCAT::zvmUtils->generateMacId($::SUDOER, $hcp);
            }
        } # End of while ($generateNew)
    }

    # Create virtual server
    my $line;
    my @hcpNets;
    my $netName = '';
    my $oldNicDef;
    my $nicDef;
    my $id;
    my $rc;
    my @vswId;
    my $target = "$::SUDOER\@$hcp";
    if ($userEntry) {        
        # Copy user entry
        $out = `cp $userEntry /tmp/$node.txt`;
        $userEntry = "/tmp/$node.txt";

        # If the directory entry contains a NICDEF statement, append MACID to the end
        # User must select the right one (layer) based on template chosen        
        $out = `cat $userEntry | egrep -i "NICDEF"`;
        if ($out) {

            # Get the networks used by the zHCP
            @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $hcp);
            
            # Search user entry for network name            
            foreach (@hcpNets) {
                if ( $out =~ m/ $_/i ) {
                    $netName = $_;
                    last;
                }
            }
            
            # Find NICDEF statement
            $oldNicDef = `cat $userEntry | egrep -i "NICDEF" | egrep -i "$netName"`;
            if ($oldNicDef) {
                $oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
                $nicDef = xCAT::zvmUtils->replaceStr($oldNicDef, $netName, "$netName MACID $macId");

                # Append MACID at the end
                $out = `sed -i -e "s,$oldNicDef,$nicDef,i" $userEntry`;
            }
        }
        
        # Open user entry
        $out = `cat $userEntry`;
        @lines = split( '\n', $out );
        
        # Get the userID in user entry
        $line = xCAT::zvmUtils->trimStr( $lines[0] );
        @words = split( ' ', $line );
        $id = $words[1];
        
        # Change userID in user entry to match userID defined in xCAT
        $out = `sed -i -e "s,$id,$userId,i" $userEntry`;

        # SCP file over to zHCP
        $out = `scp $userEntry $target:$userEntry`;

        # Create virtual server
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Create_DM -T $userId -f $userEntry"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Create_DM -T $userId -f $userEntry");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );

        # Check output
        $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
        if ( $rc == 0 ) {

            # Get VSwitch of zHCP (if any)
            @vswId = xCAT::zvmCPUtils->getVswitchId($::SUDOER, $hcp);

            # Grant access to VSwitch for Linux user
            # GuestLan do not need permissions
            foreach (@vswId) {
                $out = xCAT::zvmCPUtils->grantVSwitch( $callback, $::SUDOER, $hcp, $userId, $_ );
                xCAT::zvmUtils->printLn( $callback, "$node: Granting VSwitch ($_) access for $userId... $out" );
            }

            # Remove user entry file (on zHCP)
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $userEntry"`;
        }
        
        # Remove user entry on xCAT
        $out = `rm -rf $userEntry`;
    } elsif ($stdin) {        
        # Take directory entry from stdin
        $stdin = $::STDIN;    
        
        # If the directory entry contains a NICDEF statement, append MACID to the end
        # User must select the right one (layer) based on template chosen
        $out = `echo -e "$stdin" | egrep -i "NICDEF"`;
        if ($out) {
            # Get the networks used by the zHCP
            @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $hcp);
            
            # Search user entry for network name
            $netName = '';
            foreach (@hcpNets) {
                if ( $out =~ m/ $_/i ) {
                    $netName = $_;
                    last;
                }
            }
            
            # Find NICDEF statement
            $oldNicDef = `echo -e "$stdin" | egrep -i "NICDEF" | egrep -i "$netName"`;
            if ($oldNicDef) {
                $oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
                
                # Append MACID at the end
                $nicDef = xCAT::zvmUtils->replaceStr( $oldNicDef, $netName, "$netName MACID $macId" );
                # Update stdin
                $stdin =~ s/$oldNicDef/$nicDef/g;
            }
        }
        
        # Create a temporary file to contain directory on zHCP
        my $file = "/tmp/" . $node . ".direct";
        @lines = split("\n", $stdin);
            
        # Delete existing file on zHCP (if any)
        `ssh $::SUDOER\@$hcp "rm -rf $file"`;
            
        # Write directory entry into temporary file
        # because directory entry cannot be remotely echoed into stdin          
        foreach (@lines) {
            if ($_) {
                $_ = "'" . $_ . "'";
                `ssh $::SUDOER\@$hcp "echo $_ >> $file"`;
            }
        }
                
        # Create virtual server
        $out = `ssh $::SUDOER\@$hcp "cat $file | $::SUDO $::DIR/smcli Image_Create_DM -T $userId -s"`;
        xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp cat $file | $::SUDO $::DIR/smcli Image_Create_DM -T $userId -s");
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );

        # Check output
        $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
        if ( $rc == 0 ) {

            # Get VSwitch of zHCP (if any)
            @vswId = xCAT::zvmCPUtils->getVswitchId($::SUDOER, $hcp);

            # Grant access to VSwitch for Linux user
            # GuestLan do not need permissions
            foreach (@vswId) {
                $out = xCAT::zvmCPUtils->grantVSwitch( $callback, $::SUDOER, $hcp, $userId, $_ );
                xCAT::zvmUtils->printLn( $callback, "$node: Granting VSwitch ($_) access for $userId... $out" );
            }
            
            # Delete created file on zHCP
            `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "rm -rf $file"`;
        }
    } else {

        # Create NOLOG virtual server
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/createvs $userId"`;
        xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    }

    return;
}

#-------------------------------------------------------

=head3   cloneVM

    Description : Clone a virtual server
    Arguments   :   Node
                    Disk pool
                    Disk password
    Returns     : Nothing
    Example     : cloneVM($callback, $targetNode, $args);
    
=cut

#-------------------------------------------------------
sub cloneVM {

    # Get inputs
    my ( $callback, $nodes, $args ) = @_;

    # Get nodes
    my @nodes = @$nodes;

    # Return code for each command
    my $rc;
    my $out;

    # Child process IDs
    my @children;

    # Process ID for xfork()
    my $pid;

    # Get source node
    my $sourceNode = $args->[0];
    my @propNames  = ( 'hcp', 'userid' );
    my $propVals   = xCAT::zvmUtils->getNodeProps( 'zvm', $sourceNode, @propNames );

    # Get zHCP
    my $srcHcp = $propVals->{'hcp'};

    # Get node user ID
    my $sourceId = $propVals->{'userid'};
    # Capitalize user ID
    $sourceId =~ tr/a-z/A-Z/;
    
    # Get operating system, e.g. sles11sp2 or rhel6.2
    @propNames = ( 'os' );
    $propVals = xCAT::zvmUtils->getNodeProps( 'nodetype', $sourceNode, @propNames );
    my $srcOs = $propVals->{'os'};
    
    # Set IP address
    my $sourceIp = xCAT::zvmUtils->getIp($sourceNode);
    
    # Get networks in 'networks' table
    my $netEntries = xCAT::zvmUtils->getAllTabEntries('networks');
    my $srcNetwork = "";
    my $srcMask;
    foreach (@$netEntries) {
        # Get source network and mask
        $srcNetwork = $_->{'net'};
        $srcMask = $_->{'mask'};
                
        # If the host IP address is in this subnet, return
        if (xCAT::NetworkUtils->ishostinsubnet($sourceIp, $srcMask, $srcNetwork)) {
    
            # Exit loop
            last;
        } else {
            $srcNetwork = "";
        }
    }

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$srcHcp sudo:$::SUDO");
    xCAT::zvmUtils->printSyslog("srcHcp:$srcHcp sourceId:$sourceId srcOs:$srcOs srcNetwork:$srcNetwork srcMask:$srcMask");

    foreach (@nodes) {
        xCAT::zvmUtils->printLn( $callback, "$_: Cloning $sourceNode" );

        # Exit if missing source node
        if ( !$sourceNode ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source node" );
            return;
        }

        # Exit if missing source HCP
        if ( !$srcHcp ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source node HCP" );
            return;
        }

        # Exit if missing source user ID
        if ( !$sourceId ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source user ID" );
            return;
        }
        
        # Exit if missing source operating system
        if ( !$srcOs ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source operating system" );
            return;
        }
        
        # Exit if missing source operating system
        if ( !$sourceIp || !$srcNetwork || !$srcMask ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source IP, network, or mask" );
            return;
        }

        # Get target node
        @propNames = ( 'hcp', 'userid' );
        $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $_, @propNames );

        # Get target HCP
        my $tgtHcp = $propVals->{'hcp'};

        # Get node userID
        my $tgtId = $propVals->{'userid'};
        # Capitalize userID
        $tgtId =~ tr/a-z/A-Z/;

        # Exit if missing target zHCP
        if ( !$tgtHcp ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing target node HCP" );
            return;
        }

        # Exit if missing target user ID
        if ( !$tgtId ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing target user ID" );
            return;
        }

        # Exit if source and target zHCP are not equal
        if ( $srcHcp ne $tgtHcp ) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) Source and target HCP are not equal" );
            xCAT::zvmUtils->printLn( $callback, "$_: (Solution) Set the source and target HCP appropriately in the zvm table" );
            return;
        }

        #*** Get MAC address ***
        my $targetMac;
        my $macId;
        my $generateNew = 0;    # Flag to generate new MACID
        @propNames = ('mac');
        $propVals = xCAT::zvmUtils->getNodeProps( 'mac', $_, @propNames );
        if ( !$propVals->{'mac'} ) {

            # If no MACID is found, get one
            $macId = xCAT::zvmUtils->getMacID($::SUDOER, $tgtHcp);
            if ( !$macId ) {
                xCAT::zvmUtils->printLn( $callback, "$_: (Error) Could not generate MACID" );
                return;
            }

            # Create MAC address (target)
            $targetMac = xCAT::zvmUtils->createMacAddr( $::SUDOER, $_, $macId );

            # Save MAC address in 'mac' table
            xCAT::zvmUtils->setNodeProp( 'mac', $_, 'mac', $targetMac );

            # Generate new MACID
            $out = xCAT::zvmUtils->generateMacId($::SUDOER, $tgtHcp);
        }
        
        xCAT::zvmUtils->printSyslog("tgtHcp:$tgtHcp tgtId:$tgtId targetMac:$targetMac macId:$macId");
    }

    #*** Link source disks ***
    # Get MDisk statements of source node
    my @words;
    my $addr;
    my $type;
    my $linkAddr;
    my $i;

    # Hash table of source disk addresses
    # $srcLinkAddr[$addr] = $linkAddr
    my %srcLinkAddr;
    my %srcDiskSize;

    # Hash table of source disk type
    # $srcLinkAddr[$addr] = $type
    my %srcDiskType;
    my @srcDisks = xCAT::zvmUtils->getMdisks( $callback, $::SUDOER, $sourceNode );
        
    # Get details about source disks
    # Output is similar to:
    #   MDISK=VDEV=0100 DEVTYPE=3390 START=0001 COUNT=10016 VOLID=EMC2C4 MODE=MR        
    $out = `ssh $::SUDOER\@$srcHcp "$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $sourceId -k MDISK"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Definition_Query_DM -T $sourceId -k MDISK");
    xCAT::zvmUtils->printSyslog("$out");
    my $srcDiskDet = xCAT::zvmUtils->trimStr($out);
    foreach (@srcDisks) {

        # Get disk address
        @words      = split( ' ', $_ );
        $addr       = $words[1];
        $type       = $words[2];

        # Add 0 in front if address length is less than 4
        while (length($addr) < 4) {
            $addr = '0' . $addr;
        }
        
        # Get disk type
        $srcDiskType{$addr} = $type;

        # Get disk size (cylinders or blocks)
        # ECKD or FBA disk
        if ( $type eq '3390' || $type eq '9336' ) {                
            my @lines = split( '\n', $srcDiskDet );
            
            # Loop through each line
            for ( $i = 0 ; $i < @lines ; $i++ ) {
                $lines[$i] =~ s/MDISK=//g;
                
                # Extract NIC address
                @words = ($lines[$i] =~ m/=(\S+)/g);
                my $srcDiskAddr = $words[0];

                $srcDiskSize{$srcDiskAddr} = $words[3];
                xCAT::zvmUtils->printSyslog("addr:$addr type:$type srcDiskAddr:$srcDiskAddr srcDiskSize:$words[3]");
            }
        }

        # If source disk is not linked
        my $try = 5;
        while ( $try > 0 ) {

            # New disk address
            $linkAddr = $addr + 1000;

            # Check if new disk address is used (source)
            $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $srcHcp, $linkAddr );

            # If disk address is used (source)
            while ( $rc == 0 ) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $linkAddr = $linkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $srcHcp, $linkAddr );
            }

            $srcLinkAddr{$addr} = $linkAddr;

            # Link source disk to HCP
            foreach (@nodes) {
                xCAT::zvmUtils->printLn( $callback, "$_: Linking source disk ($addr) as ($linkAddr)" );
            }
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$srcHcp "$::SUDO /sbin/vmcp link $sourceId $addr $linkAddr RR"`;

            if ( $out =~ m/not linked/i ) {
                # Do nothing
            } else {
                last;
            }

            $try = $try - 1;

            # Wait before next try
            sleep(5);
        } # End of while ( $try > 0 )

        # If source disk is not linked
        if ( $out =~ m/not linked/i ) {
            foreach (@nodes) {
                xCAT::zvmUtils->printLn( $callback, "$_: Failed" );
            }

            # Exit
            return;
        }

        # Enable source disk
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $srcHcp, "-e", $linkAddr );
    } # End of foreach (@srcDisks)

    # Get the networks the HCP is on
    my @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $srcHcp);
    
    # Get the NICDEF address of the network on the source node
    my @tmp;
    my $srcNicAddr = '';
    my $hcpNetName = '';

    # Find the NIC address
    xCAT::zvmCPUtils->loadVmcp($::SUDOER, $sourceNode);
    $out = `ssh $::SUDOER\@$srcHcp "$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $sourceId -k NICDEF"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Definition_Query_DM -T $sourceId -k NICDEF");
    xCAT::zvmUtils->printSyslog("$out");
    # Output is similar to:
    #   NICDEF_PROFILE=VDEV=0800 TYPE=QDIO LAN=SYSTEM SWITCHNAME=VSW2
    #   NICDEF=VDEV=0900 TYPE=QDIO DEVICES=3 LAN=SYSTEM SWITCHNAME=GLAN1
    #   NICDEF=VDEV=0A00 TYPE=QDIO DEVICES=3 LAN=SYSTEM SWITCHNAME=VSW2
    
    my @lines = split( '\n', $out );
    
    # Loop through each line
    my $line;
    for ( $i = 0 ; $i < @lines ; $i++ ) {
        # Loop through each network name
        foreach (@hcpNets) {
            # If the network is found
            if ( $lines[$i] =~ m/SWITCHNAME=$_/i ) {
                # Save network name
                $hcpNetName = $_;
                
                $lines[$i] =~ s/NICDEF_PROFILE=//g;
                $lines[$i] =~ s/NICDEF=//g;
                
                # Extract NIC address
                @words = ($lines[$i] =~ m/=(\S+)/g);
                $srcNicAddr = $words[0];
                xCAT::zvmUtils->printSyslog("hcpNetName:$hcpNetName srcNicAddr:$srcNicAddr");
                
                # Grab only the 1st match    
                last;
            }
        }
    }
    
    # If no network name is found, exit
    if (!$hcpNetName || !$srcNicAddr) {
        #*** Detatch source disks ***
        for $addr ( keys %srcLinkAddr ) {
            $linkAddr = $srcLinkAddr{$addr};
    
            # Disable and detatch source disk
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $srcHcp, "-d", $linkAddr );
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$srcHcp "$::SUDO /sbin/vmcp det $linkAddr"`;            
            foreach (@nodes) {
                xCAT::zvmUtils->printLn( $callback, "$_: Detatching source disk ($addr) at ($linkAddr)" );
            }
        }
        
        foreach (@nodes) {
            xCAT::zvmUtils->printLn( $callback, "$_: (Error) No suitable network device found in user directory entry" );
            xCAT::zvmUtils->printLn( $callback, "$_: (Solution) Verify that the node has one of the following network devices: @hcpNets" );
        }
        
        return;
    }

    # Get vSwitch of source node (if any)
    my @srcVswitch = xCAT::zvmCPUtils->getVswitchId($::SUDOER, $srcHcp);

    # Get source MAC address in 'mac' table
    my $srcMac;
    @propNames = ('mac');
    $propVals = xCAT::zvmUtils->getNodeProps( 'mac', $sourceNode, @propNames );
    if ( $propVals->{'mac'} ) {

        # Get MAC address
        $srcMac = $propVals->{'mac'};
    }
    
    # Get user entry of source node
    my $srcUserEntry = "/tmp/$sourceNode.txt";
    $out = `rm $srcUserEntry`;
    $out = xCAT::zvmUtils->getUserEntryWODisk( $callback, $::SUDOER, $sourceNode, $srcUserEntry );

    # Check if user entry is valid
    $out = `cat $srcUserEntry`;

    # If output contains USER LINUX123, then user entry is good
    if ( $out =~ m/USER $sourceId/i ) {

        # Turn off source node
        if (`/opt/xcat/bin/pping $sourceNode` =~ m/ ping/i) {
            $out = `ssh -o ConnectTimeout=10 $sourceNode "shutdown -h now"`;
            sleep(90);    # Wait 1.5 minutes before logging user off
                        
            foreach (@nodes) {
                xCAT::zvmUtils->printLn( $callback, "$_: Shutting down $sourceNode" );
            }
        }
        
        $out = `ssh $::SUDOER\@$srcHcp "$::SUDO $::DIR/smcli Image_Deactivate -T $sourceId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $sourceId");
        xCAT::zvmUtils->printSyslog("$out");

        #*** Clone source node ***
        # Remove flashcopy lock (if any)
        $out = `ssh $::SUDOER\@$srcHcp "$::SUDO rm -f /tmp/.flashcopy_lock"`;
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                clone(
                    $callback, $_, $args, \@srcDisks, \%srcLinkAddr, \%srcDiskSize, \%srcDiskType, 
                    $srcNicAddr, $hcpNetName, \@srcVswitch, $srcOs, $srcMac, $netEntries, $sourceIp, $srcNetwork, $srcMask
                );

                # Exit process
                exit(0);
            }

            # End of elsif
            else {
                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Clone 4 nodes at a time
            # If you handle more than this, some nodes will not be cloned
            # You will get errors because SMAPI cannot handle many nodes
            if ( !( @children % 4 ) ) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid( $_, 0 );
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach

        # Handle the remaining nodes
        # Wait for all processes to end
        foreach (@children) {
            waitpid( $_, 0 );
        }

        # Remove source user entry
        $out = `rm $srcUserEntry`;
    }    # End of if

    #*** Detatch source disks ***
    for $addr ( keys %srcLinkAddr ) {
        $linkAddr = $srcLinkAddr{$addr};

        # Disable and detatch source disk
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $srcHcp, "-d", $linkAddr );
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$srcHcp "$::SUDO /sbin/vmcp det $linkAddr"`;

        foreach (@nodes) {
            xCAT::zvmUtils->printLn( $callback, "$_: Detatching source disk ($addr) at ($linkAddr)" );
        }
    }

    #*** Done ***
    foreach (@nodes) {
        xCAT::zvmUtils->printLn( $callback, "$_: Done" );
    }

    return;
}

#-------------------------------------------------------

=head3   clone

    Description : Clone a virtual server
    Arguments   :   Target node
                    Disk pool
                    Disk password (optional)
                    Source disks
                    Source disk link addresses
                    Source disk sizes
                    NIC address
                    Network name
                    VSwitch names (if any)
                    Operating system
                    MAC address
                    Root parition device address
                    Path to network configuration file
                    Path to hardware configuration file (SUSE only)
    Returns     : Nothing
    Example     : clone($callback, $_, $args, \@srcDisks, \%srcLinkAddr, \%srcDiskSize, 
                    $srcNicAddr, $hcpNetName, \@srcVswitch, $srcOs, $srcMac, $netEntries, 
                    $sourceIp, $srcNetwork, $srcMask);
    
=cut

#-------------------------------------------------------
sub clone {

    # Get inputs
    my (
        $callback, $tgtNode, $args, $srcDisksRef, $srcLinkAddrRef, $srcDiskSizeRef, $srcDiskTypeRef, 
        $srcNicAddr, $hcpNetName, $srcVswitchRef, $srcOs, $srcMac, $netEntries, $sourceIp, $srcNetwork, $srcMask
      )
      = @_;

    # Get source node properties from 'zvm' table
    my $sourceNode = $args->[0];
    my @propNames  = ( 'hcp', 'userid' );
    my $propVals   = xCAT::zvmUtils->getNodeProps( 'zvm', $sourceNode, @propNames );

    # Get zHCP
    my $srcHcp = $propVals->{'hcp'};

    # Get node user ID
    my $sourceId = $propVals->{'userid'};
    # Capitalize user ID
    $sourceId =~ tr/a-z/A-Z/;

    # Get source disks
    my @srcDisks    = @$srcDisksRef;
    my %srcLinkAddr = %$srcLinkAddrRef;
    my %srcDiskSize = %$srcDiskSizeRef;
    my %srcDiskType = %$srcDiskTypeRef;
    my @srcVswitch  = @$srcVswitchRef;

    # Return code for each command
    my $rc;

    # Get node properties from 'zvm' table
    @propNames = ( 'hcp', 'userid' );
    $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $tgtNode, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $tgtUserId = $propVals->{'userid'};
    if ( !$tgtUserId ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $tgtUserId =~ tr/a-z/A-Z/;

    # Exit if source node HCP is not the same as target node HCP
    if ( !( $srcHcp eq $hcp ) ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Source node HCP ($srcHcp) is not the same as target node HCP ($hcp)" );
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Solution) Set the source and target HCP appropriately in the zvm table" );
        return;
    }
    
    # Get target IP from /etc/hosts
    `makehosts`;
    sleep(5);
    my $targetIp = xCAT::zvmUtils->getIp($tgtNode);
    if ( !$targetIp ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing IP for $tgtNode in /etc/hosts" );
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Solution) Verify that the node's IP address is specified in the hosts table and then run makehosts" );
        return;
    }
    xCAT::zvmUtils->printSyslog("hcp:$hcp tgtUserId:$tgtUserId targetIp:$targetIp");

    my $out;
    my @lines;
    my @words;

    # Get disk pool and multi password
    my $i;
    my %inputs;
    foreach $i ( 1 .. 2 ) {
        if ( $args->[$i] ) {

            # Split parameters by '='
            @words = split( "=", $args->[$i] );

            # Create hash array
            $inputs{ $words[0] } = $words[1];
        }
    }

    # Get disk pool
    my $pool = $inputs{"pool"};
    if ( !$pool ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing disk pool. Please specify one." );
        return;
    }
    xCAT::zvmUtils->printSyslog("pool:$pool");

    # Get multi password
    # It is Ok not have a password
    my $tgtPw = "''";
    if ($inputs{"pw"}) {
        $tgtPw = $inputs{"pw"};
    }

    # Save user directory entry as /tmp/hostname.txt, e.g. /tmp/gpok3.txt
    # The source user entry is retrieved in cloneVM()
    my $userEntry    = "/tmp/$tgtNode.txt";
    my $srcUserEntry = "/tmp/$sourceNode.txt";

    # Remove existing user entry if any
    $out = `rm $userEntry`;
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $userEntry"`;

    # Copy user entry of source node
    $out = `cp $srcUserEntry $userEntry`;

    # Replace source userID with target userID
    $out = `sed -i -e "s,$sourceId,$tgtUserId,i" $userEntry`;

    # Get target MAC address in 'mac' table
    my $targetMac;
    my $macId;
    my $generateNew = 0;    # Flag to generate new MACID
    @propNames = ('mac');
    $propVals = xCAT::zvmUtils->getNodeProps( 'mac', $tgtNode, @propNames );
    if ($propVals) {

        # Get MACID
        $targetMac = $propVals->{'mac'};
        $macId     = $propVals->{'mac'};
        $macId     = xCAT::zvmUtils->replaceStr( $macId, ":", "" );
        $macId     = substr( $macId, 6 );
    } else {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing target MAC address" );
        return;
    }

    # If the user entry contains a NICDEF statement
    $out = `cat $userEntry | egrep -i "NICDEF"`;
    if ($out) {

        # Get the networks used by the zHCP
        my @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $hcp);
        
        # Search user entry for network name
        my $hcpNetName = '';
        foreach (@hcpNets) {
            if ( $out =~ m/ $_/i ) {
                $hcpNetName = $_;
                last;
            }
        }
        
        # If the user entry contains a MACID
        $out = `cat $userEntry | egrep -i "MACID"`;
        if ($out) {
            my $pos = rindex( $out, "MACID" );
            my $oldMacId = substr( $out, $pos + 6, 12 );
            $oldMacId = xCAT::zvmUtils->trimStr($oldMacId);

            # Replace old MACID
            $out = `sed -i -e "s,$oldMacId,$macId,i" $userEntry`;
        } else {

            # Find NICDEF statement
            my $oldNicDef = `cat $userEntry | egrep -i "NICDEF" | egrep -i "$hcpNetName"`;
            $oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
            my $nicDef = xCAT::zvmUtils->replaceStr( $oldNicDef, $hcpNetName, "$hcpNetName MACID $macId" );

            # Append MACID at the end
            $out = `sed -i -e "s,$oldNicDef,$nicDef,i" $userEntry`;
        }
    }

    # SCP user entry file over to HCP
    xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $userEntry, $userEntry );

    #*** Create new virtual server ***
    my $try = 5;
    while ( $try > 0 ) {
        if ( $try > 4 ) {
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Creating user directory entry" );
        } else {
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Trying again ($try) to create user directory entry" );
        }
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Create_DM -T $tgtUserId -f $userEntry"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Create_DM -T $tgtUserId -f $userEntry");
        xCAT::zvmUtils->printSyslog("$out");

        # Check if user entry is created
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId" | sed '\$d'`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $tgtUserId | sed '\$d'");
        xCAT::zvmUtils->printSyslog("$out");
        $rc  = xCAT::zvmUtils->checkOutput( $callback, $out );

        if ( $rc == -1 ) {

            # Wait before trying again
            sleep(5);

            $try = $try - 1;
        } else {
            last;
        }
    }

    # Remove user entry
    $out = `rm $userEntry`;
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $userEntry"`;

    # Exit on bad output
    if ( $rc == -1 ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not create user entry" );
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Solution) Verify that the node's zHCP and its zVM's SMAPI are both online" );
        return;
    }

    # Load VMCP module on HCP and source node
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;

    # Grant access to VSwitch for Linux user
    # GuestLan do not need permissions
    foreach (@srcVswitch) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Granting VSwitch ($_) access for $tgtUserId" );
        $out = xCAT::zvmCPUtils->grantVSwitch( $callback, $::SUDOER, $hcp, $tgtUserId, $_ );

        # Check for errors
        $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
        if ( $rc == -1 ) {

            # Exit on bad output
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
            return;
        }
    }    # End of foreach (@vswitchId)

    #*** Add MDisk to target user entry ***
    my $addr;
    my @tgtDisks;
    my $type;
    my $mode;
    my $cyl;
    foreach (@srcDisks) {

        # Get disk address
        @words = split( ' ', $_ );
        $addr = $words[1];
        push( @tgtDisks, $addr );
        $type       = $words[2];
        $mode       = $words[6];
        if (!$mode) {
            $mode = "MR";
        }
        
        # Add 0 in front if address length is less than 4
        while (length($addr) < 4) {
            $addr = '0' . $addr;
        }

        # Add ECKD disk
        if ( $type eq '3390' ) {

            # Get disk size (cylinders)
            $cyl = $srcDiskSize{$addr};

            $try = 5;
            while ( $try > 0 ) {

                # Add ECKD disk
                if ( $try > 4 ) {
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: Adding minidisk ($addr)" );
                } else {
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)" );
                }
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw");
                xCAT::zvmUtils->printSyslog("$out");
                
                # Check output
                $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
                if ( $rc == -1 ) {

                    # Wait before trying again
                    sleep(5);

                    # One less try
                    $try = $try - 1;
                } else {

                    # If output is good, exit loop
                    last;
                }
            }    # End of while ( $try > 0 )

            # Exit on bad output
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not add minidisk ($addr)" );
                return;
            }
        }    # End of if ( $type eq '3390' )

        # Add FBA disk
        elsif ( $type eq '9336' ) {

            # Get disk size (blocks)
            my $blkSize = '512';
            my $blks    = $srcDiskSize{$addr};

            $try = 10;
            while ( $try > 0 ) {

                # Add FBA disk
                if ( $try > 9 ) {
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: Adding minidisk ($addr)" );
                } else {
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)" );
                }
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 9336 -a AUTOG -r $pool -u 1 -z $blks -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 9336 -a AUTOG -r $pool -u 1 -z $blks -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw");
                xCAT::zvmUtils->printSyslog("$out");
                
                # Check output
                $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
                if ( $rc == -1 ) {

                    # Wait before trying again
                    sleep(5);

                    # One less try
                    $try = $try - 1;
                } else {

                    # If output is good, exit loop
                    last;
                }
            }    # End of while ( $try > 0 )

            # Exit on bad output
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not add minidisk ($addr)" );
                return;
            }
        }    # End of elsif ( $type eq '9336' )
    }

    # Check if the number of disks in target user entry
    # is equal to the number of disks added
    my @disks;
    $try = 10;
    while ( $try > 0 ) {

        # Get disks within user entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId" | sed '\$d' | grep "MDISK"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $tgtUserId | grep MDISK");
        xCAT::zvmUtils->printSyslog("$out");
        @disks = split( '\n', $out );
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Disks added (" . @tgtDisks . "). Disks in user entry (" . @disks . ")" );

        if ( @disks != @tgtDisks ) {
            $try = $try - 1;

            # Wait before trying again
            sleep(5);
        } else {
            last;
        }
    }

    # Exit if all disks are not present
    if ( @disks != @tgtDisks ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Disks not present in user entry" );
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Solution) Verify disk pool($pool) has free disks" );
        return;
    }

    #*** Link, format, and copy source disks ***
    my $srcAddr;
    my $tgtAddr;
    my $srcDevNode;
    my $tgtDevNode;
    my $tgtDiskType;
    foreach (@tgtDisks) {

        #*** Link target disk ***
        $try = 10;
        while ( $try > 0 ) {
            
            # Add 0 in front if address length is less than 4
            while (length($_) < 4) {
                $_ = '0' . $_;
            }
            
            # New disk address
            $srcAddr = $srcLinkAddr{$_};
            $tgtAddr = $_ + 2000;

            # Check if new disk address is used (target)
            $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $tgtAddr );

            # If disk address is used (target)
            while ( $rc == 0 ) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $tgtAddr = $tgtAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed( $::SUDOER, $hcp, $tgtAddr );
            }

            # Link target disk
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking target disk ($_) as ($tgtAddr)" );
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $_ $tgtAddr MR $tgtPw"`;

            # If link fails
            if ( $out =~ m/not linked/i || $out =~ m/not write-enabled/i ) {

                # Wait before trying again
                sleep(5);

                $try = $try - 1;
            } else {
                last;
            }
        }    # End of while ( $try > 0 )

        # If target disk is not linked
        if ( $out =~ m/not linked/i ) {
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link target disk ($_)" );
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );

            # Exit
            return;
        }
        
        # Get disk type (3390 or 9336)
        $tgtDiskType = $srcDiskType{$_};
        
        #*** Use flashcopy ***
        # Flashcopy only supports ECKD volumes
        # Assume flashcopy is supported and use Linux DD on failure
        my $ddCopy = 0;
        my $cpFlashcopy = 1;
        if ($tgtDiskType eq '3390') {
            
            # Use SMAPI FLASHCOPY
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($srcAddr) using FLASHCOPY" );
            if (xCAT::zvmUtils->smapi4xcat($::SUDOER, $hcp)) {
                 $out = xCAT::zvmCPUtils->smapiFlashCopy($::SUDOER, $hcp, $sourceId, $srcAddr, $tgtUserId, $srcAddr);
                 xCAT::zvmUtils->printSyslog("smapiFlashCopy: $out");
                 
                 # Exit if flashcopy completed successfully
                 # Otherwsie, try CP FLASHCOPY
                 if ( $out =~ m/Done/i ) {
                    $cpFlashcopy = 0;
                 }
            }
            
            # Use CP FLASHCOPY
            if ($cpFlashcopy)  {
                 # Check for CP flashcopy lock
                my $wait = 0;
                while ( `ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"` && $wait < 90 ) {
        
                    # Wait until the lock dissappears
                    # 90 seconds wait limit
                    sleep(2);
                    $wait = $wait + 2;
                }
        
                # If flashcopy locks still exists
                if (`ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"`) {
        
                    # Detatch disks from HCP
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Flashcopy lock is enabled" );
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Solution) Remove lock by deleting /tmp/.flashcopy_lock on the zHCP. Use caution!" );
                    return;
                } else {
        
                    # Enable lock
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO touch /tmp/.flashcopy_lock"`;
        
                    # Flashcopy source disk
                    $out = xCAT::zvmCPUtils->flashCopy( $::SUDOER, $hcp, $srcAddr, $tgtAddr );
                    xCAT::zvmUtils->printSyslog("flashCopy: $out");
                    $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
                    if ( $rc == -1 ) {
                        xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
        
                        # Try Linux dd
                        $ddCopy = 1;
                    }
        
                    # Wait a while for flashcopy to completely finish
                    sleep(10);
        
                    # Remove lock
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO rm -f /tmp/.flashcopy_lock"`;
                }
            }
        } else {
            $ddCopy = 1;
        }
        
        # Flashcopy not supported, use Linux dd
        if ($ddCopy) {

            #*** Use Linux dd to copy ***
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: FLASHCOPY not working. Using Linux DD" );

            # Enable target disk
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", $tgtAddr );

            # Determine source device node
            $srcDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $srcAddr);

            # Determine target device node
            $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtAddr);

            # Format target disk
            # Only ECKD disks need to be formated
            if ($tgtDiskType eq '3390') {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: Formating target disk ($tgtAddr)" );
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;
                xCAT::zvmUtils->printSyslog("dasdfmt -b 4096 -y -f /dev/$tgtDevNode");

                # Check for errors
                $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
                if ( $rc == -1 ) {
                    xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
                    
                    # Detatch disks from HCP
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;
        
                    return;
                }
    
                # Sleep 2 seconds to let the system settle
                sleep(2);
                                
                # Copy source disk to target disk
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)" );
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=4096 oflag=sync && $::SUDO echo $?"`;
                $out = xCAT::zvmUtils->trimStr($out);
                if (int($out) != 0) {
                    # If $? is not 0 then there was an error during Linux dd
                    $out = "(Error) Failed to copy /dev/$srcDevNode";
                }
                
                xCAT::zvmUtils->printSyslog("dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=4096 oflag=sync");
                xCAT::zvmUtils->printSyslog("$out");
            } else {
                # Copy source disk to target disk
                # Block size = 512
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)" );
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512 oflag=sync && $::SUDO echo $?"`;
                $out = xCAT::zvmUtils->trimStr($out);
                if (int($out) != 0) {
                    # If $? is not 0 then there was an error during Linux dd
                    $out = "(Error) Failed to copy /dev/$srcDevNode";
                }
                
                xCAT::zvmUtils->printSyslog("dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512 oflag=sync");
                xCAT::zvmUtils->printSyslog("$out");
                
                # Force Linux to re-read partition table
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: Forcing Linux to re-read partition table" );
                $out = 
`ssh $::SUDOER\@$hcp "$::SUDO cat<<EOM | fdisk /dev/$tgtDevNode
p
w
EOM"`;
            }
                        
            # Check for error
            $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
            if ( $rc == -1 ) {
                xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
                
                # Disable disks
                $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-d", $tgtAddr );

                # Detatch disks from zHCP
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;

                return;
            }

            # Sleep 2 seconds to let the system settle
            sleep(2);
        }
        
        # Disable and enable target disk
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-d", $tgtAddr );
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", $tgtAddr );

        # Determine target device node (it might have changed)
        $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtAddr);

        # Mount device and check if it is the root partition
        # If it is, then modify the network configuration
        
        # Mount target disk
        my $cloneMntPt = "/mnt/$tgtUserId/$tgtDevNode";
            
        # Disk can contain more than 1 partition. Find the right one (not swap)
        # Check if /usr/bin/file is available
        if (`ssh $::SUDOER\@$hcp "$::SUDO test -f /usr/bin/file && echo Exists"`) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/file -s /dev/$tgtDevNode*"`;
            xCAT::zvmUtils->printSyslog("file -s /dev/$tgtDevNode*");
        } else {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdisk -l /dev/$tgtDevNode*"`;
            xCAT::zvmUtils->printSyslog("fdisk -l /dev/$tgtDevNode*");
        }
        xCAT::zvmUtils->printSyslog("$out");
        
        $out = "";
        $try = 5;
        while (!$out && $try > 0) {
            # Check if /usr/bin/file is available
            if (`ssh $::SUDOER\@$hcp "$::SUDO test -f /usr/bin/file && echo Exists"`) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/file -s /dev/$tgtDevNode*" | grep -v swap | grep -o "$tgtDevNode\[1-9\]"`;
            } else {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdisk -l /dev/$tgtDevNode* | grep -v swap | grep -o $tgtDevNode\[1-9\]"`;
            }            
            $out = xCAT::zvmUtils->trimStr($out);
            xCAT::zvmUtils->printSyslog("fdisk -l /dev/$tgtDevNode* | grep -v swap | grep -o $tgtDevNode\[1-9\]");
            xCAT::zvmUtils->printSyslog("$out");
            
            # Wait before trying again
            sleep(5);
            $try = $try - 1;
        }
        
        my @tgtDevNodes = split( "\n", $out );
        my $iTgtDevNode = 0;
        $tgtDevNode = xCAT::zvmUtils->trimStr($tgtDevNodes[$iTgtDevNode]);
            
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: Mounting /dev/$tgtDevNode to $cloneMntPt" );

        # Check the disk is mounted
        $try = 5;
        while ( !(`ssh $::SUDOER\@$hcp "$::SUDO ls $cloneMntPt"`) && $try > 0 ) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO mkdir -p $cloneMntPt"`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO mount /dev/$tgtDevNode $cloneMntPt"`;
            xCAT::zvmUtils->printSyslog("mount /dev/$tgtDevNode $cloneMntPt");

            # If more than 1 partition, try other partitions
            if (@tgtDevNodes > 1 && $iTgtDevNode < @tgtDevNodes) {
                $iTgtDevNode++;
                $tgtDevNode = xCAT::zvmUtils->trimStr($tgtDevNodes[$iTgtDevNode]);
            }
                
            # Wait before trying again
            sleep(10);
            $try = $try - 1;
        }
        
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO ls $cloneMntPt"`)) {
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed to mount /dev/$tgtDevNode. Skipping device." );
        }
        
        # Is this the partition containing /etc?
        if (`ssh $::SUDOER\@$hcp "$::SUDO test -d $cloneMntPt/etc && echo Exists"`) {
            #*** Set network configuration ***
            # Set hostname
            xCAT::zvmUtils->printLn( $callback, "$tgtNode: Setting network configuration" );
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceNode/$tgtNode/i\" $cloneMntPt/etc/HOSTNAME"`;
            xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceNode/$tgtNode/i $cloneMntPt/etc/HOSTNAME");

            # If Red Hat - Set hostname in /etc/sysconfig/network
            if ( $srcOs =~ m/rhel/i ) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceNode/$tgtNode/i\" $cloneMntPt/etc/sysconfig/network"`;
                xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceNode/$tgtNode/i $cloneMntPt/etc/sysconfig/network");
            }

            # Get network layer
            my $layer = xCAT::zvmCPUtils->getNetworkLayer( $::SUDOER, $hcp, $hcpNetName );
            xCAT::zvmUtils->printSyslog("hcp:$hcp hcpNetName:$hcpNetName layer:$layer");

            # Get network configuration file
            # Location of this file depends on the OS
            my $srcIfcfg = '';
                        
            # If it is Red Hat - ifcfg-qeth file is in /etc/sysconfig/network-scripts
            my @files;
            if ( $srcOs =~ m/rhel/i ) {
                $out   = `ssh $::SUDOER\@$hcp "$::SUDO grep -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network-scripts"`;
                xCAT::zvmUtils->printSyslog("grep -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network-scripts");
                xCAT::zvmUtils->printSyslog("$out");
                @files = split('\n', $out);
                @words = split( ':', $files[0] );
                $srcIfcfg = $words[0];
            }
        
            # If it is SLES 10 - ifcfg-qeth file is in /etc/sysconfig/network
            elsif ( $srcOs =~ m/sles10/i ) {
                $out   = `ssh $::SUDOER\@$hcp "$::SUDO grep -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-qeth*"`;
                xCAT::zvmUtils->printSyslog("grep -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-qeth*");
                xCAT::zvmUtils->printSyslog("$out");
                @files = split('\n', $out);
                @words = split( ':', $files[0] );
                $srcIfcfg = $words[0];
            }
        
            # If it is SLES 11 - ifcfg-qeth file is in /etc/sysconfig/network
            elsif ( $srcOs =~ m/sles11/i ) {        
                $out   = `ssh $::SUDOER\@$hcp "$::SUDO grep -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-eth*"`;
                xCAT::zvmUtils->printSyslog("grep -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-eth*");
                xCAT::zvmUtils->printSyslog("$out");
                @files = split('\n', $out);
                @words = split( ':', $files[0] );
                $srcIfcfg = $words[0];
            }
            
            my $ifcfgPath = $srcIfcfg;
            
            # Change IP, network, and mask    
            # Go through each network
            my $tgtNetwork = "";
            my $tgtMask;
            foreach (@$netEntries) {
    
                # Get network and mask
                $tgtNetwork = $_->{'net'};
                $tgtMask = $_->{'mask'};
                
                # If the host IP address is in this subnet, return
                if (xCAT::NetworkUtils->ishostinsubnet($targetIp, $tgtMask, $tgtNetwork)) {
    
                    # Exit loop
                    last;
                } else {
                    $tgtNetwork = "";
                }
            }
                
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceNode/$tgtNode/i\" \ -e \"s/$sourceIp/$targetIp/i\" $cloneMntPt/etc/hosts"`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceIp/$targetIp/i\" \ -e \"s/$sourceNode/$tgtNode/i\" $ifcfgPath"`;
            xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceNode/$tgtNode/i \ -e s/$sourceIp/$targetIp/i $cloneMntPt/etc/hosts");
            xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceIp/$targetIp/i \ -e s/$sourceNode/$tgtNode/i $ifcfgPath");
            
            if ($tgtNetwork && $tgtMask) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$srcNetwork/$tgtNetwork/i\" \ -e \"s/$srcMask/$tgtMask/i\" $ifcfgPath"`;
                xCAT::zvmUtils->printSyslog("sed -i -e s/$srcNetwork/$tgtNetwork/i \ -e s/$srcMask/$tgtMask/i $ifcfgPath");
            }
            
            # Set MAC address
            my $networkFile = $tgtNode . "NetworkConfig";
            my $config;
            if ( $srcOs =~ m/rhel/i ) {

                # Red Hat only
                $config = `ssh $::SUDOER\@$hcp "$::SUDO cat $ifcfgPath" | grep -v "MACADDR"`;
                $config .= "MACADDR='" . $targetMac . "'\n";
            } else {

                # SUSE only
                $config = `ssh $::SUDOER\@$hcp "$::SUDO cat $ifcfgPath" | grep -v "LLADDR" | grep -v "UNIQUE"`;
                                
                # Set to MAC address (only for layer 2)
                if ( $layer == 2 ) {
                    $config .= "LLADDR='" . $targetMac . "'\n";
                    $config .= "UNIQUE=''\n";
                }
            }
            xCAT::zvmUtils->printSyslog("$config");

            # Write network configuration
            # You cannot SCP file over to mount point as sudo, so you have to copy file to zHCP 
            # and move it to mount point
            $out = `echo -e "$config" > /tmp/$networkFile`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO rm -rf $ifcfgPath"`;
            $out = `cat /tmp/$networkFile | ssh $::SUDOER\@$hcp "$::SUDO cat > /tmp/$networkFile"`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO mv /tmp/$networkFile $ifcfgPath"`;
            $out = `rm -rf /tmp/$networkFile`;

            # Set to hardware configuration (only for layer 2)
            if ( $layer == 2 ) {
                if ( $srcOs =~ m/rhel/i && $srcMac ) {
                    #*** Red Hat Linux ***
                    
                    # Set MAC address
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$srcMac/$targetMac/i\" $ifcfgPath"`;
                    xCAT::zvmUtils->printSyslog("sed -i -e s/$srcMac/$targetMac/i $ifcfgPath");                   
                } else {
                    #*** SuSE Linux ***

                    # Get hardware configuration
                    # hwcfg-qeth file is in /etc/sysconfig/hardware
                    my $hwcfgPath = $cloneMntPt . "/etc/sysconfig/hardware/hwcfg-qeth-bus-ccw-0.0.$srcNicAddr";
                    xCAT::zvmUtils->printSyslog("hwcfgPath=$hwcfgPath");
                    my $hardwareFile = $tgtNode . "HardwareConfig";
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO cat $hwcfgPath" | grep -v "QETH_LAYER2_SUPPORT" > /tmp/$hardwareFile`;
                    $out = `echo "QETH_LAYER2_SUPPORT='1'" >> /tmp/$hardwareFile`;
                    xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, "/tmp/$hardwareFile", $hwcfgPath );

                    # Remove hardware file from /tmp
                    $out = `rm /tmp/$hardwareFile`;
                }
            }    # End of if ( $layer == 2 )

            # Remove old SSH keys
            $out = `ssh $::SUDOER\@$hcp "$::SUDO rm -f $cloneMntPt/etc/ssh/ssh_host_*"`;
        }
        
        # Flush disk
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/sync"`;

        # Unmount disk
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/umount $cloneMntPt"`;

        # Remove mount point
        $out = `ssh $::SUDOER\@$hcp "$::SUDO rm -rf $cloneMntPt"`;

        # Disable disks
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-d", $tgtAddr );

        # Detatch disks from HCP
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;

        sleep(5);
    }    # End of foreach (@tgtDisks)

    # Update DHCP (only if it is running)
    $out = `service dhcpd status`;
    if (!($out =~ m/unused/i || $out =~ m/stopped/i)) {
        $out = `/opt/xcat/bin/makedhcp -a`;
    }

    # Power on target virtual server
    xCAT::zvmUtils->printLn( $callback, "$tgtNode: Powering on" );
    $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $tgtUserId"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $tgtUserId");

    # Check for error
    $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
    if ( $rc == -1 ) {
        xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
        return;
    }
}

#-------------------------------------------------------

=head3   nodeSet

    Description : Set the boot state for a node
                    * Punch initrd, kernel, and parmfile to node reader
                    * Layer 2 and 3 VSwitch/Lan supported
    Arguments   : Node
    Returns     : Nothing
    Example     : nodeSet($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub nodeSet {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Parse the possible operands
    my $osImg;
    my $remoteHost;
    my $transport;
    my $device;
    my $action;
    
    foreach my $arg ( @$args ) {
        if ($arg =~ m/^osimage=/i) {
            $osImg = $arg;
            $osImg =~ s/^osimage=//;
        } elsif ($arg =~ m/^device=/i) {
            $device = $arg;
            $device =~ s/device=//;
        } elsif ($arg =~ m/^remotehost=/i) {
            $remoteHost = $arg;
            $remoteHost =~ s/remotehost=//;
        } elsif ($arg =~ m/^transport=/i) {
            $transport = $arg;
            $transport =~ s/transport=//;
        } else {
            # If not a recognized operand with a value then it must be an action
            $action = $arg; 
        }
    }
    
    # Handle case where osimage is specified
    my $os;
    my $arch;
    my $profile;
    my $provMethod;    
    if (defined $osImg) {
        $osImg =~ s/osimage=//;
        $osImg =~ s/^\s+//;
        $osImg =~ s/\s+$//;
                
        @propNames = ('profile', 'provmethod', 'osvers', 'osarch');
        $propVals = xCAT::zvmUtils->getTabPropsByKey( 'osimage', 'imagename', $osImg, @propNames );
        
        # Update nodetype table with os, arch, and profile based on osimage
        if ( !$propVals->{'profile'} || !$propVals->{'provmethod'} || !$propVals->{'osvers'} || !$propVals->{'osarch'} ) {
            # Exit
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing profile, provmethod, osvers, or osarch for osimage" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Provide profile, provmethod, osvers, and osarch in the osimage definition" );
            return;
        }
        
        # Update nodetype table with osimage attributes for node
        my %propHash = (
            'os'      => $propVals->{'osvers'},
            'arch'    => $propVals->{'osarch'},
            'profile' => $propVals->{'profile'},
            'provmethod' => $propVals->{'provmethod'}
        );
        xCAT::zvmUtils->setNodeProps( 'nodetype', $node, \%propHash );
        $action = $propVals->{'provmethod'};
    }

    # Get install directory and domain from site table
    my @entries = xCAT::TableUtils->get_site_attribute("installdir");
    my $installDir = $entries[0];
    @entries = xCAT::TableUtils->get_site_attribute("domain");
    my $domain = $entries[0];
    @entries = xCAT::TableUtils->get_site_attribute("master");
    my $master = $entries[0];
    @entries = xCAT::TableUtils->get_site_attribute("xcatdport");
    my $xcatdPort = $entries[0];

    # Get node OS, arch, and profile from 'nodetype' table
    @propNames = ( 'os', 'arch', 'profile' );
    $propVals = xCAT::zvmUtils->getNodeProps( 'nodetype', $node, @propNames );

    $os      = $propVals->{'os'};
    $arch    = $propVals->{'arch'};
    $profile = $propVals->{'profile'};

    # If no OS, arch, or profile is found
    if (!$os || !$arch || !$profile) {

        # Exit
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node OS, arch, and profile in nodetype table" );
        return;
    }

    # Get action
    my $out;
    if ( $action eq "install" ) {

        # Get node root password
        @propNames = ('password');
        $propVals = xCAT::zvmUtils->getTabPropsByKey( 'passwd', 'key', 'system', @propNames );
        my $passwd = $propVals->{'password'};
        if ( !$passwd ) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing root password for this node" );
            return;
        }

        # Get node OS base
        my @tmp;
        if ( $os =~ m/sp/i ) {
            @tmp = split( /sp/, $os );
        } else {
            @tmp = split( /\./, $os );
        }
        my $osBase = $tmp[0];
        
        # Get node distro
        my $distro = "";
        if ( $os =~ m/sles/i ) {
            $distro = "sles";
        } elsif ( $os =~ m/rhel/i ) {
            $distro = "rh";
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Unable to determine node Linux distribution" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Verify the node Linux distribution is either sles* or rh*" );
            return;
        }

        # Get autoyast/kickstart template
        my $tmpl;
                
        # Check for $profile.$os.$arch.tmpl
        if ( -e "$installDir/custom/install/$distro/$profile.$os.$arch.tmpl" ) {
            $tmpl = "$profile.$os.$arch.tmpl";
        }
        # Check for $profile.$osBase.$arch.tmpl
        elsif ( -e "$installDir/custom/install/$distro/$profile.$osBase.$arch.tmpl" ) {
            $tmpl = "$profile.$osBase.$arch.tmpl";
        }
        # Check for $profile.$arch.tmpl
        elsif ( -e "$installDir/custom/install/$distro/$profile.$arch.tmpl" ) {
            $tmpl = "$profile.$arch.tmpl";
        }
        # Check for $profile.tmpl second
        elsif ( -e "$installDir/custom/install/$distro/$profile.tmpl" ) {
            $tmpl = "$profile.tmpl";
        }
        else {
            # No template exists
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing autoyast/kickstart template" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Create a template under $installDir/custom/install/$distro/" );
            return;
        }

        # Get host IP and hostname from /etc/hosts
        $out = `cat /etc/hosts | egrep -i "$node |$node."`;
        my @words    = split( ' ', $out );
        my $hostIP   = $words[0];
        my $hostname = $words[2];
        if (!($hostname =~ m/./i)) {
            $hostname = $words[1];
        }
        
        if ( !$hostIP || !$hostname ) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing IP for $node in /etc/hosts" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Verify that the nodes IP address is specified in the hosts table and then run makehosts" );
            return;
        }

        # Check template if DHCP is used
        my $dhcp = 0;
        if ($distro eq "sles") {
            # Check autoyast template
            if ( -e "$installDir/custom/install/sles/$tmpl" ) {
                $out = `cat $installDir/custom/install/sles/$tmpl | egrep -i "<bootproto>"`;
                if ($out =~ m/dhcp/i) {
                    $dhcp = 1;
                }
            }
        } elsif ($distro eq "rh") {
            # Check kickstart template
            if ( -e "$installDir/custom/install/rh/$tmpl" ) {
                $out = `cat $installDir/custom/install/rh/$tmpl | egrep -ie "--bootproto dhcp"`;
                if ($out =~ m/dhcp/i) {
                    $dhcp = 1;
                }
            }
        }
        
        # Get the noderes.primarynic
        my $channel = '';
        my $layer;
        my $i;
        
        @propNames = ( 'primarynic', 'nfsserver', 'xcatmaster' );
        $propVals = xCAT::zvmUtils->getNodeProps( 'noderes', $node, @propNames );
        
        my $repo = $propVals->{'nfsserver'};  # Repository containing Linux ISO
        my $xcatmaster = $propVals->{'xcatmaster'};        
        my $primaryNic = $propVals->{'primarynic'};  # NIC to use for OS installation
        
        # If noderes.primarynic is not specified, find an acceptable NIC shared with the zHCP
        if ($primaryNic) {
            $layer = xCAT::zvmCPUtils->getNetworkLayer($::SUDOER, $hcp, $primaryNic);
                   
            # If DHCP is used and the NIC is not layer 2, then exit
            if ($dhcp && $layer != 2) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) The template selected uses DHCP. A layer 2 VSWITCH or GLAN is required. None were found." );
                xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Modify the template to use <bootproto>static</bootproto> or --bootproto=static, or change the network device attached to virtual machine" );
                return;
            }
           
            # Find device channel of NIC
            my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
            $out = `echo "$userEntry" | grep "NICDEF" | grep "$primaryNic"`;
           
            # Check user profile for device channel
            if (!$out) {
                my $profileName = `echo "$userEntry" | grep "INCLUDE"`;            
                if ($profileName) {
                    @words = split(' ', xCAT::zvmUtils->trimStr($profileName));
                       
                    # Get user profile
                    my $userProfile = xCAT::zvmUtils->getUserProfile($::SUDOER, $hcp, $words[1]);
                   
                    # Get the NICDEF statement containing the HCP network
                    $out = `echo "$userProfile" | grep "NICDEF" | grep "$primaryNic"`;
                }
            }
           
            # Grab the device channel from the NICDEF statement
            my @lines = split('\n', $out);
            @words = split(' ',  $lines[0]);
            $channel = sprintf('%d', hex($words[1]));
        } else {
        	xCAT::zvmUtils->printLn( $callback, "$node: Searching for acceptable network device");
            ($primaryNic, $channel, $layer) = xCAT::zvmUtils->findUsablezHcpNetwork($::SUDOER, $hcp, $userId, $dhcp);
        
	        # If DHCP is used and not layer 2
	        if ($dhcp && $layer != 2) {
	            xCAT::zvmUtils->printLn( $callback, "$node: (Error) The template selected uses DHCP. A layer 2 VSWITCH or GLAN is required. None were found." );
	            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Modify the template to use <bootproto>static</bootproto> or change the network device attached to virtual machine" );
	            return;
	        }
        }
                
        # Exit if no suitable network found
        if (!$primaryNic || !$channel || !$layer) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) No suitable network device found in user directory entry" );            
            return;
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Setting up networking on $primaryNic (layer:$layer | DHCP:$dhcp)" );
        
        # Generate read, write, and data channels
        my $readChannel = "0.0." . (sprintf('%X', $channel + 0));
        if (length($readChannel) < 8) {
            # Prepend a zero
            $readChannel = "0.0.0" . (sprintf('%X', $channel + 0));
        }

        my $writeChannel = "0.0." . (sprintf('%X', $channel + 1));
        if (length($writeChannel) < 8) {
            # Prepend a zero
            $writeChannel = "0.0.0" . (sprintf('%X', $channel + 1));
        }

        my $dataChannel = "0.0." . (sprintf('%X', $channel + 2));
        if (length($dataChannel) < 8) {
            # Prepend a zero
            $dataChannel = "0.0.0" . (sprintf('%X', $channel + 2));
        }

        # Get MAC address (Only for layer 2)
        my $mac = "";
        my @propNames;
        my $propVals;
        if ($layer == 2) {

            # Search 'mac' table for node
            @propNames = ('mac');
            $propVals  = xCAT::zvmUtils->getTabPropsByKey('mac', 'node', $node, @propNames);
            $mac       = $propVals->{'mac'};

            # If no MAC address is found, exit
            # MAC address should have been assigned to the node upon creation
            if (!$mac) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing MAC address of node");
                return;
            }
        }
        
        # Get networks in 'networks' table
        my $entries = xCAT::zvmUtils->getAllTabEntries('networks');

        # Go through each network
        my $network = "";
        my $mask;
        foreach (@$entries) {

            # Get network and mask
            $network = $_->{'net'};
            $mask = $_->{'mask'};
            
            # If the host IP address is in this subnet, return
            if (xCAT::NetworkUtils->ishostinsubnet($hostIP, $mask, $network)) {

                # Exit loop
                last;
            } else {
                $network = "";
            }
        }
        
        # If no network found
        if ( !$network ) {

            # Exit
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Node does not belong to any network in the networks table" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Specify the subnet in the networks table. The mask, gateway, tftpserver, and nameservers must be specified for the subnet." );
            return;
        }

        @propNames = ( 'mask', 'gateway', 'tftpserver', 'nameservers' );
        $propVals = xCAT::zvmUtils->getTabPropsByKey( 'networks', 'net', $network, @propNames );
        my $mask       = $propVals->{'mask'};
        my $gateway    = $propVals->{'gateway'};

        # Convert <xcatmaster> to nameserver IP
        my $nameserver;
        if ($propVals->{'nameservers'} eq '<xcatmaster>') {
            $nameserver = xCAT::InstUtils->convert_xcatmaster();
        } else {
            $nameserver = $propVals->{'nameservers'};
        }
    
        if ( !$network || !$mask || !$nameserver ) {
            # It is acceptable to not have a gateway
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing network information" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Specify the mask, gateway, and nameservers for the subnet in the networks table" );
            return;
        }

        @propNames = ( 'nfsserver', 'xcatmaster' );
        $propVals = xCAT::zvmUtils->getNodeProps( 'noderes', $node, @propNames );
        my $repo = $propVals->{'nfsserver'};  # Repository containing Linux ISO
        my $xcatmaster = $propVals->{'xcatmaster'};
            
        # Use noderes.xcatmaster instead of site.master if it is given
        if ( $xcatmaster ) {
            $master = $xcatmaster;
        }

        # Combine NFS server and installation directory, e.g. 10.0.0.1/install
        my $nfs = $master . $installDir;

        # Get broadcast address        
        @words = split(/\./, $hostIP);
        my ($ipUnpack) = unpack("N", pack("C4", @words));
        @words = split(/\./, $mask);
        my ($maskUnpack) = unpack("N", pack( "C4", @words ));
        
        # Calculate broadcast address by inverting the netmask and do a logical or with network address
        my $math = ( $ipUnpack & $maskUnpack ) + ( ~ $maskUnpack );
        @words = unpack("C4", pack( "N", $math )) ;
        my $broadcast = join(".", @words);

        # Load VMCP module on HCP
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;

        # Sample paramter file exists in installation CD (Use that as a guide)
        my $sampleParm;
        my $parmHeader;
        my $parms;
        my $parmFile;
        my $kernelFile;
        my $initFile;

        # If punch is successful - Look for this string
        my $searchStr = "created and transferred";

        # Default parameters - SUSE
        my $instNetDev   = "osa";     # Only OSA interface type is supported
        my $osaInterface = "qdio";    # OSA interface = qdio or lcs
        my $osaMedium    = "eth";     # OSA medium = eth (ethernet) or tr (token ring)

        # Default parameters - RHEL
        my $netType  = "qeth";
        my $portName = "FOOBAR";
        my $portNo   = "0";

        # Get postscript content
        my $postScript;
        if ( $os =~ m/sles10/i ) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.sles10.s390x";
        } elsif ( $os =~ m/sles11/i ) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.sles11.s390x";
        } elsif ( $os =~ m/rhel5/i ) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.rhel5.s390x";
        } elsif ( $os =~ m/rhel6/i ) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.rhel6.s390x";
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) No postscript available for $os" );
            return;
        }

        # SUSE installation
        my $customTmpl;
        my $pkglist;
        my $patterns = '';
        my $packages = '';
        my $postBoot = "$installDir/postscripts/xcatinstallpost";
        my $postInit = "$installDir/postscripts/xcatpostinit1";
        if ( $os =~ m/sles/i ) {

            # Create directory in FTP root (/install) to hold template
            $out = `mkdir -p $installDir/custom/install/sles`;

            # Copy autoyast template
            $customTmpl = "$installDir/custom/install/sles/" . $node . "." . $profile . ".tmpl";
            if ( -e "$installDir/custom/install/sles/$tmpl" ) {
                $out = `cp $installDir/custom/install/sles/$tmpl $customTmpl`;
            } else {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) An autoyast template does not exist for $os in $installDir/custom/install/sles/. Please create one." );
                return;
            }
            
            # Get pkglist from /install/custom/install/sles/compute.sles11.s390x.otherpkgs.pkglist
            # Original one is in /opt/xcat/share/xcat/install/sles/compute.sles11.s390x.otherpkgs.pkglist
            $pkglist = "/install/custom/install/sles/" . $profile . "." . $osBase . "." . $arch . ".pkglist";
            if ( !(-e $pkglist) ) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing package list for $os in /install/custom/install/sles/" );
                xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Please create one or copy default one from /opt/xcat/share/xcat/install/sles/" );
                return;
            }
            
            # Read in each software pattern or package
            open (FILE, $pkglist);
            while (<FILE>) {
                chomp;
                
                # Create <xml> tags, e.g.
                # <package>apache</package>
                # <pattern>directory_server</pattern>
                $_ = xCAT::zvmUtils->trimStr($_);
                if ($_ && $_ =~ /@/) {
                    $_ =~ s/@//g;
                    $patterns .= "<pattern>$_</pattern>";
                } elsif ($_) {
                    $packages .= "<package>$_</package>";
                }
                
            }
            close (FILE);
            
            # Add appropriate software packages or patterns
            $out = `sed -i -e "s,replace_software_packages,$packages,g" \ -e "s,replace_software_patterns,$patterns,g" $customTmpl`;
            
            # Copy postscript into template
            $out = `sed -i -e "/<scripts>/r $postScript" $customTmpl`;            
            
            # Copy the contents of /install/postscripts/xcatpostinit1
            $out = `sed -i -e "/replace_xcatpostinit1/r $postInit" $customTmpl`;
            $out = `sed -i -e "s,replace_xcatpostinit1,,g" $customTmpl`;
                        
            # Copy the contents of /install/postscripts/xcatinstallpost
            $out = `sed -i -e "/replace_xcatinstallpost/r $postBoot" $customTmpl`;
            $out = `sed -i -e "s,replace_xcatinstallpost,,g" $customTmpl`;

            # Edit template
            my $device;
            my $chanIds = "$readChannel $writeChannel $dataChannel";

            # SLES 11
            if ( $os =~ m/sles11/i ) {
                $device = "eth0";
            } else {
                # SLES 10
                $device = "qeth-bus-ccw-$readChannel";
            }

            $out =
`sed -i -e "s,replace_host_address,$hostIP,g" \ -e "s,replace_long_name,$hostname,g" \ -e "s,replace_short_name,$node,g" \ -e "s,replace_domain,$domain,g" \ -e "s,replace_hostname,$node,g" \ -e "s,replace_nameserver,$nameserver,g" \ -e "s,replace_broadcast,$broadcast,g" \ -e "s,replace_device,$device,g" \ -e "s,replace_ipaddr,$hostIP,g" \ -e "s,replace_lladdr,$mac,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_network,$network,g" \ -e "s,replace_ccw_chan_ids,$chanIds,g" \ -e "s,replace_ccw_chan_mode,FOOBAR,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_root_password,$passwd,g" \ -e "s,replace_nic_addr,$readChannel,g" \ -e "s,replace_master,$master,g" \ -e "s,replace_install_dir,$installDir,g" $customTmpl`;

            # Attach SCSI FCP devices (if any)
            # Go through each pool
            # Find the SCSI device belonging to host
            my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
            my $hasZfcp = 0;
            my $entry;
            my $zfcpSection = "";
            foreach (@pools) {
                $entry = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$_" | egrep -i ",$node,"`;
                chomp($entry);
                if (!$entry) {
                    next;
                }
                
                # Go through each zFCP device
                my @device = split('\n', $entry);
                foreach (@device) {                        
                    # Each entry contains: status,wwpn,lun,size,range,owner,channel,tag
                    @tmp = split(',', $_);
                    my $wwpn = $tmp[1];
                    my $lun = $tmp[2];
                    my $device = lc($tmp[6]);
                    my $tag = $tmp[7];
                    
                    # If multiple WWPNs or device channels are specified (multipathing), just take the 1st one
                    if ($wwpn =~ m/;/i) {
                        @tmp = split(';', $wwpn);
                        $wwpn = xCAT::zvmUtils->trimStr($tmp[0]);
                    }
                    
                    if ($device =~ m/;/i) {
                        @tmp = split(';', $device);
                        $device = xCAT::zvmUtils->trimStr($tmp[0]);
                    }
                                  
                    # Make sure WWPN and LUN do not have 0x prefix
                    $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
                    $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        
                    # Make sure channel has a length of 4 
                    while (length($device) < 4) {
                        $device = "0" . $device;
                    }
                    
                    # zFCP variables must be in lower-case or AutoYast would get confused
                    $device = lc($device);
                    $wwpn = lc($wwpn);
                    $lun = lc($lun);
        
                    # Find tag in template and attach SCSI device associated with it
                    $out = `sed -i -e "s#$tag#/dev/disk/by-path/ccw-0.0.$device-zfcp-0x$wwpn:0x$lun#i" $customTmpl`;
                    
                    # Generate <zfcp> section
                    $zfcpSection .= <<END;
      <listentry>\\
        <controller_id>0.0.$device</controller_id>\\
        <fcp_lun>0x$lun</fcp_lun>\\
        <wwpn>0x$wwpn</wwpn>\\
      </listentry>\\
END
                    $hasZfcp = 1;
                }
            }
            
            if ($hasZfcp) {
                # Insert <zfcp> device list 
                my $find = 'replace_zfcp';
                my $replace = <<END;
    <devices config:type="list">\\
END
                $replace .= $zfcpSection;
                $replace .= <<END;
    </devices>\\
END
                my $expression = "'s#" . $find . "#" .$replace . "#i'";
                $out = `sed -i -e $expression $customTmpl`;

                xCAT::zvmUtils->printLn($callback, "$node: Inserting FCP devices into template... Done");
            }
            
            # Read sample parmfile in /install/sles10.2/s390x/1/boot/s390x/
            $sampleParm = "$installDir/$os/s390x/1/boot/s390x/parmfile";
            open( SAMPLEPARM, "<$sampleParm" );

            # Search parmfile for -- ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
            while (<SAMPLEPARM>) {

                # If the line contains 'ramdisk_size'
                if ( $_ =~ m/ramdisk_size/i ) {
                    $parmHeader = xCAT::zvmUtils->trimStr($_);
                }
            }

            # Close sample parmfile
            close(SAMPLEPARM);

            # Create parmfile -- Limited to 10 lines
            # End result should be:
            #   ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
            #   HostIP=10.0.0.5 Hostname=gpok5.endicott.ibm.com
            #   Gateway=10.0.0.1 Netmask=255.255.255.0
            #   Broadcast=10.0.0.0 Layer2=1 OSAHWaddr=02:00:01:FF:FF:FF
            #   ReadChannel=0.0.0800  WriteChannel=0.0.0801  DataChannel=0.0.0802
            #   Nameserver=10.0.0.1 Portname=OSAPORT Portno=0
            #   Install=ftp://10.0.0.1/sles10.2/s390x/1/
            #   UseVNC=1  VNCPassword=12345678
            #   InstNetDev=osa OsaInterface=qdio OsaMedium=eth Manual=0
            if (!$repo) {
                $repo = "http://$nfs/$os/s390x/1";
            }
        
            my $ay = "http://$nfs/custom/install/sles/" . $node . "." . $profile . ".tmpl";

            $parms = $parmHeader . "\n";
            $parms = $parms . "AutoYaST=$ay\n";
            $parms = $parms . "HostIP=$hostIP Hostname=$hostname\n";
            $parms = $parms . "Gateway=$gateway Netmask=$mask\n";

            # Set layer in autoyast profile
            if ( $layer == 2 ) {
                $parms = $parms . "Broadcast=$broadcast Layer2=1 OSAHWaddr=$mac\n";
            } else {
                $parms = $parms . "Broadcast=$broadcast Layer2=0\n";
            }

            $parms = $parms . "ReadChannel=$readChannel WriteChannel=$writeChannel DataChannel=$dataChannel\n";
            $parms = $parms . "Nameserver=$nameserver Portname=$portName Portno=0\n";
            $parms = $parms . "Install=$repo\n";
            $parms = $parms . "UseVNC=1 VNCPassword=12345678\n";
            $parms = $parms . "InstNetDev=$instNetDev OsaInterface=$osaInterface OsaMedium=$osaMedium Manual=0\n";

            # Write to parmfile
            $parmFile = "/tmp/" . $node . "Parm";
            open( PARMFILE, ">$parmFile" );
            print PARMFILE "$parms";
            close(PARMFILE);

            # Send kernel, parmfile, and initrd to reader to HCP
            $kernelFile = "/tmp/" . $node . "Kernel";
            $initFile   = "/tmp/" . $node . "Initrd";
            
            if ($repo) {
                $out = `/usr/bin/wget $repo/boot/s390x/vmrdr.ikr -O $kernelFile --no-check-certificate`;
                $out = `/usr/bin/wget $repo/boot/s390x/initrd -O $initFile --no-check-certificate`;
            } else {
                $out = `cp $installDir/$os/s390x/1/boot/s390x/vmrdr.ikr $kernelFile`;
                $out = `cp $installDir/$os/s390x/1/boot/s390x/initrd $initFile`;
            }

            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $kernelFile, $kernelFile );
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $parmFile,   $parmFile );
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $initFile,   $initFile );

            # Set the virtual unit record devices online on HCP
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", "c" );
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", "d" );

            # Purge reader
            $out = xCAT::zvmCPUtils->purgeReader( $::SUDOER, $hcp, $userId );
            xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

            # Punch kernel to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $kernelFile, "sles.kernel", "" );
            xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
            if ( $out =~ m/Failed/i ) {
                return;
            }

            # Punch parm to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $parmFile, "sles.parm", "-t" );
            xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
            if ( $out =~ m/Failed/i ) {
                return;
            }

            # Punch initrd to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $initFile, "sles.initrd", "" );
            xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
            if ( $out =~ m/Failed/i ) {
                return;
            }

            # Remove kernel, parmfile, and initrd from /tmp
            $out = `rm $parmFile $kernelFile $initFile`;
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $parmFile $kernelFile $initFile"`;

            xCAT::zvmUtils->printLn( $callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot." );
        }

        # RHEL installation
        elsif ( $os =~ m/rhel/i ) {

            # Create directory in FTP root (/install) to hold template
            $out = `mkdir -p $installDir/custom/install/rh`;

            # Copy kickstart template
            $customTmpl = "$installDir/custom/install/rh/" . $node . "." . $profile . ".tmpl";
            if ( -e "$installDir/custom/install/rh/$tmpl" ) {
                $out = `cp $installDir/custom/install/rh/$tmpl $customTmpl`;
            } else {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) An kickstart template does not exist for $os in $installDir/custom/install/rh/" );
                return;
            }

            # Get pkglist from /install/custom/install/rh/compute.rhel6.s390x.otherpkgs.pkglist
            # Original one is in /opt/xcat/share/xcat/install/rh/compute.rhel6.s390x.otherpkgs.pkglist
            $pkglist = "/install/custom/install/rh/" . $profile . "." . $osBase . "." . $arch . ".pkglist";
            if ( !(-e $pkglist) ) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing package list for $os in /install/custom/install/rh/" );
                xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Please create one or copy default one from /opt/xcat/share/xcat/install/rh/" );
                return;
            }
            
            # Read in each software pattern or package
            open (FILE, $pkglist);
            while (<FILE>) {
                chomp;
                $_ = xCAT::zvmUtils->trimStr($_);
                $packages .= "$_\\n";
            }
            close (FILE);
            
            # Add appropriate software packages or patterns
            $out = `sed -i -e "s,replace_software_packages,$packages,g"  $customTmpl`;
                                                        
            # Copy postscript into template
            $out = `sed -i -e "/%post/r $postScript" $customTmpl`;
            
            # Copy the contents of /install/postscripts/xcatpostinit1
            $out = `sed -i -e "/replace_xcatpostinit1/r $postInit" $customTmpl`;
            $out = `sed -i -e "s,replace_xcatpostinit1,,g" $customTmpl`;
            
            # Copy the contents of /install/postscripts/xcatinstallpost
            $out = `sed -i -e "/replace_xcatinstallpost/r $postBoot" $customTmpl`;
            $out = `sed -i -e "s,replace_xcatinstallpost,,g" $customTmpl`;

            # Edit template
            if (!$repo) {
                $repo = "http://$nfs/$os/s390x";
            }
            
            $out =
`sed -i -e "s,replace_url,$repo,g" \ -e "s,replace_ip,$hostIP,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_nameserver,$nameserver,g" \ -e "s,replace_hostname,$hostname,g" \ -e "s,replace_rootpw,$passwd,g" \ -e "s,replace_master,$master,g" \ -e "s,replace_install_dir,$installDir,g" $customTmpl`;

            # Attach SCSI FCP devices (if any)
            # Go through each pool
            # Find the SCSI device belonging to host
            my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
            my $hasZfcp = 0;
            my $entry;
            my $zfcpSection = "";
            foreach (@pools) {
                $entry = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$_" | egrep -i ",$node,"`;
                chomp($entry);
                if (!$entry) {
                    next;
                }
                
                # Go through each zFCP device
                my @device = split('\n', $entry);
                foreach (@device) {             
                    # Each entry contains: status,wwpn,lun,size,range,owner,channel,tag
                    @tmp = split(',', $_);
                    my $wwpn = $tmp[1];
                    my $lun = $tmp[2];
                    my $device = lc($tmp[6]);
                    my $tag = $tmp[7];
                                        
                    # If multiple WWPNs or device channels are specified (multipathing), just take the 1st one
                    if ($wwpn =~ m/;/i) {
                        @tmp = split(';', $wwpn);
                        $wwpn = xCAT::zvmUtils->trimStr($tmp[0]);
                    }
                    
                    if ($device =~ m/;/i) {
                        @tmp = split(';', $device);
                        $device = xCAT::zvmUtils->trimStr($tmp[0]);
                    }
                                  
                    # Make sure WWPN and LUN do not have 0x prefix
                    $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
                    $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        
                    # Make sure channel has a length of 4 
                    while (length($device) < 4) {
                        $device = "0" . $device;
                    }

                    # zFCP variables must be in lower-case or AutoYast would get confused.
                    $device = lc($device);
                    $wwpn = lc($wwpn);
                    $lun = lc($lun);

                    # Create zfcp section
                    $zfcpSection = "zfcp --devnum 0.0.$device --wwpn 0x$wwpn --fcplun 0x$lun" . '\n';
                    
                    # Look for replace_zfcp keyword in template and replace it
                    $out = `sed -i -e "s,$tag,$zfcpSection,i" $customTmpl`; 
                    $hasZfcp = 1;
                }
            }
            
            if ($hasZfcp) {
                xCAT::zvmUtils->printLn($callback, "$node: Inserting FCP devices into template... Done");
            }
            
            # Read sample parmfile in /install/rhel5.3/s390x/images
            $sampleParm = "$installDir/$os/s390x/images/generic.prm";
            open( SAMPLEPARM, "<$sampleParm" );

            # Search parmfile for -- root=/dev/ram0 ro ip=off ramdisk_size=40000
            while (<SAMPLEPARM>) {

                # If the line contains 'ramdisk_size'
                if ( $_ =~ m/ramdisk_size/i ) {
                    $parmHeader = xCAT::zvmUtils->trimStr($_);
                    
                    # RHEL 6.1 needs cio_ignore in order to install
                    if ( !($os =~ m/rhel6.1/i) ) {
                        $parmHeader =~ s/cio_ignore=all,!0.0.0009//g;
                    }
                }
            }

            # Close sample parmfile
            close(SAMPLEPARM);

            # Get mdisk virtual address
            my @mdisks = xCAT::zvmUtils->getMdisks( $callback, $::SUDOER, $node );
            @mdisks = sort(@mdisks);
            my $dasd   = "";
            my $devices = "";
            my $i      = 0;
            foreach (@mdisks) {
                $i     = $i + 1;
                @words = split( ' ', $_ );

                # Do not put a comma at the end of the last disk address
                if ( $i == @mdisks ) {
                    $dasd = $dasd . "0.0.$words[1]";
                } else {
                    $dasd = $dasd . "0.0.$words[1],";
                }
            }
            
            # Character limit of 50 in parm file for DASD parameter
            if (length($dasd) > 50) {
                @words = split( ',', $dasd );
                $dasd = $words[0] . "-" . $words[@words - 1];
            }
            
            # Get dedicated virtual address
            my @dedicates = xCAT::zvmUtils->getDedicates( $callback, $::SUDOER, $node );
            @dedicates = sort(@dedicates);            
            $i = 0;
            foreach (@dedicates) {
                $i = $i + 1;
                @words = split( ' ', $_ );

                # Do not put a comma at the end of the last disk address
                if ( $i == @dedicates ) {
                    $devices = $devices . "0.0.$words[1]";
                } else {
                    $devices = $devices . "0.0.$words[1],";
                }
            }
            
            # Character limit of 50 in parm file for DASD parameter
            if (length($devices) > 50) {
                @words = split( ',', $devices );
                $devices = $words[0] . "-" . $words[@words - 1];
            }
            
            # Concat dedicated devices and DASD together
            if ($devices) {
                if ($dasd) {
                    $dasd = $dasd . "," . $devices;
                } else {
                    $dasd = $devices;
                }
            }

            # Create parmfile -- Limited to 80 characters/line, maximum of 11 lines
            # End result should be:
            #    ramdisk_size=40000 root=/dev/ram0 ro ip=off
            #     ks=ftp://10.0.0.1/rhel5.3/s390x/compute.rhel5.s390x.tmpl
            #    RUNKS=1 cmdline
            #    DASD=0.0.0100 HOSTNAME=gpok4.endicott.ibm.com
            #    NETTYPE=qeth IPADDR=10.0.0.4
            #    SUBCHANNELS=0.0.0800,0.0.0801,0.0.0800
            #    NETWORK=10.0.0.0 NETMASK=255.255.255.0
            #    SEARCHDNS=endicott.ibm.com BROADCAST=10.0.0.255
            #    GATEWAY=10.0.0.1 DNS=9.0.2.11 MTU=1500
            #    PORTNAME=UNASSIGNED PORTNO=0 LAYER2=0
            #    vnc vncpassword=12345678
            my $ks = "http://$nfs/custom/install/rh/" . $node . "." . $profile . ".tmpl";

            $parms = $parmHeader . "\n";
            $parms = $parms . "ks=$ks\n";
            $parms = $parms . "RUNKS=1 cmdline\n";
            $parms = $parms . "DASD=$dasd\n";
            $parms = $parms . "HOSTNAME=$hostname NETTYPE=$netType IPADDR=$hostIP\n";
            $parms = $parms . "SUBCHANNELS=$readChannel,$writeChannel,$dataChannel\n";
            $parms = $parms . "NETWORK=$network NETMASK=$mask\n";
            $parms = $parms . "SEARCHDNS=$domain BROADCAST=$broadcast\n";
            $parms = $parms . "GATEWAY=$gateway DNS=$nameserver MTU=1500\n";

            # Set layer in kickstart profile
            if ( $layer == 2 ) {
                $parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=1 MACADDR=$mac\n";
            } else {
                $parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=0\n";
            }

            $parms = $parms . "vnc vncpassword=12345678\n";

            # Write to parmfile
            $parmFile = "/tmp/" . $node . "Parm";
            open( PARMFILE, ">$parmFile" );
            print PARMFILE "$parms";
            close(PARMFILE);

            # Send kernel, parmfile, conf, and initrd to reader to HCP
            $kernelFile = "/tmp/" . $node . "Kernel";
            $initFile   = "/tmp/" . $node . "Initrd";

            # Copy over kernel, parmfile, conf, and initrd from remote repository
            if ($repo) {
                $out = `/usr/bin/wget $repo/images/kernel.img -O $kernelFile --no-check-certificate`;
                $out = `/usr/bin/wget $repo/images/initrd.img -O $initFile --no-check-certificate`;
            } else {
                $out = `cp $installDir/$os/s390x/images/kernel.img $kernelFile`;
                $out = `cp $installDir/$os/s390x/images/initrd.img $initFile`;
            }
            
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $kernelFile, $kernelFile );
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $parmFile,   $parmFile );
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $initFile,   $initFile );

            # Set the virtual unit record devices online
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", "c" );
            $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", "d" );

            # Purge reader
            $out = xCAT::zvmCPUtils->purgeReader( $::SUDOER, $hcp, $userId );
            xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

            # Punch kernel to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $kernelFile, "rhel.kernel", "" );
            xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
            if ( $out =~ m/Failed/i ) {
                return;
            }

            # Punch parm to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $parmFile, "rhel.parm", "-t" );
            xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
            if ( $out =~ m/Failed/i ) {
                return;
            }

            # Punch initrd to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $initFile, "rhel.initrd", "" );
            xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
            if ( $out =~ m/Failed/i ) {
                return;
            }

            # Remove kernel, parmfile, and initrd from /tmp
            $out = `rm $parmFile $kernelFile $initFile`;
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $parmFile $kernelFile $initFile"`;

            xCAT::zvmUtils->printLn( $callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot." );
        }
    } elsif ( $action eq "statelite" ) {

        # Get node group from 'nodelist' table
        @propNames = ('groups');
        $propVals = xCAT::zvmUtils->getTabPropsByKey( 'nodelist', 'node', $node, @propNames );
        my $group = $propVals->{'groups'};

        # Get node statemnt (statelite mount point) from 'statelite' table
        @propNames = ('statemnt');
        $propVals = xCAT::zvmUtils->getTabPropsByKey( 'statelite', 'node', $node, @propNames );
        my $stateMnt = $propVals->{'statemnt'};
        if ( !$stateMnt ) {
            $propVals = xCAT::zvmUtils->getTabPropsByKey( 'statelite', 'node', $group, @propNames );
            $stateMnt = $propVals->{'statemnt'};

            if ( !$stateMnt ) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node statemnt in statelite table. Please specify one." );
                return;
            }
        }

        # Netboot directory
        my $netbootDir = "$installDir/netboot/$os/$arch/$profile";
        my $kernelFile = "$netbootDir/kernel";
        my $parmFile   = "$netbootDir/parm-statelite";
        my $initFile   = "$netbootDir/initrd-statelite.gz";

        # If parmfile exists
        if ( -e $parmFile ) {
            # Do nothing
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: Creating parmfile" );

            my $sampleParm;
            my $parmHeader;
            my $parms;
            if ( $os =~ m/sles/i ) {
                if ( -e "$installDir/$os/s390x/1/boot/s390x/parmfile" ) {
                    # Read sample parmfile in /install/sles11.1/s390x/1/boot/s390x/
                    $sampleParm = "$installDir/$os/s390x/1/boot/s390x/parmfile";
                } else {
                    xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing $installDir/$os/s390x/1/boot/s390x/parmfile" );
                    return;
                }
            } elsif ( $os =~ m/rhel/i ) {
                if ( -e "$installDir/$os/s390x/images/generic.prm" ) {
                    # Read sample parmfile in /install/rhel5.3/s390x/images
                    $sampleParm = "$installDir/$os/s390x/images/generic.prm";
                } else {
                    xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing $installDir/$os/s390x/images/generic.prm" );
                    return;
                }
            }

            open( SAMPLEPARM, "<$sampleParm" );

            # Search parmfile for -- ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
            while (<SAMPLEPARM>) {
                # If the line contains 'ramdisk_size'
                if ( $_ =~ m/ramdisk_size/i ) {
                    $parmHeader = xCAT::zvmUtils->trimStr($_);
                }
            }

            # Close sample parmfile
            close(SAMPLEPARM);

            # Create parmfile
            # End result should be:
            #   ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
            #   NFSROOT=10.1.100.1:/install/netboot/sles11.1.1/s390x/compute
            #   STATEMNT=10.1.100.1:/lite/state XCAT=10.1.100.1:3001
            $parms = $parmHeader . "\n";
            $parms = $parms . "NFSROOT=$master:$netbootDir\n";
            $parms = $parms . "STATEMNT=$stateMnt XCAT=$master:$xcatdPort\n";

            # Write to parmfile
            open( PARMFILE, ">$parmFile" );
            print PARMFILE "$parms";
            close(PARMFILE);
        }

        # Temporary kernel, parmfile, and initrd
        my $tmpKernelFile = "/tmp/$os-kernel";
        my $tmpParmFile   = "/tmp/$os-parm-statelite";
        my $tmpInitFile   = "/tmp/$os-initrd-statelite.gz";

        if (`ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO ls /tmp" | grep "$os-kernel"`) {
            # Do nothing
        } else {
            # Send kernel to reader to HCP
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $kernelFile, $tmpKernelFile );
        }

        if (`ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO ls /tmp" | grep "$os-parm-statelite"`) {
            # Do nothing
        } else {
            # Send parmfile to reader to HCP
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $parmFile, $tmpParmFile );
        }

        if (`ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO ls /tmp" | grep "$os-initrd-statelite.gz"`) {
            # Do nothing
        } else {
            # Send initrd to reader to HCP
            xCAT::zvmUtils->sendFile( $::SUDOER, $hcp, $initFile, $tmpInitFile );
        }

        # Set the virtual unit record devices online
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", "c" );
        $out = xCAT::zvmUtils->disableEnableDisk( $::SUDOER, $hcp, "-e", "d" );

        # Purge reader
        $out = xCAT::zvmCPUtils->purgeReader( $::SUDOER, $hcp, $userId );
        xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

        # Kernel, parm, and initrd are in /install/netboot/<os>/<arch>/<profile>
        # Punch kernel to reader on HCP
        $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $tmpKernelFile, "sles.kernel", "" );
        xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
        if ( $out =~ m/Failed/i ) {
            return;
        }

        # Punch parm to reader on HCP
        $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $tmpParmFile, "sles.parm", "-t" );
        xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
        if ( $out =~ m/Failed/i ) {
            return;
        }

        # Punch initrd to reader on HCP
        $out = xCAT::zvmCPUtils->punch2Reader( $::SUDOER, $hcp, $userId, $tmpInitFile, "sles.initrd", "" );
        xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
        if ( $out =~ m/Failed/i ) {
            return;
        }

        xCAT::zvmUtils->printLn( $callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot." );
    } elsif (  $action eq "netboot" ) {
        
        # Obtain the location of the install root directory
        my $installRoot = xCAT::TableUtils->getInstallDir();
        
        # Verify the image exists
        my $imageFile;
        my $deployImgDir = "$installRoot/$action/$os/$arch/$profile";
        my @imageFiles = glob "$deployImgDir/*.img";
        if (@imageFiles == 0) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) $deployImgDir does not contain image files" );
            return;
        } elsif (@imageFiles > 1) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) $deployImgDir contains more than the expected number of image files" );
            return;
        } else {
            $imageFile = (split('/', $imageFiles[0]))[-1];
        }
        
        if (! defined $device) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Image device was not specified" );
            return;
        }
        
        # Prepare the deployable netboot mount point on zHCP, if they need to be established.
        my $remoteDeployDir;
        my $rc = xCAT::zvmUtils->establishMount($callback, $::SUDOER, $::SUDO, $hcp, "$installRoot/$action", "ro", \$remoteDeployDir);
        if ( $rc ) {
            # Mount failed
            return;
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Deploying the image using the zHCP node" );
    
        # Copy the image to the target disk using the zHCP node
        xCAT::zvmUtils->printSyslog( "nodeset() unpackdiskimage $userId $device $remoteDeployDir/$os/$arch/$profile/$imageFile" );
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/unpackdiskimage $userId $device $remoteDeployDir/$os/$arch/$profile/$imageFile"`;
        $rc = $?;
        
        my $reasonString = "";
        $rc = xCAT::zvmUtils->checkOutputExtractReason($callback, $out, \$reasonString);
        if ($rc != 0) {
            my $reason = "Reason: $reasonString";
            xCAT::zvmUtils->printSyslog( "nodeset() unpackdiskimage of $userId $device failed. $reason" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Unable to deploy the image to $userId $device. $reason" );
            return;
        }
        
        # If the transport file was specified then setup the transport disk.
        if ($transport) {
            my $transImgDir = "$installRoot/staging/transport";
            if(!-d $transImgDir) {
                mkpath($transImgDir);
            }
            
            # Create unique transport directory and copy the transport file to it
            my $transportDir = `/bin/mktemp -d $installDir/staging/transport/XXXXXX`;
            chomp($transportDir);
            if ($remoteHost) {
                # Copy the transport file from the remote system to the local transport directory.
                xCAT::zvmUtils->printLn( $callback, "/usr/bin/scp -B $remoteHost:$transport $transportDir" );
                $out = `/usr/bin/scp -v -B $remoteHost:$transport $transportDir`;
                $rc = $?;
            } else {
                # Safely copy the transport file from a local directory.
                $out = `/bin/cp $transport $transportDir`;
                $rc = $?;
            }
            
            if ($rc != 0) {
                # Copy failed  Get rid of the unique directory that was going to receive the copy.
                rmtree $transportDir;
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to copy the transport file");
                return;
            }
            
            # Purge the target node's reader
            $out = xCAT::zvmCPUtils->purgeReader( $::SUDOER, $hcp, $userId );
            xCAT::zvmUtils->printLn($callback, "$node: Purging reader... Done");
            
            # Online zHCP's punch
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/chccwdev -e 00d && echo $?"`;
            if ($out != '0') {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to online the zHCP's punch");
                return;
            }
            
            # Load VMCP module on HCP
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;
            if ($out != '0') {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to load the vmcp module on the zHCP node");
                return;
            }
            
            # Set the punch to class 'x'
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp spool punch class x"`;
            if ($out != '0') {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to spool the punch on the zHCP node");
                return;
            }
            
            # Punch files to node's reader so it could be pulled on boot
            # Reader = transport disk
            my @files = glob "$transportDir/*";
            foreach (@files) {
                my $file = basename($_);
                my $filePath = "/tmp/$node-" . $file;
                
                # Spool file only accepts [A-Za-z] and file name can only be 8-characters long
                my @filePortions = split( '\.', $file );
                if (( @filePortions > 2 ) || 
                    ( $filePortions[0] =~ m/[^a-zA-Z0-9]/ ) || ( length($filePortions[0]) > 8 ) || ( length($filePortions[0]) < 1 ) ||
                    ( $filePortions[1] =~ m/[^a-zA-Z0-9]{1,8}/ ) || ( length($filePortions[1]) > 8 )) {
                    $out = `/bin/rm -rf $transportDir`;
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) $file contains a file name or file type portion that is longer than 8 characters, or not alphanumeric ");
                    return;
                }
                
                xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $_, $filePath);
                                
                my $punchOpt = "";
                if ($file =~ /.txt/ || $file =~ /.sh/) {
                    $punchOpt = "-t";
                }
                $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $filePath, "$file", $punchOpt);
                
                # Clean up file
                `ssh $::SUDOER\@$hcp "$::SUDO /bin/rm $filePath"`;
                
                xCAT::zvmUtils->printLn($callback, "$node: Punching $file to reader... $out");
                if ($out =~ m/Failed/i) {
                    # Clean up transport directory
                    $out = `/bin/rm -rf $transportDir`;
                    return;
                }
            }
            
            # Clean up transport directory
            $out = `/bin/rm -rf $transportDir`;            
            xCAT::zvmUtils->printLn( $callback, "$node: Completed deploying image($os-$arch-netboot-$profile)" );
        }
    } else {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Option not supported" );
        return;
    }
    
    return;
}

#-------------------------------------------------------

=head3   getMacs

    Description : Get the MAC address of a given node
                    * Requires the node be online
                    * Saves MAC address in 'mac' table
    Arguments   : Node
    Returns     : Nothing
    Example     : getMacs($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub getMacs {

    # Get inputs
    my ( $callback, $node, $args ) = @_;
    my $force = '';
    if ($args) {
        @ARGV = @$args;
        
        # Parse options
        GetOptions( 'f' => \$force );
    }

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    # Get MAC address in 'mac' table
    @propNames = ('mac');
    $propVals = xCAT::zvmUtils->getNodeProps( 'mac', $node, @propNames );
    my $mac;
    if ( $propVals->{'mac'} && !$force) {

        # Get MAC address
        $mac = $propVals->{'mac'};
        xCAT::zvmUtils->printLn( $callback, "$node: $mac" );
        return;
    }

    # If MAC address is not in the 'mac' table, get it using VMCP
    xCAT::zvmCPUtils->loadVmcp($::SUDOER, $node);

    # Get xCat MN Lan/VSwitch name
    my $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
    my @lines = split( '\n', $out );
    my @words;

    # Go through each line and extract VSwitch and Lan names
    # and create search string
    my $searchStr = "";
    my $i;
    for ( $i = 0 ; $i < @lines ; $i++ ) {

        # Extract VSwitch name
        if ( $lines[$i] =~ m/VSWITCH/i ) {
            @words = split( ' ', $lines[$i] );
            $searchStr = $searchStr . "$words[4]";
        }

        # Extract Lan name
        elsif ( $lines[$i] =~ m/LAN/i ) {
            @words = split( ' ', $lines[$i] );
            $searchStr = $searchStr . "$words[4]";
        }

        if ( $i != ( @lines - 1 ) ) {
            $searchStr = $searchStr . "|";
        }
    }

    # Get MAC address of node
    # This node should be on only 1 of the networks that the xCAT MN is on
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$node "/sbin/vmcp q v nic" | egrep -i "$searchStr"`;
    if ( !$out ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to find MAC address" );
        return;
    }

    @lines = split( '\n', $out );
    @words = split( ' ',  $lines[0] );
    $mac   = $words[1];

    # Replace - with :
    $mac = xCAT::zvmUtils->replaceStr( $mac, "-", ":" );
    xCAT::zvmUtils->printLn( $callback, "$node: $mac" );

    # Save MAC address and network interface into 'mac' table
    xCAT::zvmUtils->setNodeProp( 'mac', $node, 'mac', $mac );

    return;
}

#-------------------------------------------------------

=head3   netBoot

    Description : Boot from network
    Arguments   :   Node
                    Address to IPL from
    Returns     : Nothing
    Example     : netBoot($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub netBoot {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Get IPL
    my @ipl = split( '=', $args->[0] );
    if ( !( $ipl[0] eq "ipl" ) ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing IPL" );
        return;
    }

    # Boot node
    my $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $userId"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $userId");
    xCAT::zvmUtils->printSyslog("$out");
    
    # IPL when virtual server is online
    sleep(5);
    $out = xCAT::zvmCPUtils->sendCPCmd( $::SUDOER, $hcp, $userId, "IPL $ipl[1]" );
    xCAT::zvmUtils->printSyslog("IPL $ipl[1]");
    xCAT::zvmUtils->printSyslog("$out");
    xCAT::zvmUtils->printLn( $callback, "$node: Booting from $ipl[1]... Done" );

    return;
}

#-------------------------------------------------------

=head3   updateNode (No longer supported)

    Description : Update node
    Arguments   : Node
                  Option         
    Returns     : Nothing
    Example     : updateNode($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub updateNode {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    # Get install directory
    my @entries = xCAT::TableUtils->get_site_attribute("installdir");
    my $installDir = $entries[0];

    # Get host IP and hostname from /etc/hosts
    my $out      = `cat /etc/hosts | egrep -i "$node |$node."`;
    my @words    = split( ' ', $out );
    my $hostIP   = $words[0];
    my $hostname = $words[2];
    if (!($hostname =~ m/./i)) {
        $hostname = $words[1];
    }
    
    if ( !$hostIP || !$hostname ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing IP for $node in /etc/hosts" );
        xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Verify that the node's IP address is specified in the hosts table and then run makehosts" );
        return;
    }

    # Get first 3 octets of node IP (IPv4)
    @words = split( /\./, $hostIP );
    my $octets = "$words[0].$words[1].$words[2]";

    # Get networks in 'networks' table
    my $entries = xCAT::zvmUtils->getAllTabEntries('networks');

    # Go through each network
    my $network;
    foreach (@$entries) {

        # Get network
        $network = $_->{'net'};

        # If networks contains the first 3 octets of the node IP
        if ( $network =~ m/$octets/i ) {

            # Exit loop
            last;
        } else {
            $network = "";
        }
    }

    # If no network found
    if ( !$network ) {

        # Exit
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Node does not belong to any network in the networks table" );
        xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Specify the subnet in the networks table. The mask, gateway, tftpserver, and nameservers must be specified for the subnet." );
        return;
    }

    # Get FTP server
    @propNames = ('tftpserver');
    $propVals = xCAT::zvmUtils->getTabPropsByKey( 'networks', 'net', $network, @propNames );
    my $nfs = $propVals->{'tftpserver'};
    if ( !$nfs ) {

        # It is acceptable to not have a gateway
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing FTP server" );
        xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Specify the tftpserver for the subnet in the networks table" );
        return;
    }

    # Update node operating system
    if ( $args->[0] eq "--release" ) {
        my $version = $args->[1];

        if ( !$version ) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing operating system release. Please specify one." );
            return;
        }

        # Get node operating system
        my $os = xCAT::zvmUtils->getOs($::SUDOER, $node);

        # Check node OS is the same as the version OS given
        # You do not want to update a SLES with a RHEL
        if ( ( ( $os =~ m/SUSE/i ) && !( $version =~ m/sles/i ) ) || ( ( $os =~ m/Red Hat/i ) && !( $version =~ m/rhel/i ) ) ) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Node operating system is different from the operating system given to upgrade to. Please correct." );
            return;
        }

        # Generate FTP path to operating system image
        my $path;
        if ( $version =~ m/sles/i ) {

            # The following only applies to SLES 10
            # SLES 11 requires zypper

            # SuSE Enterprise Linux path - ftp://10.0.0.1/sles10.3/s390x/1/
            $path = "http://$nfs/install/$version/s390x/1/";

            # Add installation source using rug
            $out = `ssh $::SUDOER\@$node "rug sa -t zypp $path $version"`;
            xCAT::zvmUtils->printLn( $callback, "$node: $out" );

            # Subscribe to catalog
            $out = `ssh $::SUDOER\@$node "rug sub $version"`;
            xCAT::zvmUtils->printLn( $callback, "$node: $out" );

            # Refresh services
            $out = `ssh $::SUDOER\@$node "rug ref"`;
            xCAT::zvmUtils->printLn( $callback, "$node: $out" );

            # Update
            $out = `ssh $::SUDOER\@$node "rug up -y"`;
            xCAT::zvmUtils->printLn( $callback, "$node: $out" );
        } else {

            # Red Hat Enterprise Linux path - ftp://10.0.0.1/rhel5.4/s390x/Server/
            $path = "http://$nfs/install/$version/s390x/Server/";

            # Check if file.repo already has this repository location
            $out = `ssh $::SUDOER\@$node "cat /etc/yum.repos.d/file.repo"`;
            if ( $out =~ m/[$version]/i ) {

                # Send over release key
                my $key = "$installDir/$version/s390x/RPM-GPG-KEY-redhat-release";
                my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
                xCAT::zvmUtils->sendFile( $::SUDOER, $node, $key, $tmp );

                # Import key
                $out = `ssh $::SUDOER\@$node "rpm --import /tmp/$key"`;

                # Upgrade
                $out = `ssh $::SUDOER\@$node "yum upgrade -y"`;
                xCAT::zvmUtils->printLn( $callback, "$node: $out" );
            } else {

                # Create repository
                $out =  xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo [$version] >> /etc/yum.repos.d/file.repo");
                $out =  xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo baseurl=$path >> /etc/yum.repos.d/file.repo");
                $out =  xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo enabled=1 >> /etc/yum.repos.d/file.repo");

                # Send over release key
                my $key = "$installDir/$version/s390x/RPM-GPG-KEY-redhat-release";
                my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
                xCAT::zvmUtils->sendFile( $::SUDOER, $node, $key, $tmp );

                # Import key
                $out = `ssh $::SUDOER\@$node "rpm --import $tmp"`;

                # Upgrade
                $out = `ssh $::SUDOER\@$node "yum upgrade -y"`;
                xCAT::zvmUtils->printLn( $callback, "$node: $out" );
            }
        }
    }

    # Otherwise, print out error
    else {
        $out = "$node: (Error) Option not supported";
    }

    xCAT::zvmUtils->printLn( $callback, "$out" );
    return;
}

#-------------------------------------------------------

=head3   listTree

    Description : Show the nodes hierarchy tree
    Arguments   : Node range (zHCP)
    Returns     : Nothing
    Example     : listHierarchy($callback, $nodes, $args);
    
=cut

#-------------------------------------------------------
sub listTree {

    # Get inputs
    my ( $callback, $nodes, $args ) = @_;
    my @nodes = @$nodes;
    
    # Directory where executables are on zHCP
    $::DIR = "/opt/zhcp/bin";
    
    # Use sudo or not
    # This looks in the passwd table for a key = sudoer
    ($::SUDOER, $::SUDO) = xCAT::zvmUtils->getSudoer();

    # In order for this command to work, issue under /opt/xcat/bin: 
    # ln -s /opt/xcat/bin/xcatclient lstree
            
    my %tree;
    my $node;
    my $hcp;
    my $parent;
    my %ssi = {};
    my $found;
    
    # Create hierachy structure: CEC -> LPAR -> zVM -> VM
    # Get table
    my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );
    
    # Get CEC entries
    # There should be few of these nodes
    my @entries = $tab->getAllAttribsWhere( "nodetype = 'cec'", 'node', 'parent' );
    foreach (@entries) {
        $node = $_->{'node'};
        
        # Make CEC the tree root
        $tree{$node} = {};
    }

    # Get LPAR entries
    # There should be a couple of these nodes
    @entries = $tab->getAllAttribsWhere( "nodetype = 'lpar'", 'node', 'parent' );
    foreach (@entries) {
        $node = $_->{'node'};        # LPAR
        $parent = $_->{'parent'};    # CEC
        
        # Add LPAR branch
        $tree{$parent}{$node} = {};
    }
    
    # Get zVM entries
    # There should be a couple of these nodes
    $found = 0;
    @entries = $tab->getAllAttribsWhere( "nodetype = 'zvm'", 'node', 'hcp', 'parent' );
    foreach (@entries) {
        $node = $_->{'node'};        # zVM
        $hcp = $_->{'hcp'};          # zHCP
        $parent = $_->{'parent'};    # LPAR
        
        # Find out if this z/VM belongs to an SSI cluster
        $ssi{$node} = xCAT::zvmUtils->querySSI($::SUDOER, $hcp);
        
        # Find CEC root based on LPAR
        # CEC -> LPAR
        $found = 0;
        foreach my $cec(sort keys %tree) {
            foreach my $lpar(sort keys %{$tree{$cec}}) {
                if ($lpar eq $parent) {
                    # Add LPAR branch
                    $tree{$cec}{$parent}{$node} = {};
                    $found = 1;
                    last;
                }
                
                # Handle second level zVM
                foreach my $vm(sort keys %{$tree{$cec}{$lpar}}) {
                    if ($vm eq $parent) {
                        # Add VM branch
                        $tree{$cec}{$lpar}{$parent}{$node} = {};
                        $found = 1;
                        last;
                    }
                } # End of foreach zVM
            } # End of foreach LPAR
            
            # Exit loop if LPAR branch added
            if ($found) {
                last;
            }
        } # End of foreach CEC
    }
    
    # Get VM entries
    # There should be many of these nodes
    $found = 0;
    @entries = $tab->getAllAttribsWhere( "nodetype = 'vm'", 'node', 'parent', 'userid' );
    foreach (@entries) {
        $node = $_->{'node'};        # VM
        $parent = $_->{'parent'};    # zVM
        
        # Skip node if it is not in noderange
        if (!xCAT::zvmUtils->inArray($node, @nodes)) {
            next;
        }
        
        # Find CEC/LPAR root based on zVM
        # CEC -> LPAR -> zVM
        $found = 0;
        foreach my $cec(sort keys %tree) {
            foreach my $lpar(sort keys %{$tree{$cec}}) {
                foreach my $zvm(sort keys %{$tree{$cec}{$lpar}}) {
                    if ($zvm eq $parent) {
                        # Add zVM branch
                        $tree{$cec}{$lpar}{$parent}{$node} = $_->{'userid'};
                        $found = 1;
                        last;
                    }
                    
                    # Handle second level zVM
                    foreach my $vm(sort keys %{$tree{$cec}{$lpar}{$zvm}}) {
                        if ($vm eq $parent) {
                            # Add VM branch
                            $tree{$cec}{$lpar}{$zvm}{$parent}{$node} = $_->{'userid'};
                            $found = 1;
                            last;
                        }
                    } # End of foreach VM
                } # End of foreach zVM
                
                # Exit loop if zVM branch added
                if ($found) {
                    last;
                }
            } # End of foreach LPAR
            
            # Exit loop if zVM branch added
            if ($found) {
                last;
            }
        } # End of foreach CEC
    } # End of foreach VM node

    # Print tree
    # Loop through CECs
    foreach my $cec(sort keys %tree) {
        xCAT::zvmUtils->printLn( $callback, "CEC: $cec" );
        
        # Loop through LPARs
        foreach my $lpar(sort keys %{$tree{$cec}}) {
            xCAT::zvmUtils->printLn( $callback, "|__LPAR: $lpar" );
            
            # Loop through zVMs
            foreach my $zvm(sort keys %{$tree{$cec}{$lpar}}) {
                if ($ssi{$zvm}) {
                    xCAT::zvmUtils->printLn( $callback, "   |__zVM: $zvm ($ssi{$zvm})" );
                } else {
                    xCAT::zvmUtils->printLn( $callback, "   |__zVM: $zvm" );
                }
                
                # Loop through VMs
                foreach my $vm(sort keys %{$tree{$cec}{$lpar}{$zvm}}) {
                    # Handle second level zVM
                    if (ref($tree{$cec}{$lpar}{$zvm}{$vm}) eq 'HASH') {
                        if ($ssi{$zvm}) {
                            xCAT::zvmUtils->printLn( $callback, "      |__zVM: $vm ($ssi{$zvm})" );
                        } else {
                            xCAT::zvmUtils->printLn( $callback, "      |__zVM: $vm" );
                        }                
                        
                        foreach my $vm2(sort keys %{$tree{$cec}{$lpar}{$zvm}{$vm}}) {
                            xCAT::zvmUtils->printLn( $callback, "         |__VM: $vm2 ($tree{$cec}{$lpar}{$zvm}{$vm}{$vm2})" );
                        }
                    } else {
                        xCAT::zvmUtils->printLn( $callback, "      |__VM: $vm ($tree{$cec}{$lpar}{$zvm}{$vm})" );
                    }
                } # End of foreach VM
            } # End of foreach zVM
        } # End of foreach LPAR
    } # End of foreach CEC
    return;
}

#-------------------------------------------------------

=head3   changeHypervisor

    Description : Configure the virtualization hosts
    Arguments   :   Node
                    Arguments
    Returns     : Nothing
    Example     : changeHypervisor($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub changeHypervisor {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }
    
    # Get zHCP shortname because $hcp could be zhcp.endicott.ibm.com
    my $hcpNode = $hcp;
    if ($hcp =~ /./) {
        my @tmp = split(/\./, $hcp);
        $hcpNode = $tmp[0];  # Short hostname of zHCP
    }
    
    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Output string
    my $out = "";
        
    # adddisk2pool [function] [region] [volume] [group]
    if ( $args->[0] eq "--adddisk2pool" ) {
        my $funct   = $args->[1];
        my $region  = $args->[2];
        my $volume  = "";
        my $group   = "";
        
        # Create an array for regions
        my @regions;
        if ( $region =~ m/,/i ) {
            @regions = split( ',', $region );
        } else {
            push( @regions, $region );
        }
        
        my $tmp;
        foreach (@regions) {
            $_ = xCAT::zvmUtils->trimStr($_);
            
            # Define region as full volume and add to group
            if ($funct eq "4") {
                $volume = $args->[3];                
                # In case multiple regions/volumes are specified, just use the same name
                if (scalar(@regions) > 1) {
                    $volume = $_;
                }
                
                $group  = $args->[4];
                $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -v $volume -p $group -y 0"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -v $volume -p $group -y 0");
            }
            
            # Add existing region to group
            elsif($funct eq "5") {
                $group = $args->[3];
                $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -p $group -y 0"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -p $group -y 0");
            }
            
            $out .= $tmp;
        }
    }
    
    # addeckd [dev_no]
    elsif ( $args->[0] eq "--addeckd" ) {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $devNo = "dev_num=" . $args->[1];
        
        # Add an ECKD disk to a running z/VM system
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Add -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_Disk_Add -T $hcpUserId -k $devNo");
    }
        
    # addscsi [dev_no] [dev_path] [option] [persist]
    elsif ( $args->[0] eq "--addscsi" ) {
        # Sample command would look like: chhypervisor zvm62 --addscsi 12A3 "1,0x123,0x100;2,0x123,0x101" 1 NO
        my $argsSize = @{$args};
        if ($argsSize < 3 && $argsSize > 5) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Option can be: (1) Add new SCSI (default), (2) Add new path, or (3) Delete path
        if ($args->[3] != 1 && $args->[3] !=2 && $args->[3] !=3) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Options can be one of the following:\n  (1) Add new SCSI disk (default)\n  (2) Add new path to existing disk\n  (3) Delete path from existing disk" );
            return;
        }
        
        # Persist can be: (YES) SCSI device updated in active and configured system, or (NO) SCSI device updated only in active system
        if ($argsSize > 3 && $args->[4] ne "YES" && $args->[4] ne "NO") {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Persist can be one of the following:\n  (YES) SCSI device updated in active and configured system\n  (NO) SCSI device updated only in active system" );
            return;
        }
        
        my $devNo = "dev_num=" . $args->[1];
                
        # Device path array, each device separated by semi-colon
        # e.g. fcp_devno1 fcp_wwpn1 fcp_lun1; fcp_devno2 fcp_wwpn2 fcp_lun2;
        my @fcps;
        if ($args->[2] =~ m/;/i) {
            @fcps = split( ';', $args->[2] );
        } else {
            push( @fcps, $args->[2] );
        }
        
        # Append the correct prefix
        my @fields;
        my $pathStr = "";
        foreach (@fcps) {
            @fields = split( ',', $_ );
            $pathStr .= "fcp_dev_num=$fields[0] fcp_wwpn=$fields[1] fcp_lun=$fields[2];";
        }
        
        
        my $devPath = "dev_path_array='" . $pathStr . "'";
        
        my $option = "option=" . $args->[3];
        my $persist = "persist=" . $args->[4];

        # Add disk to running system
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_SCSI_Disk_Add -T $hcpUserId -k $devNo -k $devPath -k $option -k $persist"`;
        xCAT::zvmUtils->printSyslog("smcli System_SCSI_Disk_Add -T $hcpUserId -k $devNo -k $devPath -k $option -k $persist");
    }
    
    # addvlan [name] [owner] [type] [transport]
    elsif ( $args->[0] eq "--addvlan" ) {
        my $name = $args->[1];
        my $owner = $args->[2];
        my $type = $args->[3];
        my $transport = $args->[4];
        
        my $argsSize = @{$args};
        if ($argsSize != 5) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }

        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_LAN_Create -T $hcpUserId -n $name -o $owner -t $type -p $transport"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_LAN_Create -T $hcpUserId -n $name -o $owner -t $type -p $transport");
    }
    
    # addvswitch [name] [osa_dev_addr] [port_name] [controller] [connect (0, 1, or 2)] [memory_queue] [router] [transport] [vlan_id] [port_type] [update] [gvrp] [native_vlan]
    elsif ( $args->[0] eq "--addvswitch" ) {
        my $i;
        my $argStr = "";
        
        my $argsSize = @{$args};
        if ($argsSize < 5) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my @options = ("", "-n", "-r", "-a", "-i", "-c", "-q", "-e", "-t", "-v", "-p", "-u", "-G", "-V");
        foreach $i ( 1 .. $argsSize ) {
            if ( $args->[$i] ) {
                # Prepend options prefix to argument
                $argStr .= "$options[$i] $args->[$i] ";
            }
        }

        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Vswitch_Create -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Vswitch_Create -T $hcpUserId $argStr");
    }
    
    # addzfcp2pool [pool] [status] [wwpn] [lun] [size] [range (optional)] [owner (optional)]
    elsif ( $args->[0] eq "--addzfcp2pool" ) {
        # zFCP disk pool located on zHCP at /var/opt/zhcp/zfcp/{pool}.conf 
        # Entries contain: status,wwpn,lun,size,range,owner,channel,tag
        my $pool = $args->[1];
        my $status = $args->[2];
        my $wwpn = $args->[3];
        my $lun = $args->[4];
        my $size = $args->[5];
        
        my $argsSize = @{$args};
        if ($argsSize < 6 || $argsSize > 8) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Size can be M(egabytes) or G(igabytes)
        if ($size =~ m/G/i || $size =~ m/M/i || !$size) {
            # Do nothing
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Size not recognized. Size can be M(egabytes) or G(igabytes).");
            return;
        }
        
        # Status can be free/used/reserved
        chomp($status);
        if ($status !~ m/^(free|used|reserved)$/i) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Status not recognized. Status can be free, used, or reserved.");
            return;
        }
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, '"', "");  # Strip off enclosing quotes
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        if ($wwpn =~ /[^0-9a-f;"]/i) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid world wide portname $wwpn." );
            return;
        }
        if ($lun =~ /[^0-9a-f]/i) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid logical unit number $lun." );
            return;
        }
        
        # You cannot have a unique SCSI/FCP device in multiple pools
        my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO grep -i -l \",$wwpn,$lun\" $::ZFCPPOOL/*.conf"`);
        if (scalar(@pools)) {
            foreach (@pools) {
                my $otherPool = basename($_);
                $otherPool =~ s/\.[^.]+$//;  # Do not use extension
                
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) zFCP device $wwpn/$lun already exists in $otherPool." );
            }
            
            return;
        }
        
        # Optional parameters
        my $range = "";
        my $owner = "";
        if ($argsSize > 6) {
            $range = $args->[6];
        } if ($argsSize > 7) {
            $owner = $args->[7];
        }
        
        # Verify syntax of FCP channel range
        if ($range =~ /[^0-9a-f\-;]/i) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid FCP device range. An acceptable range can be specified as 1A80-1B90 or 1A80-1B90;2A80-2B90." );
            return;
        }
        
        # Owner must be specified if status is used
        if ($status =~ m/used/i && !$owner) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Owner must be specified if status is used." );
            return;
        }

        # Find disk pool (create one if non-existent)
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO test -d $::ZFCPPOOL && echo Exists"`)) {
            # Create pool directory
            $out = `ssh $::SUDOER\@$hcp "$::SUDO mkdir -p $::ZFCPPOOL"`;
        }
                
        # Change the file owner if using a sudoer 
        if ($::SUDOER ne "root") {
            my $priv = xCAT::zvmUtils->trimStr(`ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/stat -c \"%G:%U\" /var/opt/zhcp"`);
            if (!($priv =~ m/$::SUDOER:users/i)) {
                `ssh $::SUDOER\@$hcp "$::SUDO chown -R $::SUDOER:users /var/opt/zhcp"`;
            }
        }
        
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO test -e $::ZFCPPOOL/$pool.conf && echo Exists"`)) {                
            # Create pool configuration file
            $out = `ssh $::SUDOER\@$hcp "$::SUDO echo '#status,wwpn,lun,size,range,owner,channel,tag' > $::ZFCPPOOL/$pool.conf"`;
            xCAT::zvmUtils->printLn( $callback, "$node: New zFCP device pool $pool created" );
        }
        
        # Update file with given WWPN, LUN, size, and owner
        my $entry = "'" . "$status,$wwpn,$lun,$size,$range,$owner,," . "'";
        $out = `ssh $::SUDOER\@$hcp "$::SUDO echo $entry >> $::ZFCPPOOL/$pool.conf"`;
        xCAT::zvmUtils->printLn( $callback, "$node: Adding zFCP device to $pool pool... Done" );
        $out = "";
    }
    
    # copyzfcp [device address (or auto)] [source wwpn] [source lun] [target wwpn (optional)] [target lun (option)]
    elsif ( $args->[0] eq "--copyzfcp" ) {
    	my $fcpDevice = $args->[1];
        my $srcWwpn = $args->[2];
        my $srcLun = $args->[3];
        
        my $argsSize = @{$args};
        if ($argsSize != 4 && $argsSize != 6) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
                
        # Check if WWPN and LUN are given
        my $useWwpnLun = 0;
        my $tgtWwpn;
        my $tgtLun;
        if ($argsSize == 6) {
            $useWwpnLun = 1;
            $tgtWwpn = $args->[4];
            $tgtLun = $args->[5];
        
            # Make sure WWPN and LUN do not have 0x prefix
            $tgtWwpn = xCAT::zvmUtils->replaceStr($tgtWwpn, "0x", "");
            $tgtLun = xCAT::zvmUtils->replaceStr($tgtLun, "0x", "");           
        }
        
        # Find the pool that contains the SCSI/FCP device
        my $pool = xCAT::zvmUtils->findzFcpDevicePool($::SUDOER, $hcp, $srcWwpn, $srcLun);
        if (!$pool) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to find FCP device in any zFCP storage pool" );
            return;
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: Found FCP device in $pool" );
        }
                
        # Get source device's attributes
        my $srcDiskRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $srcWwpn, $srcLun);
        my %srcDisk = %$srcDiskRef;
        if (!defined($srcDisk{'lun'}) && !$srcDisk{'lun'}) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Source zFCP device $srcWwpn/$srcLun does not exists" );
            return;
        }
        my $srcSize = $srcDisk{'size'};
        
        # If target disk is specified, check whether it is large enough
        my $tgtSize;
        if ($useWwpnLun) {
        	my $tgtDiskRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $tgtWwpn, $tgtLun);
            my %tgtDisk = %$tgtDiskRef;
            if (!defined($tgtDisk{'lun'}) && !$tgtDisk{'lun'}) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Target zFCP device $tgtWwpn/$tgtLun does not exists" );
                return;
            }
            $tgtSize = $tgtDisk{'size'};
        
            # Convert size unit to M for comparision
            if ($srcSize =~ m/G/i) {
                $srcSize =~ s/\D//g;
                $srcSize = int($srcSize) * 1024
            }
            if ($tgtSize =~ m/G/i) {
                $tgtSize =~ s/\D//g;
                $tgtSize = int($srcSize) * 1024
            }
        
            if ($tgtSize < $srcSize) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Target zFCP device $tgtWwpn/$tgtLun is not large enough" );
                return;
            }
        }
 
        # Attach source disk to zHCP
        $out = `/opt/xcat/bin/chvm $hcpNode --addzfcp $pool $fcpDevice 0 $srcSize "" $srcWwpn $srcLun | sed 1d`;
        if ($out !~ /Done/) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source zFCP device $srcWwpn/$srcLun cannot be attached");
            return;
        }
        
        # Obtain source FCP channel
        $out =~ /Adding zFCP device ([0-9a-f]*)\/([0-9a-f]*)\/([0-9a-f]*).*/;
        my $srcFcpDevice = lc($1);
        
        # Attach target disk to zHCP
        my $isTgtAttached = 0;
        if ($useWwpnLun) {
        	$out = `/opt/xcat/bin/chvm $hcpNode --addzfcp $pool $fcpDevice 0 $tgtSize "" $tgtWwpn $tgtLun | sed 1d`;
            if ($out !~ /Done/) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Target zFCP device $tgtWwpn/$tgtLun cannot be attached");
            } else {
                $isTgtAttached = 1;
            }        
        } else {
            # Try to obtain a target disk automatically if target disk is not specified
            $out = `/opt/xcat/bin/chvm $hcpNode --addzfcp $pool $fcpDevice 0 $srcSize | sed 1d`;
            if ($out !~ /Done/) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Cannot find a suitable target zFCP device");
            } else {
                $isTgtAttached = 1;
            }
        }
        
        # Obtain target disk FCP channel, WWPN, and LUN
        $out =~ /Adding zFCP device ([0-9a-f]*)\/([0-9a-f]*)\/([0-9a-f]*).*/;
        my $tgtFcpDevice = lc($1);
        $tgtWwpn = lc($2);
        $tgtLun = lc($3);
        
        if (!$isTgtAttached) {
            # Release source disk from zHCP
            $out = `/opt/xcat/bin/chvm $hcpNode --removezfcp $fcpDevice $srcWwpn $srcLun 0`;
            return;
        }

        # Get device node of source disk and target disk
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/readlink /dev/disk/by-path/ccw-0.0.$srcFcpDevice-zfcp-0x$srcWwpn:0x$srcLun"`;
        chomp($out);
        my @srcDiskInfo = split('/', $out);
        my $srcDiskNode = pop(@srcDiskInfo);
        chomp($out);
        xCAT::zvmUtils->printLn( $callback, "$node: Device name of $tgtFcpDevice/$srcWwpn/$srcLun is $srcDiskNode");
        
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/readlink /dev/disk/by-path/ccw-0.0.$tgtFcpDevice-zfcp-0x$tgtWwpn:0x$tgtLun"`;
        chomp($out);
        my @tgtDiskInfo = split('/', $out);
        my $tgtDiskNode = pop(@tgtDiskInfo);
        chomp($tgtDiskNode);
        xCAT::zvmUtils->printLn( $callback, "$node: Device name of $tgtFcpDevice/$tgtWwpn/$tgtLun is $tgtDiskNode");
        
        my $presist = 0;
        my $rc = "Failed";
        if (!$srcDiskNode || !$tgtDiskNode) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not find device nodes for source or target disk.");
        } else {
            # Copy source disk to target disk (512 block size)
            xCAT::zvmUtils->printLn( $callback, "$node: Copying source disk ($srcDiskNode) to target disk ($tgtDiskNode)" );
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDiskNode of=/dev/$tgtDiskNode bs=512 oflag=sync && $::SUDO echo $?"`;
            $out = xCAT::zvmUtils->trimStr($out);
            if (int($out) != 0) {
                # If $? is not 0 then there was an error during Linux dd
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy /dev/$srcDiskNode");
            }
            
            $presist = 1;  # Keep target device as reserved
            $rc = "Done";
            
            # Sleep 2 seconds to let the system settle
            sleep(2);
        }
        
        # Detatch source and target disks
        xCAT::zvmUtils->printLn($callback, "$node: Detatching source and target disks");
        $out = `/opt/xcat/bin/chvm $hcpNode --removezfcp $srcFcpDevice $srcWwpn $srcLun $presist`;
        $out = `/opt/xcat/bin/chvm $hcpNode --removezfcp $tgtFcpDevice $tgtWwpn $tgtLun $presist`;
        
        # Restore original source device attributes
        my %criteria = (
            'status' => $srcDisk{'status'},
            'wwpn' => $srcDisk{'wwpn'},
            'lun' => $srcDisk{'lun'},
            'size' => $srcDisk{'size'},
            'range' => $srcDisk{'range'},
            'owner' => $srcDisk{'owner'},
            'fcp' => $srcDisk{'fcp'},
            'tag' => $srcDisk{'tag'}
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;       
        if ($results{'rc'} == -1) {
            # Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source disk attributes cannot be restored in table");
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Copying zFCP device... $rc");
        if ($rc eq "Done") {
            xCAT::zvmUtils->printLn( $callback, "$node: Source disk copied onto zFCP device $tgtWwpn/$tgtLun");
        }
        $out = "";
    }
        
    # capturezfcp [profile] [wwpn] [lun]
    elsif ( $args->[0] eq "--capturezfcp" ) {
        my $profile  = $args->[1];
        my $wwpn = $args->[2];
        my $lun  = $args->[3];
                
        # Verify required properties are defined
        if (!defined($profile) || !defined($wwpn) || !defined($lun)) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing one or more of the required parameters: profile, wwpn, or lun" );
            return;
        }
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        
        # Obtain the location of the install root directory
        my $installRoot = xCAT::TableUtils->getInstallDir();
        
        xCAT::zvmUtils->printSyslog("changeHypervisor() Preparing the staging directory");
        
        # Create the staging area location for the image
        my $os = "unknown";  # Since we do not inspect the disk contents nor care
        my $provMethod = "raw";
        my $arch = "s390x";
        my $stagingImgDir = "$installRoot/staging/$os/$arch/$profile";
        
        if(-d $stagingImgDir) {
            unlink $stagingImgDir;
        }
        mkpath($stagingImgDir);
        
        # Prepare the staging mount point on zHCP, if they need to be established.
        my $remoteStagingDir;
        my $rc = xCAT::zvmUtils->establishMount($callback, $::SUDOER, $::SUDO, $hcp, "$installRoot/staging", "rw", \$remoteStagingDir);
        if ($rc) {
            # Mount failed.
            rmtree "$stagingImgDir";
            return;
        }
        
        # Find the pool that contains the SCSI/FCP device
        my $pool = xCAT::zvmUtils->findzFcpDevicePool($::SUDOER, $hcp, $wwpn, $lun);
        if (!$pool) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find FCP device in any zFCP storage pool");
            return;
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: Found FCP device in $pool");
        }
        
        # Get source device's attributes
        my $srcDiskRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $wwpn, $lun);
        my %srcDisk = %$srcDiskRef;
        if (!defined($srcDisk{'lun'}) && !$srcDisk{'lun'}) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source zFCP device $wwpn/$lun does not exists");
            return;
        }
        
        # Reserve the volume and associated FCP channel for the zHCP node
        my %criteria = (
           'status' => 'used',
           'fcp' => 'auto',
           'wwpn' => $wwpn,
           'lun' => $lun,
           'owner' => $hcpNode
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;
                
        my $device = $results{'fcp'};
        $wwpn = $results{'wwpn'};
        $lun = $results{'lun'};
        
        if ($results{'rc'} == -1) {
        	# Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device cannot be reserved");
            rmtree "$stagingImgDir";
            return;
        }
        
        xCAT::zvmUtils->printLn($callback, "$node: Capturing volume using zHCP node");
        
        # Drive the capture on the zHCP node
        xCAT::zvmUtils->printSyslog("changeHypervisor() creatediskimage $device 0x$wwpn/0x$lun $remoteStagingDir/$os/$arch/$profile/0x${wwpn}_0x${lun}.img");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/creatediskimage $device 0x$wwpn 0x$lun $remoteStagingDir/$os/$arch/$profile/${wwpn}_${lun}.img"`;
        $rc = $?;
        
        # Check for capture errors
        my $reasonString = "";
        $rc = xCAT::zvmUtils->checkOutputExtractReason($callback, $out, \$reasonString);
        if ($rc != 0) {
            my $reason = "Reason: $reasonString";
            xCAT::zvmUtils->printSyslog("changeHypervisor() creatediskimage of volume 0x$wwpn/0x$lun failed. $reason");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Image capture of volume 0x$wwpn/0x$lun failed on the zHCP node. $reason");
            rmtree "$stagingImgDir" ;
            return;
        }
        
        # Restore original source device attributes
        my %criteria = (
            'status' => $srcDisk{'status'},
            'wwpn' => $srcDisk{'wwpn'},
            'lun' => $srcDisk{'lun'},
            'size' => $srcDisk{'size'},
            'range' => $srcDisk{'range'},
            'owner' => $srcDisk{'owner'},
            'fcp' => $srcDisk{'fcp'},
            'tag' => $srcDisk{'tag'}
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;       
        if ($results{'rc'} == -1) {
            # Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source disk attributes cannot be restored in table");
        }
       
        my $imageName = "$os-$arch-$provMethod-$profile";    
        my $deployImgDir = "$installRoot/$provMethod/$os/$arch/$profile";
    
        xCAT::zvmUtils->printLn($callback, "$node: Moving the image files to the deployable directory: $deployImgDir");
      
        # Move the image directory to the deploy directory
        mkpath($deployImgDir);
    
        my @stagedFiles = glob "$stagingImgDir/*";
        foreach my $oldFile (@stagedFiles) {
            move($oldFile, $deployImgDir) or die "$node: (Error) Could not move $oldFile to $deployImgDir: $!\n";
        }
    
        # Remove the staging directory 
        rmtree "$stagingImgDir" ;

        xCAT::zvmUtils->printSyslog("changeHypervisor() Updating the osimage table");
    
        my $osTab = xCAT::Table->new('osimage',-create => 1,-autocommit => 0);
        my %keyHash;

        unless ($osTab) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to open table 'osimage'");
            return 0;
        }
    
        $keyHash{provmethod} = $provMethod;
        $keyHash{profile} = $profile;
        $keyHash{osvers} = $os;
        $keyHash{osarch} = $arch;
        $keyHash{imagetype} = 'linux';
        $keyHash{imagename} = $imageName;
    
        $osTab->setAttribs({imagename => $imageName }, \%keyHash);
        $osTab->commit;
    
        xCAT::zvmUtils->printSyslog("changeHypervisor() Updating the linuximage table");
    
        my $linuxTab = xCAT::Table->new('linuximage',-create => 1,-autocommit => 0);
    
        %keyHash = ();
        $keyHash{imagename} = $imageName;
        $keyHash{rootimgdir} = $deployImgDir;
    
        $linuxTab->setAttribs({imagename => $imageName }, \%keyHash );
        $linuxTab->commit;
    
        xCAT::zvmUtils->printLn($callback, "$node: Completed capturing the volume. Image($imageName) is stored at $deployImgDir");
        $out = "";
    }
    
    # deployzfcp [imageName] [wwpn] [lun]
    elsif ( $args->[0] eq "--deployzfcp" ) {
        my $imageName  = $args->[1];
        my $wwpn = $args->[2];
        my $lun  = $args->[3];
        
        # Verify required properties are defined
        if ( !defined($imageName) || !defined($wwpn) || !defined($lun)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing one or more arguments: image name, wwpn, or lun");
            return;
        }
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        
        # Obtain the location of the install root directory
        my $installRoot = xCAT::TableUtils->getInstallDir();
        
        # Build the image location from the image name
        my @nameParts = split('-', $imageName);
        if (!defined $nameParts[3]) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) The image name is not valid");
            return;
        }
        my $profile = $nameParts[3];
        my $os = "unknown";
        my $provMethod = "raw";
        my $arch = "s390x";
         
        my $deployImgDir = "$installRoot/$provMethod/$os/$arch/$profile";
        
        # Find the image filename.
        my $imageFile;
        my @imageFiles = glob "$deployImgDir/*.img";
        if (@imageFiles == 0) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) $deployImgDir does not contain image files");
            return;
        } elsif (@imageFiles > 1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) $deployImgDir contains more than the expected number of image files");
            return;
        } else {
            $imageFile = (split( '/', $imageFiles[0]))[-1];
        }
        
        # Prepare the deployable netboot mount point on zHCP, if they need to be established.
        my $remoteDeployDir;
        my $rc = xCAT::zvmUtils->establishMount($callback, $::SUDOER, $::SUDO, $hcp, "$installRoot/$provMethod", "ro", \$remoteDeployDir);
        if ($rc) {
            # Mount failed.
            return;
        }
        
        # Find the pool that contains the SCSI/FCP device
        my $pool = xCAT::zvmUtils->findzFcpDevicePool($::SUDOER, $hcp, $wwpn, $lun);
        if (!$pool) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find FCP device in any zFCP storage pool");
            return;
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: Found FCP device in $pool");
        }
        
        # Reserve the volume and associated FCP channel for the zHCP node.
        my %criteria = (
           'status' => 'used',
           'fcp' => 'auto',
           'wwpn' => $wwpn,
           'lun' => $lun,
           'owner' => $hcpNode
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;
        
        # Obtain the device assigned by xCAT
        my $device = $results{'fcp'};
        $wwpn = $results{'wwpn'};
        $lun = $results{'lun'};
        
        if ($results{'rc'} == -1) {
            # Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device cannot be reserved");
            return;
        }
        
        xCAT::zvmUtils->printLn($callback, "$node: Deploying volume using zHCP node");
        
        # Drive the deploy on the zHCP node
        xCAT::zvmUtils->printSyslog("changeHypervisor() unpackdiskimage $device 0x$wwpn 0x$lun $remoteDeployDir/$os/$arch/$profile/$imageFile");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/unpackdiskimage $device 0x$wwpn 0x$lun $remoteDeployDir/$os/$arch/$profile/$imageFile"`;
        $rc = $?;
        
        # Release the volume from the zHCP node
        %criteria = (
           'status' => 'reserved',
           'wwpn' => $wwpn,
           'lun' => $lun
        );
        $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        if ($results{'rc'} == -1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device cannot be released");
        }
        
        # Check for deploy errors
        my $reasonString = "";
        $rc = xCAT::zvmUtils->checkOutputExtractReason($callback, $out, \$reasonString);
        if ($rc != 0) {
            my $reason = "Reason: $reasonString";
            xCAT::zvmUtils->printSyslog("changeHypervisor() unpackdiskimage of volume 0x$wwpn/0x$lun failed. $reason");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Image deploy to volume 0x$wwpn/0x$lun failed on the zHCP node. $reason");
            return;
        }
        
        xCAT::zvmUtils->printLn($callback, "$node: Completed deploying image($imageName)");
        $out = "";
    }
    
    # removediskfrompool [function] [region] [group]
    elsif ( $args->[0] eq "--removediskfrompool" ) {
        my $funct  = $args->[1];
        my $region = $args->[2];
        my $group  = "";
        
        # Create an array for regions
        my @regions;
        if ( $region =~ m/,/i ) {
            @regions = split( ',', $region );
        } else {
            push( @regions, $region );
        }

        my $tmp;
        foreach ( @regions ) {
            $_ = xCAT::zvmUtils->trimStr($_);
            
            # Remove region from group | Remove entire group        
            if ($funct eq "2" || $funct eq "7") {
                $group  = $args->[3];
                $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Remove_DM -T $hcpUserId -f $funct -r $_ -g $group"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Remove_DM -T $hcpUserId -f $funct -r $_ -g $group");
            } 
            
            # Remove region | Remove region from all groups
            elsif ($funct eq "1" || $funct eq "3") {
                $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Remove_DM -T $hcpUserId -f $funct -r $_"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Remove_DM -T $hcpUserId -f $funct -r $_");
            }
            
            $out .= $tmp;
        }
    }
    
    # removescsi [device number] [persist (YES or NO)]
    elsif ( $args->[0] eq "--removescsi" ) {
        my $argsSize = @{$args};
        if ($argsSize != 3) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $devNo = "dev_num=" . $args->[1];
        my $persist = "persist=" . $args->[2];
        
        # Delete a real SCSI disk
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_SCSI_Disk_Delete -T $hcpUserId -k $devNo -k $persist"`;
        xCAT::zvmUtils->printSyslog("smcli System_SCSI_Disk_Delete -T $hcpUserId -k $devNo -k $persist");
    }
    
    # removevlan [name] [owner]
    elsif ( $args->[0] eq "--removevlan" ) {
        my $name = $args->[1];
        my $owner = $args->[2];
        
        # Delete a virtual network
        $out = `ssh $hcp "$::DIR/smcli Virtual_Network_LAN_Delete -T $hcpUserId -n $name -o $owner"`;
        xCAT::zvmUtils->printSyslog("ssh $hcp $::DIR/smcli Virtual_Network_LAN_Delete -T $hcpUserId -n $name -o $owner");
    }
    
    # removevswitch [name]
    elsif ( $args->[0] eq "--removevswitch" ) {
        my $name = $args->[1];
        
        # Delete a VSWITCH
        $out = `ssh $hcp "$::DIR/smcli Virtual_Network_Vswitch_Delete -T $hcpUserId -n $name"`;
        xCAT::zvmUtils->printSyslog("ssh $hcp $::DIR/smcli Virtual_Network_Vswitch_Delete -T $hcpUserId -n $name");
    }
    
    # removezfcpfrompool [pool] [lun] [wwpn (optional)]
    elsif ( $args->[0] eq "--removezfcpfrompool" ) {
        my $pool = $args->[1];
        my $lun = $args->[2];
        
        my $wwpn;
        my $argsSize = @{$args};
        if ($argsSize == 4) {
            $wwpn = $args->[3];
        } elsif ($argsSize > 4) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", ""); 
        $lun = xCAT::zvmUtils->replaceStr($lun, "0x", "");
        
        # Verify WWPN and LUN have the correct syntax
        if ($wwpn =~ /[^0-9a-f;"]/i) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid world wide port name $wwpn." );
            return;
        }
        if ($lun =~ /[^0-9a-f,]/i) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid logical unit number $lun." );
            return;
        }
        
        my @luns;
        if ($lun =~ m/,/i) {
            @luns = split( ',', $lun );
        } else {
            push(@luns, $lun);
        }
        
        # Find disk pool
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO test -e $::ZFCPPOOL/$pool.conf && echo Exists"`)) {                
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) zFCP pool does not exist" );
            return;
        }
            
        # Go through each LUN
        my $entry;
        my @args;
        foreach (@luns) {
            # Entry should contain: status, wwpn, lun, size, range, owner, channel, tag
            $entry =  xCAT::zvmUtils->trimStr(`ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf" | egrep -i $_`);
            # Do not update if LUN does not exists
            if (!$entry) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) zFCP device $_ does not exist" );
                return;
            }
            
            # Do not update if WWPN/LUN combo does not exists
            @args = split(',', $entry);
            if ($wwpn && !($args[1] =~ m/$wwpn/i)) {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) zFCP device $wwpn/$_ does not exists" );
                return;
            }
            
            # Update file with given WWPN and LUN
            $entry = "'" . $entry . "'";
            $out = xCAT::zvmUtils->rExecute($::SUDOER, $hcp, "sed -i -e /$entry/d $::ZFCPPOOL/$pool.conf");
            if ($wwpn) {
                xCAT::zvmUtils->printLn( $callback, "$node: Removing zFCP device $wwpn/$_ from $pool pool... Done" );
            } else {
                xCAT::zvmUtils->printLn( $callback, "$node: Removing zFCP device $_ from $pool pool... Done" );
            }
        }
        $out = "";
    }
    
    # releasezfcp [pool] [wwpn] [lun]
    elsif ( $args->[0] eq "--releasezfcp" ) {
        my $pool = lc($args->[1]);
        my $wwpn = lc($args->[2]);
        my $lun = lc($args->[3]);
                
        my $argsSize = @{$args};
        if ($argsSize != 4) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }
        
        my $device = "";
        
        # In case multiple LUNs are given, push LUNs into an array to be processed
        my @luns;
        if ($lun =~ m/,/i) {
            @luns = split( ',', $lun );
        } else {
            push(@luns, $lun);
        }
        
        # Go through each LUN
        foreach (@luns) {    
            my %criteria = (
               'status' => 'free',
               'wwpn' => $wwpn,
               'lun' => $_
            );
        
            my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
            my %results = %$resultsRef;
            if ($results{'rc'} == 0) {
                xCAT::zvmUtils->printLn($callback, "$node: Releasing FCP device... Done");
                xCAT::zvmUtils->printLn($callback, "$node: FCP device 0x$wwpn/0x$_ was released");
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: Releasing FCP device... Failed");
            }
        }
    }
    
    # reservezfcp [pool] [status] [owner] [device address (or auto)] [size] [wwpn (optional)] [lun (optional)]
    elsif ( $args->[0] eq "--reservezfcp" ) {
        my $pool = lc($args->[1]);        
        my $status = $args->[2];
        my $owner = $args->[3];
        my $device = $args->[4];
        my $size = $args->[5];
           
        my $argsSize = @{$args};
        if ($argsSize != 6 && $argsSize != 8) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Obtain the FCP device, WWPN, and LUN (if any)
        my $wwpn = "";
        my $lun = "";
        if ($argsSize == 8) {
        	$wwpn = lc($args->[6]);
        	$lun = lc($args->[7]);
        	
        	# Ignore the size if the WWPN and LUN are given
        	$size = "";
        }
        
        my %criteria;
        my $resultsRef;
        if ($wwpn && $lun) {
            %criteria = (
               'status' => $status,
               'fcp' => $device,
               'wwpn' => $wwpn,
               'lun' => $lun,
               'owner' => $owner
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        } else {
            # Do not know the WWPN or LUN in this case
            %criteria = (
               'status' => $status,
               'fcp' => $device,
               'size' => $size, 
               'owner' => $owner
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        }
        
        my %results = %$resultsRef;
        
        # Obtain the device assigned by xCAT
        $device = $results{'fcp'};
        $wwpn = $results{'wwpn'};
        $lun = $results{'lun'};
        
        if ($results{'rc'} == 0) {
            xCAT::zvmUtils->printLn($callback, "$node: Reserving FCP device... Done");
            xCAT::zvmUtils->printLn($callback, "$node: FCP device $device/0x$wwpn/0x$lun was reserved");
        } else {
        	xCAT::zvmUtils->printLn($callback, "$node: Reserving FCP device... Failed");
        }
    }
    
    # resetsmapi
    elsif ( $args->[0] eq "--resetsmapi" ) {
        # IMPORTANT:
        #   This option is only supported for class A privilege!
        #   We cannot change it to use SMAPI only because SMAPI cannot be used to restart itself.
        
        # Check for VSMGUARD in z/VM 6.2 or newer
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q users VSMGUARD"`;
        if (!($out =~ m/HCPCQU045E/i)) {
            # Force VSMGUARD and log it back on using XAUTOLOG
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp force VSMGUARD logoff immediate"`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp xautolog VSMGUARD"`;
        } else {
            # Assuming zVM 6.1 or older
            # Force each worker machine off
            my @workers = ('VSMWORK1', 'VSMWORK2', 'VSMWORK3', 'VSMREQIN', 'VSMREQIU');
            foreach ( @workers ) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp force $_ logoff immediate"`;
            }
                    
            # Log on VSMWORK1
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp xautolog VSMWORK1"`;
        }
              
        $out = "Resetting SMAPI... Done";
    }
    
    # smcli [api] [args]
    elsif ( $args->[0] eq "--smcli" ) {
        # Invoke SMAPI API directly through zHCP smcli
        my $str = "@{$args}";
        $str =~ s/$args->[0]//g;
        $str = xCAT::zvmUtils->trimStr($str);

        # Pass arguments directly to smcli
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli $str"`;
    }
    
    # Otherwise, print out error
    else {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Option not supported" );
    }
    
    # Only print if there is content
    if ($out) {
        $out = xCAT::zvmUtils->appendHostname( $node, $out );
        chomp($out);
        xCAT::zvmUtils->printLn( $callback, "$out" );
    }

    return;
}

#-------------------------------------------------------

=head3   inventoryHypervisor

    Description : Get hardware and software inventory of a given hypervisor
    Arguments   :   Node
                    Type of inventory (config|all)
    Returns     : Nothing
    Example     : inventoryHypervisor($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub inventoryHypervisor {

    # Get inputs
    my ( $callback, $node, $args ) = @_;
    
    # Set cache directory
    my $cache = '/var/opt/zhcp/cache';
    
    # Output string
    my $str = "";
    
    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node zHCP" );
        return;
    }
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Get the user Id of the zHCP
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);

    # Load VMCP module
    my $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/modprobe vmcp"`;

    # Get configuration
    if ( $args->[0] eq 'config' ) {        
        # Get total physical CPU in this LPAR
        my $lparCpuTotal = xCAT::zvmUtils->getLparCpuTotal($::SUDOER, $hcp);
        
        # Get used physical CPU in this LPAR
        my $lparCpuUsed = xCAT::zvmUtils->getLparCpuUsed($::SUDOER, $hcp);
        
        # Get LPAR memory total
        my $lparMemTotal = xCAT::zvmUtils->getLparMemoryTotal($::SUDOER, $hcp);
        
        # Get LPAR memory Offline
        my $lparMemOffline = xCAT::zvmUtils->getLparMemoryOffline($::SUDOER, $hcp);
        
        # Get LPAR memory Used
        my $lparMemUsed = xCAT::zvmUtils->getLparMemoryUsed($::SUDOER, $hcp);
        
        $str .= "z/VM Host: " . uc($node) . "\n";
        $str .= "zHCP: $hcp\n";
        $str .= "LPAR CPU Total: $lparCpuTotal\n";
        $str .= "LPAR CPU Used: $lparCpuUsed\n";
        $str .= "LPAR Memory Total: $lparMemTotal\n";        
        $str .= "LPAR Memory Used: $lparMemUsed\n";
        $str .= "LPAR Memory Offline: $lparMemOffline\n";
    } elsif ( $args->[0] eq 'all' ) {
        # Get total physical CPU in this LPAR
        my $lparCpuTotal = xCAT::zvmUtils->getLparCpuTotal($::SUDOER, $hcp);
        
        # Get used physical CPU in this LPAR
        my $lparCpuUsed = xCAT::zvmUtils->getLparCpuUsed($::SUDOER, $hcp);
        
        # Get CEC model
        my $cecModel = xCAT::zvmUtils->getCecModel($::SUDOER, $hcp);
        
        # Get vendor of CEC
        my $cecVendor = xCAT::zvmUtils->getCecVendor($::SUDOER, $hcp);
        
        # Get hypervisor type and version
        my $hvInfo = xCAT::zvmUtils->getHypervisorInfo($::SUDOER, $hcp);
        
        # Get processor architecture
        my $arch = xCAT::zvmUtils->getArch($::SUDOER, $hcp);
        
        # Get hypervisor name
        my $host = xCAT::zvmCPUtils->getHost($::SUDOER, $hcp);
        
        # Get LPAR memory total
        my $lparMemTotal = xCAT::zvmUtils->getLparMemoryTotal($::SUDOER, $hcp);
        
        # Get LPAR memory Offline
        my $lparMemOffline = xCAT::zvmUtils->getLparMemoryOffline($::SUDOER, $hcp);
        
        # Get LPAR memory Used
        my $lparMemUsed = xCAT::zvmUtils->getLparMemoryUsed($::SUDOER, $hcp);
        
        # Create output string
        $str .= "z/VM Host: " . uc($node) . "\n";
        $str .= "zHCP: $hcp\n";
        $str .= "Architecture: $arch\n";
        $str .= "CEC Vendor: $cecVendor\n";
        $str .= "CEC Model: $cecModel\n";
        $str .= "Hypervisor OS: $hvInfo\n";
        $str .= "Hypervisor Name: $host\n";        
        $str .= "LPAR CPU Total: $lparCpuTotal\n";
        $str .= "LPAR CPU Used: $lparCpuUsed\n";
        $str .= "LPAR Memory Total: $lparMemTotal\n";        
        $str .= "LPAR Memory Used: $lparMemUsed\n";
        $str .= "LPAR Memory Offline: $lparMemOffline\n";
    } 
    
    # diskpoolspace
    elsif ( $args->[0] eq '--diskpoolspace' ) {
        # Check whether disk pool was given
        my @pools;
        if (!$args->[1]) {
            # Get all known disk pool names
            $out = `rinv $node --diskpoolnames`;
            $out =~ s/$node: //g;
            $out = xCAT::zvmUtils->trimStr($out);
            @pools = split('\n', $out);
        } else {
            my $pool = uc($args->[1]);
            push(@pools, $pool);
            
            # Check whether disk pool is a valid pool     
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Query_DM -q 1 -e 3 -n $pool -T $hcpUserId" | grep "Failed"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Query_DM -q 1 -e 3 -n $pool -T $hcpUserId");
            if ($out) {
                 xCAT::zvmUtils->printLn( $callback, "$node: Disk pool $pool does not exist" );
                 return;
            }
        }
        
        # Go through each pool and find it's space
        foreach(@pools) {
            # Skip empty pool
            if (!$_) {
                next;
            }            
             
            my $free = xCAT::zvmUtils->getDiskPoolFree($::SUDOER, $hcp, $_);
            my $used = xCAT::zvmUtils->getDiskPoolUsed($::SUDOER, $hcp, $_);
            my $total = $free + $used;
            
            # Change the output format from cylinders to 'G' or 'M'
            $total = xCAT::zvmUtils->getSizeFromCyl($total);
            $used = xCAT::zvmUtils->getSizeFromCyl($used);
            $free = xCAT::zvmUtils->getSizeFromCyl($free);
            
            $str .= "$_ Total: $total\n";
            $str .= "$_ Used: $used\n";
            $str .= "$_ Free: $free\n";
        }
    }
    
    # diskpool [pool] [all|free|used]
    elsif ( $args->[0] eq "--diskpool" ) {
        # Get disk pool configuration
        my $pool  = $args->[1];
        my $space = $args->[2];

        if ($space eq "all" || !$space) {
            $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/getdiskpool $hcpUserId $pool free"`;
            
            # Delete 1st line which is header
            $str .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/getdiskpool $hcpUserId $pool used" | sed 1d`;
        } else {
            $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/getdiskpool $hcpUserId $pool $space"`;
        }
    }
    
    # diskpoolnames
    elsif ( $args->[0] eq "--diskpoolnames" ) {
        # Get disk pool names
        # If the cache directory does not exist
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO test -d $cache && echo Exists"`)) {
            # Create cache directory
            $out = `ssh $::SUDOER\@$hcp "$::SUDO mkdir -p $cache"`;
        }
        
        my $file = "$cache/diskpoolnames";
        
        # If a cache for disk pool names exists
        if (`ssh $::SUDOER\@$hcp "$::SUDO ls $file"`) {
            # Get current Epoch
            my $curTime = time();
            # Get time of last change as seconds since Epoch
            my $fileTime = xCAT::zvmUtils->trimStr(`ssh $::SUDOER\@$hcp "$::SUDO stat -c %Z $file"`);
            
            # If the current time is greater than 5 minutes of the file timestamp
            my $interval = 300;        # 300 seconds = 5 minutes * 60 seconds/minute
            if ($curTime > $fileTime + $interval) {
                # Get disk pool names and save it in a file
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/getdiskpoolnames $hcpUserId > $file"`;
            }
        } else {
            # Get disk pool names and save it in a file
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/getdiskpoolnames $hcpUserId > $file"`;
        }
        
        # Print out the file contents
        $str = `ssh $::SUDOER\@$hcp "$::SUDO cat $file"`;
    }
    
    # fcpdevices [active|free|offline] [details (optional)]
    elsif ( $args->[0] eq "--fcpdevices" ) {        
        my $argsSize = @{$args};
        my $space = $args->[1]; 
        my $details = 0;
        if ($argsSize == 3 && $args->[2] eq "details") {
            $details = 1;
        }
            
        # Display the status of real FCP Adapter devices using System_WWPN_Query
        my @devices;
        my $i;
        my $devNo;
        my $status;
        if ($space eq "active" || $space eq "free" || $space eq "offline") {
            if ($details) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_WWPN_Query -T $hcpUserId"`;
                xCAT::zvmUtils->printSyslog("smcli System_WWPN_Query -T $hcpUserId");
                
                @devices = split( "\n", $out );                
                for ($i = 0; $i < @devices; $i++) {
                    # Extract the device number and status
                    $devNo = $devices[$i];
                    $devNo =~ s/^FCP device number:(.*)/$1/;
                    $devNo =~ s/^\s+//;
                    $devNo =~ s/\s+$//;
                    
                    $status = $devices[$i + 1];
                    $status =~ s/^Status:(.*)/$1/;
                    $status =~ s/^\s+//;
                    $status =~ s/\s+$//;                    
                        
                    # Only print out devices matching query
                    if ($status =~ m/$space/i) {
                        $str .= "$devices[$i]\n";
                        $str .= "$devices[$i + 1]\n";
                        $str .= "$devices[$i + 2]\n";
                        $str .= "$devices[$i + 3]\n";
                        $str .= "$devices[$i + 4]\n";
                        $i = $i + 4;
                    }
                }
            } else {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_WWPN_Query -T $hcpUserId" | egrep -i "FCP device number|Status"`;
                xCAT::zvmUtils->printSyslog("smcli System_WWPN_Query -T $hcpUserId | egrep -i FCP device number|Status");
                
                @devices = split( "\n", $out );
                for ($i = 0; $i < @devices; $i++) {
                    # Extract the device number and status
                    $devNo = $devices[$i];
                    $devNo =~ s/^FCP device number:(.*)/$1/;
                    $devNo =~ s/^\s+//;
                    $devNo =~ s/\s+$//;
                        
                    $i++;
                    $status = $devices[$i];
                    $status =~ s/^Status:(.*)/$1/;
                    $status =~ s/^\s+//;
                    $status =~ s/\s+$//;                    
                        
                    # Only print out devices matching query
                    if ($status =~ m/$space/i) {
                        $str .= "$devNo\n";
                    }
                }
            }
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Query supported on active, free, or offline devices" );
        }
    }
    
    # luns [fcp_device] (supported only on z/VM 6.2)
    elsif ( $args->[0] eq "--luns" ) {
        # Find the LUNs accessible thru given zFCP device
        my $fcp  = lc($args->[1]);
        my $argsSize = @{$args};
        if ($argsSize < 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
         
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp" | egrep -i "FCP device number:|World wide port number:|Logical unit number:|Number of bytes residing on the logical unit:"`;
        xCAT::zvmUtils->printSyslog("smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp | egrep -i FCP device number:|World wide port number:|Logical unit number:|Number of bytes residing on the logical unit:");
        
        my @wwpns = split( "\n", $out );
        my %map;
        
        my $wwpn = "";
        my $lun = "";
        my $size = "";
        foreach (@wwpns) {
            # Extract the device number
            if ($_ =~ "World wide port number:") {
                $_ =~ s/^\s+World wide port number:(.*)/$1/;
                $_ =~ s/^\s+//;
                $_ =~ s/\s+$//;
                $wwpn = $_;
                 
                if (!scalar($map{$wwpn})) {
                    $map{$wwpn} = {};
                }                
            } elsif ($_ =~ "Logical unit number:") {
                $_ =~ s/^\s+Logical unit number:(.*)/$1/;
                $_ =~ s/^\s+//;
                $_ =~ s/\s+$//;
                $lun = $_;
                
                $map{$wwpn}{$lun} = "";
            } elsif ($_ =~ "Number of bytes residing on the logical unit:") {
                $_ =~ s/^\s+Number of bytes residing on the logical unit:(.*)/$1/;
                $_ =~ s/^\s+//;
                $_ =~ s/\s+$//;
                $size = $_;
                
                $map{$wwpn}{$lun} = $size;
            }
        }
        
        xCAT::zvmUtils->printLn($callback, "#status,wwpn,lun,size,range,owner,channel,tag");
        foreach $wwpn (sort keys %map) {
            foreach $lun (sort keys %{$map{$wwpn}}) {
                # status, wwpn, lun, size, range, owner, channel, tag
                $size = sprintf("%.1f", $map{$wwpn}{$lun}/1073741824);  # Convert size to GB
                
                if ($size > 0) {
                    $size .= "G";
                   xCAT::zvmUtils->printLn($callback, "unknown,$wwpn,$lun,$size,,,,"); 
                }
            }
        }
        
        $str = "";
    }
    
    # networknames
    elsif ( $args->[0] eq "--networknames" || $args->[0] eq "--getnetworknames" ) {
        $str = xCAT::zvmCPUtils->getNetworkNames($::SUDOER, $hcp);
    }

    # network [name]
    elsif ( $args->[0] eq "--network" || $args->[0] eq "--getnetwork" ) {
        my $netName = $args->[1];
        $str = xCAT::zvmCPUtils->getNetwork( $::SUDOER, $hcp, $netName );
    }
    
    # responsedata [failed Id]
    elsif ( $args->[0] eq "--responsedata" ) {
        # This has not be completed!
        my $failedId = $args->[1];
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Response_Recovery -T $hcpUserId -k $failedId"`;
        xCAT::zvmUtils->printSyslog("smcli Response_Recovery -T $hcpUserId -k $failedId");
    }
    
    # freefcp [fcp_dev]
    elsif ( $args->[0] eq "--freefcp" ) {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $fcp = "fcp_dev=" . $args->[1];
        
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k $fcp"`;
        xCAT::zvmUtils->printSyslog("smcli System_FCP_Free_Query -T $hcpUserId -k $fcp");
    }
    
    # scsidisk [dev_no]
    elsif ( $args->[0] eq "--scsidisk" ) {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $devNo = "dev_num=" . $args->[1];
        
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_SCSI_Disk_Query -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_SCSI_Disk_Query -T $hcpUserId -k $devNo");
    }
    
    # ssi
    elsif ( $args->[0] eq "--ssi" ) {      
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli SSI_Query"`;
        xCAT::zvmUtils->printSyslog("smcli SSI_Query");
    }
    
    # smapilevel
    elsif ( $args->[0] eq "--smapilevel" ) {
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Query_API_Functional_Level -T $hcpUserId"`;
        xCAT::zvmUtils->printSyslog("smcli Query_API_Functional_Level -T $hcpUserId");
    }
    
    # systemdisk [dev_no]
    elsif ( $args->[0] eq "--systemdisk" ) {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $devNo = "dev_num=" . $args->[1];
            
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Query -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_Disk_Query -T $hcpUserId -k $devNo");
    }
    
    # systemdiskaccessibility [dev_no]
    elsif ( $args->[0] eq "--systemdiskaccessibility" ) {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        my $devNo = "dev_num=" . $args->[1];
        
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Accessibility -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_Disk_Accessibility -T $hcpUserId -k $devNo");
    }
    
    # userprofilenames
    elsif ( $args->[0] eq "--userprofilenames" ) {
        my $argsSize = @{$args};
        if ($argsSize != 1) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
        
        # Use Directory_Manager_Search_DM to find user profiles
        my $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Directory_Manager_Search_DM -T $hcpUserId -s PROFILE"`;
        my @profiles = split('\n', $tmp);
        foreach (@profiles) {
            # Extract user profile
            if ($_) {
                $_ =~ /([a-zA-Z]*):*/;
                $str .= "$1\n";
            }
        }
        
        xCAT::zvmUtils->printSyslog("smcli Directory_Manager_Search_DM -T $hcpUserId -s PROFILE");
    }
    
    # vlanstats [vlan_id] [user_id] [device] [version]
    elsif ( $args->[0] eq "--vlanstats" ) {
        # This is not completed!
        my $argsSize = @{$args};
        if ($argsSize < 4 && $argsSize > 5) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
          
        my $vlanId = "VLAN_id=" . $args->[1];
        my $tgtUserId = "userid=" . $args->[2];
        my $device = "device=" . $args->[3];
        my $fmtVersion = "fmt_version=" . $args->[4];  # Optional
        
        my $argStr = "-k $vlanId -k $tgtUserId -k $device";
        if ($argsSize == 5) {
            $argStr .= " -k $fmtVersion"
        }
        
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_VLAN_Query_Stats -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_VLAN_Query_Stats -T $hcpUserId $argStr");
    }
    
    # vswitchstats [name] [version]
    elsif ( $args->[0] eq "--vswitchstats" ) {    
        my $argsSize = @{$args};
        if ($argsSize < 2 && $argsSize > 3) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
          
        my $switchName = "switch_name=" . $args->[1];
        my $fmtVersion = "fmt_version=" . $args->[2];  # Optional   
        my $argStr = "-k $switchName";
        
        if ($argsSize == 3) {
            $argStr .= " -k $fmtVersion"
        }
        
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Vswitch_Query_Stats -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Vswitch_Query_Stats -T $hcpUserId $argStr");
    }
    
    # wwpn [fcp_device] (supported only on z/VM 6.2)
    elsif ( $args->[0] eq "--wwpns" ) {
        my $fcp  = lc($args->[1]);
        my $argsSize = @{$args};
        if ($argsSize < 2) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
            return;
        }
         
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp" | egrep -i "World wide port number:"`;
        xCAT::zvmUtils->printSyslog("smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp | egrep -i World wide port number:");
        
        my @wwpns = split( "\n", $out );
        my %uniqueWwpns;
        foreach (@wwpns) {
            # Extract the device number
            if ($_ =~ "World wide port number:") {
                $_ =~ s/^\s+World wide port number:(.*)/$1/;
                $_ =~ s/^\s+//;
                $_ =~ s/\s+$//;
             
                # Save only unique WWPNs   
                $uniqueWwpns{$_} = 1;
            }
        }
        
        my $wwpn;
        for $wwpn ( keys %uniqueWwpns ) {
            $str .= "$wwpn\n";    
        }
    }
    
    # zfcppool [pool] [space]
    elsif ( $args->[0] eq "--zfcppool" ) {
        # Get zFCP disk pool configuration
        my $pool  = lc($args->[1]);
        my $space = $args->[2];

        if ($space eq "all" || !$space) {
            $str = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf"`;
        } else {
            $str = "#status,wwpn,lun,size,range,owner,channel,tag\n";
            $str .= `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf" | egrep -i $space`;
        }
    }
    
    # zfcppoolnames
    elsif ( $args->[0] eq "--zfcppoolnames") {
        # Get zFCP disk pool names
        # Go through each zFCP pool
        my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
        foreach (@pools) {
            $_ = xCAT::zvmUtils->replaceStr( $_, ".conf", "" );
            $str .= "$_\n";
        }
    }
    
    else {
        $str = "$node: (Error) Option not supported";
        xCAT::zvmUtils->printLn( $callback, "$str" );
        return;
    }

    # Append hostname (e.g. pokdev61) in front
    $str = xCAT::zvmUtils->appendHostname( $node, $str );

    xCAT::zvmUtils->printLn( $callback, "$str" );
    return;
}

#-------------------------------------------------------

=head3   migrateVM

    Description  : Migrate a virtual machine
    Arguments    :   Node
                     Destination
                     Immediate
                     Action (optional)
                     Max_total
                     Max_quiesce
                     Force (optional)
    Returns      : Nothing
    Example      : migrateVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub migrateVM {

    # Get inputs
    my ( $callback, $node, $args ) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get HCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }
    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;
    
    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    
    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;
    
    # Check required keys: target_identifier, destination, action, immediate, and max_total
    # Optional keys: max_quiesce, and force
    if (!$args || @{$args} < 4) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Wrong number of parameters" );
        return;
    }
    
    # Output string
    my $out;
    my $migrateCmd = "VMRELOCATE -T $userId";

    my $i;
    my $destination;
    my $action;
    my $value;
    foreach $i ( 0 .. 5 ) {
        if ( $args->[$i] ) {        
            # Find destination key
            if ( $args->[$i] =~ m/destination=/i ) {
                $destination = $args->[$i];
                $destination =~ s/destination=//g;
                $destination =~ s/"//g;
                $destination =~ s/'//g;
            } elsif ( $args->[$i] =~ m/action=/i ) {
                $action = $args->[$i];
                $action =~ s/action=//g;
            } elsif ( $args->[$i] =~ m/max_total=/i ) {
                $value = $args->[$i];
                $value =~ s/max_total=//g;
                
                # Strip leading zeros
                if (!($value =~ m/[^0-9.]/ )) {
                    $value =~ s/^0+//;
                    $args->[$i] = "max_total=$value";
                }
            } elsif ( $args->[$i] =~ m/max_quiesce=/i ) {
                $value = $args->[$i];
                $value =~ s/max_quiesce=//g;
                
                # Strip leading zeros
                if (!($value =~ m/[^0-9.]/ )) {
                    $value =~ s/^0+//;
                    $args->[$i] = "max_quiesce=$value";
                }
            }
            
            # Keys passed directly to smcli
            $migrateCmd .= " -k $args->[$i]"; 
        }
    }
        
    my $destHcp;
    if ($action =~ m/MOVE/i) {        
        # Find the zHCP for the destination host and set the node zHCP as it
        # Otherwise, it is up to the user to manually change the zHCP
        @propNames = ( 'hcp' );
        $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', lc($destination), @propNames );
        $destHcp = $propVals->{'hcp'};
        if ( !$destHcp ) {
                    
            # Try upper-case
            $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', uc($destination), @propNames );
            $destHcp = $propVals->{'hcp'};
        }
                
        if (!$destHcp) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to find zHCP of $destination" );
            xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Set the hcp appropriately in the zvm table" );
            return;
        }
    }
    
    # Begin migration
    $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli $migrateCmd"`;
    xCAT::zvmUtils->printSyslog("smcli $migrateCmd");
    xCAT::zvmUtils->printLn( $callback, "$node: $out" );
    
    # Check for errors on migration only
    my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
    if ( $rc != -1 && $action =~ m/MOVE/i) {
        
        # Check the migration status
        my $check = 4;
        my $isMigrated = 0;
        while ($check > 0) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli VMRELOCATE_Status -T $hcpUserId" -k status_target=$userId`;
            xCAT::zvmUtils->printSyslog("smcli VMRELOCATE_Status -T $hcpUserId -k status_target=$userId");
            if ( $out =~ m/No active relocations found/i ) {
                $isMigrated = 1;
                last;
            }
            
            $check--;
            sleep(10);
        }
        
        # Change the zHCP if migration successful
        if ($isMigrated) {
            `/opt/xcat/bin/nodech $node zvm.hcp=$destHcp zvm.parent=$destination`;
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: Could not determine progress of relocation" );
        }
    }
    
    return;
}

#-------------------------------------------------------

=head3   evacuate

    Description  : Evacuate all virtual machines off a hypervisor
    Arguments    : Node (hypervisor)
    Returns      : Nothing
    Example      : evacuate($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub evacuate {

    # Get inputs, e.g. revacuate pokdev62 poktst62
    my ( $callback, $node, $args ) = @_;
    
    # In order for this command to work, issue under /opt/xcat/bin: 
    # ln -s /opt/xcat/bin/xcatclient revacuate
    
    my $destination = $args->[0];
    if (!$destination) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing z/VM SSI cluster name of the destination system" );
        return;
    }

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'nodetype' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP of hypervisor
    my $srcHcp = $propVals->{'hcp'};
    if ( !$srcHcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }
    
    my $type = $propVals->{'nodetype'};
    if ($type ne 'zvm') {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Invalid nodetype" );
        xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Set the nodetype appropriately in the zvm table" );
        return;
    }
    
    my $destHcp;
    
    # Find the zHCP for the destination host and set the node zHCP as it
    # Otherwise, it is up to the user to manually change the zHCP
    @propNames = ( 'hcp' );
    $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', lc($destination), @propNames );
    $destHcp = $propVals->{'hcp'};
    if ( !$destHcp ) {                    
        # Try upper-case
        $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', uc($destination), @propNames );
        $destHcp = $propVals->{'hcp'};
    }
                
    if (!$destHcp) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to find zHCP of $destination" );
        xCAT::zvmUtils->printLn( $callback, "$node: (Solution) Set the hcp appropriately in the zvm table" );
        return;
    }
    
    # Get nodes managed by this zHCP
    # Look in 'zvm' table
    my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );
    my @entries = $tab->getAllAttribsWhere( "hcp like '%" . $srcHcp . "%' and nodetype=='vm'", 'node', 'userid' );
    
    my $out;
    my $iNode;
    my $iUserId;
    my $smcliArgs;
    my $nodes = "";
    foreach (@entries) {
        $iNode = $_->{'node'};
        $iUserId = $_->{'userid'};
        
        # Skip zHCP entry
        if ($srcHcp =~ m/$iNode./i || $srcHcp eq $iNode) {
            next;
        }
        
        $nodes .=  $iNode . ",";
    }
    
    # Strip last comma
    $nodes = substr($nodes, 0, -1);
    
    # Do not continue if no nodes to migrate
    if (!$nodes) {
        xCAT::zvmUtils->printLn( $callback, "$node: No nodes to evacuate" );
        return;
    }
        
    # Begin migration
    # Required keys: target_identifier, destination, action, immediate, and max_total
    $out = `/opt/xcat/bin/rmigrate $nodes action=MOVE destination=$destination immediate=NO max_total=NOLIMIT`;
    xCAT::zvmUtils->printLn( $callback, "$out" );
    
    return;
}

#-------------------------------------------------------

=head3   eventLog

    Description : Retrieve, clear, or set logging options for event logs
    Arguments   :   Node
                    Location of source log
                    Location to place log
    Returns     : Nothing
    Example     : eventLog($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub eventLog {

    # Get inputs
    my ( $callback, $node, $args ) = @_;
    
    my $srcLog = '';
    my $tgtLog = '';
    my $clear = 0;
    my $options = '';
    if ($args) {
        @ARGV = @$args;
        
        # Parse options
        GetOptions(
            's=s' => \$srcLog,
            't=s' => \$tgtLog,  # Optional
            'c' => \$clear,
            'o=s' => \$options);  # Set logging options        
    }
    
    # Event log required
    if (!$srcLog) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing event log" );
        return;
    }
    
    # Limit to logs in /var/log/* and configurations in /var/opt/*
    my $tmp = substr($srcLog, 0, 9);
    if ($tmp ne "/var/opt/" && $tmp ne "/var/log/") {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Files are restricted to those in /var/log and /var/opt" );
        return;
    }
    
    # Check if node is the management node
    my @entries = xCAT::TableUtils->get_site_attribute("master");
    my $master = xCAT::zvmUtils->trimStr($entries[0]);
    my $ip = xCAT::NetworkUtils->getipaddr($node);
    $ip = xCAT::zvmUtils->trimStr($ip);
    my $mn = 0;
    if ($master eq $ip) {
        # If the master IP and node IP match, then it is the management node
        xCAT::zvmUtils->printLn( $callback, "$node: This is the management node" );
        $mn = 1;
    }
    
    # Just clear the log
    my $out = '';
    if ($clear) {
        if ($mn) {
            $out = `cat /dev/null > $srcLog`;
        } else {
            $out = `ssh $::SUDOER\@$node "cat /dev/null > $srcLog"`;
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Clearing event log ($srcLog)... Done" );
        return;
    }
    
    # Just set the logging options
    if ($options) {
        if ($mn) {
            $out = `echo -e \"$options\" > $srcLog`;
        } else {
            $out = `echo -e \"$options\" > /tmp/$node.tracing`;
            $out = `ssh $::SUDOER\@$node "rm -rf $srcLog"`;
            $out = `cat /tmp/$node.tracing | ssh $::SUDOER\@$node "cat > /tmp/$node.tracing"`;
            $out = `ssh $::SUDOER\@$node "mv /tmp/$node.tracing $srcLog"`;
            $out = `rm -rf /tmp/$node.tracing`;
        }
        
        xCAT::zvmUtils->printLn( $callback, "$node: Setting event logging options... Done" );
        return;
    }
    
    # Default log location is /install/logs
    if (!$tgtLog) {
        my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
        my $install = $entries[0];
    
        $tgtLog = "$install/logs/";
        $out = `mkdir -p $tgtLog`;
    }
    
    # Copy over event log onto xCAT
    xCAT::zvmUtils->printLn( $callback, "$node: Retrieving event log ($srcLog)" );    
    if ($mn) {
        if (!(`test -e $srcLog && echo Exists`)) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Specified log does not exist" );
            return;
        }
        
        $out = `cp $srcLog $tgtLog`;
    } else {
        if (!(`ssh $::SUDOER\@$node "test -e $srcLog && echo Exists"`)) {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Specified log does not exist" );
            return;
        }
        
        $out = `scp $::SUDOER\@$node:$srcLog $tgtLog`;
    }
    
    if ( -e $tgtLog ) {
        xCAT::zvmUtils->printLn( $callback, "$node: Log copied to $tgtLog" );
        $out = `chmod -R 644 $tgtLog/*`;
    } else {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to copy log" );
    }    
}

#-------------------------------------------------------

=head3   imageCapture

    Description : Capture a disk image from a Linux system on z/VM.
    Arguments   : Node
                  OS
                  Archictecture
                  Profile
                  Device information
    Returns     : Nothing
    Example     : imageCapture( $callback, $node, $os, $arch, $profile, $osimg, $device );
    
=cut

#-------------------------------------------------------
sub imageCapture {
    my ($class, $callback, $node, $os, $arch, $profile, $osimg, $device) = @_;
    my $rc;
    my $out = '';
    my $reason = "";
    
    xCAT::zvmUtils->printSyslog( "imageCapture() $node:$node os:$os arch:$arch profile:$profile osimg:$osimg device:$device" );
    
    # Verify required properties are defined
    if (!defined($os) || !defined($arch) || !defined($profile)) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) One or more of the required properties is not specified: os version, architecture or profile" );
        return;
    }
    
    # Ensure the architecture property is 's390x'
    if ($arch ne 's390x') {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Architecture was $arch instead of 's390x'. 's390x' will be used instead of the specified value." );
        $arch = 's390x';
    }
    
    # Obtain the location of the install root directory
    my $installRoot = xCAT::TableUtils->getInstallDir();
    
    # Directory where executables are on zHCP.  
    # Using a local variable to hold the directory information because this routine is called from another module.
    my $dir = "/opt/zhcp/bin";
    
    # Use sudo or not
    # This looks in the passwd table for a key = sudoer
    my ($sudoer, $sudo) = xCAT::zvmUtils->getSudoer();
    
    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
    
    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }
    
    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;
    
    # Get capture target's user ID
    my $targetUserId = $propVals->{'userid'};
    $targetUserId =~ tr/a-z/A-Z/;
    
    # Get node properties from 'zvm' table
    @propNames = ( 'ip', 'hostnames' );
    $propVals = xCAT::zvmUtils->getNodeProps('hosts', $node, @propNames);
    
    # Check if node is pingable
    if (`/opt/xcat/bin/pping $node | egrep -i "noping"`) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Host is unreachable" );
        return;
    }
    
    my $vaddr;
    my $devName;
    # Set the default is device option was specified without any parameters.
    if (!$device) {
        $devName = "/dev/root";
    }
    
    # Obtain the device number from the target system.
    if ($devName eq '/dev/root') {
        # Determine which Linux device is associated with the root directory
        $out = `ssh $sudoer\@$node $sudo cat /proc/cmdline | tr " " "\\n" | grep "^root=" | cut -c6-`;
        if ($out) {
            $out = `ssh $sudoer\@$node $sudo "/usr/bin/readlink -f $out"`;
            if ($out) {
                $devName = substr($out, 5);
                $devName =~ s/\s+$//;
                $devName =~ s/\d+$//;
            } else {
                xCAT::zvmUtils->printLn( $callback, "$node: (Error) Unable locate the device associated with the root directory" );
                return;
            }
        } else {
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Unable locate the device associated with the root directory" );
            return;
        }
    } else {
        $devName = substr $devName, 5;
    }
    
    $vaddr = xCAT::zvmUtils->getDeviceNodeAddr($sudoer, $node, $devName);
    if (!$vaddr) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Unable determine the device being captured" );
        return 0;
    }
    
    # Shutdown and logoff the virtual machine so that its disks are stable for the capture step.
    xCAT::zvmUtils->printSyslog( "imageCapture() Shutting down $node prior to disk capture" );
    $out = `ssh -o ConnectTimeout=10 $node "shutdown -h now"`;
    sleep(15);  # Wait 15 seconds to let shutdown start before logging user off
    
    # If the OS is not shutdown and the machine is enabled for shutdown signals
    # then deactivate will cause CP to send the shutdown signal and
    # wait an additional (z/VM installation configurable) time before forcing 
    # the virtual machine off the z/VM system.
    xCAT::zvmUtils->printSyslog( "$sudo $dir/smcli Image_Deactivate -T $targetUserId" );
    $out = `ssh $sudoer\@$hcp "$sudo $dir/smcli Image_Deactivate -T $targetUserId"`;
    xCAT::zvmUtils->printSyslog( "imageCapture() smcli response: $out" );
    
    xCAT::zvmUtils->printSyslog( "imageCapture() Preparing the staging directory" );
    
    # Create the staging area location for the image
    my $stagingImgDir = "$installRoot/staging/$os/$arch/$profile";
    if(-d $stagingImgDir) {
        unlink $stagingImgDir;
    }
    mkpath($stagingImgDir);
    
    # Prepare the staging mount point on zHCP, if they need to be established.
    my $remoteStagingDir;
    $rc = xCAT::zvmUtils->establishMount( $callback, $sudoer, $sudo, $hcp, "$installRoot/staging", "rw", \$remoteStagingDir );
    if ($rc) {
        # Mount failed
        rmtree "$stagingImgDir";
        return;
    }
    
    xCAT::zvmUtils->printLn( $callback, "$node: Capturing the image using zHCP node" );
    
    # Drive the capture on the zHCP node
    xCAT::zvmUtils->printSyslog( "imageCapture() creatediskimage $targetUserId $vaddr $remoteStagingDir/$os/$arch/$profile/${vaddr}.img" );
    $out = `ssh $sudoer\@$hcp "$sudo $dir/creatediskimage $targetUserId $vaddr $remoteStagingDir/$os/$arch/$profile/${vaddr}.img"`;
    $rc = $?;
            
    # If the capture failed then clean up and return
    my $reasonString = "";
    $rc = xCAT::zvmUtils->checkOutputExtractReason( $callback, $out, \$reasonString );
    if ($rc != 0) {
        $reason = "Reason: $reasonString";
        xCAT::zvmUtils->printSyslog( "imageCapture() creatediskimage of $targetUserId $vaddr failed. $reason" );
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Image capture of $targetUserId $vaddr failed on the zHCP node. $reason" );
        rmtree "$stagingImgDir" ;
        return;
    }
    
    # Now that all image files have been successfully created, move them to the deployable directory.
    my $imageName = "$os-$arch-netboot-$profile";    
    my $deployImgDir = "$installRoot/netboot/$os/$arch/$profile";
    
    xCAT::zvmUtils->printLn( $callback, "$node: Moving the image files to the deployable directory: $deployImgDir" );
    
    my @stagedFiles = glob "$stagingImgDir/*.img";
    if (!@stagedFiles) {
        rmtree "$stagingImgDir";
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) No image files were created" );
        return 0;   
    }
    
    mkpath($deployImgDir);
    
    foreach my $oldFile (@stagedFiles) {
        $rc = move($oldFile, $deployImgDir);
        $reason = $!;
        if ($rc == 0) {
            # Move failed
            rmtree "$stagingImgDir";
            xCAT::zvmUtils->printLn( $callback, "$node: (Error) Could not move $oldFile to $deployImgDir. $reason" );
            return;
        }
    }
    
    # Remove the staging directory and files 
    rmtree "$stagingImgDir";
    
    xCAT::zvmUtils->printSyslog( "imageCapture() Updating the osimage table" );
    
    # Update osimage table
    my $osTab = xCAT::Table->new('osimage',-create => 1,-autocommit => 0);
    my %keyHash;

    unless ($osTab) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Unable to open table 'osimage'" );
        return;
    }
    
    $keyHash{provmethod} = 'netboot';
    $keyHash{profile} = $profile;
    $keyHash{osvers} = $os;
    $keyHash{osarch} = $arch;
    $keyHash{imagetype} = 'linux';
    $keyHash{osname} = 'Linux';
    $keyHash{imagename} = $imageName;
    
    $osTab->setAttribs({imagename => $imageName}, \%keyHash);
    $osTab->commit;
    
    xCAT::zvmUtils->printSyslog( "imageCapture() Updating the linuximage table" );
    
    # Update linuximage table
    my $linuxTab = xCAT::Table->new('linuximage',-create => 1,-autocommit => 0);
    
    %keyHash = ();
    $keyHash{imagename} = $imageName;
    $keyHash{rootimgdir} = $deployImgDir;
    
    $linuxTab->setAttribs({imagename => $imageName}, \%keyHash);
    $linuxTab->commit;
    
    xCAT::zvmUtils->printLn( $callback, "$node: Completed capturing the image($imageName) and stored at $deployImgDir" );

    return;
}
