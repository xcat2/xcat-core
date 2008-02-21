#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Utils;
use xCAT::Table;
use Socket;
use xCAT::Schema;
use Data::Dumper;
use xCAT::NodeRange;
use DBI;

#--------------------------------------------------------------------------------

=head1    xCAT::Utils

=head2    Package Description

This program module file, is a set of utilities used by xCAT commands.

=cut

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
    $req->{noderange}->[0] = $group;
    my @nodes = noderange($req->{noderange}->[0]);
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
        (my $ref) = $sitetab->getAttribs({key => $attr}, value);
        if ($ref and $ref->{value})
        {
            $values = $ref->{value};
        }
    }
    else
    {
        xCAT::MsgUtils->message("E", " Could not read the site table\n");

    }

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
    $newentry = shift;
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
    $job = shift;
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
                my %rsp;
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
    xCAT::Utils->runcmd("$::REMOTESHELL_EXPECT -k", 0);
    if ($::RUNCMD_RC != 0)
    {    # error
        my %rsp;
        $rsp->{data}->[0] = "remoteshell.expect failed generating keys.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

    }

    # Copy the keys to the directory
    my $rc = xCAT::Utils->cpSSHFiles($SSHdir);
    if ($rc != 0)
    {    # error
        my %rsp;
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
        my %rsp;
        $rsp->{data}->[0] = "remoteshell.expect failed sending keys.\n";
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
        my %rsp;
        $rsp->{data}->[0] =
          "SSH setup failed for the following nodes: $nstring.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return @badnodes;
    }
    else
    {
        my %rsp;
        $rsp->{data}->[0] = "$::REMOTE_SHELL setup is complete.\n";
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
    if ($::VERBOSE)
    {
        my %rsp;
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
    if ($::RUNCMD_RC != 0)
    {
        my %rsp;
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        if ($::VERBOSE)
        {
            my %rsp;
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    $cmd = "cp $home/.ssh/id_rsa.pub $authorized_keys2";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my %rsp;
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        if ($::VERBOSE)
        {
            my %rsp;
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    $cmd = "cat $home/.ssh/id_dsa.pub >> $authorized_keys2";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my %rsp;
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        if ($::VERBOSE)
        {
            my %rsp;
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
        return 1;
    }

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
  
  Reads the /etc/sysconfig/xcat file for the DB configuration and exports it
  in $XCATCFG
=cut

#-----------------------------------------------------------------------------
sub exportDBConfig
{

    # export the xcat database configuration
    my $configfile = "/etc/sysconfig/xcat";
    if (!($ENV{'XCATCFG'}))
    {
        if (-e ($configfile))
        {
            open(CFGFILE, "<$configfile")
              or xCAT::MsgUtils->message('S',
                                   "Cannot open $configfile for DB access. \n");
            foreach my $line (<CFGFILE>)
            {
                if (grep /XCATCFG/, $line)
                {
                    my @cfg  = split /XCATCFG=/, $line;
                    my @cfg2 = split /'/,        $cfg[1];
                    chomp $cfg2[1];
                    $ENV{'XCATCFG'} = $cfg2[1];
                    close CFGFILE;
                    last;
                }
            }
            if (!($ENV{'XCATCFG'}))
            {    # no db setup
                xCAT::MsgUtils->message('SE',
                      "/etc/sysconfig/xcat does not contain XCATCFG setup. \n");
                return 1;
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
                                       "Could not get Master for node $node\n");
                return 1;
            }

            $et = xCAT::Utils->GetNodeOSARCH($nodename);
            if (!($et->{'os'} || $et->{'arch'}))
            {
                xCAT::MsgUtils->message('S',
                                        "Could not OS/ARCH for node $node\n");
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

  Checks to see if the input service is already setup on the node by
  checking the /etc/xCATSN file for the service name. This is put in the file
  by the service.pm plugin (e.g tftp.pm,dns.pm,...)
  It then:
  Checks the database to see if the input Service should be setup on the
  input service node
  Checks the noderes to see if this service node is a service node for any 
  node in the table.  Any node that matches, it checks the service attribute
  to see if this service node is the server, or if the attribute is blank, then
  this service node is the server.
  
  Input: service nodename, service
  Output: 
        1 - setup service 
        0 - do not setupservice 
		-1 - error
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isServiceReq()) { blah; }

=cut

#-----------------------------------------------------------------------------
sub isServiceReq
{
    my ($class, $servicenodename, $service, $serviceip) = @_;

    # check if service is already setup
    `grep $service /etc/xCATSN`;
    if ($? == 0)
    {    # service is already setup
        return 0;
    }
    else
    {    # check the db to see if this service node is suppose to
            # have this service setup
        if (($service eq "dhcpserver") || ($service eq "nameservers"))
        {

            # get handle to networks table
            my $networkstab = xCAT::Table->new('networks');
            unless ($networkstab)
            {
                xCAT::MsgUtils->message('S',
                                        "Unable to open networks table.\n");
                return -1;
            }
            my $whereclause =
              "$service like '$servicenodename' or $service like '$serviceip'";
            my @netlist =
              $networkstab->getAllAttribsWhere($whereclause, 'netname',
                                               $service);
            if (@netlist)
            {
                return 1;   # found an entry in the networks table for this node
            }
        }
        else
        {

            # get handle to noderes table
            my $noderestab = xCAT::Table->new('noderes');
            unless ($noderestab)
            {
                xCAT::MsgUtils->message('S', "Unable to open noderes table.\n");
                return -1;
            }
            my $whereclause =
              "servicenode like '$servicenodename' or servicenode like '$serviceip'";
            my @nodelist =
              $noderestab->getAllAttribsWhere($whereclause, 'node', $service);
            foreach my $node (@nodelist)
            {
                if (($node->{$service} eq $servicenodename) || ($node->{$service} eq $serviceip) || ($node->{$service} eq ""))
                {
                    return 1;   # found a node using this server for the service
                }
            }
        }

        return 0;  # did not find a node using this service for this servicenode
    }

}

#-----------------------------------------------------------------------------

=head3 determinehostname  and ip address
  
  Used on the service node to figure out what hostname and ip address
  the service node is in the database
  Input: None   TODO IPV6
  Output: nodename, ipaddress 
=cut

#-----------------------------------------------------------------------------
sub determinehostname
{
    my $hostname;
    my $hostnamecmd = "/bin/hostname";
    my @thostname   = xCAT::Utils->runcmd($hostnamecmd);
    if ($? != 0)
    {    # could not get hostname
        xCAT::MsgUtils->message("S", "Error $? from hostname command\n");
        exit $?;
    }
    $hostname = $thostname[0];
    my ($hcp, $aliases, $addtype, $length, @addrs) = gethostbyname($hostname);
    my ($a, $b, $c, $d) = unpack('C4', $addrs[0]);
    my $ipaddress = $a . "." . $b ."." . $c . "." . $d;
    my @hostinfo = ($hostname, $ipaddress);
    return @hostinfo;
}

1;
