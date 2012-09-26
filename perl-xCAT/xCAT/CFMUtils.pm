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
    | |-- group.merge
    | |-- hosts -> /etc/hosts
    | |-- passwd.merge
    | |-- shadow.merge
    |-- group.OS
    |-- passwd.OS
    |-- shadow.OS
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

    if (! -d $cfmdir)
    {
        mkpath $cfmdir;
    }

    # backup original /etc/passwd, shadow, group files
    foreach my $file (@userfiles)
    {
        my $backup = basename($file).".OS";
        if (! -e "$cfmdir/$backup")
        {
            copy($file, "$cfmdir/$backup");
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
    # touch the merge files for /etc/passwd, shadow, group
    foreach my $file (@userfiles)
    {
        my $merge = $file.".merge";
        if (! -e "$cfmdir/$merge")
        {
            system("touch $cfmdir/$merge");
        }
    }
}

#-----------------------------------------------------------------------------

=head3 updateUserInfo
    Update the /etc/passwd, shadow, group merge files under specified CFM directory

    Arguments:
      $cfmdir
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

    if (! -d $cfmdir)
    {
        my $rsp = {};
        $rsp->{error}->[0] = "The CFM directory($cfmdir) does not exist.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    my @osfiles = glob("$cfmdir/*.OS");
    if (! @osfiles)
    {
        my $rsp = {};
        $rsp->{data}->[0] = " Updating the /etc/passwd, shadow, group merge files under the CFM directory.";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }

    foreach my $file (@userfiles)
    {
        my @oldrecords = ();
        my @newrecords = ();
        my $backup = basename($file).".OS";

        # get the records from /etc/passwd, shadow, group file and backup
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
        if (@diff)
        {
            my $fp;
            open($fp, '>', $mergefile);
            for my $record (@diff)
            {
               print $fp "$record\n";
            }
            close ($fp);
        }
        
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

    my $cfmdir = "";
    my $synclists = "";
    my $cfmsynclist = "/install/osimages/$img/synclist.cfm";

    # get the cfmdir and synclists attributes
    my $osimage_t = xCAT::Table->new('osimage');
    my $records = $osimage_t->getAttribs({imagename=>$img}, 'cfmdir', 'synclists');
    if ($records)
    {
        if ($records->{'cfmdir'}) {$cfmdir = $records->{'cfmdir'}}
        if ($records->{'synclists'}) {$synclists = $records->{'synclists'}}
    } else 
    {
        my $rsp = {};
        $rsp->{error}->[0] = "Can not get cfmdir and synclists attributes, the osimage table may not been initialized.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return $cfmdir;
    }

    my $found = 0;
    my $index = 0;
    if ($synclists)
    {
        my @lists = split(/,/, $synclists); # the synclists is a comma separated list
        foreach my $synclist (@lists)
        {
            if ($synclist eq $cfmsynclist) # find the synclist configuration for CFM
            {
                $found = 1;
                last;
            }
            $index += 1;
        }
        if ($cfmdir and !$found) { $synclists = "$synclists,$cfmsynclist"; } # add CFM synclist to the list
        if ($found and !$cfmdir) { $synclists = join(',', delete $lists[$index]); } # remove CFM synclist from the list
    } else
    {
        if ($cfmdir) { $synclists = $cfmsynclist; }
    }

    # Set the synclist file
    $osimage_t->setAttribs({imagename=>$img}, {'synclists' => $synclists});
    
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
        my $cfmdir = "";
        $cfmdir = xCAT::CFMUtils->setCFMSynclistFile($osimg);
        if ($cfmdir)
        {
            my $cfmsynclist = "/install/osimages/$osimg/synclist.cfm";
            if (! -d $cfmdir)
            {
                my $rsp = {};
                $rsp->{error}->[0] = "The CFM directory($cfmdir) does not exist.";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                return 1;
            }
            # check the cfmsynclist file and it's parent directory
            if (! -d dirname($cfmsynclist))
            {
                mkpath dirname($cfmsynclist);
            }
            if (! -e $cfmsynclist)
            {
                system("touch $cfmsynclist");
            }

            # update /etc/passwd, shadow, group merge files
            my $ret = xCAT::CFMUtils->updateUserInfo($cfmdir);
            if ($ret)
            {
                my $rsp = {};
                $rsp->{error}->[0] = "Update /etc/passwd, shadow, group merge files failed.";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
            }

            # get the user specified records in synclist file
            my ($synced_ref, $append_ref, $execute_ref, $executealways_ref, $merge_ref) = getUserSynclistRecords($cfmsynclist, $cfmdir);
            my @synced = @$synced_ref;
            my @append = @$append_ref;
            my @execute = @$execute_ref;
            my @executealways = @$executealways_ref;
            my @merge = @$merge_ref;

            # recursively list the files under cfm directory 
            my @files = ();
            find ( sub { push @files, $File::Find::name if (! -d) }, $cfmdir);
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
            # output the user specified records for syncing
            foreach my $file (@synced)
            {
                print $fp "$file\n";
            }

            # output the APPEND records maintained by CFM
            print $fp "\n\nAPPEND:\n";
            foreach my $file (@appendfiles)
            { 
                my $dest = substr($file, length($cfmdir), length($file) - length(".append") - length($cfmdir));
                print $fp "$file -> $dest\n";
            }
            # output the user specified APPEND records
            foreach my $file (@append)
            {
                print $fp "$file\n";
            }

            # output the EXECUTE records
            print $fp "\n\nEXECUTE:\n";
            foreach my $file (@execute)
            {
                print $fp "$file\n";
            }

            # output the EXECUTEALWAYS records
            print $fp "\n\nEXECUTEALWAYS:\n";
            foreach my $file (@executealways)
            {
                print $fp "$file\n";
            }

            # output the MERGE records maintianed by CFM
            print $fp "\n\nMERGE:\n";
            foreach my $file (@mergefiles)
            {
                my $dest = substr($file, length($cfmdir), length($file) - length(".merge") - length($cfmdir));
                print $fp "$file -> $dest\n";
            }
            # output the user specified MERGE records
            foreach my $file (@merge)
            {
                print $fp "$file\n";
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
        my $rsp = {};
        $rsp->{error}->[0] = "Can not get pkglist attribute, the linuximage table may not been initialized.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    my $found = 0;
    if ($pkglists)
    {
        foreach my $pkglist (split(/,/, $pkglists))
        {
            if ($pkglist eq $cfmpkglist) 
            {
                $found = 1;
                last;
            }
        }
        # The pkglist file for CFM is found, return directly 
        if (!$found) { $pkglists = "$pkglists,$cfmpkglist"; } 
    } else 
    {
        $pkglists = $cfmpkglist;
    }

    # Set the pkglist attribute for linuximage
    $linuximage_t->setAttribs({imagename => $img}, {'pkglist' => $pkglists});
    
    return 0;   
}

#-----------------------------------------------------------------------------

=head3 updateCFMPkglistFile
    Update the ospkglist file

    Arguments:
      $imagename - the specified linuximage name
      @curospkgs - the currently selected OS packages list
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      none
    Error:
      none
    Example:
      my $ret = CAT::CFMUtils->updateCFMPkglistFile($imagename, @cur_selected_pkgs);

=cut

#-----------------------------------------------------------------------------
sub updateCFMPkglistFile {
    my ($class, $img, $ospkgs) = @_;
     
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

    # check the cfmpkglist file and it's parent directory
    if (! -d dirname($cfmpkglist))
    {
        mkpath dirname($cfmpkglist);
    }
    if (! -e $cfmpkglist)
    {
        system("touch $cfmpkglist");
    }

    # get previous selected and removed OS packages list from pkglist file
    my ($pre_selected_ref, $pre_removed_ref) = xCAT::CFMUtils->getPreOSpkgsList($cfmpkglist);
    my @pre_selected = @$pre_selected_ref;
    my @pre_removed = @$pre_removed_ref;

    # get diff between previous and current selected OS packages lists    
    my @diff = xCAT::CFMUtils->getOSpkgsDiff(\@pre_selected, \@cur_selected);
 
    # merge the diff to previous removed OS packages list
    my @all_removed = xCAT::CFMUtils->arrayops("U", \@pre_removed, \@diff);

    # get the rollbacked OS packages list, the packages are existing in both removed and selected lists
    # if so, we should remove the rollbacked OS packages from removed list
    my @rollback = xCAT::CFMUtils->arrayops("I", \@all_removed, \@cur_selected);
    my @cur_removed = xCAT::CFMUtils->arrayops("D", \@all_removed, \@rollback);

    # update the pkglist file
    my $fp;
    open($fp, '>', $cfmpkglist);
    # the pacakges be installed
    if (@cur_selected)
    {
        print $fp "#The OS packages be installed:\n";
        foreach my $pkg (@cur_selected)
        {
            print $fp "$pkg\n";
        }
    }
    # the packages be removed
    if (@cur_removed)
    {
        print $fp "#The OS packages be removed:\n";
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

=head3 getUserSynclistRecords
    Get the user specified records from synclist file.

    Arguments:
      $synclist - the path for synclist file
      $cfmdir - the path for CFM directory
    Returns:
      refs for synced, appened, execute, executealways and merge records arrays
    Globals:
      none
    Error:
      none
    Example:
      my ($synced_ref, $append_ref, $execute_ref, $executealways_ref, $merge_ref) = xCAT::CFMUtils->getUserSynclistRecords($synclist, $cfmdir);
      my @synced = @$synced_ref;
      my @append = @$append_ref;
      my @execute = @$execute_ref;
      my @executealways = @$executealways_ref;
      my @merge = @$merge_ref;

=cut

#----------------------------------------------------------------------------- 
sub getUserSynclistRecords {
    my ($class, $synclist, $cfmdir) = @_;

    my @records = ();
    # flags to identify the record for APPEND, EXECUTE, EXECUTEALWAYS, MERGE
    my $isappend = 0;
    my $isexecute = 0;
    my $isexecutealways = 0;
    my $ismerge = 0;
    # lists for syncing files, APPEND, EXECUTE, EXECUTEALWAYS, MERGE records
    my @synced = ();
    my @append = ();
    my @execute = ();
    my @executealways = ();
    my @merge = ();

    my $synclistfp;
    open($synclistfp, $synclist);
    while (<$synclistfp>)
    {
        my $line = xCAT::CFMUtils->trim($_);
        if (($line =~ /^#/) || ($line =~ /^\s*$/ ))
        { #comment line or blank line
            next;
        } else 
        {
            if ($line =~ /^$cfmdir/) 
            { # remove the records maintained by CFM
                next;
            } else
            {
                push @records, $line;
            }
        }
    }
    close($synclistfp);

    # list the records
    foreach my $record (@records)
    {
       if ($record eq "APPEND:") # set flag for APPEND records
       {
           $isappend = 1;
           $isexecute = 0;
           $isexecutealways = 0;
           $ismerge = 0;
           next;
       }
       if ($record eq "EXECUTE:") # set flag for EXECUTE records
       {
           $isexecute = 1;
           $isappend = 0;
           $isexecutealways = 0;
           $ismerge = 0;
           next;
       }
       if ($record eq "EXECUTEALWAYS:") # set flag for EXECUTEALWAYS records
       {
           $isexecutealways = 1;
           $isappend = 0;
           $isexecute = 0;
           $ismerge = 0;
           next;
       }
       if ($record eq "MERGE:") # set flag for MERGE records
       {
           $ismerge = 1;
           $isappend = 0;
           $isexecute = 0;
           $isexecutealways = 0;
           next;
       }
 
       if (! ($isappend || $isexecute || $isexecutealways || $ismerge)) 
       { # syncing file record
           push @synced, $record; 
           next;
       }
       if ($isappend && ! ($isexecute || $isexecutealways || $ismerge))
       { # APPEND record
           push @append, $record;
           next;
       }
       if ($isexecute && ! ($isappend || $isexecutealways || $ismerge))
       { # EXECUTE record
           push @execute, $record;
           next;
       }
       if ($isexecutealways && ! ($isappend || $isexecute || $ismerge))
       { # EXECUTEALWAYS record
           push @executealways, $record;
           next;
       }
       if ($ismerge && ! ($isappend || $isexecute || $isexecutealways))
       { # MERGE record
           push @merge, $record;
           next;
       }
    }

    return (\@synced, \@append, \@execute, \@executealways, \@merge);
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

    my $pkglistfp;
    open($pkglistfp, $pkglist);
    while (<$pkglistfp>)
    {
        my $line = xCAT::CFMUtils->trim($_);
        if (($line =~ /^#/) || ($line =~ /^\s*$/ ))
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

    return (\@selected, \@removed);
}

#-----------------------------------------------------------------------------

=head3 getOSpkgsDiff
    Get the differences between previous and current OS packages list

    Arguments:
      @pre - previous selected OS packages list
      @cur - current selected OS packages list
    Returns:
      @diff - the differencen list
    Globals:
      none
    Error:
      none
    Example:
      my @diff = xCAT::CFMUtils->getOSpkgsDiff(\@pre_selected, \@cur_selected);

=cut

#-----------------------------------------------------------------------------
sub getOSpkgsDiff {
    my ($class, $pre, $cur) = @_;

    # get the intersection firstly
    my @tmp = xCAT::CFMUtils->arrayops("I", \@$pre, \@$cur);

    # get the difference
    my @diff = xCAT::CFMUtils->arrayops("D", \@$pre, \@tmp);
    #print Dumper(@diff);

    return @diff;
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
