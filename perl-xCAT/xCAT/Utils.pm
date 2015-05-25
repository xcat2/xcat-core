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
	unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";
# do not put a use or require for  xCAT::Table here. Add to each new routine
# needing it to avoid reprocessing of user tables ( ExtTab.pm) for each command call 
use POSIX qw(ceil);
use File::Path;
use Socket;
use strict;
use Symbol;
my $sha1support;
if ( -f "/etc/debian_version" ){
    $sha1support = eval {require Digest::SHA; 1;};
}
else {
    $sha1support = eval { require Digest::SHA1; 1;};
}
use IPC::Open3;
use IO::Select;
use xCAT::GlobalDef;
eval {
  require xCAT::RemoteShellExp;
};
use warnings "all";
require xCAT::InstUtils;
#require xCAT::NetworkUtils;
require xCAT::Schema;
#require Data::Dumper;
require xCAT::NodeRange;
require xCAT::Version;
require DBI;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(genpassword runcmd3);

# The functions that has been moved to TableUtils.pm

# xCAT::Utils->list_all_nodes ====> xCAT::TableUtils->list_all_nodes
# xCAT::Utils->list_all_nodegroups ====> xCAT::TableUtils->list_all_nodegroups
# xCAT::Utils->bldnonrootSSHFiles ====> xCAT::TableUtils->bldnonrootSSHFiles
# xCAT::Utils->setupSSH ====> xCAT::TableUtils->setupSSH
# xCAT::Utils->cpSSHFiles ====> xCAT::TableUtils->cpSSHFiles
# xCAT::Utils->GetNodeOSARCH ====> xCAT::TableUtils->GetNodeOSARCH
# xCAT::Utils->logEventsToDatabase ====> xCAT::TableUtils->logEventsToDatabase
# xCAT::Utils->logEventsToTealDatabase ====> xCAT::TableUtils->logEventsToTealDatabase
# xCAT::Utils->setAppStatus ====> xCAT::TableUtils->setAppStatus
# xCAT::Utils->getAppStatus ====> xCAT::TableUtils->getAppStatus
# xCAT::Utils->get_site_attribute ====> xCAT::TableUtils->get_site_attribute
# xCAT::Utils->getInstallDir ====> xCAT::TableUtils->getInstallDir
# xCAT::Utils->getTftpDir ====> xCAT::TableUtils->getTftpDir
# xCAT::Utils->GetMasterNodeName ====> xCAT::TableUtils->GetMasterNodeName
# xCAT::Utils->create_postscripts_tar ====> xCAT::TableUtils->create_postscripts_tar
# xCAT::Utils->get_site_Master ====> xCAT::TableUtils->get_site_Master
# xCAT::Utils->checkCreds ====> xCAT::TableUtils->checkCreds
# xCAT::Utils->enablessh ====> xCAT::TableUtils->enablessh
# xCAT::Utils->getrootimage ====> xCAT::TableUtils->getrootimage



# The functions that has been moved to ServiceNodeUtils.pm

# xCAT::Utils->readSNInfo ====> xCAT::ServiceNodeUtils->readSNInfo
# xCAT::Utils->isServiceReq ====> xCAT::ServiceNodeUtils->isServiceReq
# xCAT::Utils->get_AllSN ====> xCAT::ServiceNodeUtils->get_AllSN
# xCAT::Utils->getSNandNodes ====> xCAT::ServiceNodeUtils->getSNandNodes
# xCAT::Utils->getSNList ====> xCAT::ServiceNodeUtils->getSNList
# xCAT::Utils->get_ServiceNode ====> xCAT::ServiceNodeUtils->get_ServiceNode
# xCAT::Utils->getSNformattedhash ====> xCAT::ServiceNodeUtils->getSNformattedhash



# The functions that has been moved to NetworkUtils.pm

# xCAT::Utils->classful_networks_for_net_and_mask ====> xCAT::NetworkUtils->classful_networks_for_net_and_mask
# xCAT::Utils->my_hexnets ====> xCAT::NetworkUtils->my_hexnets
# xCAT::Utils->get_host_from_ip ====> xCAT::NetworkUtils->get_host_from_ip (shall not be used)
# xCAT::Utils::isPingable ====> xCAT::NetworkUtils::isPingable
# xCAT::Utils::my_nets ====> xCAT::NetworkUtils::my_nets
# xCAT::Utils::my_if_netmap ====> xCAT::NetworkUtils::my_if_netmap
# xCAT::Utils->my_ip_facing ====> xCAT::NetworkUtils->my_ip_facing
# xCAT::Utils::formatNetmask ====> xCAT::NetworkUtils::formatNetmask
# xCAT::Utils::isInSameSubnet ====> xCAT::NetworkUtils::isInSameSubnet
# xCAT::Utils->nodeonmynet ====> xCAT::NetworkUtils->nodeonmynet
# xCAT::Utils::getNodeIPaddress ====> xCAT::NetworkUtils::getNodeIPaddress
# xCAT::Utils->thishostisnot ====> xCAT::NetworkUtils->thishostisnot
# xCAT::Utils->gethost_ips ====> xCAT::NetworkUtils->gethost_ips
# xCAT::Utils::get_subnet_aix ====> xCAT::NetworkUtils::get_subnet_aix
# xCAT::Utils->determinehostname ====> xCAT::NetworkUtils->determinehostname
# xCAT::Utils::toIP ====> xCAT::NetworkUtils::toIP
# xCAT::Utils->validate_ip ====> xCAT::NetworkUtils->validate_ip
# xCAT::Utils->getFacingIP ====> xCAT::NetworkUtils->getFacingIP
# xCAT::Utils->isIpaddr ====> xCAT::NetworkUtils->isIpaddr
# xCAT::Utils::getNodeNetworkCfg ====> xCAT::NetworkUtils::getNodeNetworkCfg
# xCAT::Utils::get_hdwr_ip ====> xCAT::NetworkUtils::get_hdwr_ip
# xCAT::Utils->pingNodeStatus ====> xCAT::NetworkUtils->pingNodeStatus


#--------------------------------------------------------------------------------

=head1    xCAT::Utils

=head2    Package Description

This program module file, is a set of utilities used by xCAT commands.

=cut

#-------------------------------------------------------------

=head3   clroptionvars

	- use this routine to clear GetOptions global option variables
		before calling GetOptions.

	- this may be needed because a "command" may be called twice
		from the same process - and global options may have been
		set the first time through. (ex. from a plugin using runxcmd() )

	- should really avoid global vars but this provides a quick fix
		for now

		ex.  my $rc = xCAT::Utils->clroptionvars($::opt1, $::opt2 ...)

=cut

