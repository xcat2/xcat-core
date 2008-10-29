#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle rolling updates
#
#####################################################

package xCAT_plugin::rollupdate;

require xCAT::NodeRange;
require xCAT::NameRange;
require xCAT::Table;
require Data::Dumper;
require Getopt::Long;
require xCAT::MsgUtils;
require File::Path;
use strict;
use warnings;

#
# Globals
#
$::LOGDIR="/var/log/xcat";
$::LOGFILE="rollupdate.log";

#------------------------------------------------------------------------------

=head1    rollupdate   

This program module file supports the cluster rolling update functions.

Supported commands:
    rollupdate - Create scheduler job command files and submit the jobs
	rebootnodes - Reboot the updategroup in response to request from scheduler 
				  job

If adding to this file, please take a moment to ensure that:

    1. Your contrib has a readable pod header describing the purpose and use of
      the subroutine.

    2. Your contrib is under the correct heading and is in alphabetical order
    under that heading.

    3. You have run tidypod on this file and saved the html file

=cut

#------------------------------------------------------------------------------

=head2    Cluster Rolling Update

=cut

#------------------------------------------------------------------------------

#----------------------------------------------------------------------------

=head3  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------
sub handled_commands {
    return {
             rollupdate  => "rollupdate",
             rebootnodes => "rollupdate"
    };
}

#----------------------------------------------------------------------------

=head3   preprocess_request


        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub preprocess_request {

    #   set management node as server for all requests
    #   any requests sent to service node need to get
    #   get sent up to the MN

    my $req = shift;
    unless ( defined( $req->{_xcatdest} ) ) {
        $req->{_xcatdest} = xCAT::Utils->get_site_Master();
    }
    return [$req];
}

#----------------------------------------------------------------------------

=head3   process_request

        Process the rolling update commands

        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub process_request {
    $::request  = shift;
    $::CALLBACK = shift;
    $::SUBREQ   = shift;
    my $ret;

    # globals used by all subroutines.
    $::command   = $::request->{command}->[0];
    $::args      = $::request->{arg};
    $::stdindata = $::request->{stdin}->[0];

    # figure out which cmd and call the subroutine to process
    if ( $::command eq "rollupdate" ) {
        $ret = &rollupdate($::request);
    }
    elsif ( $::command eq "rebootnodes" ) {
        $ret = &rebootnodes($::request);
    }

    return $ret;
}

#----------------------------------------------------------------------------

=head3  rollupdate_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

# display the usage
sub rollupdate_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: rollupdate - Submit cluster rolling update jobs \n";
    push @{ $rsp->{data} }, "  rollupdate [-h | --help | -?] \n";
    push @{ $rsp->{data} },
      "  rollupdate [-V | --verbose] [-v | --version] \n ";
    push @{ $rsp->{data} },
"      <STDIN> - stanza file, see /opt/xcat/share/xcat/rollupdate/rollupdate.input.sample";
    push @{ $rsp->{data} }, "                for example \n";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}

#----------------------------------------------------------------------------

