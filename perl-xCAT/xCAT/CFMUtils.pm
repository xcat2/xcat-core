# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::CFMUtils;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use warnings;
use File::Path;
use File::Copy;
use File::Find;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
1;

#-----------------------------------------------------------------------------

=head3 initCFMdir
    Initialize CFM directories and files. The default layout under cfmdir is:
    . 
    |-- etc
    | |-- group.merge -> /etc/group.merge
    | |-- hosts -> /etc/hosts
    | |-- passwd.merge -> /etc/passwd.merge
    | |-- shadow.merge -> /etc/shadow.merge
    |-- group.OS -> /etc/group.OS
    |-- passwd.OS -> /etc/passwd.OS
    |-- shadow.OS -> /etc/shadow.OS
    Note: the *.OS files are the backups for the original /etc/passwd, shadow, group files

    Arguments:
      $cfmdir
    Returns:
      0 - initialize successfully
      1 - initialize failed
    Globals:
      none 
    Error:
      none
    Example:
      xCAT::CFMUtils->initCFMdir($cfmdir);

=cut

#-----------------------------------------------------------------------------
sub initCFMdir
{
    my ($class, $cfmdir) = @_;

    # below system files will be synced to all compute nodes
    my @sysfiles = ("/etc/hosts");

    # the /etc/passwd, shadow, group files will be merged 
    my @userfiles = ("/etc/passwd", "/etc/shadow", "/etc/group");

    # create the cfmdir
    if (! -d $cfmdir)
    {
        mkpath $cfmdir;
    }

    # backup the OS files and create links under cfmdir
    foreach my $file (@userfiles)
    {
        my $backup = $file.".OS";
        if (! -e $backup)
        {
            copy($file, $backup);
        }

        if (! -e "$cfmdir/".basename($backup))
        {
            symlink($backup, "$cfmdir/".basename($backup));
        }
    }

    # Initialize CFM directory and related files
    if (! -d "$cfmdir/etc")
    {
        mkpath "$cfmdir/etc";
    }

    # link the system files
    foreach my $file (@sysfiles)
    {
        symlink($file, "$cfmdir/$file");
    }
    # touch and link the merge files for /etc/passwd, shadow, group
    foreach my $file (@userfiles)
    {
        my $merge = $file.".merge";
        if (! -e "$merge")
        {
            xCAT::Utils->runcmd("touch $merge", -1);
        }

        if (! -e "$cfmdir/$merge")
        {
            symlink($merge, "$cfmdir/$merge");
        }
    }
}

#-----------------------------------------------------------------------------

=head3 updateUserInfo
    Update the /etc/passwd, shadow, group merge files under specified CFM directory

    Arguments:
      $cfmdir - CFM directory for osimage      
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      $::CALLBACK
    Error:
      none
    Example:
      my $ret = xCAT::CFMUtils->updateUserInfo($cfmdir);

=cut

