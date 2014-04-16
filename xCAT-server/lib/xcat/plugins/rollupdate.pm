#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle rolling updates
#
#####################################################

package xCAT_plugin::rollupdate;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

require xCAT::NodeRange;
require xCAT::Table;
require xCAT::Utils;
require xCAT::TableUtils;
require Data::Dumper;
require Getopt::Long;
require xCAT::MsgUtils;
require File::Path;
use Text::Balanced qw(extract_bracketed);
use Safe;
my $evalcpt = new Safe;

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
   runrollupdate - Reboot the updategroup in response to request from scheduler 
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
             runrollupdate => "rollupdate"
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
     #if already preprocessed, go straight to request
    if (   (defined($req->{_xcatpreprocessed}))
        && ($req->{_xcatpreprocessed}->[0] == 1))
    {
        return [$req];
    }

    $req->{_xcatdest} = xCAT::TableUtils->get_site_Master();
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
    elsif ( $::command eq "runrollupdate" ) {
        $ret = &runrollupdate($::request);
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
      "  rollupdate [-V | --verbose] [-v | --version] [-t | --test] \n ";
    push @{ $rsp->{data} },
"      <STDIN> - stanza file, see /opt/xcat/share/xcat/rollupdate/rollupdate.input.sample";
    push @{ $rsp->{data} }, "                for example \n";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}


#----------------------------------------------------------------------------

=head3  runrollupdate_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

