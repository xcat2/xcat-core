#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Utils;
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
        none
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
    my $version = "Version 2.1\n"; 
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
      or MsgUtils->message("E", "Cannot write to file: $file\n");
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
    my $req={};
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
        if ($ref and $ref->{value})
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
    if (xCAT::Utils::isLinux) { $tabname = "-"; }
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
    if (xCAT::Utils::isLinux) { $tabname = "-"; }
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
            my $rsp={};
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

        Transfers the ssh keys to setup ssh to the input nodes.

        Arguments:
               Array of nodes
        Returns:

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
    my $SSHdir   = "/install/postscripts/.ssh";
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
        mkdir("/install/postscripts/.ssh", 0755);
    }

    # Generate the keys
    my $rsp={};
    xCAT::Utils->runcmd("$::REMOTESHELL_EXPECT -k", 0);
    if ($::RUNCMD_RC != 0)
    {    # error
        $rsp->{data}->[0] = "remoteshell.expect failed generating keys.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

    }

    # Copy the keys to the directory
    my $rc = xCAT::Utils->cpSSHFiles($SSHdir);
    if ($rc != 0)
    {    # error
        $rsp->{data}->[0] = "Error running cpSSHFiles.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;

    }

    open(FILE, ">$SSHdir/copy.perl")
      or die "cannot open file $SSHdir/copy.perl\n";

    #  build the perl copy script in $SSHdir/copy.perl
    print FILE "#!/usr/bin/perl
my (\$name,\$passwd,\$uid,\$gid,\$quota,\$comment,\$gcos,\$dir,\$shell,\$expire) = getpwnam(\"root\");
my \$home = \$dir;
umask(0077);
\$dest_dir = \"\$home/.ssh/\";
if (! -d \"\$dest_dir\" ) {
    # create a local directory
    \$cmd = \"mkdir -p \$dest_dir\";
    system(\"\$cmd\");
    chmod 0700, \$dest_dir;
}
`cat /tmp/.ssh/authorized_keys >> \$home/.ssh/authorized_keys 2>&1`;
`cat /tmp/.ssh/authorized_keys2 >> \$home/.ssh/authorized_keys2 2>&1`;
`rm -f /tmp/.ssh/authorized_keys 2>&1`;
`rm -f /tmp/.ssh/authorized_keys2 2>&1`;
`rm -f /tmp/.ssh/copy.perl 2>&1`;
rmdir(\"/tmp/.ssh\");";
    close FILE;
    chmod 0744, "$SSHdir/copy.perl";

    # end build Perl code

    #set an ENV var if more than 10 nodes for remoteshell.expect
    my $num_nodes = scalar(@nodes);
    if ($num_nodes > 10)
    {
        $ENV{'XCAT_UPD_MULTNODES'} = 1;
    }

    # send the keys to the nodes
    #
    my $cmd = "$::REMOTESHELL_EXPECT -s $n_str";
    my $rc  = system("$cmd") >> 8;
    if ($rc)
    {
        $rsp->{data}->[0] = "remoteshell.expect failed sending keys.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

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

    xCAT::Utils->runcmd("/bin/stty echo", 0);
    delete $ENV{'XCAT_UPD_MULTNODES'};

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

        Copies the ssh keyfiles and the copy perl script into
		/install/postscripts/.ssh.

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
    my $rsp={};
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
    my $rsp={};
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

    my $rsp={};
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
        1 - localHost is ServiceNode
        0 - localHost is not ServiceNode
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
        $noderestab->close;
        $typetab->close;
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
  if the input Service should be setup on the
  input service node

  Input: service nodename, service,ipaddres(s) and hostnames of service node
  Output:
        0 - no service required
        1 - setup service
        2 - service is setup, just start the daemon
		-1 - error
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isServiceReq($servicenodename, $service, $serviceip) { blah; }

=cut

#-----------------------------------------------------------------------------
sub isServiceReq
{
    my ($class, $servicenodename, $service, $serviceip) = @_;
    my @ips = @$serviceip;    # list of service node ip addresses and names
    my $rc  = 0;

    # check if service is already setup
    #`grep $service /etc/xCATSN`;
    #if ($? == 0)
    #{                         # service is already setup, just start daemon
    #    return 2;
    #}

    $rc = xCAT::Utils->exportDBConfig();    # export DB env
    if ($rc != 0)
    {
        xCAT::MsgUtils->message('S', "Unable export DB environment.\n");
        return -1;

    }

    # get handle to servicenode table
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)
    {
        xCAT::MsgUtils->message('S', "Unable to open servicenode table.\n");
        return 0;    # do not setup anything
    }

    # read all the nodes from the table
    my @snodelist = $servicenodetab->getAllNodeAttribs([$service]);
    $servicenodetab->close;
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
                        return 1;    # found service required for the node
                    }
                }
            }
        }
    }

    return 0;    # servicenode is not required to setup this service

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

