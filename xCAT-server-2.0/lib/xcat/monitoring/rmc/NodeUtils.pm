#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package NodeUtils;

1;

#-------------------------------------------------------------------------------
=head1  NodeUtils module
=head2  NodeUtils module is used to store common functions for RMC monitoring on 
        xCAT clusters.
=cut
#-------------------------------------------------------------------------------


sub isHMC
{
  my $hmcfile = "/opt/hsc/data/hmcType.properties";
  if (-e $hmcfile) { return 1; }
  else { return 0; }
}

#--------------------------------------------------------------------------------
=head3    runcmd
    Run the given cmd and return the output in an array (already chopped).  Alternatively,
    if this function is used in a scalar context, the output is joined into a single string
    with the newlines separating the lines.  
    Arguments:
        command, exitcode and reference to output
    Returns:
        see below
    Error:
        Normally, if there is an error running the cmd, it will display the error msg
        and exit with the cmds exit code, unless exitcode is given one of the
        following values:
             0:     display error msg, DO NOT exit on error, but set
                $::RUNCMD_RC to the exit code.
            -1:     DO NOT display error msg and DO NOT exit on error, but set
                $::RUNCMD_RC to the exit code.
            -2:    DO the default behavior (display error msg and exit with cmds
                exit code.
        number > 0:    Display error msg and exit with the given code
    Example:
        my $outref =  NodeUtils->runcmd($cmd, -2, 1);     
    Comments:
        If refoutput is true, then the output will be returned as a reference to
        an array for efficiency.
=cut
#--------------------------------------------------------------------------------
sub runcmd
{
  my ($class, $cmd, $exitcode, $refoutput) = @_;
  $::RUNCMD_RC = 0;
  if (!$::NO_STDERR_REDIRECT) { 
    if (!($cmd =~ /2>&1$/)) { $cmd .= ' 2>&1'; }
  }
  my $outref = [];
  @$outref = `$cmd`;
  if ($?)
  {
    $::RUNCMD_RC = $? >> 8;
    my $displayerror = 1;
    my $rc;
    if (defined($exitcode) && length($exitcode) && $exitcode != -2)
    {
      if ($exitcode > 0)
      {
	$rc = $exitcode;
      }    # if not zero, exit with specified code
      elsif ($exitcode <= 0)
      {
	$rc = '';    # if zero or negative, do not exit
	if ($exitcode < 0) { $displayerror = 0; }
      }
    }
    else
    {
      $rc = $::RUNCMD_RC;
    }    # if exitcode not specified, use cmd exit code
    if ($displayerror)
    {
      my $errmsg = '';
      if (($^O =~ /^linux/i) && $::RUNCMD_RC == 139)
      {
        $errmsg = "Segmentation fault  $errmsg";
      }
      else
      {
        # The error msgs from the -api cmds are pretty messy.  Clean them up a little.
        NodeUtils->filterRmcApiOutput($cmd, $outref);
        $errmsg = join('', @$outref);
        chomp $errmsg;
      }
      print "Exit code $::RUNCMD_RC from command: $cmd\nError message from cmd: $errmsg\n"
    }
  }
  if ($refoutput)
  {
    chomp(@$outref);
    return $outref;
  }
  elsif (wantarray)
  {
    chomp(@$outref);
    return @$outref;
  }
  else
  {
    my $line = join('', @$outref);
    chomp $line;
    return $line;
  }
}

#--------------------------------------------------------------------------------
=head3    runrmccmd
    Runs an RMC commmand
    Arguments:
        $rmccmd, $resclass, $options, $select, $exitcode, $nodelist_ref
    Returns:
        the output from  runcmd($cmd, -2, 1)
        as a ref to the output array.
    Error:
        none
    Example:
         my $outref =NodeUtils->runrmccmd('lsrsrc-api', "-i -D ':|:'", $where);
    Comments:
        When $nodelist_ref is not null, break it up into smaller slices
		and run RMC commands seperately for each slice. 
		Otherwise just run RMC commands with the arguments passed in.
=cut
#--------------------------------------------------------------------------------
sub runrmccmd
{
  my ($class, $rmccmd, $options, $select, $exitcode, $nodelist_ref) = @_;

  my @nodelist;
  my $return_ref = [];

  if (!defined($exitcode))
  {
    $exitcode = -2;
  }
	
  if(! grep /usr\/bin/, $rmccmd)
  {
    # add absolute path
    $rmccmd = "/usr/bin/$rmccmd";
  }

  if ($nodelist_ref)
  {
    # check whether to break up nodelist for better scalability.
    @nodelist = @$nodelist_ref;
    my $divide = 500;    # max number of nodes for each division
    my @sublist;
    my @newarray;
    my ($start_index, $end_index, $nodestring);

    my $count = 0;
    my $times = int(scalar(@nodelist) / $divide);
    while ($count <= $times)
    {
      $start_index = $count * $divide;
      $end_index   =
         ((scalar(@nodelist) - 1) < (($count + 1) * $divide - 1))
          ? (scalar(@nodelist) - 1)
          : (($count + 1) * $divide - 1);
      @sublist  = @nodelist[$start_index .. $end_index];
      @newarray = ();
      foreach my $node (@sublist)
      {
        my @vals = split ',|\s', $node;
        push @newarray, @vals;
      }
      $nodestring = join("','", @newarray);

      # replace the pattern in select string with the broken up node string
      my $select_new = $select;
      $select_new =~ s/XXX/$nodestring/;
      my $cmd = "$rmccmd $options $select_new";
      my $outref = NodeUtils->runcmd($cmd, $exitcode, 1);
      push @$return_ref, @$outref;
      $count++;
    }
  }
  else
  {
    my $cmd = "$rmccmd $options $select";
    $return_ref =  NodeUtils->runcmd($cmd, $exitcode, 1);
  }

  # returns a reference to the output array
  return $return_ref;
}
#--------------------------------------------------------------------------------
=head3    quote
    Quote a string, taking into account embedded quotes.  This function is most
    useful when passing string through the shell to another cmd.  It handles one
    level of embedded double quotes, single quotes, and dollar signs.
    Arguments:
        string to quote
    Returns:
        quoted string
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut
#--------------------------------------------------------------------------------
sub quote
{
  my ($class, $str) = @_;

  # if the value has imbedded double quotes, use single quotes.  If it also has
  # single quotes, escape the double quotes.
  if (!($str =~ /\"/))    # no embedded double quotes
  {
    $str =~ s/\$/\\\$/sg;    # escape the dollar signs
    $str =~ s/\`/\\\`/sg;
    $str = qq("$str");
  }
  elsif (!($str =~ /\'/))
  {
    $str = qq('$str');
  }       # no embedded single quotes
  else    # has both embedded double and single quotes
  {
    # Escape the double quotes.  (Escaping single quotes does not seem to work
    # in the shells.)
    $str =~ s/\"/\\\"/sg;    #" this comment helps formating
    $str =~ s/\$/\\\$/sg;    # escape the dollar signs
    $str =~ s/\`/\\\`/sg;
    $str = qq("$str");
  }
}


#--------------------------------------------------------------------------------
=head3    filterRmcApiOutput
    filter RMC Api Output
    Arguments:
        RMC command
        Output reference
    Returns:
        none
    Globals:
        none
    Error:
        none
    Example:
          NodeUtils->filterRmcApiOutput($cmd, $outref);
    Comments:
        The error msgs from the RPM -api cmds are pretty messy.
        This routine cleans them up a little bit.
=cut
#--------------------------------------------------------------------------------
sub filterRmcApiOutput
{
  my ($class, $cmd, $outref) = @_;
  if ($::VERBOSE || !($cmd =~ m|^/usr/bin/\S+-api |))  {
    return;
  }    # give as much info as possible, if verbose

  # Figure out the output delimiter
  my ($d) = $cmd =~ / -D\s+(\S+)/;
  if (length($d))  {
    $d =~ s/^(\'|\")(.*)(\"|\')$/$2/;    # remove any surrounding quotes
    # escape any chars perl pattern matching would intepret as special chars
    $d =~ s/([\|\^\*\+\?\.])/\\$1/g;
  }
  else
  {
    $d = '::';
  }    # this is the default output delimiter for the -api cmds
  $$outref[0] =~ s/^ERROR${d}.*${d}.*${d}.*${d}.*${d}//;
}


#--------------------------------------------------------------------------------
=head3    readFile
    Read a file and return its content.
    Arguments:
        filename
    Returns:
        file contents or undef
    Globals:
        none
    Error:
        undef
    Comments:
        none
=cut
#--------------------------------------------------------------------------------
sub readFile
{
  my ($class, $filename) = @_;
  open(FILE, "<$filename") or return undef;
  my @contents;
  @contents = <FILE>;
  close(FILE);
  if (wantarray) { return @contents; }
  else { return join('', @contents); }
}

#--------------------------------------------------------------------------------

=head3  touchFile
    Arguments: $filename, $donotExit
    Returns: non zero return code indicates error
    Example:  NodeUtils->touchFile("/var/opt/csm/touch");
=cut

#--------------------------------------------------------------------------------
sub touchFile
{
  my ($class, $filename, $donotExit) = @_;
  my $fh;
  my $rc = 0;
  if (!-e $filename)  {   
    #if the file doesn't exist we need to open and close it
    open($fh, ">>$filename") or $rc++;
    if ($rc > 0 && !$donotExit)    {
      print "Touch of file $filename failed with: $!\n";
      return $rc;
    }
    close($fh) or $rc++;
  }
  else  { 
    #if the file does exist we can just utime it (see the perlfunc man page entry on utime)
    my $now = time;
    utime($now, $now, $filename);
  }
  if ($rc > 0 && !$donotExit)  {
      print "Touch of file $filename failed with: $!\n";
    return $rc;
  }
  return 0;
}
