package xCAT::Yum;
use DBI;
use File::Find;
use File::Spec;
use File::Path;

my $yumrepofile;
my $distname;
my $arch;
my $installpfx;

my $distrepopfx="/install/postscripts/repos";

sub localize_yumrepo {
    my $self        = shift;
    my $pkgdir = shift;
    $distname=shift;
    $arch=shift;
    
    mkpath("$distrepopfx/$pkgdir");
    open($yumrepofile, ">", "$distrepopfx/$pkgdir/local-repository.tmpl");
    my %options = (
        wanted      => \&check_tofix,
        follow_fast => 1
    );
    find(\%options, $pkgdir);
    close($yumrepofile);
}


sub remove_yumrepo {
    my $self        = shift;
    my $pkgdir = shift;
    rmtree("$distrepopfx/$pkgdir/local-repository.tmpl");
}

sub check_tofix {
    if (-d $File::Find::name and $File::Find::name =~ /\/repodata$/) {
        if ($distname =~ /rhels5/)
        {
            fix_directory($File::Find::name);
        }
        generate_repo($File::Find::name);
    }
    elsif ($File::Find::name =~ /\/RPM-GPG-KEY/) {
        qx(rpm --import $File::Find::name);
    }
}


sub generate_repo
{
    #write local-repository.tmpl
    my $dirlocation = shift;
    my @dircomps    = File::Spec->splitdir($dirlocation);
    pop(@dircomps);
    my $reponame = join("-",@dircomps);
    my $yumurl = File::Spec->catdir(@dircomps);

    print $yumrepofile "[local-$distname-$arch-$reponame]\n";
    print $yumrepofile "name=xCAT configured yum repository for $yumurl\n";
    print $yumrepofile "baseurl=$yumurl\n";
    print $yumrepofile "enabled=1\n";
    print $yumrepofile "gpgcheck=0\n\n";
}	

sub fix_directory {

    my @xmlines = ();
    my $primaryxml;

    $grep_result = system("grep sha256 $dirlocation/repomd.xml|grep \\<checksum");
    if ($grep_result == 0)
    {
        $sha_command = "sha256sum";
    }
    else
    {
        $sha_command = "sha1sum";
    }

    #-----------------------------------------------------------------------
    my $oldsha;
    my $newsha;
    my $oldopensha;
    my $newopensha;

    if (-r "$dirlocation/primary.xml.gz")
    {
        $oldsha = `/usr/bin/$sha_command $dirlocation/primary.xml.gz`;
        $oldsha =~ s/\s.*//;
        chomp($oldsha);

        #update primary.xml.gz & primary.xml
        if (-r "$dirlocation/primary.xml")
        {
            unlink("$dirlocation/primary.xml");
        }
        system("/bin/gunzip  $dirlocation/primary.xml.gz");

        $oldopensha = `/usr/bin/$sha_command $dirlocation/primary.xml`;
        $oldopensha =~ s/\s+.*//;
        chomp($oldopensha);

        open($primaryxml, "+<$dirlocation/primary.xml");
        while (<$primaryxml>) {
            s!xml:base="media://[^"]*"!!g;
            push @xmlines, $_;
        }
        seek($primaryxml, 0, 0);
        print $primaryxml (@xmlines);
        truncate($primaryxml, tell($primaryxml));
        @xmlines = ();
        close($primaryxml);

        $newopensha = `/usr/bin/$sha_command $dirlocation/primary.xml`;
        $newopensha =~ s/\s.*//;
        chomp($newopensha);

        system("/bin/gzip $dirlocation/primary.xml");
        $newsha = `/usr/bin/$sha_command $dirlocation/primary.xml.gz`;
        $newsha =~ s/\s.*//;
        chomp($newsha);
    }

    #-----------------------------------------------------------------------

    my $newdbsha;
    my $olddbsha;
    my $newdbopensha;
    my $olddbopensha;

    if (-r "$dirlocation/primary.sqlite.bz2") {

        $olddbsha = `/usr/bin/$sha_command $dirlocation/primary.sqlite.bz2`;
        $olddbsha =~ s/\s.*//;
        chomp($olddbsha);

        #update primary.sqlite.bz2 & primary.sqlite
        if (-r "$dirlocation/primary.sqlite")
        {
            unlink("$dirlocation/primary.sqlite");
        }

        system("/usr/bin/bunzip2  $dirlocation/primary.sqlite.bz2");
        $olddbopensha = `/usr/bin/$sha_command $dirlocation/primary.sqlite`;
        $olddbopensha =~ s/\s+.*//;
        chomp($olddbopensha);

        my $pdbh = DBI->connect("dbi:SQLite:$dirlocation/primary.sqlite", "", "", { AutoCommit => 1 });
        $pdbh->do('UPDATE "packages" SET "location_base" = NULL');
        $pdbh->disconnect;
        $newdbopensha = `/usr/bin/$sha_command $dirlocation/primary.sqlite`;
        $newdbopensha =~ s/\s.*//;
        chomp($newdbopensha);

        system("/usr/bin/bzip2 $dirlocation/primary.sqlite");
        $newdbsha = `/usr/bin/$sha_command $dirlocation/primary.sqlite.bz2`;
        $newdbsha =~ s/\s.*//;
        chomp($newdbsha);
    }

    #-----------------------------------------------------------------------

    #update repomd.xml
    open($primaryxml, "+<$dirlocation/repomd.xml");
    while (<$primaryxml>) {
        if ($_ =~ m/\<size\>/)
        {
            next;
        }
        if ($_ =~ m/\<open-size\>/)
        {
            next;
        }
        s!xml:base="media://[^"]*"!!g;
        if (defined($oldsha)) {
            s!$oldsha!$newsha!g;
        }
        if (defined($oldopensha)) {
            s!$oldopensha!$newopensha!g;
        }
        if (defined($olddbsha)) {
            s!$olddbsha!$newdbsha!g;
        }
        if (defined($olddbopensha)) {
            s!$olddbopensha!$newdbopensha!g;
        }
        push @xmlines, $_;
    }
    seek($primaryxml, 0, 0);
    print $primaryxml (@xmlines);
    truncate($primaryxml, tell($primaryxml));
    close($primaryxml);
    @xmlines = ();
}


1;