=head3 gethost_ips
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
        my ($inet, $addr1, $Bcast, $Mask) = split(" ", $addr);
        my @ip = split(":", $addr1);
        push @ipaddress, $ip[1];
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

=cut

#-----------------------------------------------------------------------------
sub get_ServiceNode
{
    my ($class, $node, $service, $request) = @_;
    my @node_list = @$node;
    my $cmd;
    my %snhash;
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
        foreach my $node (@node_list)
        {
            $sn = $noderestab->getNodeAttribs($node, [$snattribute]);
            if ($sn and $sn->{$snattribute})
            {    # if service node defined
                my $key = $sn->{$snattribute};
                push @{$snhash{$key}}, $node;
            }
            else
            {    # use site.master
                push @{$snhash{$master}}, $node;
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
            foreach my $node (@node_list)
            {
                $sn =
                  $noderestab->getNodeAttribs($node, [$service, $snattribute]);
                if ($sn and $sn->{$service})
                {

                    # see if both  MN and Node address in attribute
                    my ($msattr, $nodeattr) = split ',', $sn->{$service};
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
                    if ($sn and $sn->{$snattribute})    # if it exists
                    {
                        my $key = $sn->{$snattribute};
                        push @{$snhash{$key}}, $node;
                    }
                    else
                    {                                   # use site.master
                        push @{$snhash{$master}}, $node;
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

                $nodehmtab = xCAT::Table->new('nodehm');
                unless ($nodehmtab)    # no nodehm table default to site->master
                {
                    xCAT::MsgUtils->message('I',
                                            "Unable to open nodehm table.\n");

                    # use service node
                    foreach my $node (@node_list)
                    {
                        $sn =
                          $noderestab->getNodeAttribs($node, [$snattribute]);
                        if ($sn)
                        {
                            my $key = $sn->{$snattribute};
                            push @{$snhash{$key}}, $node;
                        }
                        else
                        {    # no service node use master
                            push @{$snhash{$master}}, $node;
                        }
                    }
                    $nodehmtab->close;
                    return \%snhash;
                }

                # can read the nodehm table
                foreach my $node (@node_list)
                {
                    $sn = $nodehmtab->getNodeAttribs($node, ['conserver']);
                    if ($sn and $sn->{'conserver'})
                    {

                        # see if both  MN and Node address in attribute
                        my ($msattr, $nodeattr) = split ',', $sn->{'conserver'};
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
                    {                         # use service node
                        $sn =
                          $noderestab->getNodeAttribs($node, [$snattribute]);
                        if ($sn and $sn->{$snattribute})
                        {
                            my $key = $sn->{$snattribute};
                            push @{$snhash{$key}}, $node;
                        }
                        else
                        {                     # no service node use master
                            push @{$snhash{$master}}, $node;
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
    my $servicenodetab = xCAT::Table->new('servicenode',-create=>1);
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

=head3   Version 
    Returns the Version of the release, to be used for the version flag on 
    each command 
    Arguments:
        None 
    Returns:
        version number 
    Globals:
        none
    Error:
    Example:
        my $version= xCAT::Version();
#-------------------------------------------------------------------------------
sub Version 
{
my $version="Version 2.1";
    return $version;
}
1;