=head3   processArgs

        Process the command line and any input files provided on cmd line.

        Arguments:

        Returns:
                0 - OK
                1 - just print usage
                                2 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub processArgs {
    my $gotattrs = 0;

    if ( defined( @{$::args} ) ) {
        @ARGV = @{$::args};
    }
    else {

        #       return 2;   # can run with no args right now
    }

    #    if (scalar(@ARGV) <= 0) {
    #        return 2;
    #    }

    # parse the options
    # options can be bundled up like -vV, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'test|t'    => \$::opt_t,
                              'verbose|V' => \$::opt_V,
                              'version|v' => \$::opt_v,
    );

    # Option -h for Help
    # if user specifies "-t" & "-h" they want a list of valid attrs
    if ( defined($::opt_h) ) {
        return 2;
    }

    #  opt_t not yet supported
    if ( defined($::opt_t) ) {
        my $rsp;
        push @{ $rsp->{data} }, "The \'-t\' option is not yet implemented.";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        return 2;
    }

    # Option -v for version
    if ( defined($::opt_v) ) {
        my $rsp;
        my $version = xCAT::Utils->Version();
        push @{ $rsp->{data} }, "$::command - $version\n";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        return 1;    # no usage - just exit
    }

    # Option -V for verbose output
    if ( defined($::opt_V) ) {
        $::verbose = 1;
        $::VERBOSE = 1;
    }

    # process @ARGV
    #while (my $a = shift(@ARGV))
    #{
    #  no args for command yet
    #}

    # process the <stdin> input file
    if ( defined($::stdindata) ) {
        my $rc = readFileInput($::stdindata);
        if ($rc) {
            my $rsp;
            push @{ $rsp->{data} }, "Could not process file input data.\n";
            xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
            return 1;
        }
    }
    else {

        # No <stdin> stanza file, print usage
        return 2;
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   readFileInput

        Process the command line input piped in from a stanza file.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

        Comments:
                        Set  %::FILEATTRS
                                (i.e.- $::FILEATTRS{attr}=[val])

=cut

#-----------------------------------------------------------------------------
sub readFileInput {
    my ($filedata) = @_;

    my @lines = split /\n/, $filedata;

    foreach my $l (@lines) {

        # skip blank and comment lines
        next if ( $l =~ /^\s*$/ || $l =~ /^\s*#/ );

        # process a real line
        if ( $l =~ /^\s*(\w+)\s*=\s*(.*)\s*/ ) {
            my $attr = $1;
            my $val  = $2;
            $attr =~ s/^\s*//;       # Remove any leading whitespace
            $attr =~ s/\s*$//;       # Remove any trailing whitespace
            $attr =~ tr/A-Z/a-z/;    # Convert to lowercase
            $val  =~ s/^\s*//;
            $val  =~ s/\s*$//;

            # set the value in the hash for this entry
            push( @{ $::FILEATTRS{$attr} }, $val );
        }
    }    # end while - go to next line

    return 0;
}

#----------------------------------------------------------------------------

=head3   rollupdate

        Support for the xCAT rollupdate command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub rollupdate {

    my $rc    = 0;
    my $error = 0;

    # process the command line
    $rc = &processArgs;
    if ( $rc != 0 ) {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        if ( $rc != 1 ) {
            &rollupdate_usage;
        }
        return ( $rc - 1 );
    }

    #
    # Build updategroup nodelists
    #
    my %updategroup;
    foreach my $ugline ( @{ $::FILEATTRS{'updategroup'} } ) {
        my ( $ugname, $ugval ) = split( /\(/, $ugline );
        $ugval =~ s/\)$//;    # remove trailing ')'
        @{ $updategroup{$ugname} } = xCAT::NodeRange::noderange($ugval);
        if ( xCAT::NodeRange::nodesmissed() ) {
            my $rsp;
            push @{ $rsp->{data} }, "Error processing stanza line: ";
            push @{ $rsp->{data} }, "updategroup=" . $ugline;
            push @{ $rsp->{data} }, "Invalid nodes in noderange: "
              . join( ',', xCAT::NodeRange::nodesmissed() );
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
		if ($::VERBOSE) {
			my $rsp;
			push @{ $rsp->{data} }, "Creating update group $ugname with nodes: ";
			push @{ $rsp->{data} }, join(',',@{$updategroup{$ugname}});
           	xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
		}
    }

    foreach my $mgline ( @{ $::FILEATTRS{'mapgroups'} } ) {
        my @ugnamelist = xCAT::NameRange::namerange( $mgline, 0 );
        foreach my $ugname (@ugnamelist) {
            @{ $updategroup{$ugname} } = xCAT::NodeRange::noderange($ugname);
            if ( xCAT::NodeRange::nodesmissed() ) {
                my $rsp;
                push @{ $rsp->{data} }, "Error processing stanza line: ";
                push @{ $rsp->{data} }, "mapgroups=" . $mgline;
                push @{ $rsp->{data} }, "Invalid nodes in group $ugname: "
                  . join( ',', xCAT::NodeRange::nodesmissed() );
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                return 1;
            }
			if ($::VERBOSE) {
				my $rsp;
				push @{ $rsp->{data} }, "Creating update group $ugname with nodes: ";
				push @{ $rsp->{data} }, join(',',@{$updategroup{$ugname}});
           		xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
			}
        }
    }
    unless (%updategroup) {
        my $rsp;
        push @{ $rsp->{data} },
"Error processing stanza input:  No updategroup or mapgroups entries found. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }

    #
    # Build and submit scheduler jobs
    #
    my $scheduler = $::FILEATTRS{'scheduler'}[0];
    $scheduler =~ tr/A-Z/a-z/;
    if (    ( !$scheduler )
         || ( $scheduler eq "loadleveler" ) )
    {
        $rc = ll_jobs( \%updategroup );
    }
    else {

        # TODO:  support scheduler plugins here
        my $rsp;
        push @{ $rsp->{data} }, "Error processing stanza line: ";
        push @{ $rsp->{data} }, "scheduler=" . $::FILEATTRS{'scheduler'}[0];
        push @{ $rsp->{data} }, "Scheduler not supported";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }

    return $rc;
}

#----------------------------------------------------------------------------

=head3   ll_jobs

        Build and submit LoadLeveler jobs

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub ll_jobs {
    my $updategroup = shift;
    my $rc          = 0;

	if ($::VERBOSE) {
		my $rsp;
		push @{ $rsp->{data} }, "Creating LL job command files ";
   		xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
	}
    #
    # Load job command file template
    #
    my $tmpl_file_name = $::FILEATTRS{'jobtemplate'}[0];
    unless ( defined($tmpl_file_name) ) {
        my $rsp;
        push @{ $rsp->{data} },
          "Error processing stanza input:  No jobtemplate entries found. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }

    my $TMPL_FILE;
    unless ( open( $TMPL_FILE, "<", $tmpl_file_name ) ) {
        my $rsp;
        push @{ $rsp->{data} },
"Error processing stanza input:  jobtemplate file $tmpl_file_name not found. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }
	if ($::VERBOSE) {
		my $rsp;
		push @{ $rsp->{data} }, "Reading LL job template file $tmpl_file_name ";
   		xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
	}
    my @lines = <$TMPL_FILE>;
    close $TMPL_FILE;

    # Query LL for list of machines and their status
    my $cmd = "llstatus -r %n %sca 2>/dev/null";
	if ($::VERBOSE) {
		my $rsp;
		push @{ $rsp->{data} }, "Running command: $cmd ";
   		xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
	}
    my @llstatus = xCAT::Utils->runcmd( $cmd, 0 );
    if ( $::RUNCMD_RC != 0 ) {
        my $rsp;
        push @{ $rsp->{data} }, "Could not run llstatus command.";
        push @{ $rsp->{data} }, @llstatus;
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }
    my %machines;
    foreach my $machineline (@llstatus) {
        my ( $mlong, $mshort, $mstatus );
        ( $mlong, $mstatus ) = split( /\!/, $machineline );
        ($mshort) = split( /\./, $mlong );
        $machines{$mlong} = { mname => $mlong, mstatus => $mstatus };
        if ( !( $mlong eq $mshort ) ) {
            $machines{$mshort} = { mname => $mlong, mstatus => $mstatus };
        }
    }

    #
    # Generate job command file for each updategroup
    #
    # Get LL userid
    my $lluser = $::FILEATTRS{scheduser}[0];
    unless ( defined($lluser) ) {
        my $rsp;
        push @{ $rsp->{data} },
          "Error processing stanza input:  No scheduser entries found. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }
    my ( $login, $pass, $uid, $gid );
    ( $login, $pass, $uid, $gid ) = getpwnam($lluser);
    unless ( defined($uid) ) {
        my $rsp;
        push @{ $rsp->{data} },
"Error processing stanza input:  scheduser userid $lluser not in passwd file. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }
    my $lljobs_dir = $::FILEATTRS{jobdir}[0];
    unless ( defined($lljobs_dir) ) {
        my $rsp;
        push @{ $rsp->{data} },
          "Error processing stanza input:  No jobdir entries found. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }
    unless ( -d $lljobs_dir ) {
        unless ( File::Path::mkpath($lljobs_dir) ) {
            my $rsp;
            push @{ $rsp->{data} }, "Could not create directory $lljobs_dir";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
        unless ( chown( $uid, $gid, $lljobs_dir ) ) {
            my $rsp;
            push @{ $rsp->{data} },
              "Could not change owner of directory $lljobs_dir to $lluser";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
    }

    my $run_if_down = $::FILEATTRS{update_if_down}[0];
    $run_if_down =~ tr/[A-Z]/[a-z]/;
    if ( $run_if_down eq 'y' ) { $run_if_down = 'yes'; }

    # TODO - need to handle hierarchy here
    #  one idea:  build a node-to-server mapping that gets passed to
    #		the executable script so that it can figure out dynamically
    #		which service node to contact based on which node LL selects
    #		as the master node for the parallel job.
    #  don't forget to handle service node pools.  a couple ideas:
    #		pass in all service nodes on network and just keep trying to
    #		connect until we get a response from one of them
    #		OR do something similar to what we do with installs and
    #		find who the initial DHCP server for this node was (supposed
    #		to be stored somewhere on the node -- needs investigation)
    my $sitetab = xCAT::Table->new('site');
    my ($tmp) = $sitetab->getAttribs( { 'key' => 'master' }, 'value' );
    my $xcatserver = $tmp->{value};
    ($tmp) = $sitetab->getAttribs( { 'key' => 'xcatiport' }, 'value' );
    my $xcatport = $tmp->{value};

    my @calldirectly;
  ugloop: foreach my $ugname ( keys %{$updategroup} ) {

        # Build substitution strings
        my ( $nodelist, $machinelist );
        my $machinecount = 0;
        foreach my $node ( @{ $updategroup->{$ugname} } ) {
            if ( defined( $machines{$node} )
                 && ( $machines{$node}{'mstatus'} eq "1" ) )
            {
                $machinelist .= " \"$machines{$node}{'mname'}\"";
                $machinecount++;
                $nodelist .= ",$node";
            }
            elsif ( $run_if_down eq 'yes' ) {
                $nodelist .= ",$node";
            }
            elsif ( $run_if_down eq 'cancel' ) {
                my $rsp;
                push @{ $rsp->{data} },
"Node $node is not active in LL and \"update_if_down=cancel\".  Update for updategroup $ugname is canceled.";
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                ++$rc;
                next ugloop;
            }
        }
        if ( defined($nodelist) ) { $nodelist =~ s/^\,//; }

        if ( defined($machinelist) ) {
            $machinelist =~ s/^\s+//;

            # Build output file
            my @jclines;
            foreach my $line (@lines) {
                my $jcline = $line;
                $jcline =~ s/\[\[NODESET\]\]/$ugname/;
                $jcline =~ s/\[\[XNODELIST\]\]/$nodelist/;
                $jcline =~ s/\[\[XCATSERVER\]\]/$xcatserver/;
                $jcline =~ s/\[\[XCATPORT\]\]/$xcatport/;
                $jcline =~ s/\[\[LLMACHINES\]\]/$machinelist/;
                $jcline =~ s/\[\[LLCOUNT\]\]/$machinecount/;
                push( @jclines, $jcline );
            }
            my $lljob_file = $lljobs_dir . "/rollupdate_" . $ugname . ".cmd";
            my $JOBFILE;
            unless ( open( $JOBFILE, ">$lljob_file" ) ) {
                my $rsp;
                push @{ $rsp->{data} }, "Could not open file $lljob_file";
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                return 1;
            }
			if ($::VERBOSE) {
				my $rsp;
				push @{ $rsp->{data} }, "Writing LL job command file $lljob_file ";
   				xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
			}
            print $JOBFILE @jclines;
            close($JOBFILE);
            chown( $uid, $gid, $lljob_file );

            # Submit LL job
            my $cmd = qq~su - $lluser "-c llsubmit $lljob_file"~;
			if ($::VERBOSE) {
				my $rsp;
				push @{ $rsp->{data} }, "Running command: $cmd ";
   				xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
			}
            my @llsubmit = xCAT::Utils->runcmd( "$cmd", 0 );
            if ( $::RUNCMD_RC != 0 ) {
                my $rsp;
                push @{ $rsp->{data} }, "Could not run llsubmit command.";
                push @{ $rsp->{data} }, @llsubmit;
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                return 1;
            }

            my $nltab = xCAT::Table->new('nodelist');
            my @nodes = split( /\,/, $nodelist );
            $nltab->setNodesAttribs(
                                     \@nodes,
                                     {
                                        appstatus =>
                                          "ROLLUPDATE-update_job_submitted"
                                     }
            );
        }
        elsif ( defined($nodelist) ) {

            # No nodes in LL to submit job to -- not able to schedule.
            # Call xCAT directly for all other nodes.
            # TODO - this will serialize updating the updategroups
            #		 is this okay, or do we want forked child processes?
            push @calldirectly, $ugname;
        }
    }

    if ( scalar(@calldirectly) > 0 ) {
		my @children;
        foreach my $ugname (@calldirectly) {
            my $nodelist = join( ',', @{ $updategroup->{$ugname} } );
            my $rsp;
            push @{ $rsp->{data} },
              "No active LL nodes in update group $ugname";
            push @{ $rsp->{data} },
"These nodes will be updated now.  This will take a few minutes...";
            xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
            my $nltab = xCAT::Table->new('nodelist');
            my @nodes = split( /\,/, $nodelist );
            $nltab->setNodesAttribs(
                                     \@nodes,
                                     {
                                        appstatus =>
                                          "ROLLUPDATE-update_job_submitted"
                                     }
            );
			my $childpid = rebootnodes( { command => ['rebootnodes'],
                           _xcat_clienthost => [ $nodes[0] ],
                           arg 				=> [ "loadleveler", $nodelist ]
                          });
			if (defined($childpid) && ($childpid != 0)) {
				push (@children, $childpid);
			}
        }
		# wait until all the children are finished before returning
		foreach my $child (@children) {
			if ($::VERBOSE) {
				my $rsp;
				push @{ $rsp->{data} }, "Waiting for child PID $child to complete ";
   				xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
			}
			waitpid($child,0);  
		}	
    }

    return $rc;
}

#----------------------------------------------------------------------------

=head3   rebootnodes

        Reboot updategroup in response to request from scheduler job

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
			Note that since this command only gets called from the daemon
			through a port request from a node, there is no active callback
			to return messages to.  Log only critical errors to the system log.

			This subroutine will fork a child process to do the actual
			work of shutting down and rebooting nodes.  The parent will return
			immediately to the caller so that other reboot requests can be
			handled in parallel.  It is the caller's responsibility to ensure
			the parent process does not go away and take these children down
			with it.  (Not a problem when called from xcatd, since that is
			"long-running".)
=cut

#-----------------------------------------------------------------------------

sub rebootnodes {
	my $reboot_request = shift;
    my $nodes     = $reboot_request->{node};
    my $command   = $reboot_request->{command}->[0];
	my @reboot_args = @{$reboot_request->{arg}};
    my $scheduler = shift @reboot_args;
	if (($scheduler eq "-V") || ($scheduler eq "--verbose")) {
		$::VERBOSE=1;
		$scheduler = shift @reboot_args;
	}
    my $hostlist  = shift @reboot_args;
    my $rc;

	if ($::VERBOSE) { 
		unless (-d $::LOGDIR) { File::Path::mkpath($::LOGDIR); } 
		open (RULOG, ">>$::LOGDIR/$::LOGFILE");
		print RULOG localtime()." rebootnodes request for $hostlist\n";
		close (RULOG);
	}

    my $client;
    if ( defined( $reboot_request->{'_xcat_clienthost'} ) ) {
        $client = $reboot_request->{'_xcat_clienthost'}->[0];
    }
    if ( defined($client) ) { ($client) = xCAT::NodeRange::noderange($client) }
    unless ( defined($client) ) {  #Not able to do identify the host in question
        return;
    }

	my $childpid = xCAT::Utils->xfork();
    unless (defined $childpid)  { die "Fork failed" };
    if ($childpid != 0) {
		# This is the parent process, just return and let the child do all
		# the work.
		return $childpid;
	}

	# This is now the child process


    # make sure nodes are in correct state
    my @nodes = split( /\,/, $hostlist );
    my $nltab = xCAT::Table->new('nodelist');
    foreach my $node (@nodes) {
        my ($ent) = $nltab->getAttribs( { node => $node }, "appstatus" );
        unless ( defined($ent)
                 && ( $ent->{appstatus} eq "ROLLUPDATE-update_job_submitted" ) )
        {
			if ($::VERBOSE) { 
				open (RULOG, ">>$::LOGDIR/$::LOGFILE");
				print RULOG localtime()." Node $node appstatus not in valid state for rolling update\n";
				print RULOG "The following nodelist will not be processed:\n $hostlist \n";
				close (RULOG);
			}
            my $rsp;
            xCAT::MsgUtils->message(
                "S",
"ROLLUPDATE failure: Node $node appstatus not in valid state for rolling update "
            );
            exit(1);
        }
    }

    # remove nodes from LL
    $scheduler =~ tr/[A-Z]/[a-z]/;
    if ( $scheduler eq 'loadleveler' ) {

        # Query LL for list of machines and their status
        my $cmd = "llstatus -r %n %sca 2>/dev/null";
		if ($::VERBOSE) { 
			open (RULOG, ">>$::LOGDIR/$::LOGFILE");
			print RULOG localtime()." Running command \'$cmd\'\n";
			close (RULOG);
		}
        my @llstatus = xCAT::Utils->runcmd( $cmd, 0 );
        my %machines;
        foreach my $machineline (@llstatus) {
            my ( $mlong, $mshort, $mstatus );
            ( $mlong, $mstatus ) = split( /\!/, $machineline );
            ($mshort) = split( /\./, $mlong );
            $machines{$mlong} = { mname => $mlong, mstatus => $mstatus };
            if ( !( $mlong eq $mshort ) ) {
                $machines{$mshort} = { mname => $mlong, mstatus => $mstatus };
            }
        }
        foreach my $node (@nodes) {
            if ( defined( $machines{$node} )
                 && ( $machines{$node}{'mstatus'} eq "1" ) )
            {
                my $cmd = "llctl -h $node drain";
				if ($::VERBOSE) { 
					open (RULOG, ">>$::LOGDIR/$::LOGFILE");
					print RULOG localtime()." Running command \'$cmd\'\n";
					close (RULOG);
				}
                xCAT::Utils->runcmd( $cmd, 0 );
            }
        }
    }

    # Shutdown the nodes
    # FUTURE:  Replace if we ever develop cluster shutdown function
    my $shutdown_cmd = "shutdown -F &";
	if ($::VERBOSE) { 
		open (RULOG, ">>$::LOGDIR/$::LOGFILE");
		print RULOG localtime()." Running command \'xdsh $hostlist -v $shutdown_cmd\' \n";
		close (RULOG);
	}
    xCAT::Utils->runxcmd(
                          {
                             command => ['xdsh'],
                             node    => \@nodes,
                             arg     => [ "-v", $shutdown_cmd ]
                          },
                          $::SUBREQ,
                          -1
    );
    my $slept    = 0;
    my $alldown  = 1;
    my $nodelist = join( ',', @nodes );
    do {
        $alldown = 1;
        my $pwrstat_cmd = "rpower $nodelist stat";
		if ($::VERBOSE) { 
			open (RULOG, ">>$::LOGDIR/$::LOGFILE");
			print RULOG localtime()." Running command \'$pwrstat_cmd\' \n";
			close (RULOG);
		}
        my $pwrstat = xCAT::Utils->runxcmd( $pwrstat_cmd, $::SUBREQ, -1, 1 );
        foreach my $pline (@{$pwrstat}) {
            my ( $pnode, $pstat, $rest ) = split( /\s+/, $pline );
            if (    ( $pstat eq "Running" )
                 || ( $pstat eq "Shutting" )
                 || ( $pstat eq "on" ) )
            {

                # give up on shutdown after 5 minutes and force the
                # node off
                if ( $slept >= 300 ) {
                    my $pwroff_cmd = "rpower $pnode off";
					if ($::VERBOSE) { 
						open (RULOG, ">>$::LOGDIR/$::LOGFILE");
						print RULOG localtime()." Running command \'$pwroff_cmd\' \n";
						close (RULOG);
					}
                    xCAT::Utils->runxcmd( $pwroff_cmd, $::SUBREQ, -1 );
                }
                else {
                    $alldown = 0;
                    last;
                }
            }
        }

        # If all nodes are not down yet, wait some more
        unless ($alldown) {
            sleep(20);
            $slept += 20;
        }
    } until ($alldown);

    # Run any out-of-band commands here
    # TODO - need to figure what to run
    #		maybe use custom directory and run script based on updategroup name
    #		or something?

    # reboot the nodes
    # reboot command determined by nodehm power/mgt attributes
    my $hmtab = xCAT::Table->new('nodehm');
    my @rpower_nodes;
    my @rnetboot_nodes;
    my $hmtab_entries =
      $hmtab->getNodesAttribs( \@nodes, [ 'node', 'mgt', 'power' ] );
    foreach my $node (@nodes) {
        my $pwr = $hmtab_entries->{$node}->[0]->{power};
        unless ( defined($pwr) ) { $pwr = $hmtab_entries->{$node}->[0]->{mgt}; }
        if ( $pwr eq 'hmc' ) {
            push( @rnetboot_nodes, $node );
        }
        else {
            push( @rpower_nodes, $node );
        }
    }

    # my $nltab = xCAT::Table->new('nodelist');
    $nltab->setNodesAttribs( \@nodes, { appstatus => "ROLLUPDATE-rebooting" } );
    if ( scalar(@rnetboot_nodes) > 0 ) {
        my $rnb_nodelist = join( ',', @rnetboot_nodes );
        my $cmd = "rnetboot $rnb_nodelist -f";
		if ($::VERBOSE) { 
			open (RULOG, ">>$::LOGDIR/$::LOGFILE");
			print RULOG localtime()." Running command \'$cmd\' \n";
			close (RULOG);
		}
        xCAT::Utils->runxcmd( $cmd, $::SUBREQ, 0 );
    }
    elsif ( scalar(@rpower_nodes) > 0 ) {
        my $rp_nodelist = join( ',', @rpower_nodes );
        my $cmd = "rpower $rp_nodelist boot";
		if ($::VERBOSE) { 
			open (RULOG, ">>$::LOGDIR/$::LOGFILE");
			print RULOG localtime()." Running command \'$cmd\' \n";
			close (RULOG);
		}
        xCAT::Utils->runxcmd( $cmd, $::SUBREQ, 0 );
    }

    exit(0);
}

1;
