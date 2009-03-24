#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Utils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use Socket;
use strict;
require xCAT::Schema;
require Data::Dumper;
require xCAT::NodeRange;
require DBI;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(genpassword);

#--------------------------------------------------------------------------------

=head1    xCAT::Utils

=head2    Package Description

This program module file, is a set of utilities used by xCAT commands.

=cut

#-------------------------------------------------------------

=head3 genUUID
    Returns an RFC 4122 compliant UUIDv4
    Arguments:
        none
    Returns:
        string representation of a UUDv4, 
            for example: f16196d1-7534-41c1-a0ae-a9633b030583

=cut

#-------------------------------------------------------
sub genUUID
{

    #UUIDv4 has 6 fixed bits and 122 random bits
    #Though a UUID of this form is not guaranteed to be unique absolutely,
    #the chances of a cluster the size of the entire internet generating
    #two identical UUIDs is 4 in 10 octillion.
    srand();    #Many note this as bad practice, however, forks are going on..
    my $uuid;
    $uuid =
      sprintf("%08x-%04x-4%03x-",
              int(rand(4294967295)),
              int(rand(65535)), int(rand(4095)));
    my $num = 32768;
    $num = $num | int(rand(16383));
    $uuid .=
      sprintf("%04x-%04x%08x", $num, int(rand(65535)), int(rand(4294967295)));
    return $uuid;
}

#--------------------------------------------------------------------------------

=head3    genpassword
    returns a random string of specified length or 8 if none given
    Arguments:
      length of string requested
    Returns:
      string of requested length or 8
    Globals:
        none
    Error:
        none
    Example:
         my $salt = genpassword(8);
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub genpassword
{

    #Generate a pseudo-random password of specified length
    my $length = shift;
    unless ($length) { $length = 8; }
    my $password   = '';
    my $characters =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890';
    srand;    #have to reseed, rand is not rand otherwise
    while (length($password) < $length)
    {
        $password .= substr($characters, int(rand 63), 1);
    }
    return $password;
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
         if (defined($$opthashref{'WhereStr'})) {
            $where = xCAT::Utils->quote($$opthashref{'WhereStr'});
        }
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

#-------------------------------------------------------------------------------

=head3    isAIX
    returns 1 if localHost is AIX
    Arguments:
        none
    Returns:
        1 - localHost is AIX
        0 - localHost is some other platform
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isAIX()) { blah; }
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isAIX
{
    if ($^O =~ /^aix/i) { return 1; }
    else { return 0; }
}

#-------------------------------------------------------------------------------

=head3	xfork
	forks, safely coping with open database handles
	Argumens:
		none
	Returns:
		same as fork
=cut

#-------------------------------------------------------------------------------

sub xfork
{
    my $rc = fork;
    unless (defined($rc))
    {
        return $rc;
    }
    unless ($rc)
    {

        #my %drivers = DBI->installed_drivers;
        foreach (values %{$::XCAT_DBHS})
        {    #@{$drh->{ChildHandles}}) {
            $_->{InactiveDestroy} = 1;
            undef $_;
        }
    }
    return $rc;
}

sub close_all_dbhs
{
    foreach (values %{$::XCAT_DBHS})
    {        #@{$drh->{ChildHandles}}) {
        $_->disconnect;
        undef $_;
    }
}

#-------------------------------------------------------------------------------

=head3    isLinux
    returns 1 if localHost is Linux
    Arguments:
        none
    Returns:
        1 - localHost is Linux
        0 - localHost is some other platform
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isLinux()) { blah; }
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isLinux
{
    if ($^O =~ /^linux/i) { return 1; }
    else { return 0; }
}

#-------------------------------------------------------------------------------

=head3   Version 
    Arguments:
        Optional 'short' string to request only the version;
    Returns:
       xcat Version number 
    Globals:
        none
    Error:
        none
    Example:
         $version=xCAT::Utils->Version();
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub Version
{

    #The following tag tells the build script where to append build info
    my $version = shift;
    if ($version eq 'short')
    {
        $version = ''    #XCATVERSIONSUBHERE ;
    }
    else
    {
        $version = 'Version '    #XCATVERSIONSUBHERE #XCATSVNBUILDSUBHERE ;
    }
    return $version;

}

#-------------------------------------------------------------------------------

=head3    make_node_list_file

        Makes a node list file.

        Arguments:
                (\@list_of_nodes) - reference to an arrary of nodes.
        Returns:
                $file_name and sets the global var: $::NODE_LIST_FILE
        Globals:
                the ENV vars: DSH_LIST,  RPOWER_LIST,  RCONSOLE_LIST
        Error:
                None documented
        Example:
                xCAT::Utils->make_node_list_file(\@nodelist);

        Comments:
                IMPORTANT:
          Make sure to cleanup afterwards with:

                         xCAT::Utils->close_delete_file($file_handle, $file_name)

=cut

#--------------------------------------------------------------------------------

sub make_node_list_file
{
    my ($class, $ref_node_list) = @_;
    my @node_list = @$ref_node_list;
    srand(time | $$);    #random number generator start

    my $file = "/tmp/csm_$$";
    while (-e $file)
    {
        $file = xCAT::Utils->CreateRandomName($file);
    }

    open($::NODE_LIST_FILE, ">$file")
      or xCAT::MsgUtils->message("E", "Cannot write to file: $file\n");
    foreach my $node (@node_list)
    {
        print $::NODE_LIST_FILE "$node\n";
    }
    return $file;
}

#--------------------------------------------------------------------------------

=head3    CreateRandomName

		Create a randome file name.
				Arguments:
	  	    		Prefix of name
				Returns:
					Prefix with 8 random letters appended
				Error:
				none
				Example:
				$file = xCAT::Utils->CreateRandomName($namePrefix);
				Comments:
					None
																				=cut

#-------------------------------------------------------------------------------
sub CreateRandomName
{
my ($class, $name) = @_;

my $nI;
for ($nI = 0 ; $nI < 8 ; $nI++)
{
   my $char = ('a' .. 'z', 'A' .. 'Z')[int(rand(52)) + 1];
   $name .= $char;
}
	$name;
}

#-----------------------------------------------------------------------

=head3
close_delete_file.

	Arguments:
		file handle,filename
	Returns:
	    none
	Globals:
		none
	Error:
		undef
	Example:
	   xCAT::Utils->close_delete_file($file_handle, $file_name);
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub close_delete_file
{
    my ($class, $file_handle, $file_name) = @_;
    close $file_handle;

    unlink($file_name);
}

#-----------------------------------------------------------------------

=head3
 list_all_nodes

	Arguments:

	Returns:
	    an array of all define nodes from the nodelist table
	Globals:
		none
	Error:
		undef
	Example:
	   @nodes=xCAT::Utils->list_all_nodes;
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub list_all_nodes
{
    my @nodes;
    my @nodelist;
    my $nodelisttab;
    if ($nodelisttab = xCAT::Table->new("nodelist"))
    {
        my @attribs = ("node");
        @nodes = $nodelisttab->getAllAttribs(@attribs);
        foreach my $node (@nodes)
        {
            push @nodelist, $node->{node};
        }
    }
    else
    {
        xCAT::MsgUtils->message("E", " Could not read the nodelist table\n");
    }
    return @nodelist;
}

#-----------------------------------------------------------------------

=head3
 list_all_nodegroups

	Arguments:

	Returns:
	    an array of all define node groups from the nodelist table
	Globals:
		none
	Error:
		undef
	Example:
	   @nodegrps=xCAT::Utils->list_all_nodegroups;
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub list_all_node_groups
{
    my @grouplist;
    my @grouplist2;
    my @distinctgroups;
    my $nodelisttab;
    if ($nodelisttab = xCAT::Table->new("nodelist"))
    {
        my @attribs = ("groups");
        @grouplist = $nodelisttab->getAllAttribs(@attribs);

        # build a distinct list of unique group names
        foreach my $group (@grouplist)
        {
            my $gnames = $group->{groups};
            my @groupnames = split ",", $gnames;
            foreach my $groupname (@groupnames)
            {
                if (!grep(/$groupname/, @distinctgroups))
                {    # not already in list
                    push @distinctgroups, $groupname;
                }
            }
        }
    }
    else
    {
        xCAT::MsgUtils->message("E", " Could not read the nodelist table\n");
    }
    $nodelisttab->close;
    return @distinctgroups;
}

#-----------------------------------------------------------------------

=head3
 list_nodes_in_nodegroup

	Arguments:  nodegroup

	Returns:
	    an array of all define nodes in the node group

	Globals:
		none
	Error:
		undef
	Example:
	   @nodes=xCAT::Utils->list_nodes_in_nodegroup($group);
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub list_nodes_in_nodegroups
{
    my ($class, $group) = @_;
    my $req = {};
    $req->{noderange}->[0] = $group;
    my @nodes = xCAT::NodeRange::noderange($req->{noderange}->[0]);
    return @nodes;
}

#-----------------------------------------------------------------------

=head3
  get_site_attribute

	Arguments:

	Returns:
	    The value of the attribute requested from the site table
	Globals:
		none
	Error:
		undef
	Example:
	   @attr=xCAT::Utils->get_site_attribute($attribute);
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub get_site_attribute
{
    my ($class, $attr) = @_;
    my $values;

    my $sitetab = xCAT::Table->new('site');
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => $attr}, 'value');
        if ($ref)
        {
            $values = $ref->{value};
        }
    }
    else
    {
        xCAT::MsgUtils->message("E", " Could not read the site table\n");

    }
    $sitetab->close;
    return $values;
}

#-----------------------------------------------------------------------