# display the usage
sub runrollupdate_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: runrollupdate - Run submitted cluster rolling update job \n";
    push @{ $rsp->{data} }, "  runrollupdate [-h | --help | -?] \n";
    push @{ $rsp->{data} },
      "  runrollupdate [-V | --verbose] [-v | --version] scheduler datafile \n ";
    push @{ $rsp->{data} },
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

    if ( defined ($::args) && @{$::args} ) {
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
        #$::test = 1;
        $::TEST = 1;
       # my $rsp;
       # push @{ $rsp->{data} }, "The \'-t\' option is not yet implemented.";
       # xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
       # return 2;
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


    if ( $::command eq "rollupdate" ) {
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
    }
    elsif ( $::command eq "runrollupdate" ) {
        # process @ARGV
        $::scheduler = shift(@ARGV);
        $::datafile = shift(@ARGV);
        $::ll_reservation_id = shift(@ARGV);
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

    my $rf_rc=0;
    my $rf_err= "";
    my $prev_attr = "";
    foreach my $l (@lines) {

        # skip blank and comment lines
        next if ( $l =~ /^\s*$/ || $l =~ /^\s*#/ );

        # process a real line
        if ( $l =~ /^\s*(\w+)\s*=\s*(.*)\s*/ ) {
            my $attr = $1;
            my $val  = $2;
            my $orig_attr = $attr;
            my $orig_val  = $val;
            $attr =~ s/^\s*//;       # Remove any leading whitespace
            $attr =~ s/\s*$//;       # Remove any trailing whitespace
            $attr =~ tr/A-Z/a-z/;    # Convert to lowercase
            $val  =~ s/^\s*//;
            $val  =~ s/\s*$//;

            # Convert the following values to lowercase
            if ( ($attr eq 'scheduler') ||
                 ($attr eq 'updateall') ||
                 ($attr eq 'update_if_down') ||
                 ($attr eq 'skipshutdown') ) {
                $val =~ tr/A-Z/a-z/;   
                if ( ($attr eq 'scheduler') &&
                     ($val ne 'loadleveler')   ) {
                    $rf_err = "Stanza \'$orig_attr = $orig_val\' is not valid.  Valid values are \'loadleveler\'.";                    
                    $rf_rc=1;
                    my $rsp;
                    push @{ $rsp->{data} },$rf_err;
                    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                }
                if ( ($attr eq 'updateall') &&
                     (($val ne 'yes') &&
                      ($val ne 'y')   &&
                      ($val ne 'no')  &&
                      ($val ne 'n')      )     ) {
                    $rf_err = "Stanza \'$orig_attr = $orig_val\' is not valid.  Valid values are \'yes\' or \'no\'.";                    
                    $rf_rc=1;
                    my $rsp;
                    push @{ $rsp->{data} },$rf_err;
                    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                }
                if ( ($attr eq 'update_if_down') &&
                     (($val ne 'yes') &&
                      ($val ne 'y')   &&
                      ($val ne 'no')  &&
                      ($val ne 'n')   &&
                      ($val ne 'cancel')      )     ) {
                    $rf_err = "Stanza \'$orig_attr = $orig_val\' is not valid.  Valid values are \'yes\', \'no\', or \'cancel\'.";                    
                    $rf_rc=1;
                    my $rsp;
                    push @{ $rsp->{data} },$rf_err;
                    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                }
                if ( ($attr eq 'skipshutdown') &&
                     (($val ne 'yes') &&
                      ($val ne 'y')   &&
                      ($val ne 'no')  &&
                      ($val ne 'n')      )       ) {
                    $rf_err = "Stanza \'$orig_attr = $orig_val\' is not valid.  Valid values are \'yes\' or \'no\'.";                    
                    $rf_rc=1;
                    my $rsp;
                    push @{ $rsp->{data} },$rf_err;
                    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                }
            }

            # Remove surrounding quotes in the following values
            if ( ($attr eq 'bringupappstatus') ) {
                $val =~ s/^['"]//;   
                $val =~ s/['"]$//;   
            }
 
            # Set some required defaults if not specified
            if (($prev_attr eq "prescript") && ($attr ne "prescriptnodes")) {
                push ( @{ $::FILEATTRS{'prescriptnodes'} }, 'ALL_NODES_IN_UPDATEGROUP' );
            }
            if (($prev_attr eq "outofbandcmd") && ($attr ne "outofbandnodes")) {
                push ( @{ $::FILEATTRS{'outofbandnodes'} }, 'ALL_NODES_IN_UPDATEGROUP' );
            }
            if (($prev_attr eq "mutex") && ($attr ne "mutex_count")) {
                push ( @{ $::FILEATTRS{'mutex_count'} }, '1' );
            }
            if (($prev_attr eq "nodegroup_mutex") && ($attr eq "mutex_count")) {
               $attr = "nodegroup_mutex_count";
            }
            if (($prev_attr eq "nodegroup_mutex") && ($attr ne "nodegroup_mutex_count")) {
                push ( @{ $::FILEATTRS{'nodegroup_mutex_count'} }, '1' );
            }

            # set the value in the hash for this entry
            push( @{ $::FILEATTRS{$attr} }, $val );
            $prev_attr = $attr;
        }
    }    # end while - go to next line

    return $rf_rc;
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
    if ($::VERBOSE) {
        unless ( -d $::LOGDIR) {
            unless ( File::Path::mkpath($::LOGDIR) ) {
                my $rsp;
                push @{ $rsp->{data} }, "Could not create directory $::LOGDIR, logging is disabled.";
                xCAT::MsgUtils->message( "W", $rsp, $::CALLBACK );
                $::VERBOSE = 0;
                $::verbose = 0;
            }
        }
    }
    if ($::VERBOSE) {
        my $rsp;
        push @{ $rsp->{data} }, "Running rollupdate command... ";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG "\n\n";
        print RULOG localtime()." Running rollupdate command...\n";
        close (RULOG);
    }

    #
    # Build updategroup nodelists
    #
    my %updategroup;

    # Check for updateall and required stanzas
    $::updateall=0;
    $::updateall_nodecount=1;
    if ( defined($::FILEATTRS{updateall}[0])  &&
     ( ($::FILEATTRS{updateall}[0] eq 'yes') ||
       ($::FILEATTRS{updateall}[0] eq 'y'  ) ) ) {
        $::updateall=1;
        if ( defined($::FILEATTRS{updateall_nodes}[0])){
            my $ugname = "UPDATEALL".time();
            my $ugval = $::FILEATTRS{updateall_nodes}[0];
            @{ $updategroup{$ugname} } = xCAT::NodeRange::noderange($ugval);
        } else {
            my $rsp;
            push @{ $rsp->{data} },
"Error processing stanza input:  updateall=yes but no updateall_nodes specified. ";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
        if ( defined($::FILEATTRS{updateall_nodecount}[0]) ) {
            $::updateall_nodecount=$::FILEATTRS{updateall_nodecount}[0];
        } else {
            my $rsp;
            push @{ $rsp->{data} },
"Error processing stanza input:  updateall=yes but no updateall_nodecount specified. ";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
    } else {
    # Standard update (NOT updateall)
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
                my $prt_ugn = join(',',@{$updategroup{$ugname}});
                push @{ $rsp->{data} }, "Creating update group $ugname with nodes: ";
                push @{ $rsp->{data} }, $prt_ugn;
                xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Creating update group $ugname with nodes: \n";
                print RULOG  "$prt_ugn\n";
                close (RULOG);
            }
        }

        foreach my $mgline ( @{ $::FILEATTRS{'mapgroups'} } ) {
            #my @ugnamelist = xCAT::NameRange::namerange( $mgline, 0 );
            my @ugnamelist = xCAT::NodeRange::noderange( $mgline, 0, 1, genericrange=>1 );
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
                    my $prt_ugn = join(',',@{$updategroup{$ugname}});
                    push @{ $rsp->{data} }, "Creating update group $ugname with nodes: ";
                    push @{ $rsp->{data} }, $prt_ugn;
                    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." Creating update group $ugname with nodes: \n";
                    print RULOG  "$prt_ugn\n";
                    close (RULOG);
                }
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
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Creating LL job command files \n";
        close (RULOG);
     }

    # Verify scheduser exists and can run xCAT runrollupdate cmd
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
"Error processing stanza input:  scheduser userid $lluser not defined in system. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }
    if ( &check_policy($lluser,'runrollupdate') ) {
        my $rsp;
        push @{ $rsp->{data} },
          "Error processing stanza input:  scheduser userid $lluser not listed in xCAT policy table for runrollupdate command.  Add to policy table and ensure userid has ssh credentials for running xCAT commands. ";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }

    # Translate xCAT names to LL names
    $::XLATED = {};
    if (defined($::FILEATTRS{translatenames}[0])) {
       foreach my $xlate_stanza( @{ $::FILEATTRS{'translatenames'} } ) {
          translate_names($xlate_stanza);
       }
    }
    

    # Create LL floating resources for mutual exclusion support
    #   and max_updates
    if (&create_LL_mutex_resources($updategroup,$::updateall) > 0) {
        return 1;
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
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Reading LL job template file $tmpl_file_name \n";
        close (RULOG);
    }
    my @lines = <$TMPL_FILE>;
    close $TMPL_FILE;

    # Query LL for list of machines and their status
    my $cmd = "llstatus -r %n %sta 2>/dev/null";
    if ($::VERBOSE) {
        my $rsp;
        push @{ $rsp->{data} }, "Running command: $cmd ";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Running command: $cmd  \n";
        close (RULOG);
    }
    my @llstatus = xCAT::Utils->runcmd( $cmd, 0 );
    if ( $::RUNCMD_RC != 0 ) {
        my $rsp;
        push @{ $rsp->{data} }, "Could not run llstatus command.";
        push @{ $rsp->{data} }, @llstatus;
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Could not run llstatus command.  \n";
        print RULOG @llstatus;
        close (RULOG);
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

    my $nodestatus = $::FILEATTRS{bringupstatus}[0];
    my $appstatus = $::FILEATTRS{bringupappstatus}[0];
    my $df_statusline = "";
    if ( defined($appstatus) ) {
        $df_statusline = "bringupappstatus=$appstatus\n";
    } elsif ( defined($nodestatus) ) {
        $df_statusline = "bringupstatus=$nodestatus\n";
    } else {
        $df_statusline = "bringupstatus=booted\n";
    }

    my $run_if_down = "cancel";
    if ( defined($::FILEATTRS{update_if_down}[0]) ) {
        $run_if_down = $::FILEATTRS{update_if_down}[0];
        $run_if_down =~ tr/[A-Z]/[a-z]/;
        if ( $run_if_down eq 'y' ) { $run_if_down = 'yes'; }
        if ( $::updateall && ($run_if_down eq 'yes') ) { 
            $run_if_down = 'cancel'; 
            my $rsp;
            push @{ $rsp->{data} }, "update_all=yes, but update_if_down is yes which is not allowed.  update_if_down=cancel will be assumed. ";
            xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        }
    }

    my @calldirectly;
  ugloop: foreach my $ugname ( keys %{$updategroup} ) {

        $::updateall_feature = " ";
        if ($::updateall) { $::updateall_feature = "XCAT_$ugname"; }
        # Build node substitution strings
        my ( $nodelist, $machinelist );
        my $machinecount = 0;
        foreach my $node ( @{ $updategroup->{$ugname} } ) {
            my $xlated_node;
            if ( defined ($::XLATED{$node}) ){
               $xlated_node = $::XLATED{$node};
            } else {
               $xlated_node = $node;
            }
            if ( defined( $machines{$xlated_node} )
                 && ( $machines{$xlated_node}{'mstatus'} eq "1" ) ) {
                $machinelist .= " $machines{$xlated_node}{'mname'}";
                $machinecount++;
                $nodelist .= ",$node";
            } elsif ( $run_if_down eq 'yes' ) {
                if ( defined( $machines{$xlated_node} ) ) {
                   # llmkres -D will allow reserving down nodes as long
                   # as they are present in the machine list
                    $machinelist .= " $machines{$xlated_node}{'mname'}";
                    $machinecount++;
                }
                $nodelist .= ",$node";
            } elsif ( $run_if_down eq 'cancel' ) {
                my $rsp;
                push @{ $rsp->{data} },
"Node $node is not active in LL and \"update_if_down=cancel\".  Update for updategroup $ugname is canceled.";
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                ++$rc;
                next ugloop;
            }
        }
        if ( ($machinecount == 0) && ($::updateall) ) {
            my $rsp;
            push @{ $rsp->{data} },
"\"updateall=yes\" and \"update_if_down=no\", but there are no nodes specifed in the updateall noderange that are currently active in LoadLeveler.  Update for updategroup $ugname is canceled.";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            ++$rc;
            next ugloop;
        }

        if ( defined($nodelist) ) { $nodelist =~ s/^\,//; }
        # Build updategroup data file 
        my @ugdflines;
        push (@ugdflines, "# xCAT Rolling Update data file for update group $ugname \n");
        push (@ugdflines, "\n");
        push (@ugdflines, "updategroup=$ugname\n");
        if ($::updateall){
            push (@ugdflines, "updatefeature=$::updateall_feature\n");
        } else { 
            push (@ugdflines, "nodelist=$nodelist\n");
        }
        if (defined($::FILEATTRS{oldfeature}[0])){
            push (@ugdflines, "oldfeature=$::FILEATTRS{oldfeature}[0]\n");
        } 
        if (defined($::FILEATTRS{newfeature}[0])){
            push (@ugdflines, "newfeature=$::FILEATTRS{newfeature}[0]\n");
        } 
        if (defined($::FILEATTRS{reconfiglist}[0])){
            push (@ugdflines, "reconfiglist=$::FILEATTRS{reconfiglist}[0]\n");
        } 
        push (@ugdflines, "\n");
        push (@ugdflines, &get_prescripts($nodelist));
        if (defined($::FILEATTRS{shutdowntimeout}[0])){
            push (@ugdflines, "shutdowntimeout=$::FILEATTRS{shutdowntimeout}[0]\n");
        } 
        push (@ugdflines, &get_outofband($nodelist));
        push (@ugdflines, &get_bringuporder($nodelist));
        push (@ugdflines, $df_statusline);
        if (defined($::FILEATTRS{bringuptimeout}[0])){
            push (@ugdflines, "bringuptimeout=$::FILEATTRS{bringuptimeout}[0]\n");
        } 
        if (defined($::FILEATTRS{translatenames}[0])){
            foreach my $xlate_stanza( @{ $::FILEATTRS{'translatenames'} } ) {
                push (@ugdflines, "translatenames=$xlate_stanza\n");
            }
        } 
        if (defined($::FILEATTRS{skipshutdown}[0])){
            push (@ugdflines, "skipshutdown=$::FILEATTRS{skipshutdown}[0]\n");
        } 
        my $ugdf_file = $lljobs_dir . "/rollupdate_" . $ugname . ".data";
        my $UGDFFILE;
        unless ( open( $UGDFFILE, ">$ugdf_file" ) ) {
            my $rsp;
            push @{ $rsp->{data} }, "Could not open file $ugdf_file";
            xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
            return 1;
        }
        if ($::VERBOSE) {
            my $rsp;
            push @{ $rsp->{data} }, "Writing xCAT rolling update data file $ugdf_file ";
            xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." Writing xCAT rolling update data file $ugdf_file \n";
            close (RULOG);
        }
        print $UGDFFILE @ugdflines;
        close($UGDFFILE);
        chown( $uid, $gid, $ugdf_file );

        if ($machinecount > 0) {
            my $llhl_file;
            if ( !$::updateall ) {
                # Build LL hostlist file
                $machinelist =~ s/^\s+//;
                my $hllines = $machinelist;
                $hllines =~ s/"//g;
                $hllines =~ s/\s+/\n/g;
                $hllines .= "\n";
                $llhl_file = $lljobs_dir . "/rollupdate_" . $ugname . ".hostlist";
                my $HLFILE;
                unless ( open( $HLFILE, ">$llhl_file" ) ) {
                    my $rsp;
                    push @{ $rsp->{data} }, "Could not open file $llhl_file";
                    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                    return 1;
                }
                if ($::VERBOSE) {
                    my $rsp;
                    push @{ $rsp->{data} }, "Writing LL hostlist file $llhl_file ";
                       xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                }
                print $HLFILE $hllines;
                close($HLFILE);
                chown( $uid, $gid, $llhl_file );
            }           

            # Build reservation callback script 
            
my @rcblines;
            my $rcbcmd = $::FILEATTRS{'reservationcallback'}[0];
            if (!defined($rcbcmd)){ $rcbcmd = "$::XCATROOT/bin/runrollupdate"; }
            push (@rcblines, "#!/bin/sh \n");
            push (@rcblines, "# LL Reservation Callback script for xCAT Rolling Update group $ugname \n");
            push (@rcblines, "\n");
            push (@rcblines, "if [ \"\$2\"  ==  \"RESERVATION_ACTIVE\"  ] ; then\n");
            my $send_verbose = "";
            if ($::VERBOSE) {$send_verbose="--verbose";}
            push (@rcblines, "    $rcbcmd $send_verbose loadleveler $ugdf_file \$1 &\n");
            push (@rcblines, "fi \n");
            push (@rcblines, "\n");
            my $llrcb_file = $lljobs_dir . "/rollupdate_" . $ugname . ".rsvcb";
            my $RCBFILE;
            unless ( open( $RCBFILE, ">$llrcb_file" ) ) {
                my $rsp;
                push @{ $rsp->{data} }, "Could not open file $llrcb_file";
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                return 1;
            }
            if ($::VERBOSE) {
                my $rsp;
                push @{ $rsp->{data} }, "Writing LL reservation callback script $llrcb_file ";
                xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Writing LL reservation callback script $llrcb_file \n";
                close (RULOG);
            }
            print $RCBFILE @rcblines;
            close($RCBFILE);
            chown( $uid, $gid, $llrcb_file );
            chmod( 0700, $llrcb_file );

            # Build output file
            my $mutex_string = &get_mutex($ugname);
            my $lastcount = 0;
            my $llcount = $machinecount;
            if (($::updateall) &&
                ($machinecount gt $::updateall_nodecount)) {
                $lastcount = $machinecount % $::updateall_nodecount;
                $llcount = $::updateall_nodecount;
            }
            my @jclines;
            my @jclines2;
            foreach my $line (@lines) {
                my $jcline = $line;
                my $jcline2;
                $jcline =~ s/\[\[NODESET\]\]/$ugname/;
                $jcline =~ s/\[\[JOBDIR\]\]/$lljobs_dir/;
                if (defined($nodelist)){
                    $jcline =~ s/\[\[XNODELIST\]\]/$nodelist/;
                } else {
                    $jcline =~ s/\[\[XNODELIST\]\]//;
                }
                if (defined($llhl_file)){
                    $jcline =~ s/\[\[LLHOSTFILE\]\]/$llhl_file/;
                } else {
                    $jcline =~ s/\[\[LLHOSTFILE\]\]//;
                }
                if (defined($::FILEATTRS{oldfeature}[0])){
                    $jcline =~ s/\[\[OLDFEATURE\]\]/$::FILEATTRS{oldfeature}[0]/;
                } else {
                    $jcline =~ s/\[\[OLDFEATURE\]\]//;
                }
                $jcline =~ s/\[\[UPDATEALLFEATURE\]\]/$::updateall_feature/;
                $jcline =~ s/\[\[MUTEXRESOURCES\]\]/$mutex_string/;
                # LL is VERY picky about extra blanks in Feature string
                if ( $jcline =~ /Feature/ ) {
                    $jcline =~ s/\"\s+/\"/g;
                    $jcline =~ s/\s+\"/\"/g;
                    $jcline =~ s/\=\"/\= \"/g;
                }
                if ($lastcount) {
                    $jcline2 = $jcline;
                    $jcline2 =~ s/\[\[LLCOUNT\]\]/$lastcount/;
                    push( @jclines2, $jcline2 );
                }
                if ( $jcline =~ /\[\[LLCOUNT\]\]/ ) {
                   $jcline =~ s/\[\[LLCOUNT\]\]/$llcount/;
                }
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
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Writing LL job command file $lljob_file \n";
                close (RULOG);
            }
            print $JOBFILE @jclines;
            close($JOBFILE);
            chown( $uid, $gid, $lljob_file );
            my $lljob_file2 = $lljobs_dir . "/rollupdate_LAST_" . $ugname . ".cmd";
            if ($lastcount) {
                my $JOBFILE2;
                unless ( open( $JOBFILE2, ">$lljob_file2" ) ) {
                    my $rsp;
                    push @{ $rsp->{data} }, "Could not open file $lljob_file2";
                    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                    return 1;
                }
                if ($::VERBOSE) {
                    my $rsp;
                    push @{ $rsp->{data} }, "Writing LL job command file $lljob_file2 ";
                    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." Writing LL job command file $lljob_file2 \n";
                    close (RULOG);
                }
                print $JOBFILE2 @jclines2;
                close($JOBFILE2);
                chown( $uid, $gid, $lljob_file2 );
            }

            if ($::updateall) {
                &set_LL_feature($machinelist,$::updateall_feature);

            }

            # Need to change status before actually submitting LL jobs
            # If LL jobs happen to run right away, the update code checking
            # for the status may run before we've had a chance to actually update it
            my $nltab = xCAT::Table->new('nodelist');
            my @nodes = split( /\,/, $nodelist );
            xCAT::TableUtils->setAppStatus(\@nodes,"RollingUpdate","update_job_submitted");
            # Submit LL reservation
            my $downnodes = "-D";
            if ($::updateall){$downnodes = " ";}
            my $cmd = qq~su - $lluser "-c llmkres -x -d $::FILEATTRS{'reservationduration'}[0] -f $lljob_file -p $llrcb_file $downnodes "~;
            my $cmd2 = qq~su - $lluser "-c llmkres -x -d $::FILEATTRS{'reservationduration'}[0] -f $lljob_file2 -p $llrcb_file $downnodes "~;
            if ($::VERBOSE) {
                my $rsp;
                push @{ $rsp->{data} }, "Running command: $cmd ";
                xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Running command: $cmd  \n";
                close (RULOG);
            }
            my @llsubmit; 
            if ($::TEST) {
                my $rsp;
                push @{ $rsp->{data} }, "In TEST mode.  Will NOT run command: $cmd ";
                   xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                $::RUNCMD_RC = 0;
            } else {
                my $submit_count = 1;
                if ($::updateall){ 
                   $submit_count = int($machinecount / $::updateall_nodecount);
                   if ($submit_count == 0) {$submit_count = 1;}
                }
                for (1..$submit_count) {
                    @llsubmit = xCAT::Utils->runcmd( "$cmd", 0 );
                    if ( $::RUNCMD_RC != 0 ) {
                        my $rsp;
                        push @{ $rsp->{data} }, "Could not run llmkres command.";
                        push @{ $rsp->{data} }, @llsubmit;
                        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                        return 1;
                    }
                    if ( $::VERBOSE ) {
                        my $rsp;
                        push @{ $rsp->{data} }, @llsubmit;
                        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                        print RULOG @llsubmit;
                        close (RULOG);
                    }
                }
                if ($lastcount) {
                    if ($::VERBOSE) {
                        my $rsp;
                        push @{ $rsp->{data} }, "Running command: $cmd2 ";
                        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                        print RULOG localtime()." Running command: $cmd2  \n";
                        close (RULOG);
                    }
                    @llsubmit = xCAT::Utils->runcmd( "$cmd2", 0 );
                    if ( $::RUNCMD_RC != 0 ) {
                        my $rsp;
                        push @{ $rsp->{data} }, "Could not run llmkres command.";
                        push @{ $rsp->{data} }, @llsubmit;
                        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                        print RULOG @llsubmit;
                        close (RULOG);
                        return 1;
                    }
                    if ( $::VERBOSE ) {
                        my $rsp;
                        push @{ $rsp->{data} }, @llsubmit;
                        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                        print RULOG @llsubmit;
                        close (RULOG);
                    }
                }
            } 
        }
        elsif ( defined($nodelist) ) {

            # No nodes in LL to submit job to -- not able to schedule.
            # Call xCAT directly for all other nodes.
            # TODO - this will serialize updating the updategroups
            #         is this okay, or do we want forked child processes?
            push @calldirectly, $ugname;
        }
    } # end ugloop

    if ( scalar(@calldirectly) > 0 ) {
        my @children;
        foreach my $ugname (@calldirectly) {
            my $nodelist = join( ',', @{ $updategroup->{$ugname} } );
            my $ugdf = $lljobs_dir . "/rollupdate_" . $ugname . ".data";
            my $rsp;
            push @{ $rsp->{data} },
              "No active LL nodes in update group $ugname";
            push @{ $rsp->{data} },
"These nodes will be updated now.  This will take a few minutes...";
            xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
            if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." No active LL nodes in update group $ugname.  These nodes will be updated now.\n";
                close (RULOG);
            }
            my $nltab = xCAT::Table->new('nodelist');
            my @nodes = split( /\,/, $nodelist );
            xCAT::TableUtils->setAppStatus(\@nodes,"RollingUpdate","update_job_submitted");
            my $childpid = runrollupdate( { command => ['runrollupdate'],
                                                arg => [ 'internal','loadleveler', $ugdf ]
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
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Waiting for child PID $child to complete \n";
                close (RULOG);
            }
            waitpid($child,0);  
        }    
    }

    return $rc;
}



#----------------------------------------------------------------------------

=head3   check_policy

        Check the policy table to see if userid is authorized to run command

        Arguments:  userid, command
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

        Comments:

=cut

#-----------------------------------------------------------------------------
sub check_policy {
  my $userid = shift;
  my $xcatcmd = shift;

  my $policytable = xCAT::Table->new('policy');
  unless ($policytable) {
    return 1;
  }

  my $policies = $policytable->getAllEntries;
  $policytable->close;
  foreach my $rule (@$policies) {
    if ( $rule->{name} && 
        (($rule->{name} eq "*")  || ($rule->{name} eq $userid)) ) {
      if ( $rule->{commands} ) {
          if (($rule->{commands} eq "") || ($rule->{commands} eq "*") || ($rule->{commands} =~ /$xcatcmd/) ){
            return 0;  # match found
          }
      } else {
          return 0;  # default match if commands is unset
      }
    }
  }
  return 1;  # no match found
}



#----------------------------------------------------------------------------

=head3   translate_names

        Translate xCAT node names to scheduler names as requested by the user

        Arguments:  $instructions - translation instructions of the form:
                      <xcat_noderange>:/<pattern>/<replacement>/
                    OR
                      <xcat_noderange>:|<pattern>|<replacement>|
        Returns: 
        Globals:
                hash:  $::XLATED{$node}=$xlated_name                
                AND    $::XLATED{$xlated_name}=$node
                to allow easy lookup in either direction
        Error:
        Example:

        Comments:

=cut

#-----------------------------------------------------------------------------
# This is a utility function to create a number out of a string, useful for things like round robin algorithms on unnumbered nodes
sub mknum {
    my $string = shift;
    my $number=0;
    foreach (unpack("C*",$string)) { #do big endian, then it would make 'fred' and 'free' be one number apart
        $number += $_;
    }
    return $number;
}
$evalcpt->share('&mknum');
$evalcpt->permit('require');

sub translate_names{
  my $instructions = shift;

  my ($nr,$regexps) = split( /\:/, $instructions );
  my @xCATnodes = xCAT::NodeRange::noderange($nr);

  foreach my $xCATnode (@xCATnodes) {
        my $xlated_node = $xCATnode;
        my $datum = $regexps;
  # The following is based on code copied from Table::getNodeAttribs
        if ($datum =~ /^\/[^\/]*\/[^\/]*\/$/)
        {
            my $exp = substr($datum, 1);
            chop $exp;
            my @parts = split('/', $exp, 2);
            $xlated_node =~ s/$parts[0]/$parts[1]/;
            $datum = $xlated_node;
        }
        elsif ($datum =~ /^\|.*\|.*\|$/)
       {
            #Perform arithmetic and only arithmetic operations in bracketed issues on the right.
            #Tricky part:  don't allow potentially dangerous code, only eval if
            #to-be-evaled expression is only made up of ()\d+-/%$
            #Futher paranoia?  use Safe module to make sure I'm good
            my $exp = substr($datum, 1);
            chop $exp;
            my @parts = split('\|', $exp, 2);
            my $curr;
            my $next;
            my $prev;
            my $retval = $parts[1];
            ($curr, $next, $prev) =
              extract_bracketed($retval, '()', qr/[^()]*/);

            unless($curr) { #If there were no paramaters to save, treat this one like a plain regex
               undef $@; #extract_bracketed would have set $@ if it didn't return, undef $@
               $retval = $xlated_node;
               $retval =~ s/$parts[0]/$parts[1]/;
               $datum = $retval;
               unless ($datum =~ /^$/) { # ignore blank translations
                 $xlated_node=$datum;
               }
#               next; #skip the redundancy that follows otherwise
            }
            while ($curr)
            {

                #my $next = $comps[0];
                my $value = $xlated_node;
                $value =~ s/$parts[0]/$curr/;
#                $value = $evalcpt->reval('use integer;'.$value);
                $value = $evalcpt->reval($value);
                $retval = $prev . $value . $next;
                #use text::balanced extract_bracketed to parse each atom, make sure nothing but arith operators, parens, and numbers are in it to guard against code execution
                ($curr, $next, $prev) =
                  extract_bracketed($retval, '()', qr/[^()]*/);
            }
            undef $@;
            #At this point, $retval is the expression after being arithmetically contemplated, a generated regex, and therefore
            #must be applied in total
            my $answval = $xlated_node;
            $answval =~ s/$parts[0]/$retval/;
            $datum = $answval; #$retval;
        }
        unless ($datum =~ /^$/) {
            $::XLATED{$xCATnode}=$datum;
            $::XLATED{$datum}=$xCATnode;
        }

  }
#  print Dumper($::XLATED);
  return ;
}



#----------------------------------------------------------------------------

=head3   set_LL_feature

        Sets the specified feature for the list of LL machines

        Arguments:  $machinelist - blank delimited list of LL machines
                    $feature - feature value to set
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

        Comments:

=cut

#-----------------------------------------------------------------------------
sub set_LL_feature {
    my $machinelist = shift;
    my $feature = shift;

    # Query current feature
    my $cmd = "llconfig -h $machinelist -d FEATURE";
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Running command \'$cmd\'\n";
        close (RULOG);
    }
    my @llcfgoutput = xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        close (RULOG);
    }

    my %set_features;
    my %had_cfg;
    foreach my $llcfgout (@llcfgoutput) {
        my @llfeatures;
        my $haveit = 0;
        if ( $llcfgout =~ /:FEATURE =/ ) {
            my ($stuff,$curfeature_string) = split(/=/,$llcfgout);
            my $newfeature_string = "";
            my ($machine,$morestuff) = split(/:/,$stuff);
            @llfeatures = split(/\s+/,$curfeature_string);
            foreach my $f (@llfeatures) {
                if ($f =~ /XCAT_UPDATEALL\d*/) {
                    $f = "";
                } else {
                    $newfeature_string .= " $f";
                }
                if ($f eq $feature){
                   $haveit = 1;
                }
            }
            if ( !$haveit) {
                $newfeature_string .= " $feature";
            }
            $set_features{$newfeature_string} .= " $machine";
            $had_cfg{$machine} = 1;
        }
    }
    foreach my $m (split(/\s+/,$machinelist)){
        if (! $had_cfg{$m} ){
            $set_features{$feature} .= " $m";
        }
    }

    # Change in LL database
    foreach my $sf (keys %set_features) {
        if ($set_features{$sf} !~ /^\s*$/){
            $cmd = "llconfig -N -h $set_features{$sf}  -c FEATURE=\"$sf\"";
            if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Running command \'$cmd\'\n";
                close (RULOG);
            }
            if ($::TEST) {
                my $rsp;
                push @{ $rsp->{data} }, "In TEST mode.  Will NOT run command: $cmd ";
                xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                $::RUNCMD_RC = 0;
            } else {
                xCAT::Utils->runcmd( $cmd, 0 );
                if ($::VERBOSE) {
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
                    close (RULOG);
                }
            }
        }
    }

    # Send LL reconfig to all central mgrs and resource mgrs
    llreconfig();

    return 0;
}


#----------------------------------------------------------------------------

=head3   get_prescripts

        Generate the prescripts for this nodelist

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
sub get_prescripts {
    my $nodelist = shift;
    my @nl = split(/,/, $nodelist);

    my @datalines;
    my $psindex=0;
    foreach my $psl ( @{ $::FILEATTRS{'prescript'} } ) {
        my $psline = $psl;   
        if ($::updateall) {
            push (@datalines, "prescript=".$psline."\n");
            $psindex++;
            next;
        }
        my $psnoderange = $::FILEATTRS{'prescriptnodes'}[$psindex];
        my $executenodelist = "";
        if ($psnoderange eq "ALL_NODES_IN_UPDATEGROUP") {
           $executenodelist = $nodelist;
        } else {
            my @psns = xCAT::NodeRange::noderange($psnoderange);
            unless (@psns) { $psindex++; next; }
            my @executenodes;
            foreach my $node (@nl) {
                push (@executenodes, grep (/^$node$/,@psns));                 
            }
            $executenodelist = join(',',@executenodes);
        }
        if ($executenodelist ne "") {
            $psline =~ s/\$NODELIST/$executenodelist/g;
            push (@datalines, "prescript=".$psline."\n");
        } 
        $psindex++;
    }
    return @datalines;
}



#----------------------------------------------------------------------------

=head3   get_outofband

        Generate the out of band scripts for this nodelist

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
sub get_outofband {
    my $nodelist = shift;
    my @nl = split(/,/, $nodelist);

    my @datalines;
    my $obindex=0;
    foreach my $obl ( @{ $::FILEATTRS{'outofbandcmd'} } ) {
        my $obline = $obl;
        if ($::updateall) {
            push (@datalines, "outofbandcmd=".$obline."\n");
            $obindex++;
            next;
        }
        my $obnoderange = $::FILEATTRS{'outofbandnodes'}[$obindex];
        my $executenodelist = "";
        if ($obnoderange eq "ALL_NODES_IN_UPDATEGROUP") {
           $executenodelist = $nodelist;
        } else {
            my @obns = xCAT::NodeRange::noderange($obnoderange);
            unless (@obns) { $obindex++; next; }
            my @executenodes;
            foreach my $node (@nl) {
                push (@executenodes, grep (/^$node$/,@obns));                 
            }
            $executenodelist = join(',',@executenodes);
        }
        if ($executenodelist ne "") {
            $obline =~ s/\$NODELIST/$executenodelist/g;
            push (@datalines, "outofbandcmd=".$obline."\n");
        } 
        $obindex++;
    }
    return @datalines;
}


#----------------------------------------------------------------------------

=head3   get_bringuporder

        Generate the bringup order for this nodelist

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
sub get_bringuporder {
    my $nodelist = shift;
    my @nl = split(/,/, $nodelist);

    my @datalines;
    if ($::updateall) {
        $datalines[0]="\n";
        return @datalines;
    }
    foreach my $buline ( @{ $::FILEATTRS{'bringuporder'} } ) {
        my @buns = xCAT::NodeRange::noderange($buline);
        unless (@buns) { next; }
        my @bringupnodes;
        foreach my $node (@nl) {
            if (defined($node)) {
                (my $found) =  grep (/^$node$/,@buns);
                if ($found) {
                    push (@bringupnodes, $found);
                    undef $node;  # don't try to use this node again
                }
            }
        }
        my $bringupnodelist = join(',',@bringupnodes);
        if ($bringupnodelist ne "") {
            push (@datalines, "bringuporder=".$bringupnodelist."\n");
        } 
    }
    return @datalines;
}


#----------------------------------------------------------------------------

=head3   get_mutex

        Generate the list of LL mutual exclusion resources for this 
        update group

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
sub get_mutex {
    my $ugname = shift;

    my $mutex_string = "";

    my $max_updates = $::FILEATTRS{'maxupdates'}[0];
    if ( defined($max_updates)  && ($max_updates ne 'all') ) {
         $mutex_string .= "XCATROLLINGUPDATE_MAXUPDATES(1) ";
    }

    if ($::updateall){
        return $mutex_string;
    }

    my $num_mutexes = scalar @::MUTEX;
    if ( $num_mutexes > 0 ) {
        foreach my $row (0..($num_mutexes-1)) {
            foreach my $ugi (0..(@{$::MUTEX[$row]} - 1)) {
                if ( defined($::MUTEX[$row][$ugi]) && ($ugname eq $::MUTEX[$row][$ugi]) ) {
                    $mutex_string .= "XCATROLLINGUPDATE_MUTEX".$row."(1) ";
                    last;
                }
            }
        }
    }
    return $mutex_string;
}


#----------------------------------------------------------------------------

=head3   create_LL_mutex_resources

        Create all required LL mutex resources

        Arguments:
                   updategroup
                   maxupdates_only:
                        1 - only create MAXUPDATES resources (for updateall)
			0 - create MAXUPDATES and all MUTEX resources
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

        Comments: Reads the mutex entries in $::FILEATTRS and
                  sets the global array $::MUTEX
                  which is a multi-dimensional array:
                  Each row is an array of mutually exclusive update
                   group names
                 A LL Floating Resource will be created for each
                 row of the array.

=cut

#-----------------------------------------------------------------------------
sub create_LL_mutex_resources {

    my $updategroup=shift;
    my $maxupdates_only=shift;

    $::LL_MUTEX_RESOURCES_CREATED = 0;
    my $mxindex=0;
    my $fileattrs_index=0;
    if (!$maxupdates_only) {
        foreach my $mxline ( @{ $::FILEATTRS{'mutex'} } ) {
            my $mx_count = $::FILEATTRS{'mutex_count'}[$fileattrs_index];
            my @mxparts = split(/,/,$mxline);
            if ( scalar @mxparts < 2 ) {
                my $rsp;
                push @{ $rsp->{data} }, "Error processing stanza line: ";
                push @{ $rsp->{data} }, "mutex=" . $mxline;
                push @{ $rsp->{data} }, "Value must contain at least 2 update groups";
                xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
                return 1; 
            }

            my $mxpi = 0;
            my $mxindexmax = $mxindex;
            my @ugnames;
            foreach my $mxpart ( @mxparts ) {
                my $mxindex2 = $mxindex;
                #my @ugnamelist = xCAT::NameRange::namerange( $mxpart, 0 );
                my @ugnamelist = xCAT::NodeRange::noderange( $mxpart, 0, 1, genericrange=>1 );
                foreach my $ugname (@ugnamelist) {
                    $::MUTEX[$mxindex2][$mxpi] = $ugname;
                    $mxindex2++;
                }
                $mxindexmax = ($mxindex2 > $mxindexmax) ? $mxindex2 : $mxindexmax;
                $mxpi++;
            }
            my $mxc;
            for ($mxc=$mxindex; $mxc < $mxindexmax; $mxc++) {
                $::MUTEX_COUNT[$mxc] = $mx_count;
            }
            $mxindex = $mxindexmax;
            $fileattrs_index++;
         }

    # If nodegroup_mutex entries are specified, we need to use the 
    # list of all the nodes in each updategroup for this entire run.
    # Then we need to get a list of all the nodes in the specified
    # nodegroup and look for any intersections to create mutexes.
        $fileattrs_index=0;
        foreach my $mxnodegrp_range ( @{ $::FILEATTRS{'nodegroup_mutex'} } ) {
            my $mx_count = $::FILEATTRS{'nodegroup_mutex_count'}[$fileattrs_index];

            #foreach my $mxnodegroup ( xCAT::NameRange::namerange( $mxnodegrp_range, 0 ) ) {
            foreach my $mxnodegroup ( xCAT::NodeRange::noderange( $mxnodegrp_range, 0, 1, genericrange=>1 ) ) {
              my $mxpi = 0;
mxnode_loop:  foreach my $mxnode ( xCAT::NodeRange::noderange($mxnodegroup) ) {
                foreach my $ugname ( keys %{$updategroup} ) {
                  foreach my $node ( @{ $updategroup->{$ugname} } ) {
                     if ($mxnode eq $node) {
                     # found a match, add updategroup to this mutex if we
                     # don't already have it listed
                        my $chk = 0;
                        while ( $chk < $mxpi ){
                            if ($::MUTEX[$mxindex][$chk] eq $ugname) {
                                # already have this one, skip to next
                                next mxnode_loop;
                            }
                            $chk++;
                        }
                        $::MUTEX[$mxindex][$mxpi] = $ugname;
                        $mxpi++;
                        next mxnode_loop;
                     } # end if found match 
                  }  
                }
              } # end mxnode_loop
              if ($mxpi == 1) {
                 # only one updategroup in this mutex, not valid -- ignore it
                 delete $::MUTEX[$mxindex];
              } elsif ( $mxpi > 1 ) {
                 $::MUTEX_COUNT[$mxindex] = $mx_count;
                 $mxindex++;
              }
            }
            $fileattrs_index++;
        }
     }


     # Build the actual FLOATING_RESOURCES and SCHEDULE_BY_RESOURCES
     # strings to write into the LL database 
     my $resource_string = "";
     my $max_updates = $::FILEATTRS{'maxupdates'}[0];
     if ( ! defined($max_updates)  || ($max_updates eq 'all') ) {
         $max_updates = 0;
     } else {
         $resource_string .= "XCATROLLINGUPDATE_MAXUPDATES($max_updates) ";
     }

     if (!$maxupdates_only) {
         my $num_mutexes = scalar @::MUTEX;
         if ( $num_mutexes > 0 ) {
            foreach my $row (0..($num_mutexes-1)) {
                $resource_string .= "XCATROLLINGUPDATE_MUTEX".$row."($::MUTEX_COUNT[$row]) ";
            }
         }
     }

     if ( $resource_string ) {
        my $cfg_change = 0;
        my $cmd = "llconfig -d FLOATING_RESOURCES SCHEDULE_BY_RESOURCES CENTRAL_MANAGER_LIST RESOURCE_MGR_LIST";
        my @llcfg_d = xCAT::Utils->runcmd( $cmd, 0 );
        my $curSCHED = "";
        my $curFLOAT = "";
        foreach my $cfgo (@llcfg_d) {
            chomp $cfgo;
            my($llattr,$llval) = split (/ = /,$cfgo);
            if ( $llattr =~ /SCHEDULE_BY_RESOURCES/ ) {
                $curSCHED = $llval; }
            if ( $llattr =~ /FLOATING_RESOURCES/ ) {
                $curFLOAT = $llval; }
        }
        my $origSCHED = $curSCHED;
        my $origFLOAT = $curFLOAT;
        $cmd = "llconfig -N -c ";
        $curFLOAT =~ s/XCATROLLINGUPDATE_MUTEX(\d)*\((\d)*\)//g;
        $curFLOAT =~ s/XCATROLLINGUPDATE_MAXUPDATES(\d)*\((\d)*\)//g;
        $curFLOAT .= " $resource_string";
        $curFLOAT =~ s/\s+/ /g; $curFLOAT =~ s/^\s//g; $curFLOAT =~ s/\s$//g;
        $origFLOAT =~ s/\s+/ /g; $origFLOAT =~ s/^\s//g; $origFLOAT =~ s/\s$//g;
        if ( $curFLOAT ne $origFLOAT ) {
            $cmd .= "FLOATING_RESOURCES=\"$curFLOAT\" ";
            $cfg_change = 1;
        }

        $resource_string =~ s/\((\d)*\)//g;
        $curSCHED =~ s/XCATROLLINGUPDATE_MUTEX(\d)*//g;
        $curSCHED =~ s/XCATROLLINGUPDATE_MAXUPDATES(\d)*//g;
        $curSCHED .= " $resource_string";
        $curSCHED =~ s/\s+/ /g; $curSCHED =~ s/^\s//g; $curSCHED =~ s/\s$//g;
        $origSCHED =~ s/\s+/ /g; $origSCHED =~ s/^\s//g; $origSCHED =~ s/\s$//g;
        if ( $curSCHED ne $origSCHED ) {
            $cmd .= "SCHEDULE_BY_RESOURCES=\"$curSCHED\" ";
            $cfg_change = 1;
        }
        if ($cfg_change) {
            my @llcfg_c;
            if ($::TEST) {
                my $rsp;
                push @{ $rsp->{data} }, "In TEST mode.  Will NOT run command: $cmd ";
                   xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
                $::RUNCMD_RC = 0;
            } else {
                @llcfg_c = xCAT::Utils->runcmd( $cmd, 0 );
            }

            # Send LL reconfig to all central mgrs and resource mgrs
            llreconfig();
        }
    }
 
    $::LL_MUTEX_RESOURCES_CREATED = 1;
    return 0;
}




#----------------------------------------------------------------------------

=head3   runrollupdate

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

sub runrollupdate {

    my $reboot_request = shift;
    if ( ! $reboot_request->{arg} ) {
       &runrollupdate_usage;
       return;
    }

    my @reboot_args = @{$reboot_request->{arg}};
    my $internal = 0;
    if ( $reboot_args[0] eq "internal" ) { $internal = 1; }

    my $rc    = 0;
    my $error = 0;

    # process the command line
    if ( $internal ) {
        $::scheduler = $reboot_args[1];
        $::datafile = $reboot_args[2];
        $::ll_reservation_id = "";
    } else {
        $rc = &processArgs;
        if ( $rc != 0 ) {

            # rc: 0 - ok, 1 - return, 2 - help, 3 - error
            if ( $rc != 1 ) {
                &runrollupdate_usage;
            }
            return ( $rc - 1 );
        }
    }
    $::scheduler =~ tr/[A-Z]/[a-z]/;


    if ($::VERBOSE) { 
        unless (-d $::LOGDIR) { File::Path::mkpath($::LOGDIR); } 
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()."runrollupdate request for $::scheduler $::datafile $::ll_reservation_id \n";
        close (RULOG);
    }

    my $childpid = xCAT::Utils->xfork();
    unless (defined $childpid)  { die "Fork failed" };
    if ($childpid != 0) {
        # This is the parent process, just return and let the child do all
        # the work.
        return $childpid;
    }

    # This is now the child process
    
    # Load the datafile 
    &readDataFile($::datafile);
    # set some defaults
    $::ug_name =  $::DATAATTRS{updategroup}[0];
    my ($statusattr,$statusval,$statustimeout);
    if (defined($::DATAATTRS{bringupappstatus}[0])) {
        $statusattr = "appstatus";
        $statusval = $::DATAATTRS{bringupappstatus}[0];
    } elsif (defined($::DATAATTRS{bringupstatus}[0])) {
        $statusattr="status";
        $statusval = $::DATAATTRS{bringupstatus}[0];
    } else {
        $statusattr="status";
        $statusval = "booted";
    }
    if (defined($::DATAATTRS{bringuptimeout}[0])) {
        $statustimeout = $::DATAATTRS{bringuptimeout}[0];
    } else {
        $statustimeout = 10;
    }
    my $skipshutdown = 0;
    if ((defined($::DATAATTRS{skipshutdown}[0])) && 
               ( ($::DATAATTRS{skipshutdown}[0] eq "yes") ||
                 ($::DATAATTRS{skipshutdown}[0] eq "y")   ||
                 ($::DATAATTRS{skipshutdown}[0] eq "1") ) ) {
        $skipshutdown = 1;
    } 
    $::XLATED = {};
    if (defined($::DATAATTRS{translatenames}[0])) {
       foreach my $xlate_stanza( @{ $::DATAATTRS{'translatenames'} } ) {
          translate_names($xlate_stanza);
       }
    }

    # make sure nodes are in correct state
    my $hostlist = &get_hostlist();
    if (! $hostlist ) {
        if ($::VERBOSE) { 
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()."$::ug_name:  Cannot determine nodelist for this request.  \n"; 
            close (RULOG);
        }
        my $rsp;
        xCAT::MsgUtils->message( "S",
"rollupdate failure:  $::ug_name: Cannot determine nodelist for this request.  ");
        exit(1);
    }

    my $nltab = xCAT::Table->new('nodelist');
    my @nodes = split( /\,/, $hostlist );    
    my $appstatus=xCAT::TableUtils->getAppStatus(\@nodes,"RollingUpdate");
    foreach my $node (@nodes) {
        unless ( defined($appstatus->{$node})
                 && ( $appstatus->{$node} eq "update_job_submitted" ) )
        {
            if ($::VERBOSE) { 
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." $::ug_name:  Node $node appstatus not in valid state for rolling update\n";
                print RULOG "The following nodelist will not be processed:\n $hostlist \n";
                close (RULOG);
            }
            my $rsp;
            xCAT::MsgUtils->message(
                "S",
"ROLLUPDATE failure: $::ug_name:  Node $node appstatus not in valid state for rolling update "
            );
            if ($::ll_reservation_id){
               my @remove_res;
               $remove_res[0]='CANCEL_DUE_TO_ERROR';
               &remove_LL_reservations(\@remove_res);
            }
            exit(1);
        }
    }

    # Run prescripts for this update group
    xCAT::TableUtils->setAppStatus(\@nodes,"RollingUpdate","running_prescripts");
    foreach my $psline ( @{ $::DATAATTRS{'prescript'} } ) {
        $psline =~ s/\$NODELIST/$hostlist/g;
        # Run the command
        if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." $::ug_name:  Running prescript \'$psline\'\n";
                close (RULOG);
        }
        my @psoutput;
        if ($::TEST) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." $::ug_name:  In TEST mode.  Will NOT run prescript \'$psline\'\n";
                close (RULOG);
        } else {
           @psoutput = xCAT::Utils->runcmd( $psline, 0 );
        }
        if ($::VERBOSE) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." Prescript output:\n";
            foreach my $psoline (@psoutput) {
                print RULOG $psoline."\n";
            }
            close (RULOG);
        }
    }
    

    # Shutdown the nodes
    if ( ! $skipshutdown ) {
        xCAT::TableUtils->setAppStatus(\@nodes,"RollingUpdate","shutting_down");
        my $shutdown_cmd;
        if (xCAT::Utils->isAIX()) { $shutdown_cmd = "shutdown -F &"; }
                             else { $shutdown_cmd = "shutdown -h now &"; }
 
 
        if ($::VERBOSE) { 
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." $::ug_name:   Running command \'xdsh $hostlist -v $shutdown_cmd\' \n";
            close (RULOG);
        }
        if ($::TEST) { 
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." $::ug_name:  In TEST mode.  Will NOT run command \'xdsh $hostlist -v $shutdown_cmd\' \n";
            close (RULOG);
        } else {
            xCAT::Utils->runxcmd( { command => ['xdsh'],
                                    node    => \@nodes,
                                    arg     => [ "-v", $shutdown_cmd ]
                              }, $::SUBREQ, -1);
        }
        my $slept    = 0;
        my $alldown  = 1;
        my $nodelist = join( ',', @nodes );
        if (! $::TEST) { 
        do {
            $alldown = 1;
            my $shutdownmax = 5;
            if ( defined($::DATAATTRS{shutdowntimeout}[0] ) ) {
                $shutdownmax = $::DATAATTRS{shutdowntimeout}[0];
            }
            my $pwrstat_cmd = "rpower $nodelist stat";
            if ($::VERBOSE) { 
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." $::ug_name:  Running command \'$pwrstat_cmd\' \n";
                close (RULOG);
            }
            my $pwrstat = xCAT::Utils->runxcmd( $pwrstat_cmd, $::SUBREQ, -1, 1 );
            foreach my $pline (@{$pwrstat}) {
                my ( $pnode, $pstat, $rest ) = split( /\s+/, $pline );
                if (    ( ! $pstat )
                     || ( $pstat eq "Running" )
                     || ( $pstat eq "Shutting" )
                     || ( $pstat eq "on" )
                     || ( $pstat eq "Error:" ) )
                {

                    $alldown = 0;
                    # give up on shutdown after requested wait time and force the
                    # node off
                    if ( $slept >= ($shutdownmax * 60) ) {
                        $pnode =~ s/://g;
                        my $pwroff_cmd = "rpower $pnode off";
                        if ($::VERBOSE) { 
                            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                            print RULOG localtime()." $::ug_name:  shutdowntimeout exceeded for $pnode \n";
                            print RULOG localtime()." $::ug_name:  Running command \'$pwroff_cmd\' \n";
                            close (RULOG);
                        }
                        xCAT::TableUtils->setAppStatus([$pnode],"RollingUpdate","shutdowntimeout_exceeded__forcing_rpower_off");
                        xCAT::Utils->runxcmd( $pwroff_cmd, $::SUBREQ, -1 );
                    } else {
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
        } # end not TEST

        # Run out-of-band commands for this update group
        xCAT::TableUtils->setAppStatus(\@nodes,"RollingUpdate","running_outofbandcmds");
        foreach my $obline ( @{ $::DATAATTRS{'outofbandcmd'} } ) {
            $obline =~ s/\$NODELIST/$hostlist/g;
            # Run the command
            if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." $::ug_name:  Running out-of-band command  \'$obline\'\n";
                close (RULOG);
            }
            my @oboutput;
            if ($::TEST) {
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." $::ug_name:  In TEST mode.  Will NOT run out-of-band command  \'$obline\'\n";
                    close (RULOG);
            } else {
                @oboutput = xCAT::Utils->runcmd( $obline, 0 );
            }
            if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." $::ug_name:  Out-of-band command output:\n";
                foreach my $oboline (@oboutput) {
                    print RULOG $oboline."\n";
                }
                close (RULOG);
            }
        }
    } # end !$skipshutdown
    


    # reboot the nodes
    #   Use bringuporder defined in datafile
    
    my $numboots = 0;
    if ( defined($::DATAATTRS{bringuporder}[0]) ) {
        $numboots = scalar( @{$::DATAATTRS{bringuporder}} );
    }
    if ( $skipshutdown ) {
        $numboots = 0;
    }
    my @remaining_nodes = @nodes;
    foreach my $bootindex (0..$numboots){
        my @bootnodes;
        if ((!$skipshutdown) &&
            (defined($::DATAATTRS{bringuporder}[$bootindex]))) {
            @bootnodes = split(/,/,$::DATAATTRS{bringuporder}[$bootindex]);
            foreach my $rn (@remaining_nodes) {
                if ((defined($rn)) && (grep(/^$rn$/,@bootnodes))) {
                    undef($rn);
                }
            }
        } else {
            foreach my $rn (@remaining_nodes) {
                if (defined($rn)) {
                    push (@bootnodes,$rn);
                    undef($rn);
                }
            }
        }
        if (!scalar (@bootnodes)) { next; } 

        # reboot command determined by nodehm power/mgt attributes
        if (!$skipshutdown) {
            my $hmtab = xCAT::Table->new('nodehm');
            my @rpower_nodes;
            my @rnetboot_nodes;
            my $hmtab_entries =
              $hmtab->getNodesAttribs( \@bootnodes, [ 'node', 'mgt', 'power' ] );
            foreach my $node (@bootnodes) {
                my $pwr = $hmtab_entries->{$node}->[0]->{power};
                unless ( defined($pwr) ) { $pwr = $hmtab_entries->{$node}->[0]->{mgt}; }
                if ( $pwr eq 'hmc' ) {
                    push( @rnetboot_nodes, $node );
                }
                else {
                    push( @rpower_nodes, $node );
                }
            }

            xCAT::TableUtils->setAppStatus(\@bootnodes,"RollingUpdate","rebooting");
            if ($bootindex < $numboots) {
                xCAT::TableUtils->setAppStatus(\@remaining_nodes,"RollingUpdate","waiting_on_bringuporder");
            }
            if ( scalar(@rnetboot_nodes) > 0 ) {
                my $rnb_nodelist = join( ',', @rnetboot_nodes );
                # my $cmd = "rnetboot $rnb_nodelist -f";
####  TODO:  DO WE STILL NEED 2 LISTS?
####         RUNNING rpower FOR ALL BOOTS NOW!  MUCH FASTER!!!
                my $cmd = "rpower $rnb_nodelist on";
                if ($::VERBOSE) { 
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." $::ug_name:  Running command \'$cmd\' \n";
                    close (RULOG);
                }
                if ($::TEST) { 
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." $::ug_name:  In TEST mode.  Will NOT run command \'$cmd\' \n";
                    close (RULOG);
                } else {
                    xCAT::Utils->runxcmd( $cmd, $::SUBREQ, 0 );
                }
            } elsif ( scalar(@rpower_nodes) > 0 ) {
                my $rp_nodelist = join( ',', @rpower_nodes );
                my $cmd = "rpower $rp_nodelist boot";
                if ($::VERBOSE) { 
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." $::ug_name:  Running command \'$cmd\' \n";
                    close (RULOG);
                }
                if ($::TEST) { 
                    open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                    print RULOG localtime()." $::ug_name:  In TEST mode.  Will NOT run command \'$cmd\' \n";
                    close (RULOG);
                } else {
                    xCAT::Utils->runxcmd( $cmd, $::SUBREQ, 0 );
                }
            }
        } # end !$skipshutdown

         # wait for bringupstatus to be set
        my $not_done = 1;
        my $totalwait = 0;
        my %ll_res;
        while ($not_done && $totalwait < ($statustimeout * 60)) {
            my @query_bootnodes;
            foreach my $bn (keys %ll_res) {
                if ( ! ($ll_res{$bn}{removed}) ) {
                    push (@query_bootnodes,$bn);
                }
            }
            if ( ! @query_bootnodes ) {
                @query_bootnodes = @bootnodes;
            }
            if ($::VERBOSE) { 
                 open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                 print RULOG localtime()." $::ug_name:  Checking ".join(",",@query_bootnodes)." xCAT database $statusattr for value $statusval \n";
                 close (RULOG);
            }
            my $nltab_stats =
                $nltab->getNodesAttribs( \@query_bootnodes, [ 'node', $statusattr ] );
#           %ll_res = ();
            $not_done = 0;
            foreach my $bn (@query_bootnodes) {
                if ( $nltab_stats->{$bn}->[0]->{$statusattr} !~ /$statusval/ ) {
                  $ll_res{$bn}{not_done}=1;
                  $not_done = 1;
                } else {
                  $ll_res{$bn}{remove}=1;
                }
            }
            if (($::scheduler eq "loadleveler") &&
                ($::ll_reservation_id)){ 
                my @remove_res_LL;
                my @remove_res_xCAT;
                foreach my $bn (keys %ll_res) {
                    if (($ll_res{$bn}{remove}) && (! $ll_res{$bn}{removed}) ){
                        if ( defined($::XLATED{$bn}) ) {
                            push (@remove_res_LL,$::XLATED{$bn});
                            push (@remove_res_xCAT,$bn);
                        } else {
                            push (@remove_res_LL,$bn);
                            push (@remove_res_xCAT,$bn);
                        }
                        $ll_res{$bn}{removed} = 1;
                        $ll_res{$bn}{not_done} = 0;
                    }
                }
                if (@remove_res_LL) {
                    &remove_LL_reservations(\@remove_res_LL);
                    xCAT::TableUtils->setAppStatus(\@remove_res_xCAT,"RollingUpdate","update_complete");
                }
            }
            if ($not_done) {
                if ($::TEST) { 
                    $not_done = 0; 
                } else {
                    sleep(20);
                    $totalwait += 20;
                }
            }
        }
        if ($not_done) { 
            if (($::scheduler eq "loadleveler") &&
                ($::ll_reservation_id)){ 
                 open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                 print RULOG "\n";
                 print RULOG localtime()." ERROR:  Update group $::ug_name:  Reached bringuptimeout before all nodes completed bringup.  Some nodes may not have been updated. \n";
                print RULOG "Cancelling LL reservation $::ll_reservation_id \n";
                print RULOG "\n";
                close (RULOG);

                my @remove_res;
                $remove_res[0]='CANCEL_DUE_TO_ERROR';
                &remove_LL_reservations(\@remove_res);
                my @error_nodes;
                foreach my $bn (keys %ll_res) {
                    if ($ll_res{$bn}{not_done}) {
                        push (@error_nodes,$bn);
                    }
                }
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG "\n";
                print RULOG localtime()." ERROR:  bringuptimeout exceeded for the following nodes: \n";
                print RULOG join(",",@error_nodes);
                print RULOG "\n";
                xCAT::TableUtils->setAppStatus(\@error_nodes,"RollingUpdate","ERROR_bringuptimeout_exceeded");
                if ( @remaining_nodes ) {
                  my @leftover_nodes;
                  foreach my $rn (@remaining_nodes) {
                    if (defined($rn)) {
                        push (@leftover_nodes,$rn);
                    }
                  }
                  if ( @leftover_nodes ) {
                    print RULOG localtime()." ERROR:  bringuptimeout exceeded for some nodes in a preceding bringuporder.  The following nodes will not be powered on: \n";
                    print RULOG join(",",@leftover_nodes);
                    print RULOG "\n";
                    xCAT::TableUtils->setAppStatus(\@leftover_nodes,"RollingUpdate","ERROR_bringuptimeout_exceeded_for_previous_node");
                  }
                }
                close (RULOG);
            }
            last;
        }

    }
    if ($::VERBOSE) { 
          open (RULOG, ">>$::LOGDIR/$::LOGFILE");
          print RULOG localtime()." $::ug_name:  Rolling update complete.\n\n";
          close (RULOG);
    }

    exit(0);
}

#----------------------------------------------------------------------------

=head3   readDataFile

        Process the command line input piped in from a stanza file.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

        Comments:
                        Set  %::DATAATTRS
                                (i.e.- $::DATAATTRS{attr}=[val])

=cut

#-----------------------------------------------------------------------------
sub readDataFile {
    my $filedata = shift;

    my $DF;
    unless ( open( $DF, "<", $filedata ) ) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." runrollupdate cannot open datafile $filedata\n";
        close (RULOG);
        return 1;
    }
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." runrollupdate reading datafile $filedata\n";
        close (RULOG);
    }
    my @lines = <$DF>;
    close $DF;

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
            push( @{ $::DATAATTRS{$attr} }, $val );
        }
    }    # end while - go to next line

    return 0;
}