#-------------------------------------------------------
sub clroptionvars
{
	# skip the class arg and set the rest to undef
	my $skippedclass=0;
	foreach (@_) {
		if ($skippedclass) {
			$_ = undef;
		}
		$skippedclass=1;
	}
	return 0;
}

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
    } elsif ($args{url} and $sha1support) { #generate a UUIDv5 from URL
        #6ba7b810-9dad-11d1-80b4-00c04fd430c8 is the uuid for URL namespace
        my $sum = '';
        if ( -f "/etc/debian_version" ){
            $sum = Digest::SHA::sha1('6ba7b810-9dad-11d1-80b4-00c04fd430c8'.$args{url});
        }
        else{
            $sum = Digest::SHA1::sha1('6ba7b810-9dad-11d1-80b4-00c04fd430c8'.$args{url});
        }
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
      my $hostname = `/bin/hostname`;
      chomp $hostname;
		my $msg="Running command on $hostname: $cmd";

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
      close(PIPE);  # This will set the $? properly
    }

    # now if not streaming process errors 
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

	   exitcode   - see definitions below

	   refoutput - type of output to build
         Not set - array
          1 -  reference to an array
          2 -  returns the response hash as received from the plugin.   


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
      return output as reference to an array
		my $outref = xCAT::Utils->runxcmd($cmd,$sub_req, -2, 1);
      
      return response hash from plugin .  Will not display error msg for any
      exit_code setting. 
		my $outref = xCAT::Utils->runxcmd($cmd,$sub_req, -1, 2);

   Comments:
		   If refoutput is 1, then the output will be returned as a
		   reference to an array for efficiency.

		   If refoutput is 2, then the response hash will be returned  
         as output.  runxcmd will not parse the request structure, nor
         will it display the error message despite the exit_code setting.
         The caller will need to display the error.

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
    %::xcmd_outref_hash = ();
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
    # call the plugin
    my $outref;
    if (defined ($refoutput)) {
      if ($refoutput != 2)  {
        $subreq->($req, \&runxcmd_output);
        $outref = $::xcmd_outref;
      } else {  # return response hash 
         $subreq->($req, \&runxcmd_output2); 
         $outref = $::xcmd_outref_hash;
      }
    } else { 
        $subreq->($req, \&runxcmd_output);
         $outref = $::xcmd_outref;
    }
   
    $::CALLBACK = $save_CALLBACK;    # in case the subreq call changed it
    
    if ($::RUNCMD_RC)
    {
        my $displayerror = 1;

        # Do not display error for  refoutput=2
        # we do not parse the returned structure
        if (defined ($refoutput)) {
          if ($refoutput == 2)  {
             $displayerror = 0;
          }
        }
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
    if ((defined($refoutput)) && ($refoutput == 1))
        # output is reference to array
    {
        chomp(@$outref);
        return $outref;
    }
    elsif ((defined($refoutput)) && ($refoutput == 2))
       # output is structure returned from plugin
    {
        return $outref;
    }
    elsif (wantarray)   # array
    {
        chomp(@$outref);
        return @$outref;
    }
    else   # string
    {
        my $line = join('', @$outref);
        chomp $line;
        return $line;
    }
}

#-------------------------------------------------------------------------------

=head3    runxcmd_output

   Internal subroutine for runxcmd to capture the output
	from the xCAT daemon subrequest call
	Note - only basic info, data, and error responses returned
	For more complex node or other return structures, you will need
	to write your own wrapper to subreq instead of using runxcmd.

=cut

#-------------------------------------------------------------------------------
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
    if (defined($resp->{status}))
    {
        push @$::xcmd_outref, @{$resp->{status}};
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
        if (defined($node->{error}))
        {
            if (ref(\($node->{error}->[0])) eq 'SCALAR')
            {
                $desc = $desc . ": " . $node->{error}->[0];
            }
        }
        if (defined($node->{errorcode}))
        {
            if (ref(\($node->{errorcode}->[0])) eq 'SCALAR')
            {
                $::RUNCMD_RC |=  $node->{errorcode}->[0];
            }
        }
        push @$::xcmd_outref, $desc;
    }
    if (defined($resp->{error}))
    {
      if (ref($resp->{error}) eq 'ARRAY')
      {
        push @$::xcmd_outref, @{$resp->{error}};
      } else {
        push @$::xcmd_outref, $resp->{error};
      }
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

    return 0;
}
#-------------------------------------------------------------------------------

=head3    runxcmd_output2

 Internal subroutine for runxcmd to capture the output
	from the xCAT daemon subrequest call. Returns the response hash 
=cut

