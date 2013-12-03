#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Utils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
        use lib "/usr/opt/perl5/lib/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/5.8.2";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2";
}

use lib "$::XCATROOT/lib/perl";
# do not put a use or require for  xCAT::Table here. Add to each new routine
# needing it to avoid reprocessing of user tables ( ExtTab.pm) for each command call 
use POSIX qw(ceil);
use File::Path;
use Socket;
use strict;
use Symbol;
use Digest::SHA1 qw/sha1/;
use IPC::Open3;
use IO::Select;
use xCAT::GlobalDef;
require xCAT::RemoteShellExp;
use warnings "all";
require xCAT::InstUtils;
require xCAT::NetworkUtils;
require xCAT::Schema;
#require Data::Dumper;
require xCAT::NodeRange;
require xCAT::Version;
require DBI;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(genpassword runcmd3);

my $utildata; #data to persist locally
#--------------------------------------------------------------------------------

=head1    xCAT::Utils

=head2    Package Description

This program module file, is a set of utilities used by xCAT commands.

=cut

#-------------------------------------------------------------

=head3 genUUID
    Returns an RFC 4122 compliant UUIDv4 or UUIDv1
    Arguments:
        mac: If requesting a UUIDv1, the mac to use to base it upon
    Returns:
        string representation of a UUDv4, 
            for example: f16196d1-7534-41c1-a0ae-a9633b030583
            for example: f16196d1-7534-41c1-a0ae-a9633b030583

=cut