#----------------------------------------------------------------------------

=head3   get_hostlist

        Returns a comma-delimited hostlist string for this updategroup

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
sub get_hostlist {
    if ( defined($::DATAATTRS{nodelist}[0]) ){
       return $::DATAATTRS{nodelist}[0];
    }
    my $cmd;
    if ($::VERBOSE) {
        $cmd = "llqres -r -s -R $::ll_reservation_id 2>>$::LOGDIR/$::LOGFILE";
    } else {
        $cmd = "llqres -r -s -R $::ll_reservation_id";
    }
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
    my ($llstatus) = xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        print RULOG localtime()." $llstatus \n";
        close (RULOG);
    }
    if ($::RUNCMD_RC) {
        if ($::VERBOSE) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." ERROR:  FAILED calling: \n     $cmd \n";
            close (RULOG);
        }
      return 0;
    } else {
        my @status_fields = split(/!/,$llstatus);
        if ($::VERBOSE) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." Hostlist:  $status_fields[22] \n";
            close (RULOG);
        }
        my $return_list;
        foreach my $machine (split( /\,/, $status_fields[22])) {
           if ( defined($::XLATED{$machine}) ) {
               $return_list = $return_list.','.$::XLATED{$machine};
           } else {
               $return_list = $return_list.','.$machine;
           }
        }
        $return_list =~ s/^,//;
        return $return_list;
    }
}



