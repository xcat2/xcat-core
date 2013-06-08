# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle Kit management
=cut

#-------------------------------------------------------
package xCAT_plugin::kit;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
#use Data::Dumper;
use File::Basename;
use File::Path;

my $kitconf = "kit.conf";

# kit framework version for this xcat.
$::KITFRAMEWORK ="1";

# this code is compatible with other kits that are at framework 0 or 1.
$::COMPATIBLE_KITFRAMEWORKS = "0,1";


#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            lskit  => "kit",
            addkit => "kit",
            rmkit => "kit",
            lskitcomp  => "kit",
            addkitcomp => "kit",
            rmkitcomp => "kit",
            chkkitcomp => "kit",
            lskitdeployparam  => "kit",
	   };
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $request_command = shift;
    $::CALLBACK = $callback;
    $::args     = $request->{arg};

    my $lock;
    my $locked = xCAT::Utils->is_locked("kit", 1);
    if ( !locked ) {
        $lock = xCAT::Utils->acquire_lock("kit", 1);
        unless ($lock){
            $callback->({error=>["Can not acquire lock."],errorcode=>[1]});
            return 1;
        }    
    } else {
        if ( $::PID and $::PID != $$ ) {
            $callback->({error=>["Can not acquire lock, another process is running."],errorcode=>[1]});
            return 1;
        }

        $::PID = $$;
    }


    my $command  = $request->{command}->[0];
    my $rc;

    if ($command eq "lskit"){
        $rc = lskit($request, $callback, $request_command);
    } elsif ($command eq "addkit"){
        $rc = addkit($request, $callback, $request_command);
    } elsif ($command eq "rmkit"){
        $rc = rmkit($request, $callback, $request_command);
    } elsif ($command eq "lskitcomp"){
        $rc = lskitcomp($request, $callback, $request_command);
    } elsif ($command eq "addkitcomp"){
        $rc = addkitcomp($request, $callback, $request_command);
    } elsif ($command eq "rmkitcomp"){
        $rc = rmkitcomp($request, $callback, $request_command);
    } elsif ($command eq "chkkitcomp"){
        $rc = chkkitcomp($request, $callback, $request_command);
    } elsif ($command eq "lskitdeployparam"){
        $rc = lskitdeployparam($request, $callback, $request_command);
    } else{
        $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
        xCAT::Utils->release_lock($lock, 1);
        return 1;
    }

    if ( $lock ) {
        xCAT::Utils->release_lock($lock, 1);
    }
    return $rc;

}

#-------------------------------------------------------

=head3  get_highest_version

  Return the highest version and release for a list of 
  kit, kitrepo, or kitcomponent names.

  Input: @entries: the arrary contains all the data
         $key: the key name in entries hash.
         $version: compare version nums.
         $release: compare release nums.

=cut

#-------------------------------------------------------
sub get_highest_version
{
    my $key = shift;
    my $version = shift;
    my $release = shift;
    my @entries = @_;

    my $highest;

    foreach my $entry ( @entries ) {
        $highest=$entry if (!$highest);

        my $rc = compare_version($highest,$entry,$key,$version,$release);
        if ( $rc == 1 ) {
            $highest = $entry;
        }  
    }

    return $highest->{$key};
}

#-------------------------------------------------------

=head3  compare_version

  Compare the version and release between two kit/kitrepo/kitcomp

  Input: $highest: the current highest version or release 
         $entry: the new entry
         $key: the key name in entries hash.
         $version: compare version nums.
         $release: compare release nums.

=cut

#-------------------------------------------------------
sub compare_version
{
    my $highest = shift;
    my $entry = shift;
    my $key = shift;
    my $version = shift;
    my $release = shift;

    my @a1 = split(/\./, $highest->{$version});
    my @a2 = split(/\./, $entry->{$version});

    my ($len,$num1,$num2);
    if (($release = 'release') &&
       (defined $highest->{$release}) && (defined $entry->{$release})){
        $len = (scalar(@a1) > scalar(@a2) ? scalar(@a1) : scalar(@a2));
    }else{
        $len = (scalar(@a1) < scalar(@a2) ? scalar(@a1) : scalar(@a2));
    }

    $#a1 = $len - 1;  # make the arrays the same length before appending release
    $#a2 = $len - 1;

    if ($release = 'release') {
        push @a1, split(/\./, $highest->{$release});
        push @a2, split(/\./, $entry->{$release});
    }

    $len = (scalar(@a1) < scalar(@a2) ? scalar(@a1) : scalar(@a2));

    $num1 = '';
    $num2 = '';

    for (my $i = 0 ; $i < $len ; $i++)
    {
        my ($d1,$w1) = $a1[$i] =~ /^(\d*)(\w*)/;
        my ($d2,$w2) = $a2[$i] =~ /^(\d*)(\w*)/;


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
        else                               # they are the same length
        {
            $num1 .= $d1;
            $num2 .= $d2;
        }

        if ( $w1 && $w2)
        {
            my ($w_to_d1, $w_to_d2) = comp_word( $w1, $w2);
            $num1 .= $w_to_d1;
            $num2 .= $w_to_d2;
        }
    }

# Remove the leading 0s or perl will interpret the numbers as octal
    $num1 =~ s/^0+//;
    $num2 =~ s/^0+//;

#SuSE Changes
# if $num1="", the "eval '$num1 $operator $num2'" will fail. So MUSTBE be sure that $num1 is not a "".
    if (length($num1) == 0) { $num1 = 0; }
    if (length($num2) == 0) { $num2 = 0; }

    return 1 if ( $num2 > $num1 );
    return 0 if ( $num2 == $num1 );
    return -1;
}

#--------------------------------------------------------------------------------

