#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.htm

#------------------------------------------------------------------------------

=head1    SINV 

=head2    Package Description

This program module file supplies a set of utility programs for  
the sinv command.


=cut

#------------------------------------------------------------------------------

package xCAT::SINV;
use strict;
use xCAT::MsgUtils;
use xCAT::Utils;
use Fcntl qw(:flock);
use Getopt::Long;

#
# Subroutines
#

#------------------------------------------------------------------------------

=head3   usage  			    	 
  Display usage message 

=cut

#------------------------------------------------------------------------------
sub usage
{
## usage message

    my $usagemsg1 =
      "The sinv command is designed to check the configuration of nodes in a cluster.\nRun man sinv for more information.\n\nInput parameters are as follows:\n";
    my $usagemsg1a = "sinv -h \nsinv -v \nsinv [noderange]\n";
    my $usagemsg2  =
      "      [-o output file ] [-p template path] [-t template count]\n";
    my $usagemsg3 = "      [-r remove templates] [-s seednode]\n";
    my $usagemsg4 = "      [-c xdsh command  | -f xdsh command file] \n ";
    my $usagemsg5 = "     [-V verbose] [-h usage]\n ";
    my $usagemsg .= $usagemsg1 .= $usagemsg2 .= $usagemsg3 .= $usagemsg4 .=
      $usagemsg5;
###  end usage mesage
    if ($::CALLBACK)
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usagemsg;
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
    }
    else
    {
        xCAT::MsgUtils->message("I", $usagemsg . "\n");
    }
    return;

}

#------------------------------------------------------------------------------

=head3   parse_and_run_sinv  			    	 
   Checks input arguments and runs sinv from the plugin 

=cut