#----------------------------------------------------------------------------

=head3   remove_LL_reservations

        Changes the LL feature for nodes from oldfeature to newfeature
        Remove nodes from LL reservation

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
sub remove_LL_reservations {
    my $input_nodes = shift;
    my $nodes = $input_nodes;
    my $CANCEL_DUE_TO_ERROR = 0;
    if ( $input_nodes->[0] eq 'CANCEL_DUE_TO_ERROR') {
       $CANCEL_DUE_TO_ERROR = 1;
    }

    my $cmd;
    if ($::VERBOSE) {
        $cmd = "llqres -r -R $::ll_reservation_id 2>>$::LOGDIR/$::LOGFILE";
    } else {
        $cmd = "llqres -r -R $::ll_reservation_id";
    }
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        my $nl = join(",",@{$nodes});
        print RULOG localtime()." $::ug_name:  remove_LL_reservations for $nl \n";
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
    my ($llstatus) = xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        print RULOG localtime()." $llstatus \n";
        close (RULOG);
    }
    if ( $::RUNCMD_RC ) {
        if ($::VERBOSE) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." ERROR:  FAILED calling:\n   $cmd  \n";
            close (RULOG);
        }
        return 0;
    }
    my @status_fields = split(/!/,$llstatus);
    my $llnodelist = $status_fields[22];
    my @llnodes = split(/,/,$llnodelist);
    my $llnode_count = scalar (@llnodes);
    my $remove_count = 0;
    my $remove_reservation = 0;
    my $remove_cmd = "llchres -R $::ll_reservation_id -h -";

    if ($CANCEL_DUE_TO_ERROR) {
        $nodes = \@llnodes;
    }
    my @llnodes_removed;
    foreach my $n (@{$nodes}) {
        # change features for this node
        if ($CANCEL_DUE_TO_ERROR) {
            &remove_LL_updatefeature_only($n);
        } else {
            &change_LL_feature($n);
        }
        my @lln;
        if ( (@lln=grep(/^$n$/,@llnodes)) | (@lln=grep(/^$n\./,@llnodes)) ) {
            $remove_count++;
            push (@llnodes_removed,$lln[0]);
            if ( $remove_count < $llnode_count ) {
              $remove_cmd .= " $lln[0]";
            } else {
              $remove_reservation = 1;
              last;
            }
        }
    }
    # Send LL reconfig to all central mgrs and resource mgrs
    llreconfig();
   #  Verify that the config change has been registered and that updatefeature 
   #  has been removed according to what the LL daemons report 
     if (defined($::DATAATTRS{updatefeature}[0])) {
         my $machinelist = join(" ",@llnodes_removed);
         my $llset;
         my $statrun = 0;
         do {
            sleep 1;
            my $llstatus = "llstatus -Lmachine -h $machinelist -l | grep -i feature | grep -i \" $::DATAATTRS{updatefeature}[0] \"";
            if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Running command \'$llstatus\'\n";
                close (RULOG);
            }
            my @stat_out = xCAT::Utils->runcmd( $llstatus, 0 );
            if ($::VERBOSE) {
                open (RULOG, ">>$::LOGDIR/$::LOGFILE");
                print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
                close (RULOG);
            }
            # Are there any nodes with this feature still set?
            $llset = $stat_out[0];
### DEBUG - print output to see what's going on
#if ($llset) {
#   open (RULOG, ">>$::LOGDIR/$::LOGFILE");
#   print RULOG localtime()." llset:  $llset\n";
#   close (RULOG);
#}
### end DEBUG
            $statrun ++;
         } until ((! $llset) || ($statrun > 10) );
    }

    if ($remove_reservation) {
        $cmd = "llrmres -R $::ll_reservation_id";
    } elsif ( $remove_count > 0 ) {
        $cmd = $remove_cmd;
    } else {
        return 0;  # no LL nodes to remove
    }
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
#    if ($::TEST) { 
#        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
#        print RULOG localtime()." $::ug_name:  In TEST mode.  Will NOT run command \'$cmd\' \n";
#        close (RULOG);
#    } else {
        xCAT::Utils->runcmd( $cmd, 0 );
        if ( $::RUNCMD_RC != 0 ) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." $::ug_name:  Error running command \'$cmd\'\n";
            print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
            close (RULOG);
            return 1;
        }
