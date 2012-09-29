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

    my $command  = $request->{command}->[0];

    if ($command eq "addkit"){
            return addkit($request, $callback);
    } elsif ($command eq "rmkit"){
            return rmkit($request, $callback);
    } elsif ($command eq "addkitcomp"){
        return addkitcomp($request, $callback);
    } elsif ($command eq "rmkitcomp"){
            return rmkitcomp($request, $callback);
    } else{
            $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
            #return (1, "$command not found);
    }

    return;

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

=head3 addkit

  Assign a kit component to osimage

=cut

#-------------------------------------------------------
sub assign_to_osimage
{
    my $osimage = shift;
    my $kitcomp = shift;
    my $callback = shift;
    my $tabs = shift;

    (my $kitcomptable) = $tabs->{kitcomponent}->getAttribs({kitcompname=> $kitcomp}, 'kitname', 'kitreponame', 'basename', 'kitpkgdeps', 'exlist', 'postbootscripts');
    (my $osimagetable) = $tabs->{osimage}->getAttribs({imagename=> $osimage}, 'postbootscripts', 'kitcomponents');
 
    # Adding postbootscrits to osimage.postbootscripts
    if ( $kitcomptable and $kitcomptable->{postbootscripts} ){
        if ( $osimagetable ){
            if ( $osimagetable->{postbootscripts} ) {
                my $match = 0;
                my @scripts = split ',', $osimagetable->{postbootscripts};
                foreach my $script ( @scripts ) {
                    if ( $kitcomptable->{postbootscripts} =~ /^$script$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $osimagetable->{postbootscripts} = $osimagetable->{postbootscripts} . ',' . $kitcomptable->{postbootscripts};
                }
            } else {
                $osimagetable->{postbootscripts} = $kitcomptable->{postbootscripts};
            }
            
        }
    }

    (my $linuximagetable) = $tabs->{linuximage}->getAttribs({imagename=> $osimage}, 'exlist', 'otherpkglist', 'otherpkgdir');

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
        mkpath("$installdir/kits/custom/$osimage/");
        if ( -e "$installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist" ) {
            if (open(EXLIST, "<", "$installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist")) {
                @lines = <EXLIST>;
                close(EXLIST);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit component exlist file $installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit component exlist file $installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist"],errorcode=>[1]});
                return 1;
            }
        }
        unless ( grep(/^#INCLUDE:$kitdir\/other_files\/$exlistfile#$/ , @lines) ) {
            if (open(NEWEXLIST, ">>", "$installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist")) {
                
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
                    if ( $exlist =~ /^$installdir\/kits\/custom\/$osimage\/KIT_COMPONENTS.exlist$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $linuximagetable->{exlist} = $linuximagetable->{exlist} . ',' . "$installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist";
                }
            } else {
                $linuximagetable->{exlist} = "$installdir/kits/custom/$osimage/KIT_COMPONENTS.exlist";
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
        mkpath("$installdir/kits/custom/$osimage/");
        if ( -e "$installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist" ) {
            if (open(DEPLOYPARAM, "<", "$installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist")) {
                @lines = <DEPLOYPARAM>;
                close(DEPLOYPARAM);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit deployparams file $installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit deployparams file $installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist"],errorcode=>[1]});
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
        if (open(NEWDEPLOYPARAM, ">>", "$installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist")) {
            print NEWDEPLOYPARAM @l;
            close(NEWDEPLOYPARAM);
        }

        # Write this kit deployparams to osimage.otherpkglist if not existing.
        if ( $linuximagetable ) {
            if ( $linuximagetable->{otherpkglist} ) {
                my $match = 0;
                my @otherpkglists= split ',', $linuximagetable->{otherpkglist};
                foreach my $otherpkglist ( @otherpkglists ) {
                    if ( $otherpkglist =~ /^$installdir\/kits\/custom\/$osimage\/KIT_DEPLOY_PARAMS.otherpkgs.pkglist$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $linuximagetable->{otherpkglist} = $linuximagetable->{otherpkglist} . ',' . "$installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist";
                }
            } else {
                $linuximagetable->{otherpkglist} = "$installdir/kits/custom/$osimage/KIT_DEPLOY_PARAMS.otherpkgs.pkglist";
            }
        }

    }

    # Adding kit component basename to osimage.otherpkgs.pkglist
    if ( $kitcomptable and $kitcomptable->{basename} ) {

        my @lines;
        my $basename = $kitcomptable->{basename};

        # Adding kit component basename to KIT_COMPONENTS.otherpkgs.pkglist file
        mkpath("$installdir/kits/custom/$osimage/");
        if ( -e "$installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist" ) {
            if (open(OTHERPKGLIST, "<", "$installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist")) {
                @lines = <OTHERPKGLIST>;
                close(OTHERPKGLIST);
                if($::VERBOSE){
                    $callback->({data=>["\nReading kit component otherpkg file $installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist\n"]});
                }
            } else {
                $callback->({error => ["Could not open kit component otherpkg file $installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist"],errorcode=>[1]});
                return 1;
            }
        }
        unless ( grep(/^$basename$/, @lines) ) {
            if (open(NEWOTHERPKGLIST, ">>", "$installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist")) {

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
                    if ( $otherpkglist =~ /^$installdir\/kits\/custom\/$osimage\/KIT_COMPONENTS.otherpkgs.pkglist$/ ) {
                        $match = 1;
                        last;
                    }
                }
                unless ( $match ) {
                    $linuximagetable->{otherpkglist} = $linuximagetable->{otherpkglist} . ',' . "$installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist";
                }
            } else {
                $linuximagetable->{otherpkglist} = "$installdir/kits/custom/$osimage/KIT_COMPONENTS.otherpkgs.pkglist";
            }

        }

        # Remove this component basename and pkgnames from KIT_RMPKGS.otherpkg.pkglist
        if ( $kitcomptable->{kitpkgdeps} ) {
            my @lines;
            if ( -e "$installdir/kits/custom/$osimage/KIT_RMPKGS.otherpkgs.pkglist" ) {
                if (open(RMOTHERPKGLIST, "<", "$installdir/kits/custom/$osimage/KIT_RMPKGS.otherpkgs.pkglist")) {
                    @lines = <RMOTHERPKGLIST>;
                    close(RMOTHERPKGLIST);
                    if($::VERBOSE){
                        $callback->({data=>["\nReading kit component rmpkgs file $installdir/kits/custom/$osimage/KIT_RMPKGS.otherpkgs.pkglist\n"]});
                    }
                } else {
                    $callback->({error => ["Could not open kit component rmpkgs file $installdir/kits/custom/$osimage/KIT_RMPKGS.otherpkgs.pkglist"],errorcode=>[1]});
                    return 1;
                }
            }

            my @l;
            my @kitpkgdeps = split ',', $kitcomptable->{kitpkgdeps}; 
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

                if ( $line =~ /^-$basename$/ ) {
                    $matched = 1;
                    $changed = 1;
                }

                unless ( $matched ) {
                    push @l, "$line\n";
                }
            }

            if ( scalar(@l) and $changed ) {
                if (open(RMPKGLIST, ">", "$installdir/kits/custom/$osimage/KIT_RMPKGS.otherpkgs.pkglist")) {
                    print RMPKGLIST @l;
                    close(RMPKGLIST);
                }
            }
        } else {
            $callback->({error => ["Could not open kit component table and read basename for kit component $kitcomp"],errorcode=>[1]});
            return 1;
        }

    } else {
        $callback->({error => ["Could not open kit component table and read basename for kit component $kitcomp"],errorcode=>[1]});
        return 1;
    }

    #TODO: adding driverpacks
    

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


    my $kitdir;
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
            'p|path=s' => \$kitdir
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
    foreach my $kit (@kits) {

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

        unless(-r $kit){
            $callback->({error => ["Can not find $kit"],errorcode=>[1]});
            return;
        }


        if (!$kitdir) {
            $kitdir = $installdir . "/kits";
        }
        if($::VERBOSE){
            $callback->({data=>["Create Kit directory $kitdir"]});
        }

        $kitdir =~ s/\/$//;
        mkdir($kitdir);

        if(-d "$kit") {
            # This is a directory.
            # TODO: check if this is a valid kit directory.

            if($::VERBOSE){
                $callback->({data=>["Copying Kit from $kit to $kitdir"]});
                $rc = system("cp -rfv $kit $kitdir");
            } else {
                $rc = system("cp -rf $kit $kitdir");
            }

            $basename = basename($kit);
        } else {
            # should be a tar.bz2 file
            if($::VERBOSE){
                $callback->({data=>["Extract Kit $kit to $kitdir"]});
                $rc = system("tar jxvf $kit -C $kitdir");
            } else {
                $rc = system("tar jxf $kit -C $kitdir");
            }

            # Need discussion of how to get dirname from kit tarball file.  For example, how to get kit-test from kit-test.tar.bz2.
            # Remove the tar.bz2 directly or extract it to a clean dir and get its name? 
            $basename = basename($kit);
            $basename =~ s/.tar.bz2//;
        }


        $kitdir = $kitdir ."/". $basename;
        chmod(0666, "$kitdir/*");


        if($rc){
            $callback->({error => ["Failed to extract Kit $kit, (Maybe there was no space left?)"],errorcode=>[1]});
        }

        # Read kit info from kit.conf
        my @lines;
        if (open(KITCONF, "<$kitdir/$kitconf")) {
            @lines = <KITCONF>;
            close(KITCONF);
            if($::VERBOSE){
                $callback->({data=>["\nReading kit configuration file $kitdir/$kitconf\n"]});
            }
        } else {
            $callback->({error => ["Could not open kit configuration file $kitdir/$kitconf\n"],errorcode=>[1]});
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
                    $kithash{$kitname}{kitdir} = $kitdir;
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
                } elsif ( $key =~ /postboot/ ) {
                    $scripts = $scripts . ',' . $value;
                } else {
                    $kitcomphash{$kitcompname}{$key} = $value;
                }
            }
        }

        #TODO:  add check to see the the attributes name are acceptable by xCAT DB.
        #TODO: need to check if the files are existing or not, like exlist,
        # Write to DB
        if($::VERBOSE){
            $callback->({data=>["Writing kit configuration into xCAT DB\n"]});
        }

        unless (keys %kithash) {
            $callback->({error => ["Failed to add kit because there is no kit.conf or kit.conf is empty"],errorcode=>[1]});
            return 1;
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

        # Coying scripts to /installdir/postscripts/
        if($::VERBOSE){
            $callback->({data=>["Copying kit scripts from $kitdir/other_files/ to $installdir/postscripts"]});
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
        }


        $callback->({data=>["\nKit $kit was successfully added."]});
    }

    # Issue xcatd reload to load the new plugins
    system("/etc/init.d/xcatd reload");

}

#-------------------------------------------------------

=head3 rmkit

  Remove auto-generated files and their name from persistant file.

=cut

#-------------------------------------------------------
sub rm_gen_file
{
    my $kitcomponent = shift;

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

    foreach my $kitname (keys %kitnames) {

        # Remove osimage.kitcomponents.

        # Find all the components in this kit.
        my $kitcompnames;
        my @kitcomphash = $tabs{kitcomponent}->getAllAttribsWhere( "kitname = '$kitname'", 'kitcompname');

        if (defined(@entries) && (@entries > 0)) {  

            if($::VERBOSE){
                $callback->({data=>["Removing kit components from osimage.kitcomponents"]});
            }
            my @newkitcomponents;
            foreach my $entry (@entries) {

                my $catched = 0;

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
                            $catched = 1; 
                        } else {
                            push @newkitcomponents, $kitcomponent;
                        }
                    }
                }


                # Some kitcomponents attributes changed, set it back to DB.

                if ( $catched ) {
                    my $newnewkitcomponent = join ',', @newkitcomponents;
                    $tabs{osimage}->setAttribs({imagename => $entry->{imagename} }, {kitcomponents => "$newnewkitcomponent"} );
                }

                # Check if this kit component generated files has been put to osimage.exlist,osimage.otherpkglist.
                # Don't need to check -f option again, it should have returned if no -f option while checking osimage.kitcomponents.
#                rm_gen_files();

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

        $callback->({data=>["Kit $kitname was successfully removed."]});

    }

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

    my %kitcomps;
    my $des = shift @ARGV;
    my @kitcomponents = split ',', $des;
    foreach my $kitcomponent (@kitcomponents) {

        # Check if it is a kitcompname or basename
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomponent}, 'kitname');
        if ( $kitcomptable and $kitcomptable->{'kitname'}){
            $kitcomps{$kitcomponent}{name} = $kitcomponent;
        } else {
            my @entries = $tabs{kitcomponent}->getAllAttribsWhere( "basename = '$kitcomponent'", 'kitcompname' , 'version', 'release');
            unless (@entries) {
                $callback->({error => ["$kitcomponent kitcomponent does not exist\n"],errorcode=>[1]});
                return 1;
            }
            
            my $highest = get_highest_version('kitcompname', 'version', 'release', @entries);
            $kitcomps{$highest}{name} = $highest;
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

    foreach my $kitcomp ( keys %kitcomps ) {
        (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomp}, 'kitname', 'kitreponame', 'serverroles');
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

        #TODO add checks to kit components' dependencies.

    }
    
    # Now assign each component to the osimage

    my @kitcomps;
    my $catched = 0;
    if ( $osimagetable and $osimagetable->{'kitcomponents'}) {
        @oskitcomps = split ',', $osimagetable->{'kitcomponents'};
    }
    foreach my $kitcomp ( keys %kitcomps ) {
        # Check if this component is existing in osimage.kitcomponents
        foreach my $oskitcomp ( @oskitcomps ) {
            if ( $kitcomp eq $oskitcomp ) {
                $callback->({data=>["kit component $kitcomp is already in osimage $osimage"]});
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
                        system("rmkitcomp -f -u -i $osimage $kitcomp");
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
            
    }


}

#-------------------------------------------------------

=head3 rmkitcomp

  Remove Kit component from osimage 

=cut

#-------------------------------------------------------
sub rmkitcomp
{
 
}

1;