#-------------------------------------------------------
sub genUUID
{

    #UUIDv4 has 6 fixed bits and 122 random bits
    #Though a UUID of this form is not guaranteed to be unique absolutely,
    #the chances of a cluster the size of the entire internet generating
    #two identical UUIDs is 4 in 10 octillion.
    my %args = @_;
    if ($args{mac}) { #if a mac address was supplied, generate a uuidv1 instead
        use Math::BigInt;
        no warnings 'portable';
        use Time::HiRes qw/gettimeofday/;
        my $sec;
        my $usec;
        ($sec,$usec) = gettimeofday();
        my $uuidtime = Math::BigInt->new($sec);
        $uuidtime->bmul('10000000');
        $uuidtime->badd($usec*10);
        $uuidtime->badd('0x01B21DD213814000');
        my $timelow=$uuidtime->copy();
        $timelow->band('0xffffffff');# get lower 32bit
        my $timemid=$uuidtime->copy();
        $timemid->band('0xffff00000000');
        my $timehigh=$uuidtime->copy();
        $timehigh->band('0xffff000000000000');
        $timemid->brsft(32);
        $timehigh->brsft(48);
        $timehigh->bior('0x1000'); #add in version, don't bother stripping out the high bits since by the year 5236, none of this should matter
        my $clockseq=rand(8191); #leave the top three bits alone.  We could leave just top two bits, but it's unneeded
        #also, randomness matters very little, as the time+mac is here
        $clockseq = $clockseq | 0x8000; #RFC4122 variant
        #time to assemble...
        $timelow = $timelow->bstr();
        $usec=$timelow == 0; # doing numeric comparison induces perl to 'int'-ify it.  Safe at this point as the subpieces are all sub-32 bit now
        #assign to $usec the result so that perl doesn't complain about this trickery
        $timemid = $timemid->bstr();
        $usec=$timemid == 0;
        $timehigh = $timehigh->bstr();
        $usec=$timehigh == 0;
        my $uuid=sprintf("%08x-%04x-%04x-%04x-",$timelow,$timemid,$timehigh,$clockseq);
        my $mac = $args{mac};
        $mac =~ s/://g;
        $mac = lc($mac);
        $uuid .= $mac;
        return $uuid;
    } elsif ($args{url}) { #generate a UUIDv5 from URL
        #6ba7b810-9dad-11d1-80b4-00c04fd430c8 is the uuid for URL namespace
        my $sum = sha1('6ba7b810-9dad-11d1-80b4-00c04fd430c8'.$args{url});
        my @data = unpack("C*",$sum);
        splice @data,16;
        $data[6] = $data[6] & 0xf;
        $data[6] = $data[6] | (5<<4);
        $data[8] = $data[8] & 127;
        $data[8] = $data[8] | 64;
        my $uuid = unpack("H*",pack("C*",splice @data,0,4));
        $uuid .= "-". unpack("H*",pack("C*",splice @data,0,2));
        $uuid .= "-". unpack("H*",pack("C*",splice @data,0,2));
        $uuid .= "-". unpack("H*",pack("C*",splice @data,0,2));
        $uuid .= "-". unpack("H*",pack("C*",@data));
        return $uuid;
    }
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

=head3    get_OS_VRMF

    Arguments:
        none
    Returns:
        v.r.m.f  - if success
        undef - if error
    Example:
         my $osversion = xCAT::Utils->get_OS_VRMF();
    Comments:
        Only implemented for AIX for now
=cut

#-------------------------------------------------------------------------------
sub get_OS_VRMF
{
	my $version;
	if (xCAT::Utils->isAIX()) {
		my $cmd = "/usr/bin/lslpp -cLq bos.rte";
		my $output = xCAT::Utils->runcmd($cmd);
		chomp($output);

		# The third field in the lslpp output is the VRMF
		$version = (split(/:/, $output))[2];

		# not sure if the field would ever contain more than 4 parts?
		my ($v1, $v2, $v3, $v4, $rest) = split(/\./, $version);
		$version = join(".", $v1, $v2, $v3, $v4); 
	}
	return (length($version) ? $version : undef);
}

#----------------------------------------------------------------------------

=head3    testversion

        Compare version1 and version2 according to the operator and
        return True or False.

        Arguments:
                $version1
                $operator
                $version2
                $release1
                $release2
        Returns:
                True or False

        Example:
                if (ArchiveUtils->testversion ( $ins_ver,
												"<",
                                                $req_ver,
                                                $ins_rel,
                                                $req_rel)){ blah; }

        Comments:

=cut

#-------------------------------------------------------------------------------
sub testversion
{
    my ($class, $version1, $operator, $version2, $release1, $release2) = @_;

	my @a1 = split(/\./, $version1);
    my @a2 = split(/\./, $version2);
    my $len = (scalar(@a1) > scalar(@a2) ? scalar(@a1) : scalar(@a2));
    $#a1 = $len - 1;  # make the arrays the same length before appending release
    $#a2 = $len - 1;
    push @a1, split(/\./, $release1);
    push @a2, split(/\./, $release2);
    $len = (scalar(@a1) > scalar(@a2) ? scalar(@a1) : scalar(@a2));
    my $num1 = '';
    my $num2 = '';

    for (my $i = 0 ; $i < $len ; $i++)
    {
        my ($d1) = $a1[$i] =~ /^(\d*)/;    # remove any non-numbers on the end
        my ($d2) = $a2[$i] =~ /^(\d*)/;

        my $diff = length($d1) - length($d2);
        if ($diff > 0)                     # pad d2
        {
            $num1 .= $d1;
            $num2 .= ('0' x $diff) . $d2;
        }
		elsif ($diff < 0)                  # pad d1
        {
            $num1 .= ('0' x abs($diff)) . $d1;
            $num2 .= $d2;
        }
        else   # they are the same length
        {
            $num1 .= $d1;
            $num2 .= $d2;
        }
    }

    # Remove the leading 0s or perl will interpret the numbers as octal
    $num1 =~ s/^0+//;
    $num2 =~ s/^0+//;

    #SLES Changes ??
    # if $num1="", the "eval '$num1 $operator $num2'" will fail. 
	#	So MUST BE be sure that $num1 is not a "".
    if (length($num1) == 0) { $num1 = 0; }
    if (length($num2) == 0) { $num2 = 0; }
	#End of SLES Changes

    if ($operator eq '=') { $operator = '=='; }
    my $bool = eval "$num1 $operator $num2";

	if (length($@))
    {
		# error msg ?
	}

	return $bool;
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
            #if ($_) { $_->disconnect(); }
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
    $version = xCAT::Version->Version();
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
    require xCAT::Table;
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
	    an array of all define node groups from the nodelist and nodegroup
            table
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
    require xCAT::Table;
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
    # now read the nodegroup table
    if ($nodelisttab = xCAT::Table->new("nodegroup"))
     {
         my @attribs = ("groupname");
         @grouplist = $nodelisttab->getAllAttribs(@attribs);
 
         # build a distinct list of unique group names
         foreach my $group (@grouplist)
         {
             my $groupname = $group->{groupname};
             if (!grep(/$groupname/, @distinctgroups))
             {    # not already in list
                 push @distinctgroups, $groupname;
             }
         }
         $nodelisttab->close;
     }
     else
     {
         xCAT::MsgUtils->message("E", " Could not read the nodegroup table\n");
     }

    return @distinctgroups;
}

#-----------------------------------------------------------------------

=head3
 list_nodes_in_nodegroups

	Arguments:  nodegroup

	Returns:
	    an array of all define nodes in the node group

	Globals:
		none
	Error:
		undef
	Example:
	   @nodes=xCAT::Utils->list_nodes_in_nodegroups($group);
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
 isMemberofGroup 

	Arguments:  node,group

	Returns:
	   1 = is  a member
           0 = not a member 

	Globals:
		none
	Error:
		undef
	Example:
	   $ismember=xCAT::Utils->isMemberofGroup($node,$group);
	Comments:
		none

=cut

#------------------------------------------------------------------------
sub isMemberofGroup 
{
    my ($class, $node,$group ) = @_;
    my $ismember;
    my @nodes=xCAT::Utils->list_nodes_in_nodegroups($group); 
    if (grep(/^$node$/, @nodes)) {
      $ismember =1;
    } else {
      $ismember =0;
    }
    return $ismember;
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
    require xCAT::Table;
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
=head3    runcmd3
    Run the specified command with optional input and return stderr, stdout, and exit code

    Arguments:
        command=>[] - Array reference of command to run
        input=>[] or string - Data to send to stdin of process like piping input
    Returns:
        { exitcode => number, output=> $string, errors => string }
=cut
sub runcmd3 { #a proper runcmd that indpendently returns stdout, stderr, pid and accepts a stdin
    my %args = @_;
    my @indata;
    my $output;
    my $errors;
    if ($args{input}) {
        if (ref $args{input}) { #array ref
            @indata = @{$args{input}};
        } else { #just a string
            @indata=($args{input});
        }
    }
    my @cmd;
    if (ref $args{command}) {
        @cmd = @{$args{command}};
    } else {
        @cmd = ($args{command});
    }
    my $cmdin;
    my $cmdout;
    my $cmderr = gensym;
    my $cmdpid = open3($cmdin,$cmdout,$cmderr,@cmd);
    my $cmdsel = IO::Select->new($cmdout,$cmderr);
    foreach (@indata) {
        print $cmdin $_;
    }
    close($cmdin);
    my @handles;
    while ($cmdsel->count()) {
        @handles = $cmdsel->can_read();
        foreach (@handles) {
            my $line;
            my $done = sysread $_,$line,180;
            if ($done) {
                if ($_ eq $cmdout) {
                    $output .= $line;
                } else {
                    $errors .= $line;
                }
            } else {
                $cmdsel->remove($_);
                close($_);
            }
        }
    }
    waitpid($cmdpid,0);
    my $exitcode = $? >> 8;
    return { 'exitcode' => $exitcode, 'output' => $output, 'errors' => $errors }
}

#-------------------------------------------------------------------------------

=head3    runcmd
   Run the given cmd and return the output in an array (already chopped).
   Alternately, if this function is used in a scalar context, the output
   is joined into a single string with the newlines separating the lines.

   Arguments:
     command, exitcode, reference to output, streaming mode 
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
                $::CALLBACK= your callback (required for streaming from plugins)
		my $outref = xCAT::Utils->runcmd($cmd,-2, 1, 1); streaming

   Comments:
		   If refoutput is true, then the output will be returned as a
		   reference to an array for efficiency.


=cut

#-------------------------------------------------------------------------------
sub runcmd

{

    my ($class, $cmd, $exitcode, $refoutput, $stream) = @_;
    $::RUNCMD_RC = 0;
    # redirect stderr to stdout
    if (!($cmd =~ /2>&1$/)) { $cmd .= ' 2>&1'; }   

	if ($::VERBOSE)
	{
		# get this systems name as known by xCAT management node
		my $Sname = xCAT::InstUtils->myxCATname();
		my $msg;
		if ($Sname) {
			$msg = "Running command on $Sname: $cmd";
		} else {
			$msg="Running command: $cmd";
		}

		if ($::CALLBACK){
			my $rsp    = {};
			$rsp->{data}->[0] = "$msg\n";
			xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
		} else {
			xCAT::MsgUtils->message("I", "$msg\n");
		}
	}

    my $outref = [];
    if (!defined($stream) || (length($stream) == 0)) { # do not stream
      @$outref = `$cmd`;
    } else {  # streaming mode
      my @cmd;
      push @cmd,$cmd;
      my $rsp    = {};
      my $output;
      my $errout;
      open (PIPE, "$cmd |");
      while (<PIPE>) {
        push @$outref, $_;
        chomp;      # get rid of the newline, because the client will add one
        if ($::CALLBACK){
           $rsp->{data}->[0] = $_;
           $::CALLBACK->($rsp);
        } else {
          xCAT::MsgUtils->message("D", "$_");
        }
        #$output .= $_;
      }
      # store the return string
      #push  @$outref,$output;   
    }

    # now if not streaming process errors 
    if (($?) && (!defined($stream)))
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

         The caller to the runxcmd is responsible for filename expansion, that
         would have been done if the command was run on the command line.  
         For example,  the xdcp node1 /tmp/testfile*  /tmp command needs to 
         have the /tmp/testfile* argument expanded before call xdcp with 
         runxcmd.   The easy way to do this is to use the perl glob function.
              @files=glob "/tmp/testfile*";


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
			if ($::CALLBACK){
            	my $rsp    = {};
            	$rsp->{data}->[0] = "Running internal xCAT command: $cmd->{command}->[0] ... \n";
            	xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        	} else {
            	xCAT::MsgUtils->message("I", "Running internal xCAT command: $cmd->{command}->[0] ... \n");
			}
        }
        else
        {
			if ($::CALLBACK){
                my $rsp    = {};
                $rsp->{data}->[0] = "Running Command: $cmd\n";
                xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
            } else {
            	xCAT::MsgUtils->message("I", "Running Command: $cmd\n");
			}
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

=head3    getInstallDir

        Get location of the directory, used to hold the node deployment packages.

        Arguments:
                none
        Returns:
                path to install directory defined at site.installdir.
        Globals:
                none
        Error:
                none
        Example:
                $installdir = xCAT::Utils->getInstallDir();
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub getInstallDir
{
    # Default installdir location. Used by default in most Linux distros.
    my $installdir = "/install";

    # Try to lookup real installdir place.
    my @installdir1 = xCAT::Utils->get_site_attribute("installdir");

    # Use fetched value, incase successful database lookup.
    if ($installdir1[0])
    {
        $installdir = $installdir1[0];
    }

    return $installdir;
}

#--------------------------------------------------------------------------------

=head3    getTftpDir

        Get location of the directory, used to hold network boot files.

        Arguments:
                none
        Returns:
                path to TFTP directory defined at site.tftpdir.
        Globals:
                none
        Error:
                none
        Example:
                $tftpdir = xCAT::Utils->getTftpDir();
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub getTftpDir
{
    # Default tftpdir location. Used by default in most Linux distros.
    my $tftpdir = "/tftpboot";

    # Try to lookup real tftpdir place.
    my @tftpdir1 = xCAT::Utils->get_site_attribute("tftpdir");

    # Use fetched value, incase successful database lookup.
    if ($tftpdir1[0])
    {
        $tftpdir = $tftpdir1[0];
    }

    return $tftpdir;
}

#--------------------------------------------------------------------------------

=head3    getHomeDir

        Get the path the  user home directory from /etc/passwd.
        If /etc/passwd returns nothing ( id maybe in LDAP) then
        su - userid -c  pwd to figure out where home is
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
                $myHome = xCAT::Utils->getHomeDir($userid);
        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub getHomeDir
{
    my ($class, $username) = @_;
    my @user;
    my $homedir;
    if ($username)
    {
        @user = getpwnam($username);
    }
    else
    {
        @user = getpwuid($>);
        $username=$user[0];
    }
    
    if ($user[7]) { #  if homedir 
      $homedir= $user[7];
    } else { # no home
      $homedir=`su - $username -c  pwd`;
      chop $homedir; 
    }
    return $homedir;
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
    my $n_str    = $nodes[0];
    my $SSHdir   = getInstallDir() . "/postscripts/_ssh";
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


    #
    # if we are running as root
    # for non-root users, keys were generated in the xdsh client code
    #

    $::REMOTE_SHELL = "/usr/bin/ssh";
    my $rsp = {};

    # Get the home directory
    my $home = xCAT::Utils->getHomeDir($from_userid);
    $ENV{'DSH_FROM_USERID_HOME'} = $home;

    if ($from_userid eq "root")
    {

        # make the directory to hold keys to transfer to the nodes
        if (!-d $SSHdir)
        {
            mkpath("$SSHdir", { mode => 0755 });
        }

        # generates new keys for root, if they do not already exist
        my $rc=
     xCAT::RemoteShellExp->remoteshellexp("k",$::CALLBACK,$::REMOTE_SHELL);
       if ($rc != 0) {
            $rsp->{data}->[0] = "remoteshellexp failed generating keys.";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
       }
    }
    
    # build the shell copy script, needed Perl not always there
    # for root and non-root ids
    open(FILE, ">$home/.ssh/copy.sh")
      or die "cannot open file $home/.ssh/copy.sh\n";
    print FILE "#!/bin/sh
umask 0077
home=`egrep \"^$to_userid:\" /etc/passwd | cut -f6 -d :`
if [ $home ]; then
  dest_dir=\"\$home/.ssh\"
else
  home=`su - root -c pwd`
  dest_dir=\"\$home/.ssh\"
fi
mkdir -p \$dest_dir
cat /tmp/$to_userid/.ssh/authorized_keys >> \$home/.ssh/authorized_keys 2>&1
cp /tmp/$to_userid/.ssh/id_rsa  \$home/.ssh/id_rsa 2>&1
chmod 0600 \$home/.ssh/id_* 2>&1
rm -f /tmp/$to_userid/.ssh/* 2>&1
rmdir \"/tmp/$to_userid/.ssh\"
rmdir \"/tmp/$to_userid\" \n";

    close FILE;
    chmod 0777,"$home/.ssh/copy.sh";
    my $auth_key=0;
    my $auth_key2=0;
    if ($from_userid eq "root")
    {
       my $rc = xCAT::Utils->cpSSHFiles($SSHdir);
       if ($rc != 0)
       {    # error
                $rsp->{data}->[0] = "Error running cpSSHFiles.\n";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                return 1;

       }
       if (xCAT::Utils->isMN()) {    # if on Management Node
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
        }  # end is MN
    }
    else {    # from_userid is not root
                # build the authorized key files for non-root user
            xCAT::Utils->bldnonrootSSHFiles($from_userid);
    }

    # send the keys to the nodes   for root or some other id
    #
    # This environment variable determines whether to setup 
    # node to node ssh
    # The nodes must be checked against the site.sshbetweennodes attribute
    # For root user and not to devices only to nodes 
    if (($from_userid eq "root") && (!($ENV{'DEVICETYPE'}))) {
      my $enablenodes;
      my $disablenodes;
      my @nodelist=  split(",", $n_str);
      foreach my $n (@nodelist)
      {
         my $enablessh=xCAT::Utils->enablessh($n);
         if ($enablessh == 1) {
           $enablenodes .= $n;
           $enablenodes .= ","; 
         } else {
           $disablenodes .= $n;
           $disablenodes .= ","; 
         }

      }
      my $cmd;
      if ($enablenodes) {  # node on list to setup nodetonodessh
         chop $enablenodes;  # remove last comma
         $ENV{'DSH_ENABLE_SSH'} = "YES";
         my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$enablenodes);
         if ($rc != 0)
         {
          $rsp->{data}->[0] = "remoteshellexp failed sending keys to enablenodes.";
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

          }
      }
      if ($disablenodes) {  # node on list to setup nodetonodessh
         chop $disablenodes;  # remove last comma
         my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$disablenodes);
         if ($rc != 0)
         {
          $rsp->{data}->[0] = "remoteshellexp failed sending keys to disablenodes.";
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

         }
      }
    } else { # from user is not root or it is a device , always send private key
       $ENV{'DSH_ENABLE_SSH'} = "YES";
       my $rc=xCAT::RemoteShellExp->remoteshellexp("s",$::CALLBACK,"/usr/bin/ssh",$n_str);
       if ($rc != 0)
       {
           $rsp->{data}->[0] = "remoteshellexp failed sending keys.";
           xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);

       }
    }

    # must always check to see if worked, run test
    my @testnodes=  split(",", $nodes[0]);
    foreach my $n (@testnodes)
    {
       my $rc=
     xCAT::RemoteShellExp->remoteshellexp("t",$::CALLBACK,"/usr/bin/ssh",$n);
        if ($rc != 0)
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

           Builds authorized_keyfiles for root 

        Arguments:
               install directory path
        Returns:

        Globals:
              $::CALLBACK
        Error:

        Example:
                xCAT::Utils->cpSSHFiles($dir);

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


    if (xCAT::Utils->isMN()) {    # if on Management Node
      if (!(-e "$home/.ssh/id_rsa.pub"))   # only using rsa
      {
          $rsp->{data}->[0] = "Public key id_rsa.pub was missing in the .ssh directory.";
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
          return 1;
      }
      # copy to id_rsa public key to authorized_keys in the install directory
      my $authorized_keys = "$SSHdir/authorized_keys";
      # changed from  identity.pub
      $cmd = " cp $home/.ssh/id_rsa.pub $authorized_keys";
      xCAT::Utils->runcmd($cmd, 0);
      $rsp = {};
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
    } # end is MN

    # on MN and SN
    # make tmp directory to hold authorized_keys for node transfer
    if (!(-e "$home/.ssh/tmp")) {
      $cmd = " mkdir $home/.ssh/tmp";
      xCAT::Utils->runcmd($cmd, 0);
      $rsp = {};
      if ($::RUNCMD_RC != 0)
      {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

      }
    }
    # create authorized_keys file 
    if (xCAT::Utils->isMN()) {    # if on Management Node
      $cmd = " cp $home/.ssh/id_rsa.pub $home/.ssh/tmp/authorized_keys";
    } else {  # SN
      $cmd = " cp $home/.ssh/authorized_keys $home/.ssh/tmp/authorized_keys";
    }
    xCAT::Utils->runcmd($cmd, 0);
    $rsp = {};
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        chmod 0600, "$home/.ssh/tmp/authorized_keys";
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    return (0);
}

#--------------------------------------------------------------------------------

=head3   bldnonrootSSHFiles 

           Builds authorized_keyfiles for the non-root id
           It must not only contain the public keys for the non-root id
		   but also the public keys for root

        Arguments:
              from_userid -current id running xdsh from the command line 
        Returns:

        Globals:
              $::CALLBACK
        Error:

        Example:
                xCAT::Utils->bldnonrootSSHFiles;

        Comments:
                none

=cut

#--------------------------------------------------------------------------------

sub bldnonrootSSHFiles
{
    my ($class, $from_userid) = @_;
    my ($cmd, $rc);
    my $rsp = {};
    if ($::VERBOSE)
    {
        $rsp->{data}->[0] = "Building  SSH Keys for $from_userid";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
    }
    my $home     = xCAT::Utils->getHomeDir($from_userid);
    # Handle non-root userid may not be in /etc/passwd maybe LDAP
    if (!$home) { 
      $home=`su - $from_userid -c pwd`;
      chop $home;
    }
    my $roothome = xCAT::Utils->getHomeDir("root");
    if (xCAT::Utils->isMN()) {    # if on Management Node
      if (!(-e "$home/.ssh/id_rsa.pub"))
      {
          return 1;
      }
    }
    # make tmp directory to hold authorized_keys for node transfer
    if (!(-e "$home/.ssh/tmp")) {
      $cmd = " mkdir $home/.ssh/tmp";
      xCAT::Utils->runcmd($cmd, 0);
      $rsp = {};
      if ($::RUNCMD_RC != 0)
      {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

      }
    }
    # create authorized_key file in tmp directory for transfer
    if (xCAT::Utils->isMN()) {    # if on Management Node
      $cmd = " cp $home/.ssh/id_rsa.pub $home/.ssh/tmp/authorized_keys";
    } else {  # SN
      $cmd = " cp $home/.ssh/authorized_keys $home/.ssh/tmp/authorized_keys";
    }
    xCAT::Utils->runcmd($cmd, 0);
    $rsp = {};
    if ($::RUNCMD_RC != 0)
    {
        $rsp->{data}->[0] = "$cmd failed.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return (1);

    }
    else
    {
        chmod 0600, "$home/.ssh/tmp/authorized_keys";
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }
    if (xCAT::Utils->isMN()) {    # if on Management Node
      # if cannot access, warn and continue
      $rsp = {};
      $cmd = "cat $roothome/.ssh/id_rsa.pub >> $home/.ssh/tmp/authorized_keys";
      xCAT::Utils->runcmd($cmd, 0);
      if ($::RUNCMD_RC != 0)
      {
        $rsp->{data}->[0] = "Warning: Cannot give $from_userid root ssh authority. \n";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);

      }
      else
      {
        if ($::VERBOSE)
        {
            $rsp->{data}->[0] = "$cmd succeeded.\n";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
      }
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

=head3 get_host_from_ip
    Description:
        Get the hostname of an IP addresses. First from hosts table, and then try system resultion.
        If there is a shortname, it will be returned. Otherwise it will return long name. If the IP cannot be resolved, return undef;
        
    Arguments:
        $ip: the IP to get;
        
    Returns:  
        Return: the hostname.
For an example
        
    Globals:
        none
        
    Error:
        none
        
    Example:
        xCAT::Utils::get_host_from_ip('192.168.200.1')
    
    Comments:
=cut

#-----------------------------------------------------------------------
sub get_host_from_ip
{
    my $ip = shift;
}
 
#-------------------------------------------------------------------------------

=head3 isPingable
    Description:
        Check if an IP address can be pinged
        
    Arguments:
        $ip: the IP to ping;
        
    Returns:  
        Return: 1 indicates yes; 0 indicates no.
For an example
        
    Globals:
        none
        
    Error:
        none
        
    Example:
        xCAT::Utils::isPingable('192.168.200.1')
    
    Comments:
        none
=cut

#-----------------------------------------------------------------------
my %PING_CACHE;
sub isPingable
{
    my $ip = shift;

    my $rc;
    if ( exists $PING_CACHE{ $ip})
    {
         $rc = $PING_CACHE{ $ip};
    }
    else
    {
        my $res = `LANG=C ping -c 1 -w 5 $ip 2>&1`;
        if ( $res =~ /100% packet loss/g)
        { 
            $rc = 1;
        }
        else
        {
            $rc = 0;
        }
        $PING_CACHE{ $ip} = $rc;
    }

    return ! $rc;    
}
 
#-------------------------------------------------------------------------------

=head3 my_nets
    Description:
        Return a hash ref that contains all subnet and netmask on the mn (or sn). This subroutine can be invoked on both Linux and AIX.
        
    Arguments:
        none.
        
    Returns:  
        Return a hash ref. Each entry will be: <subnet/mask>=><existing ip>;
        For an example:
            '192.168.200.0/255.255.255.0' => '192.168.200.246';
For an example
        
    Globals:
        none
        
    Error:
        none
        
    Example:
        xCAT::Utils::my_nets().
    
    Comments:
        none
=cut
#-----------------------------------------------------------------------
sub my_nets
{
    require xCAT::Table;
    my $rethash;
    my @nets;
    my $v6net;
    my $v6ip;
    if ( $^O eq 'aix')
    {
        @nets = split /\n/, `/usr/sbin/ifconfig -a`;
    }
    else
    {
        @nets = split /\n/, `/sbin/ip addr`; #could use ip route, but to match hexnets...
    }
    foreach (@nets)
    {
        $v6net = '';
        my @elems = split /\s+/;
        unless (/^\s*inet/)
        {
            next;
        }
        my $curnet; my $maskbits;
        if ( $^O eq 'aix')
        {
            if ($elems[1] eq 'inet6')
            {
                $v6net=$elems[2];
                $v6ip=$elems[2];
                $v6ip =~ s/\/.*//; # ipv6 address 4000::99/64
                $v6ip =~ s/\%.*//; # ipv6 address ::1%1/128
            }
            else
            {
                $curnet = $elems[2];
                $maskbits = formatNetmask( $elems[4], 2, 1);
            }
        }
        else
        {
            if ($elems[1] eq 'inet6')
            {
                next; #Linux IPv6 TODO, do not return IPv6 networks on Linux for now
            }
            ($curnet, $maskbits) = split /\//, $elems[2];
        }
        if (!$v6net)
        {
            my $curmask  = 2**$maskbits - 1 << (32 - $maskbits);
            my $nown     = unpack("N", inet_aton($curnet));
            $nown = $nown & $curmask;
            my $textnet=inet_ntoa(pack("N",$nown));
            $textnet.="/$maskbits";
            $rethash->{$textnet} = $curnet;
         }
         else
         {
             $rethash->{$v6net} = $v6ip;
         }
    }


  # now get remote nets
    my $nettab = xCAT::Table->new("networks");
    my $sitetab = xCAT::Table->new("site");
    my $master = $sitetab->getAttribs({key=>'master'},'value');
    $master = $master->{value};
    my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');

    foreach(@vnets){
      my $n = $_->{net};
      my $if = $_->{mgtifname};
      my $nm = $_->{mask};
      if (!$n || !$if || !$nm)
      {
          next; #incomplete network
      }
      if ($if =~ /!remote!/) { #only take in networks with special interface
        $nm = formatNetmask($nm, 0 , 1);
        $n .="/$nm";
        #$rethash->{$n} = $if;
        $rethash->{$n} = $master;
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
    return my_ip_facing_aix( $peer) if ( $^O eq 'aix');
    my $peernumber = inet_aton($peer); #TODO: IPv6 support
    unless ($peernumber) { return undef; }
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

=head3   my_ip_facing_aix
         Returns my ip address  
         AIX only
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
sub my_ip_facing_aix
{
    my $peer = shift;
    my @nets = `ifconfig -a`;
    chomp @nets;
    foreach my $net (@nets)
    {
        my ($curnet,$netmask);
        if ( $net =~ /^\s*inet\s+([\d\.]+)\s+netmask\s+(\w+)\s+broadcast/)
        {
            ($curnet,$netmask) = ($1,$2);
        }
        elsif ($net =~ /^\s*inet6\s+(.*)$/)
        {
            ($curnet,$netmask) = split('/', $1);
        }
        else
        {
            next;
        }
        if (isInSameSubnet($peer, $curnet, $netmask, 2))
        {
            return $curnet;
        }
    }
    return undef;
}

#-------------------------------------------------------------------------------

=head3 formatNetmask
    Description:
        Transform netmask to one of 3 formats (255.255.255.0, 24, 0xffffff00).
        
    Arguments:
        $netmask: the original netmask
        $origType: the original netmask type. The valid value can be 0, 1, 2:
            Type 0: 255.255.255.0
            Type 1: 24
            Type 2: 0xffffff00
        $newType: the new netmask type, valid values can be 0,1,2, as above.
        
    Returns:  
        Return undef if any error. Otherwise return the netmask in new format.
        
    Globals:
        none
        
    Error:
        none
        
    Example:
        xCAT::Utils::formatNetmask( '24', 1, 0); #return '255.255.255.0'.
    
    Comments:
        none
=cut
#-----------------------------------------------------------------------
sub formatNetmask
{
    my $mask = shift;
    my $origType = shift;
    my $newType = shift;
    my $maskn;
    if ( $origType == 0)
    {
        $maskn = unpack("N", inet_aton($mask));
    }
    elsif ( $origType == 1)
    {
        $maskn = 2**$mask - 1 << (32 - $mask);
    }
    elsif( $origType == 2)
    {
        $maskn = hex $mask;
    }
    else
    {
        return undef;
    }

    if ( $newType == 0)
    {
        return inet_ntoa( pack('N', $maskn));
    }
    if ( $newType == 1)
    {
        my $bin = unpack ("B32", pack("N", $maskn));
        my @dup = ( $bin =~ /(1{1})0*/g);
        return scalar ( @dup);
    }
    if ( $newType == 2)
    {
        return sprintf "0x%1x", $maskn;
    }
    return undef;
}

#-------------------------------------------------------------------------------

=head3 isInSameSubnet
    Description:
        Check if 2 given IP addresses are in same subnet
        
    Arguments:
        $ip1: the first IP
        $ip2: the second IP
        $mask: the netmask, here are 3 possible netmask types, following are examples for these 3 types:
            Type 0: 255.255.255.0
            Type 1: 24
            Type 2: 0xffffff00
        $masktype: the netmask type, 3 possible values: 0,1,2, as indicated above
        
    Returns:  
        1: they are in same subnet
        2: not in same subnet
        
    Globals:
        none
        
    Error:
        none
        
    Example:
        xCAT::Utils::isInSameSubnet( '192.168.10.1', '192.168.10.2', '255.255.255.0', 0);
    
    Comments:
        none
=cut
#-----------------------------------------------------------------------
sub isInSameSubnet
{
    my $ip1 = shift;
    my $ip2 = shift;
    my $mask = shift;
    my $maskType = shift;

    $ip1 = xCAT::NetworkUtils->getipaddr($ip1);
    $ip2 = xCAT::NetworkUtils->getipaddr($ip2);

    if (!defined($ip1) || !defined($ip2))
    {
        return undef;
    }

    if ((($ip1 =~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 !~ /\d+\.\d+\.\d+\.\d+/))
      ||(($ip1 !~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 =~ /\d+\.\d+\.\d+\.\d+/)))
    {
        #ipv4 and ipv6 can not be in the same subnet
        return undef;
    }

    if (($ip1 =~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 =~ /\d+\.\d+\.\d+\.\d+/))
    {
        my $maskn;
        if ( $maskType == 0)
        {
            $maskn = unpack("N", inet_aton($mask));
        }
        elsif ( $maskType == 1)
        {
            $maskn = 2**$mask - 1 << (32 - $mask);
        }
        elsif( $maskType == 2)
        {
            $maskn = hex $mask;
        }
        else
        {
            return undef;
        }

        my $ip1n = unpack("N", inet_aton($ip1));
        my $ip2n = unpack("N", inet_aton($ip2));

        return ( ( $ip1n & $maskn) == ( $ip2n & $maskn) );
    }
    else
    {
        #ipv6
        if (($ip1 =~ /\%/) || ($ip2 =~ /\%/))
        {
            return undef;
        }
        my $netipmodule = eval {require Net::IP;};
        if ($netipmodule) {
           my $eip1 = Net::IP::ip_expand_address ($ip1,6);
           my $eip2 = Net::IP::ip_expand_address ($ip2,6);
           my $bmask = Net::IP::ip_get_mask($mask,6);
           my $bip1 = Net::IP::ip_iptobin($eip1,6);
           my $bip2 = Net::IP::ip_iptobin($eip2,6);
           if (($bip1 & $bmask) == ($bip2 & $bmask)) {
               return 1;
           }
       } # else, can not check without Net::IP module
       return undef;
     }
}
#-------------------------------------------------------------------------------

=head3 nodeonmynet - checks to see if node is on any network this server is attached to or remote network potentially managed by this system
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
    require xCAT::Table;
    my $nodetocheck = shift;
    if (scalar(@_))
    {
        $nodetocheck = shift;
    }

    my $nodeip = getNodeIPaddress( $nodetocheck );
    if (!$nodeip)
    {
        return 0;
    }
    unless ($nodeip =~ /\d+\.\d+\.\d+\.\d+/)
    {
        #IPv6
        if ( $^O eq 'aix')
        {
            my @subnets = get_subnet_aix();
            for my $net_ent (@subnets)
            {
                if ($net_ent !~ /-/)
                {
                    #ipv4
                    next;
                }
                my ($net, $interface, $mask, $flag) = split/-/ , $net_ent;
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip, $mask, $net))
                {
                    return 1;
                }
            }

        } else {
            my @v6routes = split /\n/,`ip -6 route`;
            foreach (@v6routes) {
                if (/via/ or /^unreachable/ or /^fe80::\/64/) {
                  #only count local ones, remote ones can be caught in next loop
                   #also, link-local would be a pitfall, 
                    #since more context than address is
                     #needed to determine locality
                    next;
                }
                s/ .*//; #remove all after the space
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip,'',$_)) { #bank on CIDR support
                    return 1;
                }
            }
        }
        my $nettab=xCAT::Table->new("networks");
        my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');
        foreach (@vnets) {
            if ((defined $_->{mgtifname}) && ($_->{mgtifname} eq '!remote!'))
            {
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip, $_->{mask}, $_->{net}))
                {
                    return 1;
                }
            }
        }
        return 0;
    }
    my $noden = unpack("N", inet_aton($nodeip));
    my @nets;
    if ($utildata->{nodeonmynetdata} and $utildata->{nodeonmynetdata}->{pid} == $$) {
        @nets = @{$utildata->{nodeonmynetdata}->{nets}};
    } else {
        if ( $^O eq 'aix')
        {
            my @subnets = get_subnet_aix();
            for my $net_ent (@subnets)
            {
                if ($net_ent =~ /-/) 
                {
                    #ipv6
                    next;
                }
                my @ents = split /:/ , $net_ent;
                push @nets, $ents[0] . '/' . $ents[2] . ' dev ' . $ents[1];
            }

        }
        else
        {
            @nets = split /\n/, `/sbin/ip route`;
        }
        my $nettab=xCAT::Table->new("networks");
        my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');
        foreach (@vnets) {
            if ((defined $_->{mgtifname}) && ($_->{mgtifname} eq '!remote!'))
            { #global scoped network
                my $curm = unpack("N", inet_aton($_->{mask}));
                my $bits=32;
                until ($curm & 1)  {
                    $bits--;
                    $curm=$curm>>1;
                }
                push @nets,$_->{'net'}."/".$bits." dev remote";
            }
        }
        $utildata->{nodeonmynetdata}->{pid}=$$;
        $utildata->{nodeonmynetdata}->{nets} = \@nets;
    }
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