#------------------------------------------------------------------------------
sub parse_and_run_sinv
{
    my ($class, $nodes, $args, $callback, $command, $noderange) = @_;
    my $rsp = {};
    $::CALLBACK = $callback;
    @ARGV       = @{$args};    # get argument
    my %options = ();
    $Getopt::Long::ignorecase = 0;    #Checks case in GetOptions
    Getopt::Long::Configure("bundling");
    if (
        !GetOptions(
                    'h|help'     => \$options{'help'},
                    't|tc=s'     => \$options{'template_cnt'},
                    'p|tp=s'     => \$options{'template_path'},
                    'r|remove=s' => \$options{'remove_template'},
                    'o|output=s' => \$options{'output_file'},
                    's|seed=s'   => \$options{'seed_node'},
                    'c|cmd=s'    => \$options{'xdsh_cmd'},
                    'f|file=s'   => \$options{'xdsh_file'},
                    'v|version'  => \$options{'version'},
                    'V|Verbose'  => \$options{'verbose'},
        )
      )
    {

        &usage;
        exit 1;
    }
    if ($options{'help'})
    {
        &usage;
        exit 0;
    }
    if ($options{'version'})
    {
        my $version = xCAT::Utils->Version();
        xCAT::MsgUtils->message("I", $version);
        exit 0;
    }
    if ($options{'verbose'})
    {
        $::VERBOSE = "yes";
    }

    # if neither xdsh command or file, error
    if (!($options{'xdsh_cmd'}) && (!($options{'xdsh_file'})))
    {
        $rsp->{data}->[0] =
          "Neither the xdsh command, nor the xdsh command file have been supplied.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    # if  both xdsh command and file, error
    if (($options{'xdsh_cmd'}) && (($options{'xdsh_file'})))
    {
        $rsp->{data}->[0] =
          "Both the xdsh command, and the xdsh command file have been supplied. Only one or the other is allowed.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    #
    # get the  node list
    #
    my @nodelist = @$nodes;
    my @inputNodes = join(',', @nodelist);
    if (@inputNodes == 0)
    {
        $rsp->{data}->[0] = "No noderange specified on the command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    #
    # Get Command to run
    #
    my $cmd;
    if ($options{'xdsh_cmd'})
    {
        $cmd = $options{'xdsh_cmd'};
    }
    else
    {

        # read the command from the file
        $cmd = `cat $options{'xdsh_file'}`;
    }
    chomp $cmd;

    #
    # Get template path
    #

    my $templatepath = $options{'template_path'};
    if (!$templatepath)
    {
        $rsp->{data}->[0] = "Missing template path on the command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    chomp $templatepath;

    #
    # Get template count
    #

    my $templatecnt = $options{'template_cnt'};
    if (!$templatecnt)
    {
        $rsp->{data}->[0] =
          "No template count on the command, defaults to 1.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        $templatecnt = 1;    # default
    }
    chomp $templatecnt;

    #
    # Get remove template value
    #

    my $rmtemplate = $options{'remove_template'};
    if (!$rmtemplate)
    {
        $rsp->{data}->[0] = "Remove template value missing, default is no.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        $rmtemplate = "no";    #default
    }
    chomp $rmtemplate;

    #
    #
    # Get where to put the output
    #

    my $outputfile = $options{'output_file'};
    if (!$outputfile)
    {
        $rsp->{data}->[0] = "Output file path missing.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    chomp $outputfile;

    # open the file for writing
    open(OUTPUTFILE, ">$outputfile");
    if ($? != 0)
    {
        $rsp->{data}->[0] = " Cannot open $outputfile for output.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    $::OUTPUT_FILE_HANDLE = \*OUTPUTFILE;

    #
    #
    # Get seed node if it exists to build the original template
    #

    my $seednode = $options{'seed_node'};
    if ($seednode)
    {
        chomp $seednode;
    }

    my $tmpnodefile;

    #
    # Build Output file header
    #
    $rsp->{data}->[0] = "Command started with following input.\n";
    $rsp->{data}->[1] = "xdsh cmd:$cmd.\n";
    $rsp->{data}->[2] = "Template path:$templatepath.\n";
    $rsp->{data}->[3] = "Template cnt:$templatecnt.\n";
    $rsp->{data}->[4] = "Remove template:$rmtemplate.\n";
    $rsp->{data}->[5] = "Output file:$outputfile.\n";
    if ($seednode)
    {
        $rsp->{data}->[6] = "Seed node:$seednode.\n";
    }
    else
    {
        $rsp->{data}->[6] = "Seed node:None.\n";
    }

    #write to output file the header
    my $i = 0;
    while ($i < 7)
    {
        print $::OUTPUT_FILE_HANDLE $rsp->{data}->[$i];
        $i++;
    }
    print $::OUTPUT_FILE_HANDLE "\n";

    #  put out for all to see
    if ($::VERBOSE)
    {
        xCAT::MsgUtils->message("I", $rsp, $callback);
        $rsp = {};
    }

    #
    # if we are to seed the original template,run the dsh command against the
    # seed node and save in template_path

    if ($seednode)
    {
        my $dsh_command = "xdsh  $seednode -v $cmd  > $templatepath";
        my $rc          = system("$dsh_command");
        if ($rc != 0)
        {
            $rsp->{data}->[0] = "Error from xdsh command:$dsh_command.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            exit 1;
        }
    }

    # Tell them we are running DSH
    if ($::VERBOSE)
    {
        $rsp->{data}->[0] = "Running xdsh command.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    #
    #  Run the DSH command
    #
    my $nodelist    = $inputNodes[0];
    my $tempfile    = "/tmp/sinv.$$";
    my $dsh_command = "xdsh ";
    $dsh_command .= $nodelist;

    $dsh_command .= " $cmd  > $tempfile";
    my $rc = system("$dsh_command");
    if ($rc != 0)
    {
        $rsp->{data}->[0] = "Error from xdsh command:$dsh_command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    #  Build report and write to output file
    #
    if (!(-z "$tempfile"))
    {    # if dsh returned something

        # Tell them we are building the report
        $rsp->{data}->[0] = "Building Report.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);

        xCAT::SINV->buildreport(
                                $outputfile,  $tempfile,   $templatepath,
                                $templatecnt, $rmtemplate, $nodelist,
                                $callback
                                );
    }
    else
    {
        $rsp->{data}->[0] = "No output from xdsh.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # Finally we need to cleanup and exit
    #
    system("/bin/rm  $tempfile");
    close(OUTPUTFILE);
    $rsp->{data}->[0] = "Command Complete. Check report in $outputfile.\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);

}

#------------------------------------------------------------------------------

=head3   buildreport  			    	 

  This routine will take the input template and compare against 
  the output of the dsh command and build a report of the differences. 
  Read a nodes worth of data from the dsh command
  Call compareoutput- compares the dsh to the template
  Get the template and nodename returned from compareoutput and build hash
  Call writereport to take the hash and write the report to the output file
  Cleanup
  Input (report file, file containing dsh run,template file,template count 
         whether to remove the generated templates, original dsh node list)         
=cut

#------------------------------------------------------------------------------
sub buildreport
{

    my ($class, $outputfile, $dshrun, $templatepath, $templatecnt,
        $removetemplate, $nodelist, $callback)
      = @_;
    my $pname = "buildreport";
    my $rc    = $::OK;
    my $rsp   = {};

    # Compare files and build report of nodes that match and those that do not
    if (!-f "$templatepath")    # we supplied a template
    {                           # does it exist
        $rsp->{data}->[0] = "$templatepath does not exist\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return;

    }
    if (!-f "$dshrun")
    {                           # does it exist
        $rsp->{data}->[0] = "$dshrun does not exist\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return;
    }

    #
    # Build an array of template name
    #
    my @templatearray;
    my $i = $templatecnt;
    push @templatearray, $templatepath;    # push first template
    for ($i = 0 ; $i <= $templatecnt ; $i++)
    {
        if ($i != 0)
        {                                  # more template file to read
            my $templatename = $templatepath . "_" . $i;
            push @templatearray, "$templatename";
        }
    }

    # Read the output of the dsh command

    if (!open(DSHRESULTS, "<$dshrun"))
    {
        $rsp->{data}->[0] = "Error reading: $dshrun\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return;
    }
    my @dsharray = <DSHRESULTS>;
    close(TEMPLATE);
    close(DSHRESULTS);

    #
    #Now we have to analyze the template(s) against the dsh command output
    #The matching nodes will be built in one array and the non matching node
    #In another array
    #

    #
    # For each node entry for the dsh command
    #   Build an array of that node's data
    #   Compare that node's data to the template
    #   Put node in array that matches template or other if no match
    #
    my $match = 0;
    my $host;
    my $label;
    my $firstpass = 0;
    my @processNodearray;
    my $hostline;
    my $nodename;
    my $template;
    my @Nodearray;
    my $dshline;
    my %nodehash;
  DSHARRAY: foreach $dshline (@dsharray)    # for each line returned from dsh
    {

        if ($dshline =~ /HOST:/)            #  Host header
        {
            if ($firstpass == 0)
            {

                # put the node name on the array to process
                push @Nodearray, $dshline;
                $firstpass = 1;
            }
            else
            {    # Hit next node name, process current array
                @processNodearray = @Nodearray;    # save node data
                @Nodearray        = ();            # initialize array
                push @Nodearray, $dshline;         # save node name
                my @info =
                  xCAT::rinv->compareoutput($outputfile, \@templatearray,
                                     \@processNodearray, \%nodehash, $callback);
                $nodename = pop @info;
                $template = pop @info;
                push @{$nodehash{$template}}, $nodename;    # add node name
                                                            # to template hash

            }
        }
        else
        {
            if (   ($dshline !~ /---------/)
                && ($dshline !~ /^\s*$/))

              # skip headers and blanks and stop on the next host
            {
                push @Nodearray, $dshline;    # build the node results  dsh
            }
        }

    }    # end foreach dshline
         # process the last entry
    if (@Nodearray)
    {
        my @info =
          xCAT::SINV->compareoutput($outputfile, \@templatearray,
                                    \@Nodearray, \%nodehash);
        $nodename = pop @info;
        $template = pop @info;
        push @{$nodehash{$template}}, $nodename;
    }

    #
    # Write the report
    #

    xCAT::SINV->writereport($outputfile, \%nodehash, $nodelist, $callback);

    #
    # Cleanup  the template files if the remove option was yes
    #
    if ($removetemplate eq "yes")
    {
        foreach $template (@templatearray)    # for each template
        {
            if (   (-f "$template")
                && ($template ne $templatepath))    # not first one
            {
                `/bin/rm -f $template 2>&1`;
            }
        }
    }
    return;
}

#------------------------------------------------------------------------------

=head3   compareoutput  			    	 
 The purpose of this routine is to build sets of nodes
   that have the same configuration.  We will build up
   to template_cnt sets.  If more nodes are not part of these
   sets they will be put in an other list.

 foreach template
  Open the input template
  Compare the template to the input node data
  if match
    add the node to the matched template  hash
 end foreach
 if no match
   if generate and a new template allowed
     make this nodes information into a new template
     add the node to matched template
   else
     add the node to "notemplate" list
=cut

#------------------------------------------------------------------------------
sub compareoutput
{
    my ($class, $outputfile, $template_array, $Node_array, $Node_hash,
        $callback) = @_;
    my @Nodearray     = @$Node_array;
    my @templatearray = @$template_array;
    my %nodehash      = %$Node_hash;
    my $pname         = "compareoutput";
    my $rc            = $::OK;
    my $templateline;
    my $info;
    my $nodeline;
    my $match = 0;
    my @info;
    my $nodename;
    my $line;
    %nodehash = ();
    my $template;
    my $matchedtemplate;
    my $rsp = {};

    foreach $template (@templatearray)    # for each template
    {
        if (-f "$template")
        {                                 # if it exists

            # Read the template file
            open(TEMPLATE, "<$template");
            my @template = <TEMPLATE>;

            # now compare host data to template
            foreach $templateline (@template)    # for each line in the template
            {

                # skip the header and blanks
                if (   ($templateline !~ /HOST:/)
                    && ($templateline !~ /---------/)
                    && ($templateline !~ /^\s*$/))

                {
                    $match = 0;
                    foreach $nodeline (@Nodearray)    # for each node line
                    {
                        if ($nodeline =~ /HOST:/)
                        {                             # if the hostname
                            ($line, $nodename) = split ':', $nodeline;
                            $nodename =~ s/\s*//g;    # remove blanks
                            chomp $nodename;

                        }
                        else
                        {
                            if ($nodeline eq $templateline) # if we find a match
                            {                               # get out
                                $match           = 1;
                                $matchedtemplate = $template;    # save name
                                last;
                            }
                        }
                    }    # end foreach nodeline
                    if ($match == 0)
                    {
                        last;    # had a template line not found
                    }

                }    # if header
            }    # end foreach templateline
        }    # end check exists
             #
             # if match found, process no more templates
             #
        if ($match == 1)
        {
            last;    # exit template loop
        }
    }    # end foreach template
         #
         # if no match
         #   if generate a new template ( check the list of template file
         #     to see if there is one that does not exist
         #       put node data to new template file
         #
    if ($match == 0)
    {
        my $nodesaved = 0;
        foreach $template (@templatearray)
        {
            if (!-f "$template")
            {
                if (!open(NEWTEMPLATE, ">$template"))
                {
                    $rsp->{data}->[0] = "Error opening $template:\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);

                    return;
                }
                else
                {
                    print NEWTEMPLATE @Nodearray;    # build a new template
                    $nodesaved = 1;
                    close(NEWTEMPLATE);
                    $matchedtemplate = $template;
                    last;
                }
            }
        }
        if ($nodesaved == 0)
        {                                            # out of templates
            $matchedtemplate = "no template";        # put in other list
        }
    }
    @info[0] = $matchedtemplate;
    @info[1] = $nodename;
    return @info;
}

#------------------------------------------------------------------------------

=head3   writereport  			    	 

 The purpose of this routine is to write the report to the output file 

=cut

#------------------------------------------------------------------------------
sub writereport
{
    my ($class, $outputfile, $Node_hash, $nodelist, $callback) = @_;
    my %nodehash     = %$Node_hash;
    my @dshnodearray = $nodelist;
    my $pname        = "writereport";
    my $template;
    my @nodenames;
    my @nodearray;

    #
    # Header message
    #
    my $rsp = {};
    foreach my $template (sort keys %nodehash)
    {

        # print template name
        $rsp->{data}->[0] = "The following nodes match $template:\n";
        print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
        if ($::VERBOSE)
        {
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        #print list of nodes
        @nodenames = @{$nodehash{$template}};
        foreach my $nodename (@nodenames)
        {
            push @nodearray, $nodename;    # build an array of all the nodes
            $rsp->{data}->[0] = "$nodename\n";
            print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
            if ($::VERBOSE)
            {
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
    }

    #
    # Now check to see if we covered all nodes in the dsh
    #
    my $firstpass = 0;
    my $nodefound = 0;
    foreach my $dshnodename (@dshnodearray)
    {
        chomp $dshnodename;
        $dshnodename =~ s/\s*//g;    # remove blanks
        foreach my $nodename (@nodearray)
        {
            if ($dshnodename eq $nodename)
            {
                $nodefound = 1;      # we have a match
                last;
            }
        }
        if ($nodefound == 0)
        {                            # dsh node name missing
            if ($firstpass == 0)
            {                        # put out header
                $rsp->{data}->[0] =
                  "The following nodes had no output from xdsh:\n";
                print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
                if ($::VERBOSE)
                {
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                $firstpass = 1;
            }

            # add missing node
            $rsp->{data}->[0] = "$dshnodename\n";
            print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
            if ($::VERBOSE)
            {
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
        $nodefound = 0;
    }
    return;
}

1;
