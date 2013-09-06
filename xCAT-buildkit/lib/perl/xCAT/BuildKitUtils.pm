#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::BuildKitUtils;

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
use POSIX qw(ceil);
use File::Path;
use Socket;
use strict;
use Symbol;
my $sha1support;
if ( -f "/etc/debian_version" ) {
    $sha1support = eval {
        require Digest::SHA;
        1;
    };
}
else {

    $sha1support = eval {
        require Digest::SHA1;
        1;
    };
}
use IPC::Open3;
use IO::Select;
use warnings "all";

our @ISA       = qw(Exporter);

#-------------------------------------------------------------------------------

=head1    xCAT::BuildKitUtils

=head2    Package Description

This program module file, is a set of utilities used by xCAT buildkit command

=cut

#-------------------------------------------------------------

#--------------------------------------------------------------------------
=head3    get_latest_version

          Find the latest version in a list of rpms with the same basename

        Arguments:
                - the repo location
                - a list of rpms with the same basename
        Returns:
                - name of rpm
                - undef
        Example:
                  my $new_d = xCAT::BuildKitUtils->get_latest_version($repodir, \@rpmlist);
        Comments:

=cut
#--------------------------------------------------------------------------
sub get_latest_version
{
    my ($class, $repodir, $rpms) = @_;

    my @rpmlist = @$rpms;

    my %localversions_hash = ();
    my %file_name_hash     = ();

    my $i = 0;
    foreach my $rpm (@rpmlist)
    {

        # include path
        my $fullrpmpath = "$repodir/$rpm*";

        # get the basename, version, and release for this rpm
        my $rcmd = "rpm -qp --queryformat '%{N} %{V} %{R}\n' $repodir/$rpm*";
        my $out  = `$rcmd`;

        my ($rpkg, $VERSION, $RELEASE) = split(' ', $out);

        chomp $VERSION;
        chomp $RELEASE;

        $localversions_hash{$i}{'VERSION'}  = $VERSION;
        $localversions_hash{$i}{'RELEASE'}  = $RELEASE;

        $file_name_hash{$VERSION}{$RELEASE} = $rpm;
        $i++;
    }

    if ($i == 0)
    {
	print "error\n";
	return undef;
    }

    my $versionout = "";
    my $releaseout = "";
    $i = 0;
    foreach my $k (keys %localversions_hash)
    {
        if ($i == 0)
        {
            $versionout = $localversions_hash{$k}{'VERSION'};
            $releaseout = $localversions_hash{$k}{'RELEASE'};
        }

        # if this is a newer version/release then set them
        if ( xCAT::BuildKitUtils->testVersion($localversions_hash{$k}{'VERSION'}, ">", $versionout, $localversions_hash{$k}{'RELEASE'}, $releaseout) ) {
            $versionout = $localversions_hash{$k}{'VERSION'};
            $releaseout = $localversions_hash{$k}{'RELEASE'};
        }
        $i++;
    }

    return ($file_name_hash{$versionout}{$releaseout});
}

#------------------------------------------------------------------------------
=head3    testVersion

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

        Comments:
                The return value is generated with the Require query of the
                rpm command.

=cut

#-----------------------------------------------------------------------------
sub testVersion
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
        # remove any non-numbers on the end
        my ($d1) = $a1[$i] =~ /^(\d*)/;  
        my ($d2) = $a2[$i] =~ /^(\d*)/;

        my $diff = length($d1) - length($d2);
        if ($diff > 0)       # pad d2
        {
            $num1 .= $d1;
            $num2 .= ('0' x $diff) . $d2;
        }
            elsif ($diff < 0)       # pad d1
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

    # be sure that $num1 is not a "".
    if (length($num1) == 0) { $num1 = 0; }
    if (length($num2) == 0) { $num2 = 0; }

    if ($operator eq '=') { $operator = '=='; }
    my $bool = eval "$num1 $operator $num2";

    return $bool;
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
         if (xCAT::BuildKitUtils->isAIX()) { blah; }
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
         my $osversion = xCAT::BuildKitUtils->get_OS_VRMF();
    Comments:
        Only implemented for AIX for now
=cut

#-------------------------------------------------------------------------------
sub get_OS_VRMF
{
	my $version;
	if (xCAT::BuildKitUtils->isAIX()) {
		my $cmd = "/usr/bin/lslpp -cLq bos.rte";
		my $output = `$cmd`;
		chomp($output);

		# The third field in the lslpp output is the VRMF
		$version = (split(/:/, $output))[2];

		# not sure if the field would ever contain more than 4 parts?
		my ($v1, $v2, $v3, $v4, $rest) = split(/\./, $version);
		$version = join(".", $v1, $v2, $v3, $v4); 
	}
	return (length($version) ? $version : undef);
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
         if (xCAT::BuildKitUtils->isLinux()) { blah; }
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub isLinux
{
    if ($^O =~ /^linux/i) { return 1; }
    else { return 0; }
}

#--------------------------------------------------------------------------------

=head3    CreateRandomName

		Create a random file name.
				Arguments:
	  	    		Prefix of name
				Returns:
					Prefix with 8 random letters appended
				Error:
				none
				Example:
				$file = xCAT::BuildKitUtils->CreateRandomName($namePrefix);
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
	   xCAT::BuildKitUtils->close_delete_file($file_handle, $file_name);
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
    if ($ver_a =~ /xCAT::BuildKitUtils/)
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
      none
    Returns:
        0 - ok
    Globals:
        none
    Error:
        1 error
    Example:
         my $os=(xCAT::BuildKitUtils->osver{ ...}
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
  #      $ver=~ s/\.//;
        $ver =~ s/[^0-9]*([0-9.]+).*/$1/;
        if    ($line =~ /AS/)     { $os = 'rhas' }
        elsif ($line =~ /ES/)     { $os = 'rhes' }
        elsif ($line =~ /WS/)     { $os = 'rhws' }
        elsif ($line =~ /Server/) { $os = 'rhels' }
        elsif ($line =~ /Client/) { $os = 'rhel' }
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
        $ver =~ s/\.//;
        $ver =~ s/[^0-9]*([0-9]+).*/$1/;
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
    $os = "$os" . "," . "$ver";
    return ($os);
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
#-----------------------------------------------------------------------------
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
#-----------------------------------------------------------------------------
sub release_lock {
    my $tlock = shift;
    unlink($tlock->{path});
    flock($tlock->{fd},LOCK_UN);
    close($tlock->{fd});
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
        my @new_array = xCAT::BuildKitUtils::get_unique_members(@orig_array);
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
        my $fp = xCAT::BuildKitUtils::full_path('./test', '/home/guest');
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

1;
