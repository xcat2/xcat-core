#!/usr/bin/env perl
## IBM(c) 2015 EPL license http://www.eclipse.org/legal/epl-v10.html
#
# This plugin is used to handle the z/VM discovery. 
# z/VM discovery will discover the z/VM virtual machines running
# on a specified z/VM host and define them to xCAT DB.
# In addition, it will optionally define the systems to OpenStack.
#

package xCAT_plugin::zvmdiscovery;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use strict;
use Data::Dumper;
use Getopt::Long;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';

use lib "$::XCATROOT/lib/perl";
use Time::HiRes qw(gettimeofday sleep);
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::DiscoveryUtils;
use xCAT::Utils;
use xCAT::zvmCPUtils;
use xCAT::zvmUtils;

my $request_command;
( $::SUDOER, $::SUDO ) = xCAT::zvmUtils->getSudoer();
my $ZHCP_BIN = '/opt/zhcp/bin';

# Hash of host name resolution commands to be issued in a virtual OS.
my @hostnameCmds = ( 'hostname --fqdn', 
                     'hostname --long',
                     'hostname',
                   );

# Location of the various OpenStack plugins for discovery.
my $locOpenStackDiscovery = '/var/lib/sspmod/discovery.py';         # location of OpenStack discovery
my $locOpenStackNodeNameInfo = '/var/lib/sspmod/nodenameinfo.py';   # location of OpenStack node name info


#-------------------------------------------------------

=head3   addOpenStackSystem

    Description : Add a single system to OpenStack.
    Arguments   : class
                  callback
                  z/VM host node
                  verbose flag: 1 - verbose output, 0 - non-verbose
                  UUID generated for this node to be used in the discoverydata table
                  z/VM userid of the discovered system
                  Reference to the discoverable hash variable
    Returns     : Node as provisioned in OpenStack or an empty string if it failed.
    Example     : my $OSnode = addOpenStackSystem( $callback,
                    $zvmHost, $hcp, $verbose, $activeSystem, $discoverableRef );

=cut