#    }

    return 0;
}


#----------------------------------------------------------------------------

=head3   change_LL_feature

        Changes the LL feature for the node from oldfeature to newfeature
           and removes updatefeature

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
sub change_LL_feature {
    my $node = shift;

    if (!defined($::DATAATTRS{updatefeature}[0]) && 
        !defined($::DATAATTRS{oldfeature}[0]) && 
        !defined($::DATAATTRS{newfeature}[0]) ) {
        return 0;
    }
    # Query current feature
    my $cmd = "llconfig -h $node -d FEATURE";
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
    my ($llcfgout) = xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        close (RULOG);
    }

    # Remove old feature 
    my $newfeature_string = "";
    my @llfeatures;
    if ( $llcfgout =~ /:FEATURE =/ ) {
        my ($stuff,$curfeature_string) = split(/=/,$llcfgout);
        @llfeatures = split(/\s+/,$curfeature_string);
        my $oldfeature = " ";
        my $updateallfeature = " ";
        if (defined($::DATAATTRS{oldfeature}[0])) {
           $oldfeature = $::DATAATTRS{oldfeature}[0];
        }
        if (defined($::DATAATTRS{updatefeature}[0])) {
           $updateallfeature = $::DATAATTRS{updatefeature}[0];
        }
        foreach my $f (@llfeatures) {
            if (($f eq $oldfeature) || ($f eq $updateallfeature)) {
               $f = " "; 
            }
        }
        $newfeature_string = join(" ",@llfeatures);
    }

    # Add new feature
    if ( defined($::DATAATTRS{newfeature}[0]) ) {
        my $haveit = 0;
        foreach my $f (@llfeatures) {
            if ($f eq $::DATAATTRS{newfeature}[0]){
               $haveit = 1;
            }
        }
        if ( !$haveit) {
            $newfeature_string .= " $::DATAATTRS{newfeature}[0]";
        }
    }
    # Change in LL database
    $cmd = "llconfig -N -h $node -c FEATURE=\"$newfeature_string\"";
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
    xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        close (RULOG);
    }

    # Send LL reconfig to all central mgrs and resource mgrs
  #  llreconfig();

    return 0;
}