=head3
  add_cron_job
     This function adds a new cron job.
	Arguments:
      	    job--- string in the crontab job format.
	Returns:
	    (code, message)
	Globals:
		none
	Error:
		undef
	Example:
	    xCAT::Utils->add_cron_job("*/5 * * * * /usr/bin/myjob");
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub add_cron_job
{
    my $newentry = shift;
    if ($newentry =~ /xCAT::Utils/)
    {
        $newentry = shift;
    }

    #read the cron tab entries
    my @tabs    = `/usr/bin/crontab -l 2>/dev/null`;
    my @newtabs = ();
    foreach (@tabs)
    {
        chomp($_);

        # stop adding if it's already there
        if ($_ eq $newentry) { return (0, "started"); }

        #skip headers for Linux
        next
          if $_ =~
          m/^\#.+(DO NOT EDIT THIS FILE|\(.+ installed on |Cron version )/;
        push(@newtabs, $_);
    }

    #add new entries to the cron tab
    push(@newtabs, $newentry);
    my $tabname = "";
    if (xCAT::Utils->isLinux()) { $tabname = "-"; }
    open(CRONTAB, "|/usr/bin/crontab $tabname")
      or return (1, "cannot open crontab.");
    foreach (@newtabs) { print CRONTAB $_ . "\n"; }
    close(CRONTAB);

    return (0, "");
}

#-----------------------------------------------------------------------

=head3
  remove_cron_job
     This function removes a new cron job.
	Arguments:
      	    job--- a substring that is contained in a crontab entry.
                  (use crontab -l to see all the job entries.)
	Returns:
	    (code, message)
	Globals:
		none
	Error:
		undef
	Example:
	    xCAT::Utils->remove_cron_job("/usr/bin/myjob");
            This will remove any cron job that contains this string.
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub remove_cron_job
{
    my $job = shift;
    if ($job =~ /xCAT::Utils/)
    {
        $job = shift;
    }

    #read the cron tab entries and remove the one that contains $job
    my @tabs    = `/usr/bin/crontab -l 2>/dev/null`;
    my @newtabs = ();
    foreach (@tabs)
    {
        chomp($_);

        # stop adding if it's already there
        next if index($_, $job, 0) >= 0;

        #skip headers for Linux
        next
          if $_ =~
          m/^\#.+(DO NOT EDIT THIS FILE|\(.+ installed on |Cron version )/;
        push(@newtabs, $_);
    }

    #refresh the cron
    my $tabname = "";
    if (xCAT::Utils->isLinux()) { $tabname = "-"; }
    open(CRONTAB, "|/usr/bin/crontab $tabname")
      or return (1, "cannot open crontab.");
    foreach (@newtabs) { print CRONTAB $_ . "\n"; }
    close(CRONTAB);

    return (0, "");
}

#-------------------------------------------------------------------------------

