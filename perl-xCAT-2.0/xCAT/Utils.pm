#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Utils;
use xCAT::Table;
use xCAT::Schema;
use Data::Dumper;
use xCAT::NodeRange;

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
	   $::RUNCMD_RC
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
    if (!$xCAT::Utils::NO_MESSAGES)
    {
        xCAT::MsgUtils->message("V", "Running Command: $cmd\n");

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
            if (!$xCAT::Utils::NO_MESSAGES)
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
1;