#-------------------------------------------------------------------------------
sub runxcmd_output2
{
    my $resp = shift;
    if (defined($resp->{info}))
    {
        push  @{$::xcmd_outref_hash->{info}},  @{$resp->{info}};
    }
    if (defined($resp->{sinfo}))
    {
        push  @{$::xcmd_outref_hash->{sinfo}},  @{$resp->{sinfo}};
    }
    if (defined($resp->{data}))
    {
        push  @{$::xcmd_outref_hash->{data}},  @{$resp->{data}};
    }
    if (defined($resp->{status}))
    {
        push  @{$::xcmd_outref_hash->{status}},  @{$resp->{status}};
    }
    if (defined($resp->{node}))
    {
        push  @{$::xcmd_outref_hash->{node}},  @{$resp->{node}};
    }
    if (defined($resp->{error}))
    {
        push  @{$::xcmd_outref_hash->{error}},  @{$resp->{error}};
    }
    if (defined($resp->{errorcode}))
    {
        if (ref($resp->{errorcode}) eq 'ARRAY')
        {
            push  @{$::xcmd_outref_hash->{errorcode}},  @{$resp->{errorcode}};
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
    return 0 ;
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

=head3   StartService
	Supports AIX only, use startservice for Linux 
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
         this subroutine is deprecated for Linux,
         will be used as an internal function to process AIX service,
         for linux, use xCAT::Utils->startservice instead

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

=head3  osver
        Returns the os and version of the System you are running on 
    Arguments:
        $type: which type of os infor you want.  Supported values are:
               all,os,version,release
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
    my $type = shift;
    if ($type =~ /xCAT::Utils/)
    {
        $type  = shift;
    }

    my $osver = "unknown";
    my $os    = '';
    my $ver   = '';
    my $rel   = '';
    my $line  = '';
    my @lines;
    my $relfile;
  
    if (-f "/etc/os-release"){
        my $version;
        my $version_id;
        my $id;
        my $id_like;
        my $name;
        my $prettyname;
        my $verrel;
        if (open($relfile,"<","/etc/os-release")) {
                    my @text = <$relfile>;
                    close($relfile);
                    chomp(@text);
                    #print Dumper(\@text);
                    foreach my $line (@text){
                    if($line =~ /^\s*VERSION=\"?([0-9\.]+).*/){
                    $version=$1;
                    }
                    if($line =~ /^\s*VERSION_ID=\"?([0-9\.]+).*/){
                    $version_id=$1;
                    }


                    if($line =~ /^\s*ID=\"?([0-9a-z\_\-\.]+).*/){
                    $id=$1;
                    }
                    if($line =~ /^\s*ID_LIKE=\"?([0-9a-z\_\-\.]+).*/){
                    $id_like=$1;
                    }


                    if($line =~ /^\s*NAME=\"?(.*)/){
                    $name=$1;
                    }
                    if($line =~ /^\s*PRETTY_NAME=\"?(.*)/){
                    $prettyname=$1;
                    }
                    }
        }   

        $os=$id;
        if (!$os and $id_like) {
           $os=$id_like;
        }

        $verrel=$version;
        if (!$verrel and $version_id) {
           $verrel=$version_id;
        }
     
      
        if(!$name and $prettyname){
           $name=$prettyname;
        }
        
        if($os =~ /rhel/ and $name =~ /Server/i){
           $os="rhels";
        }
        
        if($verrel =~ /([0-9]+)\.?(.*)/) {
           $ver=$1;
           $rel=$2;
        }
#     print "$ver -- $rel";    
    }
    elsif (-f "/etc/redhat-release")
    {
        open($relfile,"<","/etc/redhat-release");
        $line = <$relfile>;
        close($relfile);
        chomp($line);
        $os = "rh";
        my $verrel=$line;
        $ver=$line;
        if ( $type ) {
            $verrel =~ s/[^0-9]*([0-9.]+).*/$1/;
            ($ver,$rel) = split /\./, $verrel;
        } else {
            $ver=~ tr/\.//;
            $ver =~ s/[^0-9]*([0-9]+).*/$1/;
        }
        if    ($line =~ /AS/)     { $os = 'rhas' }
        elsif ($line =~ /ES/)     { $os = 'rhes' }
        elsif ($line =~ /WS/)     { $os = 'rhws' }
        elsif ($line =~ /Server/) { 
            if ( $type ) {
                $os = 'rhels';
            } else {
                $os = 'rhserver';
            }
        } elsif ($line =~ /Client/) { 
            if ( $type ) {
                $os = 'rhel';
            } else {
                $os = 'rhclient';
            }
        }
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

        $rel = $lines[2];
        $ver =~ tr/\.//;
        $rel =~ s/[^0-9]*([0-9]+).*/$1/;

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
    elsif (-f "/etc/debian_version") #possible debian
    {
        if (open($relfile, "<", "/etc/issue")){
            $line = <$relfile>;
            if ( $line =~ /debian.*/i){
                $os = "debian";
                my $relfile1;
                open($relfile1, "<", "/etc/debian_version");
                $ver = <$relfile1>;
                close($relfile1);
            }
            close($relfile);
        }
    }
#print "xxxx $type === $rel \n";
    if ( $type and $type =~ /all/ ) {
        if ( $rel ne "") {
#    print "xxx $os-$ver-$rel  \n";
            return( "$os" . "," . "$ver" . ".$rel" );
        } else {
            return( "$os" . "," . "$ver" );
        }
    } elsif ( $type and $type =~ /os/ ) {
        return( $os );
    } elsif ( $type and $type =~ /version/ ) {
        return( $ver );
    } elsif ( $type and $type =~ /release/ ) {
        return( $rel );
    } else {
        return ("$os" . "$ver");
    }
}

#-----------------------------------------------------------------------------
=head3 acquire_lock
    Get a lock on an arbirtrary named resource.  For now, this is only across the scope of one service node/master node, an argument may be added later if/when 'global' locks are supported. This call will block until the lock is free.
    Arguments:
        lock_name: A string name for the lock to acquire
        nonblock_mode: Whether this is a non-blocking call or not. (1 non-blocking, 0 = blocking)
    Returns:
        false on failure
        A reference for the lock being held.
=cut

sub acquire_lock {
    my $class = shift;
    my $lock_name = shift;
    my $nonblock_mode = shift;

    use File::Path;
    mkpath("/var/lock/xcat/");
    use Fcntl ":flock";
    my $tlock;
    $tlock->{path}="/var/lock/xcat/".$lock_name;
    open($tlock->{fd},">",$tlock->{path}) or return undef;
    unless ($tlock->{fd}) { return undef; }

    if ($nonblock_mode){
        flock($tlock->{fd},LOCK_EX|LOCK_NB) or return undef;
    } else{
        flock($tlock->{fd},LOCK_EX) or return undef;
    }
    print {$tlock->{fd}} $$;
    $tlock->{fd}->autoflush(1);
    return $tlock;
}
        
#---------------------
=head3 release_lock
    Release an acquired lock
    Arguments:
        tlock: reference to lock
        nonblock_mode: Whether this is a non-blocking call or not.
    Returns:
        false on failure, true on success
=cut

sub release_lock {
    my $class = shift;
    my $tlock = shift;
    my $nonblock_mode = shift;

    unlink($tlock->{path});
    if($nonblock_mode){
        flock($tlock->{fd},LOCK_UN|LOCK_NB);
    } else{
        flock($tlock->{fd},LOCK_UN);
    }
    close($tlock->{fd});
}

#-------------------------------------------------------------------------------

=head3 is_locked
      Description : Try to see whether current command catagory is locked or not.
      Arguments   : action - command catagory
      Returns     :
                    1 - current command catagory already locked.
                    0 - not locked yet.
=cut

#-------------------------------------------------------------------------------
sub is_locked
{
    my $class = shift;
    my $action = shift;

    my $lock = xCAT::Utils->acquire_lock($action, 1);
    if (! $lock){
        return 1;
    }

    xCAT::Utils->release_lock($lock, 1);
    return 0;
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
        } elsif ($m =~ /^[^=]*!=/) {
           ($attr, $val) = split /!=/,$m,2;
        } elsif ($m =~ /^[^=]*!~/) {
           ($attr, $val) = split /!~/,$m,2;
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


#-------------------------------------------------------------------------------

=head3   noderangecontainsMN 
    Returns:
       returns nothing, if ManagementNode is not the input noderange 
       returns name of MN,  if Management Node is in the input noderange 
    Globals:
        none
    Error:
        none
    Input:
      array of nodes in the noderange
    Example:
    my @mn=xCAT::Utils->noderangecontainsMN($noderange);
    Comments:
=cut

#-------------------------------------------------------------------------------
sub noderangecontainsMn 
{
 my ($class, @noderange)=@_;
 # check if any node in the noderange is the Management Node return the
 # name
 my @mnames; # management node names in the database, members of __mgmtnode
 my $tab = xCAT::Table->new('nodelist');
 my @nodelist=$tab->getAllNodeAttribs(['node','groups']);
 foreach my $n (@nodelist) {
  if (defined($n->{'groups'})) {
   my @groups=split(",",$n->{'groups'});
   if ((grep (/__mgmtnode/,@groups))) {  # this is the MN
     push @mnames,$n->{'node'};
   }
  }
 }
 my @MNs;  # management node names found the noderange
 if (@mnames) { # if any Management Node defined in the database
   foreach my $mn (@mnames) {
     if (grep(/^$mn$/, @noderange)) { # if  MN in the noderange
       push @MNs, $mn;
     }
   }
   if (@MNs) { # management nodes in the noderange
       return @MNs;
   }
 }
 return;   # if no MN in the noderange, return nothing
}


# the MTM of P6 and P7 machine
my %MTM_P6P7 = (
    # P6 systems
    '7998-60X' => 1,
    '7998-61X' => 1,
    '7778-23X' => 1,
    '8203-E4A' => 1,
    '8204-E8A' => 1,
    '8234-EMA' => 1,
    '9117-MMA' => 1,
    '9119-FHA' => 1,

    # P7 systems
    '8406-70Y' => 1,
    '8406-71Y' => 1,
    '7891-73X' => 1,
    '7891-74X' => 1,
    '8231-E2B' => 1,
    '8202-E4B' => 1,
    '8231-E2B' => 1,
    '8205-E6B' => 1,
    '8233-E8B' => 1,
    '8236-E8C' => 1,
    '9117-MMB' => 1,
    '9179-MHB' => 1,
    '9119-FHB' => 1,
);

#-----------------------------------------------------------------------------

=head3   isP6P7 
	
    Check whether a MTM is a P6 or P7 machine
    Parameter: MTM of Power machine

=cut

#-------------------------------------------------------------------------------
sub isP6P7
{
    my $class = shift;
    my $mtm = shift;

    if ($class !~ /Utils/) {
        $mtm = $class; 
    }

    if (defined $MTM_P6P7{$mtm} && $MTM_P6P7{$mtm} == 1) {
        return 1;
    }

    return 0;
}

=head3  filter_nodes
##########################################################################
# Fliter the nodes to  specific groups
# For specific command, figure out the node lists which should be handled by blade.pm, fsp.pm or ipmi.pm
# mp group (argument: $mpnodes): the nodes will be handled by blade.pm
# fsp group (argument: $fspnodes): the nodes will be handled by fsp.pm
# bmc group (argument: $bmcnodes): the nodes will be handled by ipmi.pm
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

    # get the node attributes from the nodehm table
    my $nodehmhash;
    my $nodehmtab = xCAT::Table->new("nodehm");
    if ($nodehmtab) {
        $nodehmhash = $nodehmtab->getNodesAttribs(\@nodes,['mgt']);
    }

    # get the node attributes from the nodetype table
    my $nodetypehash;
    my $nodetypetab = xCAT::Table->new("nodetype");
    if ($nodetypetab) {
        $nodetypehash = $nodetypetab->getNodesAttribs(\@nodes, ['arch']);
    }

    # get the node attributes from the vpd table
    my $vpdhash,
    my $vpdtab = xCAT::Table->new("vpd");
    if ($vpdtab) {
        $vpdhash = $vpdtab->getNodesAttribs(\@nodes, ['mtm']);
    }

    my (@mp, @ngpfsp, @ngpbmc, @commonfsp, @commonbmc, @unknow, @nonppcle, @p6p7);

    # if existing in both 'mpa' and 'ppc', a ngp power blade
    # if existing in both 'mpa' and 'ipmi', a ngp x86 blade
    # if only in 'ppc', a common power node
    # if only in 'ipmi', a common x86 node
    # if in ipmi and arch =~ /ppc64/, a pp64le node
    foreach (@nodes) {
        if (defined ($mptabhash->{$_}->[0]) && defined ($mptabhash->{$_}->[0]->{'mpa'})) {
            if ($mptabhash->{$_}->[0]->{'mpa'} eq $_) {
                if (defined($nodehmhash->{$_}->[0]) && defined($nodehmhash->{$_}->[0]->{'mgt'}) && 
                    $nodehmhash->{$_}->[0]->{'mgt'} eq "blade") {
                    push @mp, $_;
                } else {
                    push @unknow, $_;
                }
                next;
            } 
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
            # whether is a Power 8 or higher with FSP
            if (defined ($vpdhash->{$_}->[0]) && defined ($vpdhash->{$_}->[0]->{'mtm'})) {
                if (isP6P7($vpdhash->{$_}->[0]->{'mtm'})) {
                    push @p6p7, $_;
                }
            }
        } elsif (defined ($ipmitabhash->{$_}->[0]) && defined ($ipmitabhash->{$_}->[0]->{'bmc'})) { 
            # common bmc node
            push @commonbmc, $_;
            # whether is a Power 8 or higher with FSP
            if (defined ($nodetypehash->{$_}->[0]) && defined ($nodetypehash->{$_}->[0]->{'arch'})) {
                if ($nodetypehash->{$_}->[0]->{'arch'} !~ /^ppc64/i) {
                    push @nonppcle, $_;
                }
            }
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
        } else {
            push @{$fspnodes}, @ngpfsp;
        }
        if (grep /^(network|textid)/, @args) {
            push @{$mpnodes}, @ngpbmc;
        } else {
            push @{$bmcnodes}, @ngpbmc;
        }
    } elsif($cmd eq "getmacs") {
        if (@args && (grep /^-D$/,@args)) {
          push @{$fspnodes}, @ngpfsp;
        } else { 
          push @{$mpnodes}, @ngpfsp;
        }
        push @{$mpnodes}, @ngpbmc;
    } elsif ($cmd eq "rvitals") {
        if (@args && (grep /^lcds$/,@args)) {
            push @{$fspnodes},@ngpfsp;
        } else {
            push @{$mpnodes}, @ngpfsp;
        }
    } elsif ($cmd eq "renergy") {
        # for renergy command, only the p6,p7 get to the general fsp.pm
        # P8 and higher will get in the energy.pm
        @{$fspnodes} = ();
        push @{$fspnodes}, @p6p7;

        # for rnergy command, only the non-ppcle nodes get to the general ipmi.pm
        # ppcle of P8 and higher will get in the energy.pm
        @{$bmcnodes} = ();
        push @{$bmcnodes}, @nonppcle;

        if (grep /^(relhistogram)/, @args) {
            push @{$bmcnodes}, @ngpbmc;
        } else {
            push @{$mpnodes}, @ngpbmc;
        }
        push @{$mpnodes}, @ngpfsp;
    } else {
      push @{$fspnodes}, @ngpfsp;
    }

    push @{$nohandle}, @unknow;

    ## TRACE_LINE print "Nodes filter: nodetype [commp:@mp,ngpp:@ngpfsp,comfsp:@commonfsp]. mpnodes [@{$mpnodes}], fspnodes [@{$fspnodes}], bmcnodes [@{$bmcnodes}]\n";
    return 0;
}

#-------------------------------------------------------------------------------
=head3   filter_nostatusupdate() 
     
    filter out the nodes which support provision status feedback from the status-nodes hash
    Returns:
       returns the filtered status-nodes hash
    Globals:
        none
    Error:
        none
    Input:
      the ref of status-nodes hash to filter
    Example:
    my $mn=xCAT::Utils->filter_nostatusupdate(\%statusnodehash);
    Comments:
=cut
#-------------------------------------------------------------------------------
sub filter_nostatusupdate{

    my ($class,$inref)=@_;
    my $nttabdata;
    my @allnodes=();
    #read "nodetype" table to get the "os" attribs for all the nodes with status "installing" or "netbooting" 
    if(exists $inref->{$::STATUS_INSTALLING}){
      push @allnodes, @{$inref->{$::STATUS_INSTALLING}};
    }
    if(exists $inref->{$::STATUS_NETBOOTING}){
      push @allnodes, @{$inref->{$::STATUS_NETBOOTING}};
    }

    my $nodetypetab = xCAT::Table->new('nodetype');
    if ($nodetypetab) {
           $nttabdata     = $nodetypetab->getNodesAttribs(\@allnodes, ['node', 'os']);
           $nodetypetab->close();
    }

    #filter out the nodes which support the node provision status feedback
    my @nodesfiltered=();
    if(exists $inref->{$::STATUS_INSTALLING}){
      map{ if($nttabdata->{$_}->[0]->{os} !~ /(fedora|rh|centos|sles|ubuntu)/) {push @nodesfiltered,$_;} } @{$inref->{$::STATUS_INSTALLING}};
      delete $inref->{$::STATUS_INSTALLING};
      if(@nodesfiltered){
        @{$inref->{$::STATUS_INSTALLING}}=@nodesfiltered;
      }
    }

    @nodesfiltered=();
    if(exists $inref->{$::STATUS_NETBOOTING}){
      map{ if($nttabdata->{$_}->[0]->{os} !~ /(fedora|rh|centos|sles|ubuntu)/) {push @nodesfiltered,$_;} } @{$inref->{$::STATUS_NETBOOTING}};
      delete $inref->{$::STATUS_NETBOOTING};
      if(@nodesfiltered){
        @{$inref->{$::STATUS_NETBOOTING}}=@nodesfiltered;
      }
    }

}

sub version_cmp {
    my $ver_a = shift;
    if ($ver_a =~ /xCAT::Utils/)
    {
        $ver_a = shift;
    }
    my $ver_b = shift;
    $ver_a =~ s/([-.]0+)+$//;
    $ver_b =~ s/([-.]0+)+$//;
    my @array_a = ($ver_a =~ /([-.]|\d+|[^-.\d]+)/g);
    my @array_b = ($ver_b =~ /([-.]|\d+|[^-.\d]+)/g);

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
#            if ($a =~ /^0/ || $b =~ /^0/) {
#                return ($a cmp $b);
#            } else {
#                return ($a <=> $b);
#            }
            if($a != $b ){
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

#--------------------------------------------------------------------------------
=head3    fullpathbin
    returns the full path of a specified binary executable file
    Arguments:
      string of the bin file name
    Returns:
      string of the full path name of the binary executable file
    Globals:
        none
    Error:
      string of the bin file name in the argument
    Example:
         my $CHKCONFIG = xCAT::Utils->fullpathbin("chkconfig");
    Comments:
        none

=cut
#--------------------------------------------------------------------------------
sub fullpathbin
{
  my $bin=shift;
  if( $bin =~ /xCAT::Utils/)
  {
     $bin=shift;
  }

  my @paths= ("/bin","/usr/bin","/sbin","/usr/sbin");
  my $fullpath=$bin;

  foreach my $path (@paths)
  {
     if (-x $path.'/'.$bin)
     {
        $fullpath= $path.'/'.$bin;
        last;
     }
  }

  return $fullpath;
}
#--------------------------------------------------------------------------------

=head3   gettimezone
    returns the name of the timezone defined on the Linux distro.
    This routine was written to replace the use of /etc/sysconfig/clock which in no
    longer supported on future Linux releases such as RHEL7.  It is suppose to be a routine
    that can find the timezone on any Linux OS or AIX.
    Arguments:
      none
    Returns:
      Name of timezone,  for example US/Eastern
    Globals:
        none
    Error:
      None
    Example:
         my $timezone = xCAT::Utils->gettimezone();
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub gettimezone
{
  my ($class) = @_;

  my $tz;
  if (xCAT::Utils->isAIX()) {
    $tz= $ENV{'TZ'};
  } else {   # all linux
        my $localtime = "/etc/localtime";
        my $zoneinfo = "/usr/share/zoneinfo";
        my $cmd = "find $zoneinfo -xtype f -exec cmp -s $localtime {} \\; -print | grep -v posix | grep -v SystemV | grep -v right | grep -v localtime ";
        my $zone_result = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
           $tz="Could not determine timezone checksum";
            return $tz;
        }
        my @zones = split /\n/, $zone_result;

        $zones[0] =~ s/$zoneinfo\///;
        if (!$zones[0]) {  # if we still did not get one, then default
                $tz = `cat /etc/timezone`;
                chomp $tz;
        } else {
             $tz=$zones[0];
        }


  }
  return $tz;


}

#--------------------------------------------------------------------------------

=head3  specialservicemgr 
    some special services cannot be processed in sysVinit, upstart and systemd framework, should be process here...
    Arguments:
      service name: 
      action:        start/stop/restart/status/enable/disable
      outputoption:  
                     1:        return a hashref with the keys:"retcode","retmsg"
                     otherwise: return retcode only
    Returns:
      
                     a hashref if $outputoption is 1,the hash structure is:
                                 {"retcode"=>(status code, 0 for running/active,1 for stopped/inactive,2 for failed)
                                  "retmsg" =>(status string, running/active/stopped/inactive/failed)
                                 }
                     the status code otherwise

                     retcode:   127 if the service specified is not processed
                                the exit code of the service operation if the service specified is processed
    
    Globals:
        none
    Error:
        none
    Example:
        my $ret=xCAT::Utils->specialservicemgr("firewall","start");
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub specialservicemgr{
    my $svcname=shift;
    my $action=shift;
    my $outputoption=shift;
    my %ret; 
 
    $ret{retcode}=127;
    if($svcname eq "firewall") 
    {

       my $cmd="type -P SuSEfirewall2 >/dev/null 2>&1";
       xCAT::Utils->runcmd($cmd,-1);
       if($::RUNCMD_RC)
       {
          $ret{retcode}=127;
          if(defined $outputoption and $outputoption == 1){
             return \%ret;
          }else{
             return $ret{retcode};
          }
       }else{
          if(($action eq "start") || ($action eq "stop")) 
          {
             $cmd="SuSEfirewall2 $action";
          }elsif($action eq "restart"){
             $cmd="SuSEfirewall2 stop;SuSEfirewall2 start";
          }elsif($action eq "disable"){
             $cmd="SuSEfirewall2 off";
          }elsif($action eq "enable"){
             $cmd="SuSEfirewall2 on";
          }elsif($action eq "status"){
             $cmd="service SuSEfirewall2_setup status";
          }else{
            
             $ret{retcode}=127;
             if(defined $outputoption and $outputoption == 1){
                return \%ret;
             }else{
                return $ret{retcode};
             }
          }
      
          $ret{retmsg}=xCAT::Utils->runcmd($cmd,-1);
          $ret{retcode}= $::RUNCMD_RC;
          if(defined $outputoption and $outputoption == 1){
             return \%ret;
          }else{
             return $ret{retcode};
          }
       }

    }

    if(defined $outputoption and $outputoption == 1){
       return \%ret;
    }else{
       return $ret{retcode};
    }
}


#--------------------------------------------------------------------------------

=head3   servicemap 
    returns the name of service unit(for systemd) or service daemon(for SYSVinit). 
    Arguments:
      $svcname: the name of the service
      $svcmgrtype: the service manager type:
                   0: SYSVinit
                   1: systemd
                   2: upstart  
    Returns:
      the name of service unit or service daemon
      undef on fail
    Globals:
        none
    Error:
      None 
    Example:
         my $svc = xCAT::Utils->servicemap($svcname,1);
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub servicemap{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;
  }
  
  my $svcmgrtype=shift;


  #hash structure: 
  #"service name $svcname" =>{
  #"service manager name(SYSVinit/systemd) $svcmgrtype" 
  #=> ["list of possible service file names for the specified $svcname under the specified $svcmgrtype "]
  # }
  #
  #
  # if there are more than 1 possible service names for a service among 
  # different os distributions and os releases, the service should be 
  # specified in %svchash with structure 
  # (general service name) => {list of possible service names}
  #
  my %svchash=(
     "dhcp"  =>    ["dhcp3-server","dhcpd","isc-dhcp-server"],
     "nfs"   =>    ["nfsserver","nfs-server","nfs","nfs-kernel-server"],
     "named" =>    ["named","bind9"],
     "syslog" =>   ["syslog","syslogd","rsyslog"],
     "firewall" => ["iptables","firewalld","ufw"],
     "http" =>     ["apache2","httpd"],
     "ntpserver" =>["ntpd","ntp"],
     "mysql" =>    ["mysqld","mysql"],
  );

  my $path=undef;
  my $postfix="";
  my $retdefault=$svcname;
  if($svcmgrtype == 0){
     $path="/etc/init.d/";
  }elsif ($svcmgrtype == 1){
     $path="/usr/lib/systemd/system/";
     $postfix=".service";
#     $retdefault=$svcname.".service";
  }elsif ($svcmgrtype == 2){
     $path="/etc/init/";
     $postfix=".conf";
  }

  
  my $ret=undef;
  if($svchash{$svcname}){
    foreach my $file (@{$svchash{$svcname}}){
       if(-e $path.$file.$postfix ){
             $ret=$file;
             last;
          }
    }      
  }else{
    if(-e $path.$retdefault.$postfix){
        $ret=$retdefault;
    } 
 }
 
 return $ret;  

}


#--------------------------------------------------------------------------------

=head3  startservice  
    start a service
    Arguments:
      service name
    Returns:
      0 on success
      nonzero otherwise
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->startservice("nfs");
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub startservice{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;
  }

  my $retval=0;
  $retval=specialservicemgr($svcname,"start");
  if($retval != 127)
  {
     return $retval;
  }

  my $cmd="";
  #for Systemd
  my $svcunit=undef;
  #for sysVinit
  my $svcd=undef;
  #for upstart
  my $svcjob=undef;

  $svcunit=servicemap($svcname,1);
  $svcjob=servicemap($svcname,2);
  $svcd=servicemap($svcname,0);
  if($svcunit)
  {
      $cmd="systemctl start $svcunit";
  }
  elsif( $svcjob )
  {
      $cmd="initctl start $svcjob";
  }
  elsif( $svcd )
  {
      $cmd="service $svcd start";
  }

  #print "$cmd\n"; 
  if( $cmd eq "" )
  {
     return -1;
  }
  #xCAT::Utils->runcmd($cmd, -1);   # do not use runcmd (backtics), must use system to not fork
  system($cmd);
  $::RUNCMD_RC=$?;
  return $::RUNCMD_RC;
 
}


#--------------------------------------------------------------------------------

=head3  stopservice  
    stop a service
    Arguments:
      service name
    Returns:
      0 on success
      nonzero otherwise
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->stopservice("nfs");
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub stopservice{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;
  }


  my $retval=0;
  $retval=specialservicemgr($svcname,"stop");
  if($retval != 127)
  {
     return $retval;
  }



  my $cmd="";
  my $svcunit=undef;
  my $svcd=undef;
  my $svcjob=undef; 

  $svcunit=servicemap($svcname,1);
  $svcjob=servicemap($svcname,2);
  $svcd=servicemap($svcname,0);
  if($svcunit)
  {
      $cmd="systemctl stop $svcunit";
  }
  elsif( $svcjob )
  {
      $cmd="initctl status $svcjob |grep stop; if [ \"\$?\" != \"0\"  ]; then initctl  stop $svcjob ; fi";
  }
  elsif( $svcd )
  {
      $cmd="service $svcd stop";
  }


  #print "$cmd\n"; 
  if( $cmd eq "" )
  {
     return -1;
  }
 
  #xCAT::Utils->runcmd($cmd, -1);   # do not use runcmd (backtics), must use system to not fork
  system($cmd);
  $::RUNCMD_RC=$?;
  return $::RUNCMD_RC;
}


#--------------------------------------------------------------------------------

=head3  restartservice  
    restart a service
    Arguments:
      service name
    Returns:
      0 on success
      nonzero otherwise
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->restartservice("nfs");
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub restartservice{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;
  }


  my $retval=0;
  $retval=specialservicemgr($svcname,"restart");
  if($retval != 127)
  {
     return $retval;
  }

  my $cmd="";
  my $svcunit=undef;
  my $svcd=undef;
  my $svcjob=undef; 

  $svcunit=servicemap($svcname,1);
  $svcjob=servicemap($svcname,2);
  $svcd=servicemap($svcname,0);
  if($svcunit)
  {
      $cmd="systemctl restart $svcunit";
  }
  elsif( $svcd )
  {
      $cmd="service $svcd restart";
  }
  elsif( $svcjob )
  {
      $cmd="initctl status $svcjob |grep stop; if [ \"\$?\" != \"0\"  ]; then initctl restart $svcjob ; else initctl start $svcjob; fi";
  }

  #print "$cmd\n"; 
  if( $cmd eq "" )
  {
     return -1;
  }
 
  #xCAT::Utils->runcmd($cmd, -1);
  system($cmd);
  $::RUNCMD_RC=$?;
  return $::RUNCMD_RC;
}