=head3    comp_word

        Compare version1 word and version2 word. This subroutine can only be used to compare
        one section in version number, and this section cannot start with number.

        Arguments:
                $w1:
                $w2
        Returns:
                if $w1 > $w2, return (1,0)
                if $w1 < $w2, return (0,1)
                if $w1 == $w2, return (undef, undef)
        Globals:
                none

        Example:
                if ($self->comp_word ( "adfadsfa","acc2")
                return (0,1)
        Comments:
                the version word cannot contain ".", and cannot start with number.
                For examples, following version words cannot be compared by this subroutine:
                (123.321, 123.322)  You need use subroutine testVersion to do the version comparision
                (123abc,12bcd)      You need use subroutine testVersion to do the version comparision

=cut

#--------------------------------------------------------------------------------

sub comp_word
{
    my $self = shift;

    my ($w1,$w2) = @_;

    return (undef,undef) if (!$w1 || !$w2);

    my @strList1 = unpack "C*", $w1;
    my @strList2 = unpack "C*", $w2;

    my $len = scalar(@strList1) < scalar(@strList2) ? scalar(@strList1) : scalar(@strList2);

    for ( my $i = 0; $i < $len; $i++)
    {
        next if ( $strList1[$i] == $strList2[$i]);
        return ( 0, 1) if ( $strList1[$i] < $strList2[$i]);
        return ( 1, 0);
    }
    return (undef,undef);

}

#-------------------------------------------------------

=head3 assign_to_osimage

  Assign a kit component to osimage

=cut

#-------------------------------------------------------
sub assign_to_osimage
{
    my $osimage = shift;
    my $kitcomp = shift;
    my $callback = shift;
    my $tabs = shift;

    (my $kitcomptable) = $tabs->{kitcomponent}->getAttribs({kitcompname=> $kitcomp}, 'kitname', 'kitreponame', 'basename', 'kitpkgdeps', 'prerequisite', 'exlist', 'genimage_postinstall','postbootscripts', 'driverpacks');
    (my $osimagetable) = $tabs->{osimage}->getAttribs({imagename=> $osimage}, 'provmethod', 'osarch', 'postbootscripts', 'kitcomponents');
    (my $linuximagetable) = $tabs->{linuximage}->getAttribs({imagename=> $osimage}, 'rootimgdir', 'exlist', 'postinstall', 'otherpkglist', 'otherpkgdir', 'driverupdatesrc');

    # Reading installdir.
    my $installdir = xCAT::TableUtils->getInstallDir();
    unless($installdir){
        $installdir = '/install';
    }
    $installdir =~ s/\/$//;

    # Create osimage direcotry to save kit tmp files
    mkpath("$installdir/osimages/$osimage/kits/");

    # Adding genimage_postinstall script to linuximage.postintall attribute for diskless image or osimage.postbootscripts for diskfull image.
    if ( $kitcomptable and $kitcomptable->{genimage_postinstall} ){
        my @kitcompscripts = split ',', $kitcomptable->{genimage_postinstall};
        foreach my $kitcompscript ( @kitcompscripts ) {
            if ( $osimagetable ) {
                my $otherpkgdir;
                my $rootimgdir;
                if ( $linuximagetable and $linuximagetable->{otherpkgdir} ) {
                    $otherpkgdir = $linuximagetable->{otherpkgdir};
                } else {
                    $callback->({error => ["Could not read otherpkgdir from osimage $osimage"],errorcode=>[1]});
                    return 1;
                }

                if ( $osimagetable->{provmethod} =~ /install/ ) {
                    # for diskfull node
                    my $match = 0;
                    my @scripts = split ',', $osimagetable->{postbootscripts};
                    foreach my $script ( @scripts ) {
                         if ( $script =~ /^KIT_$osimage.postbootscripts/ ) {
                             $match = 1;
                             last;
                         }
                    }

                    if ( !-e "$installdir/postscripts/KIT_$osimage.postbootscripts" ) {
                        if (open(FILE, ">", "$installdir/postscripts/KIT_$osimage.postbootscripts")) {
                            print FILE "#!/bin/sh\n\n";
                            close(FILE);
                            chmod(0755,"$installdir/postscripts/KIT_$osimage.postbootscripts");
                        }
                    }

                    my @postbootlines;
                    if (open(POSTBOOTSCRIPTS, "<", "$installdir/postscripts/KIT_$osimage.postbootscripts")) {
                        @postbootlines = <POSTBOOTSCRIPTS>;
                        close(POSTBOOTSCRIPTS);
                        if($::VERBOSE){
                            $callback->({data=>["\nCreating osimage postbootscripts file $installdir/postscripts/KIT_$osimage.postbootscripts"]});
                        } 
                    }

                    unless ( grep(/$kitcompscript/ , @postbootlines ) ) {
                        if (open(NEWLIST, ">>", "$installdir/postscripts/KIT_$osimage.postbootscripts")) {
                            print NEWLIST "otherpkgdir=$otherpkgdir $kitcompscript\n";
                            close(NEWLIST);
                        }
                    }

                    if ( !$match ) {
                        $osimagetable->{postbootscripts} = $osimagetable->{postbootscripts} . ",KIT_$osimage.postbootscripts";
                        $osimagetable->{postbootscripts} =~ s/^,//;
                    }

                } else {
                    # for diskless node

                    if ( $linuximagetable and $linuximagetable->{rootimgdir} ) {
                        $rootimgdir = $linuximagetable->{rootimgdir}."/rootimg";
                    } else {
                        $callback->({error => ["Could not read rootimgdir from osimage $osimage"],errorcode=>[1]});
                        return 1;
                    }

                    if ( !-e "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall" ) {
                        if (open(FILE, ">", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall")) {
                            print FILE "#!/bin/sh\n\n";
                            close(FILE);
                            chmod(0755,"$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall");
                        }
                    }

                    my @postinstalllines;
                    if (open(POSTINSTALL, "<", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall")) {
                        @postinstalllines = <POSTINSTALL>;
                        close(POSTINSTALL);
        
                        if($::VERBOSE){
                           $callback->({data=>["\nReading osimage postinstall scripts file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall"]});
                        }
                    }

                    unless ( grep(/$kitcompscript/ , @postinstalllines ) ) {
                        if (open(NEWLIST, ">>", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall")) {
                            print NEWLIST "installroot=$rootimgdir otherpkgdir=$otherpkgdir $installdir/postscripts/$kitcompscript\n";
                            close(NEWLIST);
                        }
                    }

                    my $match = 0;
                    my @scripts = split ',', $linuximagetable->{postinstall};
                    foreach my $script ( @scripts ) {
                        if ( $script =~ /KIT_COMPONENTS.postinstall/ ) {
                            $match = 1;
                            last;
                        }
                    }

                    if ( !$match ) {
                        $linuximagetable->{postinstall} =  $linuximagetable->{postinstall} . ",$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall";
                    }
                    $linuximagetable->{postinstall} =~ s/^,//;
                }
            }
        }
    }
 
    # Adding postbootscrits to osimage.postbootscripts
    if ( $kitcomptable and $kitcomptable->{postbootscripts} ){
        my @kitcompscripts = split ',', $kitcomptable->{postbootscripts};
        foreach my $kitcompscript ( @kitcompscripts ) {

            my $formatedkitcomp = $kitcompscript;

            if ( $osimagetable ) {
                if ( $osimagetable->{postbootscripts} ){
                    my $match = 0;
                    my $added = 0;
                    my @newscripts;
                    my @scripts = split ',', $osimagetable->{postbootscripts};
                    foreach my $script ( @scripts ) {
                        if ( $script =~ /^$formatedkitcomp$/ ) {
                            $match = 1;
                            last;
                        }

                        if ( $script !~ /^BASEXCAT_/ and $script !~ /^KIT_/ ) {
                            unless ( $added ) {
                                push @newscripts, $formatedkitcomp;
                                $added = 1;
                            }
                        }


                        push @newscripts, $script;

                    }

                    if ( $match ) {
                        next;
                    } elsif ( !$added ) {
                        push @newscripts, $formatedkitcomp;
                    }

                    my $osimagescripts = join ',', @newscripts;
                    $osimagetable->{postbootscripts} = $osimagescripts;
                } else {
                    $osimagetable->{postbootscripts} = $formatedkitcomp;
                }

            }
            
        }
    }

    # Adding kit component's repodir to osimage.otherpkgdir
    if ( $kitcomptable and $kitcomptable->{kitreponame} ) {

        (my $kitrepotable) = $tabs->{kitrepo}->getAttribs({kitreponame=> $kitcomptable->{kitreponame}}, 'kitrepodir');
        if ( $kitrepotable and $kitrepotable->{kitrepodir} ) {

            if ( $linuximagetable and $linuximagetable->{otherpkgdir} ) {
                my $otherpkgdir = $linuximagetable->{otherpkgdir};
                my $kitrepodir = $kitrepotable->{kitrepodir};

                # Create otherpkgdir if it doesn't exist
                unless ( -d "$otherpkgdir" ) {
                    mkpath("$otherpkgdir");
                }

                # Create symlink if doesn't exist
                unless ( -d "$otherpkgdir/$kitcomptable->{kitreponame}" ) {
                    system("ln -sf $kitrepodir $otherpkgdir/$kitcomptable->{kitreponame} ");
                } 
            } else {
                $callback->({error => ["Cannot open linuximage table or otherpkgdir do not exist"],errorcode=>[1]});
                return 1;
            }
        } else {
            $callback->({error => ["Cannot open kit table or kitdir do not exist"],errorcode=>[1]});
            return 1;
        }
    }

    # Reading kitdir
    my $kittable;
    if ( $kitcomptable and $kitcomptable->{kitname} ) {
        ($kittable) = $tabs->{kit}->getAttribs({kitname=> $kitcomptable->{kitname}}, 'kitdir', 'kitdeployparams');
    }
    
    # Adding kitcomponent.exlist to osimage.exlist
    if ( $kitcomptable and $kitcomptable->{exlist} and $kittable and $kittable->{kitdir} ) {

        my @lines;
        my $exlistfile = $kitcomptable->{exlist};
        my $kitdir = $kittable->{kitdir};


        # Adding kit component exlist file to KIT_COMPONENTS.exlist file
        mkpath("$installdir/osimages/$osimage/kits/");
        if ( -e "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist" ) {
            if (open(EXLIST, "<", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist")) {
                @lines = <EXLIST>;
                close(EXLIST);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist"],errorcode=>[1]});
                return 1;
            }
        }
        unless ( grep(/^#INCLUDE:$kitdir\/other_files\/$exlistfile#$/ , @lines) ) {
            if (open(NEWEXLIST, ">>", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist")) {
                
                print NEWEXLIST "#INCLUDE:$kitdir/other_files/$exlistfile#\n"; 
                close(NEWEXLIST);
            }
        }

        # Adding KIT_COMPONENTS.exlist file to osimage.exlist if not existing.
        if ( $linuximagetable ) {
            if ( $linuximagetable->{exlist} ) {
                my $match = 0;
                my @exlists= split ',', $linuximagetable->{exlist};
                foreach my $exlist ( @exlists ) {
                    if ( $exlist =~ /^$installdir\/osimages\/$osimage\/kits\/KIT_COMPONENTS.exlist$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $linuximagetable->{exlist} = $linuximagetable->{exlist} . ',' . "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist";
                }
            } else {
                $linuximagetable->{exlist} = "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist";
            }

        }

    }

    # Adding kitdeployparams to a otherpkglist file in osimage
    my @kitdeployparams;
    if ( $kittable and $kittable->{kitdeployparams} and $kittable->{kitdir} ) { 

        # Reading contents from kit.kitdeployparams file
        my @contents;
        my $kitdir = $kittable->{kitdir};
        my $kitdeployfile = $kittable->{kitdeployparams};
        if ( -e "$kitdir/other_files/$kitdeployfile" ) {
            if (open(KITDEPLOY, "<", "$kitdir/other_files/$kitdeployfile") ) {
                @contents = <KITDEPLOY>;
                @kitdeployparams = @contents;
                close(KITDEPLOY);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit deployparams from $kitdir/other_files/$kitdeployfile\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit deployparams file $kitdir/other_files/$kitdeployfile"],errorcode=>[1]});
            }
        }

        # Creating kit deployparams file
        my @lines;
        mkpath("$installdir/osimages/$osimage/kits/");
        if ( -e "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist" ) {
            if (open(DEPLOYPARAM, "<", "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist")) {
                @lines = <DEPLOYPARAM>;
                close(DEPLOYPARAM);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit deployparams file $installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit deployparams file $installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist"],errorcode=>[1]});
                return 1;
            }
        }

        # Checking if the kit deployparams have been written in the generated kit deployparams file.
        my @l;
        foreach my $content ( @contents ) {
            chomp $content;
            my $matched = 0;
            foreach my $line ( @lines ) {
                chomp $line;
                if ( $line =~ /$content/ ) {
                    $matched = 1;
                    last;
                }
            }

            unless ( $matched ) {
                push @l, $content . "\n";
            }
        }

        # Write the missing lines to kit deployparams file
        if (open(NEWDEPLOYPARAM, ">>", "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist")) {
            print NEWDEPLOYPARAM @l;
            close(NEWDEPLOYPARAM);
        }

        # Write this kit deployparams to osimage.otherpkglist if not existing.
        if ( $linuximagetable ) {
            if ( $linuximagetable->{otherpkglist} ) {
                my $match = 0;
                my @otherpkglists= split ',', $linuximagetable->{otherpkglist};
                foreach my $otherpkglist ( @otherpkglists ) {
                    if ( $otherpkglist =~ /^$installdir\/osimages\/$osimage\/kits\/KIT_DEPLOY_PARAMS.otherpkgs.pkglist$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $linuximagetable->{otherpkglist} = $linuximagetable->{otherpkglist} . ',' . "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist";
                }
            } else {
                $linuximagetable->{otherpkglist} = "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist";
            }
        }

    }

    # Adding kit component basename to osimage.otherpkgs.pkglist
    if ( $kitcomptable and $kitcomptable->{basename} and $kitcomptable->{kitreponame} ) {

        my @lines;
        my $basename = $kitcomptable->{basename};
        my $kitreponame = $kitcomptable->{kitreponame};

        # Adding kit component basename to KIT_COMPONENTS.otherpkgs.pkglist file
        mkpath("$installdir/osimages/$osimage/kits");
        if ( -e "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist" ) {
            if (open(OTHERPKGLIST, "<", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist")) {
                @lines = <OTHERPKGLIST>;
                close(OTHERPKGLIST);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit component otherpkg file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit component otherpkg file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist"],errorcode=>[1]});
                return 1;
            }
        }
        unless ( grep(/^$kitreponame\/$basename$/, @lines) ) {
            if (open(NEWOTHERPKGLIST, ">", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist")) {
                if ( $kitcomptable and $kitcomptable->{prerequisite} ) {
                    push @lines, "#NEW_INSTALL_LIST#\n";
                    foreach my $kitdeployparam ( @kitdeployparams ) {
                        push @lines, "$kitdeployparam";
                    }
                    push @lines, "$kitreponame/$kitcomptable->{prerequisite}\n";
                    $::noupgrade = 1;
                }
                if ( $::noupgrade ) {
                    push @lines, "#NEW_INSTALL_LIST#\n";
                    foreach my $kitdeployparam ( @kitdeployparams ) {
                         push @lines, "$kitdeployparam";
                    }
                    push @lines, "$kitreponame/$basename\n";
                    print NEWOTHERPKGLIST @lines;
                } else {
                    print NEWOTHERPKGLIST "$kitreponame/$basename\n";
                    print NEWOTHERPKGLIST @lines;
                }

                close(NEWOTHERPKGLIST);
            }
        }

        # Write this kit component otherpkgs pkgfile to osimage.otherpkglist if not existing.
        if ( $linuximagetable ) {
            if ( $linuximagetable->{otherpkglist} ) {
                my $match = 0;
                my @otherpkglists= split ',', $linuximagetable->{otherpkglist};
                foreach my $otherpkglist ( @otherpkglists ) {
                    if ( $otherpkglist =~ /^$installdir\/osimages\/$osimage\/kits\/KIT_COMPONENTS.otherpkgs.pkglist$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $linuximagetable->{otherpkglist} = $linuximagetable->{otherpkglist} . ',' . "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist";
                }
            } else {
                $linuximagetable->{otherpkglist} = "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist";
            }

        }

        # Remove this component basename and pkgnames from KIT_RMPKGS.otherpkg.pkglist
        my @lines = ();

        my @kitpkgdeps = split ',', $kitcomptable->{kitpkgdeps}; 
        push @kitpkgdeps, $basename;

        my @l = ();
        if ( -e "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist" ) {
            if (open(RMOTHERPKGLIST, "<", "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist")) {
                @lines = <RMOTHERPKGLIST>;
                close(RMOTHERPKGLIST);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit component rmpkgs file $installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit component rmpkgs file $installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist"],errorcode=>[1]});
                return 1;
            }
        }

        my $changed = 0;
        foreach my $line ( @lines ) {
            chomp $line;
            my $matched = 0;
            foreach my $kitpkgdep ( @kitpkgdeps ) {
                if ( $line =~ /^-$kitpkgdep$/ ) {
                    $matched = 1;
                    $changed = 1;
                    last;
                }
            }
            if ( $line =~ /^-prep_$basename$/ ) {
                $matched = 1;
                $changed = 1;
            }
            unless ( $matched ) {
                push @l, "$line\n";
            }

            my $lastline = pop @l;
            while ( $lastline =~ /^#NEW_INSTALL_LIST#$/ ) {
                $lastline = pop @l;
            }
            push @l, $lastline if ( $lastline );
        }

        if ( $changed ) {
            if (open(RMPKGLIST, ">", "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist")) {
                print RMPKGLIST @l;
                close(RMPKGLIST);
            }
        }

    } else {
        $callback->({error => ["Could not open kit component table and read basename for kit component $kitcomp"],errorcode=>[1]});
        return 1;
    }

    # Now writing kit component to osimage.kitcomponents
    if($::VERBOSE){
        $callback->({data=>["\nAdding this kitcomponent to osimage.kitcomponents\n"]});
    }
    if ( $osimagetable ) {
        if ( $osimagetable->{kitcomponents} ){
            $osimagetable->{kitcomponents} = join( ',', $osimagetable->{kitcomponents}, $kitcomp);
        } else {
            $osimagetable->{kitcomponents} = $kitcomp;
        }
    }

    # Adding driverpacks

    if ( $linuximagetable and $linuximagetable->{driverupdatesrc} ) {
        if ( $kitcomptable and $kitcomptable->{driverpacks} ) {
            my @driverpacks = split ',', $kitcomptable->{driverpacks};
            my @driverupdatesrcs = split ',', $linuximagetable->{driverupdatesrc};

            my @newdriverupdatesrcs = @driverupdatesrcs;

            foreach  my $driverpack ( @driverpacks ) {
                my $matched = 0;
                    foreach my $driverupdatesrc ( @driverupdatesrcs ) {
                    if ( $driverpack eq $driverupdatesrc ) {
                        $matched = 1;
                        last;
                    }
                }

                unless ( $matched ) {
                    push @newdriverupdatesrcs, $driverpack;
                }
            }

            my $newdriverupdatesrc = join ',', @newdriverupdatesrcs;
            $linuximagetable->{driverupdatesrc} = $newdriverupdatesrc;
        }
    }    
    

    # Write linuximage table with all the above udpates.
    $tabs->{linuximage}->setAttribs({imagename => $osimage }, \%{$linuximagetable} );

    # Write osimage table with all the above udpates.
    $tabs->{osimage}->setAttribs({imagename => $osimage }, \%{$osimagetable} );

}


#-------------------------------------------------------

=head3 addkit 

  Add Kits into xCAT

=cut

#-------------------------------------------------------
sub addkit
{
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $path;
    my $rc;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "addkit: add Kits into xCAT from a list of tarball file or directory which have the same structure with tarball file";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\taddkit [-h|--help]";
        push@{ $rsp{data} }, "\taddkit [-i|--inspection] <kitlist>]";
        push@{ $rsp{data} }, "\taddkit [-p|--path <path>] <kitlist>] [-V]";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    };


    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            $xusage->(1);
            return;
    }


    GetOptions(
            'h|help' => \$help,
            'V|verbose' => \$::VERBOSE,
            'i|inspection' => \$inspection,
            'p|path=s' => \$path,
    );

    if($help){
            $xusage->(0);
            return;
    }

    my %tabs = ();
    my @tables = qw(kit kitrepo kitcomponent);
    foreach my $t ( @tables ) {
        $tabs{$t} = xCAT::Table->new($t,-create => 1,-autocommit => 1);

        if ( !exists( $tabs{$t} )) {
            my %rsp;
            push@{ $rsp{data} }, "Could not open xCAT table $t";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }
    }

    my $basename;
    my $des = shift @ARGV;

    my @kits = split ',', $des;
    my @kitnames;
    my $hasplugin = 0;
    foreach my $kit (@kits) {

        my $kitdir = '';
        my $kittmpdir = '';
        my %kithash;
        my %kitrepohash;
        my %kitcomphash;

        # extract the Kit to kitdir
        my $installdir = xCAT::TableUtils->getInstallDir();
        unless($installdir){
            $installdir = '/install';
        }
        $installdir =~ s/\/$//;

        my $dir = $request->{cwd}; #getcwd;
        $dir = $dir->[0];

        unless(-r $kit){
            $kit = "$dir/$kit";
        }

        unless (-r $kit) {
            my %rsp;
            push@{ $rsp{data} }, "Can not find $kit";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }


        if(-d "$kit") {
            # This is a directory.
            # TODO: check if this is a valid kit directory.

            $kittmpdir = $kit;
        } else {
            # should be a tar.bz2 file

            system("rm -rf /tmp/tmpkit/");
            mkpath("/tmp/tmpkit/");
            
            if($::VERBOSE){
                my %rsp;
                push@{ $rsp{data} }, "Extract Kit $kit to /tmp";
                xCAT::MsgUtils->message( "I", \%rsp, $callback );
                $rc = system("tar jxvf $kit -C /tmp/tmpkit/");
            } else {
                $rc = system("tar jxf $kit -C /tmp/tmpkit/");
            }

            opendir($dir,"/tmp/tmpkit/");
            my @files = readdir($dir);

            foreach my $file ( @files ) {
                next if ( $file eq '.' || $file eq '..' );
                $kittmpdir = "/tmp/tmpkit/$file";
                last;
            }

            if ( !$kittmpdir ) {
                my %rsp;
                push@{ $rsp{data} }, "Could not find extracted kit in /tmp/tmpkit";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
        }


        if($rc){
            my %rsp;
            push@{ $rsp{data} }, "Failed to extract Kit $kit, (Maybe there was no space left?)";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        # Read kit info from kit.conf
        my @lines;
        if (open(KITCONF, "<$kittmpdir/$kitconf")) {
            @lines = <KITCONF>;
            close(KITCONF);
            if($::VERBOSE){
                my %rsp;
                push@{ $rsp{data} }, "Reading kit configuration file $kittmpdir/$kitconf";
                xCAT::MsgUtils->message( "I", \%rsp, $callback );
            }
        } else {
            my %rsp;
            push@{ $rsp{data} }, "Could not open kit configuration file $kittmpdir/$kitconf";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }


        #
        # check contents of kit.conf to make sure the framework
        #       is compatible with this codes framework
        if (&check_framework(\@lines)) {
            return 1;
        }

        my $sec;
        my $kitname;
        my $kitreponame;
        my $kitcompname;
        my $scripts;
        my $kitrepoid = 0;
        my $kitcompid = 0;
        foreach my $line (@lines) {
            # Read through each line of kit.conf.
            my $key, $value;
            chomp $line;
            next if ($line =~ /^$/);
            next if ($line =~ /^\s*#/);

            # Split the kit.conf to different parts: kit, kitrepo, kitcomponent.
            if ($line =~ /kit:/) {
                $sec = "KIT";
                next;
            } elsif ($line =~ /kitrepo:/) {
                $sec = "KITREPO";
                $kitrepoid = $kitrepoid + 1;
                next;
            } elsif ($line =~ /kitcomponent:/) {
                $sec = "KITCOMPONENT";
                $kitcompid = $kitcompid + 1;
                next;
            } else {
                ($key,$value) = split /=/, $line;
            }

            # Remove spaces in each lines.
            $key =~s/^\s+|\s+$//g;
            $value =~s/^\s+|\s+$//g;

            # Add each attribute to different hash.
            if ( $sec =~ /KIT$/) {
                $kithash{$key} = $value;
            } elsif ( $sec =~ /KITREPO$/ ) {    
                $kitrepohash{$kitrepoid}{$key} = $value;
            } elsif ( $sec =~ /KITCOMPONENT$/ ) {
                if ( $key =~ /postbootscripts/ or $key =~ /genimage_postinstall/ ) {
                    $scripts = $scripts . ',' . $value;
                    $kitcomphash{$kitcompid}{$key} = $value;
                } else {
                    $kitcomphash{$kitcompid}{$key} = $value;
                }
            }
        }

        #TODO:  add check to see the the attributes name are acceptable by xCAT DB.
        #TODO: need to check if the files are existing or not, like exlist,

        unless (keys %kithash) {
            my %rsp;
            push@{ $rsp{data} }, "Failed to add kit $kit because kit.conf is invalid";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( $inspection ) {
            my %rsp;
            push@{ $rsp{data} }, "kitname=$kithash{kitname}";
            push@{ $rsp{data} }, "    description=$kithash{description}";
            push@{ $rsp{data} }, "    version=$kithash{version}";
            push@{ $rsp{data} }, "    ostype=$kithash{ostype}";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
            next;
        }

        (my $ref1) = $tabs{kit}->getAttribs({kitname => $kithash{kitname}}, 'basename');
        if ( $ref1 and $ref1->{'basename'}){
            my %rsp;
            push@{ $rsp{data} }, "Failed to add kit $kithash{kitname} because it is already existing";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }


        # Check if the kitcomponent is existing
        my @kitcomps = $tabs{kitcomponent}->getAllAttribs( 'kitcompname' );
        foreach my $kitcomp (@kitcomps) {
            if ( $kitcomp->{kitcompname} ) {
                foreach my $kitcompid (keys %kitcomphash) {
                    if ( $kitcomphash{$kitcompid}{kitcompname} and $kitcomphash{$kitcompid}{kitcompname} =~ /$kitcomp->{kitcompname}/ ) {
                        my %rsp;
                        push@{ $rsp{data} }, "Failed to add kitcomponent $kitcomp->{kitcompname} because it is already existing";
                        xCAT::MsgUtils->message( "E", \%rsp, $callback );
                        return 1;
                    }
                }
            }
        }

        my %rsp;
        push@{ $rsp{data} }, "Adding Kit $kithash{kitname}";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );

        # Moving kits from tmp directory to kitdir
        if (!$path) {
            $kitdir = $installdir . "/kits";
        } else {
            $kitdir = $path;
        }

        $kitdir =~ s/\/$//;
        $kitdir = $kitdir . "/" . $kithash{kitname};

        if($::VERBOSE){
            my %rsp;
            push@{ $rsp{data} }, "Create Kit directory $kitdir";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
        }
        mkpath($kitdir);

        # Set kitdir and kitrepodir
        $kithash{kitdir} = $kitdir;

        foreach my $kitrepoid ( keys %kitrepohash ) {
            $kitrepohash{$kitrepoid}{kitrepodir} = $kitdir."/repos/".$kitrepohash{$kitrepoid}{kitreponame};
        }

        if($::VERBOSE){
            my %rsp;
            push@{ $rsp{data} }, "Copying Kit from $kittmpdir to $kitdir";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
            $rc = system("cp -rfv $kittmpdir/* $kitdir");
        } else {
            $rc = system("cp -rf $kittmpdir/* $kitdir");
        }

        # Coying scripts to /installdir/postscripts/
        if($::VERBOSE){
            my %rsp;
            push@{ $rsp{data} }, "Copying kit scripts from $kitdir/other_files/ to $installdir/postscripts";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
        }
        my @script = split ',', $scripts;
        foreach (@script) {
            next unless ($_);
            if($::VERBOSE){
                $rc = system("cp -rfv $kitdir/other_files/$_ $installdir/postscripts/");
            } else {
                $rc = system("cp -rf $kitdir/other_files/$_ $installdir/postscripts/");
            }
            chmod(0755,"$installdir/postscripts/$_");
        }

        if($rc){
            my %rsp;
            push@{ $rsp{data} }, "Failed to copy scripts from $kitdir/scripts/ to $installdir/postscripts";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        # Copying plugins to /opt/xcat/lib/perl/xCAT_plugin/
        if ( -d "$kitdir/plugins/" ) {

            chmod(644, "$kitdir/plugins/*");

            opendir($dir,"$kitdir/plugins/");
            if ( grep { ($_ ne '.') && ($_ ne '..') } readdir($dir) ) {
                if($::VERBOSE){
                    my %rsp;
                    push@{ $rsp{data} }, "Copying kit plugins from $kitdir/plugins/ to $::XCATROOT/lib/perl/xCAT_plugin";
                    xCAT::MsgUtils->message( "I", \%rsp, $callback );

                    $rc = system("cp -rfv $kitdir/plugins/* $::XCATROOT/lib/perl/xCAT_plugin/");
                } else {
                    $rc = system("cp -rf $kitdir/plugins/* $::XCATROOT/lib/perl/xCAT_plugin/");
                }

                $hasplugin = 1;
            }
        }

        if($rc){
            my %rsp;
            push@{ $rsp{data} }, "Failed to copy plugins from $kitdir/plugins/ to $::XCATROOT/lib/perl/xCAT_plugin";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        # Write to DB
        if($::VERBOSE){
            my %rsp;
            push@{ $rsp{data} }, "Writing kit configuration into xCAT DB";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
        }

        $rc = $tabs{kit}->setAttribs({kitname => $kithash{kitname} }, \%kithash );
        if($rc){
            my %rsp;
            push@{ $rsp{data} }, "Failed to write kit object into xCAT DB";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        foreach my $kitrepoid (keys %kitrepohash) {
            $rc = $tabs{kitrepo}->setAttribs({kitreponame => $kitrepohash{$kitrepoid}{kitreponame} }, \%{$kitrepohash{$kitrepoid}} );
            if($rc){
                my %rsp;
                push@{ $rsp{data} }, "Failed to write kitrepo $kitrepohash{$kitrepoid}{kitreponame} into xCAT DB";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
        }

        foreach my $kitcompid (keys %kitcomphash) {
            $rc = $tabs{kitcomponent}->setAttribs({kitcompname => $kitcomphash{$kitcompid}{kitcompname} }, \%{$kitcomphash{$kitcompid}} );
            if($rc){
                my %rsp;
                push@{ $rsp{data} }, "Failed to write kitcomponent $kitcomphash{$kitcompid}{kitcompname} xCAT DB";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
        }

        push @kitnames, $kithash{kitname};
    }

    unless ( $inspection ) {
        my $kitlist = join ',', @kitnames;
        my %rsp;
        push@{ $rsp{data} }, "Kit $kitlist was successfully added.";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );

        if ( $hasplugin ) {
            # Issue xcatd reload to load the new plugins
            system("/etc/init.d/xcatd reload");
        }
    }
}


#-------------------------------------------------------

=head3 rmkit

  Remove Kits from xCAT

=cut

#-------------------------------------------------------
sub rmkit
{
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;
    my $kitdir;
    my $rc;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "rmkit: remove Kits from xCAT";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\trmkit [-h|--help]";
        push@{ $rsp{data} }, "\trmkit [-f|--force] <kitlist>] [-V]";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    };

    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            $xusage->(1);
            return;
    }


    GetOptions(
            'h|help' => \$help,
            'V|verbose' => \$::VERBOSE,
            'f|force' => \$force
    );

    if($help){
            $xusage->(0);
            return;
    }

    my %tabs = ();
    my @tables = qw(kit kitrepo kitcomponent osimage);
    foreach my $t ( @tables ) {
        $tabs{$t} = xCAT::Table->new($t,-create => 1,-autocommit => 1);

        if ( !exists( $tabs{$t} )) {
            my %rsp;
            push@{ $rsp{data} }, "Could not open xCAT table $t";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }
    }

    # Convert to kitname if input is a basename
    my %kitnames;
    my $des = shift @ARGV;
    my @kits = split ',', $des;
    foreach my $kit (@kits) {

        # Check if it is a kitname or basename

        (my $ref1) = $tabs{kit}->getAttribs({kitname => $kit}, 'basename', 'isinternal');
        if ( $ref1 and $ref1->{'basename'}){
            if ( $ref1->{'isinternal'} and !$force ) {
                my %rsp;
                push@{ $rsp{data} }, "Kit $kit with isinterval attribute cannot be remoed";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
            $kitnames{$kit} = 1;
        } else {
            my @entries = $tabs{kit}->getAllAttribsWhere( "basename = '$kit'", 'kitname', 'isinternal');
            unless (@entries) {
                my %rsp;
                push@{ $rsp{data} }, "Kit $kit could not be found in DB $t";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
            foreach my $entry (@entries) {
                if ( $entry->{'isinternal'} and !$force ) {
                    my %rsp;
                    push@{ $rsp{data} }, "Kit $entry->{kitname} with isinterval attribute cannot be remoed";
                    xCAT::MsgUtils->message( "E", \%rsp, $callback );
                    return 1;
                }
                $kitnames{$entry->{kitname}} = 1;
            }
        }
    }

    # Remove each kit
    my @entries = $tabs{'osimage'}->getAllAttribs( 'imagename', 'kitcomponents' );
    my @kitlist;
    my $hasplugin;

    foreach my $kitname (keys %kitnames) {

        my %rsp;
        push@{ $rsp{data} }, "Removing kit $kitname";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );

        # Remove osimage.kitcomponents.

        # Find all the components in this kit.
        my $kitcompnames;
        my @kitcomphash = $tabs{kitcomponent}->getAllAttribsWhere( "kitname = '$kitname'", 'kitcompname', 'postbootscripts', 'genimage_postinstall');

        if (@entries && (@entries > 0)) {  

            if($::VERBOSE){
                my %rsp;
                push@{ $rsp{data} }, "Removing kit components from osimage.kitcomponents";
                xCAT::MsgUtils->message( "I", \%rsp, $callback );
            }

            foreach my $entry (@entries) {
                # Check osimage.kitcomponents
                my @kitcomponents = split ',', $entry->{kitcomponents};
                foreach my $kitcomponent ( @kitcomponents ) {
                    chomp $kitcomponent;

                    # Compare with each component in osimage.kitcomponents list.
                    foreach my $kitcomp ( @kitcomphash ) {
                        my $kitcompname =  $kitcomp->{kitcompname};
                        # Remove this component from osimage.kitcomponents if -f option.
                        if ("$kitcompname" =~ /^$kitcomponent$/) {
                            unless ($force) {
                                my %rsp;
                                push@{ $rsp{data} }, "Failed to remove kit component $kitcomponent because:$kitcomponent is being used by osimage $entry->{imagename}";
                                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                                return 1;
                            }

                            # Remove this component from osimage.kitcomponents. Mark here.
                            my $ret = xCAT::Utils->runxcmd({ command => ['rmkitcomp'], arg => ['-f','-u','-i',$entry->{imagename}, $kitcompname] }, $request_command, 0, 1);
                            if ( $::RUNCMD_RC ) {
                                my %rsp;
                                push@{ $rsp{data} }, "Failed to remove kit component $kitcomponent from $entry->{imagename}";
                                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                                return 1;
                            }
                        }
                    }
                }
            }
        }

        my $kitdir;
        (my $ref1) = $tabs{kit}->getAttribs({kitname => $kitname }, 'kitdir');
        if ( $ref1 and $ref1->{'kitdir'}){

            $kitdir = $ref1->{'kitdir'};
            chomp $kitdir;

            # remove kit plugins from /opt/xcat/lib/perl/xCAT_plugin
            if($::VERBOSE){
                my %rsp;
                push@{ $rsp{data} }, "Removing kit plugins from $::XCATROOT/lib/perl/xCAT_plugin/";
                xCAT::MsgUtils->message( "I", \%rsp, $callback );
            }

            opendir($dir, $kitdir."/plugins");
            my @files = readdir($dir);
            if ( grep { ($_ ne '.') && ($_ ne '..') } @files ) {
                $hasplugin = 1;
            }
            foreach my $file (@files) {
                if ($file eq '.' or $file eq '..') { next; }
                if ( -e "$::XCATROOT/lib/perl/xCAT_plugin/$file" ) {
                    if($::VERBOSE){
                        system("rm -rfv $::XCATROOT/lib/perl/xCAT_plugin/$file");
                    } else {
                        system("rm -rf $::XCATROOT/lib/perl/xCAT_plugin/$file");
                    }
                }
            }


            if($::VERBOSE){
                my %rsp;
                push@{ $rsp{data} }, "Removing kit scripts from /install/postscripts/";
                xCAT::MsgUtils->message( "I", \%rsp, $callback );
            }
            # remove kit scripts from /install/postscripts/
            my $installdir = xCAT::TableUtils->getInstallDir();
            unless($installdir){
                $installdir = '/install';
            }
            $installdir =~ s/\/$//;

            my $scripts;
            foreach my $kitcomp ( @kitcomphash ) {
                $scripts = $scripts.",".$kitcomp->{postbootscripts} if ( $kitcomp->{postbootscripts} );
                $scripts = $scripts.",".$kitcomp->{genimage_postinstall} if ( $kitcomp->{genimage_postinstall} );
            }
            $scripts =~ s/^,//;
            my @files = split /,/, $scripts;
            foreach my $file (@files) {
                if ($file eq '.' or $file eq '..') { next; }
                if ( -e "$installdir/postscripts/$file" ) {
                    if($::VERBOSE){
                        system("rm -rfv $installdir/postscripts/$file");
                    } else {
                        system("rm -rf $installdir/postscripts/$file");
                    }
                }
            }

            # remove kitdir from /install/kits/
            if($::VERBOSE){
                my %rsp;
                push@{ $rsp{data} }, "Removing kitdir from installdir";
                xCAT::MsgUtils->message( "I", \%rsp, $callback );
                system("rm -rfv $kitdir");
            } else {
                system("rm -rf $kitdir");
            }
        }


        if($::VERBOSE){
            my %rsp;
            push@{ $rsp{data} }, "Removing kit from xCAT DB";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
        }
        # Remove kitcomponent 
        foreach my $kitcomp ( @kitcomphash ) {
            my $kitcompname =  $kitcomp->{kitcompname};
            $tabs{kitcomponent}->delEntries({kitcompname => $kitcompname});
        }

        # Remove kitrepo
        my @kitrepohash = $tabs{kitrepo}->getAllAttribsWhere( "kitname = '$kitname'", 'kitreponame');
        foreach my $kitrepo ( @kitrepohash ) {
            my $kitreponame =  $kitrepo->{kitreponame};
            $tabs{kitrepo}->delEntries({kitreponame => $kitreponame});
        }

        # Remove kit
        $tabs{kit}->delEntries({kitname => $kitname});

        push @kitlist, $kitname;

    }

    my $kits = join ',', @kitlist;
    my %rsp;
    push@{ $rsp{data} }, "Kit $kits was successfully removed.";
    xCAT::MsgUtils->message( "I", \%rsp, $callback );

    if ( $hasplugin ) {
        # Issue xcatd reload to load the new plugins
        system("/etc/init.d/xcatd reload");
    }

}

#-------------------------------------------------------

=head3 addkitcomp

  Assign Kit component to osimage 

=cut

#-------------------------------------------------------
sub addkitcomp
{
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;
    my $kitdir;
    my $rc;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "addkitcomp: assign kit component to osimage";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\taddkitcomp [-h|--help]";
        push@{ $rsp{data} }, "\taddkitcomp [-a|--adddeps] [-f|--force] [-n|--noupgrade] [-V|--verbose] -i <osimage> <kitcompname_list>";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    };

    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            $xusage->(1);
            return;
    }


    GetOptions(
            'h|help' => \$help,
            'V|verbose' => \$::VERBOSE,
            'a|adddeps' => \$adddeps,
            'f|force' => \$force,
            'n|noupgrade' => \$::noupgrade,
            'i=s' => \$osimage
    );

    if($help){
            $xusage->(0);
            return;
    }

    my %tabs = ();
    my @tables = qw(kit kitrepo kitcomponent osimage osdistro linuximage);
    foreach my $t ( @tables ) {
        $tabs{$t} = xCAT::Table->new($t,-create => 1,-autocommit => 1);

        if ( !exists( $tabs{$t} )) {
            my %rsp;
            push@{ $rsp{data} }, "Could not open xCAT table $t";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }
    }

    # Check if all the kitcomponents are existing before processing

    if($::VERBOSE){
        my %rsp;
        push@{ $rsp{data} }, "Checking if kitcomponents are valid";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    }

    my %kitcomps;
    my $des = shift @ARGV;
    my @kitcomponents = split ',', $des;
    foreach my $kitcomponent (@kitcomponents) {

        # Check if it is a kitcompname or basename
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomponent}, 'kitname', 'basename');
        if ( $kitcomptable and $kitcomptable->{'basename'}){
            $kitcomps{$kitcomponent}{name} = $kitcomponent;
            $kitcomps{$kitcomponent}{basename} = $kitcomptable->{'basename'};
        } else {
            my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcomponent'", 'kitcompname' , 'version', 'release');
            unless (@entries) {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomponent kitcomponent does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
            
            my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);
            $kitcomps{$highest}{name} = $highest;
            $kitcomps{$highest}{basename} = $kitcomponent;
        }
    }

    # Verify if the kitcomponents fitting to the osimage or not.

    if($::VERBOSE){
        my %rsp;
        push@{ $rsp{data} }, "Verifying if kitcomponents fit to osimage";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    }

    my %os;
    my $osdistrotable;
    (my $osimagetable) = $tabs{osimage}->getAttribs({imagename=> $osimage}, 'osdistroname', 'serverrole', 'kitcomponents', 'osname', 'osvers', 'osarch');
    if ( $osimagetable and $osimagetable->{'osdistroname'}){
        ($osdistrotable) = $tabs{osdistro}->getAttribs({osdistroname=> $osimagetable->{'osdistroname'}}, 'basename', 'majorversion', 'minorversion', 'arch', 'type');
        if ( !$osdistrotable or !$osdistrotable->{basename} ) {
            my %rsp;
            push @{ $rsp{data} }, "$osdistroname osdistro does not exist";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        } 

        # Read basename,majorversion,minorversion,arch,type, from osdistro table
        $os{$osimage}{basename} = lc($osdistrotable->{basename});
        $os{$osimage}{majorversion} = lc($osdistrotable->{majorversion});
        $os{$osimage}{minorversion} = lc($osdistrotable->{minorversion});
        $os{$osimage}{arch} = lc($osdistrotable->{arch});
        $os{$osimage}{type} = lc($osdistrotable->{type});

        # Read serverrole from osimage.
        $os{$osimage}{serverrole} = lc($osimagetable->{'serverrole'});

    } elsif ( !$osimagetable or !$osimagetable->{'osname'} ) {
        my %rsp;
        push@{ $rsp{data} }, "osimage $osimage does not contains a valid 'osname' attribute";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;

    } elsif ( !$osimagetable->{'osvers'} ) {
        my %rsp;
        push@{ $rsp{data} }, "osimage $osimage does not contains a valid 'osvers' attribute";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    } elsif ( !$osimagetable->{'osarch'} ) {
        my %rsp;
        push@{ $rsp{data} }, "osimage $osimage does not contains a valid 'osarch' attribute";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    } else {
        $os{$osimage}{type} = lc($osimagetable->{'osname'});
        $os{$osimage}{arch} = lc($osimagetable->{'osarch'});
        $os{$osimage}{serverrole} = lc($osimagetable->{'serverrole'});
 
        my ($basename, $majorversion, $minorversion) = $osimagetable->{'osvers'} =~ /^(\D+)(\d+)\W+(\d+)/;
        $os{$osimage}{basename} = lc($basename);
        $os{$osimage}{majorversion} = lc($majorversion);
        $os{$osimage}{minorversion} = lc($minorversion);
    }


    foreach my $kitcomp ( keys %kitcomps ) {
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomp}, 'kitname', 'kitreponame', 'serverroles', 'kitcompdeps');
        if ( $kitcomptable and $kitcomptable->{'kitname'} and $kitcomptable->{'kitreponame'}) {

            # Read serverroles from kitcomponent table 
            $kitcomps{$kitcomp}{serverroles} = lc($kitcomptable->{'serverroles'});
 
            # Read ostype from kit table
            (my $kittable) = $tabs{kit}->getAttribs({kitname => $kitcomptable->{'kitname'}}, 'ostype');
            if ( $kittable and $kittable->{ostype} ) {
                $kitcomps{$kitcomp}{ostype} = lc($kittable->{ostype});
            } else {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomptable->{'kitname'} ostype does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            # Read osbasename, osmajorversion,osminorversion,osarch,compat_osbasenames from kitrepo table
            (my $kitrepotable) = $tabs{kitrepo}->getAttribs({kitreponame => $kitcomptable->{'kitreponame'}}, 'osbasename', 'osmajorversion', 'osminorversion', 'osarch', 'compat_osbasenames');
            if ($kitrepotable and $kitrepotable->{osbasename} and $kitrepotable->{osmajorversion} and $kitrepotable->{osarch}) {
                if ($kitrepotable->{compat_osbasenames}) {
                    $kitcomps{$kitcomp}{osbasename} = lc($kitrepotable->{osbasename}) . ',' . lc($kitrepotable->{compat_osbasenames});
                } else {
                    $kitcomps{$kitcomp}{osbasename} = lc($kitrepotable->{osbasename});
                }

                $kitcomps{$kitcomp}{osmajorversion} = lc($kitrepotable->{osmajorversion});
                $kitcomps{$kitcomp}{osminorversion} = lc($kitrepotable->{osminorversion});
                $kitcomps{$kitcomp}{osarch} = lc($kitrepotable->{osarch});
            } else {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomp osbasename,osmajorversion,osminorversion or osarch does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
                            
        }  else {
            my %rsp;
            push@{ $rsp{data} }, "$kitcomp kitname or kitrepo name does not exist";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( !$force ) {

            # Validate each attribute in kitcomp.
            my $catched = 0;
            my @osbasename = split ',', $kitcomps{$kitcomp}{osbasename}; 
            foreach (@osbasename) {
                if ( $os{$osimage}{basename} eq $_ ) {
                    $catched = 1;
                }
            }

            unless ( $catched ) {
                my %rsp;
                push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute OS";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            if ( $os{$osimage}{majorversion} ne $kitcomps{$kitcomp}{osmajorversion} ) {
                my %rsp;
                push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute majorversion";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            if ( $kitcomps{$kitcomp}{osminorversion} and ($os{$osimage}{minorversion} ne $kitcomps{$kitcomp}{osminorversion}) ) {
                my %rsp;
                push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute minorversion";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            if ( $os{$osimage}{arch} ne $kitcomps{$kitcomp}{osarch} ) {
                my %rsp;
                push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute arch";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            if ( $os{$osimage}{type} ne $kitcomps{$kitcomp}{ostype} ) {
                my %rsp;
                push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute type";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            if ( $os{$osimage}{serverrole} ) {
                my $match = 0;
                my @os_serverroles = split /,/, $os{$osimage}{serverrole};
                my @kitcomp_serverroles = split /,/, $kitcomps{$kitcomp}{serverroles};
                foreach my $os_serverrole (@os_serverroles) {
                    foreach my $kitcomp_serverrole (@kitcomp_serverroles) {
                        if ( $os_serverrole eq $kitcomp_serverrole ) {
                            $match = 1;
                            last;
                        }
                    }

                    if ( $match ) {
                        last;
                    }
                }
                if ( !$match ) {
                    my %rsp;
                    push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute serverrole";
                    xCAT::MsgUtils->message( "E", \%rsp, $callback );
                    return 1;
                }
            }

            if ( $kitcomptable and $kitcomptable->{'kitcompdeps'} ) {
                my @kitcompdeps = split ',', $kitcomptable->{'kitcompdeps'};
                foreach my $kitcompdep ( @kitcompdeps ) {
                    my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcompdep'", 'kitcompname' , 'version', 'release');
                    unless (@entries) {
                        my %rsp;
                        push@{ $rsp{data} }, "Cannot find any matched kit component for kit component $kitcomp dependency $kitcompdep";
                        xCAT::MsgUtils->message( "E", \%rsp, $callback );
                        return 1;
                    }

                    my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);

                    if ( $adddeps ) {
                        if ( !$kitcomps{$highest}{name} ) {
                            $kitcomps{$highest}{name} = $highest;
                        }
                    } else {

                        my $catched = 0;
                        if ( $osimagetable and $osimagetable->{'kitcomponents'}) {
                            my @oskitcomps = split ',', $osimagetable->{'kitcomponents'};
                            foreach my $oskitcomp ( @oskitcomps ) {
                                if ( $highest eq $oskitcomp ) {
                                    $catched =  1;
                                    last;
                                }
                            }
                        }

                        foreach my $k ( keys %kitcomps ) {
                            if ( $kitcomps{$k}{basename} and $kitcompdep eq $kitcomps{$k}{basename} ) {
                                $catched =  1;
                                last;
                            }
                        }

                        if ( !$catched ) {
                            my %rsp;
                            push@{ $rsp{data} }, "kit component dependency $highest for kit component $kitcomp is not existing in osimage or specified in command line";
                            xCAT::MsgUtils->message( "E", \%rsp, $callback );
                            return 1;
                        }
                    }
                }
            }
        }

        if($::VERBOSE){
            my %rsp;
            push@{ $rsp{data} }, "kitcomponent $kitcomp fits to osimage $osimage";
            xCAT::MsgUtils->message( "I", \%rsp, $callback );
        }
    }
    
    # Now assign each component to the osimage

    if($::VERBOSE){
        my %rsp;
        push@{ $rsp{data} }, "Assigning kitcomponent to osimage";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    }

    my @kitcomps;
    my @oskitcomps;
    my $catched = 0;
    my @kitlist;

    if ( $osimagetable and $osimagetable->{'kitcomponents'}) {
        @oskitcomps = split ',', $osimagetable->{'kitcomponents'};
    }

    my @newkitcomps = keys %kitcomps;
    foreach ( keys %kitcomps ) {
        my $kitcomp = shift @newkitcomps;

        my %rsp;
        push@{ $rsp{data} }, "Assigning kit component $kitcomp to osimage $osimage";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
        # Check if this component is existing in osimage.kitcomponents
        foreach my $oskitcomp ( @oskitcomps ) {
            if ( $kitcomp eq $oskitcomp ) {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomp kit component is already in osimage $osimage";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                $catched = 1;
            }
        }

        # No matching kitcomponent name in osimage.kitcomponents, now checking their basenames.
        if ( !$catched ) {

            my $add = 0;
            foreach my $oskitcomp ( @oskitcomps ) {

                # Compare this kit component's basename with basenames in osimage.kitcomponents
                (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomp}, 'basename', 'version', 'release');
                if ( !$kitcomptable or !$kitcomptable->{'basename'} ) {
                    my %rsp;
                    push@{ $rsp{data} }, "$kitcomp kit component does not have basename";
                    xCAT::MsgUtils->message( "E", \%rsp, $callback );
                    return 1;
                }
                (my $oskitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $oskitcomp}, 'basename', 'version', 'release');
                if ( !$oskitcomptable or !$oskitcomptable->{'basename'} ) {
                    my %rsp;
                    push@{ $rsp{data} }, "$oskitcomp kit component does not have basename";
                    xCAT::MsgUtils->message( "I", \%rsp, $callback );
                    next;
                }

                if ( $kitcomptable->{'basename'} eq $oskitcomptable->{'basename'} ) {
                    my $rc = compare_version($oskitcomptable,$kitcomptable,'kitcompname', 'version', 'release');
                    if ( $rc == 1 and !$::noupgrade  ) {
                        my %rsp;
                        push@{ $rsp{data} }, "Upgrading kit component $oskitcomp to $kitcomp";
                        xCAT::MsgUtils->message( "I", \%rsp, $callback );
                        my $ret = xCAT::Utils->runxcmd({ command => ['rmkitcomp'], arg => ['-f','-u','-i',$osimage, $oskitcomp] }, $request_command, -2, 1);
                        if ( !$ret ) {
                            my %rsp;
                            push@{ $rsp{data} }, "Failed to remove kit component $kitcomp from $osimage";
                            xCAT::MsgUtils->message( "E", \%rsp, $callback );
                            return 1;
                        }
                        $add = 1;
                    } elsif ( $rc == 0 ) {
                        my %rsp;
                        push@{ $rsp{data} }, "Do nothing since kit component $oskitcomp in osimage $osimage has the same basename/version and release with kit component $kitcomp";
                        xCAT::MsgUtils->message( "I", \%rsp, $callback );
                        next;
                    } elsif ( !$::noupgrade ) {
                        my %rsp;
                        push@{ $rsp{data} }, "kit component $oskitcomp is already in osimage $osimage, and has a newer release/version than $kitcomp.  Downgrading kit component is not supported";
                        xCAT::MsgUtils->message( "E", \%rsp, $callback );
                        return 1;
                    }
                }
            }
            # Now assign this component to osimage
            my $rc = assign_to_osimage( $osimage, $kitcomp, $callback, \%tabs);                
        }
            
        push @kitlist, $kitcomp;
    }

    my $kitnames = join ',', @kitlist;
    my %rsp;
    push@{ $rsp{data} }, "Kit components $kitnames were added to osimage $osimage successfully";
    xCAT::MsgUtils->message( "I", \%rsp, $callback );

    return;
}

#-------------------------------------------------------

=head3 rmkitcomp

  Remove Kit component from osimage 

=cut

#-------------------------------------------------------
sub rmkitcomp
{

    my $request = shift;
    my $callback = shift;
    my $request_command = shift;
    my $kitdir;
    my $rc;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "rmkitcomp: remove kit component from osimage";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\trmkitcomp [-h|--help]";
        push@{ $rsp{data} }, "\trmkitcomp [-u|--uninstall] [-f|--force] [-V|--verbose] -i <osimage> <kitcompname_list>";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    };

    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            $xusage->(1);
            return;
    }


    GetOptions(
            'h|help' => \$help,
            'V|verbose' => \$::VERBOSE,
            'u|uninstall' => \$uninstall,
            'f|force' => \$force,
            'i=s' => \$osimage
    );

    if($help){
            $xusage->(0);
            return;
    }

    my %tabs = ();
    my @tables = qw(kit kitrepo kitcomponent osimage osdistro linuximage);
    foreach my $t ( @tables ) {
        $tabs{$t} = xCAT::Table->new($t,-create => 1,-autocommit => 1);

        if ( !exists( $tabs{$t} )) {
            my %rsp;
            push@{ $rsp{data} }, "Could not open xCAT table $t";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
            return 1;
        }
    }


    # Check if all the kitcomponents are existing before processing

    if($::VERBOSE){
        my %rsp;
        push@{ $rsp{data} }, "Checking if kitcomponents are valid";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    }

    my %kitcomps;
    my $des = shift @ARGV;
    my @kitcomponents = split ',', $des;
    foreach my $kitcomponent (@kitcomponents) {

        # Check if it is a kitcompname or basename
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomponent}, 'kitname', 'kitpkgdeps', 'prerequisite', 'postbootscripts', 'genimage_postinstall', 'kitreponame', 'exlist', 'basename', 'driverpacks');
        if ( $kitcomptable and $kitcomptable->{'kitname'}){
            $kitcomps{$kitcomponent}{name} = $kitcomponent;
            $kitcomps{$kitcomponent}{kitname} = $kitcomptable->{kitname};
            $kitcomps{$kitcomponent}{kitpkgdeps} = $kitcomptable->{kitpkgdeps};
            $kitcomps{$kitcomponent}{prerequisite} = $kitcomptable->{prerequisite};
            $kitcomps{$kitcomponent}{basename} = $kitcomptable->{basename};
            $kitcomps{$kitcomponent}{exlist} = $kitcomptable->{exlist};
            $kitcomps{$kitcomponent}{postbootscripts} = $kitcomptable->{postbootscripts};
            $kitcomps{$kitcomponent}{kitreponame} = $kitcomptable->{kitreponame};
            $kitcomps{$kitcomponent}{driverpacks} = $kitcomptable->{driverpacks};
            $kitcomps{$kitcomponent}{genimage_postinstall} = $kitcomptable->{genimage_postinstall};
        } else {
            my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcomponent'", 'kitcompname' , 'version', 'release');
            unless (@entries) {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomponent kitcomponent does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);
            $kitcomps{$highest}{name} = $highest;
            (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $highest}, 'kitname', 'kitpkgdeps', 'prerequisite', 'postbootscripts', 'genimage_postinstall', 'kitreponame', 'exlist', 'basename', 'driverpacks');
            $kitcomps{$highest}{kitname} = $kitcomptable->{kitname};
            $kitcomps{$highest}{kitpkgdeps} = $kitcomptable->{kitpkgdeps};
            $kitcomps{$highest}{prerequisite} = $kitcomptable->{prerequisite};
            $kitcomps{$highest}{basename} = $kitcomptable->{basename};
            $kitcomps{$highest}{exlist} = $kitcomptable->{exlist};
            $kitcomps{$highest}{postbootscripts} = $kitcomptable->{postbootscripts};
            $kitcomps{$highest}{kitreponame} = $kitcomptable->{kitreponame};
            $kitcomps{$highest}{driverpacks} = $kitcomptable->{driverpacks};
            $kitcomps{$highest}{genimage_postinstall} = $kitcomptable->{genimage_postinstall};
        }
    }
    # Check if the kitcomponents are existing in osimage.kitcomponents attribute.

    (my $osimagetable) = $tabs{osimage}->getAttribs({imagename => $osimage}, 'kitcomponents', 'postbootscripts', 'provmethod');
    if ( !$osimagetable or !$osimagetable->{'kitcomponents'} ){
        my %rsp;
        push@{ $rsp{data} }, "$osimage osimage does not exist or not includes any kit components";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    }

    if ( !$osimagetable->{'provmethod'} ){
        my %rsp;
        push@{ $rsp{data} }, "$osimage osimage is missing provmethod";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    }
    my @osikitcomps = split ',', $osimagetable->{'kitcomponents'};
    foreach my $osikitcomp ( @osikitcomps ) {
        if ( exists($kitcomps{$osikitcomp}) ) {
            $kitcomps{$osikitcomp}{matched} = 1;
        }
    } 
    my $invalidkitcomp = '';
    foreach my $kitcomp ( keys %kitcomps) {
        if ( !$kitcomps{$kitcomp}{matched} ) {
            if ( !$invalidkitcomp ) {
                $invalidkitcomp = $kitcomp;
            } else {
                $invalidkitcomp = join(',', $invalidkitcomp, $kitcomp);
            }
        }
    }

    if ( $invalidkitcomp ) {
        my %rsp;
        push@{ $rsp{data} }, "$invalidkitcomp kit components are not assigned to osimage $osimage";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    }

    # Now check if there is any other kitcomponent depending on this one.

    foreach my $kitcomponent (keys %kitcomps) {
        foreach my $osikitcomp ( @osikitcomps ) {
            (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $osikitcomp}, 'kitcompdeps');
            if ( $kitcomptable and $kitcomptable->{'kitcompdeps'} ) {

                my @kitcompdeps = split(',', $kitcomptable->{'kitcompdeps'});
                foreach my $kitcompdep (@kitcompdeps) {

                    # Get the kit component full name from basename.
                    my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcompdep'", 'kitcompname' , 'version', 'release');
                    unless (@entries) {
                        my %rsp;
                        push@{ $rsp{data} }, "kitcomponent $kitcompdep basename does not exist";
                        xCAT::MsgUtils->message( "E", \%rsp, $callback );
                        return 1;
                    }

                    my $kitcompdepname = get_highest_version('kitcompname', 'version', 'release', @entries);

                    if ( ($kitcomponent eq $kitcompdepname) and !$force and !exists($kitcomps{$osikitcomp}) ) {
                        # There is other kitcomponent depending on this one and there is no --force option
                        my %rsp;
                        push@{ $rsp{data} }, "Failed to remove kitcomponent $kitcomponent because $osikitcomp is still depending on it.  Use -f option to remove it anyway";
                        xCAT::MsgUtils->message( "E", \%rsp, $callback );
                        return 1;
                    }
                }
            }
        }
    }


    # Reading installdir
    my $installdir = xCAT::TableUtils->getInstallDir();
    unless($installdir){
        $installdir = '/install';
    }
    $installdir =~ s/\/$//;


    # Remove each kitcomponent from osimage.

    my @newosikitcomps;
    foreach my $osikitcomp ( @osikitcomps ) {
        my $match = 0;
        foreach my $kitcomponent (keys %kitcomps) {
            if ( $kitcomponent eq $osikitcomp ) {
                $match = 1;
                last;
            }
        }
        if (!$match) {
            push @newosikitcomps, $osikitcomp;
        }
    }

    my $newosikitcomp = join ',', @newosikitcomps;
    $osimagetable->{'kitcomponents'} = $newosikitcomp; 


    # Remove kitcomponent.postbootscripts and kitcomponent.genimage_postinstall from osimage.postbootscripts.

    my @osimagescripts;
    my @newosimagescripts;
    if ( $osimagetable and $osimagetable->{'postbootscripts'} ){
        @osimagescripts = split( ',', $osimagetable->{'postbootscripts'} );
    }

    foreach my $osimagescript (@osimagescripts) {
        my $match = 0;
        foreach my $kitcomponent (keys %kitcomps) {
            my @kitcompscripts = split( ',', $kitcomps{$kitcomponent}{postbootscripts} );
            foreach my $kitcompscript ( @kitcompscripts ) {
                if ( $osimagescript =~ /^$kitcompscript$/ ) {
                    $match = 1;
                    last;
                }
            }

            last if ($match);
        }

        if (!$match) {
            push @newosimagescripts, $osimagescript;
        }

        #Remove genimage_postinstall from osimage.postbootscripts 
        if ( $osimagescript =~ /KIT_$osimage.postbootscripts/ and -e "$installdir/postscripts/KIT_$osimage.postbootscripts" ) {
            foreach my $kitcomponent (keys %kitcomps) {

                my @postbootlines;
                my @newlines;
                if (open(POSTBOOTSCRIPTS, "<", "$installdir/postscripts/KIT_$osimage.postbootscripts")) {
                    @postbootlines = <POSTBOOTSCRIPTS>;
                    close(POSTBOOTSCRIPTS);
                }

                my $match = 0;
                my @kitcompscripts = split( ',', $kitcomps{$kitcomponent}{genimage_postinstall} );
                foreach my $line ( @postbootlines ) {
                    chomp $line;
                    foreach my $kitcompscript ( @kitcompscripts ) {
                        if ( grep(/$kitcompscript/, $line) ) {
                            $match = 1;
                        }
                    }

                    if ( !$match ) {
                        push @newlines, $line."\n";
                    }
                }

                # Now write the new postbootscripts file.
                if (open(NEWEXLIST, ">", "$installdir/postscripts/KIT_$osimage.postbootscripts")) {
                    print NEWEXLIST @newlines;
                    close(NEWEXLIST);
                }
            }
        }
    }

    my $newosimagescript = join ',', @newosimagescripts;
    $osimagetable->{'postbootscripts'} = $newosimagescript;

    # Remove symlink from osimage.otherpkgdir.

    (my $linuximagetable) = $tabs{linuximage}->getAttribs({imagename=> $osimage}, 'postinstall', 'exlist', 'otherpkglist', 'otherpkgdir', 'driverupdatesrc');
    if ( $linuximagetable and $linuximagetable->{otherpkgdir} ) {

        my $otherpkgdir = $linuximagetable->{otherpkgdir};
        foreach my $kitcomponent (keys %kitcomps) {

            if ( $kitcomps{$kitcomponent}{kitreponame} ) {
                if ( -d "$otherpkgdir/$kitcomps{$kitcomponent}{kitreponame}" ) {

                    # Check if this repo is used by other kitcomponent before removing the link
                    my $match = 0;
                    foreach my $osikitcomp ( @osikitcomps ) {
                        next if ( $osikitcomp =~ /$kitcomponent/ );
                        my $depkitrepodir;
                        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $osikitcomp}, 'kitreponame');
                        if ( $kitcomptable and $kitcomptable->{kitreponame} ) {
                            $depkitrepodir = "$otherpkgdir/$kitcomptable->{kitreponame}";
                        }
                        if ( $depkitrepodir =~ /^$otherpkgdir\/$kitcomps{$kitcomponent}{kitreponame}$/) {
                            $match = 1;
                        }
                    }
                    if ( !$match ) {
                        system("rm -rf $otherpkgdir/$kitcomps{$kitcomponent}{kitreponame}");
                    }
                }
            }
        }
    }

    # Remove genimage_postinstall from linuximage table
    if ( $linuximagetable->{postinstall} ) {
        my @scripts = split ',', $linuximagetable->{postinstall};
        foreach my $script ( @scripts ) {
            if ( $script =~ /KIT_COMPONENTS.postinstall/ and -e "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall" ) {

                foreach my $kitcomponent (keys %kitcomps) {

                    my @postinstalllines;
                    my @newlines;
                    if (open(POSTINSTALLSCRIPTS, "<", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall") ) { 
                        @postinstalllines = <POSTINSTALLSCRIPTS>;
                        close(POSTINSTALLSCRIPTS);
                    }

                    my @kitcompscripts = split( ',', $kitcomps{$kitcomponent}{genimage_postinstall} );
                    foreach my $line ( @postinstalllines ) {
                        chomp $line;
                        my $match = 0;
                        foreach my $kitcompscript ( @kitcompscripts ) {

                            if ( grep(/$kitcompscript/, $line) ) {
                                $match = 1;
                                last;
                            }
                        }
                        if ( !$match ) {
                            push @newlines, $line."\n";
                        }
                    }

                    # Now write the new postbootscripts file.
                    if (open(NEWEXLIST, ">", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.postinstall")) {
                        print NEWEXLIST @newlines;
                        close(NEWEXLIST);
                    }
                }
            }
        }
    }

    # Remove kitcomponent exlist,otherpkglist and deploy_params from osimage

    my @kitlist;
    foreach my $kitcomponent (keys %kitcomps) {

        my %rsp;
        push@{ $rsp{data} }, "Removing kitcomponent $kitcomponent from osimage $osimage";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );

        if ( !exists($kitcomps{$kitcomponent}{kitname}) ) {
            my %rsp;
            push@{ $rsp{data} }, "Could not find kit object for kitcomponent $kitcomponent";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        } 

        # Reading kitdir
        my $kitdir = '';
        my $exlistfile = '';
        my $kitname = $kitcomps{$kitcomponent}{kitname};
        (my $kittable) = $tabs{kit}->getAttribs({kitname=> $kitname}, 'kitdir', 'kitdeployparams');


        # Removing exlist

        if ( $linuximagetable and $linuximagetable->{exlist} ) {
            my $match = 0;
            my @exlists= split ',', $linuximagetable->{exlist};
            foreach my $exlist ( @exlists ) {
                if ( $exlist =~ /^$installdir\/osimages\/$osimage\/kits\/KIT_COMPONENTS.exlist$/ ) {
                    $match = 1;
                    last;
                }
            }
    
            my @lines = ();
            if ( $match and -e "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist" ) {
                if (open(EXLIST, "<", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist")) {
                    @lines = <EXLIST>;
                    if($::VERBOSE){
                        my %rsp;
                        push@{ $rsp{data} }, "Reading kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist";
                        xCAT::MsgUtils->message( "I", \%rsp, $callback );
                    }
                } else {
                    my %rsp;
                    push@{ $rsp{data} }, "Could not open kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist";
                    xCAT::MsgUtils->message( "E", \%rsp, $callback );
                    return 1;
                }

                if ( $kittable and $kittable->{kitdir} ) {
                    $kitdir = $kittable->{kitdir};
                }

                if ( exists($kitcomps{$kitcomponent}{exlist}) ) {
                    $exlistfile = $kitcomps{$kitcomponent}{exlist};
                }

                my @newlines = ();
                foreach my $line ( @lines ) {
                    chomp $line;
                    if ( $line =~ /^#INCLUDE:$kitdir\/other_files\/$exlistfile#$/ ) {
                        next;
                    }
                    push @newlines, $line . "\n";
                }
                if (open(NEWEXLIST, ">", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist")) {
                    print NEWEXLIST @newlines;
                    close(NEWEXLIST);
                }

            }
        }
            
        # Removing otherpkglist

        if ( $linuximagetable and $linuximagetable->{otherpkglist} ) {
            my $match = 0;
            my @lines = ();

            my @otherpkglists = split ',', $linuximagetable->{otherpkglist};
            foreach my $otherpkglist ( @otherpkglists ) {
                if ( $otherpkglist =~ /^$installdir\/osimages\/$osimage\/kits\/KIT_COMPONENTS.otherpkgs.pkglist$/ ) {
                    $match = 1;
                    last;
                }
            }

            if ( $match and -e "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist" ) {
                if (open(OTHERPKGLIST, "<", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist")) {
                    @lines = <OTHERPKGLIST>;
                    if($::VERBOSE){
                        my %rsp;
                        push@{ $rsp{data} }, "Reading kit component otherpkg pkglist $installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist";
                        xCAT::MsgUtils->message( "I", \%rsp, $callback );
                    }
                } else {
                    my %rsp;
                    push@{ $rsp{data} }, "Could not open kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist";
                    xCAT::MsgUtils->message( "E", \%rsp, $callback );
                    return 1;
                }

                my $basename = '';
                if ( exists($kitcomps{$kitcomponent}{basename}) and exists($kitcomps{$kitcomponent}{kitreponame})) {
                    $basename = $kitcomps{$kitcomponent}{basename};
                    my $kitreponame = $kitcomps{$kitcomponent}{kitreponame};

                    my @newlines = ();
                    my $num = 0;
                    my $inlist = 0;
                    foreach my $line ( @lines ) {
                        chomp $line;
                        
                        if ( $line =~ /^#NEW_INSTALL_LIST#/ ) {
                            $num = 1;
                            $inlist = 1;
                        }
                        if ( $kitcomps{$kitcomponent}{prerequisite} ) {
                            if ( $line =~ /^$kitreponame\/prep_$basename$/ ) {
                                if ( $inlist ) {
                                    $num--;
                                    foreach ( 1..$num ) {
                                        pop @newlines;
                                    }
                                }
                                next;
                            }
                        }
                        if ( $line =~ /^$kitreponame\/$basename$/ ) {
                            if ( $inlist ) {
                                $num--;
                                foreach ( 1..$num ) {
                                    pop @newlines;
                                }
                            }
                            next;
                        }
                        push @newlines, $line . "\n";
                        $num++;
                    }

                    if (open(NEWOTHERPKGLIST, ">", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist")) {
                        print NEWOTHERPKGLIST @newlines;
                        close(NEWOTHERPKGLIST);
                    }
                }
            }

            # Add this component basename and pkgnames to KIT_RMPKGS.otherpkg.pkglist
            if ( $uninstall ) {
                my @lines = ();

                mkpath("$installdir/osimages/$osimage/kits/");

                if ( -e "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist" ) {
                    if (open(RMOTHERPKGLIST, "<", "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist")) {
                        @lines = <RMOTHERPKGLIST>;
                        close(RMOTHERPKGLIST);
                        if($::VERBOSE){
                            my %rsp;
                            push@{ $rsp{data} }, "Reading kit component rmpkgs file $installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist";
                            xCAT::MsgUtils->message( "I", \%rsp, $callback );
                        }
                    } else {
                        my %rsp;
                        push@{ $rsp{data} }, "Could not open kit component rmpkgs file $installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist";
                        xCAT::MsgUtils->message( "E", \%rsp, $callback );
                        return 1;
                    }
                }

                my @l = @lines;
                my $basename = '';
                my $kitreponame = '';
                my @kitpkgdeps = ();

                if ( exists($kitcomps{$kitcomponent}{basename}) and exists($kitcomps{$kitcomponent}{kitreponame}) ) {
                    $basename = $kitcomps{$kitcomponent}{basename};
                    $kitreponame = $kitcomps{$kitcomponent}{kitreponame};
                } else {
                    my %rsp;
                    push@{ $rsp{data} }, "Could not open kit component table and read basename for kit component $kitcomp";
                    xCAT::MsgUtils->message( "E", \%rsp, $callback );
                    return 1;
                }

                if ( exists($kitcomps{$kitcomponent}{kitpkgdeps}) ) {
                    @kitpkgdeps = split ',', $kitcomps{$kitcomponent}{kitpkgdeps};
                }

                push @kitpkgdeps, $basename;

                my $update = 0;

                #check if prerequisite rpm is already added to RMPKGS.otherpkgs.pkglist.
                my $matched = 0;
                foreach my $line ( @lines ) {
                    chomp $line;
                    if ( $line =~ /^-prep_$basename$/ ) {
                        $matched = 1;
                        last;
                    }
                }
                unless ( $matched ) {
                    # add the prerequisite rpm to #NEW_INSTALL_LIST# session
                    # so they can be removed in a seperate command
                    if ( $kitcomps{$kitcomponent}{prerequisite} ) {
                        push @l, "#NEW_INSTALL_LIST#\n";
                        push @l, "-prep_$basename\n";
                    }
                    $update = 1;
                }

                my $added_mark = 0;
                foreach my $kitpkgdep ( @kitpkgdeps ) {
                    next if ( $kitpkgdep =~ /^$/ );
                    my $matched = 0;
                    foreach my $line ( @lines ) {
                        chomp $line;
                        if ( $line =~ /^-$kitpkgdep$/ ) {
                            $matched = 1;
                            last;
                        }
                    }

                    unless ( $matched ) {
                        # add the prerequisite rpm to #NEW_INSTALL_LIST# session 
                        # so they can be removed in a seperate command
                        if ( $kitcomps{$kitcomponent}{prerequisite} ) {
                            if (!$added_mark) { 
                                push @l, "#NEW_INSTALL_LIST#\n";
                                $added_mark = 1;
                            }
                            push @l, "-$kitpkgdep\n";
                        } else {
                            unshift @l, "-$kitpkgdep\n";
                        }
                        $update = 1;
                    }

                }


                if ( $update and open(RMPKGLIST, ">", "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist") ) {
                    print RMPKGLIST @l;
                    close(RMPKGLIST);
                }

                if ( $linuximagetable and $linuximagetable->{otherpkglist} ) {
                    my $match = 0;
                    my @otherpkglists= split ',', $linuximagetable->{otherpkglist};
                    foreach my $otherpkglist ( @otherpkglists ) {
                        if ( $otherpkglist =~ /^$installdir\/osimages\/$osimage\/kits\/KIT_RMPKGS.otherpkgs.pkglist$/ ) {
                            $match = 1;
                            last;
                        }
                    }

                    if ( !$match and -e "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist" ) {
                        $linuximagetable->{otherpkglist} = $linuximagetable->{otherpkglist} . ",$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist"
                    }
                }
            }

        }

        # Removing deploy parameters

        if ( $kittable and $kittable->{kitdeployparams} and $kittable->{kitdir} ) {

            my $kitdir = $kittable->{kitdir};
            my $kitdeployfile = $kittable->{kitdeployparams};

            # Check if there is other kitcomponent in the same kit.
            my $match = 0;
            if ( exists($kitcomps{$kitcomponent}{kitname}) ) {
                my $kitname = $kitcomps{$kitcomponent}{kitname};

                foreach my $osikitcomp ( @osikitcomps ) {
                    (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname=> $osikitcomp}, 'kitname');
                    
                    if ( $kitcomptable and $kitcomptable->{kitname} and $kitcomptable->{kitname} eq $kitname and !exists($kitcomps{$osikitcomp}{name}) ) {
                        $match = 1;
                        last;
                    }
                }

                unless ( $match ) {
                    my @contents = ();;
                    if ( -e "$kitdir/other_files/$kitdeployfile" ) {
                        if (open(KITDEPLOY, "<", "$kitdir/other_files/$kitdeployfile") ) {
                            @contents = <KITDEPLOY>;
                            close(KITDEPLOY);
                            if($::VERBOSE){
                                my %rsp;
                                push@{ $rsp{data} }, "Reading kit deployparams from $kitdir/other_files/$kitdeployfile";
                                xCAT::MsgUtils->message( "I", \%rsp, $callback );
                            }
                        } else {
                            my %rsp;
                            push@{ $rsp{data} }, "Could not open kit deployparams file $kitdir/other_files/$kitdeployfile";
                            xCAT::MsgUtils->message( "E", \%rsp, $callback );
                            return 1;
                        }
                    }

                    my @lines = ();
                    if ( -e "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist" ) {

                        system("cp $installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist $installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist.orig");

                        if (open(DEPLOYPARAM, "<", "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist")) {
                            @lines = <DEPLOYPARAM>;
                            close(DEPLOYPARAM);
                            if($::VERBOSE){
                                my %rsp;
                                push@{ $rsp{data} }, "Reading kit deployparams file $installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist";
                                xCAT::MsgUtils->message( "I", \%rsp, $callback );
                            }
                        } else {
                            my %rsp;
                            push@{ $rsp{data} }, "Could not open kit deployparams file $installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist";
                            xCAT::MsgUtils->message( "E", \%rsp, $callback );
                            return 1;
                        }
                    }

                    # Check if each deploy parameter is used by other kitcomponent.
                    my @otherlines = ();
                    foreach my $osikitcomp ( @osikitcomps ) {
                        next if ( exists($kitcomps{$osikitcomp}{name}) );

                        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname=> $osikitcomp}, 'kitname');
                        if ( $kitcomptable and $kitcomptable->{kitname} ) {
                            (my $kittable) = $tabs{kit}->getAttribs({kitname=> $kitcomptable->{kitname}},  'kitdir', 'kitdeployparams');
                            if ( $kittable and $kittable->{kitdeployparams} and $kittable->{kitdir} ) {
                                my @otherdeployparams;
                                my $deployparam_file = $kittable->{kitdir}."/other_files/".$kittable->{kitdeployparams};
                                if ( -e "$deployparam_file" ) {
                                    if (open(OTHERDEPLOYPARAM, "<", "$deployparam_file" )) {
                                        @otherdeployparams = <OTHERDEPLOYPARAM>;
                                        close(OTHERDEPLOYPARAM);
                                    }
                                }
                                foreach ( @otherdeployparams ) {
                                    push @otherlines, $_;
                                }
                             }
                        }
                    }


                    my @newcontents = ();
                    foreach my $line ( @lines ) {
                        chomp $line;
                        my $found = 0;

                        #check if the parameter is used by other kitcomponent
                        foreach my $otherline ( @otherlines ) {
                            chomp $otherline;
                            if ( $line =~ /$otherline/ ) {
                                $found = 1;
                                last;
                            }
                        }

                        if ( $found ) {
                            push @newcontents, $line . "\n";
                        } else {
                            foreach my $content ( @contents ) {
                                chomp $content;
                                if ( $line =~ /$content/ ) {
                                    $found = 1;
                                    last;
                                }
                            }

                            unless ( $found ) {
                                push @newcontents, $line . "\n";
                            }
                        }
                    }

                    # Write the updated lines to kit deployparams file
                    if (open(NEWDEPLOYPARAM, ">", "$installdir/osimages/$osimage/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist")) {
                        print NEWDEPLOYPARAM @newcontents;
                        close(NEWDEPLOYPARAM);
                    }
                }
            }
        }        


        # Remove driverpacks from linuximage

        if ( $linuximagetable and $linuximagetable->{driverupdatesrc} ) {
            if ( exists($kitcomps{$kitcomponent}{driverpacks}) ) {
                my @driverpacks = split ',', $kitcomps{$kitcomponent}{driverpacks};
                my @driverupdatesrcs = split ',', $linuximagetable->{driverupdatesrc};

                my @newdriverupdatesrcs = ();

                foreach my $driverupdatesrc ( @driverupdatesrcs ) {
                    my $matched = 0;
                    foreach  my $driverpack ( @driverpacks ) {
                        if ( $driverpack eq $driverupdatesrc ) {
                            $matched = 1;
                            last;
                        }
                    }

                    unless ( $matched ) {
                        push @newdriverupdatesrcs, $driverupdatesrc;
                    }
                }

                my $newdriverupdatesrc = join ',', @newdriverupdatesrcs;
                $linuximagetable->{driverupdatesrc} = $newdriverupdatesrc;
            }
        }

        push @kitlist, $kitcomponent;

    }

    my $kitcompnames = join ',', @kitlist;
    my %rsp;
    push@{ $rsp{data} }, "kitcomponents $kitcompnames were removed from osimage $osimage successfully";
    xCAT::MsgUtils->message( "I", \%rsp, $callback );

    # Write linuximage table with all the above udpates.
    $tabs{linuximage}->setAttribs({imagename => $osimage }, \%{$linuximagetable} );

    # Write osimage table with all the above udpates.
    $tabs{osimage}->setAttribs({imagename => $osimage }, \%{$osimagetable} );

    return;
}

#-------------------------------------------------------

=head3  chkkitcomp 

    Check if the kit components fits to osimage

=cut

#-------------------------------------------------------
sub chkkitcomp
{
    my $request = shift;
    my $callback = shift;
    my $request_command = shift;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "chkkitcomp: Check if kit component fits to osimage";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\tchkkitcomp [-h|--help]";
        push@{ $rsp{data} }, "\tchkkitcomp [-V|--verbose] -i <osimage> <kitcompname_list>";
        xCAT::MsgUtils->message( "I", \%rsp, $callback );
    };

    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{$request->{arg}};
    if($#ARGV eq -1){
            $xusage->(1);
            return;
    }


    GetOptions(
            'h|help' => \$help,
            'V|verbose' => \$::VERBOSE,
            'i=s' => \$osimage
    );

    if($help){
            $xusage->(0);
            return;
    }

    my %tabs = ();
    my @tables = qw(kit kitrepo kitcomponent osimage osdistro linuximage);
    foreach my $t ( @tables ) {
        $tabs{$t} = xCAT::Table->new($t,-create => 1,-autocommit => 1);

        if ( !exists( $tabs{$t} )) {
            my %rsp;
            push@{ $rsp{data} }, "Could not open xCAT table $t";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }
    }

    # Check if all the kitcomponents are existing before processing

    my %kitcomps;
    my %kitcompbasename;
    my $des = shift @ARGV;
    my @kitcomponents = split ',', $des;
    foreach my $kitcomponent (@kitcomponents) {

        # Check if it is a kitcompname or basename
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomponent}, 'kitname', 'kitcompdeps', 'kitpkgdeps', 'kitreponame', 'basename', 'serverroles');
        if ( $kitcomptable and $kitcomptable->{'kitname'}){
            $kitcomps{$kitcomponent}{name} = $kitcomponent;
            $kitcomps{$kitcomponent}{kitname} = $kitcomptable->{kitname};
            $kitcomps{$kitcomponent}{kitpkgdeps} = $kitcomptable->{kitpkgdeps};
            $kitcomps{$kitcomponent}{kitcompdeps} = $kitcomptable->{kitcompdeps};
            $kitcomps{$kitcomponent}{basename} = $kitcomptable->{basename};
            $kitcomps{$kitcomponent}{kitreponame} = $kitcomptable->{kitreponame};
            $kitcomps{$kitcomponent}{serverroles} = $kitcomptable->{serverroles};
            $kitcompbasename{$kitcomptable->{basename}} = 1;
        } else {
            my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcomponent'", 'kitcompname' , 'version', 'release');
            unless (@entries) {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomponent kitcomponent does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);
            $kitcomps{$highest}{name} = $highest;
            (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $highest}, 'kitname', 'kitpkgdeps', 'kitcompdeps', 'kitreponame', 'basename', 'serverroles');
            $kitcomps{$highest}{kitname} = $kitcomptable->{kitname};
            $kitcomps{$highest}{kitpkgdeps} = $kitcomptable->{kitpkgdeps};
            $kitcomps{$highest}{kitcompdeps} = $kitcomptable->{kitcompdeps};
            $kitcomps{$highest}{basename} = $kitcomptable->{basename};
            $kitcomps{$highest}{kitreponame} = $kitcomptable->{kitreponame};
            $kitcomps{$highest}{serverroles} = $kitcomptable->{serverroles};
            $kitcompbasename{$kitcomponent} = 1;
        }
    }

    # Verify if the kitcomponents fitting to the osimage or not.
    my %os;
    my $osdistrotable;
    (my $osimagetable) = $tabs{osimage}->getAttribs({imagename=> $osimage}, 'osdistroname', 'serverrole', 'kitcomponents', 'osname', 'osvers', 'osarch');
    if ( $osimagetable and $osimagetable->{'osdistroname'}){
        ($osdistrotable) = $tabs{osdistro}->getAttribs({osdistroname=> $osimagetable->{'osdistroname'}}, 'basename', 'majorversion', 'minorversion', 'arch', 'type');
        if ( !$osdistrotable or !$osdistrotable->{basename} ) {
            my %rsp;
            push @{ $rsp{data} }, "$osdistroname osdistro does not exist";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        } 

        # Read basename,majorversion,minorversion,arch,type, from osdistro table
        $os{$osimage}{basename} = lc($osdistrotable->{basename});
        $os{$osimage}{majorversion} = lc($osdistrotable->{majorversion});
        $os{$osimage}{minorversion} = lc($osdistrotable->{minorversion});
        $os{$osimage}{arch} = lc($osdistrotable->{arch});
        $os{$osimage}{type} = lc($osdistrotable->{type});

        # Read serverrole from osimage.
        $os{$osimage}{serverrole} = lc($osimagetable->{'serverrole'});

    } elsif ( !$osimagetable or !$osimagetable->{'osname'} ) {
        my %rsp;
        push@{ $rsp{data} }, "osimage $osimage does not contains a valid 'osname' attribute";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;

    } elsif ( !$osimagetable->{'osvers'} ) {
        my %rsp;
        push@{ $rsp{data} }, "osimage $osimage does not contains a valid 'osvers' attribute";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    } elsif ( !$osimagetable->{'osarch'} ) {
        my %rsp;
        push@{ $rsp{data} }, "osimage $osimage does not contains a valid 'osarch' attribute";
        xCAT::MsgUtils->message( "E", \%rsp, $callback );
        return 1;
    } else {
        $os{$osimage}{type} = lc($osimagetable->{'osname'});
        $os{$osimage}{arch} = lc($osimagetable->{'osarch'});
        $os{$osimage}{serverrole} = lc($osimagetable->{'serverrole'});
 
        my ($basename, $majorversion, $minorversion) = $osimagetable->{'osvers'} =~ /^(\D+)(\d+)\W+(\d+)/;
        $os{$osimage}{basename} = lc($basename);
        $os{$osimage}{majorversion} = lc($majorversion);
        $os{$osimage}{minorversion} = lc($minorversion);
    }

    my @kitcompnames;
    foreach my $kitcomp ( keys %kitcomps ) {
        if ( $kitcomps{$kitcomp}{kitname} and $kitcomps{$kitcomp}{kitreponame}) { 

            # Read ostype from kit table
            (my $kittable) = $tabs{kit}->getAttribs({kitname => $kitcomps{$kitcomp}{kitname}}, 'ostype');
            if ( $kittable and $kittable->{ostype} ) {
                $kitcomps{$kitcomp}{ostype} = lc($kittable->{ostype});
            } else {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomp ostype does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

            # Read osbasename, osmajorversion,osminorversion,osarch,compat_osbasenames from kitrepo table
            (my $kitrepotable) = $tabs{kitrepo}->getAttribs({kitreponame => $kitcomps{$kitcomp}{kitreponame}}, 'osbasename', 'osmajorversion', 'osminorversion', 'osarch', 'compat_osbasenames');
            if ($kitrepotable and $kitrepotable->{osbasename} and $kitrepotable->{osmajorversion} and $kitrepotable->{osarch}) {
                if ($kitrepotable->{compat_osbasenames}) {
                    $kitcomps{$kitcomp}{osbasename} = lc($kitrepotable->{osbasename}) . ',' . lc($kitrepotable->{compat_osbasenames});
                } else {
                    $kitcomps{$kitcomp}{osbasename} = lc($kitrepotable->{osbasename});
                }

                $kitcomps{$kitcomp}{osmajorversion} = lc($kitrepotable->{osmajorversion});
                $kitcomps{$kitcomp}{osminorversion} = lc($kitrepotable->{osminorversion});
                $kitcomps{$kitcomp}{osarch} = lc($kitrepotable->{osarch});
            } else {
                my %rsp;
                push@{ $rsp{data} }, "$kitcomp osbasename,osmajorversion,osminorversion or osarch does not exist";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }

        }  else {
            my %rsp;
            push@{ $rsp{data} }, "$kitcomp kitname $kitcomptable->{'kitname'} or kitrepo name $kitcomptable->{'kitreponame'} or serverroles $kitcomps{$kitcomp}{serverroles} does not exist";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        # Validate each attribute in kitcomp.
        my $catched = 0;
        my @osbasename = split ',', $kitcomps{$kitcomp}{osbasename};
        foreach (@osbasename) {
            if ( $os{$osimage}{basename} eq $_ ) {
                $catched = 1;
            }
        }
        unless ( $catched ) {
            my %rsp;
            push@{ $rsp{data} }, "kit component $kitcomp doesn't fit to osimage $osimage with attribute OS";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( $os{$osimage}{majorversion} ne $kitcomps{$kitcomp}{osmajorversion} ) {
            my %rsp;
            push@{ $rsp{data} }, "kit component $kitcomp doesn't fit to osimage $osimage with attribute majorversion";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( $kitcomps{$kitcomp}{osminorversion} and ($os{$osimage}{minorversion} ne $kitcomps{$kitcomp}{osminorversion}) ) {
            my %rsp;
            push@{ $rsp{data} }, "kit component $kitcomp doesn't fit to osimage $osimage with attribute minorversion";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( $os{$osimage}{arch} ne $kitcomps{$kitcomp}{osarch} ) {
            my %rsp;
            push@{ $rsp{data} }, "kit component $kitcomp doesn't fit to osimage $osimage with attribute arch";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( $os{$osimage}{type} ne $kitcomps{$kitcomp}{ostype} ) {
            my %rsp;
            push@{ $rsp{data} }, "kit component $kitcomp doesn't fit to osimage $osimage with attribute type";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        if ( $os{$osimage}{serverrole} ) {
            my $match = 0;
            my @os_serverroles = split /,/, $os{$osimage}{serverrole};
            my @kitcomp_serverroles = split /,/, $kitcomps{$kitcomp}{serverroles};
            foreach my $os_serverrole (@os_serverroles) {
                foreach my $kitcomp_serverrole (@kitcomp_serverroles) {
                    if ( $os_serverrole eq $kitcomp_serverrole ) {
                        $match = 1;
                        last;
                    }
                }

                if ( $match ) {
                    last;
                }
            }
            if ( !$match ) {
                my %rsp;
                push@{ $rsp{data} }, "osimage $osimage doesn't fit to kit component $kitcomp with attribute serverrole";
                xCAT::MsgUtils->message( "E", \%rsp, $callback );
                return 1;
            }
        }

        # Check if this kit component's dependencies are in the kitcomponent list.
        if ( $kitcomps{$kitcomp}{kitcompdeps} and !exists( $kitcompbasename{ $kitcomps{$kitcomp}{kitcompdeps} } ) ) {
            my %rsp;
            push@{ $rsp{data} }, "kit component $kitcomp dependency $kitcomps{$kitcomp}{kitcompdeps} doesn't exist";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }

        push @kitcompnames, $kitcomp;
    }

    my $kitcompnamelist = join ',', @kitcompnames;

    my %rsp;
    push@{ $rsp{data} }, "Kit components $kitcompnamelist fit to osimage $osimage";
    xCAT::MsgUtils->message( "I", \%rsp, $callback );

    return;
}

#----------------------------------------------------------------------------

=head3  lskit_usage

        Display the lskit usage
=cut

#-----------------------------------------------------------------------------

sub lskit_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: lskit - List info for one or more kits.\n";
    push @{ $rsp->{data} },
      "  lskit [-V|--verbose] [-x|--xml|--XML] [-K|--kitattr kitattr_names] [-R|--repoattr repoattr_names] [-C|--compattr compattr_names] [kit_names]\n ";
    push @{ $rsp->{data} }, "  lskit [-h|--help|-?] \n";
    push @{ $rsp->{data} },
      "  lskit [-v|--version]  \n ";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}


#----------------------------------------------------------------------------

=head3  lskitcomp_usage

        Display the lskitcomp usage
=cut

#-----------------------------------------------------------------------------

sub lskitcomp_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: lskitcomp - List info for one or more kit components.\n";
    push @{ $rsp->{data} },
      "  lskitcomp [-V|--verbose] [-x|--xml|--XML] [-C|--compattr compattr_names] [-O|--osdistro os_distro] [-S|--serverrole server_role] [kitcomp_names]\n ";
    push @{ $rsp->{data} }, "  lskitcomp [-h|--help|-?] \n";
    push @{ $rsp->{data} },
      "  lskitcomp [-v|--version]  \n ";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}


#----------------------------------------------------------------------------

=head3  lskitdeployparam_usage

        Display the lskitdeployparam usage
=cut

#-----------------------------------------------------------------------------

sub lskitdeployparam_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: lskitdeployparam - List the kit deployment parameters for either one or more kits, or one or more kit components.\n";
    push @{ $rsp->{data} },
      "  lskitdeployparam [-V|--verbose] [-x|--xml|--XML] [-k|--kitname kit_names] [-c|--compname comp_names]\n ";
    push @{ $rsp->{data} }, "  lskitdeployparam [-h|--help|-?] \n";
    push @{ $rsp->{data} },
      "  lskitdeployparam [-v|--version]  \n ";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}


#----------------------------------------------------------------------------

=head3  create_version_response

        Create a response containing the command name and version
=cut

#-----------------------------------------------------------------------------
sub create_version_response {
    my $rsp;
    my $version = xCAT::Utils->Version();
    push @{ $rsp->{data} }, "$::command - $version\n";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
}


#----------------------------------------------------------------------------

=head3  create_error_response

        Create a response containing a single error message
        Arguments:  error message
=cut

#-----------------------------------------------------------------------------
sub create_error_response {
    my $error_msg = shift;
    my $rsp;
    push @{ $rsp->{data} }, $error_msg;
    xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
}


#----------------------------------------------------------------------------

=head3   lskit_processargs

        Process the lskit command line
        Returns:
                0 - OK
                1 - just print version
                2 - just print help
                3 - error
=cut

#-----------------------------------------------------------------------------
sub lskit_processargs {

    if ( defined( @{$::args} ) ) {
        @ARGV = @{$::args};
    }

    # parse the options
    # options can be bundled up like -vV, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    my $getopt_success = Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'kitattr|K=s' => \$::opt_K,
                              'repoattr|R=s' => \$::opt_R,
                              'compattr|C=s' => \$::opt_C,
                              'verbose|V' => \$::opt_V,
                              'version|v' => \$::opt_v,
                              'xml|XML|x' => \$::opt_x,
    );

    if (!$getopt_success) {
        return 3;
    }

    # Option -h for Help
    if ( defined($::opt_h) ) {
        return 2;
    }

    # Option -v for version
    if ( defined($::opt_v) ) {
        create_version_response();
        return 1;    # no usage - just exit
    }

    # Option -V for verbose output
    if ( defined($::opt_V) ) {
        $::VERBOSE = 1;
    }

    # Option -K for kit attributes
    if ( defined($::opt_K) ) {
        $::kitattrs = split_comma_delim_str($::opt_K);
        ensure_kitname_attr_in_list($::kitattrs);
        if (check_attr_names_exist('kit', $::kitattrs) != 0) {
            return 3;
        } 
    }

    # Option -R for kit repo attributes
    if ( defined($::opt_R) ) {
        $::kitrepoattrs = split_comma_delim_str($::opt_R);
        ensure_kitname_attr_in_list($::kitrepoattrs);
        if (check_attr_names_exist('kitrepo', $::kitrepoattrs) != 0) {
            return 3;
        }
    }

    # Option -C for kit component attributes
    if ( defined($::opt_C)) {
        $::kitcompattrs = split_comma_delim_str($::opt_C);
        ensure_kitname_attr_in_list($::kitcompattrs);
        if (check_attr_names_exist('kitcomponent', $::kitcompattrs) != 0) {
            return 3;
        }
    }

    # Kit names
    my $kitnames_str = shift(@ARGV);
    if ( defined($kitnames_str) ) {
        my @tmp = split(/,/, $kitnames_str);
        $::kitnames = \@tmp;
        if (check_attr_values_exist('kit', 'kitname', 'kit names', $::kitnames) != 0) {
            return 3;
        }
    }

    # Other attributes are not allowed
    my $more_input = shift(@ARGV);
    if ( defined($more_input) ) {
        create_error_response("Invalid input: $more_input \n");
        return 3;
    } 

    return 0;
}


#----------------------------------------------------------------------------

=head3   lskitcomp_processargs

        Process the lskitcomp command line
        Returns:
                0 - OK
                1 - just print version
                2 - just print help
                3 - error
=cut

#-----------------------------------------------------------------------------
sub lskitcomp_processargs {

    if ( defined( @{$::args} ) ) {
        @ARGV = @{$::args};
    }

    # parse the options
    # options can be bundled up like -vV, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    my $getopt_success = Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'compattr|C=s' => \$::opt_C,
                              'osdistro|O=s' => \$::opt_O,
                              'serverrole|S=s' => \$::opt_S,
                              'verbose|V' => \$::opt_V,
                              'version|v' => \$::opt_v,
                              'xml|XML|x' => \$::opt_x,
    );

    if (!$getopt_success) {
        return 3;
    }

    # Option -h for Help
    if ( defined($::opt_h) ) {
        return 2;
    }

    # Option -v for version
    if ( defined($::opt_v) ) {
        create_version_response();
        return 1;    # no usage - just exit
    }

    # Option -V for verbose output
    if ( defined($::opt_V) ) {
        $::VERBOSE = 1;
    }

    # Option -C for kit component attributes
    if ( defined($::opt_C) ) {
        $::kitcompattrs = split_comma_delim_str($::opt_C);
        ensure_kitname_attr_in_list($::kitcompattrs);
        if (check_attr_names_exist('kitcomponent', $::kitcompattrs) != 0) {
            return 3;
        }
    }

    # Option -O for osdistro name
    $::osdistroname = $::opt_O;
    if ( defined($::osdistroname) ) {
        if (check_attr_values_exist('osdistro', 'osdistroname', 'os distro', [$::osdistroname]) != 0) {
            return 3;
        }
    }

    # Option -S for server role
    $::serverrole = $::opt_S;

    # Kit component names
    my $kitcompnames_str = shift(@ARGV);
    if ( defined($kitcompnames_str) ) {
        my @tmp = split(/,/, $kitcompnames_str);
        $::kitcompnames = \@tmp;
        if (check_attr_values_exist('kitcomponent', 'kitcompname', 'kit component names', $::kitcompnames) != 0) {
            return 3;
        }
    }

    # Other attributes are not allowed
    my $more_input = shift(@ARGV);
    if ( defined($more_input) ) {
        create_error_response("Invalid input: $more_input \n");
        return 3;
    } 

    return 0;
}


#----------------------------------------------------------------------------

=head3   lskitdeployparam_processargs

        Process the lskitdeployparam command line
        Returns:
                0 - OK
                1 - just print version
                2 - just print help
                3 - error
=cut

#-----------------------------------------------------------------------------
sub lskitdeployparam_processargs {

    if ( defined( @{$::args} ) ) {
        @ARGV = @{$::args};
    }

    # parse the options
    # options can be bundled up like -vV, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    my $getopt_success = Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'kitname|k=s' => \$::opt_k,
                              'compname|c=s' => \$::opt_c,
                              'verbose|V' => \$::opt_V,
                              'version|v' => \$::opt_v,
                              'xml|XML|x' => \$::opt_x,
    );

    if (!$getopt_success) {
        return 3;
    }

    # Option -h for Help
    if ( defined($::opt_h) ) {
        return 2;
    }

    # Option -v for version
    if ( defined($::opt_v) ) {
        create_version_response();
        return 1;    # no usage - just exit
    }

    # Option -V for verbose output
    if ( defined($::opt_V) ) {
        $::VERBOSE = 1;
    }

    # Ensure -k and -c option not used together
    if (defined($::opt_k) && defined($::opt_c)) {
        create_error_response("The -k and -c options cannot be used together.");
        return 3;
    }

    # Ensure -k or -c option are specified
    if (!defined($::opt_k) && !defined($::opt_c)) {
        create_error_response("The -k or -c option must be specified.");
        return 3;
    }

    # Option -k for kit names
    if ( defined($::opt_k) ) {
        $::kitnames = split_comma_delim_str($::opt_k);
        if (check_attr_values_exist('kit', 'kitname', 'kit names', $::kitnames) != 0) {
            return 3;
        }
    }

    # Option -c for kitocmponent names
    if ( defined($::opt_c) ) {
        $::kitcompnames = split_comma_delim_str($::opt_c);
        if (check_attr_values_exist('kitcomponent', 'kitcompname', 'kit component names', $::kitcompnames) != 0) {
            return 3;
        }
    }

    # Other attributes are not allowed
    my $more_input = shift(@ARGV);
    if ( defined($more_input) ) {
        create_error_response("Invalid input: $more_input \n");
        return 3;
    } 

    return 0;
}


#----------------------------------------------------------------------------

=head3  split_comma_delim_str

        Split comma-delimited list of strings into an array.

        Arguments: comma-delimited string
        Returns:   Returns list of strings (ref)

=cut

#-----------------------------------------------------------------------------
sub split_comma_delim_str {
    my $input_str = shift;

    my @result = split(/,/, $input_str);
    return \@result;
}


#----------------------------------------------------------------------------

=head3  ensure_kitname_attr_in_list

        Checks if 'kitname' attribute is in specified attribute list.
        If not, then add it.

        Arguments: list of attribute names (ref)
=cut

#-----------------------------------------------------------------------------
sub ensure_kitname_attr_in_list {
    my $attrs = shift;

    if (defined($attrs)) {
        if (! grep(/^kitname$/, @$attrs)) {
            push(@$attrs, "kitname");
        }
    }
}


#----------------------------------------------------------------------------

=head3  check_attr_names_exist

        Check if list of DB attribute names exist in a table 
        Arguments:  a table name
                    a list of attribute names to check (ref)
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub check_attr_names_exist {

    my $tablename = shift;
    my $attrs = shift;
    my @badattrs = ();

    if (defined($attrs)) {
        my $schema = xCAT::Table->getTableSchema($tablename);
        my @cols = @{$schema->{cols}};
        foreach my $attr (@{$attrs}) {
            if (! grep {$_ eq $attr} @cols ) {
                push(@badattrs, $attr);
            }
        }
    }

    if (scalar @badattrs > 0) {
        my $error = sprintf("The following %s attributes are not valid: %s.", 
            $tablename, join(",",@badattrs));
        create_error_response($error);
        return 1;
    }
    return 0;
}

#----------------------------------------------------------------------------

=head3  check_attr_values_exist

        Check if a list of DB attribute values exist
        Arguments:  
                table name
                table attribute
                table attribute desc (e.g. kit names), this string is added to error message
                list of values to check (ref)
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub check_attr_values_exist {

    my $tablename = shift;
    my $tableattr = shift;
    my $tableattr_desc = shift;
    my $values_to_check = shift;
    my @badvalues = ();

    my $filter_stmt = db_build_filter_stmt({$tableattr => $values_to_check});
    my $rows = db_get_table_rows($tablename, [$tableattr], $filter_stmt);

    my @values_in_DB = map {$_->{$tableattr}} @$rows;
    foreach my $value_to_check (@{$values_to_check}) {
        if (! grep {$_ eq $value_to_check} @values_in_DB ) {
            push(@badvalues, $value_to_check);
        }
    }

    if (scalar @badvalues > 0) {
        my $error;
        if ($tableattr_desc =~ /s$/) {
            $error = sprintf("The following %s are not valid: %s.", $tableattr_desc, join(",",@badvalues));
        } else {
            $error = sprintf("The following %s is not valid: %s.", $tableattr_desc, join(",",@badvalues));
        }
        create_error_response($error);
        return 1;
    }

    return 0;
}



#----------------------------------------------------------------------------

=head3  lskit

        Support for listing kits
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------

sub lskit {

    my $rc = 0;

    # process the command line
    # 0=success, 1=version, 2=help, 3=error
    $rc = lskit_processargs(@_);
    if ( $rc != 0 ) {
       if ( $rc != 1) {
           lskit_usage(@_);
       } 
       return ( $rc - 1 );
    }

    # Prepare the hash tables to pass to the output routines
    my $kit_hash = get_kit_hash($::kitnames, $::kitattrs);
    my $kitrepo_hash = get_kitrepo_hash($::kitnames, $::kitrepoattrs);
    my $kitcomp_hash = get_kitcomp_hash($::kitnames, $::kitcompattrs);

    # Now display the output
    my @kitnames = keys(%$kit_hash);
    if (scalar @kitnames == 0) {
        my $rsp = {};
        push @{ $rsp->{data} }, "No kits were found.";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }

    if (defined($::opt_x)) {
        create_lskit_xml_response($kit_hash, $kitrepo_hash, $kitcomp_hash);
    } else {
        create_lskit_stanza_response($kit_hash, $kitrepo_hash, $kitcomp_hash);
    }
    return 0;
}


#----------------------------------------------------------------------------

=head3  lskitcomp

        Support for listing kit components

        Arguments:
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------


sub lskitcomp {

    my $rc = 0;

    # process the command line
    # 0=success, 1=version, 2=help, 3=error
    $rc = lskitcomp_processargs(@_);
    if ( $rc != 0 ) {
       if ( $rc != 1) {
           lskitcomp_usage(@_);
       } 
       return ( $rc - 1 );
    }

    # Get the list of kitcomponents to display

    ## Build the initial kitcomponent list, filtering the kitcomponents whose:
    ##    - name matches one of the user-specified names
    ##    - AND, reponame refers to a repo that is compatible with the user-specified osdistro

    my $compat_kitreponames = undef;
    if (defined($::osdistroname)) {
        $compat_kitreponames = get_compat_kitreponames($::osdistroname);
    }
    my $kitcomps = get_kitcomp_list($::kitcompnames, $compat_kitreponames, $::kitcompattrs);


    ## Filter the kitcomponent list by user-specified server role
    if (defined($::serverrole)) {
        my @tmplist = ();
        foreach my $kitcomp (@$kitcomps) {
            if (defined($kitcomp->{serverroles})) {
                my @serverroles = split(/,/, $kitcomp->{serverroles});
                if (grep {$_ eq $::serverrole } @serverroles) {
                    push(@tmplist, $kitcomp);
                }
            } else {
                # If kit component doesn't have server roles, it means
                # it supports any server role.
                push(@tmplist, $kitcomp);
            }
        }
        @$kitcomps = @tmplist;
    }
    

    # Check if kit component list is empty

    if (scalar(@$kitcomps) == 0) {
        my $rsp = {};
        push @{ $rsp->{data} }, "No kit components were found.";
        xCAT::MsgUtils->message("I", $rsp, $::CALLBACK);
        return 0;
    }


    # Prepare the hash tables to pass to the output routines

    ## Kit hash table
    my @kitnames = map {$_->{kitname}} @$kitcomps;
    my $kit_hash = get_kit_hash(\@kitnames, ['kitname']);
    
    ## Kit component hash table
    my $kitcomp_hash = create_hash_from_table_rows($kitcomps, 'kitname');


    ## Now display the output

    if (defined($::opt_x)) {
        create_lskit_xml_response($kit_hash, {}, $kitcomp_hash);
    } else {
        create_lskit_stanza_response($kit_hash, {}, $kitcomp_hash);
    }
    return 0;
}


#----------------------------------------------------------------------------

=head3  lskitdeployparam

        Support for listing kit deployment parameters

        Arguments:
        Returns:
                0 - OK
                1 - help
                2 - error
=cut

#-----------------------------------------------------------------------------


sub lskitdeployparam {

    my $rc = 0;

    # process the command line
    # 0=success, 1=version, 2=help, 3=error
    $rc = lskitdeployparam_processargs(@_);
    if ( $rc != 0 ) {
       if ( $rc != 1) {
           lskitdeployparam_usage(@_);
       } 
       return ( $rc - 1 );
    }

    # Get the kit deployment parameter files to read

    ## First get the list of kits
    my $kitnames = undef;
    if (defined($::kitnames)) {
        $kitnames = $::kitnames;
    } elsif (defined $::kitcompnames) {
        my $kitcomps = get_kitcomp_list($::kitcompnames, undef, ['kitname','kitcompname']);
        my @tmp = map {$_->{kitname}} @$kitcomps;
        $kitnames = \@tmp;
    } else {
        # unreachable code
    }

    ## Then get the kit deployment parameter file for each kit
    my $kits = get_kit_list($kitnames, ['kitname','kitdir','kitdeployparams']);

    # Read the kit deployment parameter files. The format is:
    #        #ENV:KIT_KIT1_PARAM1=value11#
    #        #ENV:KIT_KIT1_PARAM2=value12#
    #        #ENV:KIT_KIT2_PARAM1=value21#
    my $deployparam_hash = {};
    foreach my $kit (@$kits) {
        my $deployparam_file = $kit->{kitdir}."/other_files/".$kit->{kitdeployparams};

        if (defined($deployparam_file)) {
            open(my $fh, "<", $deployparam_file) || die sprintf("Failed to open file %s because: %s", $deployparam_file, $!);
            
            while (<$fh>) {
                chomp $_;
                if ($_ =~ /^#ENV:.+=.+#$/) {
                    my $tmp = $_;
                    $tmp =~ s/^#ENV://;
                    $tmp =~ s/#$//;
                    (my $name, my $value) = split(/=/, $tmp);
                    $deployparam_hash->{$name} = $value;
                }
            }
            close($fh);
        }
    }

    # Now display the output

    my $rsp = {};

    if (defined($::opt_x)) {
        # Output XML format
        foreach my $deployparam_key (sort(keys(%$deployparam_hash))) {
            my $output_hash = {"kitdeployparam" => {"name" => "", "value" => ""}};
            $output_hash->{kitdeployparam}->{name} = $deployparam_key;
            $output_hash->{kitdeployparam}->{value} = $deployparam_hash->{$deployparam_key};
            push @{ $rsp->{data} }, $output_hash;
        }
    } else {
        # Output Stanza format
        foreach my $deployparam_key (sort(keys(%$deployparam_hash))) {
            my $output = "kitdeployparam:\n";
            $output .= sprintf("    name=%s\n", $deployparam_key);
            $output .= sprintf("    value=%s\n", $deployparam_hash->{$deployparam_key});
            push @{ $rsp->{data} }, $output;
        }
    }

    xCAT::MsgUtils->message("D", $rsp, $::CALLBACK);

    return 0
}


1;
#----------------------------------------------------------------------------

=head3  get_kit_hash

        Returns a hash table containing kit entries indexed by kit name.
        Arguments: 
            list of kit names (ref)
            list of kit attribute names (ref)
        Returns: hash table (ref)
           { kitname1 => [{kitname1,basename1,...}],
             kitname2 => [{kitname2,basename2,...}],
             ...
           }
=cut

#-----------------------------------------------------------------------------

sub get_kit_hash {

    my $tablename = 'kit';
    my $kitnames = shift;
    my $kitattrs = shift;

    my $filter_hash = {};
    if (defined($kitnames)) {
        $filter_hash->{kitname} = $kitnames;
    }

    my $filter_stmt = undef;
    if (scalar(keys(%$filter_hash)) > 0) {
        $filter_stmt = db_build_filter_stmt($filter_hash);
    }

    my $rows = db_get_table_rows($tablename, $kitattrs, $filter_stmt);

    return create_hash_from_table_rows($rows, 'kitname');
}

#----------------------------------------------------------------------------

=head3  get_kitrepo_hash

        Returns a hash table containing lists of kit repository entries 
        indexed by kit name.
        Arguments: 
            list of kit names (ref)
            list of kit repo attribute names (ref)
        Returns: hash table (ref)
           { kitname1 => [{kitrepo11,...},{kitrepo12,...}],
             kitname2 => [{kitrepo21,...},{kitrepo22,...}],
             ...
           }
=cut

#-----------------------------------------------------------------------------

sub get_kitrepo_hash {

    my $tablename = 'kitrepo';
    my $kitnames = shift;
    my $kitrepoattrs = shift;

    my $filter_hash = {};
    if (defined($kitnames)) {
        $filter_hash->{kitname} = $kitnames;
    }

    my $filter_stmt = undef;
    if (scalar(keys(%$filter_hash)) > 0) {
        $filter_stmt = db_build_filter_stmt($filter_hash);
    }
    my $rows = db_get_table_rows($tablename, $kitrepoattrs, $filter_stmt);

    return create_hash_from_table_rows($rows, 'kitname');
}


#----------------------------------------------------------------------------

=head3  get_kitcomp_hash

        Returns a hash table containing lists of kit component entries 
        indexed by kit name.
        Arguments: 
            list of kit names (ref)
            list of kit component attribute names (ref)
        Returns: hash table (ref)
           { kitname1 => [{kitcomp11,...},{kitcomp12,...}], 
             kitname2 => [{kitcomp21,...},{kitcomp22,...}],
             ...
           }
=cut

#-----------------------------------------------------------------------------

sub get_kitcomp_hash {

    my $tablename = 'kitcomponent';
    my $kitnames = shift;
    my $kitcompattrs = shift;

    my $filter_hash = {};
    if (defined($kitnames)) {
        $filter_hash->{kitname} = $kitnames;
    }

    my $filter_stmt = undef;
    if (scalar(keys(%$filter_hash)) > 0) {
        $filter_stmt = db_build_filter_stmt($filter_hash);
    }
    my $rows = db_get_table_rows($tablename, $kitcompattrs, $filter_stmt);

    return create_hash_from_table_rows($rows, 'kitname');

}


#----------------------------------------------------------------------------

=head3  get_kit_list

        Returns a list of kit, filtering the kits by:
          - kit name

        Arguments:
               list of kit attributes to query (ref)
               list of kit names for filtering  (ref)

        Returns a list of kit(ref)
=cut

#-----------------------------------------------------------------------------

sub get_kit_list {

    my $kitnames = shift;
    my $kitattrs = shift;

    my $filter_hash = {};

    if (defined($kitnames)) {
        $filter_hash->{kitname} = $kitnames;
    }

    my $filter_stmt = undef;
    if (scalar(keys(%$filter_hash)) > 0) {
        $filter_stmt = db_build_filter_stmt($filter_hash);
    }
    return db_get_table_rows('kit', $kitattrs, $filter_stmt);
}


#----------------------------------------------------------------------------

=head3  get_kitcomp_list

        Returns a list of kit components, filtering the kit components by:
          - kit component name
          - kit repository name

        Arguments:
               list of kit component names for filtering  (ref)
               list of kit repo names for filtering (ref)
               list of kit component attributes to query (ref)

        Returns a list of kit components (ref)
=cut

#-----------------------------------------------------------------------------

sub get_kitcomp_list {

    my $kitcompnames = shift;
    my $kitreponames = shift;
    my $kitcompattrs = shift;

    my $filter_hash = {};

    if (defined($kitcompnames)) {
        $filter_hash->{kitcompname} = $kitcompnames;
    }

    if (defined($kitreponames)) {
        $filter_hash->{kitreponame} = $kitreponames;
    }

    my $filter_stmt = undef;
    if (scalar(keys(%$filter_hash)) > 0) {
        $filter_stmt = db_build_filter_stmt($filter_hash);
    }
    return db_get_table_rows('kitcomponent', $kitcompattrs, $filter_stmt);
}


#----------------------------------------------------------------------------

=head3  get_compat_kitreponames

        Returns a list of kitreponames which are compatible with the specified
        osdistroname.

        Arguments:
             osdistroname

        Returns:
             List of kitreponames (ref)

=cut

#-----------------------------------------------------------------------------

sub get_compat_kitreponames {

    my $osdistroname = shift;
    my @compat_kitrepos = ();

    ## Get the osdistro info
    my $filter_stmt = db_build_filter_stmt({'osdistroname' => [$osdistroname]});
    my $osdistros = db_get_table_rows('osdistro',  undef, $filter_stmt);
    my $osdistro = $osdistros->[0];
    #print Dumper($osdistro);

    ## Get the kitrepos, which are compatible with the osdistro info
    my $kitrepos = db_get_table_rows('kitrepo',  undef, undef);

    foreach my $kitrepo (@$kitrepos) {
        ## To check if kitrepo is compatible with an osdistro, the following 4 things
        ## must be true:
        ##     1) The kitrepo basename must be same as or compatible with osdistro basename.
        ##     2) The kitrepo major verison must be same as osdistro major version.
        ##     3) The kitrepo minor version must either:
        ##           - Be same as osdistro minor version
        ##           - OR, be empty which matches any osdistro minor version
        ##     4) The kitrepo arch must be same as osdistro arch.
        if (defined($kitrepo->{osbasename})) {
            my @kitrepo_compat_basenames = ();
            if (defined($kitrepo->{compat_osbasenames})) {
                @kitrepo_compat_basenames = split(/,/, $kitrepo->{compat_osbasenames});
            }
            if ($kitrepo->{osbasename} ne $osdistro->{basename} && 
                    ! grep {$_ eq $osdistro->{basename}} @kitrepo_compat_basenames ) {
                next;
            }
        }
        if (defined($kitrepo->{osmajorversion}) && $kitrepo->{osmajorversion} ne $osdistro->{majorversion}) {
            next;
        }
        if (defined($kitrepo->{osminorversion}) && $kitrepo->{osminorversion} ne $osdistro->{minorversion}) {
            next;
        }
        if (defined($kitrepo->{osarch}) && $kitrepo->{osarch} ne $osdistro->{arch}) {
            next;
        }

        push(@compat_kitrepos, $kitrepo);
    }
    #print Dumper(@compat_kitrepos);

    my @compat_kitreponames = map {$_->{kitreponame}} @compat_kitrepos;
    return \@compat_kitreponames;

}

#----------------------------------------------------------------------------

=head3  db_build_filter_stmt

        Returns a SQL 'where' statement which is used to filter the
        result of a kit, kit repository or kit component query.
        
        Arguments: 
             hash table
                 - each entry represents a filter
                 - each entry has a key <keyN>, and a list of values <valuesN>.
                 - each entry is added to 'where' stmt as follows:
                      <key1> in (comma-separated list of <values1>)
                      <key2> in (comma-separated list of <values2>)
                      ...
        Returns: string containing SQL 'where' statement
=cut

#-----------------------------------------------------------------------------

sub db_build_filter_stmt {

    my $filter_hash = shift;
    my $filter_stmt = "";

    for my $filter_key (keys(%$filter_hash)) {
        my $filter_values = $filter_hash->{$filter_key};
        my $values_str = join ",", map {'\''.$_.'\''} @$filter_values;
        if ($filter_stmt eq "") {
            $filter_stmt = sprintf("%s in (%s)", $filter_key, $values_str);
        } else {
            $filter_stmt .= sprintf(" AND %s in (%s)", $filter_key, $values_str);
        }
    }

    return $filter_stmt;
}


#----------------------------------------------------------------------------

=head3  db_get_table_rows

        Returns a list of table rows.  Each table row is a hash table.

        Arguments: 
               table name
               attribute list
               where statement

        Returns: list of table rows (ref)
=cut

#-----------------------------------------------------------------------------

sub db_get_table_rows {

    my $tablename = shift;
    my $attrs = shift;
    my $filter_stmt = shift;

    if (!defined($attrs)) {
        @{$attrs} = ();
        my $schema = xCAT::Table->getTableSchema($tablename);
        foreach my $c (@{$schema->{cols}}) {
            push @{$attrs}, $c;
        }
    }

    my $table = xCAT::Table->new($tablename);
    my @table_rows = ();
    if (defined($filter_stmt)) {
        if (length($filter_stmt) > 0) {
            @table_rows = $table->getAllAttribsWhere($filter_stmt, @{$attrs});
        }
    } else {
        @table_rows = $table->getAllAttribs(@{$attrs});
    }

    return \@table_rows;
}

#----------------------------------------------------------------------------

=head3  create_hash_from_table_rows

        Returns a hash table containing table rows indexed by specified
        table attribute.
        Arguments: 
               list of table rows (each row is a hash table)
               table attribute
        Returns: hash table (ref)
            { kitname1 => [row11,row12,...}],
              kitname2 => [row21,row22,...}],
              ...
            }