#----------------------------------------------------------------------------

=head3   remove_LL_updatefeature_only

        Changes the LL feature for the node to remove only the updatefeature 
        Will NOT remove oldfeature or set newfeature

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
sub remove_LL_updatefeature_only {
    my $node = shift;

    if (!defined($::DATAATTRS{updatefeature}[0]) ) {
        return 0;
    }
    # Query current feature
    my $cmd = "llconfig -h $node -d FEATURE";
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
    my ($llcfgout) = xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        close (RULOG);
    }

    # Remove old feature 
    my $newfeature_string = "";
    my @llfeatures;
    if ( $llcfgout =~ /:FEATURE =/ ) {
        my ($stuff,$curfeature_string) = split(/=/,$llcfgout);
        @llfeatures = split(/\s+/,$curfeature_string);
        my $updateallfeature = " ";
        if (defined($::DATAATTRS{updatefeature}[0])) {
           $updateallfeature = $::DATAATTRS{updatefeature}[0];
        }
        foreach my $f (@llfeatures) {
            if ($f eq $updateallfeature) {
               $f = " "; 
            }
        }
        $newfeature_string = join(" ",@llfeatures);
    }

    # Change in LL database
    $cmd = "llconfig -N -h $node -c FEATURE=\"$newfeature_string\"";
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." $::ug_name:  Running command \'$cmd\'\n";
        close (RULOG);
    }
    xCAT::Utils->runcmd( $cmd, 0 );
    if ($::VERBOSE) {
        open (RULOG, ">>$::LOGDIR/$::LOGFILE");
        print RULOG localtime()." Return code:  $::RUNCMD_RC\n";
        close (RULOG);
    }

    # Send LL reconfig to all central mgrs and resource mgrs
 #   llreconfig();

    return 0;
}