#--------------------------------------------------------------------------------

=head3   checkservicestatus 
    returns theservice status. 
    Arguments:
      $svcname: the name of the service
      $outputoption[optional]:
                   the output option
                   1: return a hashref with the keys:"retcode","retmsg"
           otherwise: return retcode only
    Returns:
      undef on fail
      a hashref if $outputoption is 1,the hash structure is:
                  {"retcode"=>(status code, 0 for running/active,1 for stopped/inactive,2 for failed)
                   "retmsg" =>(status string, running/active/stopped/inactive/failed)
                  }
      the status code otherwise

    Globals:
        none
    Error:
      None 
    Example:
         my $ret = xCAT::Utils-checkservicestatus($svcname,1);
         my $retcode = xCAT::Utils-checkservicestatus($svcname);
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub checkservicestatus{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;
  }

  my $outputoption=shift;

  my $retval;
  $retval=specialservicemgr($svcname,"status",1);
  if($retval->{retcode} != 127)
  {
     if(defined $outputoption and $outputoption == 1 ){
        return $retval;
     }elsif(exists $retval->{retcode}){
        return $retval->{retcode};
     }
  }


  my $cmd="";
  my $svcunit=undef;
  my $svcd=undef;
  my $svcjob=undef;
  my %ret;

  $svcunit=servicemap($svcname,1);
  $svcjob=servicemap($svcname,2);
  $svcd=servicemap($svcname,0);
  my $output=undef;

  if($svcunit)
  {
      #for systemd, parse the output since it is formatted
      $cmd="systemctl show --property=ActiveState $svcunit|awk -F '=' '{print \$2}'";
      $output=xCAT::Utils->runcmd($cmd, -1);
      if($output =~ /^active$/i){
         $ret{retcode}=0;
      }elsif($output =~ /^failed$/i){
         $ret{retcode}=2;
       
      }elsif($output =~ /^inactive$/i){
         $ret{retcode}=1;
      }
  }
  elsif ( $svcjob  )
  {
      #for upstart, parse the output 
      $cmd="initctl status $svcjob";
      $output=xCAT::Utils->runcmd($cmd, -1);
      if($output =~ /waiting/i){
         $ret{retcode}=2;
      }elsif($output =~ /running/i){
         $ret{retcode}=0;
      }
      
  }
  elsif( $svcd )
  {
      #for SYSVinit, check the return value since the "service" command output is confused
      $cmd="service $svcd status";
      $output=xCAT::Utils->runcmd($cmd, -1);
      $ret{retcode}=$::RUNCMD_RC; 
#      if($output =~ /stopped|not running/i){
#        $ret{retcode}=1;
#      }elsif($output =~ /running/i){
#        $ret{retcode}=0;
#      }
  }
  if($output)
  {
     $ret{retmsg}=$output;
  }
  

  if(defined $outputoption and $outputoption == 1 ){
     return \%ret;
  }elsif(exists $ret{retcode}){
     return $ret{retcode};
  }

   return undef;

}