=cut

#-----------------------------------------------------------------------------

sub create_hash_from_table_rows {

    my $table_rows = shift;
    my $table_attr = shift;

    my $result = {};
    foreach my $row (@$table_rows) {
        my $hash_key = $row->{$table_attr};
        if (! defined($result->{$hash_key})) {
            $result->{$hash_key} = [];
        }
        push(@{$result->{$hash_key}}, $row);
    }

    return $result;

}

#----------------------------------------------------------------------------

=head3  create_lskit_xml_response

        Prepare a response that returns the kit, kit repository, and 
        kit component info in XML format.

        Arguments:
               kit hash table
               kit repo hash table
               kit component hash table

               Note: Hash tables are created by create_hash_from_table_rows()
=cut

#-----------------------------------------------------------------------------

sub create_lskit_xml_response {

    my $kit_hash = shift;
    my $kitrepo_hash = shift;
    my $kitcomp_hash = shift;

    my $rsp = {};

    for my $kitname (sort(keys(%$kit_hash))) {
        my $output_hash = {"kitinfo" => {"kit" => [], "kitrepo" => [], "kitcomponent" => [] } };

        # Kit info
        if (defined($kit_hash->{$kitname})) {
            my $kit = $kit_hash->{$kitname}->[0];
            push(@{$output_hash->{kitinfo}->{kit}}, $kit);
        }

        # Kit repository info
        if (defined($kitrepo_hash->{$kitname})) {
            for my $kitrepo (@{$kitrepo_hash->{$kitname}}) {
                push(@{$output_hash->{kitinfo}->{kitrepo}}, $kitrepo);
            }
        } 

        # Kit component info
        if (defined($kitcomp_hash->{$kitname})) {
            for my $kitcomp (@{$kitcomp_hash->{$kitname}}) {
                push(@{$output_hash->{kitinfo}->{kitcomp}}, $kitcomp);
            }
        }

        push @{ $rsp->{data} }, $output_hash;
    }

    xCAT::MsgUtils->message("D", $rsp, $::CALLBACK);
}