=head3   getNodeIPaddress
    Arguments:
       Node name  only one at a time 
    Returns: ip address(s) 
    Globals:
        none
    Error:
        none
    Example:   my $c1 = xCAT::Utils::getNodeIPaddress($nodetocheck);

=cut

#-------------------------------------------------------------------------------

sub getNodeIPaddress 
{
    require xCAT::Table;
    my $nodetocheck = shift;
    my $port        = shift;
    my $nodeip;

    $nodeip = xCAT::NetworkUtils->getipaddr($nodetocheck);
    if (!$nodeip)
    {
        my $hoststab = xCAT::Table->new( 'hosts');
        my $ent = $hoststab->getNodeAttribs( $nodetocheck, ['ip'] );
        if ( $ent->{'ip'} ) {
            $nodeip = $ent->{'ip'};
        }
    }
            
    if ( $nodeip ) {
        return $nodeip;
    } else {
        return undef;
    }
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

    my @ips;
    if ( $^O eq 'aix')
    {
        @ips = split /\n/, `/usr/sbin/ifconfig -a`;
    }
    else
    {
        @ips = split /\n/, `/sbin/ip addr`;
    }
    my $comp = xCAT::NetworkUtils->getipaddr($comparison);
    if ($comp)
    {
        foreach (@ips)
        {
            if (/^\s*inet.?\s+/)
            {
                my @ents = split(/\s+/);
                my $ip   = $ents[2];
                $ip =~ s/\/.*//;
                $ip =~ s/\%.*//;
                if ($ip eq $comp)
                {
                    return 0;
                }
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
    require xCAT::Table;
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
    require xCAT::Table;
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
    require xCAT::Table;
    my ($class, $servicenodename, $serviceip) = @_;

    # list of all services from service node table
    # note this must be updated if more services added
    my @services = (
                    "nameserver", "dhcpserver", "tftpserver", "nfsserver",
                    "conserver",  "monserver",  "ldapserver", "ntpserver",
                    "ftpserver",  "ipforward"
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

    #get all potentially valid abbreviations, and pick the one that is ok
    #by 'noderange'
    my @hostnamecandidates;
    my $nodename;
    while ($hostname =~ /\./) {
        push @hostnamecandidates,$hostname;
        $hostname =~ s/\.[^\.]*//;
    }
    push @hostnamecandidates,$hostname;
    my $checkhostnames = join(',',@hostnamecandidates);
    my @validnodenames = xCAT::NodeRange::noderange($checkhostnames);
    unless (scalar @validnodenames) { #If the node in question is not in table, take output literrally.
        push @validnodenames,$hostnamecandidates[0];
    }
    #now, noderange doesn't guarantee the order, so we search the preference order, most to least specific.
    foreach my $host (@hostnamecandidates) {
        if (grep /^$host$/,@validnodenames) {
            $nodename = $host;
            last;
        }
    }
    my @ips       = xCAT::Utils->gethost_ips;
    my @hostinfo  = (@ips, $nodename);

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
    $cmd = $cmd . "| grep \"inet\"";
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
            if ($addr =~ /inet6/)
            {
               #TODO, Linux ipv6 
            }
            else
            {
                my ($inet, $addr1, $Bcast, $Mask) = split(" ", $addr);
                @ip = split(":", $addr1);
                push @ipaddress, $ip[1];
            }
        }
        else
        {    #AIX
            if ($addr =~ /inet6/)
            {
               $addr =~ /\s*inet6\s+([\da-fA-F:]+).*\/(\d+)/;
               my $v6ip = $1;
               my $v6mask = $2;
               if ($v6ip)
               {
                   push @ipaddress, $v6ip;
               }
            }
            else
            {
                my ($inet, $addr1, $netmask, $mask1, $Bcast, $bcastaddr) =
                  split(" ", $addr);
                push @ipaddress, $addr1;
            }

        }
    }
    my @names = @ipaddress;
    foreach my $ipaddr (@names)
    {
        my $hostname = xCAT::NetworkUtils->gethostname($ipaddr);
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
    my $installdir = getInstallDir();
    my $cmd;
    if (!(-e "$installdir/autoinst"))
    {
        mkdir("$installdir/autoinst");
    }

    $cmd =
      "cd $installdir/postscripts; tar -cf $installdir/autoinst/xcatpost.tar * .ssh/* _xcat/*; gzip -f $installdir/autoinst/xcatpost.tar";
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
        my $entry       = "allow:$installdir/autoinst/xcatpost.tar.gz";

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
    if ($::XCATSITEVALS{master}) {
        return $::XCATSITEVALS{master};
    }
    require xCAT::Table;
    my $Master;
    my $sitetab = xCAT::Table->new('site');
    (my $et) = $sitetab->getAttribs({key => "master"}, 'value');
    if ($et and $et->{value})
    {
        $Master = $et->{value};
    }
    else
    {
# this msg can be missleading
#        xCAT::MsgUtils->message('E',
#                           "Unable to read site table for Master attribute.\n");
    }
    return $Master;
}

#-----------------------------------------------------------------------------

=head3 get_ServiceNode

     Will get the Service node ( name or ipaddress) as known by the Management
	 Node  or Node for the input nodename or ipadress of the node 
         which can be a Service Node.
         If the input node is a Service Node then it's Service node
         is always the Management Node.

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
        Note: this rountine is important to hierarchical support in xCAT
              and used in many places.  Any changes to the logic should be
              reviewed by xCAT architecture
=cut

#-----------------------------------------------------------------------------
sub get_ServiceNode
{
    require xCAT::Table;
    my ($class, $node, $service, $request) = @_;
    my @node_list = @$node;
    my $cmd;
    my %snhash;
    my $nodehash;
    my $sn;
    my $nodehmtab;
    my $noderestab;
    my $snattribute;
    my $oshash;
    my $nodetab;
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
    # get site.master this will be the default
    my $master = xCAT::Utils->get_site_Master();  
    $noderestab = xCAT::Table->new('noderes');

    unless ($noderestab)    # no noderes table, use default site.master
    {
        xCAT::MsgUtils->message('I',
                         "Unable to open noderes table. Using site->Master.\n");

        if ($master)        # use site Master value
        {
				
            foreach my $node (@node_list)
            {               
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
                if ($rec and $rec->{$snattribute}) # use noderes.servicenode
                {
                    my $key = $rec->{$snattribute};
                    push @{$snhash{$key}}, $node;
                }
                else  # use site.master
                {    
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

=head3 getSNformattedhash

     Will call get_ServiceNode to  get the Service node ( name or ipaddress)
	 as known by the Management
	 Server or Node for the input nodename or ipadress of the node
	 It will then format the output into a single servicenode key with values
	 the list of nodes service by that service node.  This routine will 
	 break up pools of service nodes into individual node in the hash unlike
	 get_ServiceNode which leaves the pool as the key.

	 input:  Same as get_ServiceNode to call get_ServiceNode
			list of nodenames and/or node ipaddresses (array ref)
			service name
			"MN" or "Node"  determines if you want the Service node as known
			 by the Management Node  or by the node.

		recognized service names: xcat,tftpserver,
		nfsserver,conserver,monserver

        service "xcat" is used by command like xdsh that need to know the
		service node that will process the command but are not tied to a
		specific service like tftp


	 output: A hash ref  of arrays, the key is a single service node 
	          pointing to
			 a list of nodes that are serviced by that service node
	        'rra000-m'=>['blade01', 'testnode']
	        'sn1'=>['blade01', 'testnode']
	        'sn2'=>['blade01']
	        'sn3'=>['testnode']

     Globals:
        $::ERROR_RC
     Error:
         $::ERROR_RC=0 no error $::ERROR_RC=1 error

	 example: $sn =xCAT::Utils->getSNformattedhash(\@nodes,$service,"MN", $type);
	  $sn =xCAT::Utils->getSNformattedhash(\@nodes,$service,"Node", "primary");

=cut

#-----------------------------------------------------------------------------
sub getSNformattedhash
{
    my ($class, $node, $service, $request, $btype) = @_;
    my @node_list = @$node;
    my $cmd;
    my %newsnhash;

	my $type="";
	if ($btype) {
		$type=$btype;
	}

	# get the values of either the servicenode or xcatmaster attributes
    my $sn = xCAT::Utils->get_ServiceNode(\@node_list, $service, $request);

    # get the keys which are the service nodes and break apart any pool lists
    # format into individual service node keys pointing to node lists
	if ($sn)
	{
        foreach my $snkey (keys %$sn)
        {
			# split the key if pool of service nodes
			push my @tmpnodes, $sn->{$snkey};
			my @nodes;
			for my $i (0 .. $#tmpnodes) {
				for my $j ( 0 .. $#{$tmpnodes[$i]}) {
					my $check=$tmpnodes[$i][$j];
					push @nodes,$check; 
				}
			}

			# for SN backup we might only want the primary or backup
			my @servicenodes;
			my ($primary, $backup) = split /,/, $snkey;
			if (($primary) && ($type eq "primary")) {
				push @servicenodes, $primary;
			} elsif (($backup) && ($type eq "backup")) {
				push @servicenodes, $backup;
			} else {
				@servicenodes = split /,/, $snkey;
			}

			# now build new hash of individual service nodes
			foreach my $newsnkey (@servicenodes) {
				push @{$newsnhash{$newsnkey}}, @nodes;
			}
		}
	}
    return \%newsnhash;
}

#-----------------------------------------------------------------------------

=head3 toIP 

 IPv4 function to convert hostname to IP address

=cut

#-----------------------------------------------------------------------------
sub toIP
{

    if (($_[0] =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/) || ($_[0] =~ /:/))
    {
        return ([0, $_[0]]);
    }
    my $ip = xCAT::NetworkUtils->getipaddr($_[0]);
    if (!$ip)
    {
        return ([1, "Cannot Resolve: $_[0]\n"]);
    }
    return ([0, $ip]);
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
    require xCAT::Table;
    my ($class, $node) = @_;

    # reads all nodes from the service node table
    my @servicenodes;
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        return 0;

    }
    my @nodes = $servicenodetab->getAllNodeAttribs(['tftpserver'],undef,prefetchcache=>1);
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

    require xCAT::Table;
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

    require xCAT::Table;
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
    require xCAT::Table;
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
        if  (! defined ($service) || ($service eq ""))     # want all the service nodes
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

=head3    validate_ip
    Validate list of IPs
    Arguments:
        List of IPs
    Returns:
        1 - Invalid IP address in the list
        0 - IP addresses are all valid
    Globals:
        none
    Error:
        none
    Example:
        if (xCAT::Utils->validate_ip($IP)) {}
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub validate_ip
{
    my ($class, @IPs) = @_;
    foreach (@IPs) {
        my $ip = $_;
        #TODO need more check for IPv6 address
        if ($ip =~ /:/)
        {
            return([0]);
        }
        ###################################
        # Length is 4 for IPv4 addresses
        ###################################
        my (@octets) = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
        if ( scalar(@octets) != 4 ) {
            return( [1,"Invalid IP address1: $ip"] );
        }
        foreach my $octet ( @octets ) {
            if (( $octet < 0 ) or ( $octet > 255 )) {
                return( [1,"Invalid IP address2: $ip"] );
            }
        }
    }
    return([0]);
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
    my $cmd;
    my @output;
    if (-e $directory) {  # does the directory exist
      if (xCAT::Utils->isLinux()) {
        $cmd = "df -T -P $directory";
        @output= xCAT::Utils->runcmd($cmd, -1);
        foreach my $line (@output){
          my ($file_sys, $type, $blocks, $used, $avail, $per, $mount_point) = 
           split(' ', $line);
          $type=~ s/\s*//g; # remove blanks
          if ( $type =~ /^nfs/ )
          {
             return 1;
          }
        }
      } else { #AIX
       $cmd = "/usr/sysv/bin/df -n $directory";
       @output = xCAT::Utils->runcmd($cmd, -1);
       foreach my $line (@output){
          my ($dir, $colon, $type) = 
           split(' ', $line);
          $type=~ s/\s*//g; # remove blanks
          if ( $type =~ /^nfs/ )
          {
             return 1;
          }
       }
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
          eventtime -- The format is "yyyy-mm-dd hh:mm:ss".
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
        eventtime=>"2009-07-28 23:02:03",
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
    require xCAT::Table;
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
                    $currtime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                                        $year + 1900, $mon + 1, $mday, 
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

=head3   logEventsToTealDatabase
       Logs the given events info to the TEAL's 'x_tealeventlog' database 
    Arguments:
        arrayref -- A pointer to an array. Each element is a hash that contains an events.
  Returns:
       (ret code, error message) 

=cut

#-------------------------------------------------------------------------------
sub logEventsToTealDatabase
{
    require xCAT::Table;
    my $pEvents = shift;
    if (($pEvents) && ($pEvents =~ /xCAT::Utils/))
    {
        $pEvents = shift;
    }

    if (($pEvents) && (@$pEvents > 0))
    {
        my $currtime;
        my $tab = xCAT::Table->new("x_tealeventlog", -create => 1, -autocommit => 0);
        if (!$tab)
        {
            return (1, "The x_tealeventlog table cannot be opened.");
        }

        foreach my $event (@$pEvents)
        {
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
                print ' ';		# indent service output to separate it from the xcatd service output
                system $cmd;
                if ($? > 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                }
                $cmd = "service $service start";
                print ' ';		# indent service output to separate it from the xcatd service output
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
	                print ' ';		# indent service output to separate it from the xcatd service output
                    system $cmd;
                    if ($? > 0)
                    {    # error
                        xCAT::MsgUtils->message("S",
                                                "Error on command: $cmd\n");
                    }
                    $cmd = "service $service start";
                	print ' ';		# indent service output to separate it from the xcatd service output
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
	                print ' ';		# indent service output to separate it from the xcatd service output
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
                print ' ';		# indent service output to separate it from the xcatd service output
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
                print ' ';		# indent service output to separate it from the xcatd service output
                system $cmd;
                if ($? > 0)
                {                            # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd\n");
                }
                $cmd = "service $service start";
                print ' ';		# indent service output to separate it from the xcatd service output
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
       Assume it is the same as my_ip_facing...
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
    my $relfile;
    if (-f "/etc/redhat-release")
    {
        open($relfile,"<","/etc/redhat-release");
        $line = <$relfile>;
        close($relfile);
        chomp($line);
        $os = "rh";
        $ver=$line;
        $ver=~ tr/\.//;
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
        open($relfile,"<","/etc/SuSE-release");
        @lines = <$relfile>;
        close($relfile);
        chomp(@lines);
        if (grep /SLES|Enterprise Server/, @lines) { $os = "sles" }
        if (grep /SLEC/, @lines) { $os = "slec" }
        $ver = $lines[0];
        $ver =~ tr/\.//;
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;

        #print "ver: $ver\n";
    }
    elsif (-f "/etc/UnitedLinux-release")
    {

        $os = "ul";
        open($relfile,"<","/etc/UnitedLinux-release");
        $ver = <$relfile>;
        close($relfile);
        $ver =~ tr/\.//;
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;
    }
    elsif (-f "/etc/lsb-release")   # Possibly Ubuntu
    {

        if (open($relfile,"<","/etc/lsb-release")) {
            my @text = <$relfile>;
            close($relfile);
            chomp(@text);
            my $distrib_id = '';
            my $distrib_rel = '';

            foreach (@text) {
                if ( $_ =~ /^\s*DISTRIB_ID=(.*)$/ ) {
                    $distrib_id = $1;                   # last DISTRIB_ID value in file used
                } elsif ( $_ =~ /^\s*DISTRIB_RELEASE=(.*)$/ ) {
                    $distrib_rel = $1;                  # last DISTRIB_RELEASE value in file used
                }
            }

            if ( $distrib_id =~ /^(Ubuntu|"Ubuntu")\s*$/ ) {
                $os = "ubuntu";

                if ( $distrib_rel =~ /^(.*?)\s*$/ ) {       # eliminate trailing blanks, if any
                    $distrib_rel = $1;
                }
                if ( $distrib_rel =~ /^"(.*?)"$/ ) {        # eliminate enclosing quotes, if any
                    $distrib_rel = $1;
                }
                $ver = $distrib_rel;
            }
        }
    }
    $os = "$os" . "$ver";
    return ($os);
}

#-------------------------------------------------------------------------------

=head3 checkCredFiles 
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
sub checkCredFiles
{
    my $lib = shift;
    my $cb  = shift;
    my $installdir = getInstallDir();
    my $dir = "$installdir/postscripts/_xcat";
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
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
            xCAT::MsgUtils->message("I", $rsp, $cb);
        }
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Error: $dir is missing.";
        xCAT::MsgUtils->message("I", $rsp, $cb);
    }


    $dir = "$installdir/postscripts/ca";
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
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
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
    $dir = "$installdir/postscripts/hostkeys";
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
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
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
    $dir = "/etc/xcat/hostkeys";
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
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
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
    $dir = "$installdir/postscripts/_ssh";

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
            $rsp->{data}->[0] = "Error: $file is missing. Run xcatconfig (no force)";
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
    my $file = "$installdir/postscripts/etc/xcat/cfgloc";
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

#-----------------------------------------------------------------------------
=head3 acquire_lock
    Get a lock on an arbirtrary named resource.  For now, this is only across the scope of one service node/master node, an argument may be added later if/when 'global' locks are supported. This call will block until the lock is free.
    Arguments:
        A string name for the lock to acquire
    Returns:
        false on failure
        A reference for the lock being held.
=cut

sub acquire_lock {
    my $lock_name = shift;
    use File::Path;
    mkpath("/var/lock/xcat/");
    use Fcntl ":flock";
    my $tlock;
    $tlock->{path}="/var/lock/xcat/".$lock_name;
    open($tlock->{fd},">",$tlock->{path}) or return undef;
    unless ($tlock->{fd}) { return undef; }
    flock($tlock->{fd},LOCK_EX) or return undef;
    return $tlock;
}
        
#---------------------
=head3 release_lock
    Release an acquired lock
    Arguments:
        reference to lock
    Returns:
        false on failure, true on success
=cut

sub release_lock {
    my $tlock = shift;
    unlink($tlock->{path});
    flock($tlock->{fd},LOCK_UN);
    close($tlock->{fd});
}


#-----------------------------------------------------------------------------


=head3 getrootimage
    Get the directory of root image for a node; 
    Note: This subroutine only works for diskless node

    Arguments:
      $node
    Returns:
      string - directory of the root image
      undef - this is not a diskless node or the root image does not existed
    Globals:
        none
    Error:
    Example:
         my $node_syncfile=xCAT::Utils->getrootimage($node);

=cut

#-----------------------------------------------------------------------------

sub getrootimage()
{
  require xCAT::Table;
  my $node = shift;
  my $installdir = getInstallDir();
  if (($node) && ($node =~ /xCAT::Utils/))
  {
    $node = shift;
  }
      # get the os,arch,profile attributes for the nodes
  my $nodetype_t = xCAT::Table->new('nodetype');
  unless ($nodetype_t) {
    return ;
  }
  my $nodetype_v = $nodetype_t->getNodeAttribs($node, ['profile','os','arch']);
  my $profile = $nodetype_v->{'profile'};
  my $os = $nodetype_v->{'os'};
  my $arch = $nodetype_v->{'arch'};

  if ($^O eq "linux") {
    my $rootdir = "$installdir/netboot/$os/$arch/$profile/rootimg/";
    if (-d $rootdir) {
      return $rootdir;
    } else {
      return undef;
    }
  } else {
    # For AIX
  }
}

#----------------------------------------------------------------------------

=head3  parse_selection_string
        Parse the selection string and 
        write the parsed result into %wherehash

        Arguments:
            $ss_ref - selection string array from -w flag
            \%wherehash - selection string hash %::WhereHash
        Returns:
            0 - parse successfully
            1 - parse failed
        Globals:
            %wherehash

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub parse_selection_string()
{
    my ($class, $ss_ref, $wherehash_ref) = @_;

    # selection string is specified with one or multiple -w flags
    # stored in an array
    foreach my $m (@{$ss_ref})
    {
        my $attr;
        my $val;
        my $matchtype;
        if ($m =~ /^[^=]*\==/) { #attr==val
            ($attr, $val) = split /==/,$m,2;
            $matchtype='match';
        } elsif ($m =~ /^[^=]*=~/) { #attr=~val
            ($attr, $val) = split /=~/,$m,2;
            $val =~ s/^\///;
            $val =~ s/\/$//;
            $matchtype='regex';
        } elsif ($m =~ /^[^=]*\!=/) { #attr!=val
             ($attr,$val) = split /!=/,$m,2;
             $matchtype='natch';
        } elsif ($m =~ /[^=]*!~/) { #attr!~val
            ($attr,$val) = split /!~/,$m,2;
            $val =~ s/^\///;
            $val =~ s/\/$//;
            $matchtype='negex';
        } elsif ($m =~ /^[^=]*=[^=]+$/) { # attr=val is the same as attr==val
            ($attr, $val) = split /=/,$m,2;
            $matchtype='match';
        } else {
           return 1;
        }

        if (!defined($attr) || !defined($val))
        {
            return 1;
        }

        $wherehash_ref->{$attr}->{'val'} = $val;
        $wherehash_ref->{$attr}->{'matchtype'} = $matchtype;
    }
    return 0;
}

#----------------------------------------------------------------------------

=head3  selection_string_match
        Check whether a node matches the selection string 
        defined in hash %wherehash

        Arguments:
            \%objhash - the hash contains the objects definition
            $objname - the object name
            $wherehash_ref - the selection string hash
        Returns:
            0 - NOT match
            1 - match
        Globals:
            %wherehash

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub selection_string_match()
{
     my ($class, $objhash_ref, $objname, $wherehash_ref) = @_;
       
     my %wherehash = %$wherehash_ref;
     my $match = 1;
     foreach my $testattr (keys %wherehash) {
         # access non-exists hash entry will create an empty one
         # we should not modify the $objhash_ref
         if (exists($objhash_ref->{$objname}) && exists($objhash_ref->{$objname}->{$testattr})) { 
             if($wherehash{$testattr}{'matchtype'} eq 'match') { #attr==val or attr=val
                 if ($objhash_ref->{$objname}->{$testattr} ne $wherehash{$testattr}{'val'}) {
                     $match = 0;
                     last;
                 }
             }
             if($wherehash{$testattr}{'matchtype'} eq 'natch') { #attr!=val
                 if ($objhash_ref->{$objname}->{$testattr} eq $wherehash{$testattr}{'val'}) {
                     $match = 0;
                     last;
                 }
             }
             if($wherehash{$testattr}{'matchtype'} eq 'regex') { #attr=~val
                 if ($objhash_ref->{$objname}->{$testattr} !~ $wherehash{$testattr}{'val'}) {
                     $match = 0;
                     last;
                 }
             }
             if($wherehash{$testattr}{'matchtype'} eq 'negex') { #attr!~val
                 if ($objhash_ref->{$objname}->{$testattr} =~ $wherehash{$testattr}{'val'}) {
                     $match = 0;
                     last;
                 }
             }
        } else { #$objhash_ref->{$objname}->{$testattr} does not exist
            $match = 0;
            last;
        }
     }
     return $match;
}
#-------------------------------------------------------------------------------

=head3 check_deployment_monitoring_settings 
       Check the deployment retry monitoring settings.
    Arguments:
      $request: request hash
      $mstring: The monitoring setting string 
               specified with the -m flag for rpower or rnetboot 
    Returns:
        0 - ok
        1 - failed
    Globals:
        none 
    Example:
         my $rc=xCAT::Utils->check_deployment_monitoring_settings($opt(m))
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub check_deployment_monitoring_settings()
{
    my ($class, $request, $opt_ref) = @_;
    
    my $callback = $request->{callback};
    my @mstring = @{$opt_ref->{'m'}};
    
    # -r flag is required with -m flag
    if (!defined($opt_ref->{'t'})) {
        my $rsp={};
        $rsp->{data}->[0] = "Flag missing, the -t flag is required";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    foreach my $m (@mstring) {
        if ($m eq '') {
            #No value specified with -m flag
            next;
        }
        my $attr;
        my $val;
        if ($m =~ /[^=]*==/) {
           ($attr, $val) = split /==/,$m,2;
        } elsif ($m =~ /^[^=]*=~/) {
           ($attr, $val) = split /=~/,$m,2;
           $val =~ s/^\///;
           $val =~ s/\/$//;
        } else {
           my $rsp={};
           $rsp->{data}->[0] = "Invalid string \"$m\" specified with -m flag";
           xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        # The attr is table.column
        if ($attr !~ /\..*$/) {
            my $rsp={};
            $rsp->{data}->[0] = "Invalid attribute \"$attr\" specified with -m flag, should be table.column";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        if($val eq '') {
           my $rsp={};
           $rsp->{data}->[0] = "The value of attribute \"$attr\" can not be NULL";
           xCAT::MsgUtils->message("E", $rsp, $callback);
           return 1;
        } 
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3 generate_monsettings()
       Generate installation monitoring settings hash.
    Arguments:
      $request: request hash
      \@monnodes: nodes to be monitored
    Returns:
        \%monsettings - the ref of %monsettings hash
    Globals:
        none
    Example:
         my $monsettings_ref = xCAT::Utils->generate_monsettings($request, \@monnodes)
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub generate_monsettings()
{
    my ($class, $request, $monnodes_ref) = @_;

    my @monnodes = @$monnodes_ref;
    my $callback = $request->{callback};
    my @mstring = @{$request->{opt}->{m}};
    my %monsettings = ();

    #set default value for each attribute,
    #to avoid ugly perl syntax error
    my %defaultattrs = (
                       "timeout"        => "10",
                       "retrycount"        => "3"
                        );

    #Monitoring settings check already done in parse_args,
    #Assume it is correct.
    foreach my $m (@mstring) {
        if ($m eq '') {
           # No value specified with -m flag
           next;
        }
        my $attr;
        my $val;
        my $matchtype; 
        if ($m =~ /^[^=]*\==/) {
            ($attr, $val) = split /==/,$m,2;
            $matchtype='match';
        } elsif ($m =~ /^[^=]*=~/) {
            ($attr, $val) = split /=~/,$m,2;
            $val =~ s/^\///;
            $val =~ s/\/$//;
            $matchtype='regex';
        }
            
        #This is a table.column
        my ($tab, $col) = split '\.', $attr;
        $monsettings{'monattrs'}{$tab}{$col}{'val'} = $val;
        $monsettings{'monattrs'}{$tab}{$col}{'matchtype'} = $matchtype;
    }

    if (defined($request->{opt}->{r})) {
        $monsettings{'retrycount'} = $request->{opt}->{r};
    }
    if (defined($request->{opt}->{t})) {
        $monsettings{'timeout'} = $request->{opt}->{t};
    }

    #Set the default values
    foreach my $attr (keys %defaultattrs) {
        if ((!defined($monsettings{$attr})) || ($monsettings{$attr} eq '')) {
            $monsettings{$attr} = $defaultattrs{$attr};
        }
    }
    if(!defined($monsettings{'monattrs'}) || (scalar(keys %{$monsettings{'monattrs'}}) == 0)) {
        $monsettings{'monattrs'}{'nodelist'}{'status'}{'val'} = "booted";
        $monsettings{'monattrs'}{'nodelist'}{'status'}{'matchtype'} = "match";
    }
    
    #Initialize the %{$monsettings{'nodes'}} hash
    foreach my $node (@monnodes) {
        foreach my $tab (keys %{$monsettings{'monattrs'}}) {
            foreach my $col (keys %{$monsettings{'monattrs'}{$tab}}) {
                $monsettings{'nodes'}{$node}{'status'}{$tab}{$col} = '';
            }
        }
    }
    return \%monsettings;
}
#-------------------------------------------------------------------------------

=head3 monitor_installation
       Monitoring os installation progress.
    Arguments:
      $request: request hash
    Returns:
        0 - ok
        1 - failed
    Globals:
        none
    Example:
         my $rc=xCAT::Utils->monitor_installation($opt(m))
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub monitor_installation()
{
    require xCAT::Table;
    my ($class, $request, $monsettings) = @_;
    my $callback = $request->{callback};

    my $mstring = $request->{opt}->{m};
    #This is the first time the monitor_installation is called,

#    my $rsp={};
#    my $monnodes = join ',', @monitornodes;
#    $rsp->{data}->[0] = "Start monitoring the installation progress with settings \"$mstring\" for nodes $monnodes";
#    xCAT::MsgUtils->message("I", $rsp, $callback);

    $monsettings->{'timeelapsed'} = 0;
    while(($monsettings->{'timeelapsed'} < $monsettings->{'timeout'}) &&(scalar(keys %{$monsettings->{'nodes'}}))) {
        #polling interval is 1 minute, 
        #do not do the first check until 1 minute after the os installation starts
        sleep 60; 


        #update the timeelapsed
        $monsettings->{'timeelapsed'}++;

        my @monitornodes = keys %{$monsettings->{'nodes'}};
        # Look up tables, do not look up the same table more than once
        my %tabattrs = ();
        foreach my $tab (keys %{$monsettings->{'monattrs'}}) {
            foreach my $col (keys %{$monsettings->{'monattrs'}->{$tab}}) {
                if (!grep(/^$col$/, @{$tabattrs{$tab}})) {
                    push @{$tabattrs{$tab}}, $col;
                }
            }
        }

        foreach my $node (keys %{$monsettings->{'nodes'}}) {
            foreach my $montable (keys %tabattrs) {
                #Get the new status of the node
                my $montab_ref = xCAT::Table->new($montable);
                if ($montab_ref) {
                    my @attrs = @{$tabattrs{$montable}};
                    my $tabdata = $montab_ref->getNodesAttribs(\@monitornodes, \@attrs);
                    foreach my $attr (@{$tabattrs{$montable}}) {
                        # nodestatus changed, print a message
                        if (($monsettings->{'nodes'}->{$node}->{'status'}->{$montable}->{$attr} ne '') 
                            && ($monsettings->{'nodes'}->{$node}->{'status'}->{$montable}->{$attr} ne $tabdata->{$node}->[0]->{$attr})) {
                             my $rsp={};
                             $rsp->{data}->[0] = "$node $montable.$attr: $monsettings->{'nodes'}->{$node}->{'status'}->{$montable}->{$attr} => $tabdata->{$node}->[0]->{$attr}";
                            xCAT::MsgUtils->message("I", $rsp, $callback);
                        }
                        #set the new status
                        $monsettings->{'nodes'}->{$node}->{'status'}->{$montable}->{$attr} = $tabdata->{$node}->[0]->{$attr};
                    }
                $montab_ref->close();
             } else { #can not open the table
                 my $rsp={};
                 $rsp->{data}->[0] = "Open table $montable failed";
                 xCAT::MsgUtils->message("E", $rsp, $callback);
                 return ();
             }
         }
         #expected status??
         my $statusmatch = 1;
         foreach my $temptab (keys %{$monsettings->{'monattrs'}}) {
            foreach my $tempcol (keys %{$monsettings->{'monattrs'}->{$temptab}}) {
               my $currentstatus = $monsettings->{'nodes'}->{$node}->{'status'}->{$temptab}->{$tempcol};
               my $expectedstatus = $monsettings->{'monattrs'}->{$temptab}->{$tempcol}->{'val'};
               my $matchtype = $monsettings->{'monattrs'}->{$temptab}->{$tempcol}->{'matchtype'};
               #regular expression
               if($matchtype eq 'match') {
                   if ($currentstatus ne $expectedstatus) {
                       $statusmatch = 0;
                   }
               } elsif($matchtype eq 'regex') {
                   if ($currentstatus !~ /$expectedstatus/) { 
                       $statusmatch = 0;
                   }
               }
             } #end foreach
         } #end foreach
         if ($statusmatch == 1) {
            my $rsp={};
            $rsp->{data}->[0] = "$node: Reached the expected status";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            delete $monsettings->{'nodes'}->{$node};
         } 
 

       } #end foreach my $node
    } #end while

    if(scalar(keys %{$monsettings->{'nodes'}}) > 0)
    {
        foreach my $n (keys %{$monsettings->{'nodes'}}) {
             my $rsp={};
             $rsp->{data}->[0] = "$n: does not transit to the expected status";
             xCAT::MsgUtils->message("E",$rsp, $callback);
        }
    }
    return $monsettings;
}
#-------------------------------------------------------------------------------

=head3 get_subnet_aix 
    Description:
        To get present subnet configuration by parsing the output of 'netstat'. Only designed for AIX.
    Arguments:
        None
    Returns:
        @aix_nrn : An array with entries in format "net:nic:netmask:flag". Following is an example entry:
            9.114.47.224:en0:27:U
    Globals:
        none 
    Error:
        none
    Example:
         my @nrn =xCAT::Utils::get_subnet_aix
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub get_subnet_aix
{
    my @netstat_res = `/usr/bin/netstat -rn`;
    chomp @netstat_res;
    my @aix_nrn;
    for my $entry ( @netstat_res)
    {
#We need to find entries like:
#Destination        Gateway           Flags   Refs     Use  If   Exp  Groups
#9.114.47.192/27    9.114.47.205      U         1         1 en0
#4000::/64          link#4            UCX       1         0 en2      -      - 
        my ( $net, $netmask, $flag, $nic);
        if ( $entry =~ /^\s*([\d\.]+)\/(\d+)\s+[\d\.]+\s+(\w+)\s+\d+\s+\d+\s(\w+)/)
        {
            ( $net, $netmask, $flag, $nic) = ($1,$2,$3,$4);
            my @dotsec = split /\./, $net;
            for ( my $i = 4; $i > scalar(@dotsec); $i--)
            {
                $net .= '.0';
            }
            push @aix_nrn, "$net:$nic:$netmask:$flag" if ($net ne '127.0.0.0');
        }
        elsif ($entry =~ /^\s*([\dA-Fa-f\:]+)\/(\d+)\s+.*?\s+(\w+)\s+\d+\s+\d+\s(\w+)/)
        {
            #print "=====$entry====\n";
            ( $net, $netmask, $flag, $nic) = ($1,$2,$3,$4);
            # for ipv6, can not use : as the delimiter
            push @aix_nrn, "$net-$nic-$netmask-$flag" if ($net ne '::')
        }
    }
    return @aix_nrn;
}

#-------------------------------------------------------------------------------

=head3    isIpaddr

    returns 1 if parameter is has a valid IP address form.

    Arguments:
        dot qulaified IP address: e.g. 1.2.3.4
    Returns:
        1 - if legal IP address
        0 - if not legal IP address.
    Globals:
        none
    Error:
        none
    Example:
         if ($ipAddr) { blah; }
    Comments:
        Doesn't test if the IP address is on the network,
        just tests its form.

=cut

#-------------------------------------------------------------------------------
sub isIpaddr
{
    my $addr = shift;
    if (($addr) && ($addr =~ /xCAT::Utils/))
    {
        $addr = shift;
    }

    unless ( $addr )
    {
        return 0;
    }
    #print "addr=$addr\n";
    if ($addr !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
    {
        return 0;
    }

    if ($1 > 255 || $1 == 0 || $2 > 255 || $3 > 255 || $4 > 255)
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

#-------------------------------------------------------------------------------

=head3   getNodeNetworkCfg 
    Description:
        Get node network configuration, including "IP, hostname(the nodename),and netmask" by this node's name. 

    Arguments:
        node: the nodename
    Returns:
        Return an array, which contains (IP,hostname,gateway,netmask').
        undef - Failed to get the network configuration info
    Globals:
        none
    Error:
        none
    Example:
        my ($ip,$host,undef,$mask) = xCAT::Utils::getNodeNetworkCfg('node1');
    Comments:
        Presently gateway is always blank. Need to be improved.

=cut

#-------------------------------------------------------------------------------
sub getNodeNetworkCfg
{
    my $node = shift;

    my $nets = xCAT::Utils::my_nets();
    my $ip   = xCAT::NetworkUtils->getipaddr($node);
    my $mask = undef;
    for my $net (keys %$nets)
    {
        my $netname;
        ($netname,$mask) = split /\//, $net;
        last if ( xCAT::Utils::isInSameSubnet( $netname, $ip, $mask, 1));
    }
    return ($ip, $node, undef, xCAT::Utils::formatNetmask($mask,1,0));
}

#-------------------------------------------------------------------------------

=head3   get_unique_members 
    Description:
        Return an array which have unique members

    Arguments:
        origarray: the original array to be treated
    Returns:
        Return an array, which contains unique members.
    Globals:
        none
    Error:
        none
    Example:
        my @new_array = xCAT::Utils::get_unique_members(@orig_array);
    Comments:

=cut

#-------------------------------------------------------------------------------
sub get_unique_members
{
    my @orig_array = @_;
    my %tmp_hash = ();
    for my $ent (@orig_array)
    {
        $tmp_hash{$ent} = 1;
    }
    return keys %tmp_hash;
}

#-------------------------------------------------------------------------------

=head3   get_hdwr_ip 
    Description:
        Get hardware(CEC, BPA) IP from the hosts table, and then /etc/hosts. 

    Arguments:
        node: the nodename(cec, or bpa)
    Returns:
        Return the node IP 
        -1  - Failed to get the IP.
    Globals:
        none
    Error:
        none
    Example:
        my $ip = xCAT::Utils::get_hdwr_ip('node1');
    Comments:
        Used in FSPpower FSPflash, FSPinv.

=cut

#-------------------------------------------------------------------------------
sub get_hdwr_ip
{
    require xCAT::Table;
    my $node = shift;
    my $ip   = undef; 
    my $Rc   = undef;

    my $ip_tmp_res  = xCAT::Utils::toIP($node);
    ($Rc, $ip) = @$ip_tmp_res;
    if ( $Rc ) {
        my $hosttab  = xCAT::Table->new( 'hosts' );
        if ( $hosttab) {
            my $node_ip_hash = $hosttab->getNodeAttribs( $node,[qw(ip)]);
            $ip = $node_ip_hash->{ip};
        }
	
    }
     
    if (!$ip) {
        return undef;
    }

    return $ip;
}

#-------------------------------------------------------------------------------

=head3   updateEtcHosts
    Description:
        Add nodes and their IP addresses into /etc/hosts.
    Arguments:
        $host_ip: the hostname-IP pairs to be updated in /etc/hosts
    Returns:
        1: Succesfully. 0: Failed.
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils::updateEtcHosts(\%node_to_be_updated)

    Comments:

=cut

#-------------------------------------------------------------------------------
# Update /etc/hosts
##########################################################################
sub updateEtcHosts
{
    my $host = shift;
    my $ip = shift;
    my $fname = "/etc/hosts";
    unless ( open( HOSTS,"<$fname" )) {
        return undef;
    }
    my @rawdata = <HOSTS>;
    my @newdata = ();
    close( HOSTS );
    chomp @rawdata;

    ######################################
    # Remove old entry
    ######################################
    my $updated = 0;
    foreach my $line ( @rawdata ) {
        if ( $line =~ /^#/ or $line =~ /^\s*$/ ) {
            next;
        }
        if ( $line =~ /^\s*\Q$ip\E\s+(.*)$/ )
        {
            $host = $1;
            $updated = 1;
            last;
        }
    }
    if ( !$updated)
    {
        push @rawdata, "$ip\t$host";
    }
    ######################################
    # Rewrite file
    ######################################
    unless ( open( HOSTS,">$fname" )) {
        return undef;
    }
    for my $line (@rawdata)
    {
        print HOSTS "$line\n";
    }
    close( HOSTS );
    return [$host,$ip];
}
#-------------------------------------------------------------------------------

=head3   getDBName 
    Description:
        Returns the current database (SQLITE,DB2,MYSQL,PG) 

    Arguments:
        None 
    Returns:
        Return string.
    Globals:
        none
    Error:
        none
    Example:
		my $DBname = xCAT::Utils->get_DBName;
    Comments:

=cut

#-------------------------------------------------------------------------------
sub get_DBName
{
    my $name = "SQLITE";  # default
    my $xcatcfg;
    if (-r "/etc/xcat/cfgloc") {
      my $cfgl;
      open($cfgl,"<","/etc/xcat/cfgloc");
      $xcatcfg = <$cfgl>;
      close($cfgl);
      if ($xcatcfg =~ /^mysql:/) {
        $name="MYSQL"
      } else {
          if ($xcatcfg =~ /^DB2:/) {
             $name="DB2"
          } else {
            if ($xcatcfg =~ /^Pg:/) {
             $name="PG"
            }
          }
      }
    }
    return $name;
}

#-------------------------------------------------------------------------------

=head3  full_path
    Description:
        Convert the relative path to full path.

    Arguments:
        relpath: relative path
        cwdir: current working directory, use the cwd() if not specified
    Returns:
        Return the full path
        NULL  - Failed to get the full path.
    Globals:
        none
    Error:
        none
    Example:
        my $fp = xCAT::Utils::full_path('./test', '/home/guest');
    Comments:

=cut

#-------------------------------------------------------------------------------
sub full_path
{
    my ($class, $relpath, $cwdir) = @_;

    my $fullpath;

    if (!$cwdir) { #cwdir is not specified
        $fullpath = Cwd::abs_path($relpath);
    } else {
        $fullpath = $cwdir . "/$relpath";
    }

    return $fullpath;
}


#-------------------------------------------------------------------------------

=head3    isStateful
    returns 1 if localHost is a Stateful install 
    Arguments:
        none
    Returns:
        1 - localHost is Stateful 
        0 - localHost is not Stateful 
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isStateful()) { }
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isStateful
{
    # check to see if / is a real directory 
    my $dir = "\/";
    my $cmd = "df -P $dir ";
    my @output = xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {    # error 
        xCAT::MsgUtils->message("", " Could not determine Stateful\n");
        return 0;
    }
    foreach my $line (@output)
    {
        my ($file_sys, $blocks, $used, $avail, $cap, $mount_point) =
          split(' ', $line);
        $mount_point=~ s/\s*//g; # remove blanks
        if ($mount_point eq $dir) {
         if ( -e ($file_sys))
         {
             return 1;
         } else {
             return 0;
         }
        }
    }
   return 0; 
}

#-----------------------------------------------------------------------------

=head3    setupAIXconserver 
	
    Set AIX conserver 

=cut

#-------------------------------------------------------------------------------

=head3  setupAIXconserver 
    Description:
        Set AIX conserver
    Arguments:
        $verbose: 
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::Utils::setupAIXconserver($verbose);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub setupAIXconserver
{
    my ($class, $verbose) = @_;
    my $cmd;
    my $outref;
    my $msg;
    my $rc = 0;

    if (!-f "/usr/sbin/conserver")
    {
        $cmd = "ln -sf /opt/freeware/sbin/conserver /usr/sbin/conserver";
        $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message(
                'E',
                "Could not ln -sf /opt/freeware/sbin/conserver /usr/sbin/conserver."
                );
        }
        else 
        {  
           $msg = "ln -sf /opt/freeware/sbin/conserver /usr/sbin/conserver.";
           if( $verbose ) {
               xCAT::MsgUtils->message("I", $msg);
           }  
        }
    }
    if (!-f "/usr/bin/console")
    {
        $cmd = "ln -sf /opt/freeware/bin/console /usr/bin/console";
        $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message(
                  'E',
                  "Could not ln -sf /opt/freeware/bin/console /usr/bin/console."
                  );
        }
        else 
        {
           
           $msg = "ln -sf /opt/freeware/bin/console /usr/sbin/console.";
           if( $verbose ) {
               xCAT::MsgUtils->message("I", $msg);
           }  
        }
    }

    $cmd = "lssrc -a | grep conserver >/dev/null 2>&1";
    $outref = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        $cmd =
          "mkssys -p /opt/freeware/sbin/conserver -s conserver -u 0 -S -n 15 -f 15 -a \"-o -O1 -C /etc/conserver.cf\"";
        $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message('E', "Could not add subsystem conserver.");
        }
        else
        {
            xCAT::MsgUtils->message('I', "Added subsystem conserver.");

            # Remove old setting
            my $rmitab_cmd = 'rmitab conserver > /dev/null 2>&1';
            $rc         = system($rmitab_cmd);

            # add to the /etc/inittab file
            my $mkitab_cmd =
              'mkitab "conserver:2:once:/usr/bin/startsrc -s conserver > /dev/console 2>&1" > /dev/null 2>&1';
            $rc = system($mkitab_cmd);    # may already be there no error check
        }
    }
    else
    {                                     # conserver already a service
                                          # Remove old setting
        my $rmitab_cmd = 'rmitab conserver > /dev/null 2>&1';
        $rc         = system($rmitab_cmd);

        # make sure it is registered in /etc/inittab file
        my $mkitab_cmd =
          'mkitab "conserver:2:once:/usr/bin/startsrc -s conserver > /dev/console 2>&1" > /dev/null 2>&1';
        $rc = system($mkitab_cmd);        # may already be there no error check
    }

    # now make sure conserver is started
    $rc = xCAT::Utils->startService("conserver");
    return $rc;
}

#-------------------------------------------------------------------------------

=head3  setAppStatus
    Description:
        Set an AppStatus value for a specific application in the nodelist
        appstatus attribute for a list of nodes
    Arguments:
        @nodes
        $application
        $status
    Returns:
        Return result of call to setNodesAttribs
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils::setAppStatus(\@nodes,$application,$status);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub setAppStatus
{
    require xCAT::Table;

    my ($class, $nodes_ref, $application, $status) = @_;
    my @nodes = @$nodes_ref;

    #get current local time to set in appstatustime attribute
    my (
        $sec,  $min,  $hour, $mday, $mon,
        $year, $wday, $yday, $isdst
        )
        = localtime(time);
    my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
                           $mon + 1, $mday, $year + 1900,
                           $hour, $min, $sec);

    my $nltab = xCAT::Table->new('nodelist');
    my $nodeappstat = $nltab->getNodesAttribs(\@nodes,['appstatus']);

    my %new_nodeappstat;
    foreach my $node (keys %$nodeappstat) {
        if ( $node =~ /^\s*$/ ) { next; }  # Skip blank node names 
        my $new_appstat = "";
        my $changed = 0;

        # Search current appstatus and change if app entry exists
        my $cur_appstat = $nodeappstat->{$node}->[0]->{appstatus};
        if ($cur_appstat) {
            my @appstatus_entries = split(/,/,$cur_appstat);
            foreach my $appstat (@appstatus_entries) {
                my ($app, $stat) = split(/=/,$appstat);
                if ($app eq $application) {
                   $new_appstat .= ",$app=$status";
                   $changed = 1;
                } else {
                   $new_appstat .= ",$appstat";
                }
            }
        }
        # If no app entry exists, add it
        if (!$changed){
           $new_appstat .= ",$application=$status";
        }
        $new_appstat =~ s/^,//;
        $new_nodeappstat{$node}->{appstatus} = $new_appstat;
        $new_nodeappstat{$node}->{appstatustime} = $currtime;
    }

    return $nltab->setNodesAttribs(\%new_nodeappstat);

}



#-------------------------------------------------------------------------------

=head3  getAppStatus
    Description:
        Get an AppStatus value for a specific application from the
        nodelist appstatus attribute for a list of nodes
    Arguments:
        @nodes
        $application
    Returns:
        a hashref of nodes set to application status value
    Globals:
        none
    Error:
        none
    Example:
        my $appstatus = $xCAT::Utils::getAppStatus(\@nodes,$application);
       my $node1_status = $appstatus->{node1};
    Comments:

=cut

#-----------------------------------------------------------------------------

sub getAppStatus
{
    require xCAT::Table;

    my ($class, $nodes_ref, $application) = @_;
    my @nodes = @$nodes_ref;

    my $nltab = xCAT::Table->new('nodelist');
    my $nodeappstat = $nltab->getNodesAttribs(\@nodes,['appstatus']);

    my $ret_nodeappstat;
    foreach my $node (keys %$nodeappstat) {
        my $cur_appstat = $nodeappstat->{$node}->[0]->{appstatus};
        my $found = 0;
        if ($cur_appstat) {
            my @appstatus_entries = split(/,/,$cur_appstat);
            foreach my $appstat (@appstatus_entries) {
                my ($app, $stat) = split(/=/,$appstat);
                if ($app eq $application) {
                   $ret_nodeappstat->{$node} = $stat;
                   $found = 1;
                }
            }
        }
        # If no app entry exists, return empty
        if (!$found){
           $ret_nodeappstat->{$node} = "";
        }
    }

    return $ret_nodeappstat;

}
#-------------------------------------------------------------------------------

=head3  enableSSH 
    Description:
        Reads the site.sshbetweennodes attribute and determines
        if the input node should be enabled to ssh between nodes 
    Arguments:
        $node 
    Returns:
       1 = enable ssh
       0 = do not enable ssh 
    Globals:
        none
    Error:
        none
    Example:
        my $eable = $xCAT::Utils::enablessh($node);
    Comments:

=cut

#-----------------------------------------------------------------------------

sub enablessh 
{

    require xCAT::Table;
    my ($class, $node) = @_;
    my $enablessh=1;
    if (xCAT::Utils->isSN($node)) 
    {
             $enablessh=1;   # service nodes always enabled
    }
    else
    {

        # if not a service node we need to check, before enabling
        my $values;
	if (keys %::XCATSITEVALS) {
		$values=$::XCATSITEVALS{sshbetweennodes};
	} else {
	        my $sitetab    = xCAT::Table->new('site');
	        my $attr = "sshbetweennodes";
	        my $ref = $sitetab->getAttribs({key => $attr}, 'value');
	        if ($ref) {
            	   $values = $ref->{value};
	        }
 	}
	if ($values) {
            my @groups = split(/,/, $values);
            if (grep(/^ALLGROUPS$/, @groups))
            {
              $enablessh=1;
            }
            else
            {
                if (grep(/^NOGROUPS$/, @groups))
                {
                      $enablessh=0;
                }
                else
                {    # check to see if the node is a member of a group
                    my $ismember = 0;
                    foreach my $group (@groups)
                    {
                        $ismember = xCAT::Utils->isMemberofGroup($node, $group);
                        if ($ismember == 1)
                        {
                            last;
                        }
                    }
                    if ($ismember == 1)
                    {
                        $enablessh=1;
                    }
                    else
                    {
                        $enablessh=0;
                    }
                }
            }
        }
        else
        {    # does not exist, set default
            $enablessh=1;

        }
    }

    return $enablessh;

}

#-------------------------------------------------------------------------------

=head3    isSELINUX
    Returns:
       returns 0 if SELINUX is  enabled 
       returns 1 if SELINUX is not enabled 
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::Utils->isSELINUX()) { blah; }
    Comments:
       This is tested on Redhat,  may need more for SLES 
=cut

#-------------------------------------------------------------------------------
sub isSELINUX
{
    if (-e "/usr/sbin/selinuxenabled") {
       `/usr/sbin/selinuxenabled`;
       if ($? == 0) {
         return 0;
       } else {
         return 1;
       }
    } else {
       return 1;
    }
}

#-------------------------------------------------------------------------------


#--------------------------------------------------------------------------------
=head3    pingNodeStatus
      This function takes an array of nodes and returns their status using fping.
    Arguments:
       nodes-- an array of nodes.
    Returns:
       a hash that has the node status. The format is: 
          {alive=>[node1, node3,...], unreachable=>[node4, node2...]}
=cut
#--------------------------------------------------------------------------------
sub pingNodeStatus {
  my ($class, @mon_nodes)=@_;
  my %status=();
  my @active_nodes=();
  my @inactive_nodes=();
  if ((@mon_nodes)&& (@mon_nodes > 0)) {
    #get all the active nodes
    my $nodes= join(' ', @mon_nodes);
    my $temp=`fping -a $nodes 2> /dev/null`;
    chomp($temp);
    @active_nodes=split(/\n/, $temp);

    #get all the inactive nodes by substracting the active nodes from all.
    my %temp2;
    if ((@active_nodes) && ( @active_nodes > 0)) {
      foreach(@active_nodes) { $temp2{$_}=1};
        foreach(@mon_nodes) {
          if (!$temp2{$_}) { push(@inactive_nodes, $_);}
        }
    }
    else {@inactive_nodes=@mon_nodes;}     
  }

  $status{$::STATUS_ACTIVE}=\@active_nodes;
  $status{$::STATUS_INACTIVE}=\@inactive_nodes;
 
  return %status;
}
=head3  filter_nodes
##########################################################################
# Fliter the nodes to  specific groups
# For specific command, figure out the node lists which should be handled by blade.pm, fsp.pm or ipmi.pm
# mp group: the nodes will be handled by blade.pm
# fsp group: the nodes will be handled by fsp.pm
# bmc group: the nodes will be handled by ipmi.pm
# For rspconfig network, the NGP ppc blade will be included in the group of mp, othewise in the fsp group
# For getmacs -D, the NGP ppc blade will be included in the group of common fsp, otherwise in the mp group
# For renergy command, NGP blade will be moved to mp group
##########################################################################
=cut

sub filter_nodes{
    my ($class, $req, $mpnodes, $fspnodes, $bmcnodes, $nohandle) = @_;

    my (@nodes,@args,$cmd);
    if (defined($req->{'node'})) {
      @nodes = @{$req->{'node'}};
    } else {
      return 1;
    }
    if (defined($req->{'command'})) {
      $cmd = $req->{'command'}->[0];
    }
    if (defined($req->{'arg'})) {
      @args = @{$req->{'arg'}};
    }
    # get the nodes in the mp table
    my $mptabhash;
    my $mptab = xCAT::Table->new("mp");
    if ($mptab) {
        $mptabhash = $mptab->getNodesAttribs(\@nodes, ['mpa','nodetype']);
    }

    # get the nodes in the ppc table
    my $ppctabhash;
    my $ppctab = xCAT::Table->new("ppc");
    if ($ppctab) {
        $ppctabhash = $ppctab->getNodesAttribs(\@nodes,['hcp']);
    }

    # get the nodes in the ipmi table
    my $ipmitabhash;
    my $ipmitab = xCAT::Table->new("ipmi");
    if ($ipmitab) {
        $ipmitabhash = $ipmitab->getNodesAttribs(\@nodes,['bmc']);
    }

    my (@mp, @ngpfsp, @ngpbmc, @commonfsp, @commonbmc, @unknow);

    # if existing in both 'mpa' and 'ppc', a ngp power blade
    # if existing in both 'mpa' and 'ipmi', a ngp x86 blade
    # if only in 'ppc', a common power node
    # if only in 'ipmi', a common x86 node
    foreach (@nodes) {
        if (defined ($mptabhash->{$_}->[0]) && defined ($mptabhash->{$_}->[0]->{'mpa'})) {
            if (defined ($ppctabhash->{$_}->[0]) && defined ($ppctabhash->{$_}->[0]->{'hcp'})) {
              # flex power node
              push @ngpfsp, $_;
              next;
            } elsif (defined ($ipmitabhash->{$_}->[0]) && defined ($ipmitabhash->{$_}->[0]->{'bmc'})) {
              # flex x86 node
              push @ngpbmc, $_;
              next;
            } 
            else {
              # Non flex blade, but blade node
              push @mp, $_;
              next;
            }
        } elsif (defined ($ppctabhash->{$_}->[0]) && defined ($ppctabhash->{$_}->[0]->{'hcp'})) { 
            # common power node
            push @commonfsp, $_;
        } elsif (defined ($ipmitabhash->{$_}->[0]) && defined ($ipmitabhash->{$_}->[0]->{'bmc'})) { 
            # common bmc node
            push @commonbmc, $_;
        } else {
            push @unknow, $_;
        }
    }

    push @{$mpnodes}, @mp;#blade.pm
    push @{$fspnodes}, @commonfsp;
    push @{$bmcnodes}, @commonbmc;
    if (@args && ($cmd eq "rspconfig")) {
        if (!(grep /^(cec_off_policy|pending_power_on_side)/, @args))  {
            push @{$mpnodes}, @ngpfsp;
            if (grep /^(network=)/, @args) {
                push @{$mpnodes}, @ngpbmc;
            }    
        } else {
            push @{$fspnodes}, @ngpfsp;
        }
    } elsif($cmd eq "getmacs") {
        if (@args && (grep /^-D$/,@args)) {
          push @{$fspnodes}, @ngpfsp;
        } else { 
          push @{$mpnodes}, @ngpfsp;
        }
    } elsif ($cmd eq "rvitals") {
        if (@args && (grep /^lcds$/,@args)) {
            push @{$fspnodes},@ngpfsp;
        } else {
            push @{$mpnodes}, @ngpfsp;
        }
    } elsif ($cmd eq "renergy") {
        push @{$mpnodes}, @ngpbmc;
        push @{$mpnodes}, @ngpfsp;
    } else {
      push @{$fspnodes}, @ngpfsp;
    }

    push @{$nohandle}, @unknow;

    ## TRACE_LINE print "Nodes filter: nodetype [commp:@mp,ngpp:@ngpfsp,comfsp:@commonfsp]. mpnodes [@{$mpnodes}], fspnodes [@{$fspnodes}], bmcnodes [@{$bmcnodes}]\n";
    return 0;
}

sub version_cmp {
    my $ver_a = shift;
    if ($ver_a =~ /xCAT::Utils/)
    {
        $ver_a = shift;
    }
    my $ver_b = shift;
    my @array_a = ($ver_a =~ /([-.]|\d+|[^-.\d])/g);
    my @array_b = ($ver_b =~ /([-.]|\d+|[^-.\d])/g);

    my ($a, $b);
    my $len_a = @array_a;
    my $len_b = @array_b;
    my $len = $len_a;
    if ( $len_b < $len_a ) {
        $len = $len_b;
    }
    for ( my $i = 0; $i < $len; $i++ ) {
        $a = $array_a[$i];
        $b = $array_b[$i];
        if ($a eq $b) {
            next;
        } elsif ( $a eq '-' ) {
            return -1;
        } elsif ( $b eq '-') {
            return 1;
        } elsif ( $a eq '.' ) {
            return -1;
        } elsif ( $b eq '.' ) {
            return 1;
        } elsif ($a =~ /^\d+$/ and $b =~ /^\d+$/) {
            if ($a =~ /^0/ || $b =~ /^0/) {
                return ($a cmp $b);
            } else {
                return ($a <=> $b);
            }
        } else {
            $a = uc $a;
            $b = uc $b;
            return ($a cmp $b);
        }
    }
    return ( $len_a <=> $len_b )
}
1;