#--------------------------------------------------------------------------------

=head3  enableservice 
   enable a service to start it on the system bootup
    Arguments:
      service name
    Returns:
      0 on success
      nonzero otherwise
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->enableservice("nfs");
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub enableservice{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;

  }

  my $retval=0;
  $retval=specialservicemgr($svcname,"enable");
  if($retval != 127)
  {
     return $retval;
  }



  my $cmd="";
  my $svcunit=undef;
  my $svcd=undef;
  my $svcjob=undef;

  $svcunit=servicemap($svcname,1);
  $svcjob=servicemap($svcname,2);
  $svcd=servicemap($svcname,0);
  if($svcunit)
  {
      $cmd="systemctl enable $svcunit";
  }
  elsif($svcjob)
  {
      $cmd="update-rc.d $svcjob defaults";
  
  }
  elsif( $svcd )
  {
      my $CHKCONFIG = xCAT::Utils->fullpathbin("chkconfig");
      if($CHKCONFIG ne "chkconfig"){
          $cmd="$CHKCONFIG $svcd on";
      }else{
        $CHKCONFIG = xCAT::Utils->fullpathbin("update-rc.d");
        if($CHKCONFIG ne "update-rc.d"){
            $cmd="$CHKCONFIG $svcd defaults";
        }
      }
  }
  if( $cmd eq "" )
  {
     return -1;
  }

  xCAT::Utils->runcmd($cmd, -1);
  return $::RUNCMD_RC;
}