#----------------------------------------------------------------------------

=head3  create_lskit_stanza_response

        Prepare a response that returns the kit, kit repository, and 
        kit component info in stanza-like format.

        Arguments:
               kit hash table
               kit repo hash table
               kit component hash table
               Note: Hash tables are created by create_hash_from_table_rows()
=cut

#-----------------------------------------------------------------------------
sub create_lskit_stanza_response {

    my $kit_hash = shift;
    my $kitrepo_hash = shift;
    my $kitcomp_hash = shift;

    my $rsp = {};
    my $count = 0;

    for my $kitname (sort(keys(%$kit_hash))) {
        my $output .= "\n----------------------------------------------------\n";

        # Kit info
        if (defined($kit_hash->{$kitname})) {
            my $kit = $kit_hash->{$kitname}->[0];
            $output .= "kit:\n";
            for my $kit_attr (sort(keys(%$kit))) {
                $output .= sprintf("    %s=%s\n", $kit_attr, $kit->{$kit_attr});
            }
            $output .= "\n";
        }

        # Kit repository info
        if (defined($kitrepo_hash->{$kitname})) {
            for my $kitrepo (@{$kitrepo_hash->{$kitname}}) {
                $output .= "kitrepo:\n";
                for my $kitrepo_attr (sort(keys(%$kitrepo))) {
                    $output .= sprintf("    %s=%s\n", $kitrepo_attr, $kitrepo->{$kitrepo_attr});
                }
                $output .= "\n";
            }
        } 

        # Kit component info
        if (defined($kitcomp_hash->{$kitname})) {
            for my $kitcomp (@{$kitcomp_hash->{$kitname}}) {
                $output .= "kitcomponent:\n";
                for my $kitcomp_attr (sort(keys(%$kitcomp))) {
                    $output .= sprintf("    %s=%s\n", $kitcomp_attr, $kitcomp->{$kitcomp_attr});
                }
                $output .= "\n";
            }
        }


        push @{ $rsp->{data} }, $output;
    }

    xCAT::MsgUtils->message("D", $rsp, $::CALLBACK);

}

