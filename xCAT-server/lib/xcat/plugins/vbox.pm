# IBM(c) 2008 EPL license http://www.eclipse.org/legal/epl-v10.html
# Ver. 2.1 (4) - sf@mauricebrinkmann.de
#-------------------------------------------------------

=head1
  xCAT plugin package to handle VirtualBox machines

   Supported command:
         rpower

=cut

#-------------------------------------------------------
package xCAT_plugin::vbox;
require Sys::Hostname;
require xCAT::Table;

require xCAT::Utils;

require xCAT::MsgUtils;
use Getopt::Long;
1;

use strict;
use warnings;

require SOAP::Lite;
require xCAT::vboxService;

my $cmd = 'clienttest';

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {rpower => 'nodehm:power,mgt'};
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $cb  = shift;
    if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
    my $nodes    = $req->{node};
    my $service  = "xcat";

    # find service nodes for requested nodes
    # build an individual request for each service node
    my $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");

	my @requests = ();
	
    # build each request for each service node

    foreach my $snkey (keys %$sn)
    {
	my $n=$sn->{$snkey};
	print "snkey=$snkey, nodes=@$n\n";
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            push @requests, $reqcopy;

    }
    return \@requests;
}


#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    our $callback = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
	our $rsp;
	my $node;
   
    my @nodes=@$nodes;

    PROCESSNODES: foreach $node (@nodes) ######################################
    {
        # Load node information from xCAT tables
        my ($error, $url, $username, $password, $vmname, $vncport) = getInfo($node);
        next PROCESSNODES           if ($error == 1);
        last PROCESSNODES           if ($error == 2);
        
        # Create connection to VirtualBox web service and check for errors
        my $vbox = getWebService($url, $username, $password, $node);
        next PROCESSNODES           if (!$vbox);
        
        # Get the machine
        my $machine = getMachine($url, $vbox, $vmname, $node);
        if ($machine)
        {
                        
            # Command differentiation #------------------------------------
            
            if ($command eq "rpower" and @$args > 0)
            {
                powerCtrl($url, $vbox, $machine, $vmname, $node, $vncport, $args);
            }
            
            #else # unrecognized command
            #{
            #    addError("$node: $command unsupported on vm");
            #}
            
            # End Command differentiation #--------------------------------

        } # /existing $machine reference
        
        xCAT::vboxService->IWebsessionManager_logoff($url, $vbox);
        
    } # /for each $node in @nodes
    continue
    {
        # print out status before waiting for others and others and ..
        printMessages();
        
        # yield???
    }
    
    # last chance to print remaining messages
    printMessages();
    
    return;
    
    
    sub addMessage ############################################################
    {
        push @{$rsp->{data}}, shift;
        
    } # /addMessage
	
	sub addError ##############################################################
    {
        push @{$rsp->{error}}, shift;
        
    } # /addError
    
    
    sub printMessages #########################################################
    {
        if (defined($rsp->{data}) or defined($rsp->{error}))
        {
			if (defined($rsp->{error}))
			{
				push @{$rsp->{errorcode}}, 1;
				xCAT::MsgUtils->message("E", $rsp, $callback, 0);
			}
			else
			{
				xCAT::MsgUtils->message("I", $rsp, $callback, 0);
			}
        }
        
    } # /printMessages
    
    
    sub powerCtrl #############################################################
    {
        my  ($url, $vbox, $machine, $vmname, $node, $vncport, $args) =
            (shift, shift, shift, shift, shift, shift, shift);
        
        # Get state of the machine first
        my $vmstate = xCAT::vboxService->IMachine_getState($url, $machine);
        
        # Check if there is anything to do
        if (!$vmstate)
        {
            addError("$node: Can not determine vm's state!");
            return;
        }
        elsif ($vmstate =~ m/^PoweredOff|^Aborted|^Saved/)
        { 
            if ($args->[0] eq "off")
            {
                addMessage("$node: off");
                return;
            }
            elsif ($args->[0] =~ m/^reset|^boot/)
            {
                # if machine is off: turn on when reset was choosen
                $args->[0] = "on reset";
            }
            elsif ($args->[0] =~ m/^stat/)
            {
                # addMessage("$node: off ($vmstate)");
				addMessage("$node: off");
                return;
            }
        }
        else
        {
            if ($args->[0] eq "on")
            {
                addMessage("$node: on");
                return;
            }
            elsif ($args->[0] =~ m/^stat/)
            {
                # addMessage("$node: on ($vmstate)");
				addMessage("$node: on");
                return;
            }
        }
        
        # Determine machine's UUID - Should work since we got the state
        my $uuid = xCAT::vboxService->IMachine_getId($url, $machine);

        # Open Session
        my $session = getSession($url, $vbox, $node, $vmname);
        if ($session)
        {
            # Decide what to do
            if ($args->[0] =~ m/^on/)
            {
                powerOn($url, $vbox, $session, $uuid, $node, $vncport, $args);
            }
            else
            {
                powerOff($url, $vbox, $session, $machine, $uuid, $node, $args);
            }
            
            xCAT::vboxService->ISession_close($url, $session);
        } # /existing $session
        
        return;
        
    
        sub powerOn #**********************************************************
        {
            my  ($url, $vbox, $session, $uuid, $node, $vncport, $args) =
                (shift, shift, shift, shift, shift, shift, shift);
				
			##########################
			xCAT::vboxService->IVirtualBox_openSession(
                    $url, $vbox, $session, $uuid);
					
			my $directmachine = xCAT::vboxService->ISession_getMachine($url, $session);
			if (!$directmachine)
			{
				addError("$node: Could not access mutable machine");
			}
			else
			{
				my $vrdp = xCAT::vboxService->IMachine_getVRDPServer(
							$url, $directmachine);
							
				my $portno = xCAT::vboxService->IVRDPServer_getPort($url, $vrdp);
				if ($vncport and ($vncport != $portno))
				{
					# If port is specified but different: Update machine settings
					xCAT::vboxService->IVRDPServer_setPort($url, $vrdp, $vncport);
					xCAT::vboxService->IMachine_saveSettings($url, $directmachine);
				} 
				elsif (!$vncport)
				{
					# If not specified yet: Save port to xCAT db
					$vncport = $portno;
					my $vmTab = openTable('vm');
					$vmTab->setNodeAttribs($node,{vncport=>$vncport});
					$vmTab->close();
				}
				xCAT::vboxService->IManagedObjectRef_release($url, $vrdp);
				xCAT::vboxService->IManagedObjectRef_release($url, $directmachine);
			}
			
			xCAT::vboxService->ISession_close($url, $session);
			##############################
            
            my $progress =  xCAT::vboxService->IVirtualBox_openRemoteSession(
                            $url, $vbox, $session, $uuid, "vrdp", "");
                            
            if (!$progress)
            {
                addError("$node: Can not open remote session");
            }
            else # existing $progress
            {
                xCAT::vboxService->IProgress_waitForCompletion(
                    $url, $progress, -1);
            
                if (xCAT::vboxService->IProgress_getCompleted(
                    $url, $progress))
                {
                    addMessage("$node: $args->[0]");
                }
                else # not successfully completed
                {
                    addError("$node: Power on failed");
                }
                
            } # /existing $progress
            
            return;
            
        } # /powerOn
        
        
        sub powerOff #*********************************************************
        {
            my  ($url, $vbox, $session, $machine, $uuid, $node, $args) =
                (shift, shift, shift, shift, shift, shift, shift);
            
            # Lock session with machine
            my $vmsessionstate =    xCAT::vboxService->IMachine_getSessionState(
                                    $url, $machine);
                                    
            if ($vmsessionstate eq "Open")
            {
                xCAT::vboxService->IVirtualBox_openExistingSession(
                    $url, $vbox, $session, $uuid);
            }
            elsif ($vmsessionstate eq "Closed")
            {
                xCAT::vboxService->IVirtualBox_openSession(
                    $url, $vbox, $session, $uuid);
            } 
            else # !$vmsessionstate
            {
                addError("$node: No direct session to machine");
            }
            
			# The session is now locked with the machine, now its direct session or console can be optained and manipulated
            # Now get the console for the mutable machine
            my $console = xCAT::vboxService->ISession_getConsole($url, $session);
            if (!$console)
            {
                addError("$node: No console for mutable machine");
            }
            else # existing $console
            {
                
                if ($args->[0] =~ m/^reset|^boot/)
                {
                    xCAT::vboxService->IConsole_reset($url, $console);
                    xCAT::vboxService->IManagedObjectRef_release($url, $console);
                    addMessage("$node: on reset");
                    
                    xCAT::vboxService->IManagedObjectRef_release($url, $console);
                    return;
                }
                else
                {
                    xCAT::vboxService->IConsole_powerButton($url, $console);
                    unless (xCAT::vboxService->IConsole_getPowerButtonHandled(
                                        $url, $console) eq "true")
                    {
						# In case of no reaction: force to power down machine
						xCAT::vboxService->IConsole_powerDown($url, $console);
                    }
					addMessage("$node: off");
                }
                
                xCAT::vboxService->IManagedObjectRef_release($url, $console);
                
            } # /existing $console
            
            return;
            
        } # /powerOff
        
        
    } # /powerCtrl
    
    
    sub getSession ############################################################
    {
        my $sess;
        my ($url, $vbox, $node, $vmname) = (shift, shift, shift, shift);
        
        eval {
        $sess = xCAT::vboxService->IWebsessionManager_getSessionObject($url, $vbox);
        };
        
        return $sess if ($sess and not $@);
        
        addError("$node: No session for $vmname on web service @ $url.");
        return undef;
    } # /getSession
    
    
    sub getMachine ############################################################
    {
        my $machine;
        my ($url, $vbox, $vmname, $node) = (shift, shift, shift, shift);
        
        eval {
        $machine = xCAT::vboxService->IVirtualBox_findMachine($url, $vbox, $vmname);
        };
        
        return $machine if ($machine and not $@);
        
        addError("$node: VM $vmname not known by the web service @ $url.");
        return undef;
    } # /getMachine
    
    
    sub getWebService #########################################################
    {
        my $ws;
        my ($url, $user, $passwd, $node) = (shift, shift, shift, shift);
        
        eval {
        $ws = xCAT::vboxService->IWebsessionManager_logon($url, $user, $passwd);
        };
        
        return $ws if ($ws and not $@);
        
        addError("$node: No connection to the web service @ $url.");
        return undef;
    } # /getWebService
    
    
    sub getInfo ###############################################################
    {
        my $node = shift;
        
        # Open tables first, return in case of a critical error = 2
        my $hostsTab = openTable('hosts');
        return (2, undef, undef, undef, undef)   if (!$hostsTab);
        
        my $vmTab = openTable('vm');
        return (2, undef, undef, undef, undef)   if (!$vmTab);
        
        my $websrvTab = openTable('websrv');
        return (2, undef, undef, undef, undef)   if (!$websrvTab);
        
        # Load attributes, return in case of missing information error = 1
        my $values;
		
		my @attributes  = ('host','vncport','comments');
        $values = loadValues($vmTab, $node, \@attributes);
        return (1, undef, undef, undef, undef)   if (!defined($values));
            
        my $hostname	= $values->{host};
        my $vncport		= $values->{vncport};
        my $comments	= $values->{comments};
		my $vmname		= undef;
		if ($comments 	=~ m/vmname:(.+)!/) {
			$vmname 	=  $1;
		} else {
			$vmname 	=  $node;
		}
        
        @attributes  = ('port','username', 'password');
        $values = loadValues($websrvTab, $hostname, \@attributes);
        return (1, undef, undef, undef, undef)   if (!defined($values));
            
        my $port     = $values->{port};
        my $username = $values->{username};
        my $password = $values->{password};
        
        @attributes  = ('ip');
        $values = loadValues($hostsTab, $hostname, \@attributes);
        return (1, undef, undef, undef, undef)   if (!defined($values));
            
        my $ipaddr   = $values->{ip};
        my $url      = "http://$ipaddr:$port/";
        
        return (0, $url, $username, $password, $vmname, $vncport);
        
        
        sub loadValues #*******************************************************
        {
            my ($table, $node, $attributes) = (shift, shift, shift);
            my ($values) = $table->getAttribs({'node'=>$node}, @$attributes);
            $table->close;
            
            addError("$node: Missing information: @$attributes")
                if (!defined($values));
                
            return $values;
            
        } # /loadValues
        
        
        sub openTable #********************************************************
        {
            my $tabname = shift;
            my $table = xCAT::Table->new($tabname);
            
            # try to create vbox tables if they don't exist yet
            if (!$table and $tabname =~ m/websrv/)
            {
                $table = xCAT::Table->new( $tabname, -create=>1, -autocommit=>1 );
                $table->close;
                addMessage("[xCAT] Info: The table $tabname has been created.");
                $table = xCAT::Table->new($tabname);
            }
            
            addError("[xCAT] Can not open table: $tabname. Command aborted.")
                if (!$table);
            
            return $table;
            
        } # /loadValues
        
    } # /getInfo
}

1;