#--------------------------------------------------------------------------------

=head3  disableservice  
    disable a service to prevent it from starting on system bootup
    Arguments:
      service name
    Returns:
      0 on success
      nonzero otherwise
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->disableservice("nfs");
    Comments:
        none
=cut

#--------------------------------------------------------------------------------
sub disableservice{
  my $svcname=shift;
  if( $svcname =~ /xCAT::Utils/)
  {
     $svcname=shift;

  }



  my $retval=0;
  $retval=specialservicemgr($svcname,"disable");
  if($retval != 127)
  {
     return $retval;
  }


  my $cmd="";
  my $svcunit=undef;
  my $svcjob=undef;
  my $svcd=undef;

  $svcunit=servicemap($svcname,1);
  $svcjob=servicemap($svcname,2);
  $svcd=servicemap($svcname,0);
  if($svcunit)
  {
      $cmd="systemctl disable $svcunit";
  }
  elsif($svcjob)
  {
      $cmd="update-rc.d -f $svcjob remove";
    
  }
  elsif( $svcd )
  {
      my $CHKCONFIG = xCAT::Utils->fullpathbin("chkconfig");
      if($CHKCONFIG ne "chkconfig"){
          $cmd="$CHKCONFIG $svcd off";
      }else{
        $CHKCONFIG = xCAT::Utils->fullpathbin("update-rc.d");
        if($CHKCONFIG ne "update-rc.d"){
            $cmd="$CHKCONFIG -f $svcd remove";
        }
      }
  }

#  print "$cmd\n";
  if( $cmd eq "" )
  {
     return -1;
  }

  xCAT::Utils->runcmd($cmd, -1);
  return $::RUNCMD_RC;
}