1;



#-----------------------------------------------------------------------------

=head3    check_framework

    Check the compatible frameworks of the kit to see if it is
        compatible with the running code.

    If one of the compatible frameworks of the kit matches one of the
        compatible frameworks of the running code then we're good.

    NOTE:  compatible_kitframeworks are the kitframeworks that I can add
        and kit frameworks that I can be added to.

    Returns:
        0 - OK
        1 - error

    Example:
        my $rc = &check_framework(\@lines);

=cut

#-----------------------------------------------------------------------------
sub check_framework
{
    my $lines = shift;

    my @kitconflines = @$lines;

    my $kitbasename;
    my $kitcompat;
    my $section = '';
    foreach my $l (@kitconflines) {
        # skip blank and comment lines
        if ( $l =~ /^\s*$/ || $l =~ /^\s*#/ ) {
            next;
        }

        if ( $l =~ /^\s*(\w+)\s*:/ ) {
           $section = $1;
           next;
        }

        if ( $l =~ /^\s*(\w+)\s*=\s*(.*)\s*/ ) {
            my $attr = $1;
            my $val  = $2;
            $attr =~ s/^\s*//;       # Remove any leading whitespace
            $attr =~ s/\s*$//;       # Remove any trailing whitespace
            $attr =~ tr/A-Z/a-z/;    # Convert to lowercase
            $val  =~ s/^\s*//;
            $val  =~ s/\s*$//;

            if ($section eq 'kitbuildinfo') {
                if ( $attr eq 'compatible_kitframeworks' )   {
                    $kitcompat = $val;
                }
            }
            if ($section eq 'kit') {
                if ( $attr eq 'basename' ) { $kitbasename = $val; }
            }
        }
    }

    if (!$kitcompat) {
        print "Warning: Could not determine the kit compatible framework values for \'$kitbasename\' from the kit.conf file. Continuing for now.\n";
        return 0;
    }

    my @kit_compat_list = split (',', $kitcompat);
    my @my_compat_list = split (',', $::COMPATIBLE_KITFRAMEWORKS);

    foreach my $myfw (@my_compat_list) {
        chomp $myfw;
        foreach my $kitfw (@kit_compat_list) {
            chomp $kitfw;

            if ($myfw eq $kitfw) {
                return 0;
            }
        }
    }
    print "Error: The kit named \'$kitbasename\' is not compatible with this version of the addkit command.  \'$kitbasename\' is compatible with \'$kitcompat\' and the addkit command is compatible with \'$::COMPATIBLE_KITFRAMEWORKS\'\n";
    return 1;
}
