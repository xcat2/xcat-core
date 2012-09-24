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
            return addkit($request, @args, $callback);
    }elsif ($command eq "rmkit"){
            return rmkit($request, @args, $callback);
    }else{
            $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
            #return (1, "$command not found);
    }

    return;

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
        my $ec = shift;
        push@{ $rsp{data} }, "addkit: add Kits into xCAT from a list of tarball file or directory which have the same structure with tarball file";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\taddkit [-h|--help]";
        push@{ $rsp{data} }, "\taddkit [-p|--path <path>] <kitlist>] [-V]";
        if($ec){ $rsp{errorcode} = $ec; }
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

    my @kits = split /,/, $des;
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
                    $kitrepohash{$kitreponame}{kitrepodir} = $kitdir."/repos";
                } else {
                    $kitrepohash{$kitreponame}{$key} = $value;
                }
            } elsif ( $sec =~ /KITCOMPONENT$/ ) {
                if ( $key =~ /kitcompname/ ) {
                    $kitcompname = $value;
                } else {
                    $kitcomphash{$kitcompname}{$key} = $value;
                }
            }
        }

        #TODO:  add check to see the the attributes name are acceptable by xCAT DB.
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
        chmod(0755,"$kitdir/scripts/*");

        if($::VERBOSE){
            $callback->({data=>["Copying kit scripts from $kitdir/scripts/ to $installdir/postscripts\n"]});
            $rc = system("cp -rfv $kitdir/scripts/* $installdir/postscripts/");
        } else {
            $rc = system("cp -rf $kitdir/scripts/* $installdir/postscripts/");
        }

        if($rc){
            $callback->({error => ["Failed to copy scripts from $kitdir/scripts/ to $installdir/postscripts\n"],errorcode=>[1]});
        }

        # Copying plugins to /opt/xcat/lib/perl/xCAT_plugin/
        chmod(644, "$kitdir/plugins/*");

        if($::VERBOSE){
            $callback->({data=>["Copying kit plugins from $kitdir/plugins/ to $::XCATROOT/lib/perl/xCAT_plugin\n"]});
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
#    system("/etc/init.d/xcatd reload");

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
        my $ec = shift;
        push@{ $rsp{data} }, "rmkit: remove Kits from xCAT";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\trmkit [-h|--help]";
        push@{ $rsp{data} }, "\trmkit [-f|--force] <kitlist>] [-V]";
        if($ec){ $rsp{errorcode} = $ec; }
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
    my $kitnames;
    my $des = shift @ARGV;
    my @kits = split /,/, $des;
    foreach my $kit (@kits) {

        # Check if it is a kitname or basename

        my $ref1 = $tabs{kit}->getAttribs({kitname => $kit }, 'basename');
        if ( $ref1 and $ref1->{'basename'}){
            push @kitnames, $kit;
        } else {
            my @entries = $tabs{kit}->getAllAttribsWhere( "basename = '$kit'", 'kitname' );
            foreach my $entry (@entries) {
                push @kitnames, $entry->{kitname};
            }
        }
    }

    unless (@kitnames) {
        $callback->({error => ["Nothing to do since the kits $des are not existing in xCAT DB"],errorcode=>[1]});
    }

    # Remove each kit
    my @entries = $tabs{'osimage'}->getAllAttribs( 'imagename', 'kitcomponents' );

    foreach my $kitname (@kitnames) {

        # Remove osimage.kitcomponents.

        # Find all the components in this kit.
        my $kitcompnames;
        my @kitcomphash = $tabs{kitcomponent}->getAllAttribsWhere( "kitname = '$kitname'", 'kitcompname');

        if (defined(@entries) && (@entries > 0)) {  

            if($::VERBOSE){
                $callback->({data=>["Deleting kit components from osimage.kitcomponents"]});
            }
            my @newkitcomponents;
            foreach my $entry (@entries) {

                my $catched = 0;

                # Check osimage.kitcomponents
                my @kitcomponents = split /,/, $entry->{kitcomponents};
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

            # remove kit plugins from /opt/xcat/lib/perl/xCAT_plugin
            if($::VERBOSE){
                $callback->({data=>["Deleting kit plugins from $::XCATROOT/lib/perl/xCAT_plugin/"]});
            }
            my $kitdir;
            my $ref1 = $tabs{kit}->getAttribs({kitname => $kitname }, 'kitdir');
            if ( $ref1 and $ref1->{'kitdir'}){

                $kitdir = $ref1->{'kitdir'};
                chomp $kitdir;

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
            }
        }

        if($::VERBOSE){
            $callback->({data=>["Deleting kit scripts from installdir"]});
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

        if($::VERBOSE){
            $callback->({data=>["Deleting kit from xCAT DB"]});
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
#    system("/etc/init.d/xcatd reload");

}


1;