sub cleanup_for_powerLE_hardware_discovery {
    my $host_node = shift;
    if( $host_node =~ /xCAT::Utils/)
    {
        $host_node=shift;
    }
    my $pbmc_node = shift;
    my $subreq = shift;
    my $ipmitab = xCAT::Table->new("ipmi");
    unless($ipmitab) {
        xCAT::MsgUtils->message("S", "Discovery Error: can not open ipmi table.");
        return;
    }
    my @nodes = ($host_node, $pbmc_node);
    my $ipmihash = $ipmitab->getNodesAttribs(\@nodes, ['node', 'bmc', 'username', 'password']);
    if ($ipmihash) {
        my $new_bmc_ip = $ipmihash->{$host_node}->[0]->{bmc};
        my $new_bmc_password = $ipmihash->{$host_node}->[0]->{password};

        xCAT::MsgUtils->message("S", "Discovery info: configure password for pbmc_node:$pbmc_node.");
        `rspconfig $pbmc_node password=$new_bmc_password`;
        #if ($new_bmc_password) {
        #    xCAT::Utils->runxcmd(
        #        {
        #        command => ["rspconfig"],
        #        node => ["$pbmc_node"],
        #        arg     => [ "password=$new_bmc_password" ],
        #        },
        #        $subreq, 0,1);
        #    if ($::RUNCMD_RC != 0) {
        #        xCAT::MsgUtils->message("S", "Discovery Error: configure password failed for FSP.");
        #        return;
        #    }
        #}

        xCAT::MsgUtils->message("S", "Discover info: configure ip:$new_bmc_ip for pbmc_node:$pbmc_node.");
        `rspconfig $pbmc_node ip=$new_bmc_ip`;
        #if($new_bmc_ip) {
        #    xCAT::Utils->runxcmd(
        #        {
        #        command => ["rspconfig"],
        #        node => ["$pbmc_node"],
        #        arg     => [ "ip=$new_bmc_ip" ],
        #        },
        #        $subreq, 0,1);
        #    if ($::RUNCMD_RC != 0) {
        #        xCAT::MsgUtils->message("S", "Discovery Error: configure IP address failed for FSP.");
        #        return;
        #    }
        #}
        xCAT::MsgUtils->message("S", "Discovery info: remove pbmc_node:$pbmc_node.");
        `rmdef $pbmc_node`;
        #xCAT::Utils->runxcmd(
        #   {
        #   command => ["rmdef"],
        #   node => ["$pbmc_node"],
        #   },
        #   $subreq, 0,1);
    }
}


