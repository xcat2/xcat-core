# IBM(c) 2013-2016 EPL license http://www.eclipse.org/legal/epl-v10.html
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
use File::Temp;
use Time::HiRes;
use POSIX;
use Getopt::Long;
use strict;
use warnings;
use Cwd;

# builtin should be set to 1 if this is xcat built into z/VM
my $builtin;
$builtin = 1;

# If the following line ("1;")is not included, you get:
# /opt/xcat/lib/perl/xCAT_plugin/zvm.pm did not return a true value
1;

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        rpower       => 'nodehm:power,mgt',
        rinv         => 'nodehm:mgt',
        mkvm         => 'nodehm:mgt',
        rmvm         => 'nodehm:mgt',
        lsvm         => 'nodehm:mgt',
        chvm         => 'nodehm:mgt',
        rscan        => 'nodehm:mgt',
        execcmdonvm  => 'nodehm:mgt',
        nodeset      => 'noderes:netboot',
        getmacs      => 'nodehm:getmac,mgt',
        rnetboot     => 'nodehm:mgt',
        rmigrate     => 'nodehm:mgt',
        chhypervisor => [ 'hypervisor:type', 'nodetype:os=(zvm.*)' ],
        revacuate    => 'hypervisor:type',
        reventlog    => 'nodehm:mgt',
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
    if ($req->{_xcatpreprocessed}->[0] == 1) {
        return [$req];
    }
    my $nodes   = $req->{node};
    my $service = "xcat";

    # Find service nodes for requested nodes
    # Build an individual request for each service node
    if ($nodes) {
        $sn = xCAT::ServiceNodeUtils->get_ServiceNode($nodes, $service, "MN");

        # Build each request for each service node
        foreach my $snkey (keys %$sn) {
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
        $rsp->{data}->[0] = "Input noderange missing. Usage: zvm <noderange> \n";
        xCAT::MsgUtils->message("I", $rsp, $callback, 0);
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
    $::STDIN = $request->{stdin}->[0];
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
    my @children = ();

    #*** Power on or off a node ***
    if ($command eq "rpower") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                powerVM($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Hardware and software inventory ***
    elsif ($command eq "rinv") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                if (xCAT::zvmUtils->isHypervisor($_)) {
                    inventoryHypervisor($callback, $_, $args);
                } else {
                    inventoryVM($callback, $_, $args);
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
    elsif ($command eq "rmigrate") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                migrateVM($callback, $_, $args);

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
    elsif ($command eq "revacuate") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                evacuate($callback, $_, $args);

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
    elsif ($command eq "mkvm") {

        # Determine if the argument is a node
        my $clone         = 0;
        my %cloneInfoHash = ();    # create empty hash
        if ($args->[0]) {
            $clone = xCAT::zvmUtils->isZvmNode($args->[0]);
        }

        # Loop through all the arguments looking for "-imagename"
        # if an image name is found and it matches what is in the
        # doclone.txt then this must be a specialcloneVM call.
        my $argsSize  = @{$args};
        my $imagename = '';

        for (my $i = 0 ; $i < $argsSize ; $i++) {
            my $parm = $args->[$i];

            #xCAT::zvmUtils->printSyslog("Args[$i] =<$parm>\n");
            if (index($parm, "--imagename") != -1) {
                if (($i + 1) < $argsSize) {
                    $imagename = $args->[ $i + 1 ];
                }

                if (!length($imagename)) {
                    xCAT::zvmUtils->printSyslog("(Error) image name value missing\n");
                    xCAT::zvmUtils->printLn($callback, "$nodes: (Error) image name value missing\n");
                    return;
                }

                xCAT::zvmUtils->printSyslog("mkvm for (@nodes). Parm --imagename found with value ($imagename). Check if this is special case.\n");

                %cloneInfoHash = xCAT::zvmUtils->getSpecialCloneInfo($imagename);
                if (%cloneInfoHash) {
                    xCAT::zvmUtils->printSyslog("Image found in doclone.txt for creating (@nodes)\n");

                    # call special clonevm processing
                    specialcloneVM($callback, \@nodes, $args, \%cloneInfoHash);
                    return;
                }
            }
        }

        # looking for --osimage, if an osimage name is found, check the image's
        # comments, if the comments indicate it's an non-xcatconf4z image, update
        # the zvm table for the nodes to set the flag to be xcatconf4z=0 in
        # comments colume
        my $osimage = '';
        for (my $i = 0 ; $i < $argsSize ; $i++) {
            my $parm = $args->[$i];
            if (index($parm, "--osimage") != -1) {
                if (($i + 1) < $argsSize) {
                    $osimage = $args->[ $i + 1 ];
                }

                if (!length($osimage)) {
                    xCAT::zvmUtils->printSyslog("(Error) osimage value missing\n");
                    xCAT::zvmUtils->printLn($callback, "$nodes: (Error) osimage value missing\n");
                    return;
                }

                xCAT::zvmUtils->printSyslog("mkvm for (@nodes). Parm --osimage found with value ($osimage). Set the node flag to indicate if it will be deployed by using xcatconf4z image or not.\n");

                # Update the zvm table comments colume to indicate the xcatconf4z type image
                my @propNames = ('comments');
                my $propVals = xCAT::zvmUtils->getTabPropsByKey('osimage', 'imagename', $osimage, @propNames);
                if ($propVals->{'comments'} =~ /xcatconf4z=0/) {
                    foreach (@nodes) {
                        @propNames = ('status');
                        $propVals = xCAT::zvmUtils->getNodeProps('zvm', $_, @propNames);
                        my $status = $propVals->{'status'};
                        if (!$status) {
                            $status = "XCATCONF4Z=0";
                        } else {
                            $status = "$status;XCATCONF4Z=0";
                        }
                        xCAT::zvmUtils->setNodeProp('zvm', $_, 'status', $status);
                    }
                }
            }
        }

        #*** Clone virtual server ***
        if ($clone) {
            cloneVM($callback, \@nodes, $args);
        }

        #*** Create user entry ***
        # Create node based on directory entry
        # or create a NOLOG if no entry is provided
        else {
            foreach (@nodes) {
                $pid = xCAT::Utils->xfork();

                # Parent process
                if ($pid) {
                    push(@children, $pid);
                }

                # Child process
                elsif ($pid == 0) {

                    makeVM($callback, $_, $args);

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
    elsif ($command eq "rmvm") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                removeVM($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Print the user entry ***
    elsif ($command eq "lsvm") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                listVM($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Change the user entry ***
    elsif ($command eq "chvm") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                changeVM($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Collect node information from zHCP ***
    elsif ($command eq "rscan") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                scanVM($callback, $_, $args);

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
    elsif ($command eq "nodeset") {
        foreach (@nodes) {

            # Only one file can be punched to reader at a time
            # Forking this process is not possible
            nodeSet($callback, $_, $args);

        }    # End of foreach
    }    # End of case

    #*** Get the MAC address of a node ***
    elsif ($command eq "getmacs") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                getMacs($callback, $_, $args);

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
    elsif ($command eq "rnetboot") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                netBoot($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Configure the virtualization hosts ***
    elsif ($command eq "chhypervisor") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                changeHypervisor($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach
    }    # End of case

    #*** Retrieve or clear event logs ***
    elsif ($command eq "reventlog") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                eventLog($callback, $_, $args);

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
    elsif ($command eq "updatenode") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                updateNode($callback, $_, $args);

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case


    #*** Execute a command on VM ***
    elsif ($command eq "execcmdonvm") {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
                xCAT::zvmUtils->execcmdonVM($::SUDOER, $_, $args->[0]);

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
        waitpid($_, 0);
    }

    return;
}

#-------------------------------------------------------

=head3   removeVM

    Description  : Delete the user from user directory
    Arguments    : Node to remove
                   Upstream instance ID (Optional)
                   Upstream request ID (Optional)
    Returns      : Nothing, errors returned in $callback
    Example      : removeVM($callback, $node);

=cut

#-------------------------------------------------------
sub removeVM {

    # Get inputs
    my ($callback, $node, $args) = @_;
    my $rc;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid', 'discovered');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");
    my $out;
    my $outmsg;

    my $requestId = "NoUpstreamRequestID"; # Default is still visible in the log
    my $objectId  = "NoUpstreamObjectID";  # Default is still visible in the log
    if ($args) {
        @ARGV = @$args;

        # Parse options
        GetOptions(
            'q|requestid=s' => \$requestId    # Optional
            , 'j|objectid=s' => \$objectId    # Optional
        );
    }

    # If node is a not a discovered node then remove the userid and its related resources.
    my $discovered = $propVals->{'discovered'};
    if (!$discovered || $discovered == 0) {

        # System was not discovered so we can destroy the virtual machine and
        # its resources.  First, get any vswitches in directory.
        xCAT::zvmUtils->printSyslog("Calling getVswitchIdsFromDirectory $::SUDOER, $hcp, $userId");
        my @vswitch = xCAT::zvmUtils->getVswitchIdsFromDirectory($::SUDOER, $hcp, $userId);
        if (xCAT::zvmUtils->checkOutput($vswitch[0]) == -1) {
            xCAT::zvmUtils->printLn($callback, "$vswitch[0]");
            return;
        }
        my %vswitchhash;

        # For each vswitch revoke the userid vswitch authority
        foreach (@vswitch) {
            if (!(length $_)) { next; }

            # skip revoke if we already did one for this vswitch
            if (exists $vswitchhash{$_}) {
                xCAT::zvmUtils->printSyslog("removeVM. Skipping duplicate vswitch remove grant from: $_");
            }
            else {
                xCAT::zvmUtils->printSyslog("removeVM. Found vswitch to remove grant from: $_");
                $out = xCAT::zvmCPUtils->revokeVSwitch($callback, $::SUDOER, $hcp, $userId, $_);
                $vswitchhash{$_} = '1';

                #caller logs any errors, so just continue.
            }
        }

        # Power off user ID
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId -f IMMED");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId -f IMMED"`;
        $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
            return;
        }
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($out =~ m/Return Code: 200/i) {
            if ($out =~ m/Reason Code: 12/i) {
                xCAT::zvmUtils->printSyslog("$userId already logged off.");
                $rc = 0;
            } elsif ($out =~ m/Reason Code: 16/i) {
                xCAT::zvmUtils->printSyslog("$userId in process of logging off.");
                $rc = 0;
            }
        }
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $userId output: $out");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            return;
        }

        # Delete user entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Delete_DM -T $userId -e 0"`;
        $rc = $? >> 8;
        if ($rc == 255) { # Adding "Failed" to message will cause zhcp error dialog to be displayed to user
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
            return;
        }
        xCAT::zvmUtils->printSyslog("smcli Image_Delete_DM -T $userId -e 0 $out");
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        # Check for errors
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($rc == -1) {
            return;
        }

        # Go through each pool and free zFCP devices belonging to node
        my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
        my $pool;
        my @luns;
        my $update;
        my $expression;
        foreach (@pools) {
            if (!(length $_)) { next; }
            $pool = xCAT::zvmUtils->replaceStr($_, ".conf", "");

            $out = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$_"`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $::ZFCPPOOL/$_\"", $hcp, "removeVM", $out, $node);
            if ($rc != 0) {
                xCAT::zvmUtils->printLn($callback, "$outmsg");
                return;
            }
            $out = `echo "$out" | egrep -a -i $node`;
            @luns = split("\n", $out);
            foreach (@luns) {
                if (!(length $_)) { next; }

                # Update entry: status,wwpn,lun,size,range,owner,channel,tag
                my @info = split(',', $_);
                $update     = "free,$info[1],$info[2],$info[3],$info[4],,,";
                $expression = "'s#" . $_ . "#" . $update . "#i'";
                $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e $expression $::ZFCPPOOL/$pool.conf"`;
            }

            if (@luns) {
                xCAT::zvmUtils->printLn($callback, "$node: Updating FCP device pool $pool... Done");
            }
        }

        # Check for errors
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($rc == -1) {
            return;
        }
    } else {
        xCAT::zvmUtils->printLn($callback, "$node: 'discovered' property in zvm table is 1.  Node is removed only from xCAT.  Virtual machine was not deleted.");
    }

    # Remove node from 'zvm', 'nodelist', 'nodetype', 'noderes', 'nodehm', 'ppc', 'switch' tables
    # Save node entry in 'mac' table
    xCAT::zvmUtils->delTabEntry('zvm',      'node', $node);
    xCAT::zvmUtils->delTabEntry('hosts',    'node', $node);
    xCAT::zvmUtils->delTabEntry('nodelist', 'node', $node);
    xCAT::zvmUtils->delTabEntry('nodetype', 'node', $node);
    xCAT::zvmUtils->delTabEntry('noderes',  'node', $node);
    xCAT::zvmUtils->delTabEntry('nodehm',   'node', $node);
    xCAT::zvmUtils->delTabEntry('ppc',      'node', $node);
    xCAT::zvmUtils->delTabEntry('switch',   'node', $node);

    # Erase old hostname from known_hosts,all hostname are recorded in lower-case.
    my $lowernode = lc($node);
    $out = `ssh-keygen -R $lowernode`;

    # Erase hostname from /etc/hosts
    $out = `sed -i /$node./d /etc/hosts`;

    return;
}

#-------------------------------------------------------

=head3   changeVM

    Description  : Change a virtual machine's configuration
    Arguments    : Node
                   Option
    Returns      : Nothing, errors returned in $callback
    Example      : changeVM($callback, $node, $args);

=cut

#-------------------------------------------------------
sub changeVM {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid', 'status');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # If the node is being actively cloned then return.
    if ($propVals->{'status'} =~ /CLONING=1/ and $propVals->{'status'} =~ /CLONE_ONLY=1/) {
        return;
    }

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};

    # add page or spool does not need a userid, but flag any others
    if ($args->[0] ne "--addpagespool") {
        if (!$userId) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
            return;
        }

        # Capitalize user ID
        $userId =~ tr/a-z/A-Z/;
    }

    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("changeVM() node:$node userid:$userId subCmd:$args->[0] zHCP:$hcp sudoer:$::SUDOER sudo:$::SUDO");

    # Common subfunction variables
    my $out = "";
    my $outmsg;
    my $device = 0;
    my $newlinkcall = -1; # -1: not linked, 0: linked using the old way, 1: linked using linkdiskandbringonline script.
    my $rc          = 0;
    my $vdev;

    # add3390 [disk pool] [device address] [size] [mode] [read password (optional)] [write password (optional)] [multi password (optional)] [fstype (optional)]
    if ($args->[0] eq "--add3390") {
        my $pool = $args->[1];
        my $addr = $args->[2];
        my $cyl  = $args->[3];


        # If the user specifies auto as the device address, then find a free device address
        if ($addr eq "auto") {
            $addr = xCAT::zvmUtils->getFreeAddress($::SUDOER, $node, "smapi");
        }

        my $mode = "MR";
        if ($args->[4]) {
            $mode = $args->[4];
        }

        my $readPw = "''";
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

        my $fstype = '';
        if ($args->[8]) {
            $fstype = $args->[8];
        }

        # Convert to cylinders if size is given as M or G
        # Otherwise, assume size is given in cylinders
        # Note this is for a 4096 block size ECKD disk, where 737280 bytes = 1 cylinder
        if ($cyl =~ m/M/i) {
            $cyl =~ s/M//g;
            $cyl = xCAT::zvmUtils->trimStr($cyl);
            $cyl = sprintf("%.4f", $cyl);
            $cyl = ($cyl * 1024 * 1024) / 737280;
            $cyl = ceil($cyl);
        } elsif ($cyl =~ m/G/i) {
            $cyl =~ s/G//g;
            $cyl = xCAT::zvmUtils->trimStr($cyl);
            $cyl = sprintf("%.4f", $cyl);
            $cyl = ($cyl * 1024 * 1024 * 1024) / 737280;
            $cyl = ceil($cyl);
        } elsif ($cyl =~ m/[a-zA-Z]/) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Size can be Megabytes (M), Gigabytes (G), or number of cylinders");
            return;
        }

        # Add to directory entry
        my $error = 0;
        xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $readPw -W $writePw -M $multiPw\"");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $readPw -W $writePw -M $multiPw"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $readPw -W $writePw -M $multiPw\"",
            $hcp, "changeVM", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, $outmsg);
            return;
        }

        if ($fstype && ($fstype !~ /(ext2|ext3|ext4|xfs|swap)/i)) {
            $out = "(Warning) File system type can only be ext2, ext3, ext4 ,swap or xfs" . "\n";
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            $error = 1;
        }

        if ($fstype && !$error) {    # Format the disk before making it active.
                # link the disk
                # Check if zhcp has the new routine to link and online the disk
            $out = `ssh -o ConnectTimeout=30 $::SUDOER\@$hcp "$::SUDO $::DIR/linkdiskandbringonline $userId $addr $mode"`;

            $rc = $? >> 8;

            # Note: We don't use zvmUtils->checkSSH_Rc() in this section because some non-zero RCs are tolerated.
            if ($rc == 255) {
                xCAT::zvmUtils->printSyslog("$node: changeVM() Unable to communicate with zHCP agent");
                xCAT::zvmUtils->printLn($callback, "$node: changeVM() Unable to communicate with zHCP agent: $hcp");
                $error = 1;
            } elsif ($rc > 0 && $rc != 127) {
                xCAT::zvmUtils->printSyslog("$node: changeVM() Unexpected error from SSH call to linkdiskandbringonline rc: $rc $out");
                xCAT::zvmUtils->printLn($callback, "$node: changeVM()Unexpected error from SSH call to linkdiskandbringonline rc: $rc $out");
                $error = 1;
            } elsif ($rc == 0) {
                $newlinkcall = 1;
                if ($out =~ m/Success:/i) {

                    # sample output=>linkdiskandbringonline maint start time: 2017-03-03-16:20:48.011
                    #                Success: Userid maint vdev 193 linked at ad35 device name dasdh
                    #                linkdiskandbringonline exit time: 2017-03-03-16:20:52.150
                    $out = `echo "$out" | egrep -a -i "Success:"`;
                    my @info = split(' ', $out);
                    $device = "/dev/" . $info[10];
                } else {
                    xCAT::zvmUtils->printSyslog("$node: changeVM() Error occurred in call to linkdiskandbringonline: $out");
                    xCAT::zvmUtils->printLn($callback, "$node: changeVM() Error occurred in call to linkdiskandbringonline: $out");
                    $error = 1;
                }
            } else {
                xCAT::zvmUtils->printSyslog("$node: changeVM() Could not find zhcp linkdiskandbringonline, using old code path.");
                my $retry = 3;
                $vdev = xCAT::zvmUtils->getFreeAddress($::SUDOER, $hcp, 'vmcp');
                while ($retry > 0) {

                    # wait 2 seconds for disk creation complete
                    sleep(2);
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp LINK TO $userId $addr AS $vdev M 2>&1"`;
                    $error = (xCAT::zvmUtils->checkOutput($out) == -1) ? 1 : 0;

                    # Note: We don't use zvmUtils->checkSSH_Rc() in this section because
                    #       we are only interested in logging the final error.
                    if ($error) {
                        $retry -= 1;
                        $vdev = xCAT::zvmUtils->getFreeAddress($::SUDOER, $hcp, 'vmcp');
                    } else {
                        $newlinkcall = 0;
                        last;
                    }
                }

                if ($error) {
                    xCAT::zvmUtils->printSyslog("Error occurred in 'vmcp LINK TO $userId $addr AS $vdev M' $device. Output: $out");
                    xCAT::zvmUtils->printLn($callback, "$node: changeVM() Error occurred in 'vmcp LINK TO $userId $addr AS $vdev M' " .
                          "Output: $out");
                } else {

                    # make the disk online and get it's device name
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/cio_ignore -r $vdev &> /dev/null"`;
                    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/cio_ignore -r $vdev &> /dev/null\"",
                        $hcp, "changeVM", $out, $node);
                    if ($rc != 0) {
                        xCAT::zvmUtils->printLn($callback, $outmsg);
                        $error = 1;
                    }
                    if (!$error) {
                        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $vdev);
                        if ($out !~ 'Done') {
                            xCAT::zvmUtils->printLn($callback, "$node: $out");
                            $error = 1;
                        }
                    }
                    if (!$error) {
                        my $select = `ssh $::SUDOER\@$hcp "$::SUDO cat /proc/dasd/devices"`;
                        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat /proc/dasd/devices\"", $hcp, "changeVM", $select, $node);
                        if ($rc != 0) {
                            xCAT::zvmUtils->printLn($callback, "$outmsg");
                            $error = 1;
                        } else {
                            $select = `echo "$select" | egrep -a -i "0.0.$vdev"`;
                            chomp($select);

                            # A sample entry:
                            # 0.0.0101(ECKD) at ( 94:     0) is dasda       : active at blocksize: 4096, 600840 blocks, 2347 MB
                            if ($select) {
                                my @info = split(' ', $select);
                                $device = "/dev/" . $info[6];
                            } else {
                                xCAT::zvmUtils->printSyslog("$node: changeVM() Error, unable to find the device " .
                                      "on $hcp related to 0.0.$vdev");
                                xCAT::zvmUtils->printLn($callback, "$node: changeVM() Error, unable to find the device " .
                                      "on $hcp related to 0.0.$vdev");
                                $error = 1;
                            }
                        }
                    }
                }
            }

            # format the disk
            if (!$error) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -y -b 4096 -d cdl -f $device 2>&1"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/dasdfmt -y -b 4096 -d cdl -f $device 2>&1\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }
            }
            if (!$error) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdasd -a $device 2>&1"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/fdasd -a $device 2>&1\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }
            }
            if (!$error) {
                $device .= '1';
                if ($fstype =~ m/xfs/i) {
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO mkfs.xfs -f $device 2>&1"`;
                    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO mkfs.xfs -f $device 2>&1\"",
                        $hcp, "changeVM", $out, $node);
                    if ($rc != 0) {
                        xCAT::zvmUtils->printLn($callback, $outmsg);
                        $error = 1;
                    }
                } elsif ($fstype =~ m/swap/i) {
                    xCAT::zvmUtils->printSyslog("the file system is swap, so no format needed");
                } else {
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO mkfs -F -t $fstype $device 2>&1"`;
                    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO mkfs -F -t $fstype $device 2>&1\"",
                        $hcp, "changeVM", $out, $node);
                    if ($rc != 0) {
                        xCAT::zvmUtils->printLn($callback, $outmsg);
                        $error = 1;
                    }
                }
                if ($error) {
                    xCAT::zvmUtils->printLn($callback, "(Warning) Cannot format disk with fstype $fstype");
                }
            }

            # offline and detach disk using the new call so that zhcp records are updated
            if ($newlinkcall == 1) {
                $out = `ssh -o ConnectTimeout=30 $::SUDOER\@$hcp "$::SUDO $::DIR/offlinediskanddetach $userId $addr"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh -o ConnectTimeout=30 $::SUDOER\@$hcp \"$::SUDO $::DIR/offlinediskanddetach $userId $addr\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }

                # Use old code to disable and detach
            } elsif ($newlinkcall == 0) {
                $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $vdev);
                if ($out !~ 'Done') {

                    # Note: We are only going to log the disable failure because a failure to
                    #       disable the device doesn't mean much because we are going to immmediately
                    #       detach it.  The worst that we expect to happen in this case is that
                    #       we have a dasd enabled that is no longer attached.
                    xCAT::zvmUtils->printSyslog("$node: $out");
                }

                xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp DETACH $vdev &> /dev/null\"");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp DETACH $vdev &> /dev/null"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp DETACH $vdev &> /dev/null\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    xCAT::zvmUtils->printSyslog($outmsg);
                    $error = 1;
                }
            }

            # else disk was not linked so we don't have to remove it.
        }

        if (!$error) {

            # Add to active configuration
            xCAT::zvmUtils->printLn($callback, "$node: Adding 3390 disk to $userId\'s directory entry as $addr ... Done");
            my $power = `/opt/xcat/bin/rpower $node stat`;
            if ($power =~ m/: on/i) {
                xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode\"");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }
            }

            if ($error != 1) {
                xCAT::zvmUtils->printLn($callback, "$node: Adding disk to $userId\'s active configuration... Done");
            }
        }
        $out = '';
    }

    # add3390active [device address] [mode]
    elsif ($args->[0] eq "--add3390active") {
        my $addr = $args->[1];
        my $mode = $args->[2];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create -T $userId -v $addr -m $mode");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # add9336 [disk pool] [virtual device address] [size] [mode] [read password (optional)] [write password (optional)] [multi password (optional)] [fstype (optional)]
    elsif ($args->[0] eq "--add9336") {
        my $pool = $args->[1];
        my $addr = $args->[2];
        my $blks = $args->[3];

        # If the user specifies auto as the device address, then find a free device address
        if ($addr eq "auto") {
            $addr = xCAT::zvmUtils->getFreeAddress($::SUDOER, $node, "smapi");
        }

        my $mode = "MR";
        if ($args->[4]) {
            $mode = $args->[4];
        }

        my $readPw = "''";
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

        my $fstype = '';
        if ($args->[8]) {
            $fstype = $args->[8];
        }

        # Convert to blocks if size is given as M or G
        # Otherwise, assume size is given in blocks
        # Note this is for a 4096 block size ECKD disk, where 737280 bytes = 1 cylinder
        if ($blks =~ m/M/i) {
            $blks =~ s/M//g;
            $blks = xCAT::zvmUtils->trimStr($blks);
            $blks = sprintf("%.4f", $blks);
            $blks = ($blks * 1024 * 1024) / 512;
            $blks = ceil($blks);
        } elsif ($blks =~ m/G/i) {
            $blks =~ s/G//g;
            $blks = xCAT::zvmUtils->trimStr($blks);
            $blks = sprintf("%.4f", $blks);
            $blks = ($blks * 1024 * 1024 * 1024) / 512;
            $blks = ceil($blks);
        } elsif ($blks =~ m/[a-zA-Z]/) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Size can be Megabytes (M), Gigabytes (G), or number of blocks");
            return;
        }

        # Add to directory entry
        my $error = 0;
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 9336 -a AUTOG -r $pool -u 2 -z $blks -m $mode -f 1 -R $readPw -W $writePw -M $multiPw 2>&1"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t 9336 -a AUTOG -r $pool -u 2 -z $blks -m $mode -f 1 -R $readPw -W $writePw -M $multiPw 2>&1\"",
            $hcp, "changeVM", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            return;
        }

        if ($fstype && ($fstype !~ /(ext2|ext3|ext4|xfs)/i)) {
            $out = "(Warning) File system type can only be ext2, ext3, ext4 or xfs" . "\n";
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            $error = 1;
        }

        my $device = 0;
        my $newlinkcall = -1; # -1: not linked, 0: linked using the old way, 1: linked using linkdiskandbringonline script.
        my $rc          = 0;
        my $vdev;

        if ($fstype && !$error) {    # Format the disk before making it active.
                # link the disk
                # Check if zhcp has the new routine to link and online the disk
            $out = `ssh -o ConnectTimeout=30 $::SUDOER\@$hcp "$::SUDO $::DIR/linkdiskandbringonline $userId $addr $mode"`;

            $rc = $? >> 8;
            if ($rc == 255) {
                xCAT::zvmUtils->printSyslog("$node: changeVM() Unable to communicate with zHCP agent");
                xCAT::zvmUtils->printLn($callback, "$node: changeVM() Unable to communicate with zHCP agent: $hcp");
                $error = 1;
            } elsif ($rc > 0 && $rc != 127) {
                xCAT::zvmUtils->printSyslog("$node: changeVM() Unexpected error from SSH call to linkdiskandbringonline rc: $rc $out");
                xCAT::zvmUtils->printLn($callback, "$node: changeVM() Unexpected error from SSH call to linkdiskandbringonline rc: $rc $out");
                $error = 1;
            } elsif ($rc == 0) {
                $newlinkcall = 1;
                if ($out =~ m/Success:/i) {

                    # sample output=>linkdiskandbringonline maint start time: 2017-03-03-16:20:48.011
                    #                Success: Userid maint vdev 193 linked at ad35 device name dasdh
                    #                linkdiskandbringonline exit time: 2017-03-03-16:20:52.150
                    $out = `echo "$out" | egrep -a -i "Success:"`;
                    my @info = split(' ', $out);
                    $device = "/dev/" . $info[10];
                } else {
                    xCAT::zvmUtils->printSyslog("$node: changeVM() Error occurred in call to linkdiskandbringonline: $out");
                    xCAT::zvmUtils->printLn($callback, "$node: changeVM()(Error occurred in call to linkdiskandbringonline: $out");
                    $error = 1;
                }
            } else {
                xCAT::zvmUtils->printSyslog("$node: changeVM() Could not find zhcp linkdiskandbringonline, using old code path.");
                my $retry = 3;
                $vdev = xCAT::zvmUtils->getFreeAddress($::SUDOER, $hcp, 'vmcp');
                while ($retry > 0) {

                    # wait 2 seconds for disk creation complete
                    sleep(2);
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp LINK TO $userId $addr AS $vdev M 2>&1"`;
                    $error = (xCAT::zvmUtils->checkOutput($out) == -1) ? 1 : 0;

                    # Note: We don't use zvmUtils->checkSSH_Rc() in this section because
                    #       we are only interested in logging the final error.
                    if ($error) {
                        $retry -= 1;
                        $vdev = xCAT::zvmUtils->getFreeAddress($::SUDOER, $hcp, 'vmcp');
                    } else {
                        $newlinkcall = 0;
                        last;
                    }
                }

                if ($error) {
                    xCAT::zvmUtils->printSyslog("Error occurred in 'vmcp LINK TO $userId $addr AS $vdev M' $device. Output: $out");
                    xCAT::zvmUtils->printLn($callback, "$node: changeVM() Error occurred in 'vmcp LINK TO $userId $addr AS $vdev M' " .
                          "Output: $out");
                } else {

                    # make the disk online and get it's device name
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/cio_ignore -r $vdev &> /dev/null"`;
                    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/cio_ignore -r $vdev &> /dev/null\"",
                        $hcp, "changeVM", $out, $node);
                    if ($rc != 0) {
                        xCAT::zvmUtils->printLn($callback, $outmsg);
                        $error = 1;
                    }
                    if (!$error) {
                        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $vdev);
                        if ($out !~ 'Done') {
                            xCAT::zvmUtils->printLn($callback, "$node: $out");
                            $error = 1;
                        }
                    }
                    if (!$error) {
                        my $select = `ssh $::SUDOER\@$hcp "$::SUDO cat /proc/dasd/devices"`;
                        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat /proc/dasd/devices\"", $hcp, "changeVM", $select, $node);
                        if ($rc != 0) {
                            xCAT::zvmUtils->printLn($callback, "$outmsg");
                            $error = 1;
                        } else {
                            $select = `echo "$select" | egrep -a -i "0.0.$vdev"`;
                            chomp($select);

                            # A sample entry:
                            # select: 0.0.0001(FBA ) at ( 94:    28) is dasdh       : active at blocksize: 512, 61440 blocks, 30 MB
                            if ($select) {
                                my @info = split(' ', $select);
                                $device = "/dev/" . $info[7];
                            } else {
                                xCAT::zvmUtils->printSyslog("$node: changeVM() Error, unable to find the device " .
                                      "on $hcp related to 0.0.$vdev");
                                xCAT::zvmUtils->printLn($callback, "$node: changeVM() Error, unable to find the device " .
                                      "on $hcp related to 0.0.$vdev");
                                $error = 1;
                            }
                        }
                    }
                }
            }

            #Delete the existing partition in case the disk already has partition on it
            if (!$error) {
                $out =
                  `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdisk $device << EOF
d
w
EOF"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
                    "ssh $::SUDOER\@$hcp \"$::SUDO /sbin/fdisk $device d w\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }
            }

            # Create one partition to use the entire disk space
            if (!$error) {
                $out =
                  `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdisk $device << EOF
n
p
1


w
EOF"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/fdisk $device n p 1 w\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }
            }
            if (!$error) {
                $device .= '1';
                if ($fstype =~ m/xfs/i) {
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO mkfs.xfs -f $device 2>&1"`;
                    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO mkfs.xfs -f $device 2>&1\"",
                        $hcp, "changeVM", $out, $node);
                    if ($rc != 0) {
                        xCAT::zvmUtils->printLn($callback, $outmsg);
                        $error = 1;
                    }
                } else {
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO mkfs -F -t $fstype $device 2>&1"`;
                    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO mkfs -F -t $fstype $device\"",
                        $hcp, "changeVM", $out, $node);
                    if ($rc != 0) {
                        xCAT::zvmUtils->printLn($callback, $outmsg);
                        $error = 1;
                    }
                }
                if ($error) {
                    xCAT::zvmUtils->printLn($callback, "(Warning) Cannot format disk with fstype $fstype");
                }
            }

            # offline and detach disk using new call so that zhcp records are updated
            if ($newlinkcall == 1) {
                $out = `ssh -o ConnectTimeout=30 $::SUDOER\@$hcp "$::SUDO $::DIR/offlinediskanddetach $userId $addr"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh -o ConnectTimeout=30 $::SUDOER\@$hcp \"$::SUDO $::DIR/offlinediskanddetach $userId $addr\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }

                # Use old code to disable and detach
            } elsif ($newlinkcall == 0) {
                $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $vdev);
                if ($out !~ 'Done') {

                    # Note: We are only going to log the disable failure because a failure to
                    #       disable the device doesn't mean much because we are going to immmediately
                    #       detach it.  The worst that we expect to happen in this case is that
                    #       we have a dasd enabled that is no longer attached.
                    xCAT::zvmUtils->printSyslog("$node: $out");
                }

                xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp DETACH $vdev &> /dev/null\"");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp DETACH $vdev &> /dev/null"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp DETACH $vdev &> /dev/null\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    xCAT::zvmUtils->printSyslog($outmsg);
                    $error = 1;
                }
            }

            # else disk was not linked so we don't have to remove it.
        }
        if (!$error) {

            # Add to active configuration
            xCAT::zvmUtils->printLn($callback, "$node: Adding 9336 disk to $userId\'s directory entry as $addr ... Done");
            my $power = `/opt/xcat/bin/rpower $node stat`;
            if ($power =~ m/: on/i) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?,
"ssh $::SUDOER\@$hcp $::SUDO \"$::DIR/smcli Image_Disk_Create -T $userId -v $addr -m $mode\"",
                    $hcp, "changeVM", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, $outmsg);
                    $error = 1;
                }
            }

            if ($error != 1) {
                xCAT::zvmUtils->printLn($callback, "$node: Adding disk to $userId\'s active configuration... Done");
            }
        }
        $out = '';
    }

    # adddisk2pool [function] [region] [volume] [group]
    elsif ($args->[0] eq "--adddisk2pool") {

        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor($callback, $node, $args);
    }

    # addzfcp2pool [pool] [status] [wwpn] [lun] [size] [owner (optional)]
    elsif ($args->[0] eq "--addzfcp2pool") {

        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor($callback, $node, $args);
    }

    # addnic [address] [type] [device count]
    elsif ($args->[0] eq "--addnic") {
        my $addr     = $args->[1];
        my $type     = $args->[2];
        my $devcount = $args->[3];
        my $allgood  = 1;

        # Add to active configuration if possible
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "ping") {

            #$out = `ssh $::SUDOER\@$node "/sbin/vmcp define nic $addr type $type"`;
            my $cmd = "$::SUDO /sbin/vmcp define nic $addr type $type";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            # Check if error.
            if ($out =~ m/not created/i || $out =~ m/conflicting/i) {
                $allgood = 0;
                xCAT::zvmUtils->printLn($callback, "(Error) Failed in: define nic $addr type $type <br>");
            }
        }
        if ($allgood == 1) {

            # Translate QDIO or Hipersocket into correct type
            if ($type =~ m/QDIO/i) {
                $type = 2;
            } elsif ($type =~ m/HIPER/i) {
                $type = 1;
            }

            # Add to directory entry
            $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Create_DM -T $userId -v $addr -a $type -n $devcount"`;
            xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Create_DM -T $userId -v $addr -a $type -n $devcount");
            $out = xCAT::zvmUtils->appendHostname($node, $out);
        }
    }

    # addpagespool [vol_addr] [volume_label] [volume_use] [system_config_name (optional)] [system_config_type (optional)] [parm_disk_owner (optional)] [parm_disk_number (optional)] [parm_disk_password (optional)]
    elsif ($args->[0] eq "--addpagespool") {
        my $argsSize = @{$args};

        my $i;
        my @options = ("", "vol_addr=", "volume_label=", "volume_use=", "system_config_name=", "system_config_type=", "parm_disk_owner=", "parm_disk_number=", "parm_disk_password=");
        my $argStr = "";
        foreach $i (1 .. $argsSize) {
            if ($args->[$i]) {
                $argStr .= " -k \"$options[$i]$args->[$i]\"";
            }
        }

        # Add a full volume page or spool disk to the system
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Page_or_Spool_Volume_Add -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Page_or_Spool_Volume_Add -T $hcpUserId $argStr");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # addprocessor [address]
    elsif ($args->[0] eq "--addprocessor") {
        my $addr = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_CPU_Define_DM -T $userId -v $addr -b 0 -d 1 -y 0"`;
        xCAT::zvmUtils->printSyslog("smcli Image_CPU_Define_DM -T $userId -v $addr -b 0 -d 1 -y 0");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # addprocessoractive [address] [type]
    elsif ($args->[0] eq "--addprocessoractive") {
        my $addr = $args->[1];
        my $type = $args->[2];

        $out = xCAT::zvmCPUtils->defineCpu($::SUDOER, $node, $addr, $type);
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # addvdisk [device address] [size]
    elsif ($args->[0] eq "--addvdisk") {
        my $addr  = $args->[1];
        my $size  = $args->[2];
        my $mode  = $args->[3];
        my $error = 0;

        xCAT::zvmUtils->printSyslog("$node: smcli Image_Disk_Create_DM -T $userId -v $addr -t FB-512 -a V-DISK -r NONE -u 2 -z $size -m $mode -f 0");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $userId -v $addr -t FB-512 -a V-DISK -r NONE -u 2 -z $size -m $mode -f 0"`;
        $error = (xCAT::zvmUtils->checkOutput($out) == -1) ? 1 : 0;
        if ($error) {
            xCAT::zvmUtils->printSyslog("$node: Error on Image_Disk_Create_DM. Output: $out");
            xCAT::zvmUtils->printLn($callback, "$node: changeVM() Error occurred during " .
"'smcli Image_Disk_Create_DM -T $userId -v $addr -t FB-512 -a V-DISK -r NONE " .
                  "-u 2 -z $size -m $mode -f 0'. Output: $out");
            return;
        }

        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # addzfcp [pool] [device address (or auto)] [loaddev (0 or 1)] [size] [tag (optional)] [wwpn (optional)] [lun (optional)]
    elsif ($args->[0] eq "--addzfcp") {
        my $argsSize = @{$args};
        if (($argsSize != 5) && ($argsSize != 6) && ($argsSize != 8)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $pool    = lc($args->[1]);
        my $device  = $args->[2];
        my $loaddev = int($args->[3]);
        if ($loaddev != 0 && $loaddev != 1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) The loaddev can be 0 or 1");
            return;
        }
        my $size = $args->[4];

        # Tag specifies what to replace in the autoyast/kickstart template, e.g. $root_device$
        # This argument is optional
        my $tag = $args->[5];

        # Check if WWPN and LUN are given
        # WWPN can be given as a semi-colon separated list
        my $wwpn       = "";
        my $lun        = "";
        my $useWwpnLun = 0;
        if ($argsSize == 8) {
            $useWwpnLun = 1;
            $wwpn       = $args->[6];
            $lun        = $args->[7];
            if ($wwpn =~ m/;/) {

                # It's not supported to ipl from a multipath device
                if ($loaddev) {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) It's not supported to ipl from a multipath device");
                    return;
                }
            }
        }

        my %zFCP;        # Store zFCP device's original attributes here
        my %criteria;    # Store zFCP device's new attributes here
        my $resultsRef;
        if ($useWwpnLun) {

            # Store current attributes of the SCSI/FCP device in case need to roll back when something goes wrong
            my $deviceRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $wwpn, $lun);
            if (xCAT::zvmUtils->checkOutput($deviceRef) == -1) {
                xCAT::zvmUtils->printLn($callback, "$deviceRef");
                return;
            }
            %zFCP = %$deviceRef;

            # Check current status of the FCP device
            if ('used' eq $zFCP{'status'}) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) FCP device 0x$wwpn/0x$lun is in use.");
                return;
            }

            %criteria = (
                'status' => 'used',
                'fcp'    => $device,
                'wwpn'   => $wwpn,
                'lun'    => $lun,
                'size'   => $size,
                'owner'  => $node,
                'tag'    => $tag
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        } else {

            # Do not know the WWPN or LUN in this case
            %criteria = (
                'status' => 'used',
                'fcp'    => $device,
                'size'   => $size,
                'owner'  => $node,
                'tag'    => $tag
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);

            # Store original attributes of the SCSI/FCP device in case need to roll back when something goes wrong
            my %results = %$resultsRef;
            %zFCP = (
                'status' => 'free',
                'wwpn'   => $results{'wwpn'},
                'lun'    => $results{'lun'},
                'fcp'    => '',
                'size'   => $size,
                'owner'  => '',
                'tag'    => ''
            );
        }

        my %results = %$resultsRef;
        if ($results{'rc'} == -1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to add zFCP device");
            return;
        }

        # Obtain the device assigned by xCAT
        $device = $results{'fcp'};
        $wwpn   = $results{'wwpn'};
        $lun    = $results{'lun'};

        # Get user directory entry
        my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;

        # Get source node OS
        my $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node);

        my @device_list = split(';', $device);
        foreach (@device_list) {

            # Find DEDICATE statement in the entry (dedicate one if one does not exist)
            my $cur_device = $_;
            if (!$cur_device) { next; }
            my $dedicate = `echo "$userEntry" | egrep -a -i "DEDICATE $cur_device"`;
            if (!$dedicate) {

                # Remove FCP device address from CIO device blacklist
                my $cmd = "$::SUDO /sbin/cio_ignore -r $cur_device";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);

                # (to-do) Add check for command fail.

                $out = `/opt/xcat/bin/chvm $node --dedicatedevice $cur_device $cur_device 0 2>&1`;
                xCAT::zvmUtils->printLn($callback, "$out");
                if (xCAT::zvmUtils->checkOutput($out) == -1) {

                    # Roll back. Undedicate FCP device and restore all attributes of the zFCP device
                    foreach (@device_list) {
                        `/opt/xcat/bin/chvm $node --undedicatedevice $_`;
                    }
                    $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%zFCP);

                    # Exit if dedicate failed
                    return;
                }
                if ($os =~ m/sles/i) {
                    my $cmd = "$::SUDO /sbin/zfcp_host_configure 0.0.$cur_device 1";
                    $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                    if (xCAT::zvmUtils->checkOutput($out) == -1) {
                        return;
                    }
                } elsif ($os =~ m/ubuntu/i) {
                    my $cmd = "$::SUDO /sbin/chzdev zfcp-host $cur_device -e";
                    $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                    if (xCAT::zvmUtils->checkOutput($out) == -1) {
                        return;
                    }
                }
            }
        }

        # Configure native SCSI/FCP inside node (if online)
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "ping") {
            foreach (@device_list) {
                my $cur_device = $_;
                if (!$cur_device)      { next; }
                if ($os =~ m/ubuntu/i) { next; }

                # Online device
                $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $node, "-e", "0.0." . $cur_device);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    xCAT::zvmUtils->printLn($callback, "$node: $out");

                    # Roll back. Undedicate FCP device and restore all attributes of the zFCP device
                    foreach (@device_list) {
                        `/opt/xcat/bin/chvm $node --undedicatedevice $_`;
                    }
                    $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%zFCP);
                    return;
                }
            }

            # Set WWPN and LUN in sysfs
            foreach (@device_list) {
                my $cur_device = lc($_);
                if (!$cur_device) { next; }
                $wwpn = lc($wwpn);

                my @wwpn_list = split(";", $wwpn);
                foreach (@wwpn_list) {
                    my $cur_wwpn = $_;
                    if (!$cur_wwpn) { next; }

                    # For versions below RHEL6 or SLES11, they are not supported any more.
                    $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo 0x$lun > /sys/bus/ccw/drivers/zfcp/0.0.$cur_device/0x$cur_wwpn/unit_add");

                    # Set WWPN and LUN in configuration files
                    my $tmp;
                    if ($os =~ m/sles1[12]/i) {

                        #   SLES 11&12: /etc/udev/rules.d/51-zfcp*
                        my $cmd = "$::SUDO /sbin/zfcp_disk_configure 0.0.$cur_device $cur_wwpn $lun 1";
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                        if (xCAT::zvmUtils->checkOutput($out) == -1) {
                            return;
                        }

                        # Check if the config file already exists and contains the zFCP channel
                        $cmd = $::SUDO . ' cat /etc/udev/rules.d/51-zfcp-0.0.' . $cur_device . '.rules';
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
                        if (xCAT::zvmUtils->checkOutput($out) == -1) {
                            return;
                        }
                        $out = `echo "$out" | egrep -a -i 'ccw/0.0.' . $cur_device. ']online'`;
                        if (!(length $out)) {

                            # Configure zFCP device to be persistent
                            $cmd = "$::SUDO touch /etc/udev/rules.d/51-zfcp-0.0.$cur_device.rules";
                            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                                return;
                            }

                            # Not configured before, do configuration, will not check for errors here
                            $tmp = 'ACTION==\"add\", SUBSYSTEM==\"ccw\", KERNEL==\"0.0.' . $cur_device . '\", IMPORT{program}=\"collect 0.0.' . $cur_device . ' \%k 0.0.' . $cur_device . ' zfcp\"';
                            $cmd = 'echo ' . $tmp . '>> /etc/udev/rules.d/51-zfcp-0.0.' . $cur_device . '.rules';
                            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);

                            $tmp = 'ACTION==\"add\", SUBSYSTEM==\"drivers\", KERNEL==\"zfcp\", IMPORT{program}=\"collect 0.0.' . $cur_device . ' \%k 0.0.' . $cur_device . 'zfcp\"';
                            $cmd = 'echo ' . $tmp . '>> /etc/udev/rules.d/51-zfcp-0.0.' . $cur_device . '.rules';
                            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);

                            $tmp = 'ACTION==\"add\", ENV{COLLECT_0.0.' . $cur_device . '}==\"0\", ATTR{[ccw/0.0.' . $cur_device . ']online}=\"1\"';
                            $cmd = 'echo ' . $tmp . '>> /etc/udev/rules.d/51-zfcp-0.0.' . $cur_device . '.rules';
                            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
                        }

                        # Will not check for errors here
                        $tmp = 'ACTION==\"add\", KERNEL==\"rport-*\", ATTR{port_name}==\"0x' . $cur_wwpn . '\", SUBSYSTEMS==\"ccw\", KERNELS==\"0.0.' . $cur_device . '\", ATTR{[ccw/0.0.' . $cur_device . ']0x' . $cur_wwpn . '/unit_add}=\"0x' . $lun . '\"';
                        $cmd = 'echo ' . $tmp . '>> /etc/udev/rules.d/51-zfcp-0.0.' . $cur_device . '.rules';
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);

                    } elsif ($os =~ m/rhel/i) {

                        #   RHEL: /etc/zfcp.conf
                        $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo \"0.0.$cur_device 0x$cur_wwpn 0x$lun\" >> /etc/zfcp.conf");
                        $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo add > /sys/bus/ccw/devices/0.0.$cur_device/uevent");

                    } elsif ($os =~ m/ubuntu/i) {

                        #   Ubuntu: chzdev zfcp-lun 0.0.$device:0x$wwpn:0x$lun -e
                        my $cmd = "$::SUDO /sbin/chzdev zfcp-lun 0.0.$cur_device:0x$cur_wwpn:0x$lun -e";
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
                        if (xCAT::zvmUtils->checkOutput($out) == -1) {
                            return;
                        }
                    }
                }
            }

            my $cmd = "$::SUDO /sbin/multipath -r";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
            if ($out) {

                # not a fatal error, print a message and continue
                xCAT::zvmUtils->printLn($callback, "$node: $out");
            }

            xCAT::zvmUtils->printLn($callback, "$node: Configuring FCP device to be persistent... Done");
            $out = "";
        }

        # Set loaddev statement in directory entry
        if ($loaddev) {
            $out = `/opt/xcat/bin/chvm $node --setloaddev $wwpn $lun`;
            xCAT::zvmUtils->printLn($callback, "$out");
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to set LOADDEV statement in the directory entry");
                return;
            }
            $out = "";
        }

        xCAT::zvmUtils->printLn($callback, "$node: Adding zFCP device $device/$wwpn/$lun... Done");
    }

    # connectnic2guestlan [address] [lan] [owner]
    elsif ($args->[0] eq "--connectnic2guestlan") {
        my $addr  = $args->[1];
        my $lan   = $args->[2];
        my $owner = $args->[3];

        # Connect to LAN in active configuration
        my $power = `/opt/xcat/bin/rpower $node stat`;
        if ($power =~ m/: on/i) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_LAN -T $userId -v $addr -l $lan -o $owner"`;
            xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_LAN -T $userId -v $addr -l $lan -o $owner");
        }

        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_LAN_DM -T $userId -v $addr -n $lan -o $owner"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_LAN_DM -T $userId -v $addr -n $lan -o $owner");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # connectnic2vswitch [address] [vSwitch]
    elsif ($args->[0] eq "--connectnic2vswitch") {
        my $addr            = $args->[1];
        my $vswitch         = $args->[2];
        my $vswitchPortType = '';
        my $vswitchLanId    = '';
        my $argsSize        = @{$args};
        if ($argsSize > 3) {
            $vswitchPortType = $args->[3];
            $vswitchLanId    = $args->[4];
        }

        # Grant access to VSWITCH for Linux user
        $out = xCAT::zvmCPUtils->grantVSwitch($callback, $::SUDOER, $hcp, $userId, $vswitch, $vswitchPortType, $vswitchLanId);
        xCAT::zvmUtils->printLn($callback, "$node: Granting VSwitch ($vswitch $vswitchPortType $vswitchLanId) access for $userId... $out");

        # Connect to VSwitch in directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_Vswitch_DM -T $userId -v $addr -n $vswitch"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_Vswitch_DM -T $userId -v $addr -n $vswitch");

        # Connect to VSwitch in active configuration
        my $power = `/opt/xcat/bin/rpower $node stat`;
        if ($power =~ m/: on/i) {
            $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Connect_Vswitch -T $userId -v $addr -n $vswitch"`;
            xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Connect_Vswitch -T $userId -v $addr -n $vswitch");
        }

        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # copydisk [target address] [source node] [source address]
    elsif ($args->[0] eq "--copydisk") {
        my $tgtNode   = $node;
        my $tgtUserId = $userId;
        my $tgtAddr   = $args->[1];
        my $srcNode   = $args->[2];
        my $srcAddr   = $args->[3];

        # Get source userID
        @propNames = ('hcp', 'userid');
        $propVals = xCAT::zvmUtils->getNodeProps('zvm', $srcNode, @propNames);
        my $sourceId = $propVals->{'userid'};

        # Assume flashcopy is supported (via SMAPI)
        xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying $sourceId disk ($srcAddr) to $tgtUserId disk ($srcAddr) using FLASHCOPY");
        if (xCAT::zvmUtils->smapi4xcat($::SUDOER, $hcp)) {
            $out = xCAT::zvmCPUtils->smapiFlashCopy($::SUDOER, $hcp, $sourceId, $srcAddr, $tgtUserId, $srcAddr);
            xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

            # Exit if flashcopy completed successfully
            # Otherwise try CP FLASHCOPY
            if (($out =~ m/Done/i) or (($out =~ m/Return Code: 592/i) and ($out =~ m/Reason Code: 8888/i))) {
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
        while ($try > 0) {

            # New disk address
            $srcLinkAddr = $srcAddr + 1000;

            # Check if new disk address is used (source)
            $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $srcLinkAddr);

            # If disk address is used (source)
            while ($rc == 0) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $srcLinkAddr = $srcLinkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $srcLinkAddr);
            }

            # Link source disk
            # Because the zHCP has LNKNOPAS, no disk password is required
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Linking source disk ($srcAddr) as ($srcLinkAddr)");
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $sourceId $srcAddr $srcLinkAddr RR"`;

            # If link fails
            if ($out =~ m/not linked/i) {

                # Wait before trying again
                sleep(5);

                $try = $try - 1;
            } else {
                last;
            }
        }    # End of while ( $try > 0 )

        # If source disk is not linked
        if ($out =~ m/not linked/i) {
            xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to link source disk ($srcAddr)");
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed");

            # Exit
            return;
        }

        # Link target disk to HCP
        my $tgtLinkAddr;
        $try = 5;
        while ($try > 0) {

            # New disk address
            $tgtLinkAddr = $tgtAddr + 2000;

            # Check if new disk address is used (target)
            $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtLinkAddr);

            # If disk address is used (target)
            while ($rc == 0) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $tgtLinkAddr = $tgtLinkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtLinkAddr);
            }

            # Link target disk
            # Because the zHCP has LNKNOPAS, no disk password is required
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Linking target disk ($tgtAddr) as ($tgtLinkAddr)");
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $tgtAddr $tgtLinkAddr MR"`;

            # If link fails
            if ($out =~ m/not linked/i) {

                # Wait before trying again
                sleep(5);

                $try = $try - 1;
            } else {
                last;
            }
        }    # End of while ( $try > 0 )

        # If target disk is not linked
        if ($out =~ m/not linked/i) {
            xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to link target disk ($tgtAddr)");
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed");

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
        while (`ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"` && $wait < 90) {

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

            xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Flashcopy lock is enabled");
            xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Remove lock by deleting /tmp/.flashcopy_lock on the zHCP. Use caution!");
            return;
        } else {

            # Enable lock
            $out = `ssh $::SUDOER\@$hcp "$::SUDO touch /tmp/.flashcopy_lock"`;

            # Flashcopy source disk
            $out = xCAT::zvmCPUtils->flashCopy($::SUDOER, $hcp, $srcLinkAddr, $tgtLinkAddr);
            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

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
            xCAT::zvmUtils->printLn($callback, "$tgtNode: FLASHCOPY not working. Using Linux DD");

            # Enable disks
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $tgtLinkAddr);
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $srcLinkAddr);

            # Determine source device node
            $srcDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $srcLinkAddr);

            # Determine target device node
            $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtLinkAddr);

            # Format target disk
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Formating target disk ($tgtDevNode)");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

            # Check for errors
            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

                # Detatch disks from HCP
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

                return;
            }

            # Sleep 2 seconds to let the system settle
            sleep(2);

            # Automatically create a partition using the entire disk
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Creating a partition using the entire disk ($tgtDevNode)");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdasd -a /dev/$tgtDevNode"`;

            # Copy source disk to target disk (4096 block size)
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($srcDevNode) to target disk ($tgtDevNode)");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=4096 oflag=sync"`;

            # Disable disks
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtLinkAddr);
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $srcLinkAddr);

            # Check for error
            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

                # Detatch disks from HCP
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

                return;
            }

            # Sleep 2 seconds to let the system settle
            sleep(2);
        }

        # Detatch disks from HCP
        xCAT::zvmUtils->printLn($callback, "$tgtNode: Detatching target disk ($tgtLinkAddr)");
        xCAT::zvmUtils->printLn($callback, "$tgtNode: Detatching source disk ($srcLinkAddr)");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $srcLinkAddr"`;

        $out = "$tgtNode: Done";
    }

    # createfilesysnode [source file] [target file]
    elsif ($args->[0] eq "--createfilesysnode") {
        my $srcFile = $args->[1];
        my $tgtFile = $args->[2];

        my $argsSize = @{$args};
        if ($argsSize != 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Obtain corresponding WWPN and LUN of source file.
        # A sample url is '/dev/disk/by-path/ccw-0.0.1fb3-zfcp-0x5005076801102991:0x0021000000000000'.
        # (On Ubuntu it's '/dev/disk/by-path/ccw-0.0.1fb3-fc-0x5005076801102991-lun-33')
        # If it's multipath, it could be '0x5005076801102991;5005076801102992;5005076801102993' instead of '0x5005076801102991'.
        # Please note the url is not an actual device path. It's a parameter used to handle devices and the parameter
        # appears like a device path.
        # For the pattern '-zfcp-([\w;]+):(\w+)', '-zfcp-' is used to locate, ([\w;]+) will capture wwpn and store it into
        # variable $1, ':' is the delimiter and (\w+) will capture lun and store it into variable $2. The pattern for wwpn
        # and lun is different because wwpn may appear in multipath format but lun could only be one number.

        # Get source node OS
        my $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node);
        if (xCAT::zvmUtils->checkOutput($os) == -1) {
            return;
        }

        my ($devices, $wwpn, $lun);
        if ($os =~ m/ubuntu/i) {
            $srcFile =~ m/ccw-0.0.([\w;]+)-fc-([\w;]+)-lun-(\w+)/;
            ($devices, $wwpn, $lun) = ($1, $2, $3);
        } else {
            $srcFile =~ m/ccw-0.0.([\w;]+)-zfcp-([\w;]+):(\w+)/;
            ($devices, $wwpn, $lun) = ($1, $2, $3);
        }

        my $multipath = 0;
        if ($wwpn =~ m/;/) { $multipath = 1; }
        my @deviceList = split(";", $devices);

        my $cmd = "$::SUDO /usr/bin/stat --printf=%n $tgtFile";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
        if ($out eq $tgtFile) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) $tgtFile already exists");
            return;
        }

        # Use udev tools to create mountpoint. If it's signal path device, its devices path
        # is enough for udev. If it's multipath device, multipath device path are involved,
        # so we have to figure out its WWID and use the WWID to create mountpoint.
        my $wwid = '';
        if ($multipath) {

            # Find the name of the multipath device by arbitrary one path in the set
            my @wwpnList = split(";", $wwpn);
            my $curWwpn = '';
            foreach (@wwpnList) {
                if ($_ =~ m/^0x/i) {
                    $curWwpn = $_;
                } else {
                    $curWwpn = "0x$_";
                }

                # Try to get WWID by current WWPN.
                foreach (@deviceList) {
                    my $cur_device = $_;
                    if ($os =~ m/ubuntu/i) {
                        $srcFile =~ s/ccw-0.0.[0-9a-f;]+-fc-0x[0-9a-f;]+-lun/ccw-0.0.$cur_device-fc-$curWwpn-lun/i;
                    } else {
                        $srcFile =~ s/ccw-0.0.[0-9a-f;]+-zfcp-0x[0-9a-f;]+:/ccw-0.0.$cur_device-zfcp-$curWwpn:/i;
                    }
                    my $cmd = "$::SUDO /usr/bin/stat --printf=%n $srcFile";
                    $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
                    if ($out ne $srcFile) {
                        xCAT::zvmUtils->printLn($callback, "$node: (Warning) $srcFile does not exist");
                        next;
                    }

                    $cmd = $::SUDO . ' /sbin/udevadm info --query=all --name=' . $srcFile;
                    $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                    if (xCAT::zvmUtils->checkOutput($out) == -1) {
                        return;
                    }
                    $out = `echo "$out" | egrep -a -i "ID_SERIAL="`;
                    $out =~ m/ID_SERIAL=(\w+)\s*$/;
                    $wwid = $1;
                    if ($wwid) { last; }
                }
                if ($wwid) { last; }
            }
            if (!$wwid) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) zfcp device $wwpn:$lun not found in OS");
                return;
            }
        } else {
            my $isFound = 0;
            foreach (@deviceList) {
                my $cur_device = $_;
                if ($os =~ m/ubuntu/i) {
                    $srcFile =~ s/ccw-0.0.[0-9a-f;]+-fc/ccw-0.0.$cur_device-fc/i;
                } else {
                    $srcFile =~ s/ccw-0.0.[0-9a-f;]+-zfcp/ccw-0.0.$cur_device-zfcp/i;
                }

                my $cmd = "$::SUDO /usr/bin/stat --printf=%n $srcFile";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
                if ($out ne $srcFile) {
                    xCAT::zvmUtils->printLn($callback, "$node: (warning) $srcFile does not exist");
                } else {
                    $isFound = 1;
                }
            }
            if (!$isFound) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) zfcp device $wwpn:$lun not found in OS");
                return;
            }
        }

        # Create udev config file if not exist
        my $configFile = '/etc/udev/rules.d/56-zfcp.rules';
        $cmd = "$::SUDO test -e $configFile && echo Exists";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
        if (!($out)) {
            $cmd = "$::SUDO touch $configFile";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            if ($os =~ m/rhel/i) {

                # will not check for errors here
                my $zfcp_rule = 'KERNEL==\"zfcp\", RUN+=\"/sbin/zfcpconf.sh\"';
                my $multipath_rule = 'KERNEL==\"zfcp\", RUN+=\"/sbin/multipath -r\"';
                $cmd = $::SUDO . ' echo ' . $zfcp_rule . ' >> ' . $configFile;
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
                $cmd = $::SUDO . ' echo ' . $multipath_rule . ' >> ' . $configFile;
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
            }
        }

        # Add the entry into udev config file
        my ($create_symlink_cmd, $reload_cmd, $update_rule_cmd);
        my $tgtFileName = $tgtFile;
        $tgtFileName =~ s/\/dev\///;
        if ($multipath) {
            my $linkItem = 'KERNEL==\"dm-*\", ENV{DM_UUID}==\"mpath-' . $wwid . '\", SYMLINK+=\"' . $tgtFileName . '\"';
            $update_rule_cmd = $::SUDO . ' echo ' . $linkItem . '>>' . $configFile;
            $reload_cmd = "$::SUDO udevadm control --reload";
            $create_symlink_cmd = "$::SUDO udevadm trigger --sysname-match=dm-*";
        } else {
            my $linkItem = 'KERNEL==\"sd*\", ATTRS{wwpn}==\"' . $wwpn . '\", ATTRS{fcp_lun}==\"' . $lun . '\", SYMLINK+=\"' . $tgtFileName . '\%n\"';
            $update_rule_cmd = $::SUDO . ' echo ' . $linkItem . '>>' . $configFile;
            $reload_cmd         = "$::SUDO udevadm control --reload";
            $create_symlink_cmd = "$::SUDO udevadm trigger --sysname-match=sd*";
        }

        $cmd = "$update_rule_cmd ; $reload_cmd ; $create_symlink_cmd";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
        if (xCAT::zvmUtils->checkOutput($out) == -1) {
            return;
        }

        xCAT::zvmUtils->printLn($callback, "$node: Creating file system node $tgtFile... Done");
    }

    # dedicatedevice [virtual device] [real device] [mode (1 or 0)]
    elsif ($args->[0] eq "--dedicatedevice") {
        my $vaddr = $args->[1];
        my $raddr = $args->[2];
        my $mode  = $args->[3];

        my $argsSize = @{$args};
        if ($argsSize != 4) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }
        my $doActive = 1;

        # Dedicate device to directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Dedicate_DM -T $userId -v $vaddr -r $raddr -R $mode"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Device_Dedicate_DM -T $userId -v $vaddr -r $raddr -R $mode");
        if (($out =~ m/Return Code: 404/i) and ($out =~ m/Reason Code: 4/i)) {
            $out = "Dedicating device $raddr to $userId" . "'s directory entry... Done";
            $doActive = 0; # Have already been defined before, no need to make active in this case.
        }
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        # Dedicate device to active configuration
        my $power = `/opt/xcat/bin/rpower $node stat`;
        if (($power =~ m/: on/i) and $doActive) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Dedicate -T $userId -v $vaddr -r $raddr -R $mode"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Device_Dedicate -T $userId -v $vaddr -r $raddr -R $mode");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
        }

        $out = "";
    }

    # deleteipl
    elsif ($args->[0] eq "--deleteipl") {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_IPL_Delete_DM -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_IPL_Delete_DM -T $userId");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # formatdisk [address] [multi password]
    elsif ($args->[0] eq "--formatdisk") {
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
        while ($try > 0) {

            # New disk address
            $tgtLinkAddr = $tgtAddr + 1000;

            # Check if new disk address is used (target)
            $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtLinkAddr);

            # If disk address is used (target)
            while ($rc == 0) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $tgtLinkAddr = $tgtLinkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtLinkAddr);
            }

            # Link target disk
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Linking target disk ($tgtAddr) as ($tgtLinkAddr)");
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $tgtAddr $tgtLinkAddr MR"`;

            # If link fails
            if ($out =~ m/not linked/i || $out =~ m/DASD $tgtLinkAddr forced R\/O/i) {

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
        if ($out =~ m/not linked/i || $out =~ m/DASD $tgtLinkAddr forced R\/O/i) {
            xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to link target disk ($tgtAddr)");
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed");

            # Detatch link because only linked as R/O
            `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;

            # Exit
            return;
        }

        #*** Format disk ***
        my @words;
        if ($rc == -1) {

            # Enable disk
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $tgtLinkAddr);

            # Determine target device node
            $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtLinkAddr);

            # Format target disk
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Formating target disk ($tgtDevNode)");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

            # Check for errors
            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");
                return;
            }
        }

        # Disable disk
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtLinkAddr);

        # Detatch disk from HCP
        xCAT::zvmUtils->printLn($callback, "$tgtNode: Detatching target disk ($tgtLinkAddr)");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtLinkAddr"`;

        $out = "$tgtNode: Done";
    }

    # grantvswitch [VSwitch]
    elsif ($args->[0] eq "--grantvswitch") {
        my $vsw             = $args->[1];
        my $vswitchPortType = '';
        my $vswitchLanId    = '';

        my $argsSize = @{$args};
        if ($argsSize > 2) {
            $vswitchPortType = $args->[2];
            $vswitchLanId    = $args->[3];
        }

        $out = xCAT::zvmCPUtils->grantVSwitch($callback, $::SUDOER, $hcp, $userId, $vsw, $vswitchPortType, $vswitchLanId);
        $out = xCAT::zvmUtils->appendHostname($node, "Granting VSwitch ($vsw) access for $userId... $out");
    }

    # disconnectnic [address]
    elsif ($args->[0] eq "--disconnectnic") {
        my $addr = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Disconnect_DM -T $userId -v $addr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Disconnect_DM -T $userId -v $addr");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # punchfile [file path] [class (optional)] [remote host (optional)]
    elsif ($args->[0] eq "--punchfile") {

        # Punch a file to a the node reader
        my $argsSize = @{$args};
        if (($argsSize < 2) || ($argsSize > 4)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $filePath = $args->[1];
        my $class    = "A";          # Default spool class should be A
        my $remoteHost;
        if ($argsSize > 2) {
            $class = $args->[2];
        }
        if ($argsSize > 3) {
            $remoteHost = $args->[3];    # Must be specified as user@host
        }

        # Obtain file name
        my $fileName  = basename($filePath);
        my $trunkFile = "/tmp/$node-$fileName";

        # Validate class
        if ($class !~ /^[a-zA-Z0-9]$/) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid spool class: $class. It should be 1-character alphanumeric");
            return;
        }

        # If a remote host is specified, obtain the file from the remote host
        # The xCAT public SSH key must have been already setup if this is to work
        my $rc;
        if (defined $remoteHost) {
            $rc = `/usr/bin/scp $remoteHost:$filePath $trunkFile 2>/dev/null; echo $?`;
        } else {
            $rc = `/bin/cp $filePath $trunkFile 2>/dev/null; echo $?`;
        }

        if ($rc != '0') {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy over source file");
            return;
        }

        # Check the node flag, if the node has xcatconf4z flag set,  punch it directly.
        # Otherwise, put files into a temp directory for later use.
        my $nodeFlag    = '';
        my $cfgTrunkDir = "/tmp/configdrive/$node/";
        my @propNames   = ('status');
        my $propVals = xCAT::zvmUtils->getTabPropsByKey('zvm', 'node', $node, @propNames);
        $nodeFlag = $propVals->{'status'};
        if ($nodeFlag =~ /XCATCONF4Z=0/) {
            if (!-d $cfgTrunkDir) {
                mkpath($cfgTrunkDir);
            }
            $rc = `/bin/cp $trunkFile $cfgTrunkDir/$fileName 2>/dev/null; echo $?`;
            `rm -rf $trunkFile`;
            if ($rc != '0') {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy over source file $trunkFile to directory $cfgTrunkDir, please check if xCAT is running out of space");
                return;
            }

        } else {

            # Set up punch device
            $rc = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/cio_ignore -r d"`;
            xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "d");

            # Send over file to zHCP and punch it to the node's reader
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $trunkFile, $trunkFile);
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $trunkFile, $fileName, "", $class);

            # No extra steps are needed if the punch succeeded or failed, just output the results
            xCAT::zvmUtils->printLn($callback, "$node: Punching $fileName to reader... $out");

            # Remove temporary file
            `rm -rf $trunkFile`;
            `ssh $::SUDOER\@$hcp "$::SUDO rm -f $trunkFile"`;
            $out = "";
        }
    }

    # purgerdr
    elsif ($args->[0] eq "--purgerdr") {

        # Purge the reader of node
        $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
        $out = xCAT::zvmUtils->appendHostname($node, "$out");
    }

    # removediskfrompool [function] [region] [group]
    elsif ($args->[0] eq "--removediskfrompool") {

        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor($callback, $node, $args);
    }

    # removezfcpfrompool [pool] [lun]
    elsif ($args->[0] eq "--removezfcpfrompool") {

        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor($callback, $node, $args);
    }

    # removedisk [virtual address]
    elsif ($args->[0] eq "--removedisk") {
        my $addr = $args->[1];

        # Remove from active configuration
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "ping") {
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $node, "-d", $addr);
            $out = `ssh $node "/sbin/vmcp det $addr"`;
        }

        # Remove from user directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Delete_DM -T $userId -v $addr -e 0"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Delete_DM -T $userId -v $addr -e 0");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # removefilesysnode [target file]
    elsif ($args->[0] eq "--removefilesysnode") {
        my $tgtFile = $args->[1];

        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Unmount this disk and remove this disk from udev config file, but ignore the output
        my $configFile  = '/etc/udev/rules.d/56-zfcp.rules';
        my $tgtFileName = $tgtFile;
        $tgtFileName =~ s/\/dev\///;
        my $update_rule_cmd_sd = $::SUDO . ' sed -i -e /SYMLINK+=\"' . $tgtFileName . '\%n\"/d ' . $configFile; # For single device
        my $update_rule_cmd_dm = $::SUDO . ' sed -i -e /SYMLINK+=\"' . $tgtFileName . '\"/d ' . $configFile; # For multipath

        my $reload_cmd = "$::SUDO udevadm control --reload";
        my $create_symlink_cmd_sd = "$::SUDO udevadm trigger --sysname-match=sd*"; # For single device
        my $create_symlink_cmd_dm = "$::SUDO udevadm trigger --sysname-match=dm-*"; # For multipath

        my $cmd = "$update_rule_cmd_sd ; $update_rule_cmd_dm ; $reload_cmd ; $create_symlink_cmd_sd ; $create_symlink_cmd_dm";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
        if (xCAT::zvmUtils->checkOutput($out) == -1) {
            return;
        }
        xCAT::zvmUtils->printLn($callback, "$node: Removing file system node $tgtFile... Done");
    }

    # removenic [address]
    elsif ($args->[0] eq "--removenic") {
        my $addr = $args->[1];

        # Remove from active configuration
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "ping") {
            $out = `ssh $node "/sbin/vmcp det nic $addr"`;
        }

        # Remove from user directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Adapter_Delete_DM -T $userId -v $addr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Adapter_Delete_DM -T $userId -v $addr");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # removeprocessor [address]
    elsif ($args->[0] eq "--removeprocessor") {
        my $addr = $args->[1];

        # Remove from user directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_CPU_Delete_DM -T $userId -v $addr"`;
        xCAT::zvmUtils->printSyslog("smcli Image_CPU_Delete_DM -T $userId -v $addr");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # removeloaddev [wwpn] [lun]
    elsif ($args->[0] eq "--removeloaddev") {
        my $wwpn = $args->[1];
        my $lun  = $args->[2];

        xCAT::zvmUtils->printLn($callback, "$node: Removing LOADDEV directory statements");

        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

        # Get user directory entry
        my $updateEntry   = 0;
        my $userEntryFile = "/tmp/$node.txt";
        my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $userId | sed '\$d'");
        chomp($userEntry);
        if (!$wwpn && !$lun) {

            # If no WWPN or LUN is provided, delete all LOADDEV statements
            `echo "$userEntry" | grep -a -v "LOADDEV" > $userEntryFile`;
            $updateEntry = 1;
        } else {

            # Delete old directory entry file
            `rm -rf $userEntryFile`;

            # Remove LOADDEV PORTNAME and LUN statements in directory entry
            my @lines = split('\n', $userEntry);
            foreach (@lines) {
                if (!(length $_)) { next; }

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
            $out = `/opt/xcat/bin/chvm $node --replacevs $userEntryFile 2>&1`;
            xCAT::zvmUtils->printLn($callback, "$out");

            # Delete directory entry file
            `rm -rf $userEntryFile`;
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: No changes required in the directory entry");
        }

        $out = "";
    }

    # removezfcp [device address] [wwpn] [lun] [persist (0 or 1) (optional)]
    elsif ($args->[0] eq "--removezfcp") {
        my $device  = $args->[1];
        my $wwpn    = $args->[2];
        my $lun     = $args->[3];
        my $persist = "0";          # Optional

        # Delete 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

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
        if (xCAT::zvmUtils->checkOutput($pool) == -1) {
            xCAT::zvmUtils->printLn($callback, "$pool");
            return;
        }
        if (!$pool) {

            # Continue to try and remove the SCSI/FCP device even when it is not found in a storage pool
            xCAT::zvmUtils->printLn($callback, "$node: Could not find FCP device in any FCP storage pool");
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: Found FCP device in $pool");

            my $select = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf"`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $::ZFCPPOOL/$pool.conf\" ", $hcp, "changeVM", $select, $node);
            if ($rc != 0) {
                xCAT::zvmUtils->printLn($callback, "$outmsg");
                return;
            }
            $select = `echo "$select" | egrep -a -i "$wwpn,$lun"`;
            chomp($select);
            my @info = split(',', $select);

            # A node can only remove a zFCP device that belongs to itself
            if (('used' eq $info[0]) && ($node ne $info[5])) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) The zFCP device 0x$wwpn/0x$lun does not belong to the node $node.");
                return;
            }

            # If the device is not known, try to find it in the storage pool
            if ($device && $device !~ /^[0-9a-f;]/i) {
                $device = $info[6];
            }

            my $status = "free";
            my $owner  = "";
            if ($persist) {

                # Keep the device reserved if persist = 1
                $status = "reserved";
            }

            my %criteria = (
                'status' => $status,
                'wwpn'   => $wwpn,
                'lun'    => $lun,
                'owner'  => $owner,
            );
            my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
            my %results = %$resultsRef;

            if ($results{'rc'} == -1) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find zFCP device");
                return;
            }

            # Obtain the device assigned by xCAT
            $wwpn = $results{'wwpn'};
            $lun  = $results{'lun'};
        }

        # De-configure SCSI over FCP inside node (if online)
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "ping") {

            # Delete WWPN and LUN from sysfs
            $device = lc($device);
            $wwpn   = lc($wwpn);

            my @device_list = split(';', $device);
            foreach (@device_list) {
                my $cur_device = $_;
                if (!$cur_device) { next; }
                my @wwpnList = split(";", $wwpn);
                foreach (@wwpnList) {
                    my $cur_wwpn = $_;
                    if (!$cur_wwpn) { next; }

                    # unit_remove does not exist on SLES 10!
                    $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo 0x$lun > /sys/bus/ccw/drivers/zfcp/0.0.$cur_device/0x$cur_wwpn/unit_remove");

                    # Get source node OS
                    my $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node);

                    # Delete WWPN and LUN from configuration files
                    my $expression = "";
                    if ($os =~ m/sles1[12]/i) {

                        #   SLES 11&12: /etc/udev/rules.d/51-zfcp*
                        $expression = "/$lun/d";
                        my $cmd = "$::SUDO sed -i -e $expression /etc/udev/rules.d/51-zfcp-0.0.$cur_device.rules";
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                        if (xCAT::zvmUtils->checkOutput($out) == -1) {
                            return;
                        }

                    } elsif ($os =~ m/rhel/i) {

                        #   RHEL: /etc/zfcp.conf
                        $expression = "/$lun/d";
                        my $cmd = "$::SUDO sed -i -e $expression /etc/zfcp.conf";
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                        if (xCAT::zvmUtils->checkOutput($out) == -1) {
                            return;
                        }

                    } elsif ($os =~ m/ubuntu/i) {

                        #   Ubuntu: chzdev zfcp-lun 0.0.$device:0x$wwpn:0x$lun -d
                        my $cmd = "$::SUDO /sbin/chzdev zfcp-lun 0.0.$cur_device:0x$cur_wwpn:0x$lun -d";
                        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                        if (xCAT::zvmUtils->checkOutput($out) == -1) {
                            return;
                        }
                    }
                }
            }

            # will not check for errors here
            my $cmd = "$::SUDO /sbin/multipath -W";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
            $cmd = "$::SUDO /sbin/multipath -r";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);

            xCAT::zvmUtils->printLn($callback, "$node: De-configuring FCP device on host... Done");
        }

        $out = "";
    }

    # replacevs [file]
    elsif ($args->[0] eq "--replacevs") {
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
                xCAT::zvmUtils->printLn($callback, "$node: (Error) File does not exist");
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
                if (!(length $_)) { next; }
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
            xCAT::zvmUtils->printLn($callback, "$node: (Error) No directory entry file specified");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Specify a text file containing the updated directory entry");
            return;
        }

        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # resetsmapi
    elsif ($args->[0] eq "--resetsmapi") {

        # This is no longer supported in chvm. Using chhypervisor instead.
        changeHypervisor($callback, $node, $args);
    }

    # setipl [ipl target] [load parms] [parms]
    elsif ($args->[0] eq "--setipl") {
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
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # setpassword [password]
    elsif ($args->[0] eq "--setpassword") {
        my $pw = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Password_Set_DM -T $userId -p $pw"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Password_Set_DM -T $userId -p $pw");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # setloaddev [wwpn] [lun] [isHex (0 or 1, optional)] [scpdata (optional)]
    elsif ($args->[0] eq "--setloaddev") {
        my $argsSize = @{$args};
        if (($argsSize != 3) && ($argsSize != 5)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $updateScpdata = 0;
        if ($argsSize > 3) {
            $updateScpdata = 1;
        }

        my $wwpn = $args->[1];
        my $lun  = $args->[2];

        # isHex and scpdata must appear or disappear concurrently.
        my $isHex   = 0;
        my $scpdata = '';
        my $scptype = '';
        if ($updateScpdata) {
            $isHex   = $args->[3];
            $scpdata = $args->[4];
            if ($isHex) {
                $scptype = '3';
            } else {
                $scptype = '2';

                # If the scpdata is not in HEX form, it may contain white space.
                # So wrap the parameter with quote marks.
                $scpdata = "'" . $scpdata . "'";
            }
        }

        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

        xCAT::zvmUtils->printLn($callback, "$node: Setting LOADDEV directory statements");

        # Change SCSI definitions
`ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_SCSI_Characteristics_Define_DM  -T $userId -b '' -k '' -l $lun -p $wwpn -s $scptype -d $scpdata"`;
        xCAT::zvmUtils->printSyslog("smcli Image_SCSI_Characteristics_Define_DM  -T $userId -b '' -k '' -l $lun -p $wwpn -s $scptype -d $scpdata");

        $out = "";
    }

    # smcli [smcli command]
    #     'smcli command' is the smcli command less the 'smcli' command name.  The command will
    #         normally have a %userid% substring within it which indicates the location in the
    #         command that should be replaced with the z/VM userid for the target node.  This can
    #         occur multiple times within the command string.
    #         e.g. chvm gpok168 --smcli 'Virtual_Network_Adapter_Query_Extended -T "%userid%" -k image_device_number=*'
    #              chvm gpok168 --smcli 'Image_Definition_Update_DM -h'
    # The output from the smcli invocation is returned.  If we cannot SSH into the
    # zhcp server then an error message indicating this failure is returned.
    elsif ($args->[0] eq "--smcli") {
        my @smcliCmd;
        my $useridKeyword = '\%userid\%';

        @smcliCmd = @{$args};
        shift @smcliCmd;
        if (!@smcliCmd) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $smcliCmdStr = join(' ', @smcliCmd);
        if ($smcliCmdStr =~ /$useridKeyword/) {

            # Replace userid keyword with the userid for the node.
            $smcliCmdStr =~ s/$useridKeyword/$userId/g;
        }

        $out = `ssh $::SUDOER\@$hcp "$::DIR/smcli $smcliCmdStr"`;
        my $rc = $? >> 8;

        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("$node: (Error) unable to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) unable to communicate with the zhcp system: $hcp");
            return;
        }
    }

    # undedicatedevice [virtual device]
    elsif ($args->[0] eq "--undedicatedevice") {
        my $vaddr = $args->[1];

        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Undedicate device in directory entry
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Undedicate_DM -T $userId -v $vaddr"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Device_Undedicate_DM -T $userId -v $vaddr");
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        # Undedicate device in active configuration
        my $power = `/opt/xcat/bin/rpower $node stat`;
        if ($power =~ m/: on/i) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Device_Undedicate -T $userId -v $vaddr"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Device_Undedicate -T $userId -v $vaddr");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
        }

        $out = "";
    }

    # sharevolume [vol_addr] [share_enable (YES or NO)]
    elsif ($args->[0] eq "--sharevolume") {
        my $volAddr = $args->[1];
        my $share   = $args->[2];

        # Add disk to running system
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Share -T $userId -k img_vol_addr=$volAddr -k share_enable=$share"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Volume_Share -T $userId -k img_vol_addr=$volAddr -k share_enable=$share");
        $out = xCAT::zvmUtils->appendHostname($node, $out);
    }

    # setprocessor [count]
    elsif ($args->[0] eq "--setprocessor") {
        my $cpuCount = $args->[1];
        my @allCpu;
        my $count = 0;
        my $newAddr;
        my $cpu;
        my @allValidAddr = ('00', '01', '02', '03', '04', '05', '06', '07', '09', '09', '0A', '0B', '0C', '0D', '0E', '0F',
'10', '11', '12', '13', '14', '15', '16', '17', '19', '19', '1A', '1B', '1C', '1D', '1E', '1F',
'20', '21', '22', '23', '24', '25', '26', '27', '29', '29', '2A', '2B', '2C', '2D', '2E', '2F',
'30', '31', '32', '33', '34', '35', '36', '37', '39', '39', '3A', '3B', '3C', '3D', '3E', '3F');

        # Get current CPU count and address
        xCAT::zvmUtils->printSyslog("smcli Image_Definition_Query_DM -T $userId -k CPU");
        my $proc = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $userId -k CPU"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $userId -k CPU\"", $hcp, "changeVM", $proc, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $proc = `echo "$proc" | egrep -a -i CPU=`;
        while (index($proc, "CPUADDR") != -1) {
            my $position = index($proc, "CPUADDR");
            my $address = substr($proc, $position + 8, 2);
            push(@allCpu, $address);
            $proc = substr($proc, $position + 10);
        }

        # Find free valid CPU address
        my %allCpu = map { $_ => 1 } @allCpu;
        my @addrLeft = grep(!defined $allCpu{$_}, @allValidAddr);

        # Add new CPUs
        if ($cpuCount > @allCpu) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k CPU_MAXIMUM=COUNT=$cpuCount -k TYPE=ESA"`;
            xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k CPU_MAXIMUM=COUNT=$cpuCount -k TYPE=ESA");
            while ($count < $cpuCount - @allCpu) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k CPU=CPUADDR=$addrLeft[$count]"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k CPU=CPUADDR=$addrLeft[$count]");
                $count++;
            }

            # Remove CPUs
        } else {
            while ($count <= @allCpu - $cpuCount) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_CPU_Delete_DM -T $userId -v $allCpu[@allCpu-$count]"`;
                xCAT::zvmUtils->printSyslog("smcli Image_CPU_Delete_DM -T $userId -v $allCpu[@allCpu-$count]");
                $count++;
            }
        }

        xCAT::zvmUtils->printLn($callback, "$node: $out");
        $out = "";
    }

    # setmemory [size]
    elsif ($args->[0] eq "--setmemory") {

        # Memory hotplug not supported, just change memory size in user directory
        my $size = $args->[1];

        if (!($size =~ m/G/i || $size =~ m/M/i)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Size can be Megabytes (M) or Gigabytes (G)");
            return;
        }

        # Set initial memory to 1M first, make this function able to increase/descrease the storage
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=1M"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=1M");

        # Set both initial memory and maximum memory to be the same
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=$size -k STORAGE_MAXIMUM=$size"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Definition_Update_DM -T $userId -k STORAGE_INITIAL=$size -k STORAGE_MAXIMUM=$size");

        xCAT::zvmUtils->printLn($callback, "$node: $out");
        $out = "";
    }

    # setconsole [start|stop]
    elsif ($args->[0] eq "--setconsole") {

        # Start or stop spool console
        my $action = $args->[1];
        my $consoleCmd;

        # Start console spooling
        if ($action eq 'start') {
            $consoleCmd = "spool console start";
            $out = xCAT::zvmCPUtils->sendCPCmd($::SUDOER, $hcp, $userId, $consoleCmd);
            xCAT::zvmUtils->printLn($callback, "$node: $out");
        }

        # Stop console
        elsif ($action eq 'stop') {
            $consoleCmd = "spool console stop";
            $out = xCAT::zvmCPUtils->sendCPCmd($::SUDOER, $hcp, $userId, $consoleCmd);
            xCAT::zvmUtils->printLn($callback, "$node: $out");
        }

        else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Option not supported");
        }
    }

    # aemod [function] [parm1 (optional)] [parm2 (optional)]..
    elsif ($args->[0] eq "--aemod") {
        my $parm         = "";
        my $conf         = "";
        my $i            = 0;
        my $invokescript = "invokeScript.sh";
        my $workerscript = $args->[1];
        my $argsSize     = @{$args};
        my $trunkFile    = "aemod.doscript";
        my $class        = "X";
        my $tempDir      = `/bin/mktemp -d /tmp/aemod.XXXXXXXX`;
        chomp($tempDir);

        $conf .= sprintf("%s\n", "#!/bin/bash");
        $parm = "/bin/bash $workerscript";
        for ($i = 2 ; $i < $argsSize ; $i++) {
            $parm .= ' ';
            $parm .= $args->[$i];
        }
        $conf .= sprintf("%s\n", $parm);

        open(FILE, ">$tempDir/$invokescript");
        print FILE ("$conf");
        close(FILE);

        if (-e "/opt/xcat/share/xcat/scripts/$workerscript") {

            # Generate the tar package for punch
            my $oldpath = cwd();
            system("cp /opt/xcat/share/xcat/scripts/$workerscript $tempDir");
            chdir($tempDir);
            system("tar cvf $trunkFile $invokescript $workerscript");

            # Check the node, if node status contains XCATCONF4Z=0, store it in a tmp directory for later use.
            # Otherwise, punch it directly.
            my $nodeFlag    = '';
            my $cfgTrunkDir = "/tmp/configdrive/$node/";
            my @propNames   = ('status');
            my $propVals = xCAT::zvmUtils->getTabPropsByKey('zvm', 'node', $node, @propNames);
            $nodeFlag = $propVals->{'status'};
            if ($nodeFlag =~ /XCATCONF4Z=0/) {
                if (!-d $cfgTrunkDir) {
                    mkpath($cfgTrunkDir, 0, 0750);
                }
                my $rc = `/bin/cp -r $tempDir $cfgTrunkDir/ 2>/dev/null; echo $?`;
                `rm -rf $tempDir`;
                if ($rc != '0') {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy over source directory $tempDir to directory $cfgTrunkDir, please check if xCAT is running out of space");
                    rmtree "$cfgTrunkDir";
                    return;
                }
            } else {

                # Online zHCP's punch device
                $out = xCAT::zvmUtils->onlineZhcpPunch($::SUDOER, $hcp);
                if ($out =~ m/Failed/i) {
                    xCAT::zvmUtils->printLn($callback, "$node: Online zHCP's punch device... $out");
                    `rm -rf $tempDir`;
                    return;
                }

                # Punch file to reader
                xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $trunkFile, $trunkFile);
                $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $trunkFile, $trunkFile, "", $class);
                chdir($oldpath);
                if ($out =~ m/Failed/i) {
                    xCAT::zvmUtils->printLn($callback, "$node: Punching file to reader... $out");
                    `rm -rf $tempDir`;
                    return;
                }
            }
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) The worker script $workerscript does not exist on xCAT server");
            rmdir($tempDir);
            return;
        }
    }

    # Otherwise, print out error
    else {
        $out = "$node: (Error) Option '$args->[0]' not supported on chvm";
        xCAT::zvmUtils->printLn($callback, "$out");
    }
    return;
}

#-------------------------------------------------------

=head3   powerVM

    Description  : Power on or off a given node
    Arguments    :   Node
                     Option [on|off|reboot|reset|stat|isreachable]
    Returns      : Nothing
    Example      : powerVM($callback, $node, $args);

=cut

#-------------------------------------------------------
sub powerVM {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid', 'status');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);
    my $status = $propVals->{'status'};

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {

        # This may be a stat query to a zVM host hypervisor, if so return on/off for the zhcp node name
        # Look in the hosts table for this zhcp to get the node name then look back in zvm table
        # to get the userid to check the power on.
        if ($args->[0] eq 'stat') {
            my @propNames2 = ('node');
            my $propVals2 = xCAT::zvmUtils->getTabPropsByKey('hosts', 'hostnames', $hcp, @propNames2);
            if (!$propVals2->{'node'}) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to look up zhcp node for $hcp");
                return;
            }

            # Now we have a node name for this zhcp, get the userid so we can check the power.
            my $node2 = $propVals2->{'node'};
            $propVals2 = xCAT::zvmUtils->getNodeProps('zvm', $node2, @propNames);
            $userId = $propVals2->{'userid'};
            if (!$userId) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID on zhcp node $node2");
                return;
            }
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
            return;
        }
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("powerVM() node:$node userid:$userId zHCP:$hcp sudoer:$::SUDOER sudo:$::SUDO");

    # Output string
    my $out;

    # Power on virtual server
    if ($args->[0] eq 'on') {

        # Check the node flag, if it contain XCATCONF4Z=0, it indicate that this node will be deployed by using non-xcatconf4z type
        # image, it will call the reconstructor to generate a final punched file, and punched to reader. otherwise, power on the vm directly.
        my $nodeFlag    = '';
        my $cfgTrunkDir = "/tmp/configdrive/$node";
        my @propNames   = ('status');
        my $propVals = xCAT::zvmUtils->getTabPropsByKey('zvm', 'node', $node, @propNames);
        my $cfgdrive     = '';
        my $destCfgdrive = '';
        my $class        = "X";
        $nodeFlag = $propVals->{'status'};

        # When start the non-xcatconf4z cloud image at first time, we need to modify cfgdrive.tgz to append xCAT key, so adding SSH and IUCV
        # check to ensure it is the first start, since after vm is started SSH and IUCV flag is set.
        if ($nodeFlag =~ /XCATCONF4Z=0/ && $nodeFlag !~ /SSH=1/ && $nodeFlag != /IUCV=1/) {

            # Call constructor to generate a final configdrive for target vm
            $cfgdrive = xCAT::zvmUtils->genCfgdrive($cfgTrunkDir);
            if (-e $cfgdrive) {

                # Purge reader
                $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
                xCAT::zvmUtils->printLn($callback, "$node: Purging reader... Done");

                # Online zHCP's punch device
                $out = xCAT::zvmUtils->onlineZhcpPunch($::SUDOER, $hcp);
                if ($out =~ m/Failed/i) {
                    `rm -rf $cfgTrunkDir`;
                    xCAT::zvmUtils->printLn($callback, "$node: Online zHCP's punch device... $out");
                    return;
                }

                $destCfgdrive = "/tmp/$node-" . basename($cfgdrive);

                # Punch file to reader
                xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $cfgdrive, $destCfgdrive);
                `/bin/rm -rf $cfgTrunkDir`;

                $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $destCfgdrive, basename($cfgdrive), "", $class);
                `ssh $::SUDOER\@$hcp "$::SUDO /bin/rm $destCfgdrive"`;
                if ($out =~ m/Failed/i) {
                    xCAT::zvmUtils->printLn($callback, "$node: Punching final config drive to reader... $out");
                    return;
                }
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: Failed to generate the final cfgdrive for target vm");
                return;
            }
        }

        xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $userId");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $userId"`;
        my $rc = $? >> 8;
        $out = xCAT::zvmUtils->trimStr($out);
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("$node: (Error) Failed to communicate with the zhcp system: $hcp output:$out");
            return;
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: $out");
        }

        my $delscriptpath = "/var/lib/sspmod/portdelete";

        # If user doesn't use NIC which is record in switch table. When power on the instance, delete
        # the port at the same time. Use file "portdelete" to delete the ports, it exists on CMA appliance.
        # If the script of "portdelete" doesn't exist, the function is skipped, ports will not be deleted.
        if (-e $delscriptpath and $status =~ /CLONING=1/ and $status =~ /CLONE_ONLY=1/) {
            xCAT::zvmUtils->printSyslog("$node: Delete the port that is NOT used for Alternate Deploy Provisioning.");

            # Get the list from switch table.
            my $switchTab = xCAT::Table->new('switch');
            if (!$switchTab) {
                xCAT::zvmUtils->printSyslog("$node: (Error) Could not open table: switch.");
                return;
            }
            my @portData = $switchTab->getAllAttribsWhere("node='" . lc($userId) . "'", 'port');
            $switchTab->close;
            my $ports = '';
            foreach (@portData) {
                $ports = $ports . ' ' . $_->{'port'};
            }
            my $out = `$delscriptpath $ports`;
            $rc  = $?;
            $out = xCAT::zvmUtils->trimStr($out);
            if ($rc != 0) {
                xCAT::zvmUtils->printSyslog("$node:(Error) Failed to delete port output:$out");
                return;
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: $out");
            }
        }

        # If we were cloning the server then turn off cloning flag.
        if ($status =~ /CLONING=1/) {
            $status =~ s/CLONING=1/CLONING=0/g;
        }

        if ($status =~ /CLONE_ONLY=1/) {

            # Indicate node is being powered up so that we will confirm the IP address on the nodestat.
            if ($status =~ /POWER_UP=/) {
                $status =~ s/POWER_UP=0/POWER_UP=1/g;
            } else {
                $status = "$status;POWER_UP=1";
            }
            xCAT::zvmUtils->setNodeProp('zvm', $node, 'status', $status);
        }
    }

    # Power off virtual server
    elsif ($args->[0] eq 'off') {
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId -f IMMED");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId -f IMMED"`;
        my $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
            return;
        }
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($out =~ m/Return Code: 200/i) {
            if ($out =~ m/Reason Code: 12/i) {
                xCAT::zvmUtils->printSyslog("$userId already logged off.");
                $out = "$userId already logged off.";
                $rc  = 0;
            } elsif ($out =~ m/Reason Code: 16/i) {
                xCAT::zvmUtils->printSyslog("$userId in process of logging off.");
                $out = "$userId in process of logging off.";
                $rc  = 0;
            }
        }
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $userId output: $out");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            return;
        }
        xCAT::zvmUtils->printLn($callback, "$node: $out");
    }

    # Power off virtual server (gracefully)
    elsif ($args->[0] eq 'softoff') {
        my $ping         = xCAT::zvmUtils->pingNode($node);
        my $sleepseconds = 15;
        if ($ping eq "ping") {

            #$out = `ssh -o ConnectTimeout=10 $::SUDOER\@$node "shutdown -h now"`;
            my $cmd = "$::SUDO shutdown -h now";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
            sleep($sleepseconds);    # Wait 15 seconds before logging user off
        }

        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId"`;
        my $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
            return;
        }
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($out =~ m/Return Code: 200/i) {
            if ($out =~ m/Reason Code: 12/i) {
                xCAT::zvmUtils->printSyslog("$userId already logged off.");
                $out = "$userId already logged off.";
                $rc  = 0;
            } elsif ($out =~ m/Reason Code: 16/i) {
                xCAT::zvmUtils->printSyslog("$userId in process of logging off.");
                $out = "$userId in process of logging off.";
                $rc  = 0;
            }
        }
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $userId output: $out");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            return;
        }
        xCAT::zvmUtils->printLn($callback, "$node: $out");
    }

    # Get the status (on|off)
    elsif ($args->[0] eq 'stat') {
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/off/' | sed 's/HCPCQU361E.*/off/' | sed 's/$userId.*/on/'`;
        my $rc = $? >> 8;
        if ($rc != 0) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $out, rc is $rc");
        }
        xCAT::zvmUtils->printLn($callback, "$node: $out");
    }

    # Reset a virtual server
    elsif ($args->[0] eq 'reset') {

        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $userId");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Deactivate -T $userId"`;
        my $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
            return;
        }
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($out =~ m/Return Code: 200/i) {
            if ($out =~ m/Reason Code: 12/i) {
                xCAT::zvmUtils->printSyslog("$userId already logged off.");
                $out = "$userId already logged off.";
                $rc  = 0;
            } elsif ($out =~ m/Reason Code: 16/i) {
                xCAT::zvmUtils->printSyslog("$userId in process of logging off.");
                $out = "$userId in process of logging off.";
                $rc  = 0;
            }
        }
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $userId output: $out");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            return;
        }
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        # Wait for output
        while (`ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/Done/'` !~ "Done") {
            sleep(5);
        }

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $userId"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $userId");
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        if ($status =~ /CLONE_ONLY=1/) {

            # Indicate node is being powered up so that we will confirm the IP address on the nodestat.
            if ($status =~ /POWER_UP=/) {
                $status =~ s/POWER_UP=0/POWER_UP=1/g;
            } else {
                $status = "$status;POWER_UP=1";
            }
            xCAT::zvmUtils->setNodeProp('zvm', $node, 'status', $status);
        }
    }

    # Reboot a virtual server
    elsif ($args->[0] eq 'reboot') {
        my $timeout = 0;

        #$out = `ssh -o ConnectTimeout=10 $::SUDOER\@$node "shutdown -r now &>/dev/null"`;
        my $cmd = "$::SUDO shutdown -r now &>/dev/null";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);

        # Wait until node is down or 180 seconds
        while ($timeout < 180) {
            my $ping = xCAT::zvmUtils->pingNode($node);
            if ($ping eq "ping") {
                sleep(1);
                $timeout++;
            } else {
                last;
            }
        }
        if ($timeout >= 180) {
            xCAT::zvmUtils->printLn($callback, "$node: Shutting down $userId... Failed\n");
            return;
        }

        xCAT::zvmUtils->printLn($callback, "$node: Shutting down $userId... Done\n");

        # Wait until node is up or 180 seconds
        $timeout = 0;
        while ($timeout < 180) {
            my $ping = xCAT::zvmUtils->pingNode($node);
            if ($ping eq "noping") {
                sleep(1);
                $timeout++;
            } else {
                last;
            }
        }
        if ($timeout >= 180) {
            xCAT::zvmUtils->printLn($callback, "$node: Rebooting $userId... Failed\n");
            return;
        }

        if ($status =~ /CLONE_ONLY=1/) {

            # Indicate node is being powered up so that we will confirm the IP address on the nodestat.
            if ($status =~ /POWER_UP=/) {
                $status =~ s/POWER_UP=0/POWER_UP=1/g;
            } else {
                $status = "$status;POWER_UP=1";
            }
            xCAT::zvmUtils->setNodeProp('zvm', $node, 'status', $status);
        }

        xCAT::zvmUtils->printLn($callback, "$node: Rebooting $userId... Done\n");
    }

    # Pause a virtual server
    elsif ($args->[0] eq 'pause') {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Pause -T $userId -k PAUSE=YES"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Pause -T $userId -k PAUSE=YES");
        xCAT::zvmUtils->printLn($callback, "$node: $out");
    }

    # Unpause a virtual server
    elsif ($args->[0] eq 'unpause') {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Pause -T $userId -k PAUSE=NO"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Pause -T $userId -k PAUSE=NO");
        xCAT::zvmUtils->printLn($callback, "$node: $out");
    }

    #Check VM reachable status
    elsif ($args->[0] eq 'isreachable') {
        if ($status =~ /CLONE_ONLY=1/ and $status =~ /POWER_UP=1/) {

            # Special test and handling for 's390x' architecture nodes which are in the nodetype
            # and zvm table and are marked as being powered up.
            my %generalArgs;
            $generalArgs{'verbose'} = 0;
            my $nodes = [$node];
            xCAT::zvmUtils->handlePowerUp($callback, $nodes, \%generalArgs);
        }

        # Check vm's status
        xCAT::zvmUtils->printSyslog("check $node isreachable");
        my $cmd = "$::SUDO date";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd);
        if (xCAT::zvmUtils->checkOutput($out) == -1) {
            xCAT::zvmUtils->printLn($callback, "$node: unreachable");
            return;
        }

        # Create output string
        if ($out) {
            xCAT::zvmUtils->printLn($callback, "$node: reachable");
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: unreachable");
        }
    }

    else {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Option not supported");
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
    my ($callback, $node, $args) = @_;
    my $write2db = '';
    if ($args) {
        @ARGV = @$args;

        # Parse options
        GetOptions('w' => \$write2db);
    }

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Exit if node is not a HCP
    if (!($hcp =~ m/$node/i)) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) $node is not a hardware control point");
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
    my $tab = xCAT::Table->new('zvm', -create => 1, -autocommit => 0);
    my @entries = $tab->getAllAttribsWhere("hcp like '%" . $hcp . "%'", 'node', 'userid');

    my $out;
    my $node2;
    my $id;
    my $os;
    my $arch;
    my $groups;

    # Get node hierarchy from /proc/sysinfo
    my $hierarchy;
    my $host = xCAT::zvmCPUtils->getHost($::SUDOER, $hcp);
    my $sysinfo = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO cat /proc/sysinfo"`;

    # Get node CEC
    my $cec = `echo "$sysinfo" | grep -a "Sequence Code"`;
    my @args = split(':', $cec);

    # Remove leading spaces and zeros
    $args[1] =~ s/^\s*0*//;
    $cec = xCAT::zvmUtils->trimStr($args[1]);

    # Get node LPAR
    my $lpar = `echo "$sysinfo" | grep -a "LPAR Name"`;
    @args = split(':', $lpar);
    $lpar = xCAT::zvmUtils->trimStr($args[1]);

    # Save CEC, LPAR, and zVM to 'zvm' table
    my %propHash;
    if ($write2db) {

        # Save CEC to 'zvm' table
        %propHash = (
            'nodetype' => 'cec',
            'parent'   => ''
        );
        xCAT::zvmUtils->setNodeProps('zvm', $cec, \%propHash);

        # Save LPAR to 'zvm' table
        %propHash = (
            'nodetype' => 'lpar',
            'parent'   => $cec
        );
        xCAT::zvmUtils->setNodeProps('zvm', $lpar, \%propHash);

        # Save zVM to 'zvm' table
        %propHash = (
            'nodetype' => 'zvm',
            'parent'   => $lpar
        );
        xCAT::zvmUtils->setNodeProps('zvm', lc($host), \%propHash);
    }

    # Search for s managed by given zHCP
    # Get 'node' and 'userid' properties
    %propHash = ();
    foreach (@entries) {
        $node2 = $_->{'node'};

        # Get groups
        @propNames = ('groups');
        $propVals = xCAT::zvmUtils->getNodeProps('nodelist', $node2, @propNames);
        $groups = $propVals->{'groups'};

        # Load VMCP module
        xCAT::zvmCPUtils->loadVmcp($::SUDOER, $node2);

        # Get user ID
        @propNames = ('userid');
        $propVals  = xCAT::zvmUtils->getNodeProps('zvm', $node2, @propNames);
        $id        = $propVals->{'userid'};
        if (!$id) {
            $id = xCAT::zvmCPUtils->getUserId($::SUDOER, $node2);
        }

        # Get architecture
        #$arch = `ssh -o ConnectTimeout=2 $::SUDOER\@$node2 "uname -p"`;
        my $cmd = "$::SUDO uname -p";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node2, $cmd, $callback);
        if (xCAT::zvmUtils->checkOutput($out) == -1) {
            return;
        }

        $arch = xCAT::zvmUtils->trimStr($out);
        if (!$out) {

            # Assume arch is s390x
            $arch = 's390x';
        }

        # Get OS
        $os = xCAT::zvmUtils->getOsVersion($::SUDOER, $node2);

        # Save node attributes
        if ($write2db) {

            # Do not save if node = host
            if (!(lc($host) eq lc($node2))) {

                # Save to 'zvm' table
                %propHash = (
                    'hcp'      => $hcp,
                    'userid'   => $id,
                    'nodetype' => 'vm',
                    'parent'   => lc($host)
                );
                xCAT::zvmUtils->setNodeProps('zvm', $node2, \%propHash);

                # Save to 'nodetype' table
                %propHash = (
                    'arch' => $arch,
                    'os'   => $os
                );
                xCAT::zvmUtils->setNodeProps('nodetype', $node2, \%propHash);
            }
        }

        # Create output string
        $str .= "$node2:\n";
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

    xCAT::zvmUtils->printLn($callback, "$str");
    return;
}

#-------------------------------------------------------

=head3   inventoryVM

    Description : Get hardware and software inventory of a given node
    Arguments   :   Node
                    Type of inventory (all|config|console [logsize]|cpumem|cpumempowerstat|--freerepospace)
    Returns     : Nothing, errors returned in $callback
    Example     : inventoryVM($callback, $node, $args);

=cut

#-------------------------------------------------------
sub inventoryVM {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Output string
    my $str = "";

    my $outmsg;
    my $rc;

    # Check if node is pingable
    if (($args->[0] ne '--consoleoutput') and ($args->[0] ne 'cpumempowerstat')) {
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "noping") {
            $str = "$node: (Error) Host is unreachable";
            xCAT::zvmUtils->printLn($callback, "$str");
            return;
        }
    }

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Get zvm system node name. nodetype should be zvm.
    my $tab2 = xCAT::Table->new('zvm', -create => 1, -autocommit => 0);
    my @results2 = $tab2->getAllAttribsWhere("nodetype='zvm'", 'hcp', 'node');
    my $hypervisornode = "unknown";
    foreach (@results2) {
        if ($_->{'hcp'} eq $hcp) {
            $hypervisornode = $_->{'node'};
        }
    }

    # Load VMCP module
    xCAT::zvmCPUtils->loadVmcp($::SUDOER, $node);

    # Get configuration
    if ($args->[0] eq 'config') {

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
        my $maxMem = xCAT::zvmUtils->getMaxMemory($::SUDOER, $hcp, $node);

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
        $str .= "xCAT Hypervisor Node: $hypervisornode\n";   # new field for GUI

    } elsif ($args->[0] eq 'cpumem') {

        # Get memory configuration
        my $memory = xCAT::zvmCPUtils->getMemory($::SUDOER, $node);

        # Get processors configuration
        my $proc = xCAT::zvmCPUtils->getCpu($::SUDOER, $node);

        # Get instance CPU used time
        my $cputime = xCAT::zvmUtils->getUsedCpuTime($::SUDOER, $hcp, $node);
        if (xCAT::zvmUtils->checkOutput($cputime) == -1) {
            xCAT::zvmUtils->printLn($callback, "$cputime");
            return;
        }

        $str .= "Total Memory: $memory\n";
        $str .= "Processors: \n$proc\n";
        $str .= "CPU Used Time: $cputime\n";

    } elsif ($args->[0] eq 'cpumempowerstat') {

        # This option will check power stat then based on the power stat, use
        # SMAPI to query the cpu, mem and uptime. so all info is done in one
        # SMAPI call will help the performance enhancement.
        my $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q user $userId 2>/dev/null"`;
        xCAT::zvmUtils->printSyslog("$node: power stat query return: $out");
        if ($out =~ 'HCPCQU045E' or $out =~ 'HCPCQU361E') {
            $out = 'off';
        } elsif ($out =~ $userId) {
            $out = 'on';
        } else {

            # should not be here
            xCAT::zvmUtils->printLn($callback, "$node: (Error) power stat query return not parsable, the result is $out");
            return
        }

        if ($out eq 'off') {

            # upper layer should check power off state first
            $str .= "Power state: off\n";
            $str .= "Total Memory: 0M\n";
            $str .= "Processors: 0\n";
            $str .= "CPU Used Time: 0 sec\n";
        } else {

            # This is 'on' branch, we should be able to query info
            xCAT::zvmUtils->printSyslog("$node: calling smcli Image_Performance_Query -T $userId -c 1");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Performance_Query -T $userId -c 1"`;
            my $rc = $? >> 8;

            if ($rc == 255) {
                xCAT::zvmUtils->printSyslog("$node: (Error) unable to communicate with the zhcp system: $hcp");
                xCAT::zvmUtils->printLn($callback, "$node: (Error) unable to communicate with the zhcp system: $hcp");
                return;
            }
            if ($rc) {
                xCAT::zvmUtils->printSyslog("$node: (Error) calling smcli Image_Performance_Query -T $userId");
                xCAT::zvmUtils->printLn($callback, "$node: (Error) calling smcli Image_Performance_Query -T $userId");
                return;
            }

            # In order to save SMAPI call effort, we didn't set them into separated function
            # just get SMAPI output and parse the output
            my $time = `echo -e "$out" | egrep -a -i "Used CPU time:"`;
            $time =~ s/^Used CPU time:(.*)/$1/;
            my @timearray = split(' ', $time);

            # Get value is us , need make it seconds
            my $usedtime = $timearray[0] / 1000000;

            my $cpus = `echo -e "$out" | egrep -a -i "Guest CPUs:"`;
            $cpus =~ s/^Guest CPUs:(.*)/$1/;
            my @cpuarray = split(' ', $cpus);
            my $totalcpu = $cpuarray[0];

            # This is the used memory, not max mem defined in user dirct, it's in KB
            my $mem = `echo -e "$out" | egrep -a -i "Max memory:"`;
            $mem =~ s/^Max memory:(.*)/$1/;
            my @memarry = split(' ', $mem);
            my $totalmem = $memarry[0] / 1024;

            $str .= "Power state: on\n";
            $str .= "Total Memory: $totalmem" . "M\n";
            $str .= "Processors: $totalcpu\n";
            $str .= "CPU Used Time: $usedtime" . " sec\n";
        }
    } elsif ($args->[0] eq 'all') {

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
        my $maxMem = xCAT::zvmUtils->getMaxMemory($::SUDOER, $hcp, $node);

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
        my $cputime = xCAT::zvmUtils->getUsedCpuTime($::SUDOER, $hcp, $node);
        if (xCAT::zvmUtils->checkOutput($cputime) == -1) {
            xCAT::zvmUtils->printLn($callback, "$cputime");
            return;
        }

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
        $str .= "xCAT Hypervisor Node: $hypervisornode\n";   # new field for GUI

    } elsif ($args->[0] eq '--freerepospace') {

        # Get /install available disk size
        my $freespace = xCAT::zvmUtils->getFreeRepoSpace($::SUDOER, $node);

        # Create output string
        if ($freespace) {
            $str .= "Free Image Repository: $freespace\n";
        } else {
            return;
        }

        # Get console output
    } elsif ($args->[0] eq '--consoleoutput') {

        my $argsSize = @{$args};

        # Let SMAPI execution on ZHCP to punch the console log to the caller
        my $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Console_Get -T $userId"`;
        xCAT::zvmUtils->printSyslog("$::SUDOER\@$hcp $::SUDO $::DIR/smcli Image_Console_Get -T $userId");

        my $out;
        chomp($out = `ssh $::SUDOER\@$hcp "$::SUDO cat /sys/bus/ccw/drivers/vmur/0.0.000c/online"`);
        if ($out != 1) {
            chomp($out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/cio_ignore -r 000c; /sbin/chccwdev -e 000c"`);
            if (!($out =~ m/Done$/i)) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to online the zHCP's reader, cmd output: $out.");
                xCAT::zvmUtils->printSyslog("inventoryVM() Failed to online the zHCP's reader, cmd output: $out.");
                return;
            }
            $out = `ssh $::SUDOER\@$hcp "$::SUDO which udevadm &> /dev/null && udevadm settle || udevsettle"`;
        }

        # we need set class otherwise we will get error like:
        # vmur: Reader device class does not match spool file class.
        $out = `ssh $::SUDOER\@$hcp "$::SUDO vmcp spool c class \\*"`;
        xCAT::zvmUtils->printSyslog("vmcp spool c class return: $out");

        # Get console output from zhcp
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/sbin/vmur list"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO /usr/sbin/vmur list\"", $hcp, "inventoryVM", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $out = `echo "$out" | egrep -a -i "$userId "`;
        my @spoolFiles = sort(split('\n', $out));
        $str = "";
        foreach (@spoolFiles) {
            if (!(length $_)) { next; }
            my @fileProperty = split(' ', $_);
            my $spoolFileId = $fileProperty[1];
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/sbin/vmur re -t -O $spoolFileId"`;
            $str .= $out
        }

        # Prepare to output
        my $str_length = length($str);
        if (!$str_length) {
            $str = "(Error) No console log avaiable";

            # Append hostname (e.g. gpok3) in front
            $str = xCAT::zvmUtils->appendHostname($node, $str);

            xCAT::zvmUtils->printLn($callback, "$str");
            return;
        } elsif ($argsSize eq 2) {
            my $logsize = $args->[1];

            # only output last $logsize bytes of console log
            if (($logsize > 0) and ($logsize < $str_length)) {
                $str = substr($str, -$logsize);
                my $truncatd = $str_length - $logsize;
                $str = "Truncated console log, $truncatd bytes ignored\n" . $str
            }
        }

        # Append hostname (e.g. gpok3) in front
        $str = xCAT::zvmUtils->appendHostname($node, $str);
        xCAT::zvmUtils->printInfo($callback, "$str");
        return;

    } else {
        $str = "$node: (Error) Option not supported";
        xCAT::zvmUtils->printLn($callback, "$str");
        return;
    }

    # Append hostname (e.g. gpok3) in front
    $str = xCAT::zvmUtils->appendHostname($node, $str);

    xCAT::zvmUtils->printLn($callback, "$str");
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
    my ($callback, $node, $args) = @_;

    # Set cache directory
    my $cache = '/var/opt/zhcp/cache';

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid', 'status');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    my $out;
    my $rc;

    # Get disk pool configuration
    if ($args->[0] eq "--diskpool") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Get disk pool names
    elsif ($args->[0] eq "--diskpoolnames") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Get network names
    elsif ($args->[0] eq "--getnetworknames") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Get network
    elsif ($args->[0] eq "--getnetwork") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Get the status of all DASDs accessible to a virtual image
    elsif ($args->[0] eq "--querydisk") {
        my $vdasd = $args->[1];

        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Query -T $userId -k $vdasd"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Disk_Query -T $userId -k $vdasd");
    }

    # Get the status of all DASDs accessible to a the system
    elsif ($args->[0] eq "--queryalldisks") {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Query -T MAINT -k dev_num=ALL -k disk_size=YES"`;
        xCAT::zvmUtils->printSyslog(" ssh zhcp smcli System_Disk_Query -T MAINT -k dev_num=ALL -k disk_size=YES");
    }

    # Get list of PAGE volumes
    elsif ($args->[0] eq "--querypagevolumes") {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Page_Utilization_Query -T MAINT "`;
        xCAT::zvmUtils->printSyslog(" ssh zhcp smcli System_Page_Utilization_Query -T MAINT");
    }

    # Get list of SPOOL volumes
    elsif ($args->[0] eq "--queryspoolvolumes") {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Spool_Utilization_Query -T MAINT "`;
        xCAT::zvmUtils->printSyslog(" ssh zhcp smcli System_Spool_Utilization_Query -T MAINT");
    }

    # Get user profile names
    elsif ($args->[0] eq "--userprofilenames") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Get zFCP disk pool configuration
    elsif ($args->[0] eq "--zfcppool") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Get zFCP disk pool names
    elsif ($args->[0] eq "--zfcppoolnames") {

        # This is no longer supported in lsvm. Using inventoryHypervisor instead.
        inventoryHypervisor($callback, $node, $args);
    }

    # Check whether instance has given NIC
    elsif ($args->[0] eq "--checknics") {
        if ($propVals->{'status'} =~ /CLONE_ONLY=1/) {
            xCAT::zvmUtils->printSyslog("$node: cloned flag detected, no further check");
        } else {

            # Get the directory data without the *DVHOPT line
            xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $userId | sed '\$d'");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId"`;
            $rc = $? >> 8;

            if ($rc == 255) {
                xCAT::zvmUtils->printSyslog("$node: (Error) unable to communicate with the zhcp system: $hcp");
                xCAT::zvmUtils->printLn($callback, "$node: (Error) unable to communicate with the zhcp system: $hcp");
                return;
            }
            if ($rc) {
                xCAT::zvmUtils->printSyslog("$node: (Error) calling smcli Image_Query_DM -T $userId");
                xCAT::zvmUtils->printLn($callback, "$node: (Error) calling smcli Image_Query_DM -T $userId");
                return;
            }
            $out =~ s/\*DVHOPT(.*)//s; # remove last line with *DVHOPT and newline after it

            my $argsSize = @{$args};
            if ($argsSize != 2) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Nodename and only one NIC address must be input");
                return;
            }

            # For each NIC given, check whether it exists in the user direct of user
            # In case this is a cloned instance, will not check whether it exist or not
            # directly return True.
            my $i;
            my $dev;

            $dev = $args->[1];
            if ($dev =~ m/^[0-9a-fA-F]{1,4}/) {

                # add '0' to $dev, e.g 0100 or 100 are both valid, the length check already done above
                if ($out =~ m/.*NICDEF [0]*$dev TYPE QDIO LAN SYSTEM .*/i) {
                    xCAT::zvmUtils->printSyslog("$node: succeed in find $dev in user direct");
                } else {

                    # Not return $out to upper layer as it might contain password
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) not able to find $dev in user direct");

                    xCAT::zvmUtils->printSyslog("$node: (Error) not able to find $dev in user direct: $out");
                    return;
                }
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) input NIC param $dev invalid");
                return;
            }
        }

        # ok, NIC we planned to check are found or this is a cloned node.
        $out = '';
    }

    # Get user entry
    elsif (!$args->[0]) {

        # Get the directory data without the *DVHOPT line
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $userId | sed '\$d'");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId"`;
        $rc = $? >> 8;

        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("$node: (Error) unable to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) unable to communicate with the zhcp system: $hcp");
            return;
        }
        if ($rc) {
            xCAT::zvmUtils->printSyslog("$node: (Error) calling smcli Image_Query_DM -T $userId");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) calling smcli Image_Query_DM -T $userId");
            return;
        }
        $out =~ s/\*DVHOPT(.*)//s; # remove last line with *DVHOPT and newline after it
    } else {
        $out = "$node: (Error) Option not supported";
    }

    # Append hostname (e.g. gpok3) in front
    $out = xCAT::zvmUtils->appendHostname($node, $out);
    xCAT::zvmUtils->printLn($callback, "$out");

    return;
}

#-------------------------------------------------------

=head3   makeVM

    Description : Create a virtual machine
                   * A unique MAC address will be assigned
    Arguments   :  Node
                   Directory entry text file (optional)
                   Upstream instance ID (optional)
                   Upstream request ID (optional)
    Returns     : Nothing
    Example     : makeVM($callback, $node, $args);

=cut

#-------------------------------------------------------
sub makeVM {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("makeVM for node:$node on zhcp:$hcp");

    # Find the number of arguments
    my $argsSize = @{$args};

    # Create a new user in zVM without user directory entry file
    my $out;
    my $outmsg;
    my $rc;
    my $stdin;
    my $password    = "";
    my $memorySize  = "";
    my $privilege   = "";
    my $profileName = "";
    my $cpuCount    = 1;
    my $diskPool    = "";
    my $diskSize    = "";
    my $diskVdev    = "";
    my $ipl         = "";
    my $logonby     = "";
    my $requestId = "NoUpstreamRequestID"; # Default is still visible in the log
    my $objectId  = "NoUpstreamObjectID";  # Default is still visible in the log

    if ($args) {
        @ARGV = @$args;

        # Parse options
        GetOptions(
            's|stdin'      => \$stdin,      # Directory entry contained in stdin
            'p|profile=s'  => \$profileName,
            'w|password=s' => \$password,
            'c|cpus=i'     => \$cpuCount,   # Optional
            'm|mem=s'      => \$memorySize,
            'd|diskpool=s' => \$diskPool,
            'z|size=s'     => \$diskSize,
            'v|diskvdev=s' => \$diskVdev,   # Optional
            'r|privilege=s' => \$privilege, # Optional
            'q|requestid=s' => \$requestId, # Optional
            'j|objectid=s'  => \$objectId,  # Optional
            'i|ipl=s'       => \$ipl,       # Optional
            'l|logonby=s'   => \$logonby);  # Optional
    }

    # If one of the options above are given, create the user without a directory entry file
    if ($profileName || $password || $memorySize) {
        if (!$profileName || !$password || !$memorySize) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing one or more required parameter(s)");
            return;
        }

        # Default privilege to G if none is given
        if (!$privilege) {
            $privilege = 'G';

        }

        # validate the logonby userid
        my @userids = split(' ', $logonby);
        if (scalar(@userids) > 8) {
            xCAT::zvmUtils->printSyslog("logonby statement contains more than 8 users which is not allowed, the value is: $logonby");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) logonby statement contains more than 8 users which is not allowed, the value is: $logonby");
            return;
        }
        for (my $i = 0 ; $i < scalar(@userids) ; $i++) {
            if (length($userids[$i]) > 8) {
                xCAT::zvmUtils->printSyslog("logonby userid $userids[$i] contains more than 8 chars");
                xCAT::zvmUtils->printLn($callback, "$node: logonby userid $userids[$i] contains more than 8 chars");
                return;
            }
        }

        # Generate temporary user directory entry file
        my $userEntryFile = xCAT::zvmUtils->generateUserEntryFile($userId, $password, $memorySize, $privilege, $profileName, $cpuCount, $ipl, $logonby);
        if ($userEntryFile == -1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to generate user directory entry file");
            return;
        }

        # Create a new user in z/VM without disks
        $out = `/opt/xcat/bin/mkvm $node $userEntryFile 2>&1`;
        xCAT::zvmUtils->printLn($callback, "$out");
        if (xCAT::zvmUtils->checkOutput($out) == -1) {

            # The error would have already been printed under mkvm
            `rm -rf $userEntryFile`;
            return;
        }

        # If one of the disk operations are given, add disk(s) to this new user
        if ($diskPool || $diskSize) {
            if (!$diskPool || !$diskSize) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing one or more required parameter(s) for adding disk");
                `rm -rf $userEntryFile`;
                return;
            }

            # Default disk virtual device to 0100 if none is given
            if (!$diskVdev) {
                $diskVdev = "0100";
            }

            $out = `/opt/xcat/bin/chvm $node --add3390 $diskPool $diskVdev $diskSize 2>&1`;
            xCAT::zvmUtils->printLn($callback, "$out");
            if (xCAT::zvmUtils->checkOutput($out) == -1) {

                # The error would have already been printed under chvm
                `rm -rf $userEntryFile`;
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
    $propVals = xCAT::zvmUtils->getNodeProps('mac', $node, @propNames);

    # If MAC address exists
    my @lines;
    my @words;
    if ($propVals->{'mac'}) {

        # Get MAC suffix (MACID)
        $macId = $propVals->{'mac'};
        $macId = xCAT::zvmUtils->replaceStr($macId, ":", "");
        $macId = substr($macId, 6);
    } else {
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;

        # Get USER Prefix
        my $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q vmlan"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh -o ConnectTimeout=5 $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp q vmlan\"", $hcp, "makeVM", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        my $prefix = `echo "$out" | egrep -a -i "USER Prefix:"`;
        $prefix =~ s/(.*?)USER Prefix:(.*)/$2/;
        $prefix =~ s/^\s+//;
        $prefix =~ s/\s+$//;

        # Get MACADDR Prefix instead if USER Prefix is not defined
        if (!$prefix) {
            $prefix = `echo "$out" | egrep -a -i "MACADDR Prefix:"`;
            $prefix =~ s/(.*?)MACADDR Prefix:(.*)/$2/;
            $prefix =~ s/^\s+//;
            $prefix =~ s/\s+$//;

            if (!$prefix) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not find the MACADDR/USER prefix of the z/VM system");
                xCAT::zvmUtils->printLn($callback, "$node: (Solution) Verify that the node's zHCP($hcp) is correct, the node is online, and the SSH keys are setup for the zHCP");
                return;
            }
        }

        # Generate MAC address
        my $mac;
        while ($generateNew) {

            # If no MACID is found, get one
            $macId = xCAT::zvmUtils->getMacID($::SUDOER, $hcp);
            if (!$macId) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not generate MACID");
                return;
            }

            # Create MAC address
            $mac = $prefix . $macId;

            # If length is less than 12, append a zero
            if (length($mac) != 12) {
                $mac = "0" . $mac;
            }

            # Format MAC address
            $mac =
              substr($mac, 0, 2) . ":"
              . substr($mac, 2,  2) . ":"
              . substr($mac, 4,  2) . ":"
              . substr($mac, 6,  2) . ":"
              . substr($mac, 8,  2) . ":"
              . substr($mac, 10, 2);

            # Check 'mac' table for MAC address
            my $tab = xCAT::Table->new('mac', -create => 1, -autocommit => 0);
            my @entries = $tab->getAllAttribsWhere("mac = '" . $mac . "'", 'node');

            # If MAC address exists
            if (@entries) {

                # Generate new MACID
                $out = xCAT::zvmUtils->generateMacId($::SUDOER, $hcp);
                $generateNew = 1;
            } else {
                $generateNew = 0;

                # Save MAC address in 'mac' table
                xCAT::zvmUtils->setNodeProp('mac', $node, 'mac', $mac);

                # Generate new MACID
                $out = xCAT::zvmUtils->generateMacId($::SUDOER, $hcp);
            }
        }    # End of while ($generateNew)
    }

    # Create virtual server
    my $line;
    my @hcpNets;
    my $netName = '';
    my $oldNicDef;
    my $nicDef;
    my $id;
    my @vswId;
    my $target = "$::SUDOER\@$hcp";

    if ($userEntry) {

        # Copy user entry
        $out       = `cp $userEntry /tmp/$node.txt`;
        $userEntry = "/tmp/$node.txt";

        # If the directory entry contains a NICDEF statement, append MACID to the end
        # User must select the right one (layer) based on template chosen
        $out = `cat $userEntry | egrep -a -i "NICDEF"`;
        if ($out) {

            # Get the networks used by the zHCP
            @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $hcp);

            # Search user entry for network name
            foreach (@hcpNets) {
                if ($out =~ m/ $_/i) {
                    $netName = $_;
                    last;
                }
            }

            # Find NICDEF statement
            $oldNicDef = `cat $userEntry | egrep -a -i "NICDEF" | egrep -a -i "$netName"`;
            if ($oldNicDef) {
                $oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
                $nicDef = xCAT::zvmUtils->replaceStr($oldNicDef, $netName, "$netName MACID $macId");

                # Append MACID at the end
                $out = `sed -i -e "s,$oldNicDef,$nicDef,i" $userEntry`;
            }
        }

        # Open user entry
        $out = `cat $userEntry`;
        @lines = split('\n', $out);

        # Get the userID in user entry
        $line  = xCAT::zvmUtils->trimStr($lines[0]);
        @words = split(' ', $line);
        $id    = $words[1];

        # Change userID in user entry to match userID defined in xCAT
        $out = `sed -i -e "s,$id,$userId,i" $userEntry`;

        # SCP file over to zHCP
        $out = `scp $userEntry $target:$userEntry`;

        # Create virtual server
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Create_DM -T $userId -f $userEntry"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Create_DM -T $userId -f $userEntry");
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        # Check output
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($rc == 0) {

            # Get VSwitch of zHCP (if any)
            @vswId = xCAT::zvmCPUtils->getVswitchId($::SUDOER, $hcp);

            # Is there an internal vswitch for xcat and zhcp? If so do not grant to that.
            my $internalVswitch = '-';
            if (open my $input_fh, "</opt/xcat/internalVswitch") {
                $internalVswitch = <$input_fh>; # read first line, should be just one token
                close $input_fh;
                chomp($internalVswitch);
            }

            # Grant access to VSwitch for Linux user
            # GuestLan do not need permissions
            # skip any duplicates
            my %vswitchhash;
            foreach (@vswId) {
                if (!(length $_)) { next; }

                # skip grant if we already did one for this vswitch
                if (exists $vswitchhash{$_}) {
                    xCAT::zvmUtils->printSyslog("makeVM. Skipping duplicate vswitch grant from: $_");
                }
                else {
                    if ($_ ne $internalVswitch) {
                        xCAT::zvmUtils->printSyslog("makeVM. Found vswitch to grant: $_");
                        $out = xCAT::zvmCPUtils->grantVSwitch($callback, $::SUDOER, $hcp, $userId, $_, '', ''); # Don't have porttype or vlan
                        xCAT::zvmUtils->printLn($callback, "$node: Granting VSwitch ($_) access for $userId... $out");
                        $vswitchhash{$_} = '1';
                    } else {
                        xCAT::zvmUtils->printSyslog("makeVM. Skipping grant for internal vswitch: $_");
                    }
                }
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
        $out = `echo -e "$stdin" | egrep -a -i "NICDEF"`;
        if ($out) {

            # Get the networks used by the zHCP
            @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $hcp);

            # Search user entry for network name
            $netName = '';
            foreach (@hcpNets) {
                if ($out =~ m/ $_/i) {
                    $netName = $_;
                    last;
                }
            }

            # Find NICDEF statement
            $oldNicDef = `echo -e "$stdin" | egrep -a -i "NICDEF" | egrep -a -i "$netName"`;
            if ($oldNicDef) {
                $oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);

                # Append MACID at the end
                $nicDef = xCAT::zvmUtils->replaceStr($oldNicDef, $netName, "$netName MACID $macId");

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
            if (!(length $_)) { next; }
            if ($_) {
                $_ = "'" . $_ . "'";
                `ssh $::SUDOER\@$hcp "echo $_ >> $file"`;
            }
        }

        # Create virtual server
        $out = `ssh $::SUDOER\@$hcp "cat $file | $::SUDO $::DIR/smcli Image_Create_DM -T $userId -s"`;
        xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp cat $file | $::SUDO $::DIR/smcli Image_Create_DM -T $userId -s");
        xCAT::zvmUtils->printLn($callback, "$node: $out");

        # Check output
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($rc == 0) {

            # Get VSwitch of zHCP (if any)
            @vswId = xCAT::zvmCPUtils->getVswitchId($::SUDOER, $hcp);

            # Grant access to VSwitch for Linux user
            # GuestLan do not need permissions
            foreach (@vswId) {
                $out = xCAT::zvmCPUtils->grantVSwitch($callback, $::SUDOER, $hcp, $userId, $_, '', '');
                xCAT::zvmUtils->printLn($callback, "$node: Granting VSwitch ($_) access for $userId... $out");
            }

            # Delete created file on zHCP
            `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "rm -rf $file"`;
        }
    } else {

        # Create NOLOG virtual server
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/createvs $userId"`;
        xCAT::zvmUtils->printLn($callback, "$node: $out");
    }

    return;
}

#-------------------------------------------------------

=head3   cloneVM

    Description : Clone a virtual server
    Arguments   :   Node
                    Disk pool
                    Disk password
                    clone info hash, can be empty
    Returns     : Nothing
    Example     : cloneVM($callback, $targetNode, $args);

=cut

#-------------------------------------------------------
sub cloneVM {

    # Get inputs
    my ($callback, $nodes, $args) = @_;

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
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $sourceNode, @propNames);

    # Get zHCP
    my $srcHcp = $propVals->{'hcp'};

    # Get node user ID
    my $sourceId = $propVals->{'userid'};

    # Capitalize user ID
    $sourceId =~ tr/a-z/A-Z/;

    # Get operating system, e.g. sles11sp2 or rhel6.2
    @propNames = ('os');
    $propVals = xCAT::zvmUtils->getNodeProps('nodetype', $sourceNode, @propNames);
    my $srcOs = $propVals->{'os'};

    # Set IP address
    my $sourceIp = xCAT::zvmUtils->getIp($sourceNode);

    my @dedicates = xCAT::zvmUtils->getDedicates($callback, $::SUDOER, $sourceNode);
    if (xCAT::zvmUtils->checkOutput($dedicates[0]) == -1) {
        xCAT::zvmUtils->printLn($callback, "$dedicates[0]");
        return;
    }
    if (scalar(@dedicates)) {
        xCAT::zvmUtils->printLn($callback, "$sourceNode: (Error) Dedicate statements found in source directory.");
        return;
    }

    # Get networks in 'networks' table
    my $netEntries = xCAT::zvmUtils->getAllTabEntries('networks');
    my $srcNetwork = "";
    my $srcMask;
    foreach (@$netEntries) {

        # Get source network and mask
        $srcNetwork = $_->{'net'};
        $srcMask    = $_->{'mask'};

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
    xCAT::zvmUtils->printSyslog("nodes:@nodes");

    foreach (@nodes) {
        xCAT::zvmUtils->printLn($callback, "$_: Cloning $sourceNode");

        # Exit if missing source node
        if (!$sourceNode) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing source node");
            return;
        }

        # Exit if missing source HCP
        if (!$srcHcp) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing source node HCP");
            return;
        }

        # Exit if missing source user ID
        if (!$sourceId) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing source user ID");
            return;
        }

        # Exit if missing source operating system
        if (!$srcOs) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing source operating system");
            return;
        }

        # Exit if missing source operating system
        if (!$sourceIp || !$srcNetwork || !$srcMask) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing source IP, network, or mask");
            return;
        }

        # Get target node
        @propNames = ('hcp', 'userid');
        $propVals = xCAT::zvmUtils->getNodeProps('zvm', $_, @propNames);

        # Get target HCP
        my $tgtHcp = $propVals->{'hcp'};

        # Get node userID
        my $tgtId = $propVals->{'userid'};

        # Capitalize userID
        $tgtId =~ tr/a-z/A-Z/;

        # Exit if missing target zHCP
        if (!$tgtHcp) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing target node HCP");
            return;
        }

        # Exit if missing target user ID
        if (!$tgtId) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Missing target user ID");
            return;
        }

        # Exit if source and target zHCP are not equal
        if ($srcHcp ne $tgtHcp) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) Source and target HCP are not equal");
            xCAT::zvmUtils->printLn($callback, "$_: (Solution) Set the source and target HCP appropriately in the zvm table");
            return;
        }

        #*** Get MAC address ***
        my $targetMac;
        my $macId;
        my $generateNew = 0;    # Flag to generate new MACID
        @propNames = ('mac');
        $propVals = xCAT::zvmUtils->getNodeProps('mac', $_, @propNames);
        if (!$propVals->{'mac'}) {

            # If no MACID is found, get one
            $macId = xCAT::zvmUtils->getMacID($::SUDOER, $tgtHcp);
            if (!$macId) {
                xCAT::zvmUtils->printLn($callback, "$_: (Error) Could not generate MACID");
                return;
            }

            # Create MAC address (target)
            $targetMac = xCAT::zvmUtils->createMacAddr($::SUDOER, $_, $macId);
            if (xCAT::zvmUtils->checkOutput($targetMac) == -1) {
                xCAT::zvmUtils->printLn($callback, "$targetMac");
                return;
            }

            # Save MAC address in 'mac' table
            xCAT::zvmUtils->setNodeProp('mac', $_, 'mac', $targetMac);

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
    my @srcDisks = xCAT::zvmUtils->getMdisks($callback, $::SUDOER, $sourceNode);
    if (xCAT::zvmUtils->checkOutput($srcDisks[0]) == -1) {
        xCAT::zvmUtils->printLn($callback, "$srcDisks[0]");
        return;
    }

    # Get details about source disks
    # Output is similar to:
    #   MDISK=VDEV=0100 DEVTYPE=3390 START=0001 COUNT=10016 VOLID=EMC2C4 MODE=MR
    $out = `ssh $::SUDOER\@$srcHcp "$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $sourceId -k MDISK"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Definition_Query_DM -T $sourceId -k MDISK");
    xCAT::zvmUtils->printSyslog("$out");
    xCAT::zvmUtils->printSyslog("srcDisks:@srcDisks");
    my $srcDiskDet = xCAT::zvmUtils->trimStr($out);
    foreach (@srcDisks) {

        # Get disk address
        @words = split(' ', $_);
        $addr  = $words[1];
        $type  = $words[2];

        # Add 0 in front if address length is less than 4
        while (length($addr) < 4) {
            $addr = '0' . $addr;
        }

        # Get disk type
        $srcDiskType{$addr} = $type;

        # Get disk size (cylinders or blocks)
        # ECKD or FBA disk
        if ($type eq '3390' || $type eq '9336') {
            my @lines = split('\n', $srcDiskDet);

            # Loop through each line
            for ($i = 0 ; $i < @lines ; $i++) {

                # remove the MDISK= from the line
                $lines[$i] =~ s/MDISK=//g;

                # Extract vdev address
                # search for = signs, capture what is after = but not whitespace
                @words = ($lines[$i] =~ m/=(\S+)/g);
                my $srcDiskAddr = $words[0];
                if ($srcDiskAddr eq $addr) {
                    $srcDiskSize{$srcDiskAddr} = $words[3];
                    xCAT::zvmUtils->printSyslog("addr:$addr type:$type srcDiskAddr:$srcDiskAddr srcDiskSize:$words[3]");
                }
            }
        }

        # If source disk is not linked
        my $try = 5;
        while ($try > 0) {

            # New disk address
            $linkAddr = $addr + 1000;

            # Check if new disk address is used (source)
            $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $srcHcp, $linkAddr);

            # If disk address is used (source)
            while ($rc == 0) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $linkAddr = $linkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $srcHcp, $linkAddr);
            }

            $srcLinkAddr{$addr} = $linkAddr;

            # Link source disk to HCP
            foreach (@nodes) {
                xCAT::zvmUtils->printLn($callback, "$_: Linking source disk ($addr) as ($linkAddr)");
            }
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$srcHcp "$::SUDO /sbin/vmcp link $sourceId $addr $linkAddr RR"`;

            if ($out =~ m/not linked/i) {

                # Do nothing
            } else {
                last;
            }

            $try = $try - 1;

            # Wait before next try
            sleep(5);
        }    # End of while ( $try > 0 )

        # If source disk is not linked
        if ($out =~ m/not linked/i) {
            foreach (@nodes) {
                xCAT::zvmUtils->printLn($callback, "$_: Failed");
            }

            # Exit
            return;
        }

        # Enable source disk
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $srcHcp, "-e", $linkAddr);
    }    # End of foreach (@srcDisks)

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

    my @lines = split('\n', $out);

    # Loop through each line
    my $line;
    for ($i = 0 ; $i < @lines ; $i++) {

        # Loop through each network name
        foreach (@hcpNets) {

            # If the network is found
            if ($lines[$i] =~ m/SWITCHNAME=$_/i) {

                # Save network name
                $hcpNetName = $_;

                $lines[$i] =~ s/NICDEF_PROFILE=//g;
                $lines[$i] =~ s/NICDEF=//g;

                # Extract NIC address
                @words      = ($lines[$i] =~ m/=(\S+)/g);
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
        for $addr (keys %srcLinkAddr) {
            $linkAddr = $srcLinkAddr{$addr};

            # Disable and detatch source disk
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $srcHcp, "-d", $linkAddr);
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$srcHcp "$::SUDO /sbin/vmcp det $linkAddr"`;
            foreach (@nodes) {
                xCAT::zvmUtils->printLn($callback, "$_: Detatching source disk ($addr) at ($linkAddr)");
            }
        }

        foreach (@nodes) {
            xCAT::zvmUtils->printLn($callback, "$_: (Error) No suitable network device found in user directory entry");
            xCAT::zvmUtils->printLn($callback, "$_: (Solution) Verify that the node has one of the following network devices: @hcpNets");
        }

        return;
    }

    # Get vSwitch of source node (if any)
    my @srcVswitch = xCAT::zvmCPUtils->getVswitchId($::SUDOER, $srcHcp);

    # Get source MAC address in 'mac' table
    my $srcMac;
    @propNames = ('mac');
    $propVals = xCAT::zvmUtils->getNodeProps('mac', $sourceNode, @propNames);
    if ($propVals->{'mac'}) {

        # Get MAC address
        $srcMac = $propVals->{'mac'};
    }

    # Get user entry of source node without any mdisk statements
    my $srcUserEntry = "/tmp/$sourceNode.txt";
    $out = `rm $srcUserEntry`;
    $out = xCAT::zvmUtils->getUserEntryWODisk($callback, $::SUDOER, $sourceNode, $srcUserEntry);
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        xCAT::zvmUtils->printLn($callback, "$out");
        return;
    }

    # Check if user entry is valid
    $out = `cat $srcUserEntry`;

    # If output contains USER LINUX123, then user entry is good
    if ($out =~ m/USER $sourceId/i) {

        # Turn off source node
        my $ping = xCAT::zvmUtils->pingNode($sourceNode);
        if ($ping eq "ping") {
            $out = `ssh -o ConnectTimeout=10 $sourceNode "shutdown -h now"`;
            sleep(90);    # Wait 1.5 minutes before logging user off

            foreach (@nodes) {
                xCAT::zvmUtils->printLn($callback, "$_: Shutting down $sourceNode");
            }
        }

        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate -T $sourceId");
        $out = `ssh $::SUDOER\@$srcHcp "$::SUDO $::DIR/smcli Image_Deactivate -T $sourceId"`;
        $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $srcHcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $srcHcp");
            return;
        }
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($out =~ m/Return Code: 200/i) {
            if ($out =~ m/Reason Code: 12/i) {
                $out = "$sourceId already logged off.";
                $rc  = 0;
            } elsif ($out =~ m/Reason Code: 16/i) {
                $out = "$sourceId in process of logging off.";
                $rc  = 0;
            }
        }
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $sourceId output: $out");
            xCAT::zvmUtils->printLn($callback, "$out");
            return;
        }
        xCAT::zvmUtils->printSyslog("$out");

        #*** Clone source node ***
        # Remove flashcopy lock (if any)
        $out = `ssh $::SUDOER\@$srcHcp "$::SUDO rm -f /tmp/.flashcopy_lock"`;
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0) {
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
            if (!(@children % 4)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach

        # Handle the remaining nodes
        # Wait for all processes to end
        foreach (@children) {
            waitpid($_, 0);
        }

        # Remove source user entry
        $out = `rm $srcUserEntry`;
    }    # End of if

    #*** Detatch source disks ***
    for $addr (keys %srcLinkAddr) {
        $linkAddr = $srcLinkAddr{$addr};

        # Disable and detatch source disk
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $srcHcp, "-d", $linkAddr);
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$srcHcp "$::SUDO /sbin/vmcp det $linkAddr"`;

        foreach (@nodes) {
            xCAT::zvmUtils->printLn($callback, "$_: Detatching source disk ($addr) at ($linkAddr)");
        }
    }

    #*** Done ***
    foreach (@nodes) {
        xCAT::zvmUtils->printLn($callback, "$_: Done");
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
    Returns     : Nothing, errors returned in $callback
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
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $sourceNode, @propNames);

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
    @propNames = ('hcp', 'userid');
    $propVals = xCAT::zvmUtils->getNodeProps('zvm', $tgtNode, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing node HCP");
        return;
    }

    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    if (!$hcpUserId) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing zHCP user ID");
        return;
    }

    # Capitalize user ID
    $hcpUserId =~ tr/a-z/A-Z/;

    # Get node user ID
    my $tgtUserId = $propVals->{'userid'};
    if (!$tgtUserId) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $tgtUserId =~ tr/a-z/A-Z/;

    # Exit if source node HCP is not the same as target node HCP
    if (!($srcHcp eq $hcp)) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Source node HCP ($srcHcp) is not the same as target node HCP ($hcp)");
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Set the source and target HCP appropriately in the zvm table");
        return;
    }

    # Get target IP from /etc/hosts
    `makehosts`;
    sleep(5);
    my $targetIp = xCAT::zvmUtils->getIp($tgtNode);
    if (!$targetIp) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing IP for $tgtNode in /etc/hosts");
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Verify that the node's IP address is specified in the hosts table and then run makehosts");
        return;
    }
    xCAT::zvmUtils->printSyslog("hcp:$hcp tgtUserId:$tgtUserId targetIp:$targetIp");

    my $out;
    my $outmsg;
    my @lines;
    my @words;

    # Get disk pool and multi password
    my $i;
    my %inputs;
    foreach $i (1 .. 2) {
        if ($args->[$i]) {

            # Split parameters by '='
            @words = split("=", $args->[$i]);

            # Create hash array
            $inputs{ $words[0] } = $words[1];
        }
    }

    # Get disk pool
    my $pool = $inputs{"pool"};
    if (!$pool) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing disk pool. Please specify one.");
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
    $propVals = xCAT::zvmUtils->getNodeProps('mac', $tgtNode, @propNames);
    if ($propVals) {

        # Get MACID
        $targetMac = $propVals->{'mac'};
        $macId     = $propVals->{'mac'};
        $macId     = xCAT::zvmUtils->replaceStr($macId, ":", "");
        $macId     = substr($macId, 6);
    } else {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing target MAC address");
        return;
    }

    # If the user entry contains a NICDEF statement
    $out = `cat $userEntry | egrep -a -i "NICDEF"`;
    if ($out) {

        # Get the networks used by the zHCP
        my @hcpNets = xCAT::zvmCPUtils->getNetworkNamesArray($::SUDOER, $hcp);

        # Search user entry for network name
        my $hcpNetName = '';
        foreach (@hcpNets) {
            if ($out =~ m/ $_/i) {
                $hcpNetName = $_;
                last;
            }
        }

        # If the user entry contains a MACID
        $out = `cat $userEntry | egrep -a -i "MACID"`;
        if ($out) {
            my $pos = rindex($out, "MACID");
            my $oldMacId = substr($out, $pos + 6, 12);
            $oldMacId = xCAT::zvmUtils->trimStr($oldMacId);

            # Replace old MACID
            $out = `sed -i -e "s,$oldMacId,$macId,i" $userEntry`;
        } else {

            # Find NICDEF statement
            my $oldNicDef = `cat $userEntry | egrep -a -i "NICDEF" | egrep -a -i "$hcpNetName"`;
            $oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
            my $nicDef = xCAT::zvmUtils->replaceStr($oldNicDef, $hcpNetName, "$hcpNetName MACID $macId");

            # Append MACID at the end
            $out = `sed -i -e "s,$oldNicDef,$nicDef,i" $userEntry`;
        }
    }

    # SCP user entry file over to HCP
    xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $userEntry, $userEntry);

    #*** Create new virtual server ***
    my $try = 5;
    while ($try > 0) {
        if ($try > 4) {
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Creating user directory entry");
        } else {
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Trying again ($try) to create user directory entry");
        }
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Create_DM -T $tgtUserId -f $userEntry"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Create_DM -T $tgtUserId -f $userEntry");
        xCAT::zvmUtils->printSyslog("$out");

        # Check if user entry is created
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId" | sed '\$d'`;
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $tgtUserId | sed '\$d'");
        xCAT::zvmUtils->printSyslog("$out");
        $rc = xCAT::zvmUtils->checkOutput($out);

        if ($rc == -1) {

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
    if ($rc == -1) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Could not create user entry");
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Verify that the node's zHCP and its zVM's SMAPI are both online");
        return;
    }

    # Load VMCP module on HCP and source node
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;

    # Grant access to VSwitch for Linux user
    # GuestLan do not need permissions
    my %vswitchhash;
    foreach (@srcVswitch) {

        # skip grant if we already did one for this vswitch
        if (exists $vswitchhash{$_}) {
            xCAT::zvmUtils->printSyslog("clone. Skipping duplicate vswitch grant from: $_");
        }
        else {
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Granting VSwitch ($_) access for $tgtUserId");

            # If this is one of our recent provisions the directory of the source should contain any vlan id grants also
            $out = xCAT::zvmCPUtils->grantVSwitch($callback, $::SUDOER, $hcp, $tgtUserId, $_, '', '');

            # Check for errors
            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc == -1) {

                # Exit on bad output
                xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");
                return;
            }
            $vswitchhash{$_} = '1';
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
        @words = split(' ', $_);
        $addr = $words[1];
        push(@tgtDisks, $addr);
        $type = $words[2];
        $mode = $words[6];
        if (!$mode) {
            $mode = "MR";
        }

        # Add 0 in front if address length is less than 4
        while (length($addr) < 4) {
            $addr = '0' . $addr;
        }

        # Add ECKD disk
        if ($type eq '3390') {

            # Get disk size (cylinders)
            $cyl = $srcDiskSize{$addr};

            $try = 5;
            while ($try > 0) {

                # Add ECKD disk
                if ($try > 4) {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Adding minidisk ($addr)");
                } else {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)");
                }
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 3390 -a AUTOG -r $pool -u 1 -z $cyl -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw");
                xCAT::zvmUtils->printSyslog("$out");
                xCAT::zvmUtils->printLn($callback, "$out");

                # Check output
                $rc = xCAT::zvmUtils->checkOutput($out);
                if ($rc == -1) {

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
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Could not add minidisk ($addr) $out");
                return;
            }
        }    # End of if ( $type eq '3390' )

        # Add FBA disk
        elsif ($type eq '9336') {

            # Get disk size (blocks)
            my $blkSize = '512';
            my $blks    = $srcDiskSize{$addr};

            $try = 10;
            while ($try > 0) {

                # Add FBA disk
                if ($try > 9) {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Adding minidisk ($addr)");
                } else {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)");
                }
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 9336 -a AUTOG -r $pool -u 1 -z $blks -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 9336 -a AUTOG -r $pool -u 1 -z $blks -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw");
                xCAT::zvmUtils->printSyslog("$out");
                xCAT::zvmUtils->printLn($callback, "$out");

                # Check output
                $rc = xCAT::zvmUtils->checkOutput($out);
                if ($rc == -1) {

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
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Could not add minidisk ($addr) $out");
                return;
            }
        }    # End of elsif ( $type eq '9336' )
    }

    # Check if the number of disks in target user entry
    # is equal to the number of disks added
    my @disks;
    $try = 10;
    xCAT::zvmUtils->printLn($callback, "$tgtNode: Disks added (@tgtDisks). Checking directory for those disks...");
    while ($try > 0) {

        # Get disks within user entry
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $tgtUserId");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId\"", $hcp, "clone", $out, $tgtNode);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $out = `echo "$out" | sed '\$d' | grep -a -i "MDISK"`;
        xCAT::zvmUtils->printSyslog("$out");
        @disks = split('\n', $out);

        if (@disks != @tgtDisks) {
            $try = $try - 1;

            # Wait before trying again
            sleep(5);
        } else {
            last;
        }
    }

    # Exit if all disks are not present
    if (@disks != @tgtDisks) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) After 50 seconds, all disks not present in target directory.");
        xCAT::zvmUtils->printSyslog("$tgtNode: (Error) After 50 seconds, all disks not present in target directory.");

        xCAT::zvmUtils->printLn($callback, "$tgtNode: Disks found in $sourceId source directory (@tgtDisks). Disks found in $tgtUserId target directory (@disks)");
        xCAT::zvmUtils->printSyslog("$tgtNode: Disks found in $sourceId + source directory (@tgtDisks). Disks found in $tgtUserId target directory (@disks)");

        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Verify disk pool($pool) has free disks and that directory updates are working");
        return;
    }

    #**  * Link, format, and copy source disks ***
    my $srcAddr;
    my $directoryMdiskAddr;
    my $tgtAddr;
    my $srcDevNode;
    my $tgtDevNode;
    my $tgtDiskType;

    foreach (@tgtDisks) {

        # Get disk type (3390 or 9336)
        $tgtDiskType = $srcDiskType{$_};

        #*** Try to use SMAPI flashcopy first if ECKD  ***
        # Otherwise link the target disks and if ECKD, try CP Flashcopy. If
        # CP flashcopy does not work or not ECKD; use Linux DD
        my $ddCopy             = 0;
        my $cpFlashcopy        = 1;
        my $smapiFlashCopyDone = 0;
        $directoryMdiskAddr = $_;

        if ($tgtDiskType eq '3390') {

            # Try SMAPI FLASHCOPY
            if (xCAT::zvmUtils->smapi4xcat($::SUDOER, $hcp)) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($directoryMdiskAddr) to target disk ($directoryMdiskAddr) using FLASHCOPY");
                xCAT::zvmUtils->printSyslog("$tgtNode: Doing SMAPI flashcopy source disk ($sourceId $directoryMdiskAddr) to target disk ($tgtUserId $directoryMdiskAddr) using FLASHCOPY");
                $out = xCAT::zvmCPUtils->smapiFlashCopy($::SUDOER, $hcp, $sourceId, $directoryMdiskAddr, $tgtUserId, $directoryMdiskAddr);

                # Exit if flashcopy completed successfully
                # Otherwise, if not built in xCAT, try CP FLASHCOPY
                if (($out =~ m/Done/i) or (($out =~ m/Return Code: 592/i) and ($out =~ m/Reason Code: 8888/i))) {
                    xCAT::zvmUtils->printSyslog("$tgtNode: SMAPI flashcopy done. output:<$out>");
                    $cpFlashcopy        = 0;
                    $smapiFlashCopyDone = 1;

                    # now link the disk in zhcp for further tailoring
                    $try = 10;
                    while ($try > 0) {

                        # Add 0 in front if address length is less than 4
                        while (length($directoryMdiskAddr) < 4) {
                            $directoryMdiskAddr = '0' . $directoryMdiskAddr;
                        }

                        # New disk address
                        $tgtAddr = $directoryMdiskAddr + 2000;

                        # Check if new disk address is used (target)
                        $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtAddr);

                        # If disk address is used (target)
                        while ($rc == 0) {

                            # Generate a new disk address
                            # Sleep 5 seconds to let existing disk appear
                            sleep(5);
                            $tgtAddr = $tgtAddr + 1;
                            $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtAddr);
                        }

                        # Link target disk
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: Linking target disk ($directoryMdiskAddr) as ($tgtAddr)");
                        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $directoryMdiskAddr $tgtAddr MR $tgtPw"`;

                        # If link fails
                        if ($out =~ m/not linked/i || $out =~ m/not write-enabled/i) {

                            # Wait before trying again
                            sleep(5);

                            $try = $try - 1;
                        } else {
                            last;
                        }
                    }    # End of while ( $try > 0 )

                    # If target disk is not linked
                    if ($out =~ m/not linked/i) {
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to link target disk ($directoryMdiskAddr)");
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed");

                        # Exit
                        return;
                    }

                } else {
                    xCAT::zvmUtils->printLn($callback, "$out");
                    xCAT::zvmUtils->printSyslog("$tgtNode: SMAPI Flashcopy error, trying CP Flashcopy. SMAPI output: $out");
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: SMAPI Flashcopy error, trying CP Flashcopy.");
                }
            }
        }

        # If SMAPI flashcopy did not work or this is not an ECKD, then link the target disks in write mode
        if (!$smapiFlashCopyDone) {

            #*** Link target disk ***
            $try = 10;
            while ($try > 0) {

                # Add 0 in front if address length is less than 4
                while (length($_) < 4) {
                    $_ = '0' . $_;
                }

                # New disk address
                $srcAddr = $srcLinkAddr{$_};
                $tgtAddr = $_ + 2000;

                # Check if new disk address is used (target)
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtAddr);

                # If disk address is used (target)
                while ($rc == 0) {

                    # Generate a new disk address
                    # Sleep 5 seconds to let existing disk appear
                    sleep(5);
                    $tgtAddr = $tgtAddr + 1;
                    $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtAddr);
                }

                # Link target disk
                xCAT::zvmUtils->printLn($callback, "$tgtNode: Linking target disk ($_) as ($tgtAddr)");
                $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $_ $tgtAddr MR $tgtPw"`;

                # If link fails
                if ($out =~ m/not linked/i || $out =~ m/not write-enabled/i) {

                    # Wait before trying again
                    sleep(5);

                    $try = $try - 1;
                } else {
                    last;
                }
            }    # End of while ( $try > 0 )

            # If target disk is not linked
            if ($out =~ m/not linked/i) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to link target disk ($_)");
                xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed");

                # Exit
                return;
            }
            if ($tgtDiskType eq '3390') {


                # Use CP FLASHCOPY
                if ($cpFlashcopy) {

                    # Check for CP flashcopy lock
                    my $wait = 0;
                    while (`ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"` && $wait < 90) {

                        # Wait until the lock dissappears
                        # 90 seconds wait limit
                        sleep(2);
                        $wait = $wait + 2;
                    }

                    # If flashcopy locks still exists
                    if (`ssh $::SUDOER\@$hcp "$::SUDO ls /tmp/.flashcopy_lock"`) {

                        # Detatch disks from HCP
                        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Flashcopy lock is enabled");
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Remove lock by deleting /tmp/.flashcopy_lock on the zHCP. Use caution!");
                        return;
                    } else {

                        # Enable lock
                        $out = `ssh $::SUDOER\@$hcp "$::SUDO touch /tmp/.flashcopy_lock"`;

                        # Flashcopy source disk
                        $out = xCAT::zvmCPUtils->flashCopy($::SUDOER, $hcp, $srcAddr, $tgtAddr);
                        xCAT::zvmUtils->printSyslog("flashCopy: $out");
                        $rc = xCAT::zvmUtils->checkOutput($out);
                        if ($rc == -1) {
                            xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");
                            xCAT::zvmUtils->printSyslog("$tgtNode: CP Flashcopy error,  trying Linux DD next.");

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
                xCAT::zvmUtils->printLn($callback, "$tgtNode: FLASHCOPY not working. Using Linux DD");

                # Enable target disk
                $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $tgtAddr);

                # Determine source device node
                $srcDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $srcAddr);

                # Determine target device node
                $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtAddr);

                # Format target disk
                # Only ECKD disks need to be formated
                if ($tgtDiskType eq '3390') {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Formating target disk ($tgtAddr)");
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;
                    xCAT::zvmUtils->printSyslog("dasdfmt -b 4096 -y -f /dev/$tgtDevNode");

                    # Check for errors
                    $rc = xCAT::zvmUtils->checkOutput($out);
                    if ($rc == -1) {
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

                        # Detatch disks from HCP
                        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;

                        return;
                    }

                    # Sleep 2 seconds to let the system settle
                    sleep(2);

                    # Copy source disk to target disk
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)");
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
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)");
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512 oflag=sync && $::SUDO echo $?"`;
                    $out = xCAT::zvmUtils->trimStr($out);
                    if (int($out) != 0) {

                        # If $? is not 0 then there was an error during Linux dd
                        $out = "(Error) Failed to copy /dev/$srcDevNode";
                    }

                    xCAT::zvmUtils->printSyslog("dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512 oflag=sync");
                    xCAT::zvmUtils->printSyslog("$out");

                    # Force Linux to re-read partition table
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Forcing Linux to re-read partition table");
                    $out =
`ssh $::SUDOER\@$hcp "$::SUDO cat<<EOM | fdisk /dev/$tgtDevNode
   p
   w
   EOM"`;
                }

                # Check for error
                $rc = xCAT::zvmUtils->checkOutput($out);
                if ($rc == -1) {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

                    # Disable disks
                    $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtAddr);

                    # Detatch disks from zHCP
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;

                    return;
                }

                # Sleep 2 seconds to let the system settle
                sleep(2);
            }    # end if ddcopy
        }    # end if SMAPI flashcopy did not complete


        # Disable and enable target disk
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtAddr);
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $tgtAddr);

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
                xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp \"$::SUDO /usr/bin/file -s /dev/$tgtDevNode*\"");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/file -s /dev/$tgtDevNode*"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO /usr/bin/file -s /dev/$tgtDevNode*\"", $hcp, "clone", $out, $tgtDevNode);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, "$outmsg");
                    return;
                }
            } else {
                xCAT::zvmUtils->printSyslog("ssh $::SUDOER\@$hcp \"$::SUDO /sbin/fdisk -l /dev/$tgtDevNode*\"");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/fdisk -l /dev/$tgtDevNode*"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO /sbin/fdisk -l /dev/$tgtDevNode*\"", $hcp, "clone", $out, $tgtDevNode);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, "$outmsg");
                    return;
                }
            }
            $out = `echo "$out" | egrep -a -i -v swap | egrep -a -o "$tgtDevNode\[1-9\]"`;
            $out = xCAT::zvmUtils->trimStr($out);
            xCAT::zvmUtils->printSyslog("$out");

            # Wait before trying again
            sleep(5);
            $try = $try - 1;
        }

        my @tgtDevNodes = split("\n", $out);
        my $iTgtDevNode = 0;
        $tgtDevNode = xCAT::zvmUtils->trimStr($tgtDevNodes[$iTgtDevNode]);

        xCAT::zvmUtils->printLn($callback, "$tgtNode: Mounting /dev/$tgtDevNode to $cloneMntPt");
        xCAT::zvmUtils->printSyslog("tgtDevNodes:@tgtDevNodes");

        # Check the disk is mounted
        $try = 5;
        while (!(`ssh $::SUDOER\@$hcp "$::SUDO ls $cloneMntPt"`) && $try > 0) {
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
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed to mount /dev/$tgtDevNode. Skipping device.");
        }

        # Is this the partition containing /etc?
        if (`ssh $::SUDOER\@$hcp "$::SUDO test -d $cloneMntPt/etc && echo Exists"`) {

            #*** Set network configuration ***
            # Set hostname
            xCAT::zvmUtils->printLn($callback, "$tgtNode: Setting network configuration");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceNode/$tgtNode/i\" $cloneMntPt/etc/HOSTNAME"`;
            $rc = $? >> 8;
            if ($rc == 255) { # Adding "Failed" to message will cause zhcp error dialog to be displayed to user
                xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp rc:$?");
                xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp rc:$?");
                return;
            }
            xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceNode/$tgtNode/i $cloneMntPt/etc/HOSTNAME output:$out");

            # If Red Hat - Set hostname in /etc/sysconfig/network
            if ($srcOs =~ m/rhel/i) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceNode/$tgtNode/i\" $cloneMntPt/etc/sysconfig/network"`;
                xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceNode/$tgtNode/i $cloneMntPt/etc/sysconfig/network");
            }

            # Get network layer
            my $layer = xCAT::zvmCPUtils->getNetworkLayer($::SUDOER, $hcp, $hcpNetName);
            xCAT::zvmUtils->printSyslog("hcp:$hcp hcpNetName:$hcpNetName layer:$layer");

            # Get network configuration file
            # Location of this file depends on the OS
            my $srcIfcfg = '';

            # If it is Red Hat - ifcfg-qeth file is in /etc/sysconfig/network-scripts
            my @files;
            if ($srcOs =~ m/rhel/i) {
                xCAT::zvmUtils->printSyslog("grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network-scripts");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network-scripts"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network-scripts\"", $hcp, "clone", $out, $tgtDevNode);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, "$outmsg");
                    return;
                }
                $out = `echo "$out" | egrep -a -i 'ifcfg-eth'`;
                xCAT::zvmUtils->printSyslog("$out");
                @files = split('\n', $out);
                @words = split(':',  $files[0]);
                $srcIfcfg = $words[0];
            }

            # If it is SLES 10 - ifcfg-qeth file is in /etc/sysconfig/network
            elsif ($srcOs =~ m/sles10/i) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-qeth*"`;
                xCAT::zvmUtils->printSyslog("grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-qeth*");
                xCAT::zvmUtils->printSyslog("$out");
                @files = split('\n', $out);
                @words = split(':',  $files[0]);
                $srcIfcfg = $words[0];
            }

            # If it is SLES 11 - ifcfg-qeth file is in /etc/sysconfig/network
            elsif ($srcOs =~ m/sles11/i) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-eth*"`;
                xCAT::zvmUtils->printSyslog("grep -a -H -i -r $srcNicAddr $cloneMntPt/etc/sysconfig/network/ifcfg-eth*");
                xCAT::zvmUtils->printSyslog("$out");
                @files = split('\n', $out);
                @words = split(':',  $files[0]);
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
                $tgtMask    = $_->{'mask'};

                # If the host IP address is in this subnet, return
                if (xCAT::NetworkUtils->ishostinsubnet($targetIp, $tgtMask, $tgtNetwork)) {

                    # Exit loop
                    last;
                } else {
                    $tgtNetwork = "";
                }
            }

            # Make sure we change all host name occurrances: long and short. Change old IP to new IP
            # add in a duplicate change in case they put in two space delimited tokens
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \'s/$sourceIp/$targetIp/i\' \ -e \'s/ $sourceNode / $tgtNode /gi\' \ -e \'s/ $sourceNode / $tgtNode /gi\' \ -e \'s/ $sourceNode\\\./ $tgtNode\\\./gi\' \ -e \'s/ $sourceNode\\\$/ $tgtNode/gi\' \ $cloneMntPt/etc/hosts"`;
            $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$sourceIp/$targetIp/i\" \ -e \"s/$sourceNode/$tgtNode/i\" $ifcfgPath"`;
            xCAT::zvmUtils->printSyslog("sed -i -e \'s/$sourceIp/$targetIp/i\' \ -e \'s/ $sourceNode / $tgtNode /gi\' \ -e \'s/ $sourceNode / $tgtNode /gi\' \ -e \'s/ $sourceNode\\\./ $tgtNode\\\./gi\' \ -e \'s/ $sourceNode\\\$/ $tgtNode/gi\' \ $cloneMntPt/etc/hosts");
            xCAT::zvmUtils->printSyslog("sed -i -e s/$sourceIp/$targetIp/i \ -e s/$sourceNode/$tgtNode/i $ifcfgPath");

            if ($tgtNetwork && $tgtMask) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO sed -i -e \"s/$srcNetwork/$tgtNetwork/i\" \ -e \"s/$srcMask/$tgtMask/i\" $ifcfgPath"`;
                xCAT::zvmUtils->printSyslog("sed -i -e s/$srcNetwork/$tgtNetwork/i \ -e s/$srcMask/$tgtMask/i $ifcfgPath");
            }

            # Set MAC address
            my $networkFile = $tgtNode . "NetworkConfig";
            my $config;

            $config = `ssh $::SUDOER\@$hcp "$::SUDO cat $ifcfgPath"`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $ifcfgPath\"", $hcp, "clone", $config, $tgtDevNode);
            if ($rc != 0) {
                xCAT::zvmUtils->printLn($callback, "$outmsg");
                return;
            }
            if ($srcOs =~ m/rhel/i) {

                # Red Hat only
                $config = `echo "$config" | egrep -a -i -v "MACADDR"`;
                $config .= "MACADDR='" . $targetMac . "'\n";
            } else {

                # SUSE only
                $config = `echo "$config" | egrep -a -i -v "LLADDR" | egrep -a -i -v "UNIQUE"`;

                # Set to MAC address (only for layer 2)
                if ($layer == 2) {
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
            if ($layer == 2) {
                if ($srcOs =~ m/rhel/i && $srcMac) {

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
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO cat $hwcfgPath" | grep -a -v "QETH_LAYER2_SUPPORT" > /tmp/$hardwareFile`;
                    $out = `echo "QETH_LAYER2_SUPPORT='1'" >> /tmp/$hardwareFile`;
                    xCAT::zvmUtils->sendFile($::SUDOER, $hcp, "/tmp/$hardwareFile", $hwcfgPath);

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
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtAddr);

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
    xCAT::zvmUtils->printLn($callback, "$tgtNode: Powering on");
    $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $tgtUserId"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $tgtUserId");

    # Check for error
    $rc = xCAT::zvmUtils->checkOutput($out);
    if ($rc == -1) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");
        return;
    }
}

#-------------------------------------------------------

=head3   nodeSet

    Description : Set the boot state for a node
                    * Punch initrd, kernel, and parmfile to node reader
                    * Layer 2 and 3 VSwitch/Lan supported
    Arguments   : Node
    Returns     : Nothing, errors returned in $callback
    Example     : nodeSet($callback, $node, $args);

=cut

#-------------------------------------------------------
sub nodeSet {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid', 'status');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # If the node is being actively cloned then return.
    if ($propVals->{'status'} =~ /CLONING=1/ and $propVals->{'status'} =~ /CLONE_ONLY=1/) {
        return;
    }

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
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
    my $rc;

    foreach my $arg (@$args) {
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
        $propVals = xCAT::zvmUtils->getTabPropsByKey('osimage', 'imagename', $osImg, @propNames);

        # Update nodetype table with os, arch, and profile based on osimage
        if (!$propVals->{'profile'} || !$propVals->{'provmethod'} || !$propVals->{'osvers'} || !$propVals->{'osarch'}) {

            # Exit
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing profile, provmethod, osvers, or osarch for osimage");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Provide profile, provmethod, osvers, and osarch in the osimage definition");
            return;
        }

        # Update nodetype table with osimage attributes for node
        my %propHash = (
            'os'         => $propVals->{'osvers'},
            'arch'       => $propVals->{'osarch'},
            'profile'    => $propVals->{'profile'},
            'provmethod' => $propVals->{'provmethod'}
        );
        xCAT::zvmUtils->setNodeProps('nodetype', $node, \%propHash);
        $action = $propVals->{'provmethod'};
    }

    # Get install directory and domain from site table
    my @entries    = xCAT::TableUtils->get_site_attribute("installdir");
    my $installDir = $entries[0];
    @entries = xCAT::TableUtils->get_site_attribute("domain");
    my $domain = $entries[0];
    @entries = xCAT::TableUtils->get_site_attribute("master");
    my $master = $entries[0];
    @entries = xCAT::TableUtils->get_site_attribute("xcatdport");
    my $xcatdPort = $entries[0];

    # Get node OS, arch, and profile from 'nodetype' table
    @propNames = ('os', 'arch', 'profile');
    $propVals = xCAT::zvmUtils->getNodeProps('nodetype', $node, @propNames);

    $os      = $propVals->{'os'};
    $arch    = $propVals->{'arch'};
    $profile = $propVals->{'profile'};

    # If no OS, arch, or profile is found
    if (!$os || !$arch || !$profile) {

        # Exit
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node OS, arch, and profile in nodetype table");
        return;
    }

    # Get action
    my $out;
    my $outmsg;
    if ($action eq "install") {

        # Get node root password
        @propNames = ('password');
        $propVals = xCAT::zvmUtils->getTabPropsByKey('passwd', 'key', 'system', @propNames);
        my $passwd = $propVals->{'password'};
        if (!$passwd) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing root password for this node");
            return;
        }

        # Get node OS base
        my @tmp;
        if ($os =~ m/sp/i) {
            @tmp = split(/sp/, $os);
        } else {
            @tmp = split(/\./, $os);
        }
        my $osBase = $tmp[0];

        # Get node distro
        my $distro = "";
        if ($os =~ m/sles/i) {
            $distro = "sles";
        } elsif ($os =~ m/rhel/i) {
            $distro = "rh";
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to determine node Linux distribution");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Verify the node Linux distribution is either sles* or rh*");
            return;
        }

        # Get autoyast/kickstart template
        my $tmpl;

        # Check for $profile.$os.$arch.tmpl
        if (-e "$installDir/custom/install/$distro/$profile.$os.$arch.tmpl") {
            $tmpl = "$profile.$os.$arch.tmpl";
        }

        # Check for $profile.$osBase.$arch.tmpl
        elsif (-e "$installDir/custom/install/$distro/$profile.$osBase.$arch.tmpl") {
            $tmpl = "$profile.$osBase.$arch.tmpl";
        }

        # Check for $profile.$arch.tmpl
        elsif (-e "$installDir/custom/install/$distro/$profile.$arch.tmpl") {
            $tmpl = "$profile.$arch.tmpl";
        }

        # Check for $profile.tmpl second
        elsif (-e "$installDir/custom/install/$distro/$profile.tmpl") {
            $tmpl = "$profile.tmpl";
        }
        else {
            # No template exists
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing autoyast/kickstart template: $installDir/custom/install/$distro/$profile.$os.$arch.tmpl");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Create a template under $installDir/custom/install/$distro/");
            return;
        }

        # Get host IP and hostname from /etc/hosts
        $out = `cat /etc/hosts | egrep -a -i "$node |$node."`;
        my @words    = split(' ', $out);
        my $hostIP   = $words[0];
        my $hostname = $words[2];
        if (!($hostname =~ m/./i)) {
            $hostname = $words[1];
        }

        if (!$hostIP || !$hostname) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing IP for $node in /etc/hosts");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Verify that the nodes IP address is specified in the hosts table and then run makehosts");
            return;
        }

        # Check template if DHCP is used
        my $dhcp = 0;
        if ($distro eq "sles") {

            # Check autoyast template
            if (-e "$installDir/custom/install/sles/$tmpl") {
                $out = `cat $installDir/custom/install/sles/$tmpl | egrep -a -i "<bootproto>"`;
                if ($out =~ m/dhcp/i) {
                    $dhcp = 1;
                }
            }
        } elsif ($distro eq "rh") {

            # Check kickstart template
            if (-e "$installDir/custom/install/rh/$tmpl") {
                $out = `cat $installDir/custom/install/rh/$tmpl | egrep -a -ie "--bootproto dhcp"`;
                if ($out =~ m/dhcp/i) {
                    $dhcp = 1;
                }
            }
        }

        # Get the noderes.primarynic
        my $channel = '';
        my $layer;
        my $i;

        @propNames = ('primarynic', 'nfsserver', 'xcatmaster');
        $propVals = xCAT::zvmUtils->getNodeProps('noderes', $node, @propNames);

        my $repo = $propVals->{'nfsserver'};   # Repository containing Linux ISO
        my $xcatmaster = $propVals->{'xcatmaster'};
        my $primaryNic = $propVals->{'primarynic'}; # NIC to use for OS installation

        # If noderes.primarynic is not specified, find an acceptable NIC shared with the zHCP
        if ($primaryNic) {
            $layer = xCAT::zvmCPUtils->getNetworkLayer($::SUDOER, $hcp, $primaryNic);

            # If DHCP is used and the NIC is not layer 2, then exit
            if ($dhcp && $layer != 2) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) The template selected uses DHCP. A layer 2 VSWITCH or GLAN is required. None were found.");
                xCAT::zvmUtils->printLn($callback, "$node: (Solution) Modify the template to use <bootproto>static</bootproto> or --bootproto=static, or change the network device attached to virtual machine");
                return;
            }

            # Find device channel of NIC
            my $userEntry = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $userId" | sed '\$d'`;
            $out = `echo "$userEntry" | grep -a "NICDEF" | grep -a "$primaryNic"`;

            # Check user profile for device channel
            if (!$out) {
                my $profileName = `echo "$userEntry" | grep -a "INCLUDE"`;
                if ($profileName) {
                    @words = split(' ', xCAT::zvmUtils->trimStr($profileName));

                    # Get user profile
                    my $userProfile = xCAT::zvmUtils->getUserProfile($::SUDOER, $hcp, $words[1]);

                    # Get the NICDEF statement containing the HCP network
                    $out = `echo "$userProfile" | grep -a "NICDEF" | grep -a "$primaryNic"`;
                }
            }

            # Grab the device channel from the NICDEF statement
            my @lines = split('\n', $out);
            @words = split(' ', $lines[0]);
            $channel = sprintf('%d', hex($words[1]));
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: Searching for acceptable network device");
            ($primaryNic, $channel, $layer) = xCAT::zvmUtils->findUsablezHcpNetwork($::SUDOER, $hcp, $userId, $dhcp);

            # If DHCP is used and not layer 2
            if ($dhcp && $layer != 2) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) The template selected uses DHCP. A layer 2 VSWITCH or GLAN is required. None were found.");
                xCAT::zvmUtils->printLn($callback, "$node: (Solution) Modify the template to use <bootproto>static</bootproto> or change the network device attached to virtual machine");
                return;
            }
        }

        # Exit if no suitable network found
        if (!$primaryNic || !$channel || !$layer) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) No suitable network device found in user directory entry");
            return;
        }

        xCAT::zvmUtils->printLn($callback, "$node: Setting up networking on $primaryNic (layer:$layer | DHCP:$dhcp)");

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
            $propVals = xCAT::zvmUtils->getTabPropsByKey('mac', 'node', $node, @propNames);
            $mac = $propVals->{'mac'};

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
            $mask    = $_->{'mask'};

            # If the host IP address is in this subnet, return
            if (xCAT::NetworkUtils->ishostinsubnet($hostIP, $mask, $network)) {

                # Exit loop
                last;
            } else {
                $network = "";
            }
        }

        # If no network found
        if (!$network) {

            # Exit
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Node does not belong to any network in the networks table");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Specify the subnet in the networks table. The mask, gateway, tftpserver, and nameservers must be specified for the subnet.");
            return;
        }

        @propNames = ('mask', 'gateway', 'tftpserver', 'nameservers');
        $propVals = xCAT::zvmUtils->getTabPropsByKey('networks', 'net', $network, @propNames);
        $mask = $propVals->{'mask'};
        my $gateway = $propVals->{'gateway'};

        # Convert <xcatmaster> to nameserver IP
        my $nameserver;
        if ($propVals->{'nameservers'} eq '<xcatmaster>') {
            $nameserver = xCAT::InstUtils->convert_xcatmaster();
        } else {
            $nameserver = $propVals->{'nameservers'};
        }

        if (!$network || !$mask || !$nameserver) {

            # It is acceptable to not have a gateway
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing network information");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Specify the mask, gateway, and nameservers for the subnet in the networks table");
            return;
        }

        @propNames = ('nfsserver', 'xcatmaster');
        $propVals = xCAT::zvmUtils->getNodeProps('noderes', $node, @propNames);
        $repo = $propVals->{'nfsserver'};    # Repository containing Linux ISO
        $xcatmaster = $propVals->{'xcatmaster'};

        # Use noderes.xcatmaster instead of site.master if it is given
        if ($xcatmaster) {
            $master = $xcatmaster;
        }

        # Combine NFS server and installation directory, e.g. 10.0.0.1/install
        my $nfs = $master . $installDir;

        # Get broadcast address
        @words = split(/\./, $hostIP);
        my ($ipUnpack) = unpack("N", pack("C4", @words));
        @words = split(/\./, $mask);
        my ($maskUnpack) = unpack("N", pack("C4", @words));

        # Calculate broadcast address by inverting the netmask and do a logical or with network address
        my $math = ($ipUnpack & $maskUnpack) + (~$maskUnpack);
        @words = unpack("C4", pack("N", $math));
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
        my $osaMedium = "eth";  # OSA medium = eth (ethernet) or tr (token ring)

        # Default parameters - RHEL
        my $netType  = "qeth";
        my $portName = "FOOBAR";
        my $portNo   = "0";

        # Get postscript content
        my $postScript;
        if ($os =~ m/sles10/i) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.sles10.s390x";
        } elsif ($os =~ m/sles11/i) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.sles11.s390x";
        } elsif ($os =~ m/rhel5/i) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.rhel5.s390x";
        } elsif ($os =~ m/rhel6/i) {
            $postScript = "/opt/xcat/share/xcat/install/scripts/post.rhel6.s390x";
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) No postscript available for $os");
            return;
        }

        # SUSE installation
        my $customTmpl;
        my $pkglist;
        my $patterns = '';
        my $packages = '';
        my $postBoot = "$installDir/postscripts/xcatinstallpost";
        my $postInit = "$installDir/postscripts/xcatpostinit1";
        if ($os =~ m/sles/i) {

            # Create directory in FTP root (/install) to hold template
            $out = `mkdir -p $installDir/custom/install/sles`;

            # Copy autoyast template
            $customTmpl = "$installDir/custom/install/sles/" . $node . "." . $profile . ".tmpl";
            if (-e "$installDir/custom/install/sles/$tmpl") {
                $out = `cp $installDir/custom/install/sles/$tmpl $customTmpl`;
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) An autoyast template does not exist for $os in $installDir/custom/install/sles/. Please create one.");
                return;
            }

            # Get pkglist from /install/custom/install/sles/compute.sles11.s390x.otherpkgs.pkglist
            # Original one is in /opt/xcat/share/xcat/install/sles/compute.sles11.s390x.otherpkgs.pkglist
            $pkglist = "/install/custom/install/sles/" . $profile . "." . $osBase . "." . $arch . ".pkglist";
            if (!(-e $pkglist)) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing package list for $os in /install/custom/install/sles/");
                xCAT::zvmUtils->printLn($callback, "$node: (Solution) Please create one or copy default one from /opt/xcat/share/xcat/install/sles/");
                return;
            }

            # Read in each software pattern or package
            open(FILE, $pkglist);
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
            close(FILE);

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
            if ($os =~ m/sles11/i) {
                $device = "eth0";
            } else {

                # SLES 10
                $device = "qeth-bus-ccw-$readChannel";
            }

            # remove any line ends
            chomp($hostIP);
            chomp($hostname);
            chomp($node);
            chomp($domain);
            chomp($node);
            chomp($nameserver);
            chomp($broadcast);
            chomp($device);
            chomp($hostIP);
            chomp($mac);
            chomp($mask);
            chomp($network);
            chomp($chanIds);
            chomp($gateway);
            chomp($passwd);
            chomp($readChannel);
            chomp($master);

            # remove any blanks
            $hostIP      = xCAT::zvmUtils->trimStr($hostIP);
            $hostname    = xCAT::zvmUtils->trimStr($hostname);
            $node        = xCAT::zvmUtils->trimStr($node);
            $domain      = xCAT::zvmUtils->trimStr($domain);
            $node        = xCAT::zvmUtils->trimStr($node);
            $nameserver  = xCAT::zvmUtils->trimStr($nameserver);
            $broadcast   = xCAT::zvmUtils->trimStr($broadcast);
            $device      = xCAT::zvmUtils->trimStr($device);
            $hostIP      = xCAT::zvmUtils->trimStr($hostIP);
            $mac         = xCAT::zvmUtils->trimStr($mac);
            $mask        = xCAT::zvmUtils->trimStr($mask);
            $network     = xCAT::zvmUtils->trimStr($network);
            $chanIds     = xCAT::zvmUtils->trimStr($chanIds);
            $gateway     = xCAT::zvmUtils->trimStr($gateway);
            $passwd      = xCAT::zvmUtils->trimStr($passwd);
            $readChannel = xCAT::zvmUtils->trimStr($readChannel);
            $master      = xCAT::zvmUtils->trimStr($master);

            $out = `sed -i -e "s,replace_host_address,$hostIP,g" $customTmpl`;
            $out = `sed -i -e "s,replace_long_name,$hostname,g" $customTmpl`;
            $out = `sed -i -e "s,replace_short_name,$node,g" $customTmpl`;
            $out = `sed -i -e "s,replace_domain,$domain,g" $customTmpl`;
            $out = `sed -i -e "s,replace_hostname,$node,g" $customTmpl`;
            $out = `sed -i -e "s,replace_nameserver,$nameserver,g" $customTmpl`;
            $out = `sed -i -e "s,replace_broadcast,$broadcast,g" $customTmpl`;
            $out = `sed -i -e "s,replace_device,$device,g" $customTmpl`;
            $out = `sed -i -e "s,replace_ipaddr,$hostIP,g" $customTmpl`;
            $out = `sed -i -e "s,replace_lladdr,$mac,g" $customTmpl`;
            $out = `sed -i -e "s,replace_netmask,$mask,g" $customTmpl`;
            $out = `sed -i -e "s,replace_network,$network,g" $customTmpl`;
            $out = `sed -i -e "s,replace_ccw_chan_ids,$chanIds,g" $customTmpl`;
            $out = `sed -i -e "s,replace_ccw_chan_mode,FOOBAR,g" $customTmpl`;
            $out = `sed -i -e "s,replace_gateway,$gateway,g" $customTmpl`;
            $out = `sed -i -e "s,replace_root_password,$passwd,g" $customTmpl`;
            $out = `sed -i -e "s,replace_nic_addr,$readChannel,g" $customTmpl`;
            $out = `sed -i -e "s,replace_master,$master,g" $customTmpl`;
            $out = `sed -i -e "s,replace_install_dir,$installDir,g" $customTmpl`;

            xCAT::zvmUtils->printSyslog("***Provision settings for SLES:replace_host_address,$hostIP replace_long_name,$hostname replace_short_name,$node replace_domain,$domain replace_hostname,$node replace_nameserver,$nameserver replace_broadcast,$broadcast replace_device,$device replace_ipaddr,$hostIP replace_lladdr,$mac replace_netmask,$mask replace_network,$network replace_ccw_chan_ids,$chanIds replace_ccw_chan_mode,FOOBAR replace_gateway,$gateway replace_root_password,$passwd replace_nic_addr,$readChannel replace_master,$master replace_install_dir,$installDir $customTmpl");

            # Attach SCSI FCP devices (if any)
            # Go through each pool
            # Find the SCSI device belonging to host
            my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
            my $hasZfcp = 0;
            my $entry;
            my $zfcpSection = "";
            foreach (@pools) {
                if (!(length $_)) { next; }
                $entry = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$_"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $::ZFCPPOOL/$_\"", $hcp, "nodeSet", $entry, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, "$outmsg");
                    return;
                }
                $entry = `echo "$entry" | egrep -a -i ",$node,"`;
                chomp($entry);
                if (!$entry) {
                    next;
                }

                # Go through each zFCP device
                my @device = split('\n', $entry);
                foreach (@device) {
                    if (!(length $_)) { next; }

                    # Each entry contains: status,wwpn,lun,size,range,owner,channel,tag
                    @tmp = split(',', $_);
                    my $wwpn   = $tmp[1];
                    my $lun    = $tmp[2];
                    my $device = lc($tmp[6]);
                    my $tag    = $tmp[7];

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
                    $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

                    # Make sure channel has a length of 4
                    while (length($device) < 4) {
                        $device = "0" . $device;
                    }

                    # zFCP variables must be in lower-case or AutoYast would get confused
                    $device = lc($device);
                    $wwpn   = lc($wwpn);
                    $lun    = lc($lun);

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
                my $find    = 'replace_zfcp';
                my $replace = <<END;
    <devices config:type="list">\\
END
                $replace .= $zfcpSection;
                $replace .= <<END;
    </devices>\\
END
                my $expression = "'s#" . $find . "#" . $replace . "#i'";
                $out = `sed -i -e $expression $customTmpl`;

                xCAT::zvmUtils->printLn($callback, "$node: Inserting FCP devices into template... Done");
            }

            # Read sample parmfile in /install/sles10.2/s390x/1/boot/s390x/
            $sampleParm = "$installDir/$os/s390x/1/boot/s390x/parmfile";
            open(SAMPLEPARM, "<$sampleParm");

            # Search parmfile for -- ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
            while (<SAMPLEPARM>) {

                # If the line contains 'ramdisk_size'
                if ($_ =~ m/ramdisk_size/i) {
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
            $parms = $parms . "Hostname=$hostname\n";
            $parms = $parms . " HostIP=$hostIP Gateway=$gateway Netmask=$mask\n";

            # Set layer in autoyast profile
            if ($layer == 2) {
                $parms = $parms . "Broadcast=$broadcast Layer2=1 OSAHWaddr=$mac\n";
            } else {
                $parms = $parms . "Broadcast=$broadcast Layer2=0\n";
            }

            $parms = $parms . "ReadChannel=$readChannel WriteChannel=$writeChannel DataChannel=$dataChannel\n";
            $parms = $parms . "Nameserver=$nameserver Portname=$portName Portno=0\n";
            $parms = $parms . "Install=$repo\n";
            $parms = $parms . "UseVNC=1 VNCPassword=12345678\n";
            $parms = $parms . "InstNetDev=$instNetDev OsaInterface=$osaInterface OsaMedium=$osaMedium Manual=0\n";

            xCAT::zvmUtils->printSyslog("***Parm file SLES(should be max 80 cols, 10 lines:\n$parms");

            # Write to parmfile
            $parmFile = "/tmp/" . $node . "Parm";
            open(PARMFILE, ">$parmFile");
            print PARMFILE "$parms";
            close(PARMFILE);

            # Send kernel, parmfile, and initrd to reader to HCP
            $kernelFile = "/tmp/" . $node . "Kernel";
            $initFile   = "/tmp/" . $node . "Initrd";

            if ($repo) {
                $out = `/usr/bin/wget $repo/boot/s390x/vmrdr.ikr -O $kernelFile --no-check-certificate`;
                xCAT::zvmUtils->printLn($callback, "Attempting to copy $repo/boot/s390x/vmrdr.ikr to $kernelFile");
                $out = `/usr/bin/wget $repo/boot/s390x/initrd -O $initFile --no-check-certificate`;
            } else {
                $out = `cp $installDir/$os/s390x/1/boot/s390x/vmrdr.ikr $kernelFile`;
                xCAT::zvmUtils->printLn($callback, "Attempting to copy $installDir/$os/s390x/1/boot/s390x/vmrdr.ikr to $kernelFile");
                $out = `cp $installDir/$os/s390x/1/boot/s390x/initrd $initFile`;
            }
            $out = `ls $kernelFile 2>1`;
            $rc  = $? >> 8;
            if ($rc) {
                xCAT::zvmUtils->printLn($callback, "(Failed) Did not copy the file. Did you forget to process the ISO?");
                $out = '(Failed) Did not copy the file.';
                return;
            }

            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $kernelFile, $kernelFile);
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $parmFile,   $parmFile);
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $initFile,   $initFile);

            # Set the virtual unit record devices online on HCP
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "c");
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "d");

            # Purge reader
            $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
            xCAT::zvmUtils->printLn($callback, "$node: Purging reader... Done");

            # Punch kernel to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $kernelFile, "sles.kernel", "", "");
            xCAT::zvmUtils->printLn($callback, "$node: Punching kernel to reader... $out");
            if ($out =~ m/Failed/i) {
                return;
            }

            # Punch parm to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $parmFile, "sles.parm", "-t", "");
            xCAT::zvmUtils->printLn($callback, "$node: Punching parm to reader... $out");
            if ($out =~ m/Failed/i) {
                return;
            }

            # Punch initrd to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $initFile, "sles.initrd", "", "");
            xCAT::zvmUtils->printLn($callback, "$node: Punching initrd to reader... $out");
            if ($out =~ m/Failed/i) {
                return;
            }

            # Remove kernel, parmfile, and initrd from /tmp
            $out = `rm $parmFile $kernelFile $initFile`;
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $parmFile $kernelFile $initFile"`;

            xCAT::zvmUtils->printLn($callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot.");
        }

        # RHEL installation
        elsif ($os =~ m/rhel/i) {

            # Create directory in FTP root (/install) to hold template
            $out = `mkdir -p $installDir/custom/install/rh`;

            # Copy kickstart template
            $customTmpl = "$installDir/custom/install/rh/" . $node . "." . $profile . ".tmpl";
            if (-e "$installDir/custom/install/rh/$tmpl") {
                $out = `cp $installDir/custom/install/rh/$tmpl $customTmpl`;
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) An kickstart template does not exist for $os in $installDir/custom/install/rh/");
                return;
            }

            # Get pkglist from /install/custom/install/rh/compute.rhel6.s390x.otherpkgs.pkglist
            # Original one is in /opt/xcat/share/xcat/install/rh/compute.rhel6.s390x.otherpkgs.pkglist
            $pkglist = "/install/custom/install/rh/" . $profile . "." . $osBase . "." . $arch . ".pkglist";
            if (!(-e $pkglist)) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing package list for $os in /install/custom/install/rh/");
                xCAT::zvmUtils->printLn($callback, "$node: (Solution) Please create one or copy default one from /opt/xcat/share/xcat/install/rh/");
                return;
            }

            # Read in each software pattern or package
            open(FILE, $pkglist);
            while (<FILE>) {
                chomp;
                $_ = xCAT::zvmUtils->trimStr($_);
                $packages .= "$_\\n";
            }
            close(FILE);

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

            # remove newlines
            chomp($repo);
            chomp($hostIP);
            chomp($mask);
            chomp($gateway);
            chomp($nameserver);
            chomp($hostname);
            chomp($passwd);
            chomp($master);

            # trim blanks
            $repo       = xCAT::zvmUtils->trimStr($repo);
            $hostIP     = xCAT::zvmUtils->trimStr($hostIP);
            $mask       = xCAT::zvmUtils->trimStr($mask);
            $gateway    = xCAT::zvmUtils->trimStr($gateway);
            $nameserver = xCAT::zvmUtils->trimStr($nameserver);
            $hostname   = xCAT::zvmUtils->trimStr($hostname);
            $passwd     = xCAT::zvmUtils->trimStr($passwd);
            $master     = xCAT::zvmUtils->trimStr($master);

            $out = `sed -i -e "s,replace_url,$repo,g" $customTmpl`;
            $out = `sed -i -e "s,replace_ip,$hostIP,g" $customTmpl`;
            $out = `sed -i -e "s,replace_netmask,$mask,g" $customTmpl`;
            $out = `sed -i -e "s,replace_gateway,$gateway,g" $customTmpl`;
            $out = `sed -i -e "s,replace_nameserver,$nameserver,g" $customTmpl`;
            $out = `sed -i -e "s,replace_hostname,$hostname,g" $customTmpl`;
            $out = `sed -i -e "s,replace_rootpw,$passwd,g" $customTmpl`;
            $out = `sed -i -e "s,replace_master,$master,g" $customTmpl`;
            $out = `sed -i -e "s,replace_install_dir,$installDir,g" $customTmpl`;

            xCAT::zvmUtils->printSyslog("***Provision settings for RedHat:replace_url,$repo replace_ip,$hostIP replace_netmask,$mask replace_gateway,$gateway replace_nameserver,$nameserver replace_hostname,$hostname replace_rootpw,$passwd replace_master,$master replace_install_dir,$installDir  for file==>$customTmpl");

            # Attach SCSI FCP devices (if any)
            # Go through each pool
            # Find the SCSI device belonging to host
            my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
            my $hasZfcp = 0;
            my $entry;
            my $zfcpSection = "";
            foreach (@pools) {
                if (!(length $_)) { next; }
                $entry = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$_"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $::ZFCPPOOL/$_\"", $hcp, "nodeSet", $entry, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, "$outmsg");
                    return;
                }
                $entry = `echo "$entry" | egrep -a -i ",$node,"`;
                chomp($entry);
                if (!$entry) {
                    next;
                }

                # Go through each zFCP device
                my @device = split('\n', $entry);
                foreach (@device) {
                    if (!(length $_)) { next; }

                    # Each entry contains: status,wwpn,lun,size,range,owner,channel,tag
                    @tmp = split(',', $_);
                    my $wwpn   = $tmp[1];
                    my $lun    = $tmp[2];
                    my $device = lc($tmp[6]);
                    my $tag    = $tmp[7];

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
                    $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

                    # Make sure channel has a length of 4
                    while (length($device) < 4) {
                        $device = "0" . $device;
                    }

                    # zFCP variables must be in lower-case or AutoYast would get confused.
                    $device = lc($device);
                    $wwpn   = lc($wwpn);
                    $lun    = lc($lun);

                    # Create zfcp section
                    $zfcpSection = "zfcp --devnum 0.0.$device --wwpn 0x$wwpn --fcplun 0x$lun" . '\n';

                    # Look for replace_zfcp keyword in template and replace it
                    $out     = `sed -i -e "s,$tag,$zfcpSection,i" $customTmpl`;
                    $hasZfcp = 1;
                }
            }

            if ($hasZfcp) {
                xCAT::zvmUtils->printLn($callback, "$node: Inserting FCP devices into template... Done");
            }

            # Read sample parmfile in /install/rhel5.3/s390x/images
            $sampleParm = "$installDir/$os/s390x/images/generic.prm";
            open(SAMPLEPARM, "<$sampleParm");

            # Search parmfile for -- root=/dev/ram0 ro ip=off ramdisk_size=40000
            while (<SAMPLEPARM>) {

                # If the line contains 'ramdisk_size'
                if ($_ =~ m/ramdisk_size/i) {
                    $parmHeader = xCAT::zvmUtils->trimStr($_);

                    # RHEL 6.1 needs cio_ignore in order to install
                    if (!($os =~ m/rhel6.1/i)) {
                        $parmHeader =~ s/cio_ignore=all,!0.0.0009//g;
                    }
                }
            }

            # Close sample parmfile
            close(SAMPLEPARM);

            # Get mdisk virtual address
            my @mdisks = xCAT::zvmUtils->getMdisks($callback, $::SUDOER, $node);
            if (xCAT::zvmUtils->checkOutput($mdisks[0]) == -1) {
                xCAT::zvmUtils->printLn($callback, "$mdisks[0]");
                return;
            }
            @mdisks = sort(@mdisks);
            my $dasd    = "";
            my $devices = "";
            my $i       = 0;
            foreach (@mdisks) {
                if (!(length $_)) { next; }
                $i = $i + 1;
                @words = split(' ', $_);

                # Do not put a comma at the end of the last disk address
                if ($i == @mdisks) {
                    $dasd = $dasd . "0.0.$words[1]";
                } else {
                    $dasd = $dasd . "0.0.$words[1],";
                }
            }

            # Character limit of 50 in parm file for DASD parameter
            if (length($dasd) > 50) {
                @words = split(',', $dasd);
                $dasd = $words[0] . "-" . $words[ @words - 1 ];
            }

            # Get dedicated virtual address
            my @dedicates = xCAT::zvmUtils->getDedicates($callback, $::SUDOER, $node);
            if (xCAT::zvmUtils->checkOutput($dedicates[0]) == -1) {
                xCAT::zvmUtils->printLn($callback, "$dedicates[0]");
                return;
            }
            @dedicates = sort(@dedicates);
            $i         = 0;
            foreach (@dedicates) {
                $i = $i + 1;
                @words = split(' ', $_);

                # Do not put a comma at the end of the last disk address
                if ($i == @dedicates) {
                    $devices = $devices . "0.0.$words[1]";
                } else {
                    $devices = $devices . "0.0.$words[1],";
                }
            }

            # Character limit of 50 in parm file for DASD parameter
            if (length($devices) > 50) {
                @words = split(',', $devices);
                $devices = $words[0] . "-" . $words[ @words - 1 ];
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
            $parms = $parms . "DASD=$dasd NETTYPE=$netType IPADDR=$hostIP\n";
            $parms = $parms . "HOSTNAME=$hostname\n";
            $parms = $parms . "SUBCHANNELS=$readChannel,$writeChannel,$dataChannel\n";
            $parms = $parms . "NETWORK=$network NETMASK=$mask\n";
            $parms = $parms . "SEARCHDNS=$domain BROADCAST=$broadcast\n";
            $parms = $parms . "GATEWAY=$gateway DNS=$nameserver MTU=1500\n";

            # Set layer in kickstart profile
            if ($layer == 2) {
                $parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=1 MACADDR=$mac\n";
            } else {
                $parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=0\n";
            }

            $parms = $parms . "vnc vncpassword=12345678\n";

            xCAT::zvmUtils->printSyslog("***Parm file RedHat(should be max 80 cols, 11 lines:\n$parms");

            # Write to parmfile
            $parmFile = "/tmp/" . $node . "Parm";
            open(PARMFILE, ">$parmFile");
            print PARMFILE "$parms";
            close(PARMFILE);

            # Send kernel, parmfile, conf, and initrd to reader to HCP
            $kernelFile = "/tmp/" . $node . "Kernel";
            $initFile   = "/tmp/" . $node . "Initrd";

            # Copy over kernel, parmfile, conf, and initrd from remote repository
            if ($repo) {
                $out = `/usr/bin/wget $repo/images/kernel.img -O $kernelFile --no-check-certificate`;
                xCAT::zvmUtils->printLn($callback, "Attempting to copy $repo/images/kernel.img to $kernelFile");
                $out = `/usr/bin/wget $repo/images/initrd.img -O $initFile --no-check-certificate`;
            } else {
                $out = `cp $installDir/$os/s390x/images/kernel.img $kernelFile`;
                xCAT::zvmUtils->printLn($callback, "Attempting to copy $installDir/$os/s390x/images/kernel.img to $kernelFile");
                $out = `cp $installDir/$os/s390x/images/initrd.img $initFile`;
            }
            $out = `ls $kernelFile 2>1`;
            $rc  = $? >> 8;
            if ($rc) {
                xCAT::zvmUtils->printLn($callback, "(Failed) Did not copy the file. Did you forget to process the ISO?");
                $out = '(Failed) Did not copy the file.';
                return;
            }

            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $kernelFile, $kernelFile);
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $parmFile,   $parmFile);
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $initFile,   $initFile);

            # Set the virtual unit record devices online
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "c");
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "d");

            # Purge reader
            $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
            xCAT::zvmUtils->printLn($callback, "$node: Purging reader... Done");

            # Punch kernel to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $kernelFile, "rhel.kernel", "", "");
            xCAT::zvmUtils->printLn($callback, "$node: Punching kernel to reader... $out");
            if ($out =~ m/Failed/i) {
                return;
            }

            # Punch parm to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $parmFile, "rhel.parm", "-t", "");
            xCAT::zvmUtils->printLn($callback, "$node: Punching parm to reader... $out");
            if ($out =~ m/Failed/i) {
                return;
            }

            # Punch initrd to reader on HCP
            $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $initFile, "rhel.initrd", "", "");
            xCAT::zvmUtils->printLn($callback, "$node: Punching initrd to reader... $out");
            if ($out =~ m/Failed/i) {
                return;
            }

            # Remove kernel, parmfile, and initrd from /tmp
            $out = `rm $parmFile $kernelFile $initFile`;
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $parmFile $kernelFile $initFile"`;

            xCAT::zvmUtils->printLn($callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot.");
        }
    } elsif ($action eq "statelite") {

        # Get node group from 'nodelist' table
        @propNames = ('groups');
        $propVals = xCAT::zvmUtils->getTabPropsByKey('nodelist', 'node', $node, @propNames);
        my $group = $propVals->{'groups'};

        # Get node statemnt (statelite mount point) from 'statelite' table
        @propNames = ('statemnt');
        $propVals = xCAT::zvmUtils->getTabPropsByKey('statelite', 'node', $node, @propNames);
        my $stateMnt = $propVals->{'statemnt'};
        if (!$stateMnt) {
            $propVals = xCAT::zvmUtils->getTabPropsByKey('statelite', 'node', $group, @propNames);
            $stateMnt = $propVals->{'statemnt'};

            if (!$stateMnt) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node statemnt in statelite table. Please specify one.");
                return;
            }
        }

        # Netboot directory
        my $netbootDir = "$installDir/netboot/$os/$arch/$profile";
        my $kernelFile = "$netbootDir/kernel";
        my $parmFile   = "$netbootDir/parm-statelite";
        my $initFile   = "$netbootDir/initrd-statelite.gz";

        # If parmfile exists
        if (-e $parmFile) {

            # Do nothing
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: Creating parmfile");

            my $sampleParm;
            my $parmHeader;
            my $parms;
            if ($os =~ m/sles/i) {
                if (-e "$installDir/$os/s390x/1/boot/s390x/parmfile") {

                    # Read sample parmfile in /install/sles11.1/s390x/1/boot/s390x/
                    $sampleParm = "$installDir/$os/s390x/1/boot/s390x/parmfile";
                } else {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing $installDir/$os/s390x/1/boot/s390x/parmfile");
                    return;
                }
            } elsif ($os =~ m/rhel/i) {
                if (-e "$installDir/$os/s390x/images/generic.prm") {

                    # Read sample parmfile in /install/rhel5.3/s390x/images
                    $sampleParm = "$installDir/$os/s390x/images/generic.prm";
                } else {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing $installDir/$os/s390x/images/generic.prm");
                    return;
                }
            }

            open(SAMPLEPARM, "<$sampleParm");

            # Search parmfile for -- ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
            while (<SAMPLEPARM>) {

                # If the line contains 'ramdisk_size'
                if ($_ =~ m/ramdisk_size/i) {
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
            open(PARMFILE, ">$parmFile");
            print PARMFILE "$parms";
            close(PARMFILE);
        }

        # Temporary kernel, parmfile, and initrd
        my $tmpKernelFile = "/tmp/$os-kernel";
        my $tmpParmFile   = "/tmp/$os-parm-statelite";
        my $tmpInitFile   = "/tmp/$os-initrd-statelite.gz";

        xCAT::zvmUtils->printLn($callback, "$node: Looking for kernel $os-kernel.");
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO ls /tmp"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh -o ConnectTimeout=5 $::SUDOER\@$hcp \"$::SUDO ls /tmp\"", $hcp, "nodeSet", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        if (`echo "$out" | egrep -a -i "$os-kernel"`) {

            # Do nothing
        } else {

            # Send kernel to reader to HCP
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $kernelFile, $tmpKernelFile);
            xCAT::zvmUtils->printLn($callback, "sendfile $kernelFile, $tmpKernelFile");
        }

        if (`echo "$out" | egrep -a -i "$"os-parm-statelite"`) {

            # Do nothing
        } else {

            # Send parmfile to reader to HCP
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $parmFile, $tmpParmFile);
        }

        if (`echo "$out" | egrep -a -i "$os-initrd-statelite.gz"`) {

            # Do nothing
        } else {

            # Send initrd to reader to HCP
            xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $initFile, $tmpInitFile);
        }

        # Set the virtual unit record devices online
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "c");
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", "d");

        # Purge reader
        $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
        xCAT::zvmUtils->printLn($callback, "$node: Purging reader... Done");

        # Kernel, parm, and initrd are in /install/netboot/<os>/<arch>/<profile>
        # Punch kernel to reader on HCP
        $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $tmpKernelFile, "sles.kernel", "", "");
        xCAT::zvmUtils->printLn($callback, "$node: Punching kernel to reader... $out");
        if ($out =~ m/Failed/i) {
            return;
        }

        # Punch parm to reader on HCP
        $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $tmpParmFile, "sles.parm", "-t", "");
        xCAT::zvmUtils->printLn($callback, "$node: Punching parm to reader... $out");
        if ($out =~ m/Failed/i) {
            return;
        }

        # Punch initrd to reader on HCP
        $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $tmpInitFile, "sles.initrd", "", "");
        xCAT::zvmUtils->printLn($callback, "$node: Punching initrd to reader... $out");
        if ($out =~ m/Failed/i) {
            return;
        }

        xCAT::zvmUtils->printLn($callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot.");
    } elsif (($action eq "netboot") || ($action eq "sysclone")) {

        # Obtain the location of the install root directory
        my $installRoot = xCAT::TableUtils->getInstallDir();

        # Verify the image exists
        my $deployImgDir = "$installRoot/$action/$os/$arch/$profile";
        my @imageFiles   = glob "$deployImgDir/*.img";
        my %imageFileList;
        if (@imageFiles == 0) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) $deployImgDir does not contain image files");
            return;
        } else {

            # Obtain the list of image files and the vaddr to which they relate
            foreach my $imageFileFull (@imageFiles) {
                my $imageFile = (split('/',  $imageFileFull))[-1];
                my $vaddr     = (split('\.', $imageFile))[0];
                $imageFileList{$vaddr} = $imageFile;
            }
        }

        # Build the list of image files and their target device addresses
        if ($action eq "netboot") {
            if (@imageFiles > 1) {

                # Can only have one image file for netboot
                xCAT::zvmUtils->printLn($callback, "$node: (Error) $deployImgDir contains more than the expected number of image files");
                return;
            }
            if (!defined $device) {

                # A device must be specified
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Image device was not specified");
                return;
            }

            # For netboot, image device address is not necessarily the same as the original device name
            my $origKey = (keys %imageFileList)[0];
            if ($origKey ne $device) {

                # file name was different with a different name than the target device.  Update to use the target device.
                $imageFileList{$device} = $imageFileList{$origKey};
                delete $imageFileList{$origKey};
            }
        } else {

            # Handle sysclone which can have multiple image files which MUST match each mdisk
            # Get the list of mdisks
            my @srcDisks = xCAT::zvmUtils->getMdisks($callback, $::SUDOER, $node);
            if (xCAT::zvmUtils->checkOutput($srcDisks[0]) == -1) {
                xCAT::zvmUtils->printLn($callback, "$srcDisks[0]");
                return;
            }

            # Verify the list of images and matching disks
            my $validArrayDisks = 0;
            foreach (@srcDisks) {

                # Get disk address
                my @words    = split(' ', $_);
                my $vaddr    = $words[1];
                my $diskType = $words[2];

                if ($diskType eq 'FB-512') {

                    # We do not do not deploy into vdisks
                    next;
                }

                # Add 0 in front if address length is less than 4
                while (length($vaddr) < 4) {
                    $vaddr = '0' . $vaddr;
                }

                if (defined $imageFileList{$vaddr}) {

                    # We only count disks that have an image file.
                    $validArrayDisks = $validArrayDisks + 1;
                }
            }
            if ($validArrayDisks != @imageFiles) {

                # Number of mdisks does not match the number of image files
                xCAT::zvmUtils->printLn($callback, "$node: (Error) $deployImgDir contains images for devices that do not exist.");
                return;
            }
        }

        # Ensure the staging directory exists in case we need to create subdirectories in it.
        if (!-d "$installRoot/staging") {
            mkpath("$installRoot/staging");
        }

        # Prepare the deployable mount point on zHCP, if it needs to be established.
        my $remoteDeployDir;
        my $rc = xCAT::zvmUtils->establishMount($callback, $::SUDOER, $::SUDO, $hcp, $installRoot, $action, "ro", \$remoteDeployDir);
        if ($rc) {

            # Mount failed
            return;
        }

        # Drive each device deploy separately.  Up to 10 at a time.
        # Each deploy request to zHCP is driven from a child process.
        # Process ID for xfork()
        my $pid;

        # Child process IDs
        my @children;

        # Make a temporary directory in case a process needs to communicate a problem.
        my $statusDir = mkdtemp("$installRoot/staging/status.$$.XXXXXX");

        xCAT::zvmUtils->printLn($callback, "$node: Deploying the image using the zHCP node");
        my $reason;
        for my $vaddr (keys %imageFileList) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push(@children, $pid);
            }

            # Child process.
            elsif ($pid == 0) {

                # Drive the deploy on the zHCP node
                # Copy the image to the target disk using the zHCP node
                xCAT::zvmUtils->printSyslog("nodeset() unpackdiskimage $userId $vaddr $remoteDeployDir/$os/$arch/$profile/$imageFileList{$vaddr}");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/unpackdiskimage $userId $vaddr $remoteDeployDir/$os/$arch/$profile/$imageFileList{$vaddr}"`;
                $rc = $?;

                # Check for script errors
                my $reasonString = "";
                $rc = xCAT::zvmUtils->checkOutputExtractReason($out, \$reasonString);
                if ($rc != 0) {
                    $reason = "Reason: $reasonString";
                    xCAT::zvmUtils->printSyslog("nodeset() unpackdiskimage of $userId $vaddr failed. $reason");
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to deploy the image to $userId $vaddr. $reason");

                    # Create a "FAILED" file to indicate the failure.
                    if (!open FILE, '>' . "$statusDir/FAILED") {

                        # if we can't open it then we log the problem.
                        xCAT::zvmUtils->printSyslog("nodeset() unable to create a 'FAILED' file.");
                    }
                }

                # Exit the child process
                exit(0);
            }

            else {
                # Ran out of resources
                # Create a "FAILED" file to indicate the failure.
                if (!open FILE, '>' . "$statusDir/FAILED") {

                    # if we can't open it then we log the problem.
                    xCAT::zvmUtils->printSyslog("nodeset() unable to create a 'FAILED' file.");
                }

                $reason = "Reason: Could not fork\n";
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to deploy the image to $userId $vaddr. $reason");
                last;
            }

            # Handle 10 nodes at a time, else you will get errors
            if (!(@children % 10)) {

                # Wait for all processes to end
                foreach (@children) {
                    waitpid($_, 0);
                }

                # Clear children
                @children = ();
            }
        }    # End of foreach

        # If any children remain, then wait for them to complete.
        foreach $pid (@children) {
            xCAT::zvmUtils->printSyslog("nodeset() Waiting for child process $pid to complete");
            waitpid($pid, 0);
        }

        # If the deploy failed then clean up and return
        if (-e "$statusDir/FAILED") {

            # Failure occurred in one of the child processes.  A message was already generated.
            rmtree "$statusDir";
            return;
        }
        rmtree "$statusDir";

        # If the transport file was specified then setup the transport disk.
        if ($transport) {
            my $transImgDir = "$installRoot/staging/transport";
            if (!-d $transImgDir) {
                mkpath($transImgDir);
            }

            # Create unique transport directory and copy the transport file to it
            my $transportDir = `/bin/mktemp -d $installDir/staging/transport/XXXXXX`;
            chomp($transportDir);
            if ($remoteHost) {

                # Copy the transport file from the remote system to the local transport directory.
                xCAT::zvmUtils->printLn($callback, "/usr/bin/scp -B $remoteHost:$transport $transportDir");
                $out = `/usr/bin/scp -v -B $remoteHost:$transport $transportDir`;
                $rc = $?;
            } else {

                # Safely copy the transport file from a local directory.
                $out = `/bin/cp $transport $transportDir`;
                $rc  = $?;
            }

            if ($rc != 0) {

                # Copy failed  Get rid of the unique directory that was going to receive the copy.
                rmtree $transportDir;
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to copy the transport file");
                return;
            }

            # Check the zvm table to see if the node flag "XCATCONF4Z=0" is set or not in status column,
            # if set put it to a temp dir for later use, otherwise punched the transport file directly to node's reader,
            my $nodeFlag    = '';
            my $cfgTrunkDir = "/tmp/configdrive/$node/";
            my @propNames   = ('status');
            my $propVals = xCAT::zvmUtils->getTabPropsByKey('zvm', 'node', $node, @propNames);
            $nodeFlag = $propVals->{'status'};
            if ($nodeFlag =~ /XCATCONF4Z=0/) {
                if (!-d $cfgTrunkDir) {
                    mkpath($cfgTrunkDir, 0, 0750);
                }
                $rc = `/bin/cp -r $transportDir/* $cfgTrunkDir/ 2>/dev/null; echo $?`;
                `rm -rf $transportDir`;
                if ($rc != '0') {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy over source directory $transportDir to directory $cfgTrunkDir with rc: $rc, please check if xCAT is running out of space");
                    `rm -rf $cfgTrunkDir`;
                    return;
                }

            } else {

                # Purge the target node's reader
                $out = xCAT::zvmCPUtils->purgeReader($::SUDOER, $hcp, $userId);
                xCAT::zvmUtils->printLn($callback, "$node: Purging reader... Done");

                # Online zHCP's punch device
                $out = xCAT::zvmUtils->onlineZhcpPunch($::SUDOER, $hcp);
                if ($out =~ m/Failed/i) {
                    xCAT::zvmUtils->printLn($callback, "$node: Online zHCP's punch device... $out");
                    return;
                }

                # Punch files to node's reader so it could be pulled on boot
                # Reader = transport disk
                my @files = glob "$transportDir/*";
                foreach (@files) {
                    my $file     = basename($_);
                    my $filePath = "/tmp/$node-" . $file;

                    # Spool file only accepts [A-Za-z] and file name can only be 8-characters long
                    my @filePortions = split('\.', $file);
                    if ((@filePortions > 2) ||
                        ($filePortions[0] =~ m/[^a-zA-Z0-9]/) || (length($filePortions[0]) > 8) || (length($filePortions[0]) < 1) ||
                        ($filePortions[1] =~ m/[^a-zA-Z0-9]{1,8}/) || (length($filePortions[1]) > 8)) {
                        $out = `/bin/rm -rf $transportDir`;
                        xCAT::zvmUtils->printLn($callback, "$node: (Error) $file contains a file name or file type portion that is longer than 8 characters, or not alphanumeric ");
                        return;
                    }

                    xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $_, $filePath);

                    my $punchOpt = "";
                    if ($file =~ /.txt/ || $file =~ /.sh/) {
                        $punchOpt = "-t";
                    }
                    $out = xCAT::zvmCPUtils->punch2Reader($::SUDOER, $hcp, $userId, $filePath, "$file", $punchOpt, "X");

                    # Clean up file
                    `ssh $::SUDOER\@$hcp "$::SUDO /bin/rm $filePath"`;
                    xCAT::zvmUtils->printLn($callback, "$node: Punching $file to reader... $out");
                    if ($out =~ m/Failed/i) {

                        # Clean up transport directory.  Message was already generated.
                        $out = `/bin/rm -rf $transportDir`;
                        return;
                    }
                }
            }

            # Clean up transport directory
            $out = `/bin/rm -rf $transportDir`;
            xCAT::zvmUtils->printLn($callback, "$node: Completed deploying image($os-$arch-$action-$profile)");
        }

    } else {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Option not supported");
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
    Returns     : Nothing, errors returned in $callback
    Example     : getMacs($callback, $node, $args);

=cut

#-------------------------------------------------------
sub getMacs {

    # Get inputs
    my ($callback, $node, $args) = @_;
    my $force = '';
    if ($args) {
        @ARGV = @$args;

        # Parse options
        GetOptions('f' => \$force);
    }

    my $out;
    my $outmsg;
    my $rc;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    # Get MAC address in 'mac' table
    @propNames = ('mac');
    $propVals = xCAT::zvmUtils->getNodeProps('mac', $node, @propNames);
    my $mac;
    if ($propVals->{'mac'} && !$force) {

        # Get MAC address
        $mac = $propVals->{'mac'};
        xCAT::zvmUtils->printLn($callback, "$node: $mac");
        return;
    }

    # If MAC address is not in the 'mac' table, get it using VMCP
    xCAT::zvmCPUtils->loadVmcp($::SUDOER, $node);

    # Get xCat MN Lan/VSwitch name
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp q v nic"`;
    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh -o ConnectTimeout=5 $::SUDOER\@$hcp \"$::SUDO /sbin/vmcp q v nic\"", $hcp, "getMacs", $out, $node);
    if ($rc != 0) {
        xCAT::zvmUtils->printLn($callback, "$outmsg");
        return;
    }
    $out = `echo "$out" | egrep -a -i "VSWITCH|LAN"`;
    my @lines = split('\n', $out);
    my @words;

    # Go through each line and extract VSwitch and Lan names
    # and create search string
    my $searchStr = "";
    my $i;
    for ($i = 0 ; $i < @lines ; $i++) {

        # Extract VSwitch name
        if ($lines[$i] =~ m/VSWITCH/i) {
            @words = split(' ', $lines[$i]);
            $searchStr = $searchStr . "$words[4]";
        }

        # Extract Lan name
        elsif ($lines[$i] =~ m/LAN/i) {
            @words = split(' ', $lines[$i]);
            $searchStr = $searchStr . "$words[4]";
        }

        if ($i != (@lines - 1)) {
            $searchStr = $searchStr . "|";
        }
    }

    # Get MAC address of node
    # This node should be on only 1 of the networks that the xCAT MN is on
    #$out = `ssh -o ConnectTimeout=5 $::SUDOER\@$node "/sbin/vmcp q v nic" | egrep -a -i "$searchStr"`;
    my $cmd = $::SUDO . ' /sbin/vmcp q v nic | egrep -a -i "' . $searchStr . '"';
    $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        return;
    }

    if (!$out) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find MAC address");
        return;
    }

    @lines = split('\n', $out);
    @words = split(' ',  $lines[0]);
    $mac   = $words[1];

    # Replace - with :
    $mac = xCAT::zvmUtils->replaceStr($mac, "-", ":");
    xCAT::zvmUtils->printLn($callback, "$node: $mac");

    # Save MAC address and network interface into 'mac' table
    xCAT::zvmUtils->setNodeProp('mac', $node, 'mac', $mac);

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
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Get IPL
    my @ipl = split('=', $args->[0]);
    if (!($ipl[0] eq "ipl")) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing IPL");
        return;
    }

    # Boot node
    my $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Activate -T $userId"`;
    xCAT::zvmUtils->printSyslog("smcli Image_Activate -T $userId");
    xCAT::zvmUtils->printSyslog("$out");

    # IPL when virtual server is online
    sleep(5);
    $out = xCAT::zvmCPUtils->sendCPCmd($::SUDOER, $hcp, $userId, "IPL $ipl[1]");
    xCAT::zvmUtils->printSyslog("IPL $ipl[1]");
    xCAT::zvmUtils->printSyslog("$out");
    xCAT::zvmUtils->printLn($callback, "$node: Booting from $ipl[1]... Done");

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
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    # Get install directory
    my @entries    = xCAT::TableUtils->get_site_attribute("installdir");
    my $installDir = $entries[0];

    # Get host IP and hostname from /etc/hosts
    my $out      = `cat /etc/hosts | egrep -a -i "$node |$node."`;
    my @words    = split(' ', $out);
    my $hostIP   = $words[0];
    my $hostname = $words[2];
    if (!($hostname =~ m/./i)) {
        $hostname = $words[1];
    }

    if (!$hostIP || !$hostname) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing IP for $node in /etc/hosts");
        xCAT::zvmUtils->printLn($callback, "$node: (Solution) Verify that the node's IP address is specified in the hosts table and then run makehosts");
        return;
    }

    # Get first 3 octets of node IP (IPv4)
    @words = split(/\./, $hostIP);
    my $octets = "$words[0].$words[1].$words[2]";

    # Get networks in 'networks' table
    my $entries = xCAT::zvmUtils->getAllTabEntries('networks');

    # Go through each network
    my $network;
    foreach (@$entries) {

        # Get network
        $network = $_->{'net'};

        # If networks contains the first 3 octets of the node IP
        if ($network =~ m/$octets/i) {

            # Exit loop
            last;
        } else {
            $network = "";
        }
    }

    # If no network found
    if (!$network) {

        # Exit
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Node does not belong to any network in the networks table");
        xCAT::zvmUtils->printLn($callback, "$node: (Solution) Specify the subnet in the networks table. The mask, gateway, tftpserver, and nameservers must be specified for the subnet.");
        return;
    }

    # Get FTP server
    @propNames = ('tftpserver');
    $propVals = xCAT::zvmUtils->getTabPropsByKey('networks', 'net', $network, @propNames);
    my $nfs = $propVals->{'tftpserver'};
    if (!$nfs) {

        # It is acceptable to not have a gateway
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing FTP server");
        xCAT::zvmUtils->printLn($callback, "$node: (Solution) Specify the tftpserver for the subnet in the networks table");
        return;
    }

    # Update node operating system
    if ($args->[0] eq "--release") {
        my $version = $args->[1];

        if (!$version) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing operating system release. Please specify one.");
            return;
        }

        # Get node operating system
        my $os = xCAT::zvmUtils->getOs($::SUDOER, $node);

        # Check node OS is the same as the version OS given
        # You do not want to update a SLES with a RHEL
        if ((($os =~ m/SUSE/i) && !($version =~ m/sles/i)) || (($os =~ m/Red Hat/i) && !($version =~ m/rhel/i))) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Node operating system is different from the operating system given to upgrade to. Please correct.");
            return;
        }

        # Generate FTP path to operating system image
        my $path;
        if ($version =~ m/sles/i) {

            # The following only applies to SLES 10
            # SLES 11 requires zypper

            # SuSE Enterprise Linux path - ftp://10.0.0.1/sles10.3/s390x/1/
            $path = "http://$nfs/install/$version/s390x/1/";

            # Add installation source using rug
            #$out = `ssh $::SUDOER\@$node "rug sa -t zypp $path $version"`;
            my $cmd = "$::SUDO rug sa -t zypp $path $version";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            xCAT::zvmUtils->printLn($callback, "$node: $out");

            # Subscribe to catalog
            #$out = `ssh $::SUDOER\@$node "rug sub $version"`;
            $cmd = "$::SUDO rug sub $version";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            xCAT::zvmUtils->printLn($callback, "$node: $out");

            # Refresh services
            #$out = `ssh $::SUDOER\@$node "rug ref"`;
            $cmd = "$::SUDO rug ref";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            xCAT::zvmUtils->printLn($callback, "$node: $out");

            # Update
            #$out = `ssh $::SUDOER\@$node "rug up -y"`;
            $cmd = "$::SUDO rug up -y";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            xCAT::zvmUtils->printLn($callback, "$node: $out");
        } else {

            # Red Hat Enterprise Linux path - ftp://10.0.0.1/rhel5.4/s390x/Server/
            $path = "http://$nfs/install/$version/s390x/Server/";

            # Check if file.repo already has this repository location
            #$out = `ssh $::SUDOER\@$node "cat /etc/yum.repos.d/file.repo"`;
            my $cmd = "$::SUDO cat /etc/yum.repos.d/file.repo";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            if ($out =~ m/[$version]/i) {

                # Send over release key
                my $key = "$installDir/$version/s390x/RPM-GPG-KEY-redhat-release";
                my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
                xCAT::zvmUtils->sendFile($::SUDOER, $node, $key, $tmp);

                # Import key
                #$out = `ssh $::SUDOER\@$node "rpm --import /tmp/$key"`;
                $cmd = "$::SUDO rpm --import /tmp/$key";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    return;
                }


                # Upgrade
                #$out = `ssh $::SUDOER\@$node "yum upgrade -y"`;
                $cmd = "$::SUDO yum upgrade -y";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    return;
                }

                xCAT::zvmUtils->printLn($callback, "$node: $out");
            } else {

                # Create repository
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo [$version] >> /etc/yum.repos.d/file.repo");
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo baseurl=$path >> /etc/yum.repos.d/file.repo");
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $node, "echo enabled=1 >> /etc/yum.repos.d/file.repo");

                # Send over release key
                my $key = "$installDir/$version/s390x/RPM-GPG-KEY-redhat-release";
                my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
                xCAT::zvmUtils->sendFile($::SUDOER, $node, $key, $tmp);

                # Import key
                #$out = `ssh $::SUDOER\@$node "rpm --import $tmp"`;
                my $cmd = "$::SUDO rpm --import $tmp";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    return;
                }


                # Upgrade
                #$out = `ssh $::SUDOER\@$node "yum upgrade -y"`;
                $cmd = "$::SUDO yum upgrade -y";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    return;
                }

                xCAT::zvmUtils->printLn($callback, "$node: $out");
            }
        }
    }

    # Otherwise, print out error
    else {
        $out = "$node: (Error) Option not supported";
    }

    xCAT::zvmUtils->printLn($callback, "$out");
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
    my ($callback, $nodes, $args) = @_;
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
    my $tab = xCAT::Table->new('zvm', -create => 1, -autocommit => 0);

    # Get CEC entries
    # There should be few of these nodes
    my @entries = $tab->getAllAttribsWhere("nodetype = 'cec'", 'node', 'parent');
    foreach (@entries) {
        $node = $_->{'node'};

        # Make CEC the tree root
        $tree{$node} = {};
    }

    # Get LPAR entries
    # There should be a couple of these nodes
    @entries = $tab->getAllAttribsWhere("nodetype = 'lpar'", 'node', 'parent');
    foreach (@entries) {
        $node   = $_->{'node'};      # LPAR
        $parent = $_->{'parent'};    # CEC

        # Add LPAR branch
        $tree{$parent}{$node} = {};
    }

    # Get zVM entries
    # There should be a couple of these nodes
    $found = 0;
    @entries = $tab->getAllAttribsWhere("nodetype = 'zvm'", 'node', 'hcp', 'parent');
    foreach (@entries) {
        $node   = $_->{'node'};      # zVM
        $hcp    = $_->{'hcp'};       # zHCP
        $parent = $_->{'parent'};    # LPAR

        # Find out if this z/VM belongs to an SSI cluster
        $ssi{$node} = xCAT::zvmUtils->querySSI($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($ssi{$node}) == -1) {
            xCAT::zvmUtils->printLn($callback, "$ssi{$node}");
            return;
        }

        # Find CEC root based on LPAR
        # CEC -> LPAR
        $found = 0;
        foreach my $cec (sort keys %tree) {
            foreach my $lpar (sort keys %{ $tree{$cec} }) {
                if ($lpar eq $parent) {

                    # Add LPAR branch
                    $tree{$cec}{$parent}{$node} = {};
                    $found = 1;
                    last;
                }

                # Handle second level zVM
                foreach my $vm (sort keys %{ $tree{$cec}{$lpar} }) {
                    if ($vm eq $parent) {

                        # Add VM branch
                        $tree{$cec}{$lpar}{$parent}{$node} = {};
                        $found = 1;
                        last;
                    }
                }    # End of foreach zVM
            }    # End of foreach LPAR

            # Exit loop if LPAR branch added
            if ($found) {
                last;
            }
        }    # End of foreach CEC
    }

    # Get VM entries
    # There should be many of these nodes
    $found = 0;
    @entries = $tab->getAllAttribsWhere("nodetype = 'vm'", 'node', 'parent', 'userid');
    foreach (@entries) {
        $node   = $_->{'node'};      # VM
        $parent = $_->{'parent'};    # zVM

        # Skip node if it is not in noderange
        if (!xCAT::zvmUtils->inArray($node, @nodes)) {
            next;
        }

        # Find CEC/LPAR root based on zVM
        # CEC -> LPAR -> zVM
        $found = 0;
        foreach my $cec (sort keys %tree) {
            foreach my $lpar (sort keys %{ $tree{$cec} }) {
                foreach my $zvm (sort keys %{ $tree{$cec}{$lpar} }) {
                    if ($zvm eq $parent) {

                        # Add zVM branch
                        $tree{$cec}{$lpar}{$parent}{$node} = $_->{'userid'};
                        $found = 1;
                        last;
                    }

                    # Handle second level zVM
                    foreach my $vm (sort keys %{ $tree{$cec}{$lpar}{$zvm} }) {
                        if ($vm eq $parent) {

                            # Add VM branch
                            $tree{$cec}{$lpar}{$zvm}{$parent}{$node} = $_->{'userid'};
                            $found = 1;
                            last;
                        }
                    }    # End of foreach VM
                }    # End of foreach zVM

                # Exit loop if zVM branch added
                if ($found) {
                    last;
                }
            }    # End of foreach LPAR

            # Exit loop if zVM branch added
            if ($found) {
                last;
            }
        }    # End of foreach CEC
    }    # End of foreach VM node

    # Print tree
    # Loop through CECs
    foreach my $cec (sort keys %tree) {
        xCAT::zvmUtils->printLn($callback, "CEC: $cec");

        # Loop through LPARs
        foreach my $lpar (sort keys %{ $tree{$cec} }) {
            xCAT::zvmUtils->printLn($callback, "|__LPAR: $lpar");

            # Loop through zVMs
            foreach my $zvm (sort keys %{ $tree{$cec}{$lpar} }) {
                if ($ssi{$zvm}) {
                    xCAT::zvmUtils->printLn($callback, "   |__zVM: $zvm ($ssi{$zvm})");
                } else {
                    xCAT::zvmUtils->printLn($callback, "   |__zVM: $zvm");
                }

                # Loop through VMs
                foreach my $vm (sort keys %{ $tree{$cec}{$lpar}{$zvm} }) {

                    # Handle second level zVM
                    if (ref($tree{$cec}{$lpar}{$zvm}{$vm}) eq 'HASH') {
                        if ($ssi{$zvm}) {
                            xCAT::zvmUtils->printLn($callback, "      |__zVM: $vm ($ssi{$zvm})");
                        } else {
                            xCAT::zvmUtils->printLn($callback, "      |__zVM: $vm");
                        }

                        foreach my $vm2 (sort keys %{ $tree{$cec}{$lpar}{$zvm}{$vm} }) {
                            xCAT::zvmUtils->printLn($callback, "         |__VM: $vm2 ($tree{$cec}{$lpar}{$zvm}{$vm}{$vm2})");
                        }
                    } else {
                        xCAT::zvmUtils->printLn($callback, "      |__VM: $vm ($tree{$cec}{$lpar}{$zvm}{$vm})");
                    }
                }    # End of foreach VM
            }    # End of foreach zVM
        }    # End of foreach LPAR
    }    # End of foreach CEC
    return;
}

#-------------------------------------------------------

=head3   changeHypervisor

    Description : Configure the virtualization hosts
    Arguments   :   Node
                    Arguments
    Returns     : Nothing, errors returned in $callback
    Example     : changeHypervisor($callback, $node, $args);

=cut

#-------------------------------------------------------
sub changeHypervisor {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get zHCP shortname because $hcp could be zhcp.endicott.ibm.com
    my $hcpNode = $hcp;
    if ($hcp =~ /./) {
        my @tmp = split(/\./, $hcp);
        $hcpNode = $tmp[0];    # Short hostname of zHCP
    }

    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Output string
    my $out = "";
    my $outmsg;
    my $rc;

    # adddisk2pool [function] [region] [volume] [group]
    if ($args->[0] eq "--adddisk2pool") {
        my $funct  = $args->[1];
        my $region = $args->[2];
        my $volume = "";
        my $group  = "";

        # Create an array for regions
        my @regions;
        if ($region =~ m/,/i) {
            @regions = split(',', $region);
        } else {
            push(@regions, $region);
        }

        my $tmp;
        foreach (@regions) {
            if (!(length $_)) { next; }
            $_ = xCAT::zvmUtils->trimStr($_);

            # Define region as full volume and add to group
            if ($funct eq "4") {
                $volume = $args->[3];

                # In case multiple regions/volumes are specified, just use the same name
                if (scalar(@regions) > 1) {
                    $volume = $_;
                }

                $group = $args->[4];
                $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -v $volume -p $group -y 0"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -v $volume -p $group -y 0");
            }

            # Add existing region to group
            elsif ($funct eq "5") {
                $group = $args->[3];
                $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -p $group -y 0"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Define_DM -T $hcpUserId -f $funct -g $_ -p $group -y 0");
            }

            $out .= $tmp;
        }
    }

    # addvolume [dev_no] [volser]
    elsif ($args->[0] eq "--addvolume") {
        my $argsSize = @{$args};
        if ($argsSize != 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo  = $args->[1];
        my $volser = $args->[2];

        # Add a DASD volume to the z/VM system configuration
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Add -T $hcpUserId -v $devNo -l $volser"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Volume_Add -T $hcpUserId -v $devNo -l $volser");
    }

    # removevolume [dev_no] [volser]
    elsif ($args->[0] eq "--removevolume") {
        my $argsSize = @{$args};
        if ($argsSize != 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo  = $args->[1];
        my $volser = $args->[2];

        # Remove a DASD volume from the z/VM system configuration
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Delete -T $hcpUserId -v $devNo -l $volser"`;
        xCAT::zvmUtils->printSyslog("smcli Image_Volume_Delete -T $hcpUserId -v $devNo -l $volser");
    }

    # addeckd [dev_no]
    elsif ($args->[0] eq "--addeckd") {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo = "dev_num=" . $args->[1];

        # Add an ECKD disk to a running z/VM system
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Add -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_Disk_Add -T $hcpUserId -k $devNo");
    }

    # addscsi [dev_no] [dev_path] [option] [persist]
    elsif ($args->[0] eq "--addscsi") {

        # Sample command would look like: chhypervisor zvm62 --addscsi 12A3 "1,0x123,0x100;2,0x123,0x101" 1 NO
        my $argsSize = @{$args};
        if ($argsSize < 3 && $argsSize > 5) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Option can be: (1) Add new SCSI (default), (2) Add new path, or (3) Delete path
        if ($args->[3] != 1 && $args->[3] != 2 && $args->[3] != 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Options can be one of the following:\n  (1) Add new SCSI disk (default)\n  (2) Add new path to existing disk\n  (3) Delete path from existing disk");
            return;
        }

        # Persist can be: (YES) SCSI device updated in active and configured system, or (NO) SCSI device updated only in active system
        if ($argsSize > 3 && $args->[4] ne "YES" && $args->[4] ne "NO") {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Persist can be one of the following:\n  (YES) SCSI device updated in active and configured system\n  (NO) SCSI device updated only in active system");
            return;
        }

        my $devNo = "dev_num=" . $args->[1];

        # Device path array, each device separated by semi-colon
        # e.g. fcp_devno1 fcp_wwpn1 fcp_lun1; fcp_devno2 fcp_wwpn2 fcp_lun2;
        my @fcps;
        if ($args->[2] =~ m/;/i) {
            @fcps = split(';', $args->[2]);
        } else {
            push(@fcps, $args->[2]);
        }

        # Append the correct prefix
        my @fields;
        my $pathStr = "";
        foreach (@fcps) {
            @fields = split(',', $_);
            $pathStr .= "$fields[0] $fields[1] $fields[2];";
        }


        my $devPath = "dev_path_array='" . $pathStr . "'";

        my $option  = "option=" . $args->[3];
        my $persist = "persist=" . $args->[4];

        # Add disk to running system
        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_SCSI_Disk_Add -T $hcpUserId -k $devNo -k $devPath -k $option -k $persist"`;
        xCAT::zvmUtils->printSyslog("smcli System_SCSI_Disk_Add -T $hcpUserId -k $devNo -k $devPath -k $option -k $persist");
    }

    # addvlan [name] [owner] [type] [transport]
    elsif ($args->[0] eq "--addvlan") {
        my $name      = $args->[1];
        my $owner     = $args->[2];
        my $type      = $args->[3];
        my $transport = $args->[4];

        my $argsSize = @{$args};
        if ($argsSize != 5) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_LAN_Create -T $hcpUserId -n $name -o $owner -t $type -p $transport"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_LAN_Create -T $hcpUserId -n $name -o $owner -t $type -p $transport");
    }

    # addvswitch [name] [osa_dev_addr] [port_name] [controller] [connect (0, 1, or 2)] [memory_queue] [router] [transport] [vlan_id] [port_type] [update] [gvrp] [native_vlan]
    elsif ($args->[0] eq "--addvswitch") {
        my $i;
        my $argStr = "";

        my $argsSize = @{$args};
        if ($argsSize < 5) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my @options = ("", "-n", "-r", "-a", "-i", "-c", "-q", "-e", "-t", "-v", "-p", "-u", "-G", "-V");
        foreach $i (1 .. $argsSize) {
            if ($args->[$i]) {

                # Prepend options prefix to argument
                $argStr .= "$options[$i] $args->[$i] ";
            }
        }

        $out .= `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Vswitch_Create -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Vswitch_Create -T $hcpUserId $argStr");
    }

    # addzfcp2pool [pool] [status] [wwpn] [lun] [size] [range (optional)] [owner (optional)]
    elsif ($args->[0] eq "--addzfcp2pool") {

        # zFCP disk pool located on zHCP at /var/opt/zhcp/zfcp/{pool}.conf
        # Entries contain: status,wwpn,lun,size,range,owner,channel,tag
        # store pool file in lower case
        my $pool   = lc($args->[1]);
        my $status = $args->[2];
        my $wwpn   = $args->[3];
        my $lun    = $args->[4];
        my $size   = $args->[5];

        my $argsSize = @{$args};
        if ($argsSize < 6 || $argsSize > 8) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
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
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, '"', ""); # Strip off enclosing quotes
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

        # Validate wwpn and lun values.
        # The pattern '[0-9a-f]{16}' means 16 characters in char-set [0-9a-f]. The pattern '(;[0-9a-f]{16})'
        # in last half part is used in the case of multipath. It will not appear in the case of signal path
        # so * is used to handle both cases.
        if ($wwpn !~ m/^[0-9a-f]{16}(;[0-9a-f]{16})*$/i) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid world wide portname $wwpn.");
            return;
        }
        if ($lun !~ m/^[0-9a-f]{16}$/i) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid logical unit number $lun.");
            return;
        }

        # You cannot have a unique SCSI/FCP device in multiple pools
        my @wwpnList = split(";", $wwpn);
        foreach (@wwpnList) {
            my $cur_wwpn = $_;
            my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO grep -a -i -l \",$cur_wwpn,$lun\" $::ZFCPPOOL/*.conf"`);
            if (scalar(@pools)) {
                foreach (@pools) {
                    my $cur_pool = $_;
                    if (!(length $cur_pool)) { next; }
                    my $otherPool = basename($cur_pool);
                    $otherPool =~ s/\.[^.]+$//;    # Do not use extension
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device $cur_wwpn/$lun already exists in $otherPool.");
                }
                return;
            }
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
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid FCP device range. An acceptable range can be specified as 1A80-1B90 or 1A80-1B90;2A80-2B90.");
            return;
        }

        # Owner must be specified if status is used
        if ($status =~ m/used/i && !$owner) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Owner must be specified if status is used.");
            return;
        } elsif ($status =~ m/free/i && $owner) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Owner must not be specified if status is free.");
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
            xCAT::zvmUtils->printLn($callback, "$node: New zFCP device pool $pool created");
        }

        # Update file with given WWPN, LUN, size, and owner
        my $entry = "'" . "$status,$wwpn,$lun,$size,$range,$owner,," . "'";
        $out = `ssh $::SUDOER\@$hcp "$::SUDO echo $entry >> $::ZFCPPOOL/$pool.conf"`;
        xCAT::zvmUtils->printLn($callback, "$node: Adding zFCP device to $pool pool... Done");
        $out = "";
    }

    # copyzfcp [device address (or auto)] [source wwpn] [source lun] [target wwpn (optional)] [target lun (option)]
    elsif ($args->[0] eq "--copyzfcp") {
        my $fcpDevice = $args->[1];
        my $srcWwpn   = $args->[2];
        my $srcLun    = $args->[3];

        my $argsSize = @{$args};
        if ($argsSize != 4 && $argsSize != 6) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Check if WWPN and LUN are given
        my $useWwpnLun = 0;
        my $tgtWwpn;
        my $tgtLun;
        if ($argsSize == 6) {
            $useWwpnLun = 1;
            $tgtWwpn    = $args->[4];
            $tgtLun     = $args->[5];

            # Make sure WWPN and LUN do not have 0x prefix
            $tgtWwpn = xCAT::zvmUtils->replaceStr($tgtWwpn, "0x", "");
            $tgtLun  = xCAT::zvmUtils->replaceStr($tgtLun,  "0x", "");
        }

        # Find the pool that contains the SCSI/FCP device
        my $pool = xCAT::zvmUtils->findzFcpDevicePool($::SUDOER, $hcp, $srcWwpn, $srcLun);
        if (!$pool) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find FCP device in any zFCP storage pool");
            return;
        } else {
            if (xCAT::zvmUtils->checkOutput($pool) == -1) {
                xCAT::zvmUtils->printLn($callback, "$pool");
                return;
            }
            xCAT::zvmUtils->printLn($callback, "$node: Found FCP device in $pool");
        }

        # Get source device's attributes
        my $srcDiskRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $srcWwpn, $srcLun);
        if (xCAT::zvmUtils->checkOutput($srcDiskRef) == -1) {
            xCAT::zvmUtils->printLn($callback, "$srcDiskRef");
            return;
        }
        my %srcDisk = %$srcDiskRef;
        if (!defined($srcDisk{'lun'}) && !$srcDisk{'lun'}) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source zFCP device $srcWwpn/$srcLun does not exists");
            return;
        }
        my $srcSize = $srcDisk{'size'};

        # If target disk is specified, check whether it is large enough
        my $tgtSize;
        if ($useWwpnLun) {
            my $tgtDiskRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $tgtWwpn, $tgtLun);
            if (xCAT::zvmUtils->checkOutput($tgtDiskRef) == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtDiskRef");
                return;
            }
            my %tgtDisk = %$tgtDiskRef;
            if (!defined($tgtDisk{'lun'}) && !$tgtDisk{'lun'}) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Target zFCP device $tgtWwpn/$tgtLun does not exists");
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
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Target zFCP device $tgtWwpn/$tgtLun is not large enough");
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
        $out =~ /Adding zFCP device ([0-9a-f]*)\/([0-9a-f]*)\/([0-9a-f]*).*/i;
        my $srcFcpDevice = lc($1);

        # Attach target disk to zHCP
        my $isTgtAttached = 0;
        if ($useWwpnLun) {
            $out = `/opt/xcat/bin/chvm $hcpNode --addzfcp $pool $fcpDevice 0 $tgtSize "" $tgtWwpn $tgtLun | sed 1d `;
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
        $out =~ /Adding zFCP device ([0-9a-f]*)\/([0-9a-f]*)\/([0-9a-f]*).*/i;
        my $tgtFcpDevice = lc($1);
        $tgtWwpn = lc($2);
        $tgtLun  = lc($3);

        if (!$isTgtAttached) {

            # Release source disk from zHCP
            $out = `/opt/xcat/bin/chvm $hcpNode --removezfcp $fcpDevice $srcWwpn $srcLun 0`;
            return;
        }

        # Get device node of source disk and target disk
        ($srcWwpn, $srcLun, $tgtWwpn, $tgtLun) = (lc($srcWwpn), lc($srcLun), lc($tgtWwpn), lc($tgtLun));
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/readlink /dev/disk/by-path/ccw-0.0.$srcFcpDevice-zfcp-0x$srcWwpn:0x$srcLun"`;
        chomp($out);
        my @srcDiskInfo = split('/', $out);
        my $srcDiskNode = pop(@srcDiskInfo);
        chomp($out);
        xCAT::zvmUtils->printLn($callback, "$node: Device name of $tgtFcpDevice/$srcWwpn/$srcLun is $srcDiskNode");

        $out = `ssh $::SUDOER\@$hcp "$::SUDO /usr/bin/readlink /dev/disk/by-path/ccw-0.0.$tgtFcpDevice-zfcp-0x$tgtWwpn:0x$tgtLun"`;
        chomp($out);
        my @tgtDiskInfo = split('/', $out);
        my $tgtDiskNode = pop(@tgtDiskInfo);
        chomp($tgtDiskNode);
        xCAT::zvmUtils->printLn($callback, "$node: Device name of $tgtFcpDevice/$tgtWwpn/$tgtLun is $tgtDiskNode");

        my $presist = 0;
        my $rc      = "Failed";
        if (!$srcDiskNode || !$tgtDiskNode) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not find device nodes for source or target disk.");
        } else {

            # Copy source disk to target disk (512 block size)
            xCAT::zvmUtils->printLn($callback, "$node: Copying source disk ($srcDiskNode) to target disk ($tgtDiskNode)");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDiskNode of=/dev/$tgtDiskNode bs=512 oflag=sync && $::SUDO echo $?"`;
            $out = xCAT::zvmUtils->trimStr($out);
            if (int($out) != 0) {

                # If $? is not 0 then there was an error during Linux dd
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy /dev/$srcDiskNode");
            }

            $presist = 1;        # Keep target device as reserved
            $rc      = "Done";

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
            'wwpn'   => $srcDisk{'wwpn'},
            'lun'    => $srcDisk{'lun'},
            'size'   => $srcDisk{'size'},
            'range'  => $srcDisk{'range'},
            'owner'  => $srcDisk{'owner'},
            'fcp'    => $srcDisk{'fcp'},
            'tag'    => $srcDisk{'tag'}
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;
        if ($results{'rc'} == -1) {

            # Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source disk attributes cannot be restored in table");
        }

        xCAT::zvmUtils->printLn($callback, "$node: Copying zFCP device... $rc");
        if ($rc eq "Done") {
            xCAT::zvmUtils->printLn($callback, "$node: Source disk copied onto zFCP device $tgtWwpn/$tgtLun");
        }
        $out = "";
    }

    # capturezfcp [profile] [wwpn] [lun] [compression]
    elsif ($args->[0] eq "--capturezfcp") {
        my $out;
        my $rc;
        my $compParm = '';
        my $argsSize = @{$args};
        if ($argsSize < 4) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $profile = $args->[1];
        my $wwpn    = $args->[2];
        my $lun     = $args->[3];
        if ($argsSize >= 5) {

            # Set the compression invocation parameter if compression was specified.
            # Note: Some older zHCP do not support compression specification.

            # Determine if zHCP supports the compression property.
            $out = `ssh -o ConnectTimeout=30 $::SUDOER\@$hcp "$::SUDO $::DIR/creatediskimage -V"`;
            $rc = $?;

            if ($rc == 65280) {
                xCAT::zvmUtils->printSyslog("changeHypervisor() Unable to communicate with zHCP agent");
                xCAT::zvmUtils->printLn($callback, "$node: changeHypervisor() is unable to communicate with zHCP agent: $hcp");
                return;
            }

            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc != -1) {

                # No error.  It is probably that the zHCP supports compression.
                # We will check the version to see if it is high enough.  Any error
                # or too low of a version means that we should ignore the compression
                # operand in the future creatediskimage call.
                # Process the version output.
                my @outLn = split("\n", $out);
                if ($#outLn == 0) {

                    # Only a single line of output should come back from a compatable zHCP.
                    my @versionInfo = split('\.', $out);
                    if ($versionInfo[0] >= 2) {

                        # zHCP supports compression specification.
                        if (($args->[4] =~ /[\d]/) and (length($args->[4]) == 1)) {
                            $compParm = "--compression $args->[4]";
                        } else {
                            xCAT::zvmUtils->printLn($callback, "$node: (Error) compression property is not a single digit from 0 to 9");
                            return;
                        }
                    }
                }
            }
        }

        # Verify required properties are defined
        if (!defined($profile) || !defined($wwpn) || !defined($lun)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing one or more of the required parameters: profile, wwpn, or lun");
            return;
        }

        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

        # Obtain the location of the install root directory
        my $installRoot = xCAT::TableUtils->getInstallDir();

        xCAT::zvmUtils->printSyslog("changeHypervisor() Preparing the staging directory");

        # Create the staging area location for the image
        my $os = "unknown"; # Since we do not inspect the disk contents nor care
        my $provMethod    = "raw";
        my $arch          = "s390x";
        my $stagingImgDir = "$installRoot/staging/$os/$arch/$profile";

        if (-d $stagingImgDir) {
            rmtree $stagingImgDir;
        }
        mkpath($stagingImgDir);

        # Prepare the staging mount point on zHCP, if they need to be established.
        my $remoteStagingDir;
        $rc = xCAT::zvmUtils->establishMount($callback, $::SUDOER, $::SUDO, $hcp, $installRoot, "staging", "rw", \$remoteStagingDir);
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
            if (xCAT::zvmUtils->checkOutput($pool) == -1) {
                xCAT::zvmUtils->printLn($callback, "$pool");
                return;
            }
            xCAT::zvmUtils->printLn($callback, "$node: Found FCP device in $pool");
        }

        # Get source device's attributes
        my $srcDiskRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $wwpn, $lun);
        if (xCAT::zvmUtils->checkOutput($srcDiskRef) == -1) {
            xCAT::zvmUtils->printLn($callback, "$srcDiskRef");
            return;
        }
        my %srcDisk = %$srcDiskRef;
        if (!defined($srcDisk{'lun'}) && !$srcDisk{'lun'}) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source zFCP device $wwpn/$lun does not exists");
            return;
        }

        # Reserve the volume and associated FCP channel for the zHCP node
        my %criteria = (
            'status' => 'used',
            'fcp'    => 'auto',
            'wwpn'   => $wwpn,
            'lun'    => $lun,
            'owner'  => $hcpNode
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;

        my $device = $results{'fcp'};
        $wwpn = $results{'wwpn'};
        $lun  = $results{'lun'};

        if ($results{'rc'} == -1) {

            # Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device cannot be reserved");
            rmtree "$stagingImgDir";
            return;
        }

        xCAT::zvmUtils->printLn($callback, "$node: Capturing volume using zHCP node");

        # Drive the capture on the zHCP node
        xCAT::zvmUtils->printSyslog("changeHypervisor() creatediskimage $device 0x$wwpn/0x$lun $remoteStagingDir/$os/$arch/$profile/0x${wwpn}_0x${lun}.img $compParm");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/creatediskimage $device 0x$wwpn 0x$lun $remoteStagingDir/$os/$arch/$profile/${wwpn}_${lun}.img $compParm"`;
        $rc = $?;

        # Check for capture errors
        my $reasonString = "";
        $rc = xCAT::zvmUtils->checkOutputExtractReason($out, \$reasonString);
        if ($rc != 0) {
            my $reason = "Reason: $reasonString";
            xCAT::zvmUtils->printSyslog("changeHypervisor() creatediskimage of volume 0x$wwpn/0x$lun failed. $reason");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Image capture of volume 0x$wwpn/0x$lun failed on the zHCP node. $reason");
            rmtree "$stagingImgDir";
            return;
        }

        # Restore original source device attributes
        %criteria = (
            'status' => $srcDisk{'status'},
            'wwpn'   => $srcDisk{'wwpn'},
            'lun'    => $srcDisk{'lun'},
            'size'   => $srcDisk{'size'},
            'range'  => $srcDisk{'range'},
            'owner'  => $srcDisk{'owner'},
            'fcp'    => $srcDisk{'fcp'},
            'tag'    => $srcDisk{'tag'}
        );
        $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        %results = %$resultsRef;
        if ($results{'rc'} == -1) {

            # Unable to reserve the volume and FCP channel
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Source disk attributes cannot be restored in table");
        }

        my $imageName    = "$os-$arch-$provMethod-$profile";
        my $deployImgDir = "$installRoot/$provMethod/$os/$arch/$profile";

        xCAT::zvmUtils->printLn($callback, "$node: Moving the image files to the deployable directory: $deployImgDir");

        # Move the image directory to the deploy directory
        mkpath($deployImgDir);

        my @stagedFiles = glob "$stagingImgDir/*";
        foreach my $oldFile (@stagedFiles) {
            move($oldFile, $deployImgDir) or die "$node: (Error) Could not move $oldFile to $deployImgDir: $!\n";
        }

        # Remove the staging directory
        rmtree "$stagingImgDir";

        xCAT::zvmUtils->printSyslog("changeHypervisor() Updating the osimage table");

        my $osTab = xCAT::Table->new('osimage', -create => 1, -autocommit => 0);
        my %keyHash;

        unless ($osTab) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to open table 'osimage'");
            return 0;
        }

        $keyHash{provmethod} = $provMethod;
        $keyHash{profile}    = $profile;
        $keyHash{osvers}     = $os;
        $keyHash{osarch}     = $arch;
        $keyHash{imagetype}  = 'linux';
        $keyHash{imagename}  = $imageName;

        $osTab->setAttribs({ imagename => $imageName }, \%keyHash);
        $osTab->commit;

        xCAT::zvmUtils->printSyslog("changeHypervisor() Updating the linuximage table");

        my $linuxTab = xCAT::Table->new('linuximage', -create => 1, -autocommit => 0);

        %keyHash             = ();
        $keyHash{imagename}  = $imageName;
        $keyHash{rootimgdir} = $deployImgDir;

        $linuxTab->setAttribs({ imagename => $imageName }, \%keyHash);
        $linuxTab->commit;

        xCAT::zvmUtils->printLn($callback, "$node: Completed capturing the volume. Image($imageName) is stored at $deployImgDir");
        $out = "";
    }

    # deployzfcp [imageName] [wwpn] [lun]
    elsif ($args->[0] eq "--deployzfcp") {
        my $imageName = $args->[1];
        my $wwpn      = $args->[2];
        my $lun       = $args->[3];

        # Verify required properties are defined
        if (!defined($imageName) || !defined($wwpn) || !defined($lun)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing one or more arguments: image name, wwpn, or lun");
            return;
        }

        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

        # Obtain the location of the install root directory
        my $installRoot = xCAT::TableUtils->getInstallDir();

        # Build the image location from the image name
        my @nameParts = split('-', $imageName);
        if (!defined $nameParts[3]) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) The image name is not valid");
            return;
        }
        my $profile    = $nameParts[3];
        my $os         = "unknown";
        my $provMethod = "raw";
        my $arch       = "s390x";

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
            $imageFile = (split('/', $imageFiles[0]))[-1];
        }

        # Prepare the deployable netboot mount point on zHCP, if they need to be established.
        my $remoteDeployDir;
        my $rc = xCAT::zvmUtils->establishMount($callback, $::SUDOER, $::SUDO, $hcp, $installRoot, $provMethod, "ro", \$remoteDeployDir);
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
            if (xCAT::zvmUtils->checkOutput($pool) == -1) {
                xCAT::zvmUtils->printLn($callback, "$pool");
                return;
            }
            xCAT::zvmUtils->printLn($callback, "$node: Found FCP device in $pool");
        }

        # Reserve the volume and associated FCP channel for the zHCP node.
        my %criteria = (
            'status' => 'used',
            'fcp'    => 'auto',
            'wwpn'   => $wwpn,
            'lun'    => $lun,
            'owner'  => $hcpNode
        );
        my $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        my %results = %$resultsRef;

        # Obtain the device assigned by xCAT
        my $device = $results{'fcp'};
        $wwpn = $results{'wwpn'};
        $lun  = $results{'lun'};

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
            'wwpn'   => $wwpn,
            'lun'    => $lun
        );
        $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        if ($results{'rc'} == -1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device cannot be released");
        }

        # Check for deploy errors
        my $reasonString = "";
        $rc = xCAT::zvmUtils->checkOutputExtractReason($out, \$reasonString);
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
    elsif ($args->[0] eq "--removediskfrompool") {
        my $funct  = $args->[1];
        my $region = $args->[2];
        my $group  = "";

        # Create an array for regions
        my @regions;
        if ($region =~ m/,/i) {
            @regions = split(',', $region);
        } else {
            push(@regions, $region);
        }

        my $tmp;
        foreach (@regions) {
            if (!(length $_)) { next; }
            $_ = xCAT::zvmUtils->trimStr($_);

            # Remove region from group | Remove entire group
            if ($funct eq "2" || $funct eq "7") {
                $group = $args->[3];
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
    elsif ($args->[0] eq "--removescsi") {
        my $argsSize = @{$args};
        if ($argsSize != 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo   = "dev_num=" . $args->[1];
        my $persist = "persist=" . $args->[2];

        # Delete a real SCSI disk
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_SCSI_Disk_Delete -T $hcpUserId -k $devNo -k $persist"`;
        xCAT::zvmUtils->printSyslog("smcli System_SCSI_Disk_Delete -T $hcpUserId -k $devNo -k $persist");
    }

    # removevlan [name] [owner]
    elsif ($args->[0] eq "--removevlan") {
        my $name  = $args->[1];
        my $owner = $args->[2];

        # Delete a virtual network
        $out = `ssh $hcp "$::DIR/smcli Virtual_Network_LAN_Delete -T $hcpUserId -n $name -o $owner"`;
        xCAT::zvmUtils->printSyslog("ssh $hcp $::DIR/smcli Virtual_Network_LAN_Delete -T $hcpUserId -n $name -o $owner");
    }

    # removevswitch [name]
    elsif ($args->[0] eq "--removevswitch") {
        my $name = $args->[1];

        # Delete a VSWITCH
        $out = `ssh $hcp "$::DIR/smcli Virtual_Network_Vswitch_Delete -T $hcpUserId -n $name"`;
        xCAT::zvmUtils->printSyslog("ssh $hcp $::DIR/smcli Virtual_Network_Vswitch_Delete -T $hcpUserId -n $name");
    }

    # removezfcpfrompool [pool] [lun] [wwpn]
    elsif ($args->[0] eq "--removezfcpfrompool") {
        my $argsSize = @{$args};
        my $pool     = $args->[1];
        my $lun      = $args->[2];
        if ($argsSize < 4) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) WWPN is required.");
            return;
        }
        my $wwpn = $args->[3];
        if ($argsSize > 4) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Make sure WWPN and LUN do not have 0x prefix
        $wwpn = xCAT::zvmUtils->replaceStr($wwpn, "0x", "");
        $lun  = xCAT::zvmUtils->replaceStr($lun,  "0x", "");

        # Verify WWPN and LUN have the correct syntax
        # The pattern '[0-9a-f]{16}' means 16 characters in char-set [0-9a-f]. The pattern '(;[0-9a-f]{16})'
        # in last half part is used in the case of multipath. It will not appear in the case of signal path
        # so * is used to handle both cases.
        if ($wwpn !~ m/^[0-9a-f]{16}(;[0-9a-f]{16})*$/i) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid world wide port name $wwpn.");
            return;
        }

        # The pattern '[0-9a-f]{16}' means 16 characters in char-set [0-9a-f]. The pattern '(,[0-9a-f]{16})'
        # in last half part is used to deal with lun list.
        if ($lun !~ m/^[0-9a-f]{16}(,[0-9a-f]{16})*$/i) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid logical unit number $lun.");
            return;
        }

        my @luns;
        if ($lun =~ m/,/i) {
            @luns = split(',', $lun);
        } else {
            push(@luns, $lun);
        }

        # Find disk pool
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO test -e $::ZFCPPOOL/$pool.conf && echo Exists"`)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP pool does not exist");
            return;
        }

        # Go through each LUN, look for matches of lun + wwpn (if specified)
        my $entry;
        my @args;
        foreach (@luns) {
            my $cur_lun = $_;
            if (!(length $cur_lun)) { next; }

            # Entry should contain: status, wwpn, lun, size, range, owner, channel, tag
            $entry = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf"`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $::ZFCPPOOL/$pool.conf\"", $hcp, "changeHypervisor", $entry, $node);
            if ($rc != 0) {
                xCAT::zvmUtils->printLn($callback, "$outmsg");
                return;
            }
            $entry = `echo "$entry" | egrep -a -i "$cur_lun"`;

            # Do not update if LUN does not exists, stop checking other luns if this one not found
            if (!$entry) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device $cur_lun does not exist");
                return;
            }

            # process multiple lines if they exist with this lun
            my @lines = split("\n", $entry);
            my $foundit = 0;
            foreach (@lines) {
                my $fcpline = $_;
                $fcpline = xCAT::zvmUtils->trimStr($fcpline);
                if (!(length $fcpline)) { next; } # in case split causes an empty item

                # Skip if WWPN specified, and WWPN/LUN combo does not exists for this line
                @args = split(',', $fcpline);
                if ((length $wwpn) && !($args[1] =~ m/$wwpn/i)) {
                    next;
                }

                # delete this line in the file with given WWPN and LUN
                $foundit = 1;
                $fcpline = "'" . $fcpline . "'";
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $hcp, "sed -i -e /$fcpline/d $::ZFCPPOOL/$pool.conf");

                xCAT::zvmUtils->printLn($callback, "$node: Removing zFCP device $wwpn/$cur_lun from $pool pool... Done");

                # Check if pool is empty, if so delete the pool.conf (If empty it only contains a header line)
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $hcp, "cat $::ZFCPPOOL/$pool.conf");
                my @linesLeft = split("\n", $out);
                my $lineCount = scalar(@linesLeft);
                my $emptyLines = `grep -cavP '\\S' $::ZFCPPOOL/$pool.conf`; # Count "empty" lines
                if ($lineCount <= 1 || $lineCount == $emptyLines) {
                    $out = xCAT::zvmUtils->rExecute($::SUDOER, $hcp, "rm -f $::ZFCPPOOL/$pool.conf");
                    xCAT::zvmUtils->printLn($callback, "$node: Deleting empty zFCP $pool pool.");
                    return;
                }
            }
            if ($foundit == 0) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) zFCP device $wwpn/$cur_lun does not exist.");
                return;
            }
        }

        # clear any data left in out so it does not display on callback
        $out = "";
    }

    # releasezfcp [pool] [wwpn] [lun]
    elsif ($args->[0] eq "--releasezfcp") {
        my $pool = lc($args->[1]);
        my $wwpn = lc($args->[2]);
        my $lun  = lc($args->[3]);

        my $argsSize = @{$args};
        if ($argsSize != 4) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $device = "";

        # In case multiple LUNs are given, push LUNs into an array to be processed
        my @luns;
        if ($lun =~ m/,/i) {
            @luns = split(',', $lun);
        } else {
            push(@luns, $lun);
        }

        # Go through each LUN
        foreach (@luns) {
            if (!(length $_)) { next; }
            my %criteria = (
                'status' => 'free',
                'wwpn'   => $wwpn,
                'lun'    => $_
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
    elsif ($args->[0] eq "--reservezfcp") {
        my $pool   = lc($args->[1]);
        my $status = $args->[2];
        my $owner  = $args->[3];
        my $device = $args->[4];
        my $size   = $args->[5];

        my $argsSize = @{$args};
        if ($argsSize != 6 && $argsSize != 8) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # status can be used or reserved but not free
        if ($status =~ m/^free$/i) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Status can be used or reserved but not free.");
            return;
        }

        # Obtain the FCP device, WWPN, and LUN (if any)
        my $wwpn = "";
        my $lun  = "";
        if ($argsSize == 8) {
            $wwpn = lc($args->[6]);
            $lun  = lc($args->[7]);

            # WWPN and LUN must both be specified or both not
            if ($wwpn xor $lun) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) WWPN and LUN must both be specified or both not.");
                return;
            }

            # Ignore the size if the WWPN and LUN are given
            $size = "";
        }

        my %criteria;
        my $resultsRef;
        if ($wwpn && $lun) {

            # Check the status of the FCP device
            my $deviceRef = xCAT::zvmUtils->findzFcpDeviceAttr($::SUDOER, $hcp, $pool, $wwpn, $lun);
            if (xCAT::zvmUtils->checkOutput($deviceRef) == -1) {
                xCAT::zvmUtils->printLn($callback, "$deviceRef");
                return;
            }
            my %zFCP = %$deviceRef;
            if ($zFCP{'status'} eq 'used') {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) FCP device 0x$wwpn/0x$lun is in use.");
                return;
            }

            %criteria = (
                'status' => $status,
                'fcp'    => $device,
                'wwpn'   => $wwpn,
                'lun'    => $lun,
                'owner'  => $owner
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        } else {

            # Do not know the WWPN or LUN in this case
            %criteria = (
                'status' => $status,
                'fcp'    => $device,
                'size'   => $size,
                'owner'  => $owner
            );
            $resultsRef = xCAT::zvmUtils->findAndUpdatezFcpPool($callback, $node, $::SUDOER, $hcp, $pool, \%criteria);
        }

        my %results = %$resultsRef;

        # Obtain the device assigned by xCAT
        $device = $results{'fcp'};
        $wwpn   = $results{'wwpn'};
        $lun    = $results{'lun'};

        if ($results{'rc'} == 0) {
            xCAT::zvmUtils->printLn($callback, "$node: Reserving FCP device... Done");
            my $fcpDevice = $device ? "$device/0x$wwpn/0x$lun" : "0x$wwpn/0x$lun";
            xCAT::zvmUtils->printLn($callback, "$node: FCP device $fcpDevice was reserved... Done");
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Reserving FCP device... Failed");
        }
    }

    # resetsmapi
    elsif ($args->[0] eq "--resetsmapi") {

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
            foreach (@workers) {
                $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp force $_ logoff immediate"`;
            }

            # Log on VSMWORK1
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp xautolog VSMWORK1"`;
        }

        $out = "Resetting SMAPI... Done";
    }

    # smcli [api] [args]
    elsif ($args->[0] eq "--smcli") {

        # Invoke SMAPI API directly through zHCP smcli
        my $str = "@{$args}";
        $str =~ s/$args->[0]//g;
        $str = xCAT::zvmUtils->trimStr($str);

        # Pass arguments directly to smcli
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli $str"`;
    }

    # Otherwise, print out error
    else {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Option not supported");
    }

    # Only print if there is content
    if ($out) {
        $out = xCAT::zvmUtils->appendHostname($node, $out);
        chomp($out);
        xCAT::zvmUtils->printLn($callback, "$out");
    }

    return;
}

#-------------------------------------------------------

=head3   inventoryHypervisor

    Description : Get hardware and software inventory of a given hypervisor
    Arguments   :   Node
                    Type of inventory (config|all)
    Returns     : Nothing, errors returned in $callback
    Example     : inventoryHypervisor($callback, $node, $args);

=cut

#-------------------------------------------------------
sub inventoryHypervisor {

    # Get inputs
    my ($callback, $node, $args) = @_;

    # Set cache directory
    my $cache = '/var/opt/zhcp/cache';

    # Output string
    my $str = "";

    my $rc;
    my $out;
    my $outmsg;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node zHCP");
        return;
    }

    xCAT::zvmUtils->printSyslog("sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO");

    # Get the user Id of the zHCP
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);

    # Load VMCP module
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/modprobe vmcp"`;

    # Get configuration
    if ($args->[0] eq 'config') {

        # Get z/VM host for zhcp
        my $hypname = xCAT::zvmCPUtils->getHost($::SUDOER, $hcp);

        # Get total physical CPU in this LPAR
        my $lparCpuTotal = xCAT::zvmUtils->getLparCpuTotal($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparCpuTotal) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparCpuTotal");
            return;
        }

        # Get used physical CPU in this LPAR
        my $lparCpuUsed = xCAT::zvmUtils->getLparCpuUsed($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparCpuUsed) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparCpuUsed");
            return;
        }

        # Get LPAR memory total
        my $lparMemTotal = xCAT::zvmUtils->getLparMemoryTotal($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparMemTotal) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparMemTotal");
            return;
        }

        # Get LPAR memory Offline
        my $lparMemOffline = xCAT::zvmUtils->getLparMemoryOffline($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparMemOffline) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparMemOffline");
            return;
        }

        # Get LPAR memory Used
        my $lparMemUsed = xCAT::zvmUtils->getLparMemoryUsed($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparMemUsed) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparMemUsed");
            return;
        }

        $str .= "z/VM Host: $hypname\n";
        $str .= "zHCP: $hcp\n";
        $str .= "LPAR CPU Total: $lparCpuTotal\n";
        $str .= "LPAR CPU Used: $lparCpuUsed\n";
        $str .= "LPAR Memory Total: $lparMemTotal\n";
        $str .= "LPAR Memory Used: $lparMemUsed\n";
        $str .= "LPAR Memory Offline: $lparMemOffline\n";
        $str .= "xCAT Hypervisor Node: $node\n"; # need node name from table unmodified

    } elsif ($args->[0] eq 'all') {

        # Get z/VM system name  for zhcp
        my $hypname = xCAT::zvmCPUtils->getHost($::SUDOER, $hcp);

        # Get total physical CPU in this LPAR
        my $lparCpuTotal = xCAT::zvmUtils->getLparCpuTotal($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparCpuTotal) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparCpuTotal");
            return;
        }

        # Get used physical CPU in this LPAR
        my $lparCpuUsed = xCAT::zvmUtils->getLparCpuUsed($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparCpuUsed) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparCpuUsed");
            return;
        }

        # Get CEC model
        my $cecModel = xCAT::zvmUtils->getCecModel($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($cecModel) == -1) {
            xCAT::zvmUtils->printLn($callback, "$cecModel");
            return;
        }

        # Get vendor of CEC
        my $cecVendor = xCAT::zvmUtils->getCecVendor($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($cecVendor) == -1) {
            xCAT::zvmUtils->printLn($callback, "$cecVendor");
            return;
        }

        # Get hypervisor type and version
        my $hvInfo = xCAT::zvmUtils->getHypervisorInfo($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($hvInfo) == -1) {
            xCAT::zvmUtils->printLn($callback, "$hvInfo");
            return;
        }

        # Get processor architecture
        my $arch = xCAT::zvmUtils->getArch($::SUDOER, $hcp);

        # Get hypervisor name
        my $host = xCAT::zvmCPUtils->getHost($::SUDOER, $hcp);

        # Get LPAR memory total
        my $lparMemTotal = xCAT::zvmUtils->getLparMemoryTotal($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparMemTotal) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparMemTotal");
            return;
        }

        # Get LPAR memory Offline
        my $lparMemOffline = xCAT::zvmUtils->getLparMemoryOffline($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparMemOffline) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparMemOffline");
            return;
        }

        # Get LPAR memory Used
        my $lparMemUsed = xCAT::zvmUtils->getLparMemoryUsed($::SUDOER, $hcp);
        if (xCAT::zvmUtils->checkOutput($lparMemUsed) == -1) {
            xCAT::zvmUtils->printLn($callback, "$lparMemUsed");
            return;
        }

        # Get IPL Time
        my $ipl = xCAT::zvmCPUtils->getIplTime($::SUDOER, $hcp);

        # Create output string

        $str .= "z/VM Host: $hypname\n";
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
        $str .= "IPL Time: $ipl\n";
        $str .= "xCAT Hypervisor Node: $node\n"; # need node name from table unmodified
    }

    # diskpoolspace
    elsif ($args->[0] eq '--diskpoolspace') {

        # Check whether disk pool was given
        my @pools;
        if (!$args->[1]) {

            # Get all known disk pool names
            $out = `/opt/xcat/bin/rinv $node "--diskpoolnames"`;
            $out =~ s/$node: //g;
            $out = xCAT::zvmUtils->trimStr($out);
            @pools = split('\n', $out);
        } else {
            my $pool = uc($args->[1]);
            push(@pools, $pool);

            # Check whether disk pool is a valid pool
            xCAT::zvmUtils->printSyslog("smcli Image_Volume_Space_Query_DM -q 1 -e 3 -n $pool -T $hcpUserId");
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Volume_Space_Query_DM -q 1 -e 3 -n $pool -T $hcpUserId"`;
            if ($out eq '') {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to communicate with zHCP agent");
                return;
            } elsif ($out =~ m/Failed/i) {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to obtain disk pool information for $pool, additional information: $out");
                return;
            }
        }

        # Go through each pool and find it's space
        foreach (@pools) {

            # Skip empty pool
            if (!$_) {
                next;
            }

            my $free = xCAT::zvmUtils->getDiskPoolFree($::SUDOER, $hcp, $_);
            my $used = xCAT::zvmUtils->getDiskPoolUsed($::SUDOER, $hcp, $_);
            my $total = $free + $used;

            # Change the output format from cylinders to 'G' or 'M'
            $total = xCAT::zvmUtils->getSizeFromCyl($total);
            $used  = xCAT::zvmUtils->getSizeFromCyl($used);
            $free  = xCAT::zvmUtils->getSizeFromCyl($free);

            $str .= "$_ Total: $total\n";
            $str .= "$_ Used: $used\n";
            $str .= "$_ Free: $free\n";
        }
    }

    # diskpool [pool] [all|free|used]
    elsif ($args->[0] eq "--diskpool") {

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
    elsif ($args->[0] eq "--diskpoolnames") {

        # Get disk pool names
        # If the cache directory does not exist
        if (!(`ssh $::SUDOER\@$hcp "$::SUDO test -d $cache && echo Exists"`)) {

            # Create cache directory
            $out = `ssh $::SUDOER\@$hcp "$::SUDO mkdir -p $cache"`;
        }
        $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("$node: (Error) unable to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "$node: (Error) unable to communicate with the zhcp system: $hcp");
            return;
        }

        my $file = "$cache/diskpoolnames";

        # If a cache for disk pool names exists
        if (`ssh $::SUDOER\@$hcp "$::SUDO ls $file"`) {

            # Get current Epoch
            my $curTime = time();

            # Get time of last change as seconds since Epoch
            my $fileTime = xCAT::zvmUtils->trimStr(`ssh $::SUDOER\@$hcp "$::SUDO stat -c %Z $file"`);

            # If the current time is greater than 5 minutes of the file timestamp
            my $interval = 300;    # 300 seconds = 5 minutes * 60 seconds/minute
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
    elsif ($args->[0] eq "--fcpdevices") {
        my $argsSize = @{$args};
        my $space    = $args->[1];
        my $details  = 0;
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

                @devices = split("\n", $out);
                for ($i = 0 ; $i < @devices ; $i++) {

                    # Extract the device number and status
                    $devNo = $devices[$i];
                    $devNo =~ s/^FCP device number:(.*)/$1/;
                    $devNo =~ s/^\s+//;
                    $devNo =~ s/\s+$//;

                    $status = $devices[ $i + 1 ];
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
                xCAT::zvmUtils->printSyslog("smcli System_WWPN_Query -T $hcpUserId");
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_WWPN_Query -T $hcpUserId"`;
                ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli System_WWPN_Query -T $hcpUserId\"", $hcp, "inventoryHypervisor", $out, $node);
                if ($rc != 0) {
                    xCAT::zvmUtils->printLn($callback, "$outmsg");
                    return;
                }
                $out = `echo "$out" | egrep -a -i "FCP device number|Status"`;

                @devices = split("\n", $out);
                for ($i = 0 ; $i < @devices ; $i++) {

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
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Query supported on active, free, or offline devices");
        }
    }

    # luns [fcp_device] (supported only on z/VM 6.2)
    elsif ($args->[0] eq "--luns") {

        # Find the LUNs accessible thru given zFCP device
        my $fcp      = lc($args->[1]);
        my $argsSize = @{$args};
        if ($argsSize < 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        xCAT::zvmUtils->printSyslog("smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp\"", $hcp, "inventoryHypervisor", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $out = `echo "$out" | egrep -a -i "FCP device number:|World wide port number:|Logical unit number:|Number of bytes residing on the logical unit:"`;

        my @wwpns = split("\n", $out);
        my %map;

        my $wwpn = "";
        my $lun  = "";
        my $size = "";
        foreach (@wwpns) {
            if (!(length $_)) { next; }

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
            foreach $lun (sort keys %{ $map{$wwpn} }) {

                # status, wwpn, lun, size, range, owner, channel, tag
                $size = sprintf("%.1f", $map{$wwpn}{$lun} / 1073741824); # Convert size to GB

                if ($size > 0) {
                    $size .= "G";
                    xCAT::zvmUtils->printLn($callback, "unknown,$wwpn,$lun,$size,,,,");
                }
            }
        }

        $str = "";
    }

    # networknames
    elsif ($args->[0] eq "--networknames" || $args->[0] eq "--getnetworknames") {
        $str = xCAT::zvmCPUtils->getNetworkNames($::SUDOER, $hcp);
    }

    # network [name]
    elsif ($args->[0] eq "--network" || $args->[0] eq "--getnetwork") {
        my $netName = $args->[1];
        my $netType = $args->[2];
        $str = xCAT::zvmCPUtils->getNetwork($::SUDOER, $hcp, $netName, $netType);
    }

    # responsedata [failed Id]
    elsif ($args->[0] eq "--responsedata") {

        # This has not be completed!
        my $failedId = $args->[1];
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Response_Recovery -T $hcpUserId -k $failedId"`;
        xCAT::zvmUtils->printSyslog("smcli Response_Recovery -T $hcpUserId -k $failedId");
    }

    # freefcp [fcp_dev]
    elsif ($args->[0] eq "--freefcp") {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $fcp = "fcp_dev=" . $args->[1];

        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k $fcp"`;
        xCAT::zvmUtils->printSyslog("smcli System_FCP_Free_Query -T $hcpUserId -k $fcp");
    }

    # scsidisk [dev_no]
    elsif ($args->[0] eq "--scsidisk") {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo = "dev_num=" . $args->[1];

        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_SCSI_Disk_Query -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_SCSI_Disk_Query -T $hcpUserId -k $devNo");
    }

    # ssi
    elsif ($args->[0] eq "--ssi") {
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli SSI_Query"`;
        xCAT::zvmUtils->printSyslog("smcli SSI_Query");
    }

    # smapilevel
    elsif ($args->[0] eq "--smapilevel") {
        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Query_API_Functional_Level -T $hcpUserId"`;
        xCAT::zvmUtils->printSyslog("smcli Query_API_Functional_Level -T $hcpUserId");
    }

    # systemdisk [dev_no]
    elsif ($args->[0] eq "--systemdisk") {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo = "dev_num=" . $args->[1];

        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Query -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_Disk_Query -T $hcpUserId -k $devNo");
    }

    # systemdiskaccessibility [dev_no]
    elsif ($args->[0] eq "--systemdiskaccessibility") {
        my $argsSize = @{$args};
        if ($argsSize != 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $devNo = "dev_num=" . $args->[1];

        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_Disk_Accessibility -T $hcpUserId -k $devNo"`;
        xCAT::zvmUtils->printSyslog("smcli System_Disk_Accessibility -T $hcpUserId -k $devNo");
    }

    # userprofilenames
    elsif ($args->[0] eq "--userprofilenames") {
        my $argsSize = @{$args};
        if ($argsSize != 1) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        # Use Directory_Manager_Search_DM to find user profiles
        my $tmp = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Directory_Manager_Search_DM -T $hcpUserId -s PROFILE"`;
        my @profiles = split('\n', $tmp);
        foreach (@profiles) {
            if (!(length $_)) { next; }

            # Extract user profile
            if ($_) {
                $_ =~ /([a-zA-Z]*):*/;
                $str .= "$1\n";
            }
        }

        xCAT::zvmUtils->printSyslog("smcli Directory_Manager_Search_DM -T $hcpUserId -s PROFILE");
    }

    # vlanstats [vlan_id] [user_id] [device] [version]
    elsif ($args->[0] eq "--vlanstats") {

        # This is not completed!
        my $argsSize = @{$args};
        if ($argsSize < 4 && $argsSize > 5) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $vlanId     = "VLAN_id=" . $args->[1];
        my $tgtUserId  = "userid=" . $args->[2];
        my $device     = "device=" . $args->[3];
        my $fmtVersion = "fmt_version=" . $args->[4];    # Optional

        my $argStr = "-k $vlanId -k $tgtUserId -k $device";
        if ($argsSize == 5) {
            $argStr .= " -k $fmtVersion"
        }

        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_VLAN_Query_Stats -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_VLAN_Query_Stats -T $hcpUserId $argStr");
    }

    # vswitchstats [name] [version]
    elsif ($args->[0] eq "--vswitchstats") {
        my $argsSize = @{$args};
        if ($argsSize < 2 && $argsSize > 3) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        my $switchName = "switch_name=" . $args->[1];
        my $fmtVersion = "fmt_version=" . $args->[2];    # Optional
        my $argStr     = "-k $switchName";

        if ($argsSize == 3) {
            $argStr .= " -k $fmtVersion"
        }

        $str = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Virtual_Network_Vswitch_Query_Stats -T $hcpUserId $argStr"`;
        xCAT::zvmUtils->printSyslog("smcli Virtual_Network_Vswitch_Query_Stats -T $hcpUserId $argStr");
    }

    # wwpn [fcp_device] (supported only on z/VM 6.2)
    elsif ($args->[0] eq "--wwpns") {
        my $fcp      = lc($args->[1]);
        my $argsSize = @{$args};
        if ($argsSize < 2) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Wrong number of parameters");
            return;
        }

        xCAT::zvmUtils->printSyslog("smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli System_FCP_Free_Query -T $hcpUserId -k fcp_dev=$fcp\"", $hcp, "inventorHypervisor", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $out = `echo "$out" | egrep -a -i "World wide port number:"`;

        my @wwpns = split("\n", $out);
        my %uniqueWwpns;
        foreach (@wwpns) {
            if (!(length $_)) { next; }

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
        for $wwpn (keys %uniqueWwpns) {
            $str .= "$wwpn\n";
        }
    }

    # zfcppool [pool] [space]
    elsif ($args->[0] eq "--zfcppool") {

        # Get zFCP disk pool configuration
        my $pool  = lc($args->[1]);
        my $space = $args->[2];

        if ($space eq "all" || !$space) {
            $str = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf"`;
        } else {
            $str = "#status,wwpn,lun,size,range,owner,channel,tag\n";
            $out = `ssh $::SUDOER\@$hcp "$::SUDO cat $::ZFCPPOOL/$pool.conf"`;
            ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO cat $::ZFCPPOOL/$pool.conf\"", $hcp, "inventoryHypervisor", $out, $node);
            if ($rc != 0) {
                xCAT::zvmUtils->printLn($callback, "$outmsg");
                return;
            }
            $out = `echo "$out" | egrep -a -i "$space"`;
            $str .= $out;
        }
    }

    # zfcppoolnames
    elsif ($args->[0] eq "--zfcppoolnames") {

        # Get zFCP disk pool names
        # Go through each zFCP pool
        # Note: the code makes an assumption that the only files in this directory are
        # zfcp configuration files. (*.conf)
        my @pools = split("\n", `ssh $::SUDOER\@$hcp "$::SUDO ls $::ZFCPPOOL"`);
        foreach (@pools) {
            if (!(length $_)) { next; }
            my $pool = $_;

            # Check if pool is empty (just one line), if so delete
            my $out = xCAT::zvmUtils->rExecute($::SUDOER, $hcp, "cat $::ZFCPPOOL/$pool");
            my @linesLeft = split("\n", $out);
            my $lineCount = scalar(@linesLeft);
            my $emptyLines = `grep -cavP '\\S' $::ZFCPPOOL/$pool`; # Count "empty" lines
            if ($lineCount <= 1 || $lineCount == $emptyLines) {

                # Delete the empty pool, write log entry
                xCAT::zvmUtils->printSyslog("Deleting empty zfcp pool: $pool");
                $out = xCAT::zvmUtils->rExecute($::SUDOER, $hcp, "rm -f $::ZFCPPOOL/$pool");
                next;
            }

            # return just the pool name without the ".conf"
            $pool = xCAT::zvmUtils->replaceStr($pool, ".conf", "");
            $str .= "$pool\n";
        }
    }

    else {
        $str = "$node: (Error) Option not supported";
        xCAT::zvmUtils->printLn($callback, "$str");
        return;
    }

    # Append hostname (e.g. pokdev61) in front
    $str = xCAT::zvmUtils->appendHostname($node, $str);

    xCAT::zvmUtils->printLn($callback, "$str");
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
    my ($callback, $node, $args) = @_;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get HCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if (!$userId) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing user ID");
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    xCAT::zvmUtils->printSyslog("migrateVM() node:$node userid:$userId zHCP:$hcp sudoer:$::SUDOER sudo:$::SUDO");

    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;

    # Output string
    my $out;
    my $migrateCmd = "VMRELOCATE -T $userId";

    my $destination;
    my $action;
    my $value;
    foreach my $operand (@$args) {
        if ($operand) {

            # Find destination key
            if ($operand =~ m/destination=/i) {
                $destination = $operand;
                $destination =~ s/destination=//g;
                $destination =~ s/"//g;
                $destination =~ s/'//g;
            } elsif ($operand =~ m/action=/i) {
                $action = $operand;
                $action =~ s/action=//g;
            } elsif ($operand =~ m/max_total=/i) {
                $value = $operand;
                $value =~ s/max_total=//g;

                # Strip leading zeros
                if (!($value =~ m/[^0-9.]/)) {
                    $value =~ s/^0+//;
                    $operand = "max_total=$value";
                }
            } elsif ($operand =~ m/max_quiesce=/i) {
                $value = $operand;
                $value =~ s/max_quiesce=//g;

                # Strip leading zeros
                if (!($value =~ m/[^0-9.]/)) {
                    $value =~ s/^0+//;
                    $operand = "max_quiesce=$value";
                }
            }

            # Keys passed directly to smcli
            $migrateCmd .= " -k $operand";
        }
    }

    if (!$action || !$destination) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) One or more required operands was not specified: 'action' or 'destination'.");
        return;
    }

    my $destHcp;
    if ($action =~ m/MOVE/i) {

        # Find the zHCP for the destination host and set the node zHCP as it
        # Otherwise, it is up to the user to manually change the zHCP
        @propNames = ('hcp');
        $propVals = xCAT::zvmUtils->getNodeProps('zvm', lc($destination), @propNames);
        $destHcp = $propVals->{'hcp'};
        if (!$destHcp) {

            # Try upper-case
            $propVals = xCAT::zvmUtils->getNodeProps('zvm', uc($destination), @propNames);
            $destHcp = $propVals->{'hcp'};
        }

        if (!$destHcp) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find zHCP of $destination");
            xCAT::zvmUtils->printLn($callback, "$node: (Solution) Set the hcp appropriately in the zvm table");
            return;
        }
    }

    # Begin migration
    $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli $migrateCmd"`;
    xCAT::zvmUtils->printSyslog("On $hcp, smcli $migrateCmd");
    xCAT::zvmUtils->printLn($callback, "$node: $out");

    # Check for errors on migration only
    my $rc = xCAT::zvmUtils->checkOutput($out);
    if ($rc != -1 && $action =~ m/MOVE/i) {

        # Check the migration status
        my $check      = 4;
        my $isMigrated = 0;
        while ($check > 0) {
            $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli VMRELOCATE_Status -T $hcpUserId" -k status_target=$userId`;
            xCAT::zvmUtils->printSyslog("smcli VMRELOCATE_Status -T $hcpUserId -k status_target=$userId");
            if ($out =~ m/No active relocations found/i) {
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
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not determine progress of relocation");
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
    my ($callback, $node, $args) = @_;

    # In order for this command to work, issue under /opt/xcat/bin:
    # ln -s /opt/xcat/bin/xcatclient revacuate

    my $destination = $args->[0];
    if (!$destination) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing z/VM SSI cluster name of the destination system");
        return;
    }

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'nodetype');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP of hypervisor
    my $srcHcp = $propVals->{'hcp'};
    if (!$srcHcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    my $type = $propVals->{'nodetype'};
    if ($type ne 'zvm') {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Invalid nodetype");
        xCAT::zvmUtils->printLn($callback, "$node: (Solution) Set the nodetype appropriately in the zvm table");
        return;
    }

    my $destHcp;

    # Find the zHCP for the destination host and set the node zHCP as it
    # Otherwise, it is up to the user to manually change the zHCP
    @propNames = ('hcp');
    $propVals = xCAT::zvmUtils->getNodeProps('zvm', lc($destination), @propNames);
    $destHcp = $propVals->{'hcp'};
    if (!$destHcp) {

        # Try upper-case
        $propVals = xCAT::zvmUtils->getNodeProps('zvm', uc($destination), @propNames);
        $destHcp = $propVals->{'hcp'};
    }

    if (!$destHcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to find zHCP of $destination");
        xCAT::zvmUtils->printLn($callback, "$node: (Solution) Set the hcp appropriately in the zvm table");
        return;
    }

    # Get nodes managed by this zHCP
    # Look in 'zvm' table
    my $tab = xCAT::Table->new('zvm', -create => 1, -autocommit => 0);
    my @entries = $tab->getAllAttribsWhere("hcp like '%" . $srcHcp . "%' and nodetype=='vm'", 'node', 'userid');

    my $out;
    my $iNode;
    my $iUserId;
    my $smcliArgs;
    my $nodes = "";
    foreach (@entries) {
        $iNode   = $_->{'node'};
        $iUserId = $_->{'userid'};

        # Skip zHCP entry
        if ($srcHcp =~ m/$iNode./i || $srcHcp eq $iNode) {
            next;
        }

        $nodes .= $iNode . ",";
    }

    # Strip last comma
    $nodes = substr($nodes, 0, -1);

    # Do not continue if no nodes to migrate
    if (!$nodes) {
        xCAT::zvmUtils->printLn($callback, "$node: No nodes to evacuate");
        return;
    }

    # Begin migration
    # Required keys: target_identifier, destination, action, immediate, and max_total
    $out = `/opt/xcat/bin/rmigrate $nodes action=MOVE destination=$destination immediate=NO max_total=NOLIMIT`;
    xCAT::zvmUtils->printLn($callback, "$out");

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
    my ($callback, $node, $args) = @_;

    my $srcLog  = '';
    my $tgtLog  = '';
    my $clear   = 0;
    my $options = '';
    if ($args) {
        @ARGV = @$args;

        # Parse options
        GetOptions(
            's=s' => \$srcLog,
            't=s' => \$tgtLog,      # Optional
            'c'   => \$clear,
            'o=s' => \$options);    # Set logging options
    }

    # Event log required
    if (!$srcLog) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing event log");
        return;
    }

    # Limit to logs in /var/log/* and configurations in /var/opt/*
    my $tmp = substr($srcLog, 0, 9);
    if ($tmp ne "/var/opt/" && $tmp ne "/var/log/") {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Files are restricted to those in /var/log and /var/opt");
        return;
    }

    # Check if node is the management node
    my @entries = xCAT::TableUtils->get_site_attribute("master");
    my $master  = xCAT::zvmUtils->trimStr($entries[0]);
    my $ip      = xCAT::NetworkUtils->getipaddr($node);
    $ip = xCAT::zvmUtils->trimStr($ip);
    my $mn = 0;
    if ($master eq $ip) {

        # If the master IP and node IP match, then it is the management node
        xCAT::zvmUtils->printLn($callback, "$node: This is the management node");
        $mn = 1;
    }

    # Just clear the log
    my $out = '';
    if ($clear) {
        if ($mn) {
            $out = `cat /dev/null > $srcLog`;
        } else {

            #$out = `ssh $::SUDOER\@$node "cat /dev/null > $srcLog"`;
            my $cmd = "$::SUDO cat /dev/null > $srcLog";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

        }

        xCAT::zvmUtils->printLn($callback, "$node: Clearing event log ($srcLog)... Done");
        return;
    }

    # Just set the logging options
    if ($options) {
        if ($mn) {
            $out = `echo -e \"$options\" > $srcLog`;
        } else {
            $out = `echo -e \"$options\" > /tmp/$node.tracing`;

            #$out = `ssh $::SUDOER\@$node "rm -rf $srcLog"`;
            my $cmd = "$::SUDO rm -rf $srcLog";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            # Get node communicate type.
            my @propNames = ('status');
            my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);
            if ($propVals->{'status'} =~ /SSH=1/) {
                $out = `cat /tmp/$node.tracing | ssh $::SUDOER\@$node "cat > /tmp/$node.tracing"`;
            }
            elsif ($propVals->{'status'} =~ /IUCV=1/) {

                #$cmd = "$::SUDO cat /tmp/$node.tracing | ssh $::SUDOER\@$node cat > /tmp/$node.tracing";
                $cmd = "file_transport /tmp/$node.tracing  /tmp/$node.tracing";
                $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    return;
                }
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: Not set communicate type.");
                return;
            }


            #$out = `ssh $::SUDOER\@$node "mv /tmp/$node.tracing $srcLog"`;
            $cmd = "$::SUDO mv /tmp/$node.tracing $srcLog";
            $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }

            $out = `rm -rf /tmp/$node.tracing`;
        }

        xCAT::zvmUtils->printLn($callback, "$node: Setting event logging options... Done");
        return;
    }

    # Default log location is /install/logs
    if (!$tgtLog) {
        my @entries = xCAT::TableUtils->get_site_attribute("installdir");
        my $install = $entries[0];

        $tgtLog = "$install/logs/";
        $out    = `mkdir -p $tgtLog`;
    }

    # Copy over event log onto xCAT
    xCAT::zvmUtils->printLn($callback, "$node: Retrieving event log ($srcLog)");
    if ($mn) {
        if (!(`test -e $srcLog && echo Exists`)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Specified log does not exist");
            return;
        }

        $out = `cp $srcLog $tgtLog`;
    } else {

        #if (!(`ssh $::SUDOER\@$node "test -e $srcLog && echo Exists"`)) {
        my $cmd = "$::SUDO test -e $srcLog && echo Exists";
        $out = xCAT::zvmUtils->execcmdonVM($::SUDOER, $node, $cmd, $callback);
        if (xCAT::zvmUtils->checkOutput($out) == -1) {
            return;
        }

        if (!($out)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Specified log does not exist");
            return;
        }

        # ???? Must have SSH key to do the copy
        $out = `scp $::SUDOER\@$node:$srcLog $tgtLog`;
    }

    if (-e $tgtLog) {
        xCAT::zvmUtils->printLn($callback, "$node: Log copied to $tgtLog");
        $out = `chmod -R 644 $tgtLog/*`;
    } else {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Failed to copy log");
    }
}

#-------------------------------------------------------

=head3   imageCapture

    Description : Capture a disk image from a Linux system on z/VM.
    Arguments   : Node
                  OS
                  Archictecture
                  Specified provisioning method type
                  Profile
                  Device information
                  Compression level: 0 - none, 1 thru 9 - gzip compression level
    Returns     : Nothing, errors returned in $callback
    Example     : imageCapture( $callback, $node, $os, $arch, $type, $profile, $osimg, $device, $comp );

=cut

#-------------------------------------------------------
sub imageCapture {
    my ($class, $callback, $node, $os, $arch, $type, $profile, $osimg, $device, $comp) = @_;
    my $rc;
    my $out = '';
    my $outmsg;
    my $reason = "";
    my $provMethod;
    my $compParm = "";
    my $cmd      = '';

    xCAT::zvmUtils->printSyslog("imageCapture() node:$node os:$os arch:$arch type:$type profile:$profile osimg:$osimg device:$device comp:$comp");

    # Verify required properties are defined
    if (!defined($os) || !defined($arch) || !defined($profile)) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) One or more of the required properties is not specified: os version, architecture or profile");
        return;
    }

    if (defined($type)) {
        $provMethod = $type;
    } else {

        # Type operand was not specified on command, therefore need to get provmethod from the nodetype table.
        my $nodetypetab = xCAT::Table->new("nodetype");
        my $ref_nodetype = $nodetypetab->getNodeAttribs($node, ['provmethod']);
        $provMethod = $ref_nodetype->{provmethod};
        if (!defined($provMethod)) {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) provmethod property is not specified in the nodetype table");
            return;
        }
    }

    # Ensure provmethod is one of the supported methods
    if (($provMethod ne 'sysclone') && ($provMethod ne 'netboot')) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) provmethod property is not 'netboot' or 'sysclone'");
        return;
    }

    # Ensure the architecture property is 's390x'
    if ($arch ne 's390x') {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Architecture was $arch instead of 's390x'. 's390x' will be used instead of the specified value.");
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

    # Process ID for xfork()
    my $pid;

    # Child process IDs
    my @children;

    # Get node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $node, @propNames);

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Missing node HCP");
        return;
    }

    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($sudoer, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;

    # Get capture target's user ID
    my $targetUserId = $propVals->{'userid'};
    $targetUserId =~ tr/a-z/A-Z/;

    # Get node properties from 'hosts' table
    @propNames = ('ip', 'hostnames');
    $propVals = xCAT::zvmUtils->getNodeProps('hosts', $node, @propNames);

    # Determine the disks to be captured.
    my $vaddr;
    my @vaddrList;

    if ($provMethod eq 'netboot') {

        # Check if node is pingable
        my $ping = xCAT::zvmUtils->pingNode($node);
        if ($ping eq "noping") {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Host is unreachable");
            return;
        }

        my $devName;

        # Set the default is device option was specified without any parameters.
        if (!$device) {
            $devName = "/dev/root";
        }

        # Obtain the device number from the target system.
        if ($devName eq '/dev/root') {

            # Determine which Linux device is associated with the root directory
            #$out = `ssh $sudoer\@$node $sudo 'cat /proc/cmdline | tr " " "\\n" | grep -a "^root=" | cut -c6-'`;
            $cmd = "$::SUDO" . ' cat /proc/cmdline | tr " " "\\n"';
            $out = xCAT::zvmUtils->execcmdonVM($sudoer, $node, $cmd, $callback);
            if (xCAT::zvmUtils->checkOutput($out) == -1) {
                return;
            }
            $out = `echo "$out" | egrep -a -i "^root=" | cut '-c6-'`;

            my $rootDev = '';
            if ($out) {
                if ($out =~ m/^UUID=/i) {
                    $rootDev = "/dev/disk/by-uuid/" . substr($out, 5);
                }
                elsif ($out =~ m/^LABEL=/i) {
                    $rootDev = "/dev/disk/by-label/" . substr($out, 6);
                }
                elsif ($out =~ /mapper/) {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Capturing a disk with root filesystem on logical volume is not supported");
                    return;
                } else {
                    $rootDev = $out;
                }

                #$out = `ssh $sudoer\@$node $sudo "readlink -f $rootDev 2>&1"`;
                $cmd = "$::SUDO readlink -f $rootDev 2>&1";
                $out = xCAT::zvmUtils->execcmdonVM($sudoer, $node, $cmd, $callback);
                if (xCAT::zvmUtils->checkOutput($out) == -1) {
                    return;
                }


                if ($rc != 0) {
                    xCAT::zvmUtils->printSyslog("imageCapture() failed to execute readlink -f $rootDev on capture source vm rc: $rc, out: $out");
                    xCAT::zvmUtils->printLn($callback, "$node: imageCapture() failed to execute readlink to locate the root device rc: $rc, out: $out");
                    return;
                }

                if ($out) {
                    $devName = substr($out, 5);
                    $devName =~ s/\s+$//;
                    $devName =~ s/\d+$//;
                } else {
                    xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to locate the root device from $out");
                    return;
                }
            } else {
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to get useful info from /proc/cmdline to locate the device associated with the root directory on capture source vm");
                return;
            }
        } else {
            $devName = substr $devName, 5;
        }

        $vaddr = xCAT::zvmUtils->getDeviceNodeAddr($sudoer, $node, $devName);
        if ($vaddr) {
            push(@vaddrList, $vaddr);
        } else {
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable determine the device being captured");
            return 0;
        }

    } else {

        # provmethod is 'sysclone'

        # Get the list of mdisks
        my @srcDisks = xCAT::zvmUtils->getMdisks($callback, $sudoer, $node);
        if (xCAT::zvmUtils->checkOutput($srcDisks[0]) == -1) {
            xCAT::zvmUtils->printLn($callback, "$srcDisks[0]");
            return;
        }
        foreach (@srcDisks) {

            # Get disk address
            my @words = split(' ', $_);
            $vaddr = $words[1];
            my $diskType = $words[2];

            if ($diskType eq 'FB-512') {

                # We do not capture vdisks but we will capture minidisks, dedicated disks and tdisks.
                next;
            }

            # Add 0 in front if address length is less than 4
            while (length($vaddr) < 4) {
                $vaddr = '0' . $vaddr;
            }
            push(@vaddrList, $vaddr);
        }
    }

    # Set the compression invocation parameter if compression was specified.
    # Note: Some older zHCP do not support compression specification.
    if (defined($comp)) {

        # Determine if zHCP supports the compression property.
        $out = `ssh -o ConnectTimeout=30 $sudoer\@$hcp "$sudo $dir/creatediskimage -V"`;
        $rc = $?;

        if ($rc == 65280) {
            xCAT::zvmUtils->printSyslog("imageCapture() Unable to communicate with zHCP agent");
            xCAT::zvmUtils->printLn($callback, "$node: imageCapture() is unable to communicate with zHCP agent: $hcp");
            return;
        }

        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($rc != -1) {

            # No error.  It is probably that the zHCP supports compression.
            # We will check the version to see if it is high enough.  Any error
            # or too low of a version means that we should ignore the compression
            # operand in the future creatediskimage call.
            # Process the version output.
            my @outLn = split("\n", $out);
            if ($#outLn == 0) {

                # Only a single line of output should come back from a compatable zHCP.
                my @versionInfo = split('\.', $out);
                if ($versionInfo[0] >= 2) {

                    # zHCP supports compression specification.
                    if (($comp =~ /[\d]/) and (length($comp) == 1)) {
                        $compParm = "--compression $comp";
                    } else {
                        xCAT::zvmUtils->printLn($callback, "$node: (Error) compression property is not a single digit from 0 to 9");
                        return;
                    }
                }
            }
        }
    }

    # Shutdown and logoff the virtual machine so that its disks are stable for the capture step.
    xCAT::zvmUtils->printSyslog("imageCapture() Shutting down $node prior to disk capture");

    #$out = `ssh -o ConnectTimeout=10 $node "shutdown -h now"`;
    $cmd = "$::SUDO shutdown -h now";
    $out = xCAT::zvmUtils->execcmdonVM($sudoer, $node, $cmd);

    sleep(15);   # Wait 15 seconds to let shutdown start before logging user off

    # If the OS is not shutdown and the machine is enabled for shutdown signals
    # then deactivate will cause CP to send the shutdown signal and
    # wait an additional (z/VM installation configurable) time before forcing
    # the virtual machine off the z/VM system.
    xCAT::zvmUtils->printSyslog("$sudo $dir/smcli Image_Deactivate -T $targetUserId");
    $out = `ssh $sudoer\@$hcp "$sudo $dir/smcli Image_Deactivate -T $targetUserId"`;
    $rc = $? >> 8;
    if ($rc == 255) {
        xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
        xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
        return;
    }
    $rc = xCAT::zvmUtils->checkOutput($out);
    if ($out =~ m/Return Code: 200/i) {
        if ($out =~ m/Reason Code: 12/i) {
            $out = "$targetUserId already logged off.";
            $rc  = 0;
        } elsif ($out =~ m/Reason Code: 16/i) {
            $out = "$targetUserId in process of logging off.";
            $rc  = 0;
        }
    }
    if ($rc == -1) {
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $targetUserId output: $out");
        xCAT::zvmUtils->printLn($callback, "$node: $out");
        return;
    }
    xCAT::zvmUtils->printSyslog("imageCapture() smcli response: $out");

    # Wait (checking every 15 seconds) until user is finally logged off or maximum wait time has elapsed
    my $max = 0;
    $out = `ssh $sudoer\@$hcp "$sudo /sbin/vmcp q user $targetUserId 2>/dev/null"`;
    ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $sudoer\@$hcp \"$sudo /sbin/vmcp q user $targetUserId 2>/dev/null\"", $hcp, "imageCapture", $out, $node);
    if ($rc != 0) {
        xCAT::zvmUtils->printLn($callback, "$outmsg");
        return;
    }
    $out = `echo "$out" | egrep -a -i "HCPCQU045E"`;
    while (!$out && $max < 60) {
        sleep(15);    # Wait 15 seconds
        $max++;
        $out = `ssh $sudoer\@$hcp "$sudo /sbin/vmcp q user $targetUserId 2>/dev/null"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $sudoer\@$hcp \"$sudo /sbin/vmcp q user $targetUserId 2>/dev/null\"", $hcp, "imageCapture", $out, $node);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $out = `echo "$out" | egrep -a -i "HCPCQU045E"`;
    }
    my $totalMinutes = $max * 15 / 60;
    if ($out) {

        # Target system was successfully logged off
        xCAT::zvmUtils->printSyslog("imageCapture() Target system was logged off after $totalMinutes minutes");
    } else {

        # Target system was not logged off
        xCAT::zvmUtils->printSyslog("imageCapture() Target system was not logged off after $totalMinutes minutes");
        xCAT::zvmUtils->printSyslog("$sudo $dir/smcli Image_Deactivate -T $targetUserId -f IMMED");
        $out = `ssh $sudoer\@$hcp "$sudo $dir/smcli Image_Deactivate -T $targetUserId -f IMMED"`;
        $rc = $? >> 8;
        if ($rc == 255) {
            xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $hcp");
            xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $hcp");
            return;
        }
        $rc = xCAT::zvmUtils->checkOutput($out);
        if ($out =~ m/Return Code: 200/i) {
            if ($out =~ m/Reason Code: 12/i) {
                $out = "$targetUserId already logged off.";
                $rc  = 0;
            } elsif ($out =~ m/Reason Code: 16/i) {
                $out = "$targetUserId in process of logging off.";
                $rc  = 0;
            }
        }
        if ($rc == -1) {
            xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $targetUserId output: $out");
            xCAT::zvmUtils->printLn($callback, "$node: $out");
            return;
        }
        xCAT::zvmUtils->printSyslog("imageCapture() smcli response: $out");
        sleep(15);    # Wait 15 seconds
    }

    xCAT::zvmUtils->printSyslog("imageCapture() Preparing the staging directory");

    # Create the staging area location for the image
    my $stagingImgDir = "$installRoot/staging/$os/$arch/$profile";
    if (-d $stagingImgDir) {
        rmtree $stagingImgDir;
    }
    mkpath($stagingImgDir);

    # Prepare the staging mount point on zHCP, if they need to be established.
    my $remoteStagingDir;
    $rc = xCAT::zvmUtils->establishMount($callback, $sudoer, $sudo, $hcp, $installRoot, "staging", "rw", \$remoteStagingDir);
    if ($rc) {

        # Mount failed
        rmtree "$stagingImgDir";
        return;
    }

    xCAT::zvmUtils->printLn($callback, "$node: Capturing the image using zHCP node");

    # Drive each device capture separately.  Up to 10 at a time.
    # Each capture request to zHCP is driven from a child process.
    foreach my $vaddr (@vaddrList) {
        $pid = xCAT::Utils->xfork();

        # Parent process
        if ($pid) {
            push(@children, $pid);
        }

        # Child process.
        elsif ($pid == 0) {

            # Drive the capture on the zHCP node
            xCAT::zvmUtils->printSyslog("imageCapture() creatediskimage $targetUserId $vaddr $remoteStagingDir/$os/$arch/$profile/${vaddr}.img $compParm");
            $out = `ssh $sudoer\@$hcp "$sudo $dir/creatediskimage $targetUserId $vaddr $remoteStagingDir/$os/$arch/$profile/${vaddr}.img $compParm"`;
            $rc = $?;
            xCAT::zvmUtils->printLn($callback, "$node: $out");

            # Check for script errors
            my $reasonString = "";
            $rc = xCAT::zvmUtils->checkOutputExtractReason($out, \$reasonString);
            if ($rc != 0) {
                $reason = "Reason: $reasonString";
                xCAT::zvmUtils->printSyslog("imageCapture() creatediskimage of $targetUserId $vaddr failed. $reason");
                xCAT::zvmUtils->printLn($callback, "$node: (Error) Image capture of $targetUserId $vaddr failed on the zHCP node. $reason");

                # Create a "FAILED" file to indicate the failure.
                if (!open FILE, '>' . "$stagingImgDir/FAILED") {

                    # if we can't open it then we log the problem.
                    xCAT::zvmUtils->printSyslog("imageCapture() unable to create a 'FAILED' file.");
                }
            }

            # Exit the child process
            exit(0);
        }

        else {
            # Ran out of resources
            # Create a "FAILED" file to indicate the failure.
            if (!open FILE, '>' . "$stagingImgDir/FAILED") {

                # if we can't open it then we log the problem.
                xCAT::zvmUtils->printSyslog("imageCapture() unable to create a 'FAILED' file.");
            }

            $reason = ". Reason: Could not fork\n";
            last;
        }

        # Handle 10 nodes at a time, else you will get errors
        if (!(@children % 10)) {

            # Wait for all processes to end
            foreach (@children) {
                waitpid($_, 0);
            }

            # Clear children
            @children = ();
        }
    }    # End of foreach

    # If any children remain, then wait for them to complete.
    foreach $pid (@children) {
        xCAT::zvmUtils->printSyslog("imageCapture() Waiting for child process $pid to complete");
        waitpid($pid, 0);
    }

    # if the capture failed then clean up and return
    if (-e "$stagingImgDir/FAILED") {
        xCAT::zvmUtils->printSyslog("imageCapture() 'FAILED' file found.  Removing staging directory.");
        rmtree "$stagingImgDir";
        return;
    }

    # Now that all image files have been successfully created, move them to the deployable directory.
    my $imageName    = "$os-$arch-$provMethod-$profile";
    my $deployImgDir = "$installRoot/$provMethod/$os/$arch/$profile";

    xCAT::zvmUtils->printLn($callback, "$node: Moving the image files to the deployable directory: $deployImgDir");

    my @stagedFiles = glob "$stagingImgDir/*.img";
    if (!@stagedFiles) {
        rmtree "$stagingImgDir";
        xCAT::zvmUtils->printLn($callback, "$node: (Error) No image files were created");
        return 0;
    }

    if (-e "$deployImgDir") {
        $out = `/bin/rm -f $deployImgDir/*.img`;
    } else {
        mkpath($deployImgDir);
    }

    foreach my $oldFile (@stagedFiles) {
        $rc = move($oldFile, $deployImgDir);
        $reason = $!;
        if ($rc == 0) {

            # Move failed
            rmtree "$stagingImgDir";
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not move $oldFile to $deployImgDir. $reason");
            return;
        }
    }

    # For sysclone, obtain the userid/identity entry for the user and move it to the deploy image directory.
    if ($provMethod eq 'sysclone') {
        $out = `ssh $sudoer\@$hcp "$sudo $dir/smcli Image_Query_DM -T $targetUserId | sed '\$d' > $remoteStagingDir/$os/$arch/$profile/$targetUserId.direct"`;

        # Move the direct file to the deploy image directory
        $rc = move("$stagingImgDir/$targetUserId.direct", $deployImgDir);
        $reason = $!;
        if ($rc == 0) {

            # Move failed
            rmtree "$stagingImgDir";
            xCAT::zvmUtils->printLn($callback, "$node: (Error) Could not move $stagingImgDir/$targetUserId.direct to $deployImgDir. $reason");
            return;
        }
    }

    # Remove the staging directory and files
    rmtree "$stagingImgDir";

    xCAT::zvmUtils->printSyslog("imageCapture() Updating the osimage table");

    # Update osimage table
    my $osTab = xCAT::Table->new('osimage', -create => 1, -autocommit => 0);
    my %keyHash;

    unless ($osTab) {
        xCAT::zvmUtils->printLn($callback, "$node: (Error) Unable to open table 'osimage'");
        return;
    }

    $keyHash{provmethod} = $provMethod;
    $keyHash{profile}    = $profile;
    $keyHash{osvers}     = $os;
    $keyHash{osarch}     = $arch;
    $keyHash{imagetype}  = 'linux';
    $keyHash{osname}     = 'Linux';
    $keyHash{imagename}  = $imageName;

    $osTab->setAttribs({ imagename => $imageName }, \%keyHash);
    $osTab->commit;

    xCAT::zvmUtils->printSyslog("imageCapture() Updating the linuximage table");

    # Update linuximage table
    my $linuxTab = xCAT::Table->new('linuximage', -create => 1, -autocommit => 0);

    %keyHash             = ();
    $keyHash{imagename}  = $imageName;
    $keyHash{rootimgdir} = $deployImgDir;

    $linuxTab->setAttribs({ imagename => $imageName }, \%keyHash);
    $linuxTab->commit;

    xCAT::zvmUtils->printLn($callback, "$node: Completed capturing the image($imageName) and stored at $deployImgDir");

    return;
}

#-------------------------------------------------------

=head3   specialcloneVM

    Description : Do a special clone of virtual server
    Arguments   :   callback
                    Node(s) array
                    args with: maybe disk password, imagename
                    clone info hash, can be empty
    Returns     : Nothing
    Example     : cloneVM($callback, \@targetNodes, $args, \%cloneInfoHash);

=cut

#-------------------------------------------------------
sub specialcloneVM {

    # Get inputs
    my ($callback, $nodes, $args, $cloneInfoHash) = @_;

    # Get nodes
    my @nodes     = @$nodes;
    my $nodeCount = @nodes;

    my %cloneInfo = %$cloneInfoHash;

    my $sourceId;
    my $srcOS = "unknown";

    my $sudo = "sudo";
    my $user = $::SUDOER;

    # Return code for each command
    my $rc;
    my $out;
    my $i;

    # Child process IDs
    my @children;

    # Process ID for xfork()
    my $pid;

    # Directory where executables are
    my $dir = '/opt/zhcp/bin';

    if ($user eq "root") {
        $sudo = "";
    }

    # Do some parameter checking
    if (defined $cloneInfo{'CLONE_FROM'}) {
        $sourceId = $cloneInfo{'CLONE_FROM'};
        xCAT::zvmUtils->printSyslog("Clone of <@nodes> count:$nodeCount to be done from: $sourceId\n");
    } else {
        xCAT::zvmUtils->printLn($callback, "(Error) CLONE_FROM value is missing from DOCLONE COPY on 193.");
        return;
    }


    if ($nodeCount < 1) {
        xCAT::zvmUtils->printLn($callback, "(Error) Missing target nodes to clone.");
        return;
    }

    # Verify that all the target nodes use the same zhcp
    my $tgtFirstNode = $nodes[0];
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $tgtFirstNode, @propNames);

    # Get target zhcp, all nodes must use the same one, and the source userid must be
    # also on that zhcp
    my $tgtZhcp        = $propVals->{'hcp'};
    my $tgtFirstUserid = $propVals->{'userid'};
    my $founderror     = 0;

    foreach (@nodes) {
        $propVals = xCAT::zvmUtils->getNodeProps('zvm', $_, @propNames);
        my $temp       = $propVals->{'hcp'};
        my $tempUserid = $propVals->{'userid'};
        if ($temp ne $tgtZhcp) {
            $founderror = 1;
            xCAT::zvmUtils->printLn($callback, "(Error) node $_ does not match zhcp $tgtZhcp.");
        }
        if (length($tempUserid) < 1) {
            $founderror = 1;
            xCAT::zvmUtils->printLn($callback, "(Error) node $_ does not have a zVM userid.");
        }
    }
    if ($founderror == 1) { return; }

    # Get the source userid directory using original call.
    xCAT::zvmUtils->printSyslog("Executing: ssh $::SUDOER\@$tgtZhcp $::SUDO $dir/smcli Image_Query_DM -T $sourceId | sed '\$d'\n");
    $out = `ssh $::SUDOER\@$tgtZhcp "$::SUDO $dir/smcli Image_Query_DM -T $sourceId" | sed '\$d'`;
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        xCAT::zvmUtils->printLn($callback, "(Error) Did not get the $sourceId directory. Return output was: $out.");
        return;
    }

    my @sourceDirectory = split('\n', $out);
    my $sourceMdisks = `echo "$out" | grep -a -E -i "MDISK"`; # maybe not use this?
    $sourceMdisks = xCAT::zvmUtils->trimStr($sourceMdisks);

    my $sourceLinks = `echo "$out" | grep -a -E -i "LINK"`;
    $sourceLinks = xCAT::zvmUtils->trimStr($sourceLinks);

    my $sourceWithoutMdisks = `echo "$out" | grep -a -E -i -v "MDISK"`;
    $sourceWithoutMdisks = xCAT::zvmUtils->trimStr($sourceWithoutMdisks);

    # Get the available mini disks using Image Definition in case this is SSI
    # Output is similar to:
    #   MDISK=VDEV=0100 DEVTYPE=3390 START=0001 COUNT=10016 VOLID=EMC2C4 MODE=MR
    $out = `ssh $::SUDOER\@$tgtZhcp "$::SUDO $::DIR/smcli Image_Definition_Query_DM -T $sourceId -k MDISK"`;
    if (xCAT::zvmUtils->checkOutput($out) == -1) {
        xCAT::zvmUtils->printLn($callback, "(Error) Did not get the $sourceId mini disks. Return output was: $out.");
        return;
    }

    my @lines     = split('\n', $out);
    my @srcMdisks = ();
    my $foundECKD = 0;
    my $foundFBA  = 0;

    # Loop through each mini disk line, make a hash table and add it to the disk array
    for ($i = 0 ; $i < @lines ; $i++) {

        # remove the MDISK= from the line
        $lines[$i] =~ s/MDISK=//g;

        my %hash = ($lines[$i] =~ m/(\w+)\s*=\s*(\w+)/g);

        #foreach (keys%hash) {
        #    xCAT::zvmUtils->printSyslog("Mdisk key: $_ value: $hash{$_}\n");
        #}
        if ($hash{'DEVTYPE'} eq '3390') {
            $foundECKD = 1;
        } else {
            $foundFBA = 1;
        }
        push @srcMdisks, \%hash;
    }

    # Check for missing disk pool
    if ($foundFBA && !(defined $cloneInfo{'FBA_POOL'})) {
        xCAT::zvmUtils->printLn($callback, "(Error) FBA disk was found but no FBA_POOL was defined in DOCLONE COPY.");
        xCAT::zvmUtils->printSyslog("(Error) FBA disk was found but no FBA_POOL was defined in DOCLONE COPY.\n");
        return;
    }

    # Check for missing disk pool
    if ($foundECKD && !(defined $cloneInfo{'ECKD_POOL'})) {
        xCAT::zvmUtils->printLn($callback, "(Error) ECKD disk was found but no ECKD_POOL was defined in DOCLONE COPY.");
        xCAT::zvmUtils->printSyslog("(Error) ECKD disk was found but no ECKD_POOL was defined in DOCLONE COPY.\n");
        return;
    }

    # Update the zvm table status column to indicate the special processing.
    foreach (@nodes) {
        my %propHash = ();
        %propHash = ('status' => 'CLONE_ONLY=1;CLONING=1;');
        xCAT::zvmUtils->setNodeProps('zvm', $_, \%propHash);
        %propHash = ();
        %propHash = ('disable' => '1');
        xCAT::zvmUtils->setNodeProps('hosts', $_, \%propHash);
        xCAT::zvmUtils->setNodeProps('mac',   $_, \%propHash);

    }

    #*** Link source disks
    # Hash table of source disk addresses to linked address
    my %srcLinkAddr;
    my $addr;
    my $linkAddr;

    for my $rowdisk (@srcMdisks) {
        my %rowhash = %$rowdisk;

        # Get disk address from the array entry hash
        $addr = $rowhash{'VDEV'};

        # Add 0 in front if address length is less than 4
        while (length($addr) < 4) {
            $addr = '0' . $addr;
        }

        # Save any updates to length of addr
        $rowhash{'VDEV'} = $addr;

        # If source disk is not linked
        my $try = 5;
        while ($try > 0) {

            # New disk address
            $linkAddr = $addr + 1000;

            # Check if new disk address is used (source)
            $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $tgtZhcp, $linkAddr);

            # If disk address is used (source)
            while ($rc == 0) {

                # Generate a new disk address
                # Sleep 5 seconds to let existing disk appear
                sleep(5);
                $linkAddr = $linkAddr + 1;
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $tgtZhcp, $linkAddr);
            }

            $srcLinkAddr{$addr} = $linkAddr;

            # Link source disk to HCP
            xCAT::zvmUtils->printLn($callback, "Linking source disk ($addr) as ($linkAddr)");
            $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$tgtZhcp "$::SUDO /sbin/vmcp link $sourceId $addr $linkAddr RR"`;

            if ($out =~ m/not linked/i) {
                xCAT::zvmUtils->printSyslog("Retry linking source disk ($addr) as ($linkAddr)\n");
                xCAT::zvmUtils->printLn($callback, "Retry linking source disk ($addr) as ($linkAddr)");

                # Do nothing
            } else {
                last;
            }

            $try = $try - 1;

            # Wait before next try
            sleep(5);
        }    # End of while ( $try > 0 )

        # If source disk is not linked
        if ($out =~ m/not linked/i) {
            xCAT::zvmUtils->printSyslog("Failed to link source disk $addr from userid $sourceId.\n");
            xCAT::zvmUtils->printLn($callback, "Failed to link source disk $addr from userid $sourceId.");

            # Exit
            return;
        }

        # Enable source disk
        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $tgtZhcp, "-e", $linkAddr);
    }    # End of foreach (@srcMdisks)


    # Save the source directory without any mdisk statements, use temp file name
    my $srcUserEntry = `/bin/mktemp /tmp/$sourceId.txtXXXXXXXX`;
    if ($?) {
        xCAT::zvmUtils->printLn($callback, "Failed to create temp file using pattern /tmp/$sourceId.txtXXXXXXXX");
        xCAT::zvmUtils->printSyslog("Failed to create temp file using pattern /tmp/$sourceId.txtXXXXXXXX");
        return;
    }
    chomp($srcUserEntry);    # need to remove line ends
       #xCAT::zvmUtils->printSyslog("Created temp file called ($srcUserEntry)");

    # Create a file to save output
    open(DIRENTRY, ">$srcUserEntry");
    @lines = split('\n', $sourceWithoutMdisks);
    foreach (@lines) {

        # Trim line
        $_ = xCAT::zvmUtils->trimStr($_);

        # Write directory entry into file
        print DIRENTRY "$_\n";
    }
    close(DIRENTRY);

    # Turn off source node
    xCAT::zvmUtils->printSyslog("Calling smcli Image_Deactivate -T $sourceId (On clone for @nodes)");
    $out = `ssh $::SUDOER\@$tgtZhcp "$::SUDO $::DIR/smcli Image_Deactivate -T $sourceId"`;
    $rc = $? >> 8;
    if ($rc == 255) {
        xCAT::zvmUtils->printSyslog("(Error) Failed to communicate with the zhcp system: $tgtZhcp");
        xCAT::zvmUtils->printLn($callback, "(Error) Failed to communicate with the zhcp system: $tgtZhcp");
        return;
    }
    $rc = xCAT::zvmUtils->checkOutput($out);
    if ($out =~ m/Return Code: 200/i) {
        if ($out =~ m/Reason Code: 12/i) {
            $out = "$sourceId already logged off.";
            $rc  = 0;
        } elsif ($out =~ m/Reason Code: 16/i) {
            $out = "$sourceId in process of logging off.";
            $rc  = 0;
        }
    }
    if ($rc == -1) {
        xCAT::zvmUtils->printSyslog("smcli Image_Deactivate $sourceId output: $out");
        xCAT::zvmUtils->printLn($callback, "$out");
        return;
    }
    xCAT::zvmUtils->printSyslog("$out");

    #*** Clone source node ***
    foreach (@nodes) {
        $pid = xCAT::Utils->xfork();

        # Parent process
        if ($pid) {
            push(@children, $pid);
        }

        # Child process
        elsif ($pid == 0) {
            specialClone($callback, $_, $args, \@srcMdisks, \%srcLinkAddr, \%cloneInfo, $sourceId, $srcUserEntry);

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
        if (!(@children % 4)) {

            # Wait for all processes to end
            foreach (@children) {
                waitpid($_, 0);
            }

            # Clear children
            @children = ();
        }
    }    # End of foreach

    # Handle the remaining nodes
    # Wait for all processes to end
    foreach (@children) {
        waitpid($_, 0);
    }

    # Remove source user entry
    $out = `rm $srcUserEntry`;


    #*** Detatch source disks ***

    for $addr (keys %srcLinkAddr) {

        $linkAddr = $srcLinkAddr{$addr};


        # Disable and detatch source disk

        $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $tgtZhcp, "-d", $linkAddr);

        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$tgtZhcp "$::SUDO /sbin/vmcp det $linkAddr"`;


        xCAT::zvmUtils->printLn($callback, "Detatching source disk ($addr) at ($linkAddr)");

    }


    #*** Done ***

    foreach (@nodes) {

        xCAT::zvmUtils->printLn($callback, "$_: Done");

    }

    return;
}


#-------------------------------------------------------

=head3   specialClone

    Description : Clone a virtual server from a zvm userid
    Arguments   :   Target node
                    args (Disk pool, Disk password (optional))
                    Source disks array of hash
                    Source disk link addresses
                    clone info hash from doclone.txt
                    Source zvm userid
                    Source userid directory file name
    Returns     : Nothing, errors returned in $callback
    Example     : specialClone($callback, $_, $args, \@srcMdisks, \%srcLinkAddr, \%cloneInfoHash, $sourceId, $srcUserEntry);

=cut

#-------------------------------------------------------
sub specialClone {

    # Get inputs
    my (
        $callback, $tgtNode, $args, $srcMdisksRef, $srcLinkAddrRef, $cloneInfoHash, $sourceId, $srcUserEntry) = @_;

    # Get source disks
    my @srcMdisks   = @$srcMdisksRef;
    my %srcLinkAddr = %$srcLinkAddrRef;
    my %cloneInfo   = %$cloneInfoHash;

    # Return code for each command
    my $rc;

    # Disk pools
    my $ECKD_Pool = '';
    my $FBA_Pool  = '';

    my $cmsVDEVs = '';
    if (defined $cloneInfo{'CMS_VDEVS'}) {
        $cmsVDEVs = $cloneInfo{'CMS_VDEVS'};
    }

    # Get the Dirmaint pool information
    if (defined $cloneInfo{'ECKD_POOL'}) {
        $ECKD_Pool = $cloneInfo{'ECKD_POOL'};
    }
    if (defined $cloneInfo{'FBA_POOL'}) {
        $FBA_Pool = $cloneInfo{'FBA_POOL'};
    }

    # Get target node properties from 'zvm' table
    my @propNames = ('hcp', 'userid');
    my $propVals = xCAT::zvmUtils->getNodeProps('zvm', $tgtNode, @propNames);

    # Get node user ID
    my $tgtUserId = $propVals->{'userid'};
    if (!$tgtUserId) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing target user ID");
        return;
    }

    # Capitalize user ID
    $tgtUserId =~ tr/a-z/A-Z/;

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if (!$hcp) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Missing target node HCP");
        return;
    }

    # Get zHCP user ID
    my $hcpUserId = xCAT::zvmCPUtils->getUserId($::SUDOER, $hcp);
    $hcpUserId =~ tr/a-z/A-Z/;

    my $out;
    my $outmsg;
    my @lines;
    my @words;

    # Get disk pool and multi password
    # parameters are in "--key value"
    my $i;
    my %inputs;
    my $argsSize = @{$args};
    for (my $i = 0 ; $i < $argsSize ; $i++) {
        if (($i + 1) < $argsSize) {

            # add to hash array
            $inputs{ $args->[$i] } = $args->[ $i + 1 ];
        }
    }

    # Get multi password
    # It is Ok not have a password
    my $tgtPw = "''";
    if ($inputs{"--password"}) {
        $tgtPw = $inputs{"--password"};
    }

    # Save user directory entry as /tmp/hostname.txt, e.g. /tmp/gpok3.txt
    # The source user entry is retrieved and passed as parameter in specialCloneVM()
    my $userEntry = "/tmp/$tgtNode.txt";

    # Remove existing user entry if any
    $out = `rm $userEntry`;
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $userEntry"`;

    # Copy user entry of source node
    $out = `cp $srcUserEntry $userEntry`;
    if ($?) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to copy $srcUserEntry to $userEntry");
        xCAT::zvmUtils->printSyslog("$tgtNode: (Error) Failed to copy $srcUserEntry to $userEntry");
        return;
    }
    xCAT::zvmUtils->printSyslog("Copied temp named source <$srcUserEntry> to <$userEntry>");

    # Replace source userID with target userID
    $out = `sed -i -e "s,$sourceId,$tgtUserId,i" $userEntry`;

    # SCP user entry file over to HCP
    my $reasonString    = '';
    my $remoteUserEntry = '';
    $rc = xCAT::zvmUtils->sendFile($::SUDOER, $hcp, $userEntry, $userEntry);
    if ($rc == 0) {
        $remoteUserEntry = $userEntry;
    } else {
        $reasonString = "Unable to send $userEntry to $hcp, SCP rc: $rc";
    }

    #*** Create new virtual server ***
    xCAT::zvmUtils->printLn($callback, "$tgtNode: Creating user directory entry");
    if ($remoteUserEntry ne '') {
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Create_DM -T $tgtUserId -f $remoteUserEntry"`;
        $rc = $? >> 8;
        xCAT::zvmUtils->printSyslog("$tgtNode: Result from smcli Image_Create_DM -T $tgtUserId, rc: $rc, out: $out");

        if ($rc == 0) {
            $rc = xCAT::zvmUtils->checkOutput($out);
            if ($rc != 0) {
                $rc           = -1;
                $reasonString = "Image_Create_DM returned $out";
            }
        } elsif ($rc == 255) {
            $reasonString = "Unable to communicate with $hcp";
        } else {
            $reasonString = "Image_Create_DM returned rc: $rc, out: $out";
        }
    }

    # Remove user entry
    $out = `rm $userEntry`;
    if ($remoteUserEntry ne '') {
        $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO rm $remoteUserEntry"`;
    }

    # Exit on bad output
    if ($rc != 0) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Could not create user entry.  $reasonString");
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Verify that the node's zHCP and its zVM's SMAPI are both online");
        return;
    }

    # Load VMCP module on HCP and source node
    $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "/sbin/modprobe vmcp"`;

    #*** Add MDisk to target user entry ***
    my $addr;
    my @tgtDisks;
    my $type;
    my $mode;
    my $disksize;
    my $try;
    for my $rowdisk (@srcMdisks) {
        my %rowhash = %$rowdisk;

        # Get disk address from the array entry hash
        $addr = $rowhash{'VDEV'};

        push(@tgtDisks, $addr);

        $type     = $rowhash{'DEVTYPE'};
        $disksize = $rowhash{'COUNT'};

        if (defined $rowhash{'MODE'}) {
            $mode = $rowhash{'MODE'};
        } else {
            $mode = "MR";
        }

        # Add ECKD disk
        if ($type eq '3390') {

            $try = 5;
            while ($try > 0) {

                # Add ECKD disk
                if ($try > 4) {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Adding minidisk ($addr)");
                } else {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)");
                }
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 3390 -a AUTOG -r $ECKD_Pool -u 1 -z $disksize -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 3390 -a AUTOG -r $ECKD_Pool -u 1 -z $disksize -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw");
                xCAT::zvmUtils->printSyslog("$out");
                xCAT::zvmUtils->printLn($callback, "$out");

                # Check output
                $rc = xCAT::zvmUtils->checkOutput($out);
                if ($rc == -1) {

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
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Could not add minidisk ($addr) $out");
                return;
            }
        }    # End of if ( $type eq '3390' )

        # Add FBA disk
        elsif ($type eq '9336') {

            # Get disk size (blocks)
            my $blkSize = '512';

            $try = 10;
            while ($try > 0) {

                # Add FBA disk
                if ($try > 9) {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Adding minidisk ($addr)");
                } else {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)");
                }
                $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 9336 -a AUTOG -r $FBA_Pool -u 1 -z $disksize -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw"`;
                xCAT::zvmUtils->printSyslog("smcli Image_Disk_Create_DM -T $tgtUserId -v $addr -t 9336 -a AUTOG -r $FBA_Pool -u 1 -z $disksize -m $mode -f 1 -R $tgtPw -W $tgtPw -M $tgtPw");
                xCAT::zvmUtils->printSyslog("$out");
                xCAT::zvmUtils->printLn($callback, "$out");

                # Check output
                $rc = xCAT::zvmUtils->checkOutput($out);
                if ($rc == -1) {

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
            if ($rc == -1) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Could not add minidisk ($addr) $out");
                return;
            }
        }    # End of elsif ( $type eq '9336' )
    }

    # Check if the number of disks in target user entry
    # is equal to the number of disks added
    my @disks;
    $try = 10;
    xCAT::zvmUtils->printLn($callback, "$tgtNode: Disks added (@tgtDisks). Checking directory for those disks...");
    while ($try > 0) {

        # Get disks within user entry
        xCAT::zvmUtils->printSyslog("smcli Image_Query_DM -T $tgtUserId");
        $out = `ssh $::SUDOER\@$hcp "$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId"`;
        ($rc, $outmsg) = xCAT::zvmUtils->checkSSH_Rc($?, "ssh $::SUDOER\@$hcp \"$::SUDO $::DIR/smcli Image_Query_DM -T $tgtUserId\"", $hcp, "specialClone", $out, $tgtNode);
        if ($rc != 0) {
            xCAT::zvmUtils->printLn($callback, "$outmsg");
            return;
        }
        $out = `echo "$out" | sed '\$d' | grep -a -i "MDISK"`;
        xCAT::zvmUtils->printSyslog("$out");
        @disks = split('\n', $out);

        if (@disks != @tgtDisks) {
            $try = $try - 1;

            # Wait before trying again
            sleep(5);
        } else {
            last;
        }
    }

    # Exit if all disks are not present
    if (@disks != @tgtDisks) {
        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) After 50 seconds, all disks not present in target directory.");
        xCAT::zvmUtils->printSyslog("$tgtNode: (Error) After 50 seconds, all disks not present in target directory.");

        xCAT::zvmUtils->printLn($callback, "$tgtNode: Disks found in $sourceId source directory (@tgtDisks). Disks found in $tgtUserId target directory (@disks)");
        xCAT::zvmUtils->printSyslog("$tgtNode: Disks found in $sourceId + source directory (@tgtDisks). Disks found in $tgtUserId target directory (@disks)");

        xCAT::zvmUtils->printLn($callback, "$tgtNode: (Solution) Verify disk pool has free disks and that directory updates are working");
        return;
    }

    #**  * Link, format, and copy source disks ***
    my $srcAddr;
    my $srcHcpLinkAddr;
    my $mdiskAddr;
    my $tgtAddr;
    my $srcDevNode;
    my $tgtDevNode;
    my $tgtDiskType;

    # source and target disks will be same type and size
    for my $rowdisk (@srcMdisks) {
        my %rowhash = %$rowdisk;

        # Get disk address from the array entry hash
        $mdiskAddr   = $rowhash{'VDEV'};
        $tgtDiskType = $rowhash{'DEVTYPE'};

        #*** Try to use SMAPI flashcopy first if ECKD  ***
        # Otherwise link the target disks and if ECKD, try CP Flashcopy. If
        # CP flashcopy does not work or not ECKD; use Linux DD
        my $ddCopy             = 0;
        my $cpFlashcopy        = 1;
        my $smapiFlashCopyDone = 0;

        if ($tgtDiskType eq '3390') {

            # Try SMAPI FLASHCOPY
            if (xCAT::zvmUtils->smapi4xcat($::SUDOER, $hcp)) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($mdiskAddr) to target disk ($mdiskAddr) using FLASHCOPY");
                xCAT::zvmUtils->printSyslog("$tgtNode: Doing SMAPI flashcopy source disk ($sourceId $mdiskAddr) to target disk ($tgtUserId $mdiskAddr) using FLASHCOPY");
                $out = xCAT::zvmCPUtils->smapiFlashCopy($::SUDOER, $hcp, $sourceId, $mdiskAddr, $tgtUserId, $mdiskAddr);

                # Check if flashcopy completed successfully, or it completed and is asynchronous
                if (($out =~ m/Done/i) or (($out =~ m/Return Code: 592/i) and ($out =~ m/Reason Code: 8888/i))) {
                    chomp($out);
                    xCAT::zvmUtils->printSyslog("$tgtNode: SMAPI flashcopy done. output($out)");
                    $cpFlashcopy        = 0;
                    $smapiFlashCopyDone = 1;
                } else {

                    # Continue to try a Linux format and DD. Put out information message to log and back to caller
                    chomp($out);
                    my $outlen = length($out);
                    xCAT::zvmUtils->printSyslog("$tgtNode: SMAPI Flashcopy did not work, continuing with Linux DD. SMAPI output($outlen bytes):");
                    xCAT::zvmUtils->printSyslog("$tgtNode: $out");

                    # Change any (error) or "failed" to info so that OpenStack does not reject this clone
                    $out =~ s/\(error\)/\(info\)/gi;
                    $out =~ s/failed/info/gi;
                    xCAT::zvmUtils->printLn($callback, "$out");
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: SMAPI Flashcopy did not work, continuing with Linux format and DD.");
                }
            }
        }

        # If SMAPI flashcopy did not work or this is not an ECKD, then link the target disks in write mode
        if (!$smapiFlashCopyDone) {
            $ddCopy = 1;

            #*** Link target disk ***
            $try = 10;
            while ($try > 0) {

                # New disk address
                $srcAddr        = $mdiskAddr;
                $srcHcpLinkAddr = $srcLinkAddr{$mdiskAddr};
                $tgtAddr        = $mdiskAddr + 2000;

                # Check if new disk address is used (target)
                $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtAddr);

                # If disk address is used (target)
                while ($rc == 0) {

                    # Generate a new disk address
                    # Sleep 5 seconds to let existing disk appear
                    sleep(5);
                    $tgtAddr = $tgtAddr + 1;
                    $rc = xCAT::zvmUtils->isAddressUsed($::SUDOER, $hcp, $tgtAddr);
                }

                # Link target disk
                xCAT::zvmUtils->printLn($callback, "$tgtNode: Linking target disk ($mdiskAddr) as ($tgtAddr) in write mode");
                $out = `ssh -o ConnectTimeout=5 $::SUDOER\@$hcp "$::SUDO /sbin/vmcp link $tgtUserId $mdiskAddr $tgtAddr MR $tgtPw"`;

                # If link fails
                if ($out =~ m/not linked/i || $out =~ m/not write-enabled/i) {

                    # Wait before trying again
                    sleep(5);

                    $try = $try - 1;
                } else {
                    last;
                }
            }    # End of while ( $try > 0 )

            # If target disk is not linked
            if ($out =~ m/not linked/i) {
                xCAT::zvmUtils->printLn($callback, "$tgtNode: (Error) Failed to link target disk ($mdiskAddr) in write mode");
                xCAT::zvmUtils->printLn($callback, "$tgtNode: Failed");

                # Exit
                return;
            }

            # Flashcopy not supported, use Linux dd
            if ($ddCopy) {

                #*** Use Linux dd to copy ***
                xCAT::zvmUtils->printLn($callback, "$tgtNode: FLASHCOPY not working. Using Linux DD");

                # Enable target disk
                $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $tgtAddr);

                # Determine source device node
                $srcDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $srcHcpLinkAddr);

                # Determine target device node
                $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtAddr);

                # Format target disk
                # Only ECKD disks need to be formated
                if ($tgtDiskType eq '3390') {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Formating target disk ($tgtAddr)");
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;
                    xCAT::zvmUtils->printSyslog("dasdfmt -b 4096 -y -f /dev/$tgtDevNode");

                    # Check for errors
                    $rc = xCAT::zvmUtils->checkOutput($out);
                    if ($rc == -1) {
                        xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

                        # Detatch disks from HCP
                        $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;

                        return;
                    }

                    # Sleep 2 seconds to let the system settle
                    sleep(2);

                    # Copy source disk to target disk
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)");
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
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)");
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512 oflag=sync && $::SUDO echo $?"`;
                    $out = xCAT::zvmUtils->trimStr($out);
                    if (int($out) != 0) {

                        # If $? is not 0 then there was an error during Linux dd
                        $out = "(Error) Failed to copy /dev/$srcDevNode";
                    }

                    xCAT::zvmUtils->printSyslog("dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512 oflag=sync");
                    xCAT::zvmUtils->printSyslog("$out");

                    # Force Linux to re-read partition table
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: Forcing Linux to re-read partition table");
                    $out =
`ssh $::SUDOER\@$hcp "$::SUDO cat<<EOM | fdisk /dev/$tgtDevNode
   p
   w
   EOM"`;
                }

                # Check for error
                $rc = xCAT::zvmUtils->checkOutput($out);
                if ($rc == -1) {
                    xCAT::zvmUtils->printLn($callback, "$tgtNode: $out");

                    # Disable disks
                    $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtAddr);

                    # Detatch disks from zHCP
                    $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;

                    return;
                }

                # Sleep 2 seconds to let the system settle
                sleep(2);
            }    # end if ddcopy
        }    # end if SMAPI flashcopy did not complete


        # If not Flashcopy Disable and enable target disk
        if (!$smapiFlashCopyDone) {
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtAddr);
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-e", $tgtAddr);

            # Determine target device node (it might have changed)
            $tgtDevNode = xCAT::zvmUtils->getDeviceNode($::SUDOER, $hcp, $tgtAddr);
        }

        # Flush disk
        $out = `ssh $::SUDOER\@$hcp "$::SUDO /bin/sync"`;

        # If not Flashcopy disable and detach disk from zhcp
        if (!$smapiFlashCopyDone) {

            # Disable disks
            $out = xCAT::zvmUtils->disableEnableDisk($::SUDOER, $hcp, "-d", $tgtAddr);

            # Detatch disks from HCP
            $out = `ssh $::SUDOER\@$hcp "$::SUDO /sbin/vmcp det $tgtAddr"`;
        }

        sleep(5);
    }    # End of foreach (@srcMdisks)

    # Power on target virtual server will be done in later call
}
