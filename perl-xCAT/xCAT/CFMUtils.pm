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
use xCAT::Utils;
use xCAT::MsgUtils;
1;

#-----------------------------------------------------------------------------

=head3 initCFMdir
    Initialize CFM directies and files. The default laout under cfmdir is:
    . 
    |-- etc
    | |-- group.merge
    | |-- hosts -> /etc/hosts
    | |-- passwd.merge
    | |-- shadow.merge
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
        $rsp->{error}->[0] = "The CFM directory is not initialized.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
    }

    my @osfiles = glob("$cfmdir/*.OS");
    if (! @osfiles)
    {
        my $rsp = {};
        $rsp->{error}->[0] = "The default CFM files are not initialized.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
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

=head3 updateSynclistFile
    Update the synlist file. It will recursively scan the files under cfmdir directory and then add them to synclist file.
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
      $synclist - the path for synclist file
      $cfmdir - the path for CFM directory
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      $::CALLBACK
    Error:
      none
    Example:
      my $ret = CAT::CFMUtils->updateSynclistFile($synclist, $cfmdir);

=cut

#-----------------------------------------------------------------------------
sub updateSynclistFile {
    my ($class, $synclist, $cfmdir) = @_;

    if (! -d $cfmdir)
    {
        my $rsp = {};
        $rsp->{error}->[0] = "The CFM directory is not initialized.\n";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
        return 1;
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
    my ($synced_ref, $append_ref, $execute_ref, $executealways_ref, $merge_ref) = getUserSynclistRecords($synclist, $cfmdir);
    my @synced = @$synced_ref;
    my @append = @$append_ref;
    my @execute = @$execute_ref;
    my @executealways = @$executealways_ref;
    my @merge = @$merge_ref;

    # recursively list the files under cfm directory 
    my @files = ();
    find ( sub { push @files, $File::Find::name if (! -d) }, $cfmdir);

    my $fp;
    open($fp, '>', $synclist);
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
 
    return 0;
}

#-----------------------------------------------------------------------------

=head3 updateOSpkglistFile
    Update the ospkglist file

    Arguments:
      $ospkglist - the path for ospkglist file
      @curospkgs - the currently selected OS packages list
    Returns:
      0 - update successfully
      1 - update failed
    Globals:
      none
    Error:
      none
    Example:
      my $ret = CAT::CFMUtils->updateOSpkglistFile($ospkglist, @cur_selected_pkgs);

=cut

#-----------------------------------------------------------------------------
sub updateOSpkglistFile {
    my ($class, $ospkglist, $ospkgs) = @_;
    my @cur_selected = @$ospkgs;

    # get previous selected and removed OS packages list from pkglist file
    my ($pre_selected_ref, $pre_removed_ref) = xCAT::CFMUtils->getPreOSpkgsList($ospkglist);
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
    open($fp, '>', $ospkglist);
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
      @array1
      @array2
    Returns:
      @union/@intersection/@difference
    Globals:
      none
    Error:
      none
    Example:
      my @array = xCAT::CFMUtils->arrayops(@array1, @array2);

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