#-------------------------------------------------------
sub addOpenStackSystem {
    my ( $callback, $zvmHost, $hcp, $verbose, $activeSystem, $discoverableRef ) = @_;
    my %discoverable = %$discoverableRef;

    my $junk;
    my $openstackNodeName = '';
    my $out = '';
    my $rc = 0;

    # Argument mapping between xCAT and the OpenStack python code.
    # Argument name is as known to xCAT is the key and the value is
    # the argument name as it is known to the OpenStack python code.
    my %passingArgs = (
            'cpuCount'            => '--cpucount',
            'hostname'            => '--hostname',
            'ipAddr'              => '--ipaddr',
            'memory'              => '--memory',
            'node'                => '--guestname',
            'os'                  => '--os',
            'openstackoperands'   => '',
            );
    my $args = "";

    # Build the argument string for the OpenStack call.
    foreach my $key ( keys %passingArgs ) {
        if ( defined( $discoverable{$activeSystem}{$key} ) ) {
            if ( $key ne '' ) {
                # Pass the key and the value.
                $args = "$args $passingArgs{$key} $discoverable{$activeSystem}{$key}";
            } else {
                # When name of parm to pass is '', we just pass the value of the parm.
                # The name would only complicates things for the call because it contains multiple subparms.
                # We also remove any surrounding quotes or double quotes.
                $args = "$args $discoverable{$activeSystem}{$key}";
            }
        }
    }
    $args = "$args --verbose $verbose --zvmhost $zvmHost --uuid $discoverable{$activeSystem}{'uuid'}";

    # Call the python discovery command
    if ( $verbose == 1 ) {
        my $rsp;
        push @{$rsp->{data}}, "Passing $discoverable{$activeSystem}{'node'} to OpenStack " .
                              "for userid $activeSystem on z/VM $zvmHost with arguments: $args";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    xCAT::MsgUtils->message( "S", "Calling $locOpenStackDiscovery for $discoverable{$activeSystem}{'node'} on $zvmHost" );
    $out = `python $locOpenStackDiscovery $args`;
    xCAT::MsgUtils->message( "S", "Returned from $locOpenStackDiscovery" );

    if ( $out ) {
        chomp( $out );

        if ( $verbose == 1 ) {
            my $rsp;
            push @{$rsp->{data}}, $out;
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        my @lines= split( /\n/, $out );
        my (@createdLine) = grep( /Node\screated:/, @lines );
        if ( @createdLine ) {
            # Node created. Do not need to show any output from OpenStack.
            ($junk, $openstackNodeName) = split( /:\s/, $createdLine[0], 2 );
        } else {
            # Node was not created.
            my @failedLine = grep( /Node\screation\sfailed/, @lines );
            if ( @failedLine ) {
                my $rsp;
                push @{$rsp->{data}}, "Unable to create the node " .
                                      "in OpenStack.  xCAT node creation is being undone " .
                                      "for $discoverable{$activeSystem}{'node'}.";
                if (( @lines > 1 ) && ( $verbose == 0 )) {
                    # Had more then the "Node creation failed" line AND we have not
                    # shown them (vebose == 0) so show all of the lines now.
                    push @{$rsp->{data}}, "Response from the OpenStack plugin:";
                    push @{$rsp->{data}}, @lines;
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
            } else {
                my @alreadyCreatedLine = grep( /already\screated/, @lines );
                if ( @alreadyCreatedLine ) {
                	# The node is already known to OpenStack as an instance.  We will get
                	# the node name from the response in case OpenStack wants the xCAT node to
                	# be a different name.
                	($openstackNodeName) = $alreadyCreatedLine[0] =~ m/Node (.*) already created/;
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "Response from the Openstack plugin " .
                                          "did not contain 'Node created:' or 'Node creation failed' " .
                                          "or 'already created' string.  It is assumed to have failed.";
                    if (( @lines > 1 ) && ( $verbose == 0 )) {
                        # Had more then the "Node creation failed" line AND we have not
                        # shown them (vebose == 0) so show all of the lines now.
                        push @{$rsp->{data}}, "Response from the OpenStack plugin:";
                        push @{$rsp->{data}}, @lines;
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                }
            }
        }
    } else {
        my $rsp;
        push @{$rsp->{data}}, "No response was received from the Openstack plugin.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }

    # If the xCAT node was renamed by OpenStack then update xCAT to use the new node name
    # so that the node names match.
    if (( $openstackNodeName ne '' ) and ( $discoverable{$activeSystem}{'node'} ne $openstackNodeName )) {
        if ( $verbose == 1 ) {
            my $rsp;
            push @{$rsp->{data}}, "Renaming the xCAT node $discoverable{$activeSystem}{'node'} " .
                                  "to $openstackNodeName as requested by the OpenStack plugin.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        my $renameRC = changeNode( $callback,
                                   $discoverable{$activeSystem}{'node'},
                                   'r',
                                   $openstackNodeName );
        if ( $renameRC == 0 ) {
            $discoverable{$activeSystem}{'node'} = $openstackNodeName;
        } else {
            $openstackNodeName = '';  # Want to undo the created xCAT node.
            my $rsp;
            push @{$rsp->{data}}, "Unable to rename the xCAT node $discoverable{$activeSystem}{'node'} " .
                                  "to $openstackNodeName, as requested by the OpenStack plugin, " .
                                  "rc: $renameRC";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
    }

FINISH_addOpenStackSystem:
    return $openstackNodeName;
}


#-------------------------------------------------------

=head3   addPrevDisc

    Description : Add previously discovered xCAT nodes
                  to OpenStack. (Not done. Waiting for input from Emily)
    Arguments   : class
                  callback
                  z/VM host node
                  ZHCP node
                  Time when discovery was started.  Used to determine if
                  a stop was requested and then we were restarted.
                  nodediscoverstart argument hash
    Returns     : None.
    Example     : my $out = addPrevDisc( $callback, $zvmHost,
                                         $hcp, $initStartTime, \%args );

=cut

#-------------------------------------------------------
sub addPrevDisc {
    my ( $callback, $zvmHost, $hcp, $initStartTime, $argsRef ) = @_;

    my %discoverable;
    my @nodes;
    my $rc = 0;
    my $verbose = $argsRef->{'verbose'};

    # Get the list of discovered nodes from the 'zvm' table.
    my $zvmTab = xCAT::Table->new("zvm");
    if ( !$zvmTab ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not open table: zvm.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_addPrevDisc;
    }
    my @results = $zvmTab->getAttribs( { 'discovered'=>'1', 'hcp'=>$hcp }, ('userid', 'node') );
    foreach my $id ( @results ) {
        if ( $id->{'userid'} and $id->{'node'} ) {
            $discoverable{$id->{'userid'}}{'node'} = $id->{'node'};
            $discoverable{$id->{'userid'}}{'hcp'} = $hcp;
        } else {
            if ( $verbose == 1 ) {
                my $rsp;
                push @{$rsp->{data}}, "Node $id->{'node'} is missing 'userid' or 'node' property in the zvm table.";
                xCAT::MsgUtils->message( "E", $rsp, $callback );
            }
         }
    }
    $zvmTab->close;

    if ( $verbose == 1 ) {
        my @discoverableKeys = keys %discoverable;
        my $discoverableCount = scalar( @discoverableKeys );
        my $rsp;
        push @{$rsp->{data}}, "$discoverableCount nodes have been previously discovered for $zvmHost.";
        xCAT::MsgUtils->message( "I", $rsp, $callback );
    }

    # Get the ip and hostname for each discovered node from the hosts table.
    my $hostsTab = xCAT::Table->new('hosts');
    if ( !$hostsTab ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not open table: hosts.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_addPrevDisc;
    }
    my %nodes;
    my @attribs = ('node', 'ip', 'hostnames');
    my @hosts = $hostsTab->getAllAttribs( @attribs );
    foreach my $nodeRef ( @hosts ) {
        my $node;
        if ( $nodeRef->{'node'} ) {
            $node = $nodeRef->{'node'};
        } else {
            next;
        }
        if ( $nodeRef->{'ip'} ) {
            $nodes{$node}{'ip'} = $nodeRef->{'ip'};
        } else {
            next;
        }
        if ( $nodeRef->{'hostnames'} ) {
            $nodes{$node}{'hostnames'} = $nodeRef->{'hostnames'};
        } else {
            # Don't have enough info, remove it from the nodes hash.
            delete( @nodes{$node} );
        }
    }
    $hostsTab->close;

    foreach my $activeSystem ( keys %discoverable ) {
        my $node = $discoverable{$activeSystem}{'node'};
        if ( $nodes{$node}{'ip'} ) {
            $discoverable{$activeSystem}{'ipAddr'} = $nodes{$node}{'ip'};
            $discoverable{$activeSystem}{'hostname'} = $nodes{$node}{'hostnames'};
        } else {
            # Don't have enough info, remove it from the discoverable hash.
            delete( $discoverable{$activeSystem} );
        }
    }

    # Get the OS info, memory, CPU count and UUID.
    foreach my $activeSystem ( keys %discoverable ) {
        # Verify that the virtual machine is currently running.
        my $out = `ssh -q $::SUDOER\@$hcp $::SUDO $ZHCP_BIN/smcli "Image_Status_Query -T '$activeSystem'"`;
        $rc = $? >> 8;
        if ( $rc == 255 ) {
            my $rsp;
            push @{$rsp->{data}}, "z/VM discovery is unable to communicate with the zhcp server: $hcp";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            delete( $discoverable{$activeSystem} );
            next;
        } elsif ( $rc == 1 ) {
            if ( $verbose == 1 ) {
                my $rsp;
                push @{$rsp->{data}}, "ignoring: $activeSystem - virtual machine is not logged on";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            delete( $discoverable{$activeSystem} );
            next;
        } elsif ( $rc != 0 ) {
            my $rsp;
            push @{$rsp->{data}}, "An unexpected return code $rc was received from " .
                                  "the zhcp server $hcp for an smcli Image_Status_Query " .
                                  "request.  SMAPI servers may be unavailable.  " .
                                  "Received response: $out";

            xCAT::MsgUtils->message("E", $rsp, $callback);
            delete( $discoverable{$activeSystem} );
            next;
        }

        # Get the OS version from the OS.
        my $os = xCAT::zvmUtils->getOsVersion( $::SUDOER, $discoverable{$activeSystem}{'node'}, $callback );
        if ( $os ) {
            $discoverable{$activeSystem}{'os'} = $os;
        } else {
            if ( $verbose == 1 ) {
                my $rsp;
                push @{$rsp->{data}}, "ignoring: $activeSystem - Unable to obtain OS version information from node $discoverable{$activeSystem}{'node'}";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
            delete( $discoverable{$activeSystem} );
            next;
        }

        # Install vmcp in the target system just in case no one has done that yet.
        xCAT::zvmCPUtils->loadVmcp( $::SUDOER, $discoverable{$activeSystem}{'node'} );

        # Get the current memory from CP.
        my $memory = xCAT::zvmCPUtils->getMemory( $::SUDOER, $discoverable{$activeSystem}{'node'} );
        if ( $memory ) {
            $discoverable{$activeSystem}{'memory'} = $memory;
        } else {
            my $rsp;
            push @{$rsp->{data}}, "Could not obtain the current virtual machine memory size from node: $discoverable{$activeSystem}{'node'}";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            delete( $discoverable{$activeSystem} );
            next;
        }

        # Get the current CPU count from CP.
        my $cpuString = xCAT::zvmCPUtils->getCpu( $::SUDOER, $discoverable{$activeSystem}{'node'} );
        if ( $cpuString ) {
            my @cpuLines = split( /\n/, $cpuString );
            $discoverable{$activeSystem}{'cpuCount'} = scalar( @cpuLines );
        } else {
            my $rsp;
            push @{$rsp->{data}}, "Could not obtain the current virtual machine CPU count from node: $discoverable{$activeSystem}{'node'}";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            delete( $discoverable{$activeSystem} );
            next;
        }

        $discoverable{$activeSystem}{'uuid'} = xCAT::Utils::genUUID();
    }

    my $rsp;
    if ( %discoverable ) {
        if ( $verbose == 1 ) {
            push @{$rsp->{data}}, "The following xCAT nodes are eligible for OpenStack only discovery:";
        }
    } else {
        push @{$rsp->{data}}, "No xCAT nodes are eligible for OpenStack only discovery.";
    }
    foreach my $activeSystem ( keys %discoverable ) {
        $discoverable{$activeSystem}{'openstackoperands'} = $argsRef->{'openstackoperands'};
        if ( $verbose == 1 ) {
            push @{$rsp->{data}}, "  $discoverable{$activeSystem}{'node'}";
        }
    }
    if ( $rsp ) {
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    foreach my $activeSystem ( keys %discoverable ) {
        # Exit if we have been asked to stop discovery for this host.
        my $startTime = getRunningDiscTimestamp( $callback, $zvmHost );
        if ( $startTime != $initStartTime ) {
            # Start time for this run is different from start time in the site table.
            # User must have stopped and restarted discovery for this host.
            # End now to let other discovery handle the work.
            push @{$rsp->{data}}, "Stopping due to a detected stop request.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            goto FINISH_addPrevDisc;
        }

        # Define the system to OpenStack
        my $openstackNodeName = addOpenStackSystem( $callback, $zvmHost, $hcp, $verbose, $activeSystem, \%discoverable );
        if ( $openstackNodeName ) {
            updateDiscoverydata( $callback, 'add', $verbose, $zvmHost, $activeSystem, \%discoverable );
        }
    }

FINISH_addPrevDisc:
    return;
}


#-------------------------------------------------------

=head3   changeNode

    Description : Change an xCAT node.  The change can
                  be a rename or a deletion of the node from
                  the xCAT tables.
    Arguments   : Callback handle
                  node name
                  Type of change:
                    'r'  - rename the node name and redo makehosts
                    'd'  - delete the node from xCAT tables and /etc/hosts
                    'do' - delete the node from xCAT tables only, don't
                           undo makehosts
    Returns     : Return code
                    0 - It worked
                    1 - It failed
    Example     : rc = changeNode( $callback, $nodeName, 'r', $newName );

=cut

#-------------------------------------------------------
sub changeNode {
    my $callback = shift;
    my $nodeName = shift;
    my $changeType = shift;
    my $newNode = shift;
    
    my $rc = 0;           # Assume everything works
    my $retStrRef;

    # Remove the node from the /etc/hosts file
    if (( $changeType eq 'r' ) or ( $changeType eq 'd' )) {
        my $out = `/opt/xcat/sbin/makehosts -d $nodeName 2>&1`;
        if ( $out ne '' ) {
            my $rsp;
            push @{$rsp->{data}}, "'makehosts -d' failed for $nodeName.  Node is still defined in xCAT MN's /etc/hosts file.  'makehosts' response: $out";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            $rc = 1;
        }
    }

    # Remove the node.
    if (( $changeType eq 'd' ) or ( $changeType eq 'do' )) {
        my $retRef = xCAT::Utils->runxcmd({command => ['rmdef'], stdin=>['NO_NODE_RANGE'], arg => [ "-t", "node", "-o", $nodeName ]}, $request_command, 0, 2);
        if ( $::RUNCMD_RC != 0 ) {
            my $rsp;
            $retStrRef = parse_runxcmd_ret($retRef);
            push @{$rsp->{data}}, "Unable to remove node $nodeName from the xCAT tables.  rmdef response: $retStrRef->[1]";
            push @{$rsp->{data}}, "-t". "node". "-o". $nodeName;
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            $rc = 1;
        }
    }

    # Rename the node.
    if ( $changeType eq 'r' ) {
        my $retRef = xCAT::Utils->runxcmd({command=>['chdef'], stdin=>['NO_NODE_RANGE'], arg=>[ '-t', 'node', '-o', $nodeName, '-n', $newNode, '--nocache' ]}, $request_command, 0, 2);
        if ( $::RUNCMD_RC != 0 ) {
            my $rsp;
            $retStrRef = parse_runxcmd_ret($retRef);
            push @{$rsp->{data}}, '-t'. 'node'. '-o'. $nodeName. '-n'. $newNode;
            push @{$rsp->{data}}, "Unable to rename node $nodeName " .
                "to $newNode in the xCAT tables.  " .
                "The node definition for $nodeName will be removed.  " .
                "chdef response: $retStrRef->[1]";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            $rc = 1;
            changeNode( $callback, $nodeName, 'do' );
        } else {
            my $out = `/opt/xcat/sbin/makehosts $newNode 2>&1`;
            if ( $out ne '' ) {
                my $rsp;
                push @{$rsp->{data}}, "'makehosts' failed for $newNode.  " .
                    "The node definition for $newNode will be removed.  " .
                    "'makehosts' response: $out";
                xCAT::MsgUtils->message( "E", $rsp, $callback );
                $rc = 1;
                changeNode( $callback, $newNode, 'do' );
            }
        }
    }
    return $rc;
}


#-------------------------------------------------------

=head3   createNode

    Description : Find an available xCAT nodename and create a node
                  for the virtual machine and indicate it is a 
                  discovered node.  Also, do a MAKEHOSTS so xCAT MN
                  can access it by the node name.
    Arguments   : Callback handle
                  DNS name associated with the OS in the machine
                  Desired name format template, if specified
                  Current numeric adjustment value, used to get
                      to the next available nodename.
                  xCAT STANZA information in a string that will
                       be used to create the node.
                  Reference for the xCAT NODEs hash so that we
                      can check for already known node names.
    Returns     : Node name if created or empty string if an error occurred.
                  Current numeric value
    Example     : ( $node, $numeric ) = createNode($callback, $discoverable{$activeSystem}{'hostname'}, 
                                        $args{'nodenameformat'}, $numeric, $retstr_gen, \%xcatNodes);

=cut

#-------------------------------------------------------
sub createNode {
    my $callback = shift;
    my $dnsName = shift;
    my $nameFormat = shift;
    my $numeric = shift;
    my $stanzaInfo = shift;
    my $xcatNodesRef = shift;

    my $attempts = 0;     # Number of attempts to find a usable node name
    my $nodeName;         # Node name found or being checked
    my $prefix = '';      # Node name prefix, used with templates
    my $rsp;              # Message work variable
    my $shortName;        # Short form of the DNS name
    my $suffix = '';      # Node name suffix, initially none
    my $templateType = 0; # Type of template; 0: none, 1: old style xCAT, 2: OpenStack (sprintf)

    # Determine the component parts of the new node name based on whether
    # a template is specified.
    if ( $nameFormat ) {
        if ( $nameFormat =~ /#NNN/ ) {
            # Old Style xCAT template e.g. node#NNN -> node001
            $templateType = 1;
            
            # Deconstruct the name format template into its component parts.
            my @fmtParts = split ( '#NNN', $nameFormat );
            $prefix = $fmtParts[0];
            $suffix = $fmtParts[1];
        } elsif ( $nameFormat =~ /%/ ) {
            # OpenStack style template, uses sprintf for formatting
            $templateType = 2;
        } else {
            $nodeName = '';
            push @{$rsp->{data}}, "Unrecognized node name template.  Nodes will not be discovered.";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            goto FINISH_createNode;
        }

        if ( $numeric eq '' ) {
            $numeric = 0;
        }
    } else {
        # Set up to use the DNS short name as the root of the node name.
        my @nameParts = split( /\./, $dnsName );
        $shortName = lc( $nameParts[0] );
        $numeric = "";
    }

    # Loop to find an available node name and reserve it by creating the
    # node with minimal information.
    while ( 1 ) {
        # Create the next nodename
        if ( $templateType == 1 ) {
            $numeric = $numeric + 1;
            my $numSize = length($numeric);
            if ( $numSize < 3 ) {
                $numSize = 3;
            }
            my $format = "%0".$numSize."d";
            $numeric = sprintf($format, $numeric);
            $nodeName = $prefix.$numeric.$suffix;
        } elsif ( $templateType == 2 ) {
            $numeric = $numeric + 1;
            $nodeName = sprintf($nameFormat, $numeric);
        } else {
            if ( $numeric ne '' ){
                $numeric += 1;
            }
            $nodeName = $shortName.$numeric;
        }

        # Verify that the nodename is available.
        if ( !$xcatNodesRef->{$nodeName} ) {
            # Found an available node name
            # Attempt to create the node with that name.
            $attempts += 1;
            my $retstr_gen = "$nodeName:\n$stanzaInfo";
            my $retRef = xCAT::Utils->runxcmd({command=>["mkdef"], stdin=>[$retstr_gen], arg=>['-z']}, $request_command, 0, 2);

            if ( $::RUNCMD_RC == 0 ) {
                # Node created.  All done.
                $xcatNodesRef->{$nodeName} = 1;
                
                # Update the zvm table for the node to indicate that it is a discovered system.
                my %zvmProps = ( "discovered" => "1" );
                my $zvmTab = xCAT::Table->new('zvm');
                if ( !$zvmTab ) {
                    # Node was created but there is not much we can do about it since
                    # not being able to update the zvm table indicates a severe error.
                    push @{$rsp->{data}}, "Could not open table: zvm.  $nodeName was created but discovered=1 could not be set in the zvm table.";
                    xCAT::MsgUtils->message( "E", $rsp, $callback );
                } else {
                    $zvmTab->setAttribs( {node => $nodeName}, \%zvmProps );
                    $zvmTab->commit();
                }
                last;
            } else {
                if ( $attempts > 10 ) {
                    # Quit trying to create a node after 10 attempts
                    my $retStrRef = parse_runxcmd_ret($retRef);
                    my $rsp;
                    push @{$rsp->{data}}, "Unable to create a node, $nodeName.  Last attempt response: $retStrRef->[1]";
                    xCAT::MsgUtils->message( "E", $rsp, $callback );
                    $nodeName = '';
                    last;
                } else {
                    # Assume xCAT daemon is unavailable.  Give it 15 seconds to come back 
                    # before next attempt.
                    sleep(15);
                }
            } 
        }

        # Did not find an available node name on this pass.
        # Wipe out the nodename in case we exit the loop.  Also, ensure a numeric 
        # is used next time around.
        $nodeName = '';
        if ( $numeric eq '' ){
            $numeric = 0;
        }
    }

    if ( $nodeName ne '' ) {
        # Issue MAKEHOSTS so that xCAT MN can drive commands to the host using the node name.
        # Note: If OpenStack changes the node name then we will have to redo this later.
        my $out = `/opt/xcat/sbin/makehosts $nodeName 2>&1`;
        if ( $out ne '' ) {
            my $rsp;
            push @{$rsp->{data}}, "'makehosts' failed for $nodeName.  Node creation is being undone.  'makehosts' response: $out";
            xCAT::MsgUtils->message( "E", $rsp, $callback );
            changeNode( $callback, $nodeName, 'do' );
            $nodeName = '';
        }
    }

FINISH_createNode:
    return ( $nodeName, $numeric );
}



#-------------------------------------------------------

=head3   findme

    Description : Handle the request form node to map and 
                  define the request to a node.
    Arguments   : request handle
                  callback
                  sub request
    Returns     : 0 - No error
                  non-zero - Error detected.
    Example     : findme( $request, $callback, $request_command );
    
=cut

#-------------------------------------------------------
sub findme {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $SEQdiscover = getSiteVal("__SEQDiscover");
    my $PCMdiscover = getSiteVal("__PCMDiscover");
    my $ZVMdiscover = getSiteVal("__ZVMDiscover");
    unless ( $ZVMdiscover ) {
        if ( $SEQdiscover or $PCMdiscover ) {
            # profile or sequential discovery is running, then just return 
            # to make the other discovery handle it
            return;
        }

        # update the discoverydata table to have an undefined node
        $request->{discoverymethod}->[0] = 'undef';
        xCAT::DiscoveryUtils->update_discovery_data($request);
        return;
    }
}


#-------------------------------------------------------

=head3   getOpenStackTemplate

    Description : Get the current template used by OpenStack
                  for this host and the largest numeric
                  value currently in use.
    Arguments   : callback
                  z/VM host node
    Returns     : Template to be used for node naming
                  Highest numeric value in use
    Example     : my $out = getOpenStackTemplate( $callback, $zvmHost );

=cut

#-------------------------------------------------------
sub getOpenStackTemplate {
    my ( $callback, $zvmHost ) = @_;

    my $out = '';
    my %response = (
        'template' => '',
        'number' => '' );

    xCAT::MsgUtils->message( "S", "Calling $locOpenStackNodeNameInfo for $zvmHost" );
    $out = `python $locOpenStackNodeNameInfo`;
    xCAT::MsgUtils->message( "S", "Returned from $locOpenStackNodeNameInfo with $out" );

    if (( $out ne '' ) && ( $out !~ /^Error detected/ )) {
        my @parts = split( /\s/, $out );
        my $key;
        foreach my $part ( @parts ) {
            if ( $part eq 'Template:' ) {
                $key = 'template';
            } elsif ( $part eq 'Number:' ) {
                $key = 'number';
            } else {
                $part =~ s/^\s+|\s+$//g;    # Trim leading & ending blanks
                $response{$key} = $part;
            }
        }
    } else {
        my $rsp;
        my @lines = split( /\n/, $out );
        shift( @lines );
        if ( @lines ) {
            push @{$rsp->{data}}, @lines;
        } else {
            push @{$rsp->{data}}, "An error was detected in the nova instance name template."
        }
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        $response{'template'} = '';
    }

FINISH_getOpenStackTemplate:
    return ( $response{'template'}, $response{'number'} );
}


#-------------------------------------------------------

=head3   getRunningDiscTimestamp

    Description : Get the timestamp on a specific running
                  discovery from the site table variable.
    Arguments   : Callback handle
                  z/VM host node
    Returns     : Timestamp for the run that was specified or 
                    empty string if a run was not found.
    Example     : $ts = getRunningDiscTimestamp( 'zvm1' );

=cut

#-------------------------------------------------------
sub getRunningDiscTimestamp {
    my $callback = shift;
    my $zvmHost = shift;

    my $rsp;            # Response buffer for output messages
    my $ts = '';        # Timestamp value

    my $val = getSiteVal("__ZVMDiscover");
    if ( $val ) {
        if ( $val =~ /zvmhost=$zvmHost,/ ) {
            my @discoveries = split( /zvmhost=/, $val );
            foreach my $discovery ( @discoveries ) {
                if ( $discovery =~ "^$zvmHost" ) {
                    my @parts = split( ',', $discovery );
                    if ( $parts[1] ) {
                        $ts = $parts[1];
                    }
                }
            }
        }
    }

    return $ts;
}


#-------------------------------------------------------

=head3   getSiteVal

    Description : Bypasses a problem with get_site_attribute
                  returning an old cashe value instead of
                  the current value.
    Arguments   : Name of attribute
    Returns     : Value from the site table
    Example     : ( $val ) = getSiteVal( '__ZVMDiscover' );

=cut

#-------------------------------------------------------
sub getSiteVal {
    my $attribute = shift;

    my $response = '';        # Response buffer for return

    my $siteTab = xCAT::Table->new( "site", -autocommit=>1 );
    my @results = $siteTab->getAttribs( { 'key'=>$attribute }, ('value') );
    foreach my $id ( @results ) {
        $response .= $id->{'value'};
    }
    $siteTab->close;

    return $response;
}


#-------------------------------------------------------

=head3   handled_commands

    Description : Returns the supported commands and their handler.
    Arguments   : None.
    Returns     : Command handler hash for this module.

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        findme             => 'zvmdiscovery',
        #nodediscoverdef   => 'zvmdiscovery',    # Handled by sequential discovery
        nodediscoverls     => 'zvmdiscovery',
        nodediscoverstart  => 'zvmdiscovery',
        nodediscoverstatus => 'zvmdiscovery',
        nodediscoverstop   => 'zvmdiscovery',
    }
}


#-------------------------------------------------------

=head3   nodediscoverls

    Description : List discovered z/VM systems.
    Arguments   : callback
                  arguments for nodediscoverls
    Returns     : None.
    Example     : nodediscoverls( $callback, $args );

=cut

#-------------------------------------------------------
sub nodediscoverls {
    my $callback = shift;
    my $args = shift;

    my %origArgs;                # Original arguments from the command invocation
    my $maxNodeSize = 4;         # Maximum size of a nodename in the current list
    my $maxHostSize = 6;         # Maximum size of a host nodename in the current list
    my $maxUseridSize = 6;       # Maximum size of a userid in the current list

    # Determine which options were specified and their values.
    if ( $args ) {
        @ARGV = @$args;
    }

    GetOptions(
        't=s'         => \$origArgs{'type'},
        'u=s'         => \$origArgs{'uuid'},
        'l'           => \$origArgs{'long'},
        'h|help'      => \$origArgs{'help'},
        'v|version'   => \$origArgs{'ver'},
        'z|zvmhost=s' => \$origArgs{'zvmHost'} );

    # If '-u' was specified then let seqdiscovery handle it as common output.
    if ( $origArgs{'uuid'} ) {
        return;
    }

    # If z/VM discovery is running and the type was not already specified then
    # we treat this as a z/VM type of listing.
    my @ZVMDiscover = xCAT::TableUtils->get_site_attribute( "__ZVMDiscover" );
    if ( $ZVMDiscover[0] ) {
        $origArgs{'type'} = 'zvm';
    }

    # Weed out invocations that this routine does not handle but instead
    # leaves to sequential discovery to handle.
    if ( $origArgs{'help'} ||
         $origArgs{'ver'}  ||
         ( $origArgs{'type'} && $origArgs{'type'} ne 'zvm' ))
    {
        # Sequential discovery will have handled these options.
        return;
    } elsif ( $origArgs{'zvmHost'} || ( $origArgs{'type'} && $origArgs{'type'} eq 'zvm' )) {
        # z/VM related operands are handled here.
    } else {
        # Sequential discovery will have handled other combinations of options.
        return;
    }

    # If a zvmHost was specified then process it into an array
    my %zvmHosts;
    my @inputZvmHosts;
    if ( $origArgs{'zvmHost'} ) {
        if ( index( $origArgs{'zvmHost'}, ',' ) != -1 ) {
            # Must have specified multiple host node names
            my @hosts = split( /,/, $origArgs{'zvmHost'} );
            foreach my $host ( @hosts ) {
                if ( !$host ) {
                    # Tolerate zvmhost value beginning with a comma.  
                    # It is wrong but not worth an error message.
                    next;
                }
                push( @inputZvmHosts, $host );
            }
        } else {
            push( @inputZvmHosts, $origArgs{'zvmHost'} );
        }
        %zvmHosts = map { $_ => 1 } @inputZvmHosts;
    }

    # Get the list xCAT nodes and their userids.
    my $zvmTab = xCAT::Table->new("zvm");
    if ( !$zvmTab ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not open table: zvm.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_nodediscoverls;
    }
    my %xcatNodes;
    my @attribs = ('node', 'userid');
    my @nodes = $zvmTab->getAllAttribs( @attribs );
    foreach my $nodeRef ( @nodes ) {
        if ( !$nodeRef->{'node'} || !$nodeRef->{'userid'} ) {
            next;
        }
        $xcatNodes{$nodeRef->{'node'}} = $nodeRef->{'userid'};
    }

    # Get the list of discovered systems for the specified z/VMs.
    my %discoveredNodes;
    my $disTab = xCAT::Table->new('discoverydata');
    if ( !$disTab ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not open table: discoverydata.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_nodediscoverls;
    }

    my @disData = $disTab->getAllAttribsWhere( "method='zvm'", 'node', 'uuid', 'otherdata',
                                               'method', 'discoverytime', 'arch', 'cpucount',
                                               'memory');
    foreach my $disRef ( @disData ) {
        if ( !$disRef->{'uuid'} || !$disRef->{'node'} || !$disRef->{'otherdata'} ) {
            next;
        }

        my $host = $disRef->{'otherdata'};
        $host =~ s/^zvmhost.//g;

        if ( !%zvmHosts | $zvmHosts{$host} ) {
            my $node = $disRef->{'node'};
            $discoveredNodes{$node}{'uuid'} = $disRef->{'uuid'};
            $discoveredNodes{$node}{'host'} = $host;
            if ( $xcatNodes{$node} ) {
                $discoveredNodes{$node}{'userid'} = $xcatNodes{$node};
            }
            $discoveredNodes{$node}{'method'} = $disRef->{'method'};
            $discoveredNodes{$node}{'discoverytime'} = $disRef->{'discoverytime'};
            $discoveredNodes{$node}{'arch'} = $disRef->{'arch'};
            $discoveredNodes{$node}{'cpucount'} = $disRef->{'cpucount'};
            $discoveredNodes{$node}{'memory'} = $disRef->{'memory'};

            # Update size of node and host node names if size has increased.
            # This is used later when producing the output.
            my $length = length( $host );
            if ( $length > $maxHostSize ) {
                $maxHostSize = $length;
            }
            $length = length( $node );
            if ( $length > $maxNodeSize ) {
                $maxNodeSize = $length;
            }
            $length = length( $discoveredNodes{$node}{'userid'} );
            if ( $length > $maxUseridSize ) {
                $maxUseridSize = $length;
            }
        }
    }

    # Produce the output
    my $rsp;
    my $discoverednum = keys %discoveredNodes;
    push @{$rsp->{data}}, "Discovered $discoverednum nodes.";
    if ( %discoveredNodes ) {
        # Create the format string for the column output
        if ( $maxHostSize > 20 ) {
            $maxHostSize = 20;     # Set a maximum, individual lines may throw it off but we need to be reasonable.
        }
        $maxHostSize += 2;
        if ( $maxNodeSize > 20 ) {
            $maxNodeSize = 20;     # Set a maximum, individual lines may throw it off but we need to be reasonable.
        }
        $maxNodeSize += 2;
        if ( $maxUseridSize > 20 ) {
            $maxUseridSize = 20;     # Set a maximum, individual lines may throw it off but we need to be reasonable.
        }
        $maxUseridSize += 2;

        my $fmtString;
        if ( !$origArgs{'long'} ) {
            $fmtString = ' %-' . $maxNodeSize . 's%-' . $maxUseridSize . 's%-' . $maxHostSize . 's';
            push @{$rsp->{data}}, sprintf( $fmtString, 'NODE', 'USERID', 'ZVM HOST' );
        }

        # Create the output
        foreach my $node (keys %discoveredNodes) {
            if ( $origArgs{'long'} ) {
                push @{$rsp->{data}}, "Object uuid: $discoveredNodes{$node}{'uuid'}";
                push @{$rsp->{data}}, "    node=$node";
                push @{$rsp->{data}}, "    userid=$discoveredNodes{$node}{'userid'}";
                push @{$rsp->{data}}, "    host=$discoveredNodes{$node}{'host'}";
                push @{$rsp->{data}}, "    method=$discoveredNodes{$node}{'method'}";
                push @{$rsp->{data}}, "    discoverytime=$discoveredNodes{$node}{'discoverytime'}";
                push @{$rsp->{data}}, "    arch=$discoveredNodes{$node}{'arch'}";
                push @{$rsp->{data}}, "    cpucount=$discoveredNodes{$node}{'cpucount'}";
                push @{$rsp->{data}}, "    memory=$discoveredNodes{$node}{'memory'}";
            } else {
                push @{$rsp->{data}}, sprintf( $fmtString,
                                               $node,
                                               $discoveredNodes{$node}{'userid'},
                                               $discoveredNodes{$node}{'host'} );
            }
        }
    }

    xCAT::MsgUtils->message("I", $rsp, $callback);

FINISH_nodediscoverls:
    return;
}


#-------------------------------------------------------

=head3   nodediscoverstart

    Description : Initiate the z/VM discovery process.
    Arguments   : callback
                  arguments for nodediscoverstart
    Returns     : None.
    Example     : nodediscoverstart( $callback, $args );
    
=cut

#-------------------------------------------------------
sub nodediscoverstart {
    my $callback = shift;
    my $args = shift;

    my $lock = 0;            # Lock word, 0: not obtained, 1: lock failed, other: lock handle
    my @newZvmHosts;         # Array of z/VM host nodes on this command invocation
    my %origArgs;            # Original arguments from the command invocation
    my %parms;               # Parameters to pass along to start routine
    my $rsp;                 # Response buffer for output messages
    my %runningZvmHosts;     # List of z/VM host nodes from the __ZVMDiscover property in the site table
    my $zvmHost;             # Short scope work parameter used to contain a z/VM host node name

    # Valid attributes for nodediscoverstart
    my %validArgs = (
        'defineto'          => 1,
        'groups'            => 1,
        'ipfilter'          => 1,
        'nodenameformat'    => 1,
        'useridfilter'      => 1,
        'zvmhost'           => 1,
        'openstackoperands' => 1,
    );

    if ( $args ) {
        @ARGV = @$args;
    }

    $origArgs{'verbose'} = 0;     # Assume we are not doing verbose
    my ($help, $ver); 
    if (!GetOptions(
        'h|help' => \$help,
        'V|verbose' => \$origArgs{'verbose'},
        'v|version' => \$ver)) {
        # Sequential discovery will have produced an error message.
        # We don't need another
        return;
    }
    
    if ( $help | $ver ) {
        # Sequential discovery will have handled these options.
        return;
    }

    foreach ( @ARGV ) {
        my ($name, $value) = split ('=', $_);
        $origArgs{$name} = $value;
    }

    if ( !defined( $origArgs{'zvmhost'} ) ) {
        # If zvmhost parm is not present then this is not a z/VM discovery.
        goto FINISH_NODEDISCOVERSTART;
    }

    push @{$rsp->{data}}, "Processing: nodediscoverstart @$args";
    xCAT::MsgUtils->message("I", $rsp, $callback, 1);

    # Check the running of sequential or profile-based discovery
    my $SEQdiscover = getSiteVal("__SEQDiscover");
    my $PCMdiscover = getSiteVal("__PCMDiscover");
    if ( $PCMdiscover or $SEQdiscover ) {
        push @{$rsp->{data}}, "z/VM Discovery cannot be run together with Sequential or Profile-based discovery";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        goto FINISH_NODEDISCOVERSTART;
    }

    # Verify that specified filters are valid.
    if ( defined( $origArgs{'ipfilter'} )) {
        eval {''=~/$origArgs{'ipfilter'}/};
        if ( $@ ) {
            push @{$rsp->{data}}, "The ipfilter is not a valid regular expression: $@";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            goto FINISH_NODEDISCOVERSTART;
        }
    }
    if ( defined( $origArgs{'useridfilter'} )) {
        eval {''=~/$origArgs{'useridfilter'}/};
        if ( $@ ) {
            push @{$rsp->{data}}, "The useridfilter is not a valid regular expression: $@";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            goto FINISH_NODEDISCOVERSTART;
        }
    }

    # Set the default defineto option if none was specified and verify the value.
    if ( ! defined( $origArgs{'defineto'} ) ) {
        $origArgs{'defineto'} = 'both';
    } else {
        if (( $origArgs{'defineto'} ne 'both' ) and ( $origArgs{'defineto'} ne 'xcatonly' ) and
            ( $origArgs{'defineto'} ne 'openstackonly' )) {
            push @{$rsp->{data}}, "Specified 'defineto' value is not 'both', 'xcatonly' or " .
                                  "'openstackonly': $origArgs{'defineto'}";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            goto FINISH_NODEDISCOVERSTART;
        }
    }

    # Verify that the OpenStack plugin is available.
    if ( $origArgs{'defineto'} ne 'xcatonly' ) {
        if ( !-e $locOpenStackDiscovery ) {
            my $rsp;
            push @{$rsp->{data}}, "$locOpenStackDiscovery does not exist.  " .
                                  "Discovery cannot occur.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            goto FINISH_NODEDISCOVERSTART;
        }
        if ( $origArgs{'defineto'} ne 'both' ) {
            if ( !-e $locOpenStackNodeNameInfo ) {
                my $rsp;
                push @{$rsp->{data}}, "$locOpenStackNodeNameInfo does not exist.  " .
                                      "Discovery cannot occur.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                goto FINISH_NODEDISCOVERSTART;
            }
        }
    }

    # Use sudo or not
    # This looks in the passwd table for a key = sudoer
    ($::SUDOER, $::SUDO) = xCAT::zvmUtils->getSudoer();

    # Obtain any ongoing z/VM discovery parms and get the list of z/VM hosts.
    $lock = xCAT::Utils->acquire_lock( "nodemgmt", 0 );
    if ( $lock == 1 ) {
        push @{$rsp->{data}}, "Unable to acquire the 'nodemgmt' lock to protect __ZVMDiscover property in the xCAT site table from changes.";
        xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
        goto FINISH_NODEDISCOVERSTART;
    }

    my $ZVMdiscover = getSiteVal( "__ZVMDiscover" );
    if ( $ZVMdiscover ) {
        if ( $ZVMdiscover =~ '^zvmhost=' ) {
            my @discoveries = split(/zvmhost=/, $ZVMdiscover);
            foreach my $activeParms ( @discoveries ) {
                if ( !$activeParms ) {
                    next;
                }
                if ( index( $activeParms, ',' ) != -1 ) {
                    $zvmHost = substr( $activeParms, 0, index( $activeParms, ',' ));
                } else {
                    $zvmHost = $activeParms;
                }
                $runningZvmHosts{$zvmHost} = 1;
            }
        } else {
            # Not an expected format, Drop it when we push out the new saved parameters.
            push @{$rsp->{data}}, "Wrong format";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            $ZVMdiscover = '';
        }
    }

    my %param;               # The valid parameters in a hash
    my $textParam;           # The valid parameters in 'name=value,name=value...' format
    my @newZvmhosts;         # Array of z/VM hosts to be added
    my %zhcpServers;         # Hash of ZHCP servers for each new host to be discovered.

    # Validate the parameters
    foreach my $name ( keys %origArgs ) {
        if ( $name eq 'verbose' ) {
            # Verbose is a hyphenated option and is not listed in the
            # validArgs hash.  So we won't do a validation check on it.
        } elsif ( !defined( $validArgs{$name} ) ) {
            push @{$rsp->{data}}, "Argument \"$name\" is not valid.";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            goto FINISH_NODEDISCOVERSTART;
        }
        if ( !defined( $origArgs{$name} ) ) {
            push @{$rsp->{data}}, "The parameter \"$name\" needs a value.";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            goto FINISH_NODEDISCOVERSTART;
        }

        if (( $name eq 'nodenameformat' ) and ( index( $origArgs{$name}, '#NNN' ) == -1)) {
            push @{$rsp->{data}}, "The parameter \"$name\" is missing the '#NNN' string.";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            goto FINISH_NODEDISCOVERSTART;
        }

        # Invoke the OpenStack plugin to validate OpenStack related variables.
        if (( $name eq 'openstackoperands' ) and 
            (( $origArgs{'defineto'} eq 'both' ) || ( $origArgs{'defineto'} eq 'openstackonly' )) &&
             defined( $origArgs{$name} )) {
            $origArgs{$name} =~ s/^\'+|\'+$//g;
            $origArgs{$name} =~ s/^\"+|\"+$//g;
            xCAT::MsgUtils->message( "S", "Calling $locOpenStackDiscovery to validate parms: $origArgs{$name}" );
            my $out = `python $locOpenStackDiscovery --validate $origArgs{$name}`;
            chomp( $out );
            xCAT::MsgUtils->message( "S", "Returned from $locOpenStackDiscovery with $out" );
            if ( $out ne '0' ) {
                if ( $out eq '' ) {
                    $out = "No response was received from $locOpenStackDiscovery for OpenStack operand validation.  z/VM discovery will not be started.";
                }
                push @{$rsp->{data}}, "$out";
                xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
                goto FINISH_NODEDISCOVERSTART;
            }
        }

        # Keep the valid parameters
        if ( $name eq 'zvmhost' ) {
            if ( index( $origArgs{$name}, ',' ) != -1 ) {
                # Must have specified multiple host node names
                my @hosts = split( /,/, $origArgs{$name} );
                foreach $zvmHost ( @hosts ) {
                    if ( !$zvmHost ) {
                        # Tolerate zvmhost value beginning with a comma.
                        # It is wrong but not worth an error message.
                        next;
                    }
                    push( @newZvmhosts, $zvmHost );
                }
            } else {
                push( @newZvmhosts, $origArgs{$name} );
            }
            foreach $zvmHost ( @newZvmhosts ) {
                if ( exists( $runningZvmHosts{$zvmHost} )) {
                    push @{$rsp->{data}}, "The node \"$zvmHost\" specified with the zvmhost parameter is already running z/VM discovery.";
                    xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
                    goto FINISH_NODEDISCOVERSTART;
                }
            }
        } else {
            # Non-zvmhost parms get added to textParam string
            $param{$name} = $origArgs{$name};
            $param{$name} =~ s/^\s+|\s+$//g;
            $textParam .= $name . '=' . $param{$name} . ' ';
        }
    }

    $textParam =~ s/,\z//;
    if ( $textParam ) {
        $textParam =  $textParam;
    }

    my ($sec,  $min,  $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my $currTime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                           $mon + 1, $mday, $year + 1900, $hour, $min, $sec);

    # Save the discovery parameters to the site.  __ZVMDiscover which will be used by nodediscoverls/status/stop and findme.
    foreach $zvmHost ( @newZvmhosts ) {
        # Verify that the zvmHost node exists
        my @reqProps = ( 'node' );
        my $propVals = xCAT::zvmUtils->getNodeProps( 'nodetype', $zvmHost, @reqProps );
        if ( !$propVals->{'node'} ) {
            push @{$rsp->{data}}, "The z/VM host node is not a defined node.  " .
                                  "The node $zvmHost is missing from the nodetype table.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        # Verify that the node is a z/VM host and locate the ZHCP server for this host.
        my @propNames = ( 'hcp', 'nodetype' );
        $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $zvmHost, @propNames );

        if ( $propVals->{'nodetype'} ne 'zvm') {
            push @{$rsp->{data}}, "The specified z/VM host $zvmHost does not appear to be a z/VM host.  " .
                                  "The 'nodetype' property in the zvm table should be set to 'zvm'.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        my $hcp = $propVals->{'hcp'};
        if ( $hcp ) {
            # Remember the ZHCP info so we can pass it along
            $zhcpServers{$zvmHost} = $hcp;
        } else {
            push @{$rsp->{data}}, "The 'hcp' property is not defined in the zvm table for $zvmHost node.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        # Add the parms for the new z/VM host to the list of running servers and their parms
        if ( $ZVMdiscover eq '' ) {
            $ZVMdiscover = "zvmhost=$zvmHost,$currTime,$textParam";
        } else {
            $ZVMdiscover .= ",zvmhost=$zvmHost,$currTime,$textParam";
        }
    }

    my $siteTab = xCAT::Table->new( "site", -autocommit=>1 );
    $siteTab->setAttribs( {"key" => "__ZVMDiscover"}, {"value" => "$ZVMdiscover"} );
    $siteTab->commit();
    $siteTab->close();

    xCAT::Utils->release_lock( $lock, 1 );
    $lock = 0;

    # Start each new discovery.
    foreach $zvmHost ( @newZvmhosts ) {
        startDiscovery( $callback, $zvmHost, $zhcpServers{$zvmHost}, $currTime, \%param );
    }

    # Common exit point to ensure that any lock has been freed.
FINISH_NODEDISCOVERSTART:
    # Release the lock if we obtained it.
    if (( $lock != 1 ) and ( $lock != 0 )) {
        xCAT::Utils->release_lock( $lock, 1 );
    }
}


#-------------------------------------------------------

=head3   nodediscoverstatus

    Description : Display the z/VM discovery status.
    Arguments   : callback
                  arguments for nodediscoverstatus
    Returns     : None.
    Example     : nodediscoverstatus( $callback, $args );
    
=cut

#-------------------------------------------------------
sub nodediscoverstatus {
    my $callback = shift;
    my $args = shift;

    my @inputZvmHosts;       # Input list of z/VM host nodes
    my $rsp;                 # Response buffer for output messages
    my @runningZvmHosts;     # z/VM host nodes being queried
    my $zvmHost;             # Small scope variable to temporarily hold a host node value

    # Valid attributes for z/VM discovery
    my ( $help, $ver );
    if ( !GetOptions(
        'h|help' => \$help,
        'v|version' => \$ver,
        'z|zvmhost=s' => \$zvmHost )) {
        # Return if unrecognized parms found so other discoveries can respond.
        goto FINISH_NODEDISCOVERSTATUS;
    }

    # Return if the user asked for help or version because sequential discovery will handle that.
    if ( $help or $ver ) {
        return;
    }

    # Return if sequential or profile discovery is running or all are stopped.
    # Sequential discovery will handle the response in that case.
    my $SEQdiscover = getSiteVal("__SEQDiscover");
    my $PCMdiscover = getSiteVal("__PCMDiscover");
    my $ZVMdiscover = getSiteVal("__ZVMDiscover");
    if (( $PCMdiscover or $SEQdiscover ) or ( !$SEQdiscover and !$PCMdiscover and !$ZVMdiscover )) {
        return;
    }

    # Put any specified zvmhosts into a hash that we can query.
    if ( $zvmHost ) {
        if ( index( $zvmHost, ',' ) != -1 ) {
            # Must have specified multiple host node names
            my @hosts = split( /,/, $zvmHost );
            foreach $zvmHost ( @hosts ) {
                if ( !$zvmHost ) {
                    # Tolerate zvmhost value beginning with a comma.  
                    # It is wrong but not worth an error message.
                    next;
                }
                push( @inputZvmHosts, $zvmHost );
            }
        } else {
            push( @inputZvmHosts, $zvmHost );
        }
    } 
    my %inputZvmHostsHash = map { $_ => 1 } @inputZvmHosts;

    # Get the list of z/VM hosts.
    my $newZVMdiscover;
    if ( $ZVMdiscover ) {
        if ( $ZVMdiscover =~ '^zvmhost=' ) {
            my @discoveries = split( /zvmhost=/, $ZVMdiscover );
            foreach my $activeParms ( @discoveries ) {
                if ( !$activeParms ) {
                    next;
                }
                if ( index( $activeParms, ',' ) != -1 ) {
                    $zvmHost = substr( $activeParms, 0, index( $activeParms, ',' ));
                } else {
                    $zvmHost = $activeParms;
                }
                push( @runningZvmHosts, $zvmHost );
                if ( exists( $inputZvmHostsHash{$zvmHost} )) {
                    $inputZvmHostsHash{$zvmHost} = 2;
                }
            }
        } else {
            # Not an expected format, Drop it when we push out the new saved parameters.
            push @{$rsp->{data}}, "__ZVMDiscover property in the xCAT site table is corrupted.  It has been cleared so that all z/VM discovery stops.  You may restart z/VM discovery.";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            
            # Remove the site.__ZVMDiscover property
            # We don't need a lock because we are whipping out the value and not trying to keep it around.
            my $siteTab = xCAT::Table->new( "site", -autocommit=>1 );
            $siteTab->delEntries({key => '__ZVMDiscover'});
            $siteTab->commit();
            $siteTab->close();
            undef $siteTab;
            goto FINISH_NODEDISCOVERSTATUS;
        }
    }

    if ( !@inputZvmHosts ) {
        # Not a specific status request so let's remind them that sequential
        # and Profile discovery are stopped.
        push @{$rsp->{data}}, "Sequential discovery is stopped.";
        push @{$rsp->{data}}, "Profile discovery is stopped.";
        xCAT::MsgUtils->message( "I", $rsp, $callback, 1 );
    }

    # Inform the user about any node that is specified as input but is not running discovery.
    if ( %inputZvmHostsHash ) {
        # --zvmhost was specified so indicate a response for each host.
        foreach $zvmHost ( keys %inputZvmHostsHash ) {
            if ( $inputZvmHostsHash{$zvmHost} == 1 ) {
                push @{$rsp->{data}}, "z/VM Discovery is stopped for: $zvmHost.";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            } else {
                push @{$rsp->{data}}, "z/VM Discovery is started for: $zvmHost.";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
        }
    } else {
        # --zvmhost was not specified so give a single line response.
        if ( @runningZvmHosts ) {
            my $runningList;
            foreach $zvmHost ( @runningZvmHosts ) {
                if ( $runningList ) {
                    $runningList .= ', ' . $zvmHost;
                } else {
                    $runningList = $zvmHost;
                }
            }
            push @{$rsp->{data}}, "z/VM Discovery is started for: $runningList";
            xCAT::MsgUtils->message( "I", $rsp, $callback );
        } else {
            # No on-going z/VM discovery.
            push @{$rsp->{data}}, "z/VM Discovery is stopped.";
            xCAT::MsgUtils->message( "I", $rsp, $callback );
        }
    }

    # Common exit point to ensure that any lock has been freed.
    # Currently, we do not use locks in this routine.
FINISH_NODEDISCOVERSTATUS:
    return;
}


#-------------------------------------------------------

=head3   nodediscoverstop

    Description : Stop the z/VM discovery process.
    Arguments   : callback
                  arguments for nodediscoverstop
                  $auto option (not used by z/VM)
    Returns     : None.
    Example     : nodediscoverstop( $callback, $args, $auto );
    
=cut

#-------------------------------------------------------
sub nodediscoverstop {
    my $callback = shift;
    my $args = shift;
    my $auto = shift;

    my @inputZvmHosts;       # Input list of z/VM host nodes to stop
    my $rsp;                 # Response buffer for output messages
    my @stoppingZvmHosts;    # z/VM host nodes that can be stopped because they are running
    my $zvmHost;             # Small scope variable to temporarily hold a host node value

    # Check for a running of z/VM discovery
    my $ZVMdiscover = getSiteVal("__ZVMDiscover");
    if ( !$ZVMdiscover ) {
        # Return so one of the other discoveries can handle the response.
        goto FINISH_NODEDISCOVERSTOP;
    }

    # Handle parameters
    if ( $args ) {
        @ARGV = @$args;
    }

    my ( $help, $ver );
    if ( !GetOptions(
        'h|help' => \$help,
        'v|version' => \$ver,
        'z|zvmhost=s' => \$zvmHost )) {}

    # Return if the user asked for help or version because sequential will handle that.
    if ( $help or $ver ) {
        goto FINISH_NODEDISCOVERSTOP;
    }

    if ( $zvmHost ) {
        if ( index( $zvmHost, ',' ) != -1 ) {
            # Must have specified multiple host node names
            my @hosts = split( /,/, $zvmHost );
            foreach $zvmHost ( @hosts ) {
                if ( !$zvmHost ) {
                    # Tolerate zvmhost value beginning with a comma.  
                    # It is wrong but not worth an error message.
                    next;
                }
                push( @inputZvmHosts, $zvmHost );
            }
        } else {
            push( @inputZvmHosts, $zvmHost );
        }
    } else {
        # If zvmhost parm is not present then this is not a z/VM discovery.
        push @{$rsp->{data}}, "nodediscoverstop did not specify a --zvmhost property.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        goto FINISH_NODEDISCOVERSTOP;
    }
    my %inputZvmHostsHash = map { $_ => 1 } @inputZvmHosts;

    # Obtain any on-going z/VM discovery parms and get the list of z/VM hosts.
    my $ZVMdiscover = getSiteVal("__ZVMDiscover");
    my $newZVMdiscover;
    if ( $ZVMdiscover ) {
        if ( $ZVMdiscover =~ '^zvmhost=' ) {
            my @discoveries = split( /zvmhost=/, $ZVMdiscover );
            foreach my $activeParms ( @discoveries ) {
                if ( !$activeParms ) {
                    next;
                }
                if ( index( $activeParms, ',' ) != -1 ) {
                    $zvmHost = substr( $activeParms, 0, index( $activeParms, ',' ));
                } else {
                    $zvmHost = $activeParms;
                }

                if ( exists( $inputZvmHostsHash{$zvmHost} )) {
                    $inputZvmHostsHash{$zvmHost} = 2;
                    push( @stoppingZvmHosts, $zvmHost );
                }
            }
        } else {
            # Not an expected format, Drop it when we push out the new saved parameters.
            push @{$rsp->{data}}, "__ZVMDiscover property in the xCAT site table is corrupted.  It has been cleared so that all z/VM discovery stops.  You may restart z/VM discovery.";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
            
            # Remove the site.__ZVMDiscover property
            my $siteTab = xCAT::Table->new( "site", -autocommit=>1 );
            $siteTab->delEntries({key => '__ZVMDiscover'});
            $siteTab->commit();
            $siteTab->close();
            undef $siteTab;
            goto FINISH_NODEDISCOVERSTOP;
        }
    }

    # Inform the user about any node that is specified as input but is not running discovery.
    foreach $zvmHost ( keys %inputZvmHostsHash ) {
        if ( $inputZvmHostsHash{$zvmHost} == 1 ) {
            push @{$rsp->{data}}, "z/VM discovery is not running for node: $zvmHost.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
    }

    # Stop the host discovery immediately, if possible.
    foreach $zvmHost ( @stoppingZvmHosts ) {
        stopDiscovery( $callback, $zvmHost, \@ARGV );
    }

    # Common exit point.
FINISH_NODEDISCOVERSTOP:
    return;
}


#-----------------------------------------------------
=head3  parse_runxcmd_ret

    Description : Get return of runxcmd and convert it into strings.
    Arguments   : The return reference of runxcmd
    Returns     : [$outstr, $errstr], A reference of list, placing 
                  standard output and standard error message.
    Example     : my $retStrRef = parse_runxcmd_ret($retRef);

=cut

#-----------------------------------------------------
sub parse_runxcmd_ret {
    my $retRef = shift;

    my $msglistref;
    my $outstr = "";
    my $errstr = "";
    if ($retRef){
        if($retRef->{data}){
            $msglistref = $retRef->{data};
            $outstr = Dumper(@$msglistref);
            xCAT::MsgUtils->message( 'S', "Command standard output: $outstr" );
        }
        if($retRef->{error}){
            $msglistref = $retRef->{error};
            $errstr =  Dumper(@$msglistref);
            xCAT::MsgUtils->message( 'S', "Command error output: $errstr" );
        }
    }
    return [$outstr, $errstr];
}


#-------------------------------------------------------

=head3   process_request

    Description : Process a request and drive the function handler.
    Arguments   : Request handle
                  Callback handle
                  Command that is requested
    Returns     : None
    Example     : process_request( $request, $callback, $request_command );
    
=cut

#-------------------------------------------------------
sub process_request {
    my $request = shift;
    my $callback = shift;
    $request_command = shift;

    my $command = $request->{command}->[0];
    my $args = $request->{arg};

    if ($command eq "findme"){
        findme( $request, $callback, $request_command );
    } elsif ($command eq "nodediscoverls") {
        nodediscoverls( $callback, $args );
    } elsif ($command eq "nodediscoverstart") {
        nodediscoverstart( $callback, $args );
    } elsif ($command eq "nodediscoverstop") {
        nodediscoverstop( $callback, $args );
    } elsif ($command eq "nodediscoverstatus") {
        nodediscoverstatus( $callback, $args );
    }
}


#-------------------------------------------------------

=head3   removeHostInfo

    Description : Remove z/VM host info from the __ZVMDiscover
                  property in the site table.
    Arguments   : Callback handle
                  z/VM host node name
    Returns     : None.
    Example     : $rc = removeHostInfo( $callback, $zvmHost );
    
=cut

#-------------------------------------------------------
sub removeHostInfo {
    my $callback = shift;
    my $zvmHost = shift;

    my $lock = 0;            # Lock word, 0: not obtained, 1: lock failed, other: lock handle
    my $rsp;                 # Response buffer for output messages

    # Obtain any on-going z/VM discovery parms and get the list of z/VM hosts.
    $lock = xCAT::Utils->acquire_lock( "nodemgmt", 0 );
    if ( $lock == 1 ) {
        push @{$rsp->{data}}, "Unable to acquire the 'nodemgmt' lock to protect __ZVMDiscover property in the xCAT site table.";
        xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );
        goto FINISH_removeHostInfo;
    }

    my $origZVMdiscover = getSiteVal("__ZVMDiscover");
    my $newZVMdiscover;
    if ( $origZVMdiscover ) {
        if ( $origZVMdiscover =~ '^zvmhost=' ) {
            my $currHost;
            my @discoveries = split( /zvmhost=/, $origZVMdiscover );
            foreach my $activeParms ( @discoveries ) {
                if ( !$activeParms ) {
                    next;
                }
                if ( index( $activeParms, ',' ) != -1 ) {
                    $currHost = substr( $activeParms, 0, index( $activeParms, ',' ));
                } else {
                    $currHost = $activeParms;
                }

                if ( $zvmHost ne $currHost ) {
                    # Not stopping this host so keep it in the new __ZVMdiscover property.
                    $activeParms =~ s/\,+$//;
                    my $hostDiscParms = "zvmhost=$activeParms";
                    if ( $newZVMdiscover ) {
                        $newZVMdiscover = "$newZVMdiscover,$hostDiscParms";
                    } else {
                        $newZVMdiscover = $hostDiscParms;
                    }
                }
            }
        } else {
            # Not an expected format, Drop it when we push out the new saved parameters.
            push @{$rsp->{data}}, "__ZVMDiscover property in the xCAT site table is corrupted.  It has been cleared so that all z/VM discovery stops.  You may restart z/VM discovery.";
            xCAT::MsgUtils->message( "E", $rsp, $callback, 1 );

            # Remove the site table's '__ZVMDiscover property.
            my $siteTab = xCAT::Table->new( "site", -autocommit=>1 );
            $siteTab->delEntries({key => '__ZVMDiscover'});
            $siteTab->commit();
            $siteTab->close();
            undef $siteTab;
            goto FINISH_removeHostInfo;
        }
    }

    # Update the site table to have the remaining discovery host information.
    my $siteTab = xCAT::Table->new( "site", -autocommit=>1 );
    if ( !$newZVMdiscover ) {
        $siteTab->delEntries({key => '__ZVMDiscover'});
    } else {
        $siteTab->setAttribs({"key" => "__ZVMDiscover"}, {"value" => "$newZVMdiscover"});
    }
    $siteTab->commit();
    $siteTab->close();
    undef $siteTab;

    # Common exit point so we can make certain to release any lock that is held.
FINISH_removeHostInfo:
    # Release the lock if we obtained it.
    if (( $lock != 1 ) and ( $lock != 0 )) {
        xCAT::Utils->release_lock( $lock, 1 );
    }
}


#-------------------------------------------------------

=head3   startDiscovery

    Description : Start z/VM discovery for a particular z/VM host.
    Arguments   : Callback handle
                  z/VM host node name
                  ZHCP
                  Start time of the discovery
                  Hash of arguments specified on the nodediscoverstart 
                    command and their values
    Returns     : None
    Example     : startDiscovery( $callback, $zvmHost, $hcp, $startTime, \%args );
    
=cut

#-------------------------------------------------------
sub startDiscovery{
    my $callback = shift;
    my $zvmHost = shift;
    my $hcp = shift;
    my $initStartTime = shift;
    my $argsRef = shift;
    my %args = %$argsRef;

    my $numeric = "";             # Numeric portion of last generated node name
    my $out;                      # Output work buffer
    my $rc;                       # Return code
    my $rsp;                      # Response buffer for output messages
    my $startOpenStack = 0;       # Tell OpenStack provisioner to begin, 0: no, 1: yes

    push @{$rsp->{data}}, "z/VM discovery started for $zvmHost";
    xCAT::MsgUtils->message( "I", $rsp, $callback );

    # Clean the entries in the discoverydata table for discovery method 'zvm'
    # and the specific zvmHost that we are going to begin to discover.
    my $disTab = xCAT::Table->new("discoverydata");
    if ( !$disTab ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not open table: discoverydata.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_startDiscovery;
    }
    
    my %keyhash;
    $keyhash{'method'} = 'zvm';
    $keyhash{'otherdata'} = "zvmhost." . $zvmHost;
    $disTab->delEntries( \%keyhash );
    $disTab->commit();
    
    # Handle 'openstackonly' discovery or get the template for 'both' discovery.
    if ( $args{'defineto'} eq 'openstackonly' ) {
        # Verify that OpenStack has a valid template to use when it is called 
        # to handle the node.
        my ( $osTemplate, $osNumeric ) = getOpenStackTemplate( $callback, $zvmHost );
        if ( $osTemplate eq '' ) {
            # An error was detected in the template and message produced leave now.
            goto FINISH_startDiscovery;
        }
        # Discover the xCAT nodes available to OpenStack
        $out = addPrevDisc( $callback, $zvmHost, $hcp, $initStartTime, \%args );
        goto FINISH_startDiscovery;
    } elsif ( $args{'defineto'} eq 'both') {
        # Obtain the template and highest numeric value from OpenStack
        my ( $osTemplate, $osNumeric ) = getOpenStackTemplate( $callback, $zvmHost );
        if ( $osTemplate ne '' ) {
            $args{'nodenameformat'} = $osTemplate;
            $numeric = $osNumeric;
        } else {
            # An error was detected in the template and message produced leave now.
            goto FINISH_startDiscovery;
        }
        
        $startOpenStack = 1;
    }

    # Get the current list of node names.
    my @nodeNames;
    my $nodelistTab = xCAT::Table->new('nodelist');
    if ( !$nodelistTab ) {
        push @{$rsp->{data}}, "Could not open table: nodelist.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_startDiscovery;
    }

    my @attribs = ('node');
    my @nodes = $nodelistTab->getAllAttribs( @attribs );
    foreach my $node ( @nodes ) {
        push @nodeNames,$node->{'node'};
    }
    @nodes = sort @nodeNames;
    my %xcatNodes = map { $_ => 1 } @nodes;

    # Obtain the list of logged on users.
    $out = `ssh -q $::SUDOER\@$hcp $::SUDO $ZHCP_BIN/smcli "Image_Status_Query '-T *'"`;
    $rc = $? >> 8;
    if ( $rc == 255 ) {
        push @{$rsp->{data}}, "z/VM discovery is unable to communicate with the zhcp system: $hcp";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_startDiscovery;
    } elsif ( $rc != 0 ) {
        my $rsp;
        push @{$rsp->{data}}, "An unexpected return code $rc was received from " .
                              "the zhcp server $hcp for an smcli Image_Status_Query " .
                              "request.  SMAPI servers may be unavailable.  " .
                              "Received response: $out";
            
        xCAT::MsgUtils->message("E", $rsp, $callback);
        goto FINISH_startDiscovery;
    }

    # Build the hash of running systems.
    my @runningSystems = split( "\n", lc( $out ) );

    # Create a hash of discoverable systems by starting with the 
    # list of running systems and removing any systems in the
    # list of non-discoverable (known to be z/VM servers or 
    # non-Linux systems).
    my @nonDiscoverable = (
        'auditor',  'autolog1', 'autolog2', 'avsvm',
        'bldcms',   'bldnuc',   'bldracf',  'bldseg',
        'cbdiodsp', 'cmsbatch',
        'datamove', 'datamov2', 'datamov3', 'datamov4', 'diskacnt',
        'dirmaint', 'dirmsat',  'dirmsat2', 'dirmsat3', 'dirmsat4',
        'dtcens1',  'dtcens2',  'dtcsmapi', 'dtcvsw1',  'dtcvsw2',
        'erep',
        'ftpserve', 'gcs',      'gskadmin',
        'ibmuser',  'imap',     'imapauth',
        'ldapsrv',  'lohcost',
        'maint',    'maint630', 'migmaint', 'monwrite', 'mproute',
        'operator', 'operatns', 'opersymp', 'osadmin1', 'osadmin2',
        'osadmin3', 'osamaint', 'osasf',    'ovfdev62',
        'perfsvm',  'persmapi', 'pmaint',   'portmap',
        'racfsmf',  'racfvm',   'racmaint', 'rexecd',
        'rscs',     'rscsauth', 'rscsdns',  'rxagent1',
        'smtp',     'snmpd',    'snmpsuba', 'ssl',      'ssldcssm',
        'sysadmin', 'sysmon',
        'tcpip',    'tcpmaint', 'tsafvm',
        'uftd',
        'vmnfs',    'vmrmadmn', 'vmrmsvm',
        'vmservp',  'vmservr',  'vmservu',  'vmservs',  'vsmevsrv', 
        'vsmguard', 'vsmproxy', 'vsmreqim', 'vsmreqin', 'vsmreqiu', 
        'vsmreqi6', 'vsmwork1', 'vsmwork2', 'vsmwork3', 
        'xcat',     'xcatserv', 'xchange',
        'zhcp',     'zvmlxapp', 'zvmmaplx',
        '4osasf40', '5684042j', '6vmdir30', '6vmhcd20', '6vmlen20',
        '6vmptk30', '6vmrac30', '6vmrsc30', '6vmtcp30',
    );
    my %discoverable;
    @discoverable {@runningSystems} = ( );
    delete @discoverable{@nonDiscoverable};

    # Apply any user specified userid filter to the list to weed it further.
    if ( $args{'useridfilter'} ) {
        if ( $args{'verbose'} ) {
            push @{$rsp->{data}}, "Applying useridfilter: '" . $args{'useridfilter'} . "'";
            xCAT::MsgUtils->message( "I", $rsp, $callback );
        }
        foreach my $activeSystem ( keys %discoverable ) {
            if ( $activeSystem !~ m/$args{'useridfilter'}/i ) {
                delete( $discoverable{$activeSystem} );
                if ( $args{'verbose'} ) {
                    push @{$rsp->{data}}, "ignoring: $activeSystem - filtered by user";
                    xCAT::MsgUtils->message( "I", $rsp, $callback );
                }
            } else {
                if ( $args{'verbose'} ) {
                    push @{$rsp->{data}}, "keeping: $activeSystem";
                    xCAT::MsgUtils->message( "I", $rsp, $callback );
                }
            }
        }
    }

    # Determine the long and short zhcp DNS name.
    my ( $longName, $shortName );
    if ( $hcp =~ /\./ ) {
        $longName = lc( $hcp );
        my @parts = split( /\./, $longName );
        if ( $parts[0] ne '' ) {
            $shortName = $parts[0];
        }
    } else {
        $shortName = lc( $hcp );
    }
    if (( !defined $longName ) && ( -e '/etc/hosts' )) {
        # Search /etc/hosts for the short name in a non-commented out portion of the lines and
        # look for the long name (contains periods).  The short and long form can be in any order
        # after the IP address.
        $out = `cat /etc/hosts | sed 's/#\.*\$//g' | sed 's/\$/ /g' | grep -i " $shortName "`;
        my @lines = split( /\n/, $out );
        my @parts = split( / /, $lines[0] );
        my $numParts = @parts;
        for( my $i = 1; $i < $numParts; $i++ ) {
            if ( $parts[$i] =~ /\./ ) {
                $longName = lc( $parts[$i] );
                last;
            }
        }
    }

    # Get the list of systems that are known to xCAT already for this host.
    my %knownToXCAT;
    my @knownUserids;
    my $zvmTab = xCAT::Table->new("zvm");
    my @attribs = ('hcp', 'userid');
    @nodes = $zvmTab->getAllAttribs( @attribs );
    foreach my $nodeRef ( @nodes ) {
        my $nodeHCP;
        if ( $nodeRef->{'hcp'} && $nodeRef->{'userid'} ) {
            $nodeHCP = lc( $nodeRef->{'hcp'} );
            if ((( defined $longName) && ( $longName eq $nodeHCP )) || 
                (( defined $shortName) && ( $shortName eq $nodeHCP ))) {
                push @knownUserids, lc( $nodeRef->{'userid'} );
            }
        }
    }
    my %knownToXCAT = map { $_ => 1 } @knownUserids;

    # Weed out any systems that are already defined as xCAT nodes.
    foreach my $activeSystem ( keys %discoverable ) {
        if ( $knownToXCAT{$activeSystem} ) {
            delete( $discoverable{$activeSystem} );
            if ( $args{'verbose'} ) {
                push @{$rsp->{data}}, "ignoring: $activeSystem - already defined to xCAT";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
        }
    }

    my $numSystems = length( %discoverable );
    xCAT::MsgUtils->message( "S", "Discovery for $zvmHost found $numSystems virtual machines." );

    # Perform a set of potentially long running functions.  We do this one 
    # server at a time so that we can stop if we are told to do so.
    # Loop through the list performing the following:
    #   - See if discovery has been stopped early.
    #   - Attempt to access the system to identify which server can be discovered.
    #   - Contact the system to obtain system information.
    #   - Create a xCAT node and update xCAT tables.
    #   - Drive the OpenStack definition of the node, if requested.
    my ($ipAddr,$ipVersion, $hostname);
    foreach my $activeSystem ( keys %discoverable ) {

        # Exit if we have been asked to stop discovery for this host.
        my $startTime = getRunningDiscTimestamp( $callback, $zvmHost );
        if ( $startTime != $initStartTime ) {
            # Start time for this run is different from start time in the site table.
            # User must have stopped and restarted discovery for this host.
            # End now to let other discovery handle the work.
            push @{$rsp->{data}}, "Stopping due to a detected stop request.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            goto FINISH_startDiscovery;
        }

        # Further refine the list by finding only systems which have a NICs with known IP addresses
        # that will allow us to SSH into them.
        $rc = xCAT::zvmUtils->findAccessIP( $callback, $activeSystem, $hcp, \%discoverable, \%args, $::SUDOER );
        if ( $rc != 0 ) {
            delete( $discoverable{$activeSystem} );
            if ( $args{'verbose'} ) {
                push @{$rsp->{data}}, "ignoring: $activeSystem - could not access the virtual server.";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
            next;
        }

        # Obtain the memory and CPU count from the active system information.
        $out = `ssh -q $::SUDOER\@$hcp $::SUDO $ZHCP_BIN/smcli "Image_Active_Configuration_Query -T '$activeSystem'"`;
        $rc = $? >> 8;
        if ($rc == 255) {
            delete( $discoverable{$activeSystem} );
            push @{$rsp->{data}}, "z/VM discovery is unable to communicate with the zhcp system: $hcp";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        } elsif ( $rc != 0 ) {
            my $rsp;
            push @{$rsp->{data}}, "An unexpected return code $rc was received from " .
                                  "the zhcp server $hcp for an smcli Image_Active_Configuration_Query " .
                                  "request.  SMAPI servers may be unavailable.  " .
                                  "Received response: $out";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        }

        my $memOut = `echo "$out" | egrep -i 'Memory:'`;
        chomp $memOut;
        my @parts = split( /Memory: /, $memOut );
        @parts = split( / /, $parts[1] );
        $discoverable{$activeSystem}{'memory'} = $parts[0].$parts[1];
        my $cpuOut = `echo "$out" | egrep -i 'CPU count:'`;
        chomp $cpuOut;
        @parts = split( 'CPU count: ', $cpuOut );
        $discoverable{$activeSystem}{'cpuCount'} = $parts[1];

        my $os = xCAT::zvmUtils->getOSFromIP( $callback, $activeSystem, $discoverable{$activeSystem}{'ipAddr'}, $discoverable{$activeSystem}{'ipVersion'} );
        if ( $os ne '' ) {
            $discoverable{$activeSystem}{'os'} = $os;
        } else {
            if ( $args{'verbose'} ) {
                push @{$rsp->{data}}, "ignoring: $activeSystem - unable to obtain OS version information from the operating system";
                xCAT::MsgUtils->message( "I", $rsp, $callback );
            }
            delete( $discoverable{$activeSystem} );
            next;
        }

        xCAT::MsgUtils->message( "S", "Discovery for $zvmHost is preparing to create a node for $activeSystem." );

        # Set up to define the node.
        $discoverable{$activeSystem}{'uuid'} = xCAT::Utils::genUUID();
        $discoverable{$activeSystem}{'openstackoperands'} = $args{'openstackoperands'};

        # Generate an xCAT node name for the newly discovered system.
        my $node;

        # Create an xCAT node.
        my $retstr_gen = '';

        $retstr_gen .= "    arch=s390x\n";
        if ( $args{'groups'} ) {
            $retstr_gen .= "    groups=$args{'groups'}\n";
        } else {
            $retstr_gen .= "    groups=all\n";
        }
        $retstr_gen .= "    hcp=$hcp\n";
        if ( $discoverable{$activeSystem}{'hostname'} ) {
            $retstr_gen .= "    hostnames=$discoverable{$activeSystem}{'hostname'}\n";
        }
        $retstr_gen .= "    ip=$discoverable{$activeSystem}{'ipAddr'}\n";
        $retstr_gen .= "    mgt=zvm\n";
        $retstr_gen .= "    objtype=node\n";
        $retstr_gen .= "    os=$discoverable{$activeSystem}{'os'}\n";
        $retstr_gen .= "    userid=$activeSystem\n";

        ( $node, $numeric ) = createNode( $callback, $discoverable{$activeSystem}{'hostname'}, $args{'nodenameformat'}, $numeric, $retstr_gen, \%xcatNodes );
        if ( $node eq '' ) {
            # If we cannot create a node then skip this one and go on to the next.
            next;
        }
        $discoverable{$activeSystem}{'node'} = $node;

        # Start OpenStack Provisioning for this node, if desired.
        if ( $startOpenStack ) {
            my $openstackNodeName = addOpenStackSystem( $callback, $zvmHost, $hcp, $args{'verbose'}, $activeSystem, \%discoverable );

            if ( !$openstackNodeName ) {
                # Node was not created in OpenStack.  Remove it from xCAT.
                changeNode( $callback, $node, 'd' );
                next;
            }
        }

        updateDiscoverydata( $callback, 'add', $args{'verbose'}, $zvmHost, $activeSystem, \%discoverable );
    }

    # Common exit point.
FINISH_startDiscovery:
    my $startTime = getRunningDiscTimestamp( $callback, $zvmHost );
    if ( $startTime == $initStartTime ) {
        my @stopArgs = ();
        stopDiscovery( $callback, $zvmHost, \@stopArgs );
    }
    return;
}


#-------------------------------------------------------

=head3   stopDiscovery

    Description : Stop z/VM discovery for a particular z/VM host.
    Arguments   : Callback handle
                  z/VM host node name
                  Array of arguments specified on nodediscoverstop or 
                    an empty array if this is an internal call.
    Returns     : None.
    Example     : stopDiscovery( $callback, $zvmHost, \@args );
    
=cut

#-------------------------------------------------------
sub stopDiscovery{
    my $callback = shift;
    my $zvmHost = shift;
    my $argsRef = shift;
    my @args = @$argsRef;

    my $rsp;
    push @{$rsp->{data}}, "z/VM discovery is being stopped for $zvmHost.";
    xCAT::MsgUtils->message( "I", $rsp, $callback, 1 );

    # Get the hcp from the zvm table.
    my @propNames = ( 'hcp', 'nodetype' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $zvmHost, @propNames );
    my $hcp = $propVals->{'hcp'};

    # Get the list of discovered systems from the zvm table.
    my $zvmTab = xCAT::Table->new('zvm');
    if ( !$zvmTab ) {
        push @{$rsp->{data}}, "Could not open table: zvm.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        return;
    }

    my %discoveredNodes;
    my @zvmData = $zvmTab->getAllAttribsWhere( "hcp='$hcp'", 'node', 'userid' );
    foreach ( @zvmData ) {
        $discoveredNodes{$_->{'node'}} = $_->{'userid'};
    }

    # Go though the discoverydata table and display the z/VM discovery entries
    my $disTab = xCAT::Table->new('discoverydata');
    if ( !$disTab ) {
        push @{$rsp->{data}}, "Could not open table: discoverydata.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        return;
    }

    my @disData = $disTab->getAllAttribsWhere( "method='zvm' and otherdata='zvmhost.$zvmHost'", 'node' );
    push @{$rsp->{data}}, "Discovered ".($#disData+1)." nodes running on $zvmHost.";

    if ( @disData ) {
        push @{$rsp->{data}}, sprintf("    %-20s%-8s", 'NODE', 'z/VM USERID');
        foreach ( @disData ) {
             push @{$rsp->{data}}, sprintf("    %-20s%-8s", $_->{'node'}, $discoveredNodes{$_->{'node'}} ); 
        }
    }

    removeHostInfo( $callback, $zvmHost );
    
    xCAT::MsgUtils->message( "I", $rsp, $callback );
    xCAT::MsgUtils->message( "I", "z/VM discovery stopped for z/VM host: $zvmHost" );

    return;
}


#-------------------------------------------------------

=head3  updateDiscoverydata

    Description : Update the discoverydata table.
    Arguments   : Callback handle
                  function: 'add' is the only function
                    currently supported.
                  verbose flag
                  z/VM host node name
                  Virtual machine userid
                  discoverable hash which contains lots of properties
    Returns     : None.
    Example     : updateDiscoverydata( $callback, 'add', $verbose, $zvmHost,
                                       $activeSystem, \%discoverable ):
    
=cut

#-------------------------------------------------------
sub updateDiscoverydata{
    my ( $callback, $function, $verbose, $zvmHost, $activeSystem, $discoverableRef ) = @_;
    my %discoverable = %$discoverableRef;

    my %discoverInfo;
    my $disTab = xCAT::Table->new("discoverydata");
    if ( !$disTab ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not open table: discoverydata.";
        xCAT::MsgUtils->message( "E", $rsp, $callback );
        goto FINISH_updateDiscoverydata;
    }

    if ( $function = 'add' ) {
        # Create a row in the discoverydata table to represent this discovered system.
        $discoverInfo{'arch'} = "s390x";
        $discoverInfo{'cpucount'} = $discoverable{$activeSystem}{'cpuCount'};
        $discoverInfo{'memory'} = $discoverable{$activeSystem}{'memory'};
        $discoverInfo{'method'} = "zvm";
        $discoverInfo{'node'} = $discoverable{$activeSystem}{'node'};
        $discoverInfo{'otherdata'} = 'zvmhost.' . $zvmHost;

        # Set the discovery time.
        my ($sec,  $min,  $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
        my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                               $mon + 1, $mday, $year + 1900, $hour, $min, $sec);
        $discoverInfo{'discoverytime'} = $currtime;

        # Update the discoverydata table.
        $disTab->setAttribs({uuid => $discoverable{$activeSystem}{'uuid'}}, \%discoverInfo);
        $disTab->commit();
    }

FINISH_updateDiscoverydata:
    return;
}
1;
