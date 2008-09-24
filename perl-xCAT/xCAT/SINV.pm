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
my $tempfile;
my $errored = 0;
my @dshresult;
my $templatepath;
my $processflg;

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
    my $usagemsg2  = "      [-V verbose] [-v version] [-h usage]\n ";
    my $usagemsg3  =
      "     [-o output file ] [-p template path] [-t template count]\n";
    my $usagemsg4  = "      [-r remove templates] [-s seednode]\n";
    my $usagemsg4a = "      [-e exactmatch] [-i ignore]\n";
    my $usagemsg5  = "      [-c xdsh command  | -f xdsh command file] \n ";
    my $usagemsg .= $usagemsg1 .= $usagemsg2 .= $usagemsg3 .= $usagemsg4 .=
      $usagemsg4a .= $usagemsg5;
###  end usage mesage

    my $rsp = {};
    $rsp->{data}->[0] = $usagemsg;
    xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
    return;

}

#------------------------------------------------------------------------------

=head3   parse_and_run_sinv  			    	 
   Checks input arguments and runs sinv from the plugin 

=cut

#------------------------------------------------------------------------------
sub parse_and_run_sinv
{
    my ($class, $nodes, $args, $callback, $command, $noderange, $sub_req) = @_;
    my $rsp = {};
    $::CALLBACK = $callback;
    @ARGV       = @{$args};    # get argument
    my %options = ();
    $Getopt::Long::ignorecase = 0;    #Checks case in GetOptions
    Getopt::Long::Configure("bundling");
    if (
        !GetOptions(
                    'h|help'        => \$options{'help'},
                    't|tc=s'        => \$options{'template_cnt'},
                    'p|tp=s'        => \$options{'template_path'},
                    'r|remove'      => \$options{'remove_template'},
                    'o|output=s'    => \$options{'output_file'},
                    's|seed=s'      => \$options{'seed_node'},
                    'e|exactmatch'  => \$options{'exactmatch'},
                    'i|ignorefirst' => \$options{'ignorefirst'},
                    'c|cmd=s'       => \$options{'xdsh_cmd'},
                    'f|file=s'      => \$options{'xdsh_file'},
                    'v|version'     => \$options{'version'},
                    'V|Verbose'     => \$options{'verbose'},
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
        $version .= "\n";
        my $rsp = {};
        $rsp->{data}->[0] = $version;
        xCAT::MsgUtils->message("I", $rsp, $callback);
        exit 0;
    }
    if ($options{'verbose'})
    {
        $::VERBOSE = "yes";
    }

    # if neither xdsh command or file, error
    if (!($options{'xdsh_cmd'}) && (!($options{'xdsh_file'})))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "Neither the xdsh command, nor the xdsh command file have been supplied.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    # if  both xdsh command and file, error
    if (($options{'xdsh_cmd'}) && (($options{'xdsh_file'})))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "Both the xdsh command, and the xdsh command file have been supplied. Only one or the other is allowed.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    #
    # get the  node list
    #
    if (!(@$nodes))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "No noderange specified on the command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    my @nodelist = @$nodes;

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
        if (!(-e $options{'xdsh_file'}))
        {    # file does not exist
            my $rsp = {};
            $rsp->{data}->[0] =
              "Input xdsh command file: $options{'xdsh_file'} does not exist.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            exit 1;
        }
        $cmd = `cat $options{'xdsh_file'}`;
    }
    chomp $cmd;

    #
    # Get exact match request
    #
    my $exactmatch = "NO";
    if ($options{'exactmatch'})
    {
        $exactmatch = "YES";
    }

    #
    # Get ignore matches on first template request
    #
    my $ignorefirsttemplate = "NO";
    if ($options{'ignorefirst'})
    {
        $ignorefirsttemplate = "YES";
    }

    #
    #
    # Get template path
    #
    my $admintemplate;
    $templatepath = $options{'template_path'};
    if (!$templatepath)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Missing template path on the command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    else
    {
        if (-e ($templatepath))
        {    # the admin has input the template
            $admintemplate = "YES";
        }
        else
        {
            $admintemplate = "NO";
        }
    }

    chomp $templatepath;

    #
    # Get template count
    #

    my $templatecnt = $options{'template_cnt'};
    if (!$templatecnt)
    {
        $templatecnt = 0;    # default
    }
    chomp $templatecnt;

    #
    # Get remove template value
    #

    my $rmtemplate = "NO";    #default
    if ($options{'remove_template'})
    {
        $rmtemplate = "YES";
    }
    chomp $rmtemplate;

    #
    #
    # Get where to put the output
    #

    my $outputfile = $options{'output_file'};
    if (!$outputfile)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Output file path missing.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    chomp $outputfile;

    # open the file for writing
    unless (open(OUTPUTFILE, ">$outputfile"))
    {
        my $rsp = {};
        $rsp->{data}->[0] = " Cannot open $outputfile for output.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    $::OUTPUT_FILE_HANDLE = \*OUTPUTFILE;

    #
    #
    # Get seed node if it exists to build the original template
    # if seed node does not exist and the admin did not submit a \
    # template, the the first node becomes the seed node
    #
    my @seed;
    my $seednode = $options{'seed_node'};
    if ($seednode)
    {
        chomp $seednode;
        push @seed, $seednode;
    }
    else
    {
        if ($admintemplate eq "NO")
        {    # admin did not generate a template
            push @seed, $nodelist[$#nodelist];    # assign last element as seed
            $seednode = $nodelist[$#nodelist];
        }
    }

    my $tmpnodefile;

    #
    # Build Output file header
    #
    my $rsp = {};
    $rsp->{data}->[0] = "Command started with following input.\n";
    if ($cmd)
    {
        $rsp->{data}->[1] = "xdsh cmd:$cmd.\n";
    }
    else
    {
        $rsp->{data}->[1] = "xdsh cmd:None.\n";
    }
    $rsp->{data}->[2] = "Template path:$templatepath.\n";
    $rsp->{data}->[3] = "Template cnt:$templatecnt.\n";
    $rsp->{data}->[4] = "Remove template:$rmtemplate.\n";
    $rsp->{data}->[5] = "Output file:$outputfile.\n";
    $rsp->{data}->[6] = "Exactmatch:$exactmatch.\n";
    $rsp->{data}->[7] = "Ignorefirst:$ignorefirsttemplate.\n";
    if ($seednode)
    {
        $rsp->{data}->[8] = "Seed node:$seednode.\n";
    }
    else
    {
        $rsp->{data}->[8] = "Seed node:None.\n";
    }
    if ($options{'xdsh_file'})
    {
        $rsp->{data}->[9] = "file:$options{'xdsh_file'}.\n";
    }
    else
    {
        $rsp->{data}->[9] = "file:None.\n";
    }

    #write to output file the header
    my $i = 0;
    while ($i < 10)
    {
        print $::OUTPUT_FILE_HANDLE $rsp->{data}->[$i];
        $i++;
    }
    print $::OUTPUT_FILE_HANDLE "\n";
    if ($::VERBOSE)
    {
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # setup a tempfile for xdsh output
    $tempfile = "/tmp/sinv.$$";

    #
    # if we are to seed the original template,run the dsh command against the
    # seed node and save in template_path
    if ($seednode)
    {

        # Below code needed to run xdsh from the plugin
        # and still support a hierarchial xdsh
        # this will run xdsh with input,  return to xdshoutput routine
        # and then return inline after this code.

        $processflg = "seednode";
        $sub_req->(
                   {
                    command => ['xdsh'],
                    node    => \@seed,
                    arg     => [$cmd]
                   },
                   \&xdshoutput
                   );

    }
    $processflg = "node";

    # Tell them we are running DSH
    if ($::VERBOSE)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Running xdsh command.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    #
    #  Run the DSH command
    #

    # Below code needed to run xdsh from the plugin
    # and still support a hierarchial xdsh
    # this will run xdsh with input,  return to xdshoutput routine
    # and then return inline after this code.

    $sub_req->(
               {
                command => ['xdsh'],
                node    => \@nodelist,
                arg     => [$cmd]
               },
               \&xdshoutput
               );

    #  Build report and write to output file
    #  if file exist and has something in it
    if (-e $tempfile)
    {    # if dsh returned something

        # Tell them we are building the report
        my $rsp = {};
        $rsp->{data}->[0] = "Building Report.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);

        xCAT::SINV->buildreport(
                                $outputfile,   $tempfile,
                                $templatepath, $templatecnt,
                                $rmtemplate,   \@nodelist,
                                $callback,     $ignorefirsttemplate,
                                $exactmatch,   $admintemplate
                                );
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "No output from xdsh.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # Finally we need to cleanup and exit
    #
    system("/bin/rm  $tempfile");
    close(OUTPUTFILE);
    my $rsp = {};
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
         whether to remove the generated templates, original dsh node list,
		 ignorefirsttemplate,exactmatch)

  If exactmatch is chosen, a diff is done against the template and the output.
  If not exactmatch, then each record (line) in the template must be 
  checked against the node's output to determine, if it exists. 

=cut

#------------------------------------------------------------------------------
sub buildreport
{

    my (
        $class,        $outputfile,  $dshrun,
        $templatepath, $templatecnt, $removetemplate,
        $nodelistin,   $callback,    $ignorefirsttemplate,
        $exactmatch,   $admintemplate
      )
      = @_;
    my @nodelist = @$nodelistin;
    my $pname    = "buildreport";
    my $rc       = $::OK;
    my $rsp      = {};

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
                my @info;
                if ($exactmatch eq "YES")
                {                                  # output matches exactly
                    @info =
                      xCAT::SINV->diffoutput($outputfile, \@templatearray,
                                     \@processNodearray, \%nodehash, $callback);
                }
                else
                {    # output is contained in the template
                    @info =
                      xCAT::SINV->compareoutput($outputfile, \@templatearray,
                                     \@processNodearray, \%nodehash, $callback);
                }
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
        my @info;
        if ($exactmatch eq "YES")
        {    # output matches exactly
            @info =
              xCAT::SINV->diffoutput(
                                     $outputfile, \@templatearray,
                                     \@Nodearray, \%nodehash,
                                     $callback
                                     );
        }
        else
        {    # output is contained in the template
            @info =
              xCAT::SINV->compareoutput(
                                        $outputfile, \@templatearray,
                                        \@Nodearray, \%nodehash,
                                        $callback
                                        );
        }
        $nodename = pop @info;
        $template = pop @info;
        push @{$nodehash{$template}}, $nodename;
    }

    #
    # Write the report
    #

    xCAT::SINV->writereport($outputfile, \%nodehash, \@nodelist, $callback,
                            $ignorefirsttemplate);

    #
    # Cleanup  the template files if the remove option was yes
    #
    $removetemplate =~ tr/a-z/A-Z/;    # convert to upper
    if ($removetemplate eq "YES")
    {
        foreach $template (@templatearray)    # for each template
        {
            if (-f "$template")
            {

                if (($template ne $templatepath) || ($admintemplate eq "NO"))

                  # not the first template or the first one was not created by
                  # admin, it was generated by the code
                {
                    `/bin/rm -f $template 2>&1`;
                }
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
        }

        # end check exists
        #
        # if match found, process no more templates
        #
        if ($match == 1)
        {
            last;    # exit template loop
        }
    }

    # end foreach template
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

=head3   diffoutput  			    	 
 The purpose of this routine is to build sets of nodes
   that have the same configuration.  We will build up
   to template_cnt sets.  If more nodes are not part of these
   sets they will be put in an other list.

 foreach template
  Open the input template
  Compare the template to the input node data
  if exact match
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
sub diffoutput
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
    my $rsp                = {};
    my @template_noheader  = ();
    my @nodearray_noheader = ();

    # build a node arrray without the header
    foreach $nodeline (@Nodearray)    # for each node line
    {
        if ($nodeline =~ /HOST:/)
        {                             # save the hostname
            ($line, $nodename) = split ':', $nodeline;
            $nodename =~ s/\s*//g;    # remove blanks
            chomp $nodename;

        }
        else                          # build node array with no header
        {
            push(@nodearray_noheader, $nodeline);
        }
    }    # end foreach nodeline

    #
    # foreach template
    #   build a template array with no header
    #   compare to the node array with no header
    #

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

                    # Build template array with no header
                    push(@template_noheader, $templateline);

                }    # if header
            }    # end foreach templateline

            # if nodearray matches template exactly,quit processing templates

            if (@nodearray_noheader eq @template_noheader)
            {
                $matchedtemplate = $template;
                $match           = 1;
                last;
            }
            else    # go to next template
            {
                $match             = 0;
                @template_noheader = ();
            }
        }    # end template exist

    }    #end foreach template

    #
    # if no match
    #   if generate a new template - check the list of template files
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
    my ($class, $outputfile, $Node_hash, $nodelistin, $callback,
        $ignorefirsttemplate)
      = @_;
    my %nodehash     = %$Node_hash;
    my @dshnodearray = @$nodelistin;
    my $pname        = "writereport";
    my $template;
    my @nodenames;
    my @nodearray;

    #
    # Header message
    #
    my $rsp = {};
    $ignorefirsttemplate =~ tr/a-z/A-Z/;    # convert to upper

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
            if ($ignorefirsttemplate ne "YES")
            {                              #  report first template
                $rsp->{data}->[0] = "$nodename\n";
                print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
                if ($::VERBOSE)
                {
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }
            else
            {    # do not report nodes on first template
                $rsp->{data}->[0] =
                  "Not reporting matches on first template.\n";
                print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
                if ($::VERBOSE)
                {
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                $ignorefirsttemplate = "NO";    # reset for remaining templates
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

#------------------------------------------------------------------------------

=head3   dshoutput  			    	 

 Check xdsh output  - get output from xdsh and pipe to xdshbak and
 store results in $tempfile or $templatepath ( for seed node) based on
 $processflag = seednode 

=cut

#------------------------------------------------------------------------------
sub xdshoutput
{
    my $resp = shift;
    my $i    = 0;
    @dshresult = ();
    foreach (@{$resp->{info}})
    {
        my $line = $_;
        $line .= "\n";
        push(@dshresult, $line);
    }

    # open file to write results of xdsh
    my $newtempfile = $tempfile;
    $newtempfile .= "temp";
    my $rsp = {};
    $rsp->{data}->[0] = "Could not open $newtempfile\n";
    open(FILE, ">$newtempfile");
    if ($? > 0)
    {
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }
    foreach my $line (@dshresult)
    {
        print FILE $line;
    }
    close FILE;
    my $outputfile;
    if ($processflg eq "seednode")
    {    # xdsh to seednode
        $outputfile = $templatepath;
    }
    else
    {    # xdsh to nodelist
        $outputfile = $tempfile;
    }

    # open  file to put results of xdshbak
    my $rsp = {};
    $rsp->{data}->[0] = "Could not open $outputfile\n";
    open(FILE, ">$outputfile");
    if ($? > 0)
    {
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }
    my $rsp = {};
    $rsp->{data}->[0] = "Could not call xdshbak \n";
    my $cmd = " /opt/xcat/bin/xdshbak <$newtempfile |";

    open(DSHBAK, "$cmd");
    if ($? > 0)
    {
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    my $line;

    while (<DSHBAK>)
    {
        $line = $_;
        print FILE $line

    }

    close(DSHBAK);
    close FILE;

    system("/bin/rm  $newtempfile");
    return 0;

}

1;