=head3    runcmd
   Run the given cmd and return the output in an array (already chopped).
   Alternately, if this function is used in a scalar context, the output
   is joined into a single string with the newlines separating the lines.

   Arguments:
	   command, exitcode and reference to output
   Returns:
	   see below
   Globals:
	   $::RUNCMD_RC  , $::CALLBACK
   Error:
      Normally, if there is an error running the cmd,it will display the
		error and exit with the cmds exit code, unless exitcode
		is given one of the following values:
            0:     display error msg, DO NOT exit on error, but set
					$::RUNCMD_RC to the exit code.
			-1:     DO NOT display error msg and DO NOT exit on error, but set
				    $::RUNCMD_RC to the exit code.
			-2:    DO the default behavior (display error msg and exit with cmds
				exit code.
             number > 0:    Display error msg and exit with the given code

   Example:
		my $outref = xCAT::Utils->runcmd($cmd, -2, 1);

   Comments:
		   If refoutput is true, then the output will be returned as a
		   reference to an array for efficiency.


=cut

#-------------------------------------------------------------------------------
sub runcmd

{

    my ($class, $cmd, $exitcode, $refoutput) = @_;
    $::RUNCMD_RC = 0;
    if (!$xCAT::Utils::NO_STDERR_REDIRECT)
    {
        if (!($cmd =~ /2>&1$/)) { $cmd .= ' 2>&1'; }

    }
    if ($::VERBOSE)
    {
        xCAT::MsgUtils->message("I", "Running Command: $cmd\n");
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
            my $rsp    = {};
            my $errmsg = '';
            if (xCAT::Utils->isLinux() && $::RUNCMD_RC == 139)
            {
                $errmsg = "Segmentation fault  $errmsg";
            }
            else
            {
                $errmsg = join('', @$outref);
                chomp $errmsg;

            }
            if ($::CALLBACK)
            {
                $rsp->{data}->[0] =
                  "Command failed: $cmd. Error message: $errmsg.\n";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

            }
            else
            {
                xCAT::MsgUtils->message("E",
                             "Command failed: $cmd. Error message: $errmsg.\n");
            }
            $xCAT::Utils::errno = 29;
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

#-------------------------------------------------------------------------------

=head3    runxcmd
   Run the given xCAT cmd and return the output in an array.
   Alternately, if this function is used in a scalar context, the output
   is joined into a single string with newlines separating the lines.

   Arguments:
	   command - string with following format:
			<xCAT cmd name> <comma-delimited nodelist> <cmd args>
			where the xCAT cmd name is as reqistered in the plugins,
				  the nodelist is already flattened and verified
				  the remainder of the string is passed as args.
				  The nodelist may be set to the string "NO_NODE_RANGE" to
				  not pass in any nodes to the command.
	OR
	   command - request hash

	   reference to xCAT daemon sub_req routine

	   exitcode  

	   reference to output

   Returns:
	   see below
   Globals:
	   $::RUNCMD_RC  , $::CALLBACK
   Error:
	  Cannot determine error code. If ERROR data set in response
	  hash, $::RUNCMD_RC will be set to 1.
      Normally, if there is an error running the cmd,it will display the
		error and exit with the cmds exit code, unless exitcode
		is given one of the following values:
            0:     display error msg, DO NOT exit on error, but set
					$::RUNCMD_RC to the exit code.
			-1:     DO NOT display error msg and DO NOT exit on error, but set
				    $::RUNCMD_RC to the exit code.
			-2:    DO the default behavior (display error msg and exit with cmds
				exit code.
             number > 0:    Display error msg and exit with the given code

   Example:
		my $outref = xCAT::Utils->runxcmd($cmd,$sub_req, -2, 1);

   Comments:
		   If refoutput is true, then the output will be returned as a
		   reference to an array for efficiency.

		   Do not use the scalar string input for xdsh unless you are running
		   a simple single-word command.  When building your request hash,
		   the entire command string xdsh runs needs to be a single entry
		   in the arg array.


=cut

#-------------------------------------------------------------------------------
sub runxcmd

{

    my $save_CALLBACK = $::CALLBACK;
    my ($class, $cmd, $subreq, $exitcode, $refoutput) = @_;
    $::RUNCMD_RC = 0;
    if ($::VERBOSE)
    {
        if (ref($cmd) eq "HASH")
        {
            xCAT::MsgUtils->message("I",
                  "Running internal xCAT command: $cmd->{command}->[0] ... \n");
        }
        else
        {
            xCAT::MsgUtils->message("I", "Running Command: $cmd\n");
        }
    }
    $::xcmd_outref = [];
    my $req;
    if (ref($cmd) eq "HASH")
    {
        $req = $cmd;
    }
    else
    {    # assume scalar, build request hash the way we do in xcatclient
        my @cmdargs = split(/\s+/, $cmd);
        my $cmdname = shift(@cmdargs);
        $req->{command} = [$cmdname];
        my $arg = shift(@cmdargs);
        while ($arg =~ /^-/)
        {
            push(@{$req->{arg}}, $arg);
            $arg = shift(@cmdargs);
        }
        if ($arg ne "NO_NODE_RANGE")
        {
            my @nodes = split(",", $arg);
            $req->{node} = \@nodes;
        }
        push(@{$req->{arg}}, @cmdargs);
    }
    $subreq->($req, \&runxcmd_output);
    $::CALLBACK = $save_CALLBACK;    # in case the subreq call changed it
    my $outref = $::xcmd_outref;
    if ($::RUNCMD_RC)
    {
        my $displayerror = 1;
        my $rc;
        if (defined($exitcode) && length($exitcode) && $exitcode != -2)
        {
            if ($exitcode > 0)
            {
                $rc = $exitcode;
            }                        # if not zero, exit with specified code
            elsif ($exitcode <= 0)
            {
                $rc = '';            # if zero or negative, do not exit
                if ($exitcode < 0) { $displayerror = 0; }
            }
        }
        else
        {
            $rc = $::RUNCMD_RC;
        }    # if exitcode not specified, use cmd exit code
        if ($displayerror)
        {
            my $rsp = {};
            my $errmsg = join('', @$outref);
            chomp $errmsg;
            my $displaycmd = $cmd;
            if (ref($cmd) eq "HASH")
            {
                $displaycmd = $cmd->{command}->[0];
            }
            if ($::CALLBACK)
            {
                $rsp->{data}->[0] =
                  "Command failed: $displaycmd. Error message: $errmsg.\n";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            }
            else
            {
                xCAT::MsgUtils->message("E",
                      "Command failed: $displaycmd. Error message: $errmsg.\n");
            }
            $xCAT::Utils::errno = 29;
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

# runxcmd_output -- Internal subroutine for runxcmd to capture the output
#	from the xCAT daemon subrequest call
#	Note - only basic info, data, and error responses returned
#	For more complex node or other return structures, you will need
#	to write your own wrapper to subreq instead of using runxcmd.
sub runxcmd_output
{
    my $resp = shift;
    if (defined($resp->{info}))
    {
        push @$::xcmd_outref, @{$resp->{info}};
    }
    if (defined($resp->{sinfo}))
    {
        push @$::xcmd_outref, @{$resp->{sinfo}};
    }
    if (defined($resp->{data}))
    {
        push @$::xcmd_outref, @{$resp->{data}};
    }
    if (defined($resp->{node}))
    {
        my $node = $resp->{node}->[0];
        my $desc = $node->{name}->[0];
        if (defined($node->{data}))
        {
            if (ref(\($node->{data}->[0])) eq 'SCALAR')
            {
                $desc = $desc . ": " . $node->{data}->[0];
            }
            else
            {
                if (defined($node->{data}->[0]->{desc}))
                {
                    $desc = $desc . ": " . $node->{data}->[0]->{desc}->[0];
                }
                if (defined($node->{data}->[0]->{contents}))
                {
                    $desc = "$desc: " . $node->{data}->[0]->{contents}->[0];
                }
            }
        }
        push @$::xcmd_outref, $desc;
    }
    if (defined($resp->{error}))
    {
        push @$::xcmd_outref, @{$resp->{error}};
        $::RUNCMD_RC = 1;
    }
    if (defined($resp->{errorcode}))
    {
        if (ref($resp->{errorcode}) eq 'ARRAY')
        {
            foreach my $ecode (@{$resp->{errorcode}})
            {
                $::RUNCMD_RC |= $ecode;
            }
        }
        else
        {

            # assume it is a non-reference scalar
            $::RUNCMD_RC |= $resp->{errorcode};
        }
    }

    #  		my $i=0;
    #	    foreach my $line ($resp->{info}->[$i]) {
    #	      push (@dshresult, $line);
    #	      $i++;
    #	    }
    return 0;
}

#--------------------------------------------------------------------------------

=head3    getHomeDir

        Get the path the  user home directory from /etc/passwd.

        Arguments:
                none
        Returns:
                path to  user home directory.
        Globals:
                none
        Error:
                none
        Example:
                $myHome = xCAT::Utils->getHomeDir();
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub getHomeDir
{
    my ($class, $username) = @_;
    my @user = split ':', (`/bin/grep ^$username /etc/passwd 2>&1`);
    my $home = $user[5];
    return $home;
}

#--------------------------------------------------------------------------------

=head3   setupSSH

        Generates if needed and Transfers the ssh keys 
		fOr a userid to setup ssh to the input nodes.

        Arguments:
               Array of nodes
        Returns:

        Env Variables: $DSH_FROM_USERID,  $DSH_TO_USERID, $DSH_REMOTE_PASSWORD
          the ssh keys are transferred from the $DSH_FROM_USERID to the $DSH_TO_USERID
          on the node(s).  The DSH_REMOTE_PASSWORD and the DSH_FROM_USERID 
               must be obtained by
		         the calling script or from the xdsh client

        Globals:
              $::XCATROOT  ,  $::CALLBACK
        Error:
             0=good,  1=error
        Example:
                xCAT::Utils->setupSSH(@target_nodes);
        Comments:
			Does not setup known_hosts.  Assumes automatically
			setup by SSH  ( ssh config option StrictHostKeyChecking no should
			   be set in the ssh config file).

=cut

#--------------------------------------------------------------------------------
sub setupSSH
{
    my ($class, $ref_nodes) = @_;
    my @nodes    = $ref_nodes;
    my @badnodes = ();
    my $n_str    = join ',', @nodes;
    my $SSHdir   = "/install/postscripts/_ssh";
    if (!($ENV{'DSH_REMOTE_PASSWORD'}))
    {
        my $rsp = ();
        $rsp->{data}->[0] =
          "User password for the ssh key exchange has not been input. xdsh -K cannot complete.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        return;

    }

    # setup who the keys are coming from and who they are going to
    my $from_userid;
    my $to_userid;
    if (!($ENV{'DSH_FROM_USERID'}))
    {
        my $rsp = ();
        $rsp->{data}->[0] =
          "DSH From Userid  has not been input. xdsh -K cannot complete.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        return;

    }
    else
    {
        $from_userid = $ENV{'DSH_FROM_USERID'};
    }
    if (!($ENV{'DSH_TO_USERID'}))
    {
        my $rsp = ();
        $rsp->{data}->[0] =
          "DSH to Userid  has not been input. xdsh -K cannot complete.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        return;

    }
    else
    {
        $to_userid = $ENV{'DSH_TO_USERID'};
    }

    if ($::XCATROOT)
    {
        $::REMOTESHELL_EXPECT = "$::XCATROOT/sbin/remoteshell.expect";
    }
    else
    {
        $::REMOTESHELL_EXPECT = "/opt/xcat/sbin/remoteshell.expect";
    }
    $::REMOTE_SHELL = "/usr/bin/ssh";

    # make the directory to hold keys to transfer to the nodes
    if (!-d $SSHdir)
    {
        mkdir("/install",                  0755);
        mkdir("/install/postscripts",      0755);
        mkdir("/install/postscripts/_ssh", 0755);
    }

    # Generate the keys, if they do not already exist
    my $rsp = {};

    # Get the home directory
    my $home = xCAT::Utils->getHomeDir($from_userid);
    $ENV{'DSH_FROM_USERID_HOME'} = $home;

    # generates new keys, if they do not already exist
    xCAT::Utils->runcmd("$::REMOTESHELL_EXPECT -k", 0);
    if ($::RUNCMD_RC != 0)
    {    # error
        $rsp->{data}->[0] = "remoteshell.expect failed generating keys.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

    }

    #  build the perl copy script in $HOME/.ssh/copy.perl
    #open(FILE, ">$home/.ssh/copy.perl")
    #  or die "cannot open file $home/.ssh/copy.perl\n";
    #print FILE "#!/usr/bin/perl
    #my (\$name,\$passwd,\$uid,\$gid,\$quota,\$comment,\$gcos,\$dir,\$shell,\$expire) = getpwnam($to_userid);
    #my \$home = \$dir;
    #umask(0077);
    #\$dest_dir = \"\$home/.ssh/\";
    #if (! -d \"\$dest_dir\" ) {
    # create a local directory
    #   \$cmd = \"mkdir -p \$dest_dir\";
    #  system(\"\$cmd\");
    # chmod 0700, \$dest_dir;
    #}
    #`cat /tmp/$to_userid/.ssh/authorized_keys >> \$home/.ssh/authorized_keys 2>&1`;
    #`cat /tmp/$to_userid/.ssh/authorized_keys2 >> \$home/.ssh/authorized_keys2 2>&1`;
    #`cp /tmp/$to_userid/.ssh/id_rsa  \$home/.ssh/id_rsa 2>&1`;
    #`cp /tmp/$to_userid/.ssh/id_dsa  \$home/.ssh/id_dsa 2>&1`;
    #`chmod 0600 \$home/.ssh/id_* 2>&1`;
    #`rm -f /tmp/$to_userid/.ssh/* 2>&1`;
    #rmdir(\"/tmp/$to_userid/.ssh\");
    #rmdir(\"/tmp/$to_userid\");";
    #   close FILE;
    #   chmod 0744, "$home/.ssh/copy.perl";

    #  Replace the perl script with a shell script
    #  Shell is needed because the nodes may not have Perl installed
    open(FILE, ">$home/.ssh/copy.sh")
      or die "cannot open file $home/.ssh/copy.sh\n";
    print FILE "#!/bin/sh
umask 0077
home=`egrep \"^$to_userid\" /etc/passwd | cut -f6 -d :`
dest_dir=\"\$home/.ssh\"
mkdir -p \$dest_dir
cat /tmp/$to_userid/.ssh/authorized_keys >> \$home/.ssh/authorized_keys 2>&1
cat /tmp/$to_userid/.ssh/authorized_keys2 >> \$home/.ssh/authorized_keys2 2>&1
cp /tmp/$to_userid/.ssh/id_rsa  \$home/.ssh/id_rsa 2>&1
cp /tmp/$to_userid/.ssh/id_dsa  \$home/.ssh/id_dsa 2>&1
chmod 0600 \$home/.ssh/id_* 2>&1
rm -f /tmp/$to_userid/.ssh/* 2>&1
rmdir \"/tmp/$to_userid/.ssh\"
rmdir \"/tmp/$to_userid\"";

    close FILE;
    chmod 0744, "$home/.ssh/copy.sh";

    if (xCAT::Utils->isMN())
    {    # if on Management Node
        if ($from_userid eq "root")
        {
            my $rc = xCAT::Utils->cpSSHFiles($SSHdir);
            if ($rc != 0)
            {    # error
                $rsp->{data}->[0] = "Error running cpSSHFiles.\n";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                return 1;

            }

            # copy the copy install file to the install directory, if from and
            # to userid are root
            if ($to_userid eq "root")
            {

                my $cmd = " cp $home/.ssh/copy.sh $SSHdir/copy.sh";
                xCAT::Utils->runcmd($cmd, 0);
                my $rsp = {};
                if ($::RUNCMD_RC != 0)
                {
                    $rsp->{data}->[0] = "$cmd failed.\n";
                    xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                    return (1);

                }
            }
        }
    }

    # send the keys to the nodes   for root or some other id
    #
    my $cmd = "$::REMOTESHELL_EXPECT -s $n_str";
    my $rc  = system("$cmd") >> 8;
    if ($rc)
    {
        $rsp->{data}->[0] = "remoteshell.expect failed sending keys.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

    }

    #  Remove $home/.ssh/authorized_keys*
    #  Easy to remote this code, if we want
    #  The MN to be able to ssh to itself
    if (xCAT::Utils->isMN())
    {
        $cmd = "rm $home/.ssh/authorized_keys*";
        xCAT::Utils->runcmd($cmd, 0);
        my $rsp = {};
        if ($::RUNCMD_RC != 0)
        {
            $rsp->{data}->[0] = "$cmd failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            return (1);

        }
    }

    # must always check to see if worked, run test
    foreach my $n (@nodes)
    {
        my $cmd    = "$::REMOTESHELL_EXPECT -t $::REMOTE_SHELL $n ";
        my @cmdout = `$cmd 2>&1`;
        chomp(@cmdout);    # take the newline off
        my $rc = $? >> 8;
        if ($rc)
        {
            push @badnodes, $n;
        }
    }

    if (@badnodes)
    {
        my $nstring = join ',', @badnodes;
        $rsp->{data}->[0] =
          "SSH setup failed for the following nodes: $nstring.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return @badnodes;
    }
    else
    {
        $rsp->{data}->[0] = "$::REMOTE_SHELL setup is complete.";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }
}

#--------------------------------------------------------------------------------

=head3    cpSSHFiles

           Builds authorized_keyfiles from the keys only run on Management Node
           and for root and puts them in /install/postscripts/_ssh 

        Arguments:
               directory path
        Returns:

        Globals:
              $::CALLBACK
        Error:

        Example:
                xCAT::Utils->cpSSHFiles;

        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub cpSSHFiles
{
    my ($class, $SSHdir) = @_;
    my ($cmd, $rc);
    my $rsp = {};
    if ($::VERBOSE)
    {
        $rsp->{data}->[0] = "Copying SSH Keys";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
    }
    my $home = xCAT::Utils->getHomeDir("root");

    my $authorized_keys  = "$SSHdir/authorized_keys";
    my $authorized_keys2 = "$SSHdir/authorized_keys2";
    if (   !(-e "$home/.ssh/identity.pub")
        || !(-e "$home/.ssh/id_rsa.pub")
        || !(-e "$home/.ssh/id_dsa.pub"))
    {
        return 1;
    }
    $cmd = " cp $home/.ssh/identity.pub $authorized_keys";
    xCAT::Utils->runcmd($cmd, 0);
    my $rsp = {};
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }
    $cmd = " cp $home/.ssh/identity.pub $home/.ssh/authorized_keys";
    xCAT::Utils->runcmd($cmd, 0);
    my $rsp = {};
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        chmod 0600, "$home/.ssh/authorized_keys";
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    $cmd = "cp $home/.ssh/id_rsa.pub $authorized_keys2";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }
    $cmd = "cp $home/.ssh/id_rsa.pub $home/.ssh/authorized_keys2";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        chmod 0600, "$home/.ssh/authorized_keys2";
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    my $rsp = {};
    $cmd = "cat $home/.ssh/id_dsa.pub >> $authorized_keys2";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    if (!(-e "$authorized_keys") || !(-e "$authorized_keys2"))
    {
        return 1;
    }
    return (0);
}

#-------------------------------------------------------------------------------

=head3    isServiceNode
	checks for the /etc/xCATSN file

    Arguments:
        none
    Returns:
        1 - localHost is ServiceNode
        0 - localHost is not ServiceNode
    Globals:
        none
    Error:
        none
    Example:
	     %::XCATMasterPort defined in the caller.
         $return=(xCAT::Utils->isServiceNode())
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isServiceNode
{
    my $value;
    if (-e "/etc/xCATSN")
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#-------------------------------------------------------------------------------

=head3    isMN
	checks for the /etc/xCATMN file , if it exists it is a Management Server

    Arguments:
        none
    Returns:
        1 - localHost is Management Node 
        0 - localHost is not a Management Node 
    Globals:
        none
    Error:
        none
    Example:
         $return=(xCAT::Utils->isMN())
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isMN
{
    my $value;
    if (-e "/etc/xCATMN")
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#-------------------------------------------------------------------------------

=head3   classful_networks_for_net_and_mask

    Arguments:
        network and mask
    Returns:
        a list of classful subnets that constitute the entire potentially classless arguments
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub classful_networks_for_net_and_mask
{
    my $network    = shift;
    my $mask       = shift;
    my $given_mask = 0;
    if ($mask =~ /\./)
    {
        $given_mask = 1;
        my $masknumber = unpack("N", inet_aton($mask));
        $mask = 32;
        until ($masknumber % 2)
        {
            $masknumber = $masknumber >> 1;
            $mask--;
        }
    }

    my @results;
    my $bitstoeven = (8 - ($mask % 8));
    if ($bitstoeven eq 8) { $bitstoeven = 0; }
    my $resultmask = $mask + $bitstoeven;
    if ($given_mask)
    {
        $resultmask =
          inet_ntoa(pack("N", (2**$resultmask - 1) << (32 - $resultmask)));
    }
    push @results, $resultmask;

    my $padbits  = (32 - ($bitstoeven + $mask));
    my $numchars = int(($mask + $bitstoeven) / 4);
    my $curmask  = 2**$mask - 1 << (32 - $mask);
    my $nown     = unpack("N", inet_aton($network));
    $nown = $nown & $curmask;
    my $highn = $nown + ((2**$bitstoeven - 1) << (32 - $mask - $bitstoeven));

    while ($nown <= $highn)
    {
        push @results, inet_ntoa(pack("N", $nown));

        #$rethash->{substr($nowhex, 0, $numchars)} = $network;
        $nown += 1 << (32 - $mask - $bitstoeven);
    }
    return @results;
}

#-------------------------------------------------------------------------------

=head3   my_hexnets

    Arguments:
        none
    Returns:
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub my_hexnets
{
    my $rethash;
    my @nets = split /\n/, `/sbin/ip addr`;
    foreach (@nets)
    {
        my @elems = split /\s+/;
        unless (/^\s*inet\s/)
        {
            next;
        }
        (my $curnet, my $maskbits) = split /\//, $elems[2];
        my $bitstoeven = (4 - ($maskbits % 4));
        if ($bitstoeven eq 4) { $bitstoeven = 0; }
        my $padbits  = (32 - ($bitstoeven + $maskbits));
        my $numchars = int(($maskbits + $bitstoeven) / 4);
        my $curmask  = 2**$maskbits - 1 << (32 - $maskbits);
        my $nown     = unpack("N", inet_aton($curnet));
        $nown = $nown & $curmask;
        my $highn =
          $nown + ((2**$bitstoeven - 1) << (32 - $maskbits - $bitstoeven));

        while ($nown <= $highn)
        {
            my $nowhex = sprintf("%08x", $nown);
            $rethash->{substr($nowhex, 0, $numchars)} = $curnet;
            $nown += 1 << (32 - $maskbits - $bitstoeven);
        }
    }
    return $rethash;
}

#-------------------------------------------------------------------------------

=head3   my_if_netmap
   Arguments:
      none
   Returns:
      hash of networks to interface names
   Globals:
      none
   Error:
      none
   Comments:
      none
=cut

#-------------------------------------------------------------------------------
sub my_if_netmap
{
    my $net;
    if (scalar(@_))
    {    #called with the other syntax
        $net = shift;
    }
    my @rtable = split /\n/, `netstat -rn`;
    if ($?)
    {
        return "Unable to run netstat, $?";
    }
    my %retmap;
    foreach (@rtable)
    {
        if (/^\D/) { next; }    #skip headers
        if (/^\S+\s+\S+\s+\S+\s+\S*G/)
        {
            next;
        }                       #Skip networks that require gateways to get to
        /^(\S+)\s.*\s(\S+)$/;
        $retmap{$1} = $2;
    }
    return \%retmap;
}

#-------------------------------------------------------------------------------

=head3   my_ip_facing
         Returns my ip address  
         Linux only
    Arguments:
        nodename 
    Returns:
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub my_ip_facing
{
    my $peer = shift;
    if (@_)
    {
        $peer = shift;
    }
    my $noden = unpack("N", inet_aton($peer));
    my @nets = split /\n/, `/sbin/ip addr`;
    foreach (@nets)
    {
        my @elems = split /\s+/;
        unless (/^\s*inet\s/)
        {
            next;
        }
        (my $curnet, my $maskbits) = split /\//, $elems[2];
        my $curmask = 2**$maskbits - 1 << (32 - $maskbits);
        my $curn = unpack("N", inet_aton($curnet));
        if (($noden & $curmask) == ($curn & $curmask))
        {
            return $curnet;
        }
    }
    return undef;
}

#-------------------------------------------------------------------------------

=head3 nodeonmynet - checks to see if node is on the network
    Arguments:
       Node name
    Returns:  1 if node is on the network
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------

sub nodeonmynet
{
    my $nodetocheck = shift;
    if (scalar(@_))
    {
        $nodetocheck = shift;
    }
    unless (inet_aton($nodetocheck))
    {
        return 0;
    }
    my $nodeip = inet_ntoa(inet_aton($nodetocheck));
    unless ($nodeip =~ /\d+\.\d+\.\d+\.\d+/)
    {
        return 0;    #Not supporting IPv6 here IPV6TODO
    }
    my $noden = unpack("N", inet_aton($nodeip));
    my @nets = split /\n/, `/sbin/ip route`;
    foreach (@nets)
    {
        my @elems = split /\s+/;
        unless ($elems[1] =~ /dev/)
        {
            next;
        }
        (my $curnet, my $maskbits) = split /\//, $elems[0];
        my $curmask = 2**$maskbits - 1 << (32 - $maskbits);
        my $curn = unpack("N", inet_aton($curnet));
        if (($noden & $curmask) == $curn)
        {
            return 1;
        }
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3   thishostisnot
    returns  0 if host is not the same
    Arguments:
       hostname
    Returns:
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------

sub thishostisnot
{
    my $comparison = shift;
    if (scalar(@_))
    {
        $comparison = shift;
    }

    my @ips = split /\n/, `/sbin/ip addr`;
    my $comp = inet_aton($comparison);
    if ($comp)
    {
        foreach (@ips)
        {
            if (/^\s*inet/)
            {
                my @ents = split(/\s+/);
                my $ip   = $ents[2];
                $ip =~ s/\/.*//;
                if (inet_aton($ip) eq $comp)
                {
                    return 0;
                }

                #print Dumper(inet_aton($ip));
            }
        }
    }
    return 1;
}

#-------------------------------------------------------------------------------

=head3   GetMasterNodeName
        Reads the database for the Master node name for the input node
    Arguments:
		 Node
    Returns:
        MasterHostName
    Globals:
        none
    Error:
        none
    Example:
         $master=(xCAT::Utils->GetMasterNodeName($node))
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub GetMasterNodeName
{
    my ($class, $node) = @_;
    my $master;
    my $noderestab = xCAT::Table->new('noderes');
    my $typetab    = xCAT::Table->new('nodetype');
    unless ($noderestab and $typetab)
    {
        xCAT::MsgUtils->message('S',
                                "Unable to open noderes or nodetype table.\n");
        return 1;
    }
    my $sitetab = xCAT::Table->new('site');
    (my $et) = $sitetab->getAttribs({key => "master"}, 'value');
    if ($et and $et->{value})
    {
        $master = $et->{value};
    }
    $et = $noderestab->getNodeAttribs($node, ['xcatmaster']);
    if ($et and $et->{'xcatmaster'})
    {
        $master = $et->{'xcatmaster'};
    }
    unless ($master)
    {
        xCAT::MsgUtils->message('S', "Unable to identify master for $node.\n");
        $sitetab->close;
        $noderestab->close;
        $typetab->close;
        return 1;
    }

    $sitetab->close;
    $noderestab->close;
    $typetab->close;
    return $master;
}

#-------------------------------------------------------------------------------

=head3   GetNodeOSARCH
        Reads the database for the OS and Arch of the input Node
    Arguments:
		 Node
    Returns:
        $et->{'os'}
		$et->{'arch'}
    Globals:
        none
    Error:
        none
    Example:
         $master=(xCAT::Utils->GetNodeOSARCH($node))
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub GetNodeOSARCH
{
    my ($class, $node) = @_;
    my $noderestab = xCAT::Table->new('noderes');
    my $typetab    = xCAT::Table->new('nodetype');
    unless ($noderestab and $typetab)
    {
        xCAT::MsgUtils->message('S',
                                "Unable to open noderes or nodetype table.\n");
        return 1;
    }
    my $et = $typetab->getNodeAttribs($node, ['os', 'arch']);
    unless ($et and $et->{'os'} and $et->{'arch'})
    {
        xCAT::MsgUtils->message('S',
                           "No os/arch setting in nodetype table for $node.\n");
        return 1;
    }

    return $et;

}

#-----------------------------------------------------------------------------

=head3 exportDBConfig

  Reads the /etc/xcat/cfgloc file for the DB configuration and exports it
  in $XCATCFG
=cut

#-----------------------------------------------------------------------------
sub exportDBConfig
{

    # export the xcat database configuration
    my $configfile = "/etc/xcat/cfgloc";
    if (!($ENV{'XCATCFG'}))
    {
        if (-e ($configfile))
        {
            open(CFGFILE, "<$configfile")
              or xCAT::MsgUtils->message('S',
                                   "Cannot open $configfile for DB access. \n");
            foreach my $line (<CFGFILE>)
            {
                chop $line;
                my $exp .= $line;

                $ENV{'XCATCFG'} = $exp;
                close CFGFILE;
                last;
            }

        }
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3 readSNInfo

  Read resource, NFS server, Master node, OS an ARCH from the database
  for the service node

  Input: service nodename
  Output: Masternode, OS and ARCH
=cut

#-----------------------------------------------------------------------------
sub readSNInfo
{
    my ($class, $nodename) = @_;
    my $rc = 0;
    my $et;
    my $masternode;
    my $os;
    my $arch;
    $rc = xCAT::Utils->exportDBConfig();
    if ($rc == 0)
    {

        if ($nodename)
        {
            $masternode = xCAT::Utils->GetMasterNodeName($nodename);
            if (!($masternode))
            {
                xCAT::MsgUtils->message('S',
                                   "Could not get Master for node $nodename\n");
                return 1;
            }

            $et = xCAT::Utils->GetNodeOSARCH($nodename);
            if ($et == 1)
            {
                xCAT::MsgUtils->message('S',
                                  "Could not get OS/ARCH for node $nodename\n");
                return 1;
            }
            if (!($et->{'os'} || $et->{'arch'}))
            {
                xCAT::MsgUtils->message('S',
                                  "Could not get OS/ARCH for node $nodename\n");
                return 1;
            }
        }
        $et->{'master'} = $masternode;
        return $et;
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 isServiceReq


  Checks the service node table in the database to see 
  if input Service should be setup on the
  input service node

  Input:servicenodename,ipaddres(s) and hostnames of service node
  Output:
        array of services to setup  for this service node
    Globals:
        $::RUNCMD_RC = 0; good
        $::RUNCMD_RC = 1; error 
    Error:
        none
    Example:
      @servicestosetup=xCAT::Utils->isServiceReq($servicenodename, @serviceip) { blah; }

=cut

#-----------------------------------------------------------------------------
sub isServiceReq
{
    my ($class, $servicenodename, $serviceip) = @_;

    # list of all services from service node table
    # note this must be updated if more services added
    my @services = (
                    "nameserver", "dhcpserver", "tftpserver", "nfsserver",
                    "conserver",  "monserver",  "ldapserver", "ntpserver",
                    "ftpserver"
                    );

    my @ips = @$serviceip;    # list of service node ip addresses and names
    my $rc  = 0;

    $rc = xCAT::Utils->exportDBConfig();    # export DB env
    if ($rc != 0)
    {
        xCAT::MsgUtils->message('S', "Unable export DB environment.\n");
        $::RUNCMD_RC = 1;
        return;

    }

    # get handle to servicenode table
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)
    {
        xCAT::MsgUtils->message('S', "Unable to open servicenode table.\n");
        $::RUNCMD_RC = 1;
        return;    # do not setup anything
    }

    my @process_service_list = ();

    # read all the nodes from the table, for each service
    foreach my $service (@services)
    {
        my @snodelist = $servicenodetab->getAllNodeAttribs([$service]);

        foreach $serviceip (@ips)    # check the table for this servicenode
        {
            foreach my $node (@snodelist)

            {
                if ($serviceip eq $node->{'node'})
                {                    # match table entry
                    if ($node->{$service})
                    {                # returns service, only if set
                        my $value = $node->{$service};
                        $value =~ tr/a-z/A-Z/;    # convert to upper
                             # value 1 or yes  then we setup the service
                        if (($value eq "1") || ($value eq "YES"))
                        {
                            push @process_service_list,
                              $service;    # found service to setup
                        }
                    }
                }
            }
        }
    }
    $servicenodetab->close;

    $::RUNCMD_RC = 0;
    return @process_service_list;

}

#-----------------------------------------------------------------------------

=head3 determinehostname  and ip address(s)

  Used on the service node to figure out what hostname and ip address(s)
  are valid names and addresses 
  Input: None
  Output: ipaddress(s),nodename
=cut

#-----------------------------------------------------------------------------
sub determinehostname
{
    my $hostname;
    my $hostnamecmd = "/bin/hostname";
    my @thostname = xCAT::Utils->runcmd($hostnamecmd, 0);
    if ($::RUNCMD_RC != 0)
    {    # could not get hostname
        xCAT::MsgUtils->message("S",
                              "Error $::RUNCMD_RC from $hostnamecmd command\n");
        exit $::RUNCMD_RC;
    }
    $hostname = $thostname[0];

    # strip off domain, if there
    my @shorthost = split(/\./, $hostname);
    my @ips       = xCAT::Utils->gethost_ips;
    my @hostinfo  = (@ips, $shorthost[0]);

    return @hostinfo;
}

#-----------------------------------------------------------------------------

=head3 update_xCATSN
  Will add the input service string to /etc/xCATSN to indicate that
  the service has been setup by the service node
  Input: service (e.g. tftp, nfs,etc)
  Output: 0 = added, 1= already there

=cut

#-----------------------------------------------------------------------------
sub update_xCATSN
{
    my ($class, $service) = @_;
    my $file = "/etc/xCATSN";
    my $rc   = 0;
    my $cmd  = " grep $service $file";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {    # need to add
        `echo $service  >> /etc/xCATSN`;
    }
    else
    {
        $rc = 1;
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 gethost_ips  (AIX and Linux)
     Will use ifconfig to determine all possible ip addresses for the
	 host it is running on and then gethostbyaddr to get all possible hostnames

     input:
	 output: array of ipaddress(s)  and hostnames
	 example:  @ips=xCAT::gethost_ips();

=cut

#-----------------------------------------------------------------------------
sub gethost_ips
{
    my ($class) = @_;
    my $cmd;
    my @ipaddress;
    $cmd = "ifconfig" . " -a";
    $cmd = $cmd . "| grep \"inet \"";
    my @result = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd\n");
        exit $::RUNCMD_RC;
    }
    foreach my $addr (@result)
    {
        my @ip;
        if (xCAT::Utils->isLinux())
        {
            my ($inet, $addr1, $Bcast, $Mask) = split(" ", $addr);
            @ip = split(":", $addr1);
            push @ipaddress, $ip[1];
        }
        else
        {    #AIX
            my ($inet, $addr1, $netmask, $mask1, $Bcast, $bcastaddr) =
              split(" ", $addr);
            push @ipaddress, $addr1;

        }
    }
    my @names = @ipaddress;
    foreach my $ipaddr (@names)
    {
        my $packedaddr = inet_aton($ipaddr);
        my $hostname = gethostbyaddr($packedaddr, AF_INET);
        if ($hostname)
        {
            my @shorthost = split(/\./, $hostname);
            push @ipaddress, $shorthost[0];
        }
    }

    return @ipaddress;
}

#-----------------------------------------------------------------------------

=head3 create_postscripts_tar

     This routine will tar and compress the /install/postscripts directory
	 and place in /install/autoinst/xcat_postscripts.Z

     input: none
	 output:
	 example: $rc=xCAT::create_postscripts_tar();

=cut

#-----------------------------------------------------------------------------
sub create_postscripts_tar
{
    my ($class) = @_;
    my $cmd;
    if (!(-e "/install/autoinst"))
    {
        mkdir("/install/autoinst");
    }

    $cmd =
      "cd /install/postscripts; tar -cf /install/autoinst/xcatpost.tar * .ssh/* _xcat/*; gzip -f /install/autoinst/xcatpost.tar";
    my @result = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd\n");
        return $::RUNCMD_RC;
    }

    # for AIX add an entry to the /etc/tftpaccess.ctrl file so
    #	we can tftp the tar file from the node
    if (xCAT::Utils->isAIX())
    {
        my $tftpctlfile = "/etc/tftpaccess.ctl";
        my $entry       = "allow:/install/autoinst/xcatpost.tar.gz";

        # see if there is already an entry
        my $cmd = "cat $tftpctlfile | grep xcatpost";
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {

            # not found so add it
            unless (open(TFTPFILE, ">>$tftpctlfile"))
            {
                xCAT::MsgUtils->message("S", "Could not open $tftpctlfile.\n");
                return $::RUNCMD_RC;
            }

            print TFTPFILE $entry;

            close(TFTPFILE);
        }
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3 get_site_Master

     Reads the site table for the Master attribute and returns it.
     input: none
     output : value of site.Master attribute , blank is an error
	 example: $Master =xCAT::get_site_Master();

=cut

#-----------------------------------------------------------------------------

sub get_site_Master
{
    my $Master;
    my $sitetab = xCAT::Table->new('site');
    (my $et) = $sitetab->getAttribs({key => "master"}, 'value');
    if ($et and $et->{value})
    {
        $Master = $et->{value};
    }
    else
    {
        xCAT::MsgUtils->message('E',
                           "Unable to read site table for Master attribute.\n");
    }
    return $Master;
}

#-----------------------------------------------------------------------------

=head3 get_ServiceNode

     Will get the Service node ( name or ipaddress) as known by the Management
	 Server or Node for the input nodename or ipadress of the node

     input: list of nodenames and/or node ipaddresses (array ref)
			service name
			"MN" or "Node"  determines if you want the Service node as known
			 by the Management Node  or by the node.

		recognized service names: xcat,tftpserver,
		nfsserver,conserver,monserver

        service "xcat" is used by command like xdsh that need to know the
		service node that will process the command but are not tied to a
		specific service like tftp

		Todo:  Handle  dhcpserver and nameserver from the networks table

	 output: A hash ref  of arrays, the key is the service node pointing to
			 an array of nodes that are serviced by that service node

     Globals:
        $::ERROR_RC
     Error:
         $::ERROR_RC=0 no error $::ERROR_RC=1 error

	 example: $sn =xCAT::Utils->get_ServiceNode(\@nodes,$service,"MN");
	  $sn =xCAT::Utils->get_ServiceNode(\@nodes,$service,"Node");

=cut

#-----------------------------------------------------------------------------
sub get_ServiceNode
{
    my ($class, $node, $service, $request) = @_;
    my @node_list = @$node;
    my $cmd;
    my %snhash;
    my $nodehash;
    my $sn;
    my $nodehmtab;
    my $noderestab;
    my $snattribute;
    $::ERROR_RC = 0;

    # determine if the request is for the service node as known by the MN
    # or the node

    if ($request eq "MN")
    {
        $snattribute = "servicenode";
    }
    else    # Node
    {
        $snattribute = "xcatmaster";
    }

    my $master =
      xCAT::Utils->get_site_Master();    # read the site table, master attrib

    $noderestab = xCAT::Table->new('noderes');
    unless ($noderestab)    # no noderes table, use default site.master
    {
        xCAT::MsgUtils->message('I',
                         "Unable to open noderes table. Using site->Master.\n");
        if ($master)        # use site Master value
        {
            foreach my $node (@node_list)
            {               # no noderes table, all use site Master
                push @{$snhash{$master}}, $node;
            }
        }
        else
        {
            xCAT::MsgUtils->message('E', "Unable to read site Master value.\n");
            $::ERROR_RC = 1;
        }
        return \%snhash;
    }

    if ($service eq "xcat")
    {    # find all service nodes for the nodes in the list

        $nodehash = $noderestab->getNodesAttribs(\@node_list, [$snattribute]);
        foreach my $node (@node_list)
        {
            foreach my $rec (@{$nodehash->{$node}})
            {
                if ($rec and $rec->{$snattribute})
                {
                    my $key = $rec->{$snattribute};
                    push @{$snhash{$key}}, $node;
                }
                else
                {    # use site.master
                    push @{$snhash{$master}}, $node;
                }
            }
        }

        $noderestab->close;
        return \%snhash;

    }
    else
    {
        if (
            ($service eq "tftpserver")    # all from noderes table
            || ($service eq "nfsserver") || ($service eq "monserver")
          )
        {
            $nodehash =
              $noderestab->getNodesAttribs(\@node_list,
                                           [$service, $snattribute]);
            foreach my $node (@node_list)
            {
                foreach my $rec (@{$nodehash->{$node}})
                {
                    if ($rec and $rec->{$service})
                    {

                        # see if both  MN and Node address in attribute
                        my ($msattr, $nodeattr) = split ':', $rec->{$service};
                        my $key = $msattr;
                        if ($request eq "Node")
                        {
                            if ($nodeattr)    # override with Node, if it exists
                            {
                                $key = $nodeattr;
                            }
                        }
                        push @{$snhash{$key}}, $node;
                    }
                    else
                    {
                        if ($rec and $rec->{$snattribute})    # if it exists
                        {
                            my $key = $rec->{$snattribute};
                            push @{$snhash{$key}}, $node;
                        }
                        else
                        {                                     # use site.master
                            push @{$snhash{$master}}, $node;
                        }
                    }
                }
            }

            $noderestab->close;
            return \%snhash;

        }
        else
        {
            if ($service eq "conserver")
            {

                # read the nodehm table
                $nodehmtab = xCAT::Table->new('nodehm');
                unless ($nodehmtab)    # no nodehm table
                {
                    xCAT::MsgUtils->message('I',
                                            "Unable to open nodehm table.\n");

                    # use servicenode
                    $nodehash =
                      $noderestab->getNodesAttribs(\@node_list, [$snattribute]);
                    foreach my $node (@node_list)
                    {
                        foreach my $rec (@{$nodehash->{$node}})
                        {
                            if ($rec and $rec->{$snattribute})
                            {
                                my $key = $rec->{$snattribute};
                                push @{$snhash{$key}}, $node;
                            }
                            else
                            {    # use site.master
                                push @{$snhash{$master}}, $node;
                            }
                        }
                    }
                    $noderestab->close;
                    return \%snhash;
                }

                # can read the nodehm table
                $nodehash =
                  $nodehmtab->getNodesAttribs(\@node_list, ['conserver']);
                foreach my $node (@node_list)
                {
                    foreach my $rec (@{$nodehash->{$node}})
                    {
                        if ($rec and $rec->{'conserver'})
                        {

                            # see if both  MN and Node address in attribute
                            my ($msattr, $nodeattr) = split ':',
                              $rec->{'conserver'};
                            my $key = $msattr;
                            if ($request eq "Node")
                            {
                                if ($nodeattr
                                  )    # override with Node, if it exists
                                {
                                    $key = $nodeattr;
                                }
                            }
                            push @{$snhash{$key}}, $node;
                        }
                        else
                        {              # use service node for this node
                            $sn =
                              $noderestab->getNodeAttribs($node,
                                                          [$snattribute]);
                            if ($sn and $sn->{$snattribute})
                            {
                                my $key = $sn->{$snattribute};
                                push @{$snhash{$key}}, $node;
                            }
                            else
                            {          # no service node use master
                                push @{$snhash{$master}}, $node;
                            }
                        }
                    }
                }
                $noderestab->close;
                $nodehmtab->close;
                return \%snhash;

            }
            else
            {
                xCAT::MsgUtils->message('E',
                                        "Invalid service=$service input.\n");
                $::ERROR_RC = 1;
            }
        }
    }
    return \%snhash;

}

#-----------------------------------------------------------------------------

=head3 toIP 

 IPv4 function to convert hostname to IP address

=cut

#-----------------------------------------------------------------------------
sub toIP
{

    # does not support IPV6  IPV6TODO
    if ($_[0] =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/)
    {
        return ([0, $_[0]]);
    }
    my $packed_ip = gethostbyname($_[0]);
    if (!$packed_ip or $!)
    {
        return ([1, "Cannot Resolve: $_[0]\n"]);
    }
    return ([0, inet_ntoa($packed_ip)]);
}

#-----------------------------------------------------------------------------

=head3 isSN 
 
	Determines if the input node name is a service node
	Reads the servicenode table. nodename must be service node name as 
	known by the Management node.

    returns 1 if input host is a service node 
    Arguments:
       hostname 
    Returns:
        1 - is  Service Node
        0 - is not a Service Node
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isSN($nodename)) { blah; }
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub isSN
{
    my ($class, $node) = @_;

    # reads all nodes from the service node table
    my @servicenodes;
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        return 0;

    }
    my @nodes = $servicenodetab->getAllNodeAttribs(['tftpserver']);
    $servicenodetab->close;
    foreach my $nodes (@nodes)
    {
        if ($node eq $nodes->{node})
        {
            return 1;           # match
        }
    }

    return 0;
}

#-----------------------------------------------------------------------------

=head3 getAllSN 
 
    Returns an array of all service nodes from service node table 

    Arguments:
       none 
    Returns:
		array of Service Nodes or empty array, if none
    Globals:
        none
    Error:
        1 - error
    Example:
         @allSN=xCAT::Utils->get_AllSN
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getAllSN
{

    # reads all nodes from the service node table
    my @servicenodes;
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        $servicenodetab->close;
        return @servicenodes;

    }
    my @nodes = $servicenodetab->getAllNodeAttribs(['tftpserver']);
    foreach my $nodes (@nodes)
    {
        push @servicenodes, $nodes->{node};
    }
    $servicenodetab->close;
    return @servicenodes;
}

#-----------------------------------------------------------------------------

=head3 getSNandNodes 
 
    Returns an hash-array of all service nodes and the nodes they service

    Arguments:
       none 
#-----------------------------------------------------------------------------

=head3 getSNandNodes 
 
    Returns an hash-array of all service nodes and the nodes they service

    Arguments:
       none 
    Returns:
	 Service Nodes and the nodes they service or empty , if none
    Globals:
        none
    Error:
        1 - error
    Example:
        $sn=xCAT::Utils->getSNandNodes()
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getSNandNodes
{

    # read all the nodes from the nodelist table
    #  call get_ServiceNode to find which Service Node
    # the node belongs to.
    my %sn;
    my @nodes;
    my $nodelisttab = xCAT::Table->new('nodelist');
    my $recs        = $nodelisttab->getAllEntries();
    foreach (@$recs)
    {
        push @nodes, $_->{node};
    }
    $nodelisttab->close;
    my $sn = xCAT::Utils->get_ServiceNode(\@nodes, "xcat", "MN");
    return $sn;
}

#-----------------------------------------------------------------------------

=head3 getSNList 
 
	Reads the servicenode table. Will return all the enabled Service Nodes
	that will setup the input Service ( e.g tftpserver,nameserver,etc)
	If service is blank, then will return the list of all enabled Service
	Nodes. 

    Arguments:
       Servicename ( xcat,tftpserver,dhcpserver,conserver,etc) 
    Returns:
	  Array of service node names 
    Globals:
        none
    Error:
        1 - error  
    Example:
         $sn= xCAT::Utils->getSNList($servicename) { blah; }
         $sn= xCAT::Utils->getSNList() { blah; }
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getSNList
{
    my ($class, $service) = @_;

    # reads all nodes from the service node table
    my @servicenodes;
    my $servicenodetab = xCAT::Table->new('servicenode', -create => 1);
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        return ();
    }
    my @nodes = $servicenodetab->getAllNodeAttribs([$service]);
    $servicenodetab->close;
    foreach my $node (@nodes)
    {
        if ($service eq "")     # want all the service nodes
        {
            push @servicenodes, $node->{node};
        }
        else
        {                       # looking for a particular service
            if ($node->{$service})
            {                   # if null then do not add node
                my $value = $node->{$service};
                $value =~ tr/a-z/A-Z/;    # convert to upper
                     # value 1 or yes or blank then we setup the service
                if (($value == 1) || ($value eq "YES"))
                {
                    push @servicenodes, $node->{node};

                }
            }
        }
    }

    return @servicenodes;
}

#-------------------------------------------------------------------------------

=head3    isMounted
    Checks if the input directory is already mounted 
    Arguments:
       directory 
    Returns:
        1 - directory is mounted 
        0 - directory is not mounted 
    Globals:
        none
    Error:
        -1 error
    Example:
         if (xCAT::Utils->isMounted($directory)) { blah; }
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isMounted
{
    my ($class, $directory) = @_;
    my $cmd = "df -P $directory";
    my @output = xCAT::Utils->runcmd($cmd, -1);
    foreach my $line (@output)
    {
        my ($file_sys, $blocks, $used, $avail, $cap, $mount_point) =
          split(' ', $line);
        if ($mount_point eq $directory)
        {
            return 1;
        }
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3   runxcatd 
    Stops or starts xcatd  
    Arguments:
        xcatstart - start the daemon,  restart if already running
        xcatstop - stop the daemon
    Returns:
        0 = not error, 1 = error 
    Globals:
        none
    Error:
	   
    Example:
        my $rc = xCAT::runxcatd("xcatstart") ; ( starts xcatd)
        my $rc = xCAT::runxcatd("xcatstop") ; ( stops xcatd)

=cut

#-------------------------------------------------------------------------------
sub runxcatd
{
    my ($class, $cmd) = @_;
    if (!(xCAT::Utils->isAIX()))
    {    # only runs on AIX
        xCAT::MsgUtils->message("E",
                                "This command should only be run on AIX.\n");
        return 1;
    }

    #
    # if xcatd already running
    # Get the  xcatd processes  and stop them
    #
    my @xpids = xCAT::Utils->runcmd("ps -ef\|grep \"xcatd\"", 0);
    if ($#xpids >= 1)
    {    # will have at least "0" for the grep
        xCAT::MsgUtils->message('I', "Stopping xcatd processes....\n");
        foreach my $ps (@xpids)
        {

            $ps =~ s/^\s+//;    # strip any leading spaces
            my ($uid, $pid, $ppid, $desc) = split /\s+/, $ps;

            # if $ps contains "grep" then it's not one of the daemon processes
            if ($ps !~ /grep/)
            {

                #	    	print "pid=$pid\n";
                #my $cmd = "/bin/kill -9 $pid";
                my $cmd = "/bin/kill  $pid";
                xCAT::Utils->runcmd($cmd, 0);
                if ($::RUNCMD_RC != 0)
                {
                    xCAT::MsgUtils->message('E',
                                        "Could not stop xcatd process $pid.\n");
                    return 1;
                }
            }
        }
    }

    if ($cmd eq "xcatstart")
    {    # start xcatd
        xCAT::MsgUtils->message('I', "Starting xcatd.....\n");
        my $xcmd = "$::XCATROOT/sbin/xcatd &";
        my $outref = xCAT::Utils->runcmd("$xcmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message('E', "Could not start xcatd process.\n");
            return 1;
        }
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3   get_image_name
       get a name for the install image on AIX and Linux, to be used
       by xdsh and sinv for the nodename 
    Arguments:
        path to image.
    Returns:
       imagename 

=cut

#-------------------------------------------------------------------------------
sub get_image_name
{
    my ($class, $imagepath) = @_;
    my $imagename;
    if (xCAT::Utils->isLinux())
    {
        my @fields = split('/', $imagepath);
        $imagename .= $fields[5];
        $imagename .= "-";
        $imagename .= $fields[3];
        $imagename .= "-";
        $imagename .= $fields[4];
    }
    else
    {    # AIX
        my @fields = split('/', $imagepath);
        my $name = pop @fields;
        $imagename = $name;
    }

    return $imagename;
}

#-------------------------------------------------------------------------------

=head3   logEventsToDatabase
       Logs the given events info to the xCAT's 'eventlog' database 
    Arguments:
        arrayref -- A pointer to an array. Each element is a hash that contains an events.
        The hash should contain the at least one of the following keys:
          eventtime -- The format is "mm-dd-yyyy hh:mm:ss".
                       If omitted, the current date and time will be used.
          monitor  -- The name of the monitor that monitors this event.
          monnode -- The node that monitors this event.
          node -- The node where the event occurred.
          application -- The application that reports the event.
          component -- The component where the event occurred.
          id -- The location or the resource name where the event occurred.
          severity -- The severity of the event. Valid values are: informational, warning, critical.
          message -- The full description of the event.
	  rawdata -- The data that associated with the event.         
  Returns:
       (ret code, error message) 
  Example:
    my  @a=();
    my $event={
        eventtime=>"07-28-2009 23:02:03",
        node => 'node1',
        rawdata => 'kjdlkfajlfjdlksaj',
    };
    push (@a, $event);

    my $event1={
        node => 'cu03cp',
        monnode => 'cu03sv',
        application => 'RMC',
        component => 'IBM.Sensor',
        id => 'AIXErrorLogSensor',
        severity => 'warning',
    };
    push(@a, $event1);
    xCAT::Utils->logEventsToDatabase(\@a);

=cut

#-------------------------------------------------------------------------------
sub logEventsToDatabase
{
    my $pEvents = shift;
    if (($pEvents) && ($pEvents =~ /xCAT::Utils/))
    {
        $pEvents = shift;
    }

    if (($pEvents) && (@$pEvents > 0))
    {
        my $currtime;
        my $tab = xCAT::Table->new("eventlog", -create => 1, -autocommit => 0);
        if (!$tab)
        {
            return (1, "The evnetlog table cannot be opened.");
        }

        foreach my $event (@$pEvents)
        {

            #create event time if it does not exist
            if (!exists($event->{eventtime}))
            {
                if (!$currtime)
                {
                    my (
                        $sec,  $min,  $hour, $mday, $mon,
                        $year, $wday, $yday, $isdst
                      )
                      = localtime(time);
                    $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                                        $mon + 1, $mday, $year + 1900,
                                        $hour, $min, $sec);
                }
                $event->{eventtime} = $currtime;
            }
            my @ret = $tab->setAttribs(undef, $event);
            if (@ret > 1) { return (1, $ret[1]); }
        }
        $tab->commit;
    }

    return (0, "");
}

#-------------------------------------------------------------------------------

=head3   StartService
	Supports AIX and Linux as long as the service is registered with
	lssrc or startsrc.  
	Used by the service node plugin (AAsn.pm) to start requested services. 
    Checks to see if the input service is already started. If it is started
	it stops and  starts the service. Otherwise
	it just starts the service.
	Note we are using the system command on the start of the services to see
	the output when the xcatd is started on Service Nodes.  Do not change this.
    Arguments:
     servicename
	 force flag
    Returns:
        0 - ok
		1 - could not start the service
    Globals:
        none
    Error:
        1 error
    Example:
         if (xCAT::Utils->startService("named") { ...}
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub startService
{
    my ($class, $service) = @_;
    my $rc = 0;
    my @output;
    my $cmd;
    if (xCAT::Utils->isAIX())
    {
        @output = xCAT::Utils->runcmd("LANG=C /usr/bin/lssrc -s $service", 0);
        if ($::RUNCMD_RC != 0)
        {    # error so start it
            $cmd = "/usr/bin/stopsrc -s $service";
            system $cmd;    # note using system here to see output when
                            # daemon comes up
            if ($? > 0)
            {               # error
                xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
            }
            $cmd = "/usr/bin/startsrc -s $service";
            system $cmd;
            if ($? > 0)
            {               # error
                xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                return 1;
            }

        }
        else
        {

            # check to see if running
            my ($subsys, $group, $pid, $status) = split(' ', $output[1]);
            if (defined($status) && $status eq 'active')
            {

                # already running, stop and start
                $cmd = "/usr/bin/stopsrc -s $service";
                system $cmd;    # note using system here to see output when
                                # daemon comes up
                if ($? > 0)
                {               # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                }
                $cmd = "/usr/bin/startsrc -s $service";
                system $cmd;
                if ($? > 0)
                {               # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                    return 1;
                }
                return 0;
            }
            else
            {

                # not running, start it
                $cmd = "/usr/bin/startsrc -s $service";
                system $cmd;    # note using system here to see output when
                                # daemon comes up
                if ($? > 0)
                {
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                    return 1;
                }

            }
        }
    }
    else                        # linux
    {
        my @output = xCAT::Utils->runcmd("service $service status", -1);
        if ($::RUNCMD_RC == 0)
        {

            #  whether or not an error is returned varies by service
            #  stop and start the service for those running
            if (($service ne "conserver") && ($service ne "nfs"))
            {
                $cmd = "service $service stop";
                system $cmd;
                if ($? > 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                }
                $cmd = "service $service start";
                system $cmd;
                if ($? > 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                    return 1;
                }
                return 0;
            }
            if (($service eq "conserver") || ($service eq "nfs"))
            {

                # must check output
                if (grep(/running/, @output))
                {
                    $cmd = "service $service stop";
                    system $cmd;
                    if ($? > 0)
                    {    # error
                        xCAT::MsgUtils->message("S",
                                                "Error on command: $cmd\n");
                    }
                    $cmd = "service $service start";
                    system $cmd;
                    if ($? > 0)
                    {    # error
                        xCAT::MsgUtils->message("S",
                                                "Error on command: $cmd\n");
                        return 1;
                    }
                    return 0;
                }
                else
                {

                    # not running , just start
                    $cmd = "service $service start";
                    system $cmd;
                    if ($? > 0)
                    {    # error
                        xCAT::MsgUtils->message("S",
                                                "Error on command: $cmd\n");
                        return 1;
                    }
                    return 0;
                }
            }
        }
        else
        {

            # error getting status, check output
            # must check output
            if (grep(/stopped/, @output))    # stopped
            {
                $cmd = "service $service start";
                system $cmd;
                if ($? > 0)
                {                            # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                    return 1;
                }
            }
            else
            {                                # not sure
                $cmd = "service $service stop";
                system $cmd;
                if ($? > 0)
                {                            # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                }
                $cmd = "service $service start";
                system $cmd;
                if ($? > 0)
                {                            # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                    return 1;
                }
            }
        }
    }

    return $rc;
}

#-------------------------------------------------------------------------------

=head3   CheckVersion
       Checks the two versions numbers to see which one is greater.
    Arguments:
        ver_a the version number in format of d.d.d.d...
        ver_b the version number in format of d.d.d.d...
    Returns:
        1 if ver_a is greater than ver_b
        0 if ver_a is eaqual to ver_b
        -1 if ver_a is smaller than ver_b

=cut

#-------------------------------------------------------------------------------
sub CheckVersion
{
    my $ver_a = shift;
    if ($ver_a =~ /xCAT::Utils/)
    {
        $ver_a = shift;
    }
    my $ver_b = shift;

    my @a = split(/\./, $ver_a);
    my @b = split(/\./, $ver_b);
    my $len_a = @a;
    my $len_b = @b;

    my $index     = 0;
    my $max_index = ($len_a > $len_b) ? $len_a : $len_b;

    for ($index = 0 ; $index <= $max_index ; $index++)
    {
        my $val_a = ($len_a < $index) ? 0 : $a[$index];
        my $val_b = ($len_b < $index) ? 0 : $b[$index];
        if ($val_a > $val_b) { return 1; }
        if ($val_a < $val_b) { return -1; }
    }

    return 0;
}

#-------------------------------------------------------------------------------

=head3   getFacingIP
       Gets the ip address of the adapter of the localhost that is facing the
    the given node.
    Arguments:
       The name of the node that is facing the localhost.
    Returns:
       The ip address of the adapter that faces the node.

=cut

#-------------------------------------------------------------------------------
sub getFacingIP
{
    my ($class, $node) = @_;
    my $ip;
    my $cmd;
    my @ipaddress;

    my $nodeip = inet_ntoa(inet_aton($node));
    unless ($nodeip =~ /\d+\.\d+\.\d+\.\d+/)
    {
        return 0;    #Not supporting IPv6 here IPV6TODO
    }

    $cmd = "ifconfig" . " -a";
    $cmd = $cmd . "| grep \"inet \"";
    my @result = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd\n");
        exit $::RUNCMD_RC;
    }

    # split node address
    my ($n1, $n2, $n3, $n4) = split('\.', $nodeip);

    foreach my $addr (@result)
    {
        my $ip;
        my $mask;
        if (xCAT::Utils->isLinux())
        {
            my ($inet, $addr1, $Bcast, $Mask) = split(" ", $addr);
            if ((!$addr1) || (!$Mask)) { next; }
            my @ips   = split(":", $addr1);
            my @masks = split(":", $Mask);
            $ip   = $ips[1];
            $mask = $masks[1];
        }
        else
        {    #AIX
            my ($inet, $addr1, $netmask, $mask1, $Bcast, $bcastaddr) =
              split(" ", $addr);
            if ((!$addr1) && (!$mask1)) { next; }
            $ip = $addr1;
            $mask1 =~ s/0x//;
            $mask =
              `printf "%d.%d.%d.%d" \$(echo "$mask1" | sed 's/../0x& /g')`;
        }

        if ($ip && $mask)
        {

            # split interface IP
            my ($h1, $h2, $h3, $h4) = split('\.', $ip);

            # split mask
            my ($m1, $m2, $m3, $m4) = split('\.', $mask);

            # AND this interface IP with the netmask of the network
            my $a1 = ((int $h1) & (int $m1));
            my $a2 = ((int $h2) & (int $m2));
            my $a3 = ((int $h3) & (int $m3));
            my $a4 = ((int $h4) & (int $m4));

            # AND node IP with the netmask of the network
            my $b1 = ((int $n1) & (int $m1));
            my $b2 = ((int $n2) & (int $m2));
            my $b3 = ((int $n3) & (int $m3));
            my $b4 = ((int $n4) & (int $m4));

            if (($b1 == $a1) && ($b2 == $a2) && ($b3 == $a3) && ($b4 == $a4))
            {
                return $ip;
            }
        }
    }

    xCAT::MsgUtils->message("S", "Cannot find master for the node $node\n");
    return 0;
}

#-------------------------------------------------------------------------------

=head3  osver
        Returns the os and version of the System you are running on 
    Arguments:
      none
    Returns:
        0 - ok
    Globals:
        none
    Error:
        1 error
    Example:
         my $os=(xCAT::Utils->osver{ ...}
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub osver
{
    my $osver = "unknown";
    my $os    = '';
    my $ver   = '';
    my $line  = '';
    my @lines;
    if (-f "/etc/redhat-release")
    {
        chomp($line = `head -n 1 /etc/redhat-release`);
        $os = "rh";
        chomp($ver = `tr -d '.' < /etc/redhat-release | head -n 1`);
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;
        if    ($line =~ /AS/)     { $os = 'rhas' }
        elsif ($line =~ /ES/)     { $os = 'rhes' }
        elsif ($line =~ /WS/)     { $os = 'rhws' }
        elsif ($line =~ /Server/) { $os = 'rhserver' }
        elsif ($line =~ /Client/) { $os = 'rhclient' }
        elsif (-f "/etc/fedora-release") { $os = 'rhfc' }
    }
    elsif (-f "/etc/SuSE-release")
    {
        chomp(@lines = `cat /etc/SuSE-release`);
        if (grep /SLES|Enterprise Server/, @lines) { $os = "sles" }
        if (grep /SLEC/, @lines) { $os = "slec" }
        chomp($ver = `tr -d '.' < /etc/SuSE-release | head -n 1 `);
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;

        #print "ver: $ver\n";
    }
    elsif (-f "/etc/UnitedLinux-release")
    {

        $os = "ul";
        chomp($ver = `tr -d '.' < /etc/UnitedLinux-release | head -n 1 `);
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;
    }
    $os = "$os" . "$ver";
    return ($os);
}

#-------------------------------------------------------------------------------

=head3 checkCreds 
        Checks the various credential files on the Management Node to
		make sure the permission are correct for using and transferring
		to the nodes and service nodes.
		Also removes /install/postscripts/etc/xcat/cfgloc if found
    Arguments:
      $callback 
    Returns:
        0 - ok
    Globals:
        none 
    Error:
         warnings of possible missing files  and directories
    Example:
         my $rc=xCAT::Utils->checkCreds
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub checkCreds
{
    my $lib  = shift;
    my $cb  = shift;
    my $dir = "/install/postscripts/_xcat";
    if (-d $dir)
    {
        my $file = "$dir/ca.pem";
        if (-e $file)
        {

            my $cmd = "/bin/chmod 0644 $file";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {    # ca.pem missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing.";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }
    my $dir = "/install/postscripts/ca";
    if (-d $dir)
    {
        my $file = "$dir/ca-cert.pem";
        if (-e $file)
        {

            my $cmd = "/bin/chmod 0644 $file";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {    # ca_cert.pem missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing.";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }

    # ssh hostkeys
    my $dir = "/install/postscripts/hostkeys";
    if (-d $dir)
    {
        my $file = "$dir/ssh_host_key.pub";
        if (-e $file)
        {
            my $file2  = "$dir/*.pub";                     # all public keys
            my $cmd    = "/bin/chmod 0644 $file2";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }
        }
        else
        {                                                  # hostkey missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing.";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }

    # ssh directory
    my $dir = "/install/postscripts/_ssh";
    if (-d $dir)
    {
        my $file = "$dir/authorized_keys";
        if (-e $file)
        {
            my $file2  = "$dir/authorized_keys*";
            my $cmd    = "/bin/chmod 0644 $file2";
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Error on command: $cmd";
                xCAT::MsgUtils->message("I", $rsp, $cb);

            }

            # make install script executable
            $file2 = "$dir/copy.sh";
            if (-e $file2)
            {
                my $cmd = "/bin/chmod 0744 $file2";
                my $outref = xCAT::Utils->runcmd("$cmd", 0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Error on command: $cmd";
                    xCAT::MsgUtils->message("I", $rsp, $cb);

                }
            }
        }
        else
        {    # authorized keys missing
            my $rsp = {};
            $rsp->{data}->[0] = "Error: $file is missing.";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }

    # remove any old cfgloc files
    my $file = "/install/postscripts/etc/xcat/cfgloc";
    if (-e $file)
    {

        my $cmd = "/bin/rm  $file";
        my $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Error on command: $cmd";
            xCAT::MsgUtils->message("I", $rsp, $cb);

        }
    }

}

1;