#-----------------------------------------------------------------------------
sub updateUserInfo {
    my ($class, $cfmdir) = @_;

    my @userfiles = ("/etc/passwd", "/etc/shadow", "/etc/group");

    my @osfiles = glob("$cfmdir/*.OS");
    if (!@osfiles)
    {
        if ($::VERBOSE)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Skiping the update of the /etc/passwd, shadow, group merge files under the CFM directory.";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
	return 0;
    }

    foreach my $file (@userfiles)
    {
        my @oldrecords = ();
        my @newrecords = ();
        my $backup = basename($file).".OS";

        # get the records from /etc/passwd, shadow, group file and backup files(.OS files)
        # and all the files from /install/osimages/$imgname/cfmdir directory  
        foreach my $userinfo ($file, "$cfmdir/$backup") 
        {
            my $fp;
            open($fp, $userinfo);
            my @records = ();
            while (<$fp>)
            {
                my $line = xCAT::CFMUtils->trim($_);
                if (($line =~ /^#/) || ($line =~ /^\s*$/ ))
                { #comment line or blank line
                    next;
                } else
                {    
                    push @records, $line;
                }   
            }
            close($fp);

            # check the records from /etc/passwd, shadow, group file or backup
            if ($userinfo =~ /^\/etc/ )
            {
                @newrecords = @records;
            } else {
                @oldrecords = @records;
            }
        }

        # update the merge file
        my $mergefile = $cfmdir."/".$file.".merge";
        my @diff = xCAT::CFMUtils->arrayops("D", \@newrecords, \@oldrecords);
        # output the diff to merge files
        my $fp;
        open($fp, '>', $mergefile);
        if (@diff)
        {
            for my $record (@diff)
            {
                # skip to add ROOT relative records into MERGE file
                if ($record =~ /^root/)
                {
                    next;
                }
                print $fp "$record\n";
            }
        }
        close ($fp);
        
    }

    return 0;
}


#-----------------------------------------------------------------------------
=head3 setCFMSynclistFile
    Set osimage synclists attribute for CFM function, the CMF synclist file is:
    /install/osimages/<imagename>/synclist.cfm

    Arguments:
      $imagename - the specified osimage name
    Returns:
      It returns the cfmdir path if it is defined for an osimage object
    Globals:
      $::CALLBACK
    Error:
      none
    Example:
      my $cfmdir = xCAT::CFMUtils->setCFMSynclistFile($imagename);
      if ($cfmdir) { # update the CFM synclist file }
=cut
#-----------------------------------------------------------------------------
sub setCFMSynclistFile {
    my ($class, $img) = @_;

    my $cfmdir;
    my $synclists;
    my $cfmsynclist = "/install/osimages/$img/synclist.cfm";

    # get the cfmdir and synclists attributes
    my $osimage_t = xCAT::Table->new('osimage');
    my $records = $osimage_t->getAttribs({imagename=>$img}, 'cfmdir', 'synclists');
    if (defined ($records->{'cfmdir'}))
    {
        $cfmdir = $records->{'cfmdir'};
        if (defined ($records->{'synclists'})) {$synclists = $records->{'synclists'}}
    } else {
        # no cfmdir defined, return directly
        return 0;
    }

    my $found = 0;
    my $index = 0; 
    if ($synclists)
    {
        # the synclists is a comma separated list
        my @lists = split(/,/, $synclists);
        foreach my $synclist (@lists)
        {
            # find the synclist configuration for CFM
            if ($synclist eq $cfmsynclist) 
            {
                $found = 1;
                last;
            }
            $index += 1;
        }
        if ($found == 0)
        {
            # the CFM synclist is not defined, append it to $synclists
            $synclists = "$synclists,$cfmsynclist"; 
            # set the synclists attribute 
            $osimage_t->setAttribs({imagename=>$img}, {'synclists' => $synclists});
        }
    } else {
        # no synclists defined, set it to CFM synclist file
        if ($cfmdir) { $synclists = $cfmsynclist; }
        $osimage_t->setAttribs({imagename=>$img}, {'synclists' => $synclists});
    }

    return $cfmdir;   
}


#-----------------------------------------------------------------------------

=head3 updateCFMSynclistFile
    Update the synclist file(/install/osimages/<imagename>/synclist.cfm) for CFM function. 
    It will recursively scan the files under cfmdir directory and then add them to CFM synclist file.
    Note:
    The files with suffix ".append" will be appended to the dest file(records in "APPEND:" section).
    The files with suffix ".merge" will be merged to the dest file(records in "MERGE:" section).

    In addition, it will reserve the user specified records in the synclist file. The example synclist file:
	<cfmdir>/etc/hosts -> /etc/hosts
	/root/install.log -> /tmp/install.log
	...

	APPEND:
	<cfmdir>/etc/hosts.append -> /etc/hosts
	/root/install.log.syslog -> /tmp/install.log
	...
	EXECUTE:
	...
	EXECUTEALWAYS:
	...
	MERGE:
	<cfmdir>/etc/group.merge -> /etc/group
	<cfmdir>/etc/shadow.merge -> /etc/shadow
	<cfmdir>/etc/passwd.merge -> /etc/passwd

    Arguments:
      \@imagenames - reference to the osimage names array
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      $::CALLBACK
    Error:
      none
    Example:
      my $ret = CAT::CFMUtils->updateCFMSynclistFile(\@imagenames);

=cut

#-----------------------------------------------------------------------------
sub updateCFMSynclistFile {
    my ($class, $imgs) = @_;

    my @osimgs = @$imgs;
    if (!@osimgs)
    {
        my $rsp = {};
        $rsp->{error}->[0] = "No osimage names specified to process.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    foreach my $osimg (@osimgs)
    {
        my $cfmdir;
        $cfmdir = xCAT::CFMUtils->setCFMSynclistFile($osimg);
        if ($cfmdir)   # check for /install/osiamges/$osimg/cfmdir
        {
            my $cfmsynclist = "/install/osimages/$osimg/synclist.cfm";
            if (! -d $cfmdir)
            {
                # skip this one go on to the next image, nothing to do for 
                # CFMUtils in this image
                next;
            }
            # create the parent directory of CFM synclist file
            if (! -d dirname($cfmsynclist))
            {
                mkpath dirname($cfmsynclist);
            }

            # update /etc/passwd, shadow, group merge files
            my $ret = xCAT::CFMUtils->updateUserInfo($cfmdir);
            if ($ret !=0 )
            {
                my $rsp = {};
                $rsp->{error}->[0] = 
                "Update /etc/passwd, shadow, group merge files failed.";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                return 1;
            }

            # recursively list the files under cfm directory 
            my @files = ();

            find ( { wanted => sub { push @files, $File::Find::name if -f }, follow => 1 }, $cfmdir);
            if (!@files) # not files under cfm directory, skip to next loop 
            {
                next;
            }

            my $fp;
            open($fp, '>', $cfmsynclist);
            my @mergefiles = ();
            my @appendfiles = ();
            foreach my $file (@files)
            {
                my $name = basename($file);
                #TODO: find a better way to get the suffix 
                my $suffix = ($name =~ m/([^.]+)$/)[0];
                my $dest = substr($file, length($cfmdir));
                if ($suffix eq "OS") # skip the backup files
                {
                    next;
                } elsif ($suffix eq "merge") # merge file
                {
                    push(@mergefiles, $file);
                } elsif ($suffix eq "append") { # append file
                    push(@appendfiles, $file); 
                } else { # output the syncing files maintained by CFM
                    print $fp "$file -> $dest\n";
                }
            }

            # output the APPEND records maintained by CFM
            if (@appendfiles) {
                print $fp "APPEND:\n";
            }
            foreach my $file (@appendfiles)
            { 
                my $dest = substr($file, length($cfmdir), length($file) - length(".append") - length($cfmdir));
                print $fp "$file -> $dest\n";
            }

            # output the MERGE records maintained by CFM
            if (@mergefiles) {
                print $fp "MERGE:\n";
            }
            foreach my $file (@mergefiles)
            {
                my @userfiles = ("/etc/passwd", "/etc/shadow", "/etc/group");
                my $dest = substr($file, length($cfmdir), length($file) - length(".merge") - length($cfmdir));
                # only /etc/passwd, /etc/shadow, /etc/groups merging is supported
                if (grep(/$dest/, @userfiles)) {		
                    print $fp "$file -> $dest\n";
                }
            }
            
            # close the file 
            close($fp);   
        }
    }
 
    return 0;
}

#-----------------------------------------------------------------------------
=head3 setCFMPkglistFile
    Set the pkglist attribute of linuximage object for CFM function

    Arguments:
      $imagename - the specified linuximage name
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      $::CALLBACK
    Error:
      none
    Example:
      my $ret = xCAT::CFMUtils->setCFMPkglistFile($imagename);
=cut
#-----------------------------------------------------------------------------
sub setCFMPkglistFile {
    my ($class, $img) = @_;

    my $pkglists = "";
    my $cfmpkglist = "/install/osimages/$img/pkglist.cfm";

    # get the pkglist files
    my $linuximage_t = xCAT::Table->new('linuximage');
    my $records = $linuximage_t->getAttribs({imagename => $img}, 'pkglist');
    if ($records)
    {
        if ($records->{'pkglist'}) { $pkglists = $records->{'pkglist'}; }
    } else 
    {
        if ($::VERBOSE)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "There are no records for pkglist attribute in the linuximage:$img. There is nothing to process.";
            xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        }
    }

    my $found = 0;
    if ($pkglists)
    {
        foreach my $pkglist (split(/,/, $pkglists))
        {
            if ($pkglist eq $cfmpkglist) # the pkglist file for CFM is found, exit the loop 
            {
                $found = 1;
                last;
            }
        }
        # the pkglist file for CFM is not found, append it to $pkglits 
        if (!$found) 
        {
            $pkglists = "$pkglists,$cfmpkglist"; 
            # set the pkglist attribute for linuximage
            $linuximage_t->setAttribs({imagename => $img}, {'pkglist' => $pkglists});
        } 
    } else 
    {
        # the pkglist file for linuximage is not defined, set it to $cfmpkglist
        $pkglists = $cfmpkglist;
        $linuximage_t->setAttribs({imagename => $img}, {'pkglist' => $pkglists});
    }

    return 0;   
}

#-----------------------------------------------------------------------------

=head3 updateCFMPkglistFile
    Update the ospkglist file

    Arguments:
      $imagename - the specified linuximage name
      @curospkgs - the currently selected OS packages list
      $mode      - using Fuzzy Matching or Exact Matching to check packages
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      none
    Error:
      none
    Example:
      my $ret = CAT::CFMUtils->updateCFMPkglistFile($imagename, @cur_selected_pkgs);
      my $ret = CAT::CFMUtils->updateCFMPkglistFile($imagename, @cur_selected_pkgs, 1);

=cut

#-----------------------------------------------------------------------------
sub updateCFMPkglistFile {
    my ($class, $img, $ospkgs, $mode) = @_;
    
    if(defined($mode)){
        # Exact Matching
        $mode = 1;
    }else {
        # Fuzzy Matching
        $mode = 0;
    }
    
    my @cur_selected = @$ospkgs;
    my $cfmpkglist = "/install/osimages/$img/pkglist.cfm";

    my $ret = xCAT::CFMUtils->setCFMPkglistFile($img);
    if ($ret)
    {
        my $rsp = {};
        $rsp->{error}->[0] = "Set pkglist attribute for CFM failed.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    # check the parent directory of cfmpkglist file
    if (! -d dirname($cfmpkglist))
    {
        mkpath dirname($cfmpkglist);
    }

    # get previous selected and removed OS packages list from pkglist file
    my ($pre_selected_ref, $pre_removed_ref) = xCAT::CFMUtils->getPreOSpkgsList($cfmpkglist);
    my @pre_selected = @$pre_selected_ref;
    my @pre_removed = @$pre_removed_ref;

    # get the #INCLUDE file from cfmpkglist file
    my @incfiles = xCAT::CFMUtils->getIncludefiles($cfmpkglist);
    # get the packages list in the #INCLUDE files
    my @basepkgs = ();
    foreach my $inc (@incfiles)
    {
        my ($selected_ref, $removed_ref) = xCAT::CFMUtils->getPreOSpkgsList($inc);
        my @selected = @$selected_ref;
        @basepkgs = xCAT::CFMUtils->arrayops("U", \@basepkgs, \@selected);
    }
    
    # Fuzzy Matching
    if (not $mode){
        my ($ref1, $ref2, $ref3) = xCAT::CFMUtils->updateSelectedPkgs(\@pre_selected, \@pre_removed, \@cur_selected);
        @pre_selected = @$ref1;
        @pre_removed = @$ref2;
        @cur_selected = @$ref3;
    }

    # get diff between previous and current selected OS packages lists    
    my @diff = xCAT::CFMUtils->getPkgsDiff(\@pre_selected, \@cur_selected);
 
    # merge the diff to previous removed OS packages list
    my @all_removed = xCAT::CFMUtils->arrayops("U", \@pre_removed, \@diff);

    # get the rollbacked OS packages list, the packages are existing in both removed and selected lists
    # if so, we should remove the rollbacked OS packages from removed list
    my @rollback = xCAT::CFMUtils->arrayops("I", \@all_removed, \@cur_selected);
    my @cur_removed = xCAT::CFMUtils->arrayops("D", \@all_removed, \@rollback);

    # remove the BASE packages from selected pakages
    @basepkgs = xCAT::CFMUtils->arrayops("I", \@basepkgs, \@cur_selected);
    @cur_selected = xCAT::CFMUtils->arrayops("D", \@cur_selected, \@basepkgs);

    # update the pkglist file
    my $fp;
    open($fp, '>', $cfmpkglist);
    foreach my $inc (@incfiles)
    {
        print $fp "#INCLUDE:$inc#\n";
    }
    # the pacakges be installed
    if (@cur_selected)
    {
        foreach my $pkg (@cur_selected)
        {
            print $fp "$pkg\n";
        }
    }
    # the packages be removed
    if (@cur_removed)
    {
        foreach my $pkg (@cur_removed)
        {
            print $fp "-$pkg\n";
        }
    }
    # close the file
    close($fp);

    return 0;
}

#-----------------------------------------------------------------------------

=head3 getPreOSpkgsList
    Get previously selected and removed OS packages lists from pkglist file

    Arguments:
      $ospkglist - the path for ospkglist file
    Returns:
      refs for selected and removed OS packages arrays
    Globals:
      none
    Error:
      none
    Example:
      my ($pre_selected_ref, $pre_removed_ref) = xCAT::CFMUtils->getPreOSpkgsList($ospkglist);
      my @pre_selected = @$pre_selected_ref;
      my @pre_removed = @$pre_removed_ref;

=cut

#-----------------------------------------------------------------------------
sub getPreOSpkgsList {
    my ($class, $pkglist) = @_;
    my @selected = ();
    my @removed = ();
    my @pkglistfiles = ();

    # get the #INCLUDE file from cfmpkglist file
    my @incfiles = xCAT::CFMUtils->getIncludefiles($pkglist);
    foreach my $inc (@incfiles)
    {
        push @pkglistfiles, $inc;
    }
    # assume the #INCLUDE file includes the BASE packages
    push @pkglistfiles, $pkglist;

    foreach my $file (@pkglistfiles)
    {
        my $pkglistfp;
        open($pkglistfp, xCAT::CFMUtils->trim($file));
        while (<$pkglistfp>)
        {
            my $line = xCAT::CFMUtils->trim($_);
            if (($line =~ /^#/) || ($line =~ /^\s*$/ ) || ($line =~ /^@/))
            { #comment line or blank line
                next;
            } else
            {
                if ($line =~ /^-/)
                { # the package be removed
                    push @removed, substr($line, 1);
                } else
                { # the package be installed
                    push @selected, $line;
                } 
            }
        }    
        close($pkglistfp);
    }

    # delete the removed packages from selected list
    my @intersection = xCAT::CFMUtils->arrayops("I", \@removed, \@selected);
    @selected = xCAT::CFMUtils->arrayops("D", \@selected, \@intersection);

    return (\@selected, \@removed);
}

#-----------------------------------------------------------------------------

=head3 getPreBaseOSpkgsList
    Get previously selected and removed base OS packages lists from pkglist file. Packages named with "example.xxx" should be the base name "example"

    Arguments:
      $ospkglist - the path for ospkglist file
    Returns:
      refs for selected and removed OS packages arrays
    Globals:
      none
    Error:
      none
    Example:
      my $pre_selected_ref = xCAT::CFMUtils->getPreOSpkgsList($ospkglist);

=cut

#-----------------------------------------------------------------------------
sub getPreBaseOSpkgsList {
    my ($class, $pkglist) = @_;
    
    my ($pre_selected_ref, $pre_removed_ref) = xCAT::CFMUtils->getPreOSpkgsList($pkglist); 
    
    my %pre_selected_hash = ();
    foreach (@$pre_selected_ref) {
        my @names = split(/\./, $_);
        my $basename = $names[0];
        
        if ($_ =~ /^$basename\.([^\.]+)$/) {
            $pre_selected_hash{$basename} = 1;
        }else {
            $pre_selected_hash{$_} = 1;
        }
    }
    
    @pre_selected = keys %pre_selected_hash;

    return \@pre_selected;
}


#-----------------------------------------------------------------------------

=head3 getPkgsDiff
    Get the differences between previous and current packages list

    Arguments:
      @pre - previous selected packages list
      @cur - current selected packages list
    Returns:
      @diff - the differencen list
    Globals:
      none
    Error:
      none
    Example:
      my @diff = xCAT::CFMUtils->getPkgsDiff(\@pre_selected, \@cur_selected);

=cut

#-----------------------------------------------------------------------------
sub getPkgsDiff {
    my ($class, $pre, $cur) = @_;

    # get the intersection firstly
    my @tmp = xCAT::CFMUtils->arrayops("I", \@$pre, \@$cur);

    # get the difference
    my @diff = xCAT::CFMUtils->arrayops("D", \@$pre, \@tmp);
    #print Dumper(@diff);

    return @diff;
}

#-----------------------------------------------------------------------------

=head3 getIncludefiles 
    Get the #INCLUDE files from the given file 

    Arguments:
      $file - the given file
    Returns:
      @files - the #INCLUDE files list
    Globals:
      none
    Error:
      none
    Example:
      my @diff = xCAT::CFMUtils->getIncludefiles($file);

=cut

#-----------------------------------------------------------------------------
sub getIncludefiles {
    my ($class, $file) = @_;
    my @files = ();

    my $fp;
    open($fp, $file);
    while (<$fp>)
    {
        my $line = xCAT::CFMUtils->trim($_);
        if ($line =~ /^\s*$/)
        { # blank line
            next;
        }
        # find the #INCLUDE line
        if ($line =~ /^\s*#INCLUDE:[^#^\n]+#/)
        {
            #print "The line is: [$line]\n";
            my $incfile = substr($line, length("#INCLUDE:"), length($line)-length("#INCLUDE:")-1);
            push @files, $incfile;
        }
    }
    close($fp);

    return @files;
}

#-----------------------------------------------------------------------------

=head3 trim
    Strip left and right whitspaces for a string 

    Arguments:
      $string
    Returns:
      @string
    Globals:
      none
    Error:
      none
    Example:
      my @new_string = xCAT::CFMUtils->trim($string);

=cut

#-----------------------------------------------------------------------------
sub trim {
    my ($class, $string) = @_;

    # trim the left whitespaces
    $string =~ s/^\s*//;

    # trim the right whitespaces
    $string =~ s/\s*$//;

    return $string;
}

# Function: compute Union, Intersection or Difference of unique lists
# Usage: arrayops ("U"/"I"/"D", @a, @b)
# Return: @union/@intersection/@difference
#-----------------------------------------------------------------------------

=head3 arrayops
    Compute Union/Intersection/Difference for 2 unique lists

    Arguments:
      $flag - "U"/"I"/"D"
      \@array1 - reference to an arrary
      \@array2 - reference to an arrary
    Returns:
      @union/@intersection/@difference
    Globals:
      none
    Error:
      none
    Example:
      my @array = xCAT::CFMUtils->arrayops(\@array1, \@array2);

=cut

#-----------------------------------------------------------------------------
sub arrayops {
    my ($class, $ops, $array1, $array2) = @_;

    my @union = ();
    my @intersection = ();
    my @difference = ();
    my %count = ();
    foreach my $element (@$array1, @$array2) 
    { 
        $count{$element}++ 
    }

    foreach my $element (keys %count) {
        push @union, $element;
        push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
    }

    if ($ops eq "U") { return @union; }
   
    if ($ops eq "I") { return @intersection; }

    if ($ops eq "D") { return @difference; }

    #return (\@union, \@intersection, \@difference);
}


#-----------------------------------------------------------------------------

=head3 updateSelectedPkgs
    Update previous selected, previous removed and current selected packages based on fuzzy matching rules. Packages named with "example.i686" should be same with package "example"

    Arguments:
      \@pre_selected - reference to previous selected packages
      \@pre_removed - reference to previous removed packages
      \@cur_selected - reference to current selected packages
    Returns:
      new previous selected, previous removed, current selected packages
    Globals:
      none
    Error:
      none
    Example:
      my ($ref1, $ref2, $ref3) = xCAT::CFMUtils->arrayops(\@pre_selected, \@pre_removed, \@cur_selected);

=cut

#-----------------------------------------------------------------------------
sub updateSelectedPkgs() {
    my ($class, $pre_selected_ref, $pre_removed_ref, $cur_selected_ref) = @_; 
    
    my %pre_selected_hash = map{$_ => 1} @$pre_selected_ref;
    my %pre_removed_hash = map{$_ => 1} @$pre_removed_ref;
    my %cur_selected_hash = map{$_ => 1} @$cur_selected_ref;
    
    my %new_pre_selected_hash = %pre_selected_hash;
    my %new_pre_removed_hash = %pre_removed_hash;
    my %new_cur_selected_hash = %cur_selected_hash;
    
    foreach (keys %cur_selected_hash) {
        my $father = $_;
        my $flag = 0;
        foreach (keys %pre_selected_hash) {
            my $child = $_;
            if ($child =~ /^$father\.([^\.]+)$/) {
                $new_cur_selected_hash{$child} = 1;
                $flag = 1;
            }
        }
        if ($flag and not exists $pre_selected_hash{$father}){
            delete $new_cur_selected_hash{$father} if exists $new_cur_selected_hash{$father};
        }
        
        foreach (keys %pre_removed_hash) {
            my $child = $_;
            if ($child =~ /^$father\.([^\.]+)$/) {
                delete $new_pre_removed_hash{$child} if exists $new_pre_removed_hash{$child};
            }
        }
    }
    
    my @new_cur_selected = keys %new_cur_selected_hash;
    my @new_pre_selected = keys %new_pre_selected_hash;
    my @new_pre_removed = keys %new_pre_removed_hash;
    
    
    return (\@new_pre_selected, \@new_pre_removed, \@new_cur_selected);  
}