#----------------------------------------------------------------------------

=head3   llreconfig

        Queries LoadLeveler for the list of central mgrs and resource mgrs
           and sends a llrctl reconfig to those nodes

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
sub llreconfig {

    # Send LL reconfig to all central mgrs and resource mgrs
    my $cmd = "llconfig -d CENTRAL_MANAGER_LIST RESOURCE_MGR_LIST";
    my @llcfg_d = xCAT::Utils->runcmd( $cmd, 0 );
    my $llcms = "";
    my $llrms = "";
    foreach my $cfgo (@llcfg_d) {
        chomp $cfgo;
        my($llattr,$llval) = split (/ = /,$cfgo);
        if ( $llattr =~ /CENTRAL_MANAGER_LIST/ ) {
            $llcms = $llval; }
        if ( $llattr =~ /RESOURCE_MGR_LIST/ ) {
            $llrms = $llval; }
    }
    $cmd = "llrctl reconfig";
    my @llms = split(/\s+/,$llcms." ".$llrms);
    my %have = ();
    my @llnodes;
    my $runlocal=1;   # need to always run reconfig at least on local MN
    foreach my $m (@llms) {
       my ($sm,$rest) = split(/\./,$m);
       my $xlated_sm = $sm;
       if ( defined ($::XLATED{$sm}) ) { $xlated_sm = $::XLATED{$sm}; }
       if (xCAT::NetworkUtils->thishostisnot($m)) {
           push(@llnodes, $xlated_sm) unless $have{$sm}++;
       } else {
           $runlocal=1;
       }
    }
    if ( defined($::FILEATTRS{reconfiglist}[0]) ) { 
        push (@llnodes, split( /,/,$::FILEATTRS{reconfiglist}[0]) ); 
    } elsif ( defined($::DATAATTRS{reconfiglist}[0]) ) {
        push (@llnodes, split( /,/,$::DATAATTRS{reconfiglist}[0]) ); 
    }
    if ($runlocal) {
        if ($::VERBOSE) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." Running local command \'$cmd\'\n";
            close (RULOG);
        }
        if ($::TEST) {
            my $rsp;
            push @{ $rsp->{data} }, "In TEST mode.  Will NOT run command:  $cmd ";
               xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
            $::RUNCMD_RC = 0;
        } else {
            xCAT::Utils->runcmd( $cmd, 0 );
        }
    }

    if ( scalar(@llnodes) > 0 ) {
        if ($::VERBOSE) {
            open (RULOG, ">>$::LOGDIR/$::LOGFILE");
            print RULOG localtime()." Running command \'xdsh ".join(',',@llnodes)." $cmd\'\n";
            close (RULOG);
        }
        if ($::TEST) {
            my $rsp;
            push @{ $rsp->{data} }, "In TEST mode.  Will NOT run command: xdsh <llcm,llrm> $cmd ";
               xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
            $::RUNCMD_RC = 0;
        } else {
            xCAT::Utils->runxcmd(
                  { command => ['xdsh'],
                     node    => \@llnodes,
                     arg     => [ "-v", $cmd ]
                  },
                  $::SUBREQ, -1);
        }
    }

}

1;
