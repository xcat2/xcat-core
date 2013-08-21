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
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use strict;
use xCAT::MsgUtils;
use xCAT::NodeRange;
use xCAT::NodeRange qw/noderange abbreviate_noderange/;
use xCAT::Utils;
use Fcntl qw(:flock);
use Getopt::Long;
#use Data::Dumper;
my $tempfile;
my $errored = 0;
my @dshresult;
my $templatepath;
my $processflg;
my @cmdresult;
my @errresult;

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
    my $callback = shift;
## usage message

    my $usagemsg1 =
      "The sinv command is designed to check the configuration of nodes in a cluster.\nRun man sinv for more information.\n\nInput parameters are as follows:\n";
    my $usagemsg1a = "sinv -h \nsinv -v \nsinv";
    my $usagemsg3  =
      " -p <template path> [-o output file ] [-t <template count>]\n";
    my $usagemsg4 = "      [-r remove templates] [-s <seednode>]\n";
    my $usagemsg5 = "      [-e exactmatch] [-i ignore] [-V verbose]\n";
    my $usagemsg5A = "      [-l userid] [--devicetype type_of_device]\n";
    my $usagemsg6 = "      {-c <command>  | -f <command file>}";
    my $usagemsg .= $usagemsg1 .= $usagemsg1a .= $usagemsg3 .= $usagemsg4 .=
      $usagemsg5 .= $usagemsg5A .= $usagemsg6;
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
    my ($class, $request, $callback, $sub_req) = @_;
    my $rsp = {};
    my $rc  = 0;
    $::CALLBACK = $callback;
    my $args = $request->{arg};
    if (!($args)) {
        my $rsp = {};
        $rsp->{data}->[0] =
          "No arguments have been supplied to the sinv command. Check the sinv man page for appropriate input. \n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    @ARGV = @{$args};    # get arguments
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
                    'l|user=s'      => \$options{'user'},
                    'devicetype|devicetype=s'    => \$options{'devicetype'}, 
                    'c|cmd=s'       => \$options{'sinv_cmd'},
                    'f|file=s'      => \$options{'sinv_cmd_file'},
                    'v|version'     => \$options{'version'},
                    'V|Verbose'     => \$options{'verbose'},
        )
      )
    {

        &usage($callback);
        exit 1;
    }
    if ($options{'help'})
    {
        &usage($callback);
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

    # if neither  command or file, error
    if (!($options{'sinv_cmd'}) && (!($options{'sinv_cmd_file'})))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "Neither the sinv command, nor the sinv command file have been supplied.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    # if  both  command and file, error
    if (($options{'sinv_cmd'}) && (($options{'sinv_cmd_file'})))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "Both the sinv command, and the sinv command file have been supplied. Only one or the other is allowed.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }

    if ( defined( $options{template_path} ) && ($options{template_path} !~ /^\//) ) {#relative path
        $options{template_path} = xCAT::Utils->full_path($options{template_path}, $request->{cwd}->[0]);
    }
    if ( defined( $options{output_file} ) && ($options{output_file} !~ /^\//) ) {#relative path
        $options{output_file} = xCAT::Utils->full_path($options{output_file}, $request->{cwd}->[0]);
    }
    if ( defined( $options{sinv_cmd_file} ) && ($options{sinv_cmd_file} !~ /^\//) ) {#relative path
        $options{sinv_cmd_file} = xCAT::Utils->full_path($options{sinv_cmd_file}, $request->{cwd}->[0]);
    }
    #
    # Get Command to run
    #
    my $cmd;
    if ($options{'sinv_cmd'})
    {
        $cmd = $options{'sinv_cmd'};
    }
    else
    {

        # read the command from the file
        if (!(-e $options{'sinv_cmd_file'}))
        {    # file does not exist
            my $rsp = {};
            $rsp->{data}->[0] =
              "Input command file: $options{'sinv_cmd_file'} does not exist.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        $cmd = `cat $options{'sinv_cmd_file'}`;
    }
    chomp $cmd;

    #
    # the command can be either xdsh or rinv for now
    # strip off the program and the noderange
    #
    my @nodelist  = ();
    my @cmdparts  = ();
    my $devicecommand =0;
    if ($options{'devicetype'}) {  
      # must split different because devices have commands with spaces
      @cmdparts  = split(' ', $cmd,3);
      $devicecommand =1;
    } else {
      @cmdparts  = split(' ', $cmd);
    }
    my $cmdtype   = shift @cmdparts;
    my $noderange = shift @cmdparts;
    my @cmd       = ();
    if ($noderange =~ /^-/)  # if imageupdate not node
    {    # no noderange
        push @cmd, $noderange;    #  put flag back on command
    }
    # root is sending the command
    my @envs;
    # if -l user id supplied
    if ($options{'user'}) {
       push @cmd,"-l";
       push @cmd,$options{'user'};
       push @envs,"DSH_TO_USERID=$options{'user'}";
    }
    # if device type supplied
    if ($options{'devicetype'}) {
       push @cmd,"--devicetype";
       my $switchtype = $options{'devicetype'};
       $switchtype =~ s/::/\//g;
       push @cmd,$switchtype;
    }
 
    foreach my $part (@cmdparts)
    {

        push @cmd, $part;         # build rest of command
    }
    if (($cmdtype ne "xdsh") && ($cmdtype ne "rinv"))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "Only commands xdsh and rinv are currently supported.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        exit 1;
    }
    my $cmdoutput;
    if ($cmdtype eq "xdsh")
    {                             # choose output routine to run
        $cmdoutput = "xdshoutput";
    }
    else
    {                             # rinv
        $cmdoutput = "rinvoutput";
    }

    # this must be a noderange or the flag indicating we are going to the
    #  install image ( -i) for xdsh, only case where noderange is not required

    if ($noderange =~ /^-/)
    {                             # no noderange, it is a flag
        @nodelist = "NO_NODE_RANGE";

        # add flag back to arguments
        $args .= $noderange;
    }
    else
    {                             # get noderange
        @nodelist = noderange($noderange);    # expand noderange
        if (nodesmissed)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "Invalid or missing noderange:" . join(',', nodesmissed);
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return;
        }
    }

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
        $::NOOUTPUTFILE = 1;
    }
    else
    {

        chomp $outputfile;
    }

    # open the file for writing, if it exists
    if ($outputfile)
    {
        unless (open(OUTPUTFILE, ">$outputfile"))
        {
            my $rsp = {};
            $rsp->{data}->[0] = " Cannot open $outputfile for output.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            exit 1;
        }
        $::OUTPUT_FILE_HANDLE = \*OUTPUTFILE;

    }

    #
    # For xdsh command
    # Get seed node if it exists to build the original template
    # if seed node does not exist and the admin did not submit a
    # template, the the first node becomes the seed node
    # if there is no nodelist then error
    my @seed;
    my $seednode = $options{'seed_node'};
    if ($seednode)
    {
        chomp $seednode;
        push @seed, $seednode;
    }
    else
    {
        if ($admintemplate eq "NO")    # default the seed node
        {                              # admin did not generate a template
            if ($nodelist[0] ne "NO_NODE_RANGE")
            {
                push @seed, $nodelist[0];    # assign first element as seed
                $seednode = $nodelist[0];
            }
            else
            {                                # error cannot default
                my $rsp = {};
                $rsp->{data}->[0] =
                  "No template or seed node supplied and no noderange to choose a default.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit 1;
            }
        }
    }

    my $tmpnodefile;

    #
    # Build Output header
    if (($::VERBOSE) || ($outputfile))
    {

        #
        my $rsp = {};
        $rsp->{data}->[0] = "Command started with following input.\n";
        if ($cmd)
        {
            $rsp->{data}->[1] = "$cmdtype cmd:$cmd.\n";
        }
        else
        {
            $rsp->{data}->[1] = "$cmdtype cmd:None.\n";
        }
        $rsp->{data}->[2] = "Template path:$templatepath.\n";
        $rsp->{data}->[3] = "Template cnt:$templatecnt.\n";
        $rsp->{data}->[4] = "Remove template:$rmtemplate.\n";
        if ($outputfile)
        {
            $rsp->{data}->[5] = "Output file:$outputfile.\n";
        }
        else
        {
            $rsp->{data}->[5] = "Output file:None.\n";
        }
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
        if ($options{'sinv_cmd_file'})
        {
            $rsp->{data}->[9] = "file:$options{'sinv_cmd_file'}.\n";
        }
        else
        {
            $rsp->{data}->[9] = "file:None.\n";
        }

        #write to output file the header
        my $i = 0;
        if ($::OUTPUT_FILE_HANDLE)
        {
            while ($i < 10)
            {
                print $::OUTPUT_FILE_HANDLE $rsp->{data}->[$i];
                $i++;
            }
            print $::OUTPUT_FILE_HANDLE "\n";
        }
        if (!($outputfile))
        {
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
    }

    # setup a tempfile for command output
    $tempfile = "/tmp/sinv.$$";

    #
    # if we are to seed the original template,run the dsh command against the
    # seed node and save in template_path
    # already checked for rinv command above and exited, if seed node
    #
    if ($seednode)
    {

        # Below code needed to run xdsh or rinv from the plugin
        # and still support a hierarchial xdsh
        # this will run xdsh or rinv with input,  return to
        # xdshoutput routine or rinvoutput routine
        # and then return inline after this code.

        $processflg = "seednode";
        @errresult  = ();
        @cmdresult  = ();
        $sub_req->(
                   {
                    command => [$cmdtype],
                    node    => \@seed,
                    env     => [@envs],
                    arg     => [@cmd]
                   },
                   \&$cmdoutput
                   );

        #  write the results to the tempfile after running through xdshcoll
        $rc = &storeresults($callback,$devicecommand);

    }
    $processflg = "node";

    # Tell them we are running the command
    if (($::VERBOSE) || ($::NOOUTPUTFILE))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Running $cmdtype command.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # Below code needed to run xdsh/rinv from the plugin
    # and still support a hierarchial xdsh
    # this will run the command with input,  return to cmdoutput routine
    # and then return inline after this code.
    @errresult = ();
    @cmdresult = ();
    $sub_req->(
               {
                command => [$cmdtype],
                node    => \@nodelist,
                env     => [@envs],
                arg     => [@cmd]
               },
               \&$cmdoutput
               );


    #  write the results to the tempfile after running through xdshcoll
    $rc = &storeresults($callback,$devicecommand);

    #  Build report and write to output file
    #  if file exist and has something in it
    if ((-e $tempfile) && ($rc == 0))
    {    # if cmd returned something

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
        $rsp->{data}->[0] = "No output from $cmdtype.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # Finally we need to cleanup and exit
    #
    if (-e $tempfile)
    {

        system("/bin/rm  $tempfile");
    }
    my $rsp = {};
    $rsp->{data}->[0] = "Command Complete.";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    if ($::OUTPUT_FILE_HANDLE)
    {
        close(OUTPUTFILE);
        $rsp->{data}->[0] = "Check report in $outputfile.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    return $rc;
}

#------------------------------------------------------------------------------

=head3   buildreport (note originally written only for xdsh but
		 now supports rinv also)

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

    # Read the output of the dsh or rinv command

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
    my $headerlines = 0;
    my @processNodearray;
    my $hostline;
    my $nodename;
    my $template;
    my @Nodearray;
    my $dshline;
    my %nodehash;
  DSHARRAY: foreach $dshline (@dsharray)    # each line returned from dsh/rinv
    {

        if ($dshline =~ /============/)     #  Host header
        {
            if ($headerlines < 2)
            {

                # read until we reach another header
                push @Nodearray, $dshline;
                $headerlines++;
            }
            else
            {    # Hit next header, process current array
                @processNodearray = @Nodearray;    # save node data
                @Nodearray        = ();            # initialize array
                $headerlines      = 1;             # already read one line
                push @Nodearray, $dshline;         # save next data
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
                if ($nodename ne "UNKNOWN")
                {
                    push @{$nodehash{$template}}, $nodename;    # add node name
                }    # to template hash

            }
        }
        else
        {

            if ($dshline !~ /^\s*$/)    # skip blanks

              # skip  blanks and stop on the next host
            {
                push @Nodearray, $dshline;    # build the node results
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
        if ($nodename ne "UNKNOWN")
        {
            push @{$nodehash{$template}}, $nodename;
        }
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
    my @nodenames;
    my @tmpnodenames;
    my $line;
    %nodehash = ();
    my $template;
    my $matchedtemplate;
    my $rsp = {};

    foreach $template (@templatearray)    # for each template
    {
        my $skiphostline = 1;
        if (-f "$template")
        {                                 # if it exists

            # Read the template file
            open(TEMPLATE, "<$template");
            my @template = <TEMPLATE>;

            # now compare host data to template
            foreach $templateline (@template)    # for each line in the template
            {

                # skip the header and blanks
                if ($templateline =~ /============/)
                {                                #  Host header
                    next;
                }
                if ($templateline =~ /UNKNOWN/)
                {                                #  skip UNKNOWN header
                    next;
                }
                if ($skiphostline == 1)
                {
                    $skiphostline = 0;
                    next;
                }
                if ($templateline !~ /^\s*$/)    # skip blanks
                {
                    $match = 0;
                    my $gothosts = 0;
                    foreach $nodeline (@Nodearray)    # for each node line
                    {
                        if ($nodeline =~ /==========/)
                        {
                            next;
                        }

                        if ($gothosts == 0)
                        {                             # get the hostnames
                            $nodename = $nodeline;
                            $nodename =~ s/\s*//g;    # remove blanks
                            chomp $nodename;
                            if ($nodename eq "UNKNOWN")
                            {                         # skip this node
                                @info[0] = "NONE";
                                @info[1] = "UNKNOWN";
                                return @info;
                            }
                            $gothosts = 1;
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
    my $hostfound          = 0;

    # build a node array without the header
    # skip any UNKNOWN entries added by xdshcoll
    foreach $nodeline (@Nodearray)    # for each node line
    {
        if ($nodeline =~ /================/)
        {                             # skip
            next;
        }
        if ($hostfound == 0)
        {                             # save the hostname
            $nodename = $nodeline;
            $nodename =~ s/\s*//g;    # remove blanks
            chomp $nodename;
            if ($nodename eq "UNKNOWN")
            {                         # skip this node
                @info[0] = "NONE";
                @info[1] = "UNKNOWN";
                return @info;
            }
            $hostfound = 1;
            next;

        }

        # build node array with no header
        push(@nodearray_noheader, $nodeline);
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
            my $skiphostline = 1;

            # Read the template file
            open(TEMPLATE, "<$template");
            my @template = <TEMPLATE>;

            # now compare host data to template
            foreach $templateline (@template)    # for each line in the template
            {

                # skip the header and blanks
                if ($templateline =~ /============/)
                {                                #  Host header
                    next;
                }
                if ($templateline =~ /UNKNOWN/)
                {                                # skip UNKNOWN HEADER 
                    next;
                }
                if ($skiphostline == 1)
                {
                    $skiphostline = 0;
                    next;
                }
                if ($templateline !~ /^\s*$/)    # skip blanks

                {

                    # Build template array with no header
                    push(@template_noheader, $templateline);

                }                                # if header
            }    # end foreach templateline

            # if nodearray matches template exactly,quit processing templates
            my $are_equal =
              compare_arrays(\@nodearray_noheader, \@template_noheader);
            if ($are_equal)
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
    my $firstpass = 0;
    my @allnodearray=();
    foreach my $template (sort keys %nodehash)
    {

        # print template name
        $rsp->{data}->[0] = "The following nodes match $template:\n";
        if ($::OUTPUT_FILE_HANDLE)
        {
            print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
        }
        if (($::VERBOSE) || ($::NOOUTPUTFILE))
        {
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        #print list of nodes
        @nodenames = @{$nodehash{$template}};
        my $nodelist = "";
        @nodearray=();
        foreach my $nodenameline (@nodenames)
        {

            # split apart the list of nodes
            my @longnodenames = split(',', $nodenameline);
            foreach my $node (@longnodenames)
            {
                my @shortnodename = split(/\./, $node);
                push @nodearray, $shortnodename[0];    # add to process list
                push @allnodearray, $shortnodename[0];  # add to total list
                $nodelist .= $shortnodename[0];        # add to print list
                $nodelist .= ',';
            }
        }
      
        chop $nodelist;
        # convert to noderanges if possible
        my $nodearray;
        $nodearray->{0} = \@nodearray;
        my $newnodelist = abbreviate_noderange($nodearray->{0});        
        if ($ignorefirsttemplate ne "YES")
        {                                              #  report first template
                $rsp->{data}->[0] = "$newnodelist\n";
            
            if ($::OUTPUT_FILE_HANDLE)
            {
                print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
            }
            if (($::VERBOSE) || ($::NOOUTPUTFILE))
            {
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
        else
        {    # do not report nodes on first template
            if ($firstpass == 0)
            {
                $rsp->{data}->[0] =
                  "Not reporting matches on first template.\n";
                if ($::OUTPUT_FILE_HANDLE)
                {
                    print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
                }
                if (($::VERBOSE) || ($::NOOUTPUTFILE))
                {
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                $firstpass = 1;
            }
        }
        $ignorefirsttemplate = "NO";    # reset for remaining templates
    }

    #
    # Now check to see if we covered all nodes in the dsh
    #  short names must match long names, ignore NO_NODE_RANGE
    #
    my $nodefound = 0;
    my $rsp       = {};
    foreach my $dshnodename (@dshnodearray)
    {
        if (($dshnodename ne "NO_NODE_RANGE") && ($dshnodename ne "UNKNOWN"))
        {                               # skip it
            my @shortdshnodename;
            my @shortnodename;
            chomp $dshnodename;
            $dshnodename =~ s/\s*//g;    # remove blanks
            #foreach my $nodename (@nodearray)
            foreach my $nodename (@allnodearray)
            {
                @shortdshnodename = split(/\./, $dshnodename);
                @shortnodename    = split(/\./, $nodename);

                if ($shortdshnodename[0] eq $shortnodename[0])
                {
                    $nodefound = 1;      # we have a match
                    last;
                }
            }
            if ($nodefound == 0)
            {                            # dsh node name missing

                # add missing node
                $rsp->{data}->[0] .= $shortdshnodename[0];
                $rsp->{data}->[0] .= ",";
            }
        }
    }
    if ($rsp->{data}->[0])
    {
        $rsp->{data}->[0] = "The following nodes had no output:\n";
        if ($::OUTPUT_FILE_HANDLE)
        {
            print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
        }
        if (($::VERBOSE) || ($::NOOUTPUTFILE))
        {
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        chop $rsp->{data}->[0];
        $rsp->{data}->[0] .= "\n";
        if ($::OUTPUT_FILE_HANDLE)
        {
            print $::OUTPUT_FILE_HANDLE $rsp->{data}->[0];
        }
        if (($::VERBOSE) || ($::NOOUTPUTFILE))
        {
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
    }
    $nodefound = 0;
    return;
}

#------------------------------------------------------------------------------

=head3   xdshoutput  			    	 

 Check xdsh output  - get output from command and pipe to xdshcoll 

=cut

#------------------------------------------------------------------------------
sub xdshoutput
{
    my $rsp = shift;

    my $rc = 0;

    # Handle info structure, like xdsh returns
    if ($rsp->{warning})
    {
        foreach (@{$rsp->{warning}})
        {
            my $line = $_;
            $line .= "\n";
            push(@errresult, $line);
        }
    }
    if ($rsp->{error})
    {
        foreach (@{$rsp->{error}})
        {
            my $line = $_;
            $line .= "\n";
            push(@errresult, $line);
        }
    }
    if ($rsp->{info})
    {
        foreach (@{$rsp->{info}})
        {
            my $line = $_;
            $line .= "\n";
            push(@cmdresult, $line);
        }
    }
    if ($rsp->{data})
    {
        foreach (@{$rsp->{data}})
        {
            my $line = $_;
            $line .= "\n";
            push(@cmdresult, $line);
        }
    }

    return $rc;

}

#------------------------------------------------------------------------------

=head3   rinvoutput  			    	 

 Check rinv output  - get output from command

=cut

#------------------------------------------------------------------------------
sub rinvoutput
{
    my $rsp = shift;
    #print "I am here \n"; 
    #print Dumper($rsp); 
    # Handle node structure, like rinv returns
    my $errflg = 0;

    #if (scalar @{$rsp->{node}})
    if ($rsp->{node})
    {

        my $nodes = ($rsp->{node});
        my $node;
        foreach $node (@$nodes)
        {
            my $desc = $node->{name}->[0];
            if ($node->{errorcode})
            {
                if (ref($node->{errorcode}) eq 'ARRAY')
                {
                    foreach my $ecode (@{$node->{errorcode}})
                    {
                        $xCAT::Client::EXITCODE |= $ecode;
                    }
                }
                else
                {
                    $xCAT::Client::EXITCODE |= $node->{errorcode};
                }    # assume it is a non-reference scalar
            }
            if ($node->{error})
            {
                $desc .= ": Error: " . $node->{error}->[0];
                $errflg = 1;
            }
            if ($node->{data})
            {
                if (ref(\($node->{data}->[0])) eq 'SCALAR')
                {
                    $desc = $desc . ": " . $node->{data}->[0];
                }
                else
                {
                    if ($node->{data}->[0]->{desc})
                    {
                        $desc = $desc . ": " . $node->{data}->[0]->{desc}->[0];
                    }
                    if ($node->{data}->[0]->{contents})
                    {
                        $desc = "$desc: " . $node->{data}->[0]->{contents}->[0];
                    }
                }
            }
            if ($desc)
            {

                my $line = $desc;
                $line .= "\n";

                push(@cmdresult, $line);
            }
        }
    }

    return 0;

}

#------------------------------------------------------------------------------

=head3   storeresults 			    	 

  Runs command output through xdshcoll and stores in /tmp/<tempfile>
 store results in $tempfile or $templatepath ( for seed node) based on
 $processflag = seednode 
=cut

#------------------------------------------------------------------------------

sub storeresults
{
    my $callback = shift;
    my $devicecommand= shift;
    # open file to write results of xdsh or rinv command
    my $newtempfile = $tempfile;
    $newtempfile .= "temp";
    unless (open(NEWTMPFILE, ">$newtempfile"))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Could not open $newtempfile\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    foreach my $line (@cmdresult)
    {
        print NEWTMPFILE $line;
    }
    close NEWTMPFILE;
    my $outputfile;
    if ($processflg eq "seednode")
    {    # cmd to seednode
        $outputfile = $templatepath;
    }
    else
    {    # cmd to nodelist
        $outputfile = $tempfile;
    }

    # open  file to put results of xdshcoll
    unless (open(NEWOUTFILE, ">$outputfile"))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Could not open $outputfile\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    my $cmd = " $::XCATROOT/sbin/xdshcoll <$newtempfile |";

    unless (open(XCOLL, "$cmd"))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Could not call xdshcoll \n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my $line;

    while (<XCOLL>)
    {
        $line = $_;
        print NEWOUTFILE $line

    }

    close(XCOLL);
    close NEWOUTFILE;

    system("/bin/rm  $newtempfile");
    # is device command, we get false errors from the Switch, check for  
    # blank error output lines and remove them.  If there is nothing left
    # then there really were no errors
    my @newerrresult=();
    my $processerrors =1;
    if ($devicecommand==1) {
        foreach my $line (@errresult)
        {
          my @newline =  (split(/:/, $line));
          if ($newline[1] !~ /^\s*$/) { # Not blank, then save it 
            push @newerrresult,$line;  
          } 
          
        } 
        my $arraysize=@newerrresult;
        if ($arraysize < 1) {
            $processerrors =0;
        }
    }

    # capture errors
    #
    if ((@errresult) && ($processerrors ==1))
    {    # if errors
        my $rsp = {};
        my $i   = 0;
        foreach my $line (@errresult)
        {
            $rsp->{data}->[$i] = "$line";
            $i++;
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);

    }
    return;
}

sub compare_arrays
{
    my ($first, $second) = @_;
    return 0 unless @$first == @$second;
    for (my $i = 0 ; $i < @$first ; $i++)
    {
        return 0 if $first->[$i] ne $second->[$i];
    }
    return 1;
}
1;