#The parseMacTabEntry parses the mac table entry and return the mac address of nic in management network 
#Arguments:
#macString : the string of mac table entry
#HostName  : the hostname of the node
#The mac address is taken as installnic when:
#1. the mac addr does not have a suffix "!xxxx"
#2. the mac addr has a fuffix "!<the node name in xcat nodelist table>"
#The schema description of mac table is:
#  mac:            The mac address or addresses for which xCAT will manage static bindings for this node.  
#This may be simply a mac address, which would be bound to the node name (such as "01:02:03:04:05:0E").  
#This may also be a "|" delimited string of "mac address!hostname" format (such as "01:02:03:04:05:0E!node5|01:02:03:05:0F!node6-eth1").
sub parseMacTabEntry{

    my $macString=shift;
    if( $macString =~ /xCAT::Utils/)     {
        $macString=shift;
    }
    my $HostName=shift;
    
    my $mac_ret;
    my @macEntry=split(/\|/,$macString);
    
    foreach my $mac_t  (@macEntry){
        if($mac_t =~ /!/){
            if($mac_t =~ /(.+)!$HostName$/){
                $mac_ret=$1;
            }
        }else{
            $mac_ret=$mac_t;
        }
    }

    if ($mac_ret) {
        if ($mac_ret !~ /:/) {
            $mac_ret =~ s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
        }
    }
    
    return $mac_ret;
}

#The splitkcmdline subroutine is used to split the "persistent kernel options" 
#and "provision-time kernel options" out of the kernel cmdline string
#Arguments:
#          $kcmdline:  the native kernel cmdline string
#Return value:
#          a reference of hash with the following KEY-VALUE def:
#          "persistent" ==> string of persistent kernel options,delimited with space " "
#          "volatile"   ==> string of provision-time kernel options,delimited with space " "
sub splitkcmdline{
 my $kcmdline=shift;
 if( $kcmdline =~ /xCAT::Utils/)     {
     $kcmdline=shift;
 }

 my %cmdhash;

 my @cmdlist=split(/[, ]/,$kcmdline);
 foreach my $cmd (@cmdlist){
    if($cmd =~ /^R::(.*)$/){
      $cmdhash{persistent}.="$1 ";
    }else{
      $cmdhash{volatile}.="$cmd ";
    }

 }

 return \%cmdhash;
}


###################################################################################
#subroutine lookupNetboot 
#Usage: determine the possible noderes.netboot values of the osimage 
#       according to the "osvers" and "osarch" attributes.
#Input Params: 
#       $osvers: the osname of the osimage,i.e,rhels7.1,sles11.3,ubuntu14.04.1 ...
#       $osarch: the osarch of the osimage,i.e, x86_64,ppc64,ppc64le ...
#Return value:
#       a string of the possible noderes.netboot values delimited with comma ","
#       i.e, "pxe,xnba", empty on fail.        
###################################################################################

sub lookupNetboot{
    my $osvers=shift;
    if ( $osvers =~ /xCAT::Utils/ ){
       $osvers=shift;
    }
    my $osarch=shift;

    my $ret="";
    my $osv;
    my $osn;
    my $osm;
    if ($osvers =~ /(\D+)(\d+)\.(\d+)/) {
        $osv = $1;
        $osn = $2;
        $osm = $3;

    } elsif ($osvers =~ /(\D+)(\d+)/){
        $osv = $1;
        $osn = $2;
        $osm = 0;
    }


    if ($osarch =~ /^x86_64$/i){
        $ret= "xnba,pxe";
    }elsif($osarch =~ /^ppc64$/i){
       if(($osv =~ /rh/i and $osn < 7) or ($osv =~ /sles/i and $osn < 12)){
          $ret="yaboot";
       }else{
          $ret="grub2,grub2-tftp,grub2-http";
       }
    }elsif($osarch =~ /^ppc64le$/i or $osarch =~ /^ppc64el$/i){
       $ret="petitboot,grub2,grub2-tftp,grub2-http"; 
    }
    
    return $ret;
}

1;
