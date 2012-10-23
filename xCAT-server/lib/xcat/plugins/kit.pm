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
use Data::Dumper;
use File::Basename;
use File::Path;

my $kitconf = "kit.conf";

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            addkit => "kit",
            rmkit => "kit",
            addkitcomp => "kit",
            rmkitcomp => "kit",
            chkkitcomp => "kit",
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

    if ($command eq "addkit"){
        $rc = addkit($request, $callback, $request_command);
    } elsif ($command eq "rmkit"){
        $rc = rmkit($request, $callback, $request_command);
    } elsif ($command eq "addkitcomp"){
        $rc = addkitcomp($request, $callback, $request_command);
    } elsif ($command eq "rmkitcomp"){
        $rc = rmkitcomp($request, $callback, $request_command);
    } elsif ($command eq "chkkitcomp"){
        $rc = chkkitcomp($request, $callback, $request_command);
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

    (my $kitcomptable) = $tabs->{kitcomponent}->getAttribs({kitcompname=> $kitcomp}, 'kitname', 'kitreponame', 'basename', 'kitpkgdeps', 'exlist', 'postbootscripts', 'driverpacks');
    (my $osimagetable) = $tabs->{osimage}->getAttribs({imagename=> $osimage}, 'osarch', 'postbootscripts', 'kitcomponents');
    (my $linuximagetable) = $tabs->{linuximage}->getAttribs({imagename=> $osimage}, 'exlist', 'otherpkglist', 'otherpkgdir', 'driverupdatesrc');
 
    # Adding postbootscrits to osimage.postbootscripts
    if ( $kitcomptable and $kitcomptable->{postbootscripts} ){
        my @kitcompscripts = split ',', $kitcomptable->{postbootscripts};
        foreach my $kitcompscript ( @kitcompscripts ) {

            my $formatedkitcomp = "KIT_".$kitcompscript;

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

    my $installdir = xCAT::TableUtils->getInstallDir();
    unless($installdir){
        $installdir = '/install';
    }
    $installdir =~ s/\/$//;


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
    if ( $kittable and $kittable->{kitdeployparams} and $kittable->{kitdir} ) { 

        # Reading contents from kit.kitdeployparams file
        my @contents;
        my $kitdir = $kittable->{kitdir};
        my $kitdeployfile = $kittable->{kitdeployparams};
        if ( -e "$kitdir/other_files/$kitdeployfile" ) {
            if (open(KITDEPLOY, "<", "$kitdir/other_files/$kitdeployfile") ) {
                @contents = <KITDEPLOY>;
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
            my $matched = 0;
            foreach my $line ( @lines ) {
                if ( $line =~ /$content/ ) {
                    $matched = 1;
                    last;
                }
            }

            unless ( $matched ) {
                push @l, $content;
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
    if ( $kitcomptable and $kitcomptable->{basename} ) {

        my @lines;
        my $basename = $kitcomptable->{basename};

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
        unless ( grep(/^$basename$/, @lines) ) {
            if (open(NEWOTHERPKGLIST, ">>", "$installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist")) {

                print NEWOTHERPKGLIST "$basename\n";
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
        my @kitpkgdeps = ();
        my @l = ();
        if ( $kitcomptable->{kitpkgdeps} ) {
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

            @kitpkgdeps = split ',', $kitcomptable->{kitpkgdeps}; 

        }

        push @kitpkgdeps, $basename;

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
            unless ( $matched ) {
                push @l, "$line\n";
            }
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
    my %kithash;
    my %kitrepohash;
    my %kitcomphash;

    my $xusage = sub {
        my %rsp;
        push@{ $rsp{data} }, "addkit: add Kits into xCAT from a list of tarball file or directory which have the same structure with tarball file";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\taddkit [-h|--help]";
        push@{ $rsp{data} }, "\taddkit [-p|--path <path>] <kitlist>] [-V]";
        $callback->(\%rsp);
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
            $callback->({error => ["Could not open xCAT table $t\n"],errorcode=>[1]});
            return 1;
        }
    }

    my $basename;
    my $des = shift @ARGV;

    my @kits = split ',', $des;
    my @kitnames;
    foreach my $kit (@kits) {

        my $kitdir = '';
        my $kittmpdir = '';

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
            $callback->({error => ["Can not find $kit"],errorcode=>[1]});
            return;
        }


        if(-d "$kit") {
            # This is a directory.
            # TODO: check if this is a valid kit directory.

            $kittmpdir = $kit;
        } else {
            # should be a tar.bz2 file

            $basename = basename($kit);
            $basename =~ s/.tar.bz2//;
            $kittmpdir = "/tmp/" . $basename;
            chmod(0666, "$kittmpdir/*");

            system("rm -rf $kittmpdir");

            if($::VERBOSE){
                $callback->({data=>["Extract Kit $kit to /tmp"]});
                $rc = system("tar jxvf $kit -C /tmp");
            } else {
                $rc = system("tar jxf $kit -C /tmp");
            }

        }


        if($rc){
            $callback->({error => ["Failed to extract Kit $kit, (Maybe there was no space left?)"],errorcode=>[1]});
        }

        # Read kit info from kit.conf
        my @lines;
        if (open(KITCONF, "<$kittmpdir/$kitconf")) {
            @lines = <KITCONF>;
            close(KITCONF);
            if($::VERBOSE){
                $callback->({data=>["\nReading kit configuration file $kittmpdir/$kitconf\n"]});
            }
        } else {
            $callback->({error => ["Could not open kit configuration file $kittmpdir/$kitconf\n"],errorcode=>[1]});
            return 1;
        }

        my $sec;
        my $kitname;
        my $kitreponame;
        my $kitcompname;
        my $scripts;
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
                next;
            } elsif ($line =~ /kitcomponent:/) {
                $sec = "KITCOMPONENT";
                next;
            } else {
                ($key,$value) = split /=/, $line;
            }

            # Add each attribute to different hash.
            if ( $sec =~ /KIT$/) {
                if ( $key =~ /kitname/ ) {
                    $kitname = $value;
                } else {
                    $kithash{$kitname}{$key} = $value;
                }
            } elsif ( $sec =~ /KITREPO$/ ) {    
                if ( $key =~ /kitreponame/ ) {
                    $kitreponame = $value;
                    $kitrepohash{$kitreponame}{kitrepodir} = $kitdir."/repos/".$kitreponame;
                } else {
                    $kitrepohash{$kitreponame}{$key} = $value;
                }
            } elsif ( $sec =~ /KITCOMPONENT$/ ) {
                if ( $key =~ /kitcompname/ ) {
                    $kitcompname = $value;
                } elsif ( $key =~ /postbootscripts/ ) {
                    $scripts = $scripts . ',' . $value;
                    $kitcomphash{$kitcompname}{$key} = $value;
                } else {
                    $kitcomphash{$kitcompname}{$key} = $value;
                }
            }
        }

        #TODO:  add check to see the the attributes name are acceptable by xCAT DB.
        #TODO: need to check if the files are existing or not, like exlist,

        unless (keys %kithash) {
            $callback->({error => ["Failed to add kit because kit.conf is invalid"],errorcode=>[1]});
            return 1;
        }

        (my $ref1) = $tabs{kit}->getAttribs({kitname => $kitname}, 'basename');
        if ( $ref1 and $ref1->{'basename'}){
            $callback->({error => ["Failed to add kit $kitname because it is already existing"],errorcode=>[1]});
            return 1;
        }

        $callback->({data=>["Adding Kit $kitname"]});

        # Moving kits from tmp directory to kitdir
        if (!$path) {
            $kitdir = $installdir . "/kits";
        } else {
            $kitdir = $path;
        }

        $kitdir =~ s/\/$//;
        $kitdir = $kitdir . "/" . $kitname;

        if($::VERBOSE){
            $callback->({data=>["Create Kit directory $kitdir"]});
        }
        mkpath($kitdir);

        # Set kitdir
        $kithash{$kitname}{kitdir} = $kitdir;

        if($::VERBOSE){
            $callback->({data=>["\nCopying Kit from $kittmpdir to $kitdir"]});
            $rc = system("cp -rfv $kittmpdir/* $kitdir");
        } else {
            $rc = system("cp -rf $kittmpdir/* $kitdir");
        }

        # Coying scripts to /installdir/postscripts/
        if($::VERBOSE){
            $callback->({data=>["\nCopying kit scripts from $kitdir/other_files/ to $installdir/postscripts"]});
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
            $callback->({error => ["Failed to copy scripts from $kitdir/scripts/ to $installdir/postscripts\n"],errorcode=>[1]});
            return 1;
        }

        # Copying plugins to /opt/xcat/lib/perl/xCAT_plugin/
        chmod(644, "$kitdir/plugins/*");

        if($::VERBOSE){
            $callback->({data=>["\nCopying kit plugins from $kitdir/plugins/ to $::XCATROOT/lib/perl/xCAT_plugin"]});
            $rc = system("cp -rfv $kitdir/plugins/* $::XCATROOT/lib/perl/xCAT_plugin/");
        } else {
            $rc = system("cp -rf $kitdir/plugins/* $::XCATROOT/lib/perl/xCAT_plugin/");
        }

        if($rc){
            $callback->({error => ["Failed to copy plugins from $kitdir/plugins/ to $::XCATROOT/lib/perl/xCAT_plugin\n"],errorcode=>[1]});
            return 1;
        }

        # Write to DB
        if($::VERBOSE){
            $callback->({data=>["\nWriting kit configuration into xCAT DB"]});
        }

        foreach my $kitname (keys %kithash) {
            $tabs{kit}->setAttribs({kitname => $kitname }, \%{$kithash{$kitname}} );
        }

        foreach my $kitreponame (keys %kitrepohash) {
            $tabs{kitrepo}->setAttribs({kitreponame => $kitreponame }, \%{$kitrepohash{$kitreponame}} );
        }

        foreach my $kitcompname (keys %kitcomphash) {
            $tabs{kitcomponent}->setAttribs({kitcompname => $kitcompname }, \%{$kitcomphash{$kitcompname}} );
        }

        push @kitnames, $kit;
    }

    my $kitlist = join ',', @kitnames;
    $callback->({data=>["\nKit $kitlist was successfully added."]});

    # Issue xcatd reload to load the new plugins
    system("/etc/init.d/xcatd reload");

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
        $callback->(\%rsp);
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
            $callback->({error => ["Could not open xCAT table $t\n"],errorcode=>[1]});
            return 1;
        }
    }

    # Convert to kitname if input is a basename
    my %kitnames;
    my $des = shift @ARGV;
    my @kits = split ',', $des;
    foreach my $kit (@kits) {

        # Check if it is a kitname or basename

        (my $ref1) = $tabs{kit}->getAttribs({kitname => $kit}, 'basename');
        if ( $ref1 and $ref1->{'basename'}){
            $kitnames{$kit} = 1;
        } else {
            my @entries = $tabs{kit}->getAllAttribsWhere( "basename = '$kit'", 'kitname' );
            unless (@entries) {
                $callback->({error => ["Kit $kit could not be found in DB $t\n"],errorcode=>[1]});
                return 1;
            }
            foreach my $entry (@entries) {
                $kitnames{$entry->{kitname}} = 1;
            }
        }
    }

    # Remove each kit
    my @entries = $tabs{'osimage'}->getAllAttribs( 'imagename', 'kitcomponents' );
    my @kitlist;

    foreach my $kitname (keys %kitnames) {

        $callback->({data=>["Removing kit $kitname"]});

        # Remove osimage.kitcomponents.

        # Find all the components in this kit.
        my $kitcompnames;
        my @kitcomphash = $tabs{kitcomponent}->getAllAttribsWhere( "kitname = '$kitname'", 'kitcompname');

        if (defined(@entries) && (@entries > 0)) {  

            if($::VERBOSE){
                $callback->({data=>["Removing kit components from osimage.kitcomponents"]});
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
                                $callback->({error => ["Failed to remove kit component $kitcomponent because:$kitcomponent is being used by osimage $entry->{imagename}\n"],errorcode=>[1]});
                                return 1;
                            }

                            # Remove this component from osimage.kitcomponents. Mark here.
                            my $ret = xCAT::Utils->runxcmd({ command => ['rmkitcomp'], arg => ['-f','-u','-i',$entry->{imagename}, $kitcompname] }, $request_command, 0, 1);
                            if ( $::RUNCMD_RC ) {
                                $callback->({error => ["ret=$ret,Failed to remove kit component $kitcomponent from $entry->{imagename}\n"],errorcode=>[1]});
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
                $callback->({data=>["Removing kit plugins from $::XCATROOT/lib/perl/xCAT_plugin/"]});
            }
            opendir($dir, $kitdir."/plugins");
            my @files = readdir($dir);
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
                $callback->({data=>["Removing kit scripts from /install/postscripts/"]});
            }
            # remove kit scripts from /install/postscripts/
            my $installdir = xCAT::TableUtils->getInstallDir();
            unless($installdir){
                $installdir = '/install';
            }
            $installdir =~ s/\/$//;

            opendir($dir, $kitdir."/scripts");
            my @files = readdir($dir);
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
                $callback->({data=>["Removing kitdir from installdir"]});
                system("rm -rfv $kitdir");
            } else {
                system("rm -rf $kitdir");
            }
        }


        if($::VERBOSE){
            $callback->({data=>["Removing kit from xCAT DB"]});
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
    $callback->({data=>["Kit $kits was successfully removed."]});

    # Issue xcatd reload to load the new plugins
    system("/etc/init.d/xcatd reload");

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
        push@{ $rsp{data} }, "\taddkitcomp [-a|--adddeps] [-f|--force] [-V|--verbose] -i <osimage> <kitcompname_list>";
        $callback->(\%rsp);
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
            $callback->({error => ["Could not open xCAT table $t\n"],errorcode=>[1]});
            return 1;
        }
    }

    # Check if all the kitcomponents are existing before processing

    if($::VERBOSE){
        $callback->({data=>["Checking if kitcomponents are valid"]});
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
                $callback->({error => ["$kitcomponent kitcomponent does not exist\n"],errorcode=>[1]});
                return 1;
            }
            
            my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);
            $kitcomps{$highest}{name} = $highest;
            $kitcomps{$highest}{basename} = $kitcomponent;
        }
    }

    # Verify if the kitcomponents fitting to the osimage or not.

    if($::VERBOSE){
        $callback->({data=>["Verifying if kitcomponents fit to osimage"]});
    }

    my %os;
    my $osdistrotable;
    (my $osimagetable) = $tabs{osimage}->getAttribs({imagename=> $osimage}, 'osdistroname', 'serverrole', 'kitcomponents');
    if ( $osimagetable and $osimagetable->{'osdistroname'}){
        ($osdistrotable) = $tabs{osdistro}->getAttribs({osdistroname=> $osimagetable->{'osdistroname'}}, 'basename', 'majorversion', 'minorversion', 'arch', 'type');
        if ( !$osdistrotable or !$osdistrotable->{basename} ) {
            $callback->({error => ["$osdistroname osdistro does not exist\n"],errorcode=>[1]});
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

    } else {
        $callback->({error => ["$osimage osimage does not exist or not saticified\n"],errorcode=>[1]});
        return 1;
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
                $callback->({error => ["$kitcomptable->{'kitname'} ostype does not exist\n"],errorcode=>[1]});
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
                $callback->({error => ["$kitcomp osbasename,osmajorversion,osminorversion or osarch does not exist\n"],errorcode=>[1]});
                return 1;
            }
                            
        }  else {
            $callback->({error => ["$kitcomp kitname or kitrepo name does not exist\n"],errorcode=>[1]});
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
                $callback->({error => ["osimage $osimage doesn't fit to kit component $kitcomp with attribute OS \n"],errorcode=>[1]});
                return 1;
            }

            if ( $os{$osimage}{majorversion} ne $kitcomps{$kitcomp}{osmajorversion} ) {
                $callback->({error => ["osimage $osimage doesn't fit to kit component $kitcomp with attribute majorversion\n"],errorcode=>[1]});
                return 1;
            }

            if ( $os{$osimage}{minorversion} and ($os{$osimage}{minorversion} ne $kitcomps{$kitcomp}{osminorversion}) ) {
                $callback->({error => ["osimage $osimage doesn't fit to kit component $kitcomp with attribute minorversion\n"],errorcode=>[1]});
                return 1;
            }

            if ( $os{$osimage}{arch} ne $kitcomps{$kitcomp}{osarch} ) {
                $callback->({error => ["osimage $osimage doesn't fit to kit component $kitcomp with attribute arch\n"],errorcode=>[1]});
                return 1;
            }

            if ( $os{$osimage}{type} ne $kitcomps{$kitcomp}{ostype} ) {
                $callback->({error => ["osimage $osimage doesn't fit to kit component $kitcomp with attribute type\n"],errorcode=>[1]});
                return 1;
            }

            if ( $os{$osimage}{serverrole} and ($os{$osimage}{serverrole} ne $kitcomps{$kitcomp}{serverroles}) ) {
                $callback->({error => ["osimage $osimage doesn't fit to kit component $kitcomp with attribute serverrole\n"],errorcode=>[1]});
                return 1;
            }

            if ( $kitcomptable and $kitcomptable->{'kitcompdeps'} ) {
                my @kitcompdeps = split ',', $kitcomptable->{'kitcompdeps'};
                foreach my $kitcompdep ( @kitcompdeps ) {
                    my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcompdep'", 'kitcompname' , 'version', 'release');
                    unless (@entries) {
                        $callback->({error => ["Cannot find any matched kit component for kit component $kitcomp dependency $kitcompdep\n"],errorcode=>[1]});
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
                            $callback->({error => ["kit component dependency $highest for kit component $kitcomp is not existing in osimage or specified in command option\n"],errorcode=>[1]});
                            return 1;
                        }
                    }
                }
            }
        }

        if($::VERBOSE){
            $callback->({data=>["kitcomponent $kitcomp fits to osimage $osimage"]});
        }
    }
    
    # Now assign each component to the osimage

    if($::VERBOSE){
        $callback->({data=>["Assigning kitcomponent to osimage"]});
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

        $callback->({data=>["Assigning kit component $kitcomp to osimage $osimage"]});
        # Check if this component is existing in osimage.kitcomponents
        foreach my $oskitcomp ( @oskitcomps ) {
            if ( $kitcomp eq $oskitcomp ) {
                $callback->({data=>["$kitcomp kit component is already in osimage $osimage"]});
                $catched = 1;
                last;
            } 
        }

        # No matching kitcomponent name in osimage.kitcomponents, now checking their basenames.
        if ( !$catched ) {

            my $add = 0;
            foreach my $oskitcomp ( @oskitcomps ) {

                # Compare this kit component's basename with basenames in osimage.kitcomponents
                (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomp}, 'basename', 'version', 'release');
                if ( !$kitcomptable or !$kitcomptable->{'basename'} ) {
                    $callback->({error => ["$kitcomp kit component does not have basename"],errorcode=>[1]});
                    return 1;
                }
                (my $oskitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $oskitcomp}, 'basename', 'version', 'release');
                if ( !$oskitcomptable or !$oskitcomptable->{'basename'} ) {
                    $callback->({error => ["$oskitcomp kit component does not have basename"],errorcode=>[1]});
                    next;
                }

                if ( $kitcomptable->{'basename'} eq $oskitcomptable->{'basename'} ) {
                    my $rc = compare_version($oskitcomptable,$kitcomptable,'kitcompname', 'version', 'release');
                    if ( $rc == 1 ) {
                        $callback->({data=>["Upgrading kit component $oskitcomp to $kitcomp"]});
                        my $ret = xCAT::Utils->runxcmd({ command => ['rmkitcomp'], arg => ['-f','-u','-i',$osimage, $kitcomp] }, $request_command, -2, 1);
                        if ( !$ret ) {
                            $callback->({error => ["Failed to remove kit component $kitcomp from $osimage\n"],errorcode=>[1]});
                            return 1;
                        }
                        $add = 1;
                    } elsif ( $rc == 0 ) {
                        $callback->({data=>["Do nothing since kit component $oskitcomp in osimage $osimage has the same basename/version and release with kit component $kitcomp."]});
                        next;
                    } else {
                        $callback->({error => ["kit component $oskitcomp is already in osimage $osimage, and has a newer release/version than $kitcomp.  Downgrading kit component is not supported"],errorcode=>[1]});
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
    $callback->({data=>["Kit components $kitnames were added to osimage $osimage successfully"]});
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
        $callback->(\%rsp);
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
            $callback->({error => ["Could not open xCAT table $t\n"],errorcode=>[1]});
            return 1;
        }
    }


    # Check if all the kitcomponents are existing before processing

    if($::VERBOSE){
        $callback->({data=>["Checking if kitcomponents are valid"]});
    }

    my %kitcomps;
    my $des = shift @ARGV;
    my @kitcomponents = split ',', $des;
    foreach my $kitcomponent (@kitcomponents) {

        # Check if it is a kitcompname or basename
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomponent}, 'kitname', 'kitpkgdeps', 'postbootscripts', 'kitreponame', 'exlist', 'basename', 'driverpacks');
        if ( $kitcomptable and $kitcomptable->{'kitname'}){
            $kitcomps{$kitcomponent}{name} = $kitcomponent;
            $kitcomps{$kitcomponent}{kitname} = $kitcomptable->{kitname};
            $kitcomps{$kitcomponent}{kitpkgdeps} = $kitcomptable->{kitpkgdeps};
            $kitcomps{$kitcomponent}{basename} = $kitcomptable->{basename};
            $kitcomps{$kitcomponent}{exlist} = $kitcomptable->{exlist};
            $kitcomps{$kitcomponent}{postbootscripts} = $kitcomptable->{postbootscripts};
            $kitcomps{$kitcomponent}{kitreponame} = $kitcomptable->{kitreponame};
            $kitcomps{$kitcomponent}{driverpacks} = $kitcomptable->{driverpacks};
        } else {
            my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcomponent'", 'kitcompname' , 'version', 'release');
            unless (@entries) {
                $callback->({error => ["$kitcomponent kitcomponent does not exist\n"],errorcode=>[1]});
                return 1;
            }

            my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);
            $kitcomps{$highest}{name} = $highest;
            (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $highest}, 'kitname', 'kitpkgdeps', 'postbootscripts', 'kitreponame', 'exlist', 'basename', 'driverpacks');
            $kitcomps{$highest}{kitname} = $kitcomptable->{kitname};
            $kitcomps{$highest}{kitpkgdeps} = $kitcomptable->{kitpkgdeps};
            $kitcomps{$highest}{basename} = $kitcomptable->{basename};
            $kitcomps{$highest}{exlist} = $kitcomptable->{exlist};
            $kitcomps{$highest}{postbootscripts} = $kitcomptable->{postbootscripts};
            $kitcomps{$highest}{kitreponame} = $kitcomptable->{kitreponame};
            $kitcomps{$highest}{driverpacks} = $kitcomptable->{driverpacks};
        }
    }
    # Check if the kitcomponents are existing in osimage.kitcomponents attribute.

    (my $osimagetable) = $tabs{osimage}->getAttribs({imagename => $osimage}, 'kitcomponents', 'postbootscripts');
    if ( !$osimagetable or !$osimagetable->{'kitcomponents'} ){
        $callback->({error => ["$osimage osimage does not exist or not includes any kit components\n"],errorcode=>[1]});
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
        $callback->({error => ["$invalidkitcomp kit components are not assigned to osimage $osimage\n"],errorcode=>[1]});;
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
                        $callback->({error => ["$kitcompdep kitcomponent basename does not exist\n"],errorcode=>[1]});
                         return 1;
                    }

                    my $kitcompdepname = get_highest_version('kitcompname', 'version', 'release', @entries);

                    if ( ($kitcomponent eq $kitcompdepname) and !$force and !exists($kitcomps{$osikitcomp}) ) {
                        # There is other kitcomponent depending on this one and there is no --force option
                        $callback->({error => ["$osikitcomp kitcomponent is still depending on this kitcomponent $kitcomponent\n"],errorcode=>[1]});;
                        return 1;
                    }
                }
            }
        }
    }


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


    # Remove kitcomponent.postbootscripts from osimage.postbootscripts.

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
                if ( $osimagescript =~ /^KIT_$kitcompscript$/ ) {
                    $match = 1;
                    last;
                }
            }

            last if ($match);
        }

        if (!$match) {
            push @newosimagescripts, $osimagescript
        }
    }

    my $newosimagescript = join ',', @newosimagescripts;
    $osimagetable->{'postbootscripts'} = $newosimagescript;

    # Remove symlink from osimage.otherpkgdir.

    (my $linuximagetable) = $tabs{linuximage}->getAttribs({imagename=> $osimage}, 'exlist', 'otherpkglist', 'otherpkgdir', 'driverupdatesrc');
    if ( $linuximagetable and $linuximagetable->{otherpkgdir} ) {

        my $otherpkgdir = $linuximagetable->{otherpkgdir};
        foreach my $kitcomponent (keys %kitcomps) {
            if ( $kitcomps{$kitcomponent}{kitreponame} ) {
                if ( -d "$otherpkgdir/$kitcomps{$kitcomponent}{kitreponame}" ) {
                    system("rm -rf $otherpkgdir/$kitcomps{$kitcomponent}{kitreponame}");
                }
            }
        }
    }


    # Remove kitcomponent exlist,otherpkglist and deploy_params from osimage

    my $installdir = xCAT::TableUtils->getInstallDir();
    unless($installdir){
        $installdir = '/install';
    }
    $installdir =~ s/\/$//;

    my @kitlist;
    foreach my $kitcomponent (keys %kitcomps) {

        $callback->({data=>["Removing kitcomponent $kitcomponent from osimage $osimage"]});

        if ( !exists($kitcomps{$kitcomponent}{kitname}) ) {
            $callback->({error => ["Could not find kit object for kitcomponent $kitcomponent"],errorcode=>[1]});
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
                        $callback->({data=>["\nReading kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist\n"]});
                    }
                } else {
                    $callback->({error => ["Could not open kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist"],errorcode=>[1]});
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
                    if ( $line =~ /^#INCLUDE:$kitdir\/other_files\/$exlistfile#$/ ) {
                        next;
                    }
                    push @newlines, $line;
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
                        $callback->({data=>["\nReading kit component otherpkg pkglist $installdir/osimages/$osimage/kits/KIT_COMPONENTS.otherpkgs.pkglist\n"]});
                    }
                } else {
                    $callback->({error => ["Could not open kit component exlist file $installdir/osimages/$osimage/kits/KIT_COMPONENTS.exlist"],errorcode=>[1]});
                    return 1;
                }

                my $basename = '';
                if ( exists($kitcomps{$kitcomponent}{basename}) ) {
                    $basename = $kitcomps{$kitcomponent}{basename};

                    my @newlines = ();
                    foreach my $line ( @lines ) {
                        if ( $line =~ /^$basename$/ ) {
                            next;
                        }
                        push @newlines, $line;
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
                            $callback->({data=>["\nReading kit component rmpkgs file $installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist\n"]});
                        }
                    } else {
                        $callback->({error => ["Could not open kit component rmpkgs file $installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist"],errorcode=>[1]});
                        return 1;
                    }
                }

                my @l = @lines;
                my $basename = '';
                my @kitpkgdeps = ();

                if ( exists($kitcomps{$kitcomponent}{basename}) ) {
                    $basename = $kitcomps{$kitcomponent}{basename};
                } else {
                    $callback->({error => ["Could not open kit component table and read basename for kit component $kitcomp"],errorcode=>[1]});
                    return 1;
                }

                if ( exists($kitcomps{$kitcomponent}{kitpkgdeps}) ) {
                    @kitpkgdeps = split ',', $kitcomps{$kitcomponent}{kitpkgdeps};
                }

                push @kitpkgdeps, $basename;

                foreach my $kitpkgdep ( @kitpkgdeps ) {
                    my $matched = 0;
                    foreach my $line ( @lines ) {
                        chomp $line;
                        if ( $line =~ /^-$kitpkgdep$/ ) {
                            $matched = 1;
                            last;
                        }
                    }

                    unless ( $matched ) {
                        push @l, "-$kitpkgdep\n";
                    }

                }

                if (open(RMPKGLIST, ">", "$installdir/osimages/$osimage/kits/KIT_RMPKGS.otherpkgs.pkglist")) {
                    print RMPKGLIST @l;
                    close(RMPKGLIST);
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
                                $callback->({data=>["\nReading kit deployparams from $kitdir/other_files/$kitdeployfile\n"]});
                            }
                        } else {
                            $callback->({error => ["Could not open kit deployparams file $kitdir/other_files/$kitdeployfile"],errorcode=>[1]});
                        }
                    }

                    my @lines = ();
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

                    my @newcontents = ();
                    foreach my $line ( @lines ) {
                        my $found = 0;
                        foreach my $content ( @contents ) {
                            if ( $line =~ /$content/ ) {
                                $found = 1;
                                last;
                            }
                        }

                        unless ( $found ) {
                            push @newcontents, $line;
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
    $callback->({data=>["kitcomponents $kitcompnames were removed from osimage $osimage successfully"]});

    # Write linuximage table with all the above udpates.
    $tabs{linuximage}->setAttribs({imagename => $osimage }, \%{$linuximagetable} );

    # Write osimage table with all the above udpates.
    $tabs{osimage}->setAttribs({imagename => $osimage }, \%{$osimagetable} );

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
        push@{ $rsp{data} }, "\tchkkitcomp [-o|--overwrite] [-V|--verbose] -i <osimage> <kitcompname_list>";
        $callback->(\%rsp);
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
            'o|overwrite' => \$overwrite,
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
            $callback->({error => ["Could not open xCAT table $t\n"],errorcode=>[1]});
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
                $callback->({error => ["$kitcomponent kitcomponent does not exist\n"],errorcode=>[1]});
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
    (my $osimagetable) = $tabs{osimage}->getAttribs({imagename=> $osimage}, 'osdistroname', 'serverrole', 'kitcomponents');
    if ( $osimagetable and $osimagetable->{'osdistroname'}){
        ($osdistrotable) = $tabs{osdistro}->getAttribs({osdistroname=> $osimagetable->{'osdistroname'}}, 'basename', 'majorversion', 'minorversion', 'arch', 'type');
        if ( !$osdistrotable or !$osdistrotable->{basename} ) {
            $callback->({error => ["$osdistroname osdistro does not exist\n"],errorcode=>[1]});
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

    } else {
        $callback->({error => ["$osimage osimage does not exist or not saticified\n"],errorcode=>[1]});
        return 1;
    }

    my @kitcompnames;
    foreach my $kitcomp ( keys %kitcomps ) {
        if ( $kitcomps{$kitcomp}{kitname} and $kitcomps{$kitcomp}{kitreponame}) { 

            # Read ostype from kit table
            (my $kittable) = $tabs{kit}->getAttribs({kitname => $kitcomps{$kitcomp}{kitname}}, 'ostype');
            if ( $kittable and $kittable->{ostype} ) {
                $kitcomps{$kitcomp}{ostype} = lc($kittable->{ostype});
            } else {
                $callback->({error => ["$kitcomp ostype does not exist\n"],errorcode=>[1]});
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
                $callback->({error => ["$kitcomp osbasename,osmajorversion,osminorversion or osarch does not exist\n"],errorcode=>[1]});
                return 1;
            }

        }  else {
            $callback->({error => ["$kitcomp kitname $kitcomptable->{'kitname'} or kitrepo name $kitcomptable->{'kitreponame'} or serverroles $kitcomps{$kitcomp}{serverroles} does not exist.\n"],errorcode=>[1]});
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
            $callback->({error => ["kit component $kitcomp doesn't fit to osimage $osimage with attribute OS \n"],errorcode=>[1]});
            return 1;
        }

        if ( $os{$osimage}{majorversion} ne $kitcomps{$kitcomp}{osmajorversion} ) {
            $callback->({error => ["kit component $kitcomp doesn't fit to osimage $osimage with attribute majorversion\n"],errorcode=>[1]});
            return 1;
        }

        if ( $os{$osimage}{minorversion} and ($os{$osimage}{minorversion} ne $kitcomps{$kitcomp}{osminorversion}) ) {
            $callback->({error => ["kit component $kitcomp doesn't fit to osimage $osimage with attribute minorversion\n"],errorcode=>[1]});
            return 1;
        }

        if ( $os{$osimage}{arch} ne $kitcomps{$kitcomp}{osarch} ) {
            $callback->({error => ["kit component $kitcomp doesn't fit to osimage $osimage with attribute arch\n"],errorcode=>[1]});
            return 1;
        }

        if ( $os{$osimage}{type} ne $kitcomps{$kitcomp}{ostype} ) {
            $callback->({error => ["kit component $kitcomp doesn't fit to osimage $osimage with attribute type\n"],errorcode=>[1]});
            return 1;
        }

        if ( $os{$osimage}{serverrole} and ($os{$osimage}{serverrole} ne $kitcomps{$kitcomp}{serverroles}) ) {
            $callback->({error => ["kit component $kitcomp doesn't fit to osimage $osimage with attribute serverrole\n"],errorcode=>[1]});
            return 1;
        }

        # Check if this kit component's dependencies are in the kitcomponent list.
        if ( $kitcomps{$kitcomp}{kitcompdeps} and !exists( $kitcompbasename{ $kitcomps{$kitcomp}{kitcompdeps} } ) ) {
            $callback->({error => ["kit component $kitcomp dependency $kitcomps{$kitcomp}{kitcompdeps} doesn't existing\n"],errorcode=>[1]});
            return 1;
        }

        push @kitcompnames, $kitcomp;
    }

    my $kitcompnamelist = join ',', @kitcompnames;

    $callback->({data=>["\nKit components $kitcompnamelist fit to osimage $osimage\n"]});    

}

1;

