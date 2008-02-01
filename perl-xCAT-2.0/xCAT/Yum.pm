package xCAT::Yum;
use DBI;
use File::Find;
sub localize_yumrepo {
   my $self = shift;
   my $installroot = shift;
   my $distname = shift;
   my $arch = shift;
   my $dosqlite = 0;
  my $repomdfile;
  my $primaryxml;
  my @xmlines;
  my $dirlocation = "$installroot/$distname/$arch/";
  find(\&check_tofix,$dirlocation);
}
sub check_tofix {
   if (-d $File::Find::name and $File::Find::name =~ /\/repodata$/) {
      fix_directory($File::Find::name);
   }
}
sub fix_directory { 
  my $dirlocation = shift;
  my $oldsha=`/usr/bin/sha1sum $dirlocation/primary.xml.gz`;
  my $olddbsha; 
  $oldsha =~ s/\s.*//;
  chomp($oldsha);
  unlink("$dirlocation/primary.xml");
  system("/bin/gunzip  $dirlocation/primary.xml.gz");
  my $oldopensha=`/usr/bin/sha1sum $dirlocation/primary.xml`;
  $oldopensha =~ s/\s+.*//;
  chomp($oldopensha);
  open($primaryxml,"+<$dirlocation/primary.xml");
  while (<$primaryxml>) {
     s!xml:base="media://[^"]*"!!g;
     push @xmlines,$_;
  }
  seek($primaryxml,0,0);
  print $primaryxml (@xmlines);
  truncate($primaryxml,tell($primaryxml));
  @xmlines=();
  close($primaryxml);
  my $newopensha=`/usr/bin/sha1sum $dirlocation/primary.xml`;
  system("/bin/gzip $dirlocation/primary.xml");
  my $newsha=`/usr/bin/sha1sum $dirlocation/primary.xml.gz`;
  $newopensha =~ s/\s.*//;
  $newsha =~ s/\s.*//;
  chomp($newopensha);
  chomp($newsha);
  my  $newdbsha;
  my $newdbopensha;
  my $olddbopensha;
  if (-r "$dirlocation/primary.sqlite.bz2") { 
   $olddbsha =`/usr/bin/sha1sum $dirlocation/primary.sqlite.bz2`;
   $olddbsha =~ s/\s.*//;
   chomp($olddbsha);
   unlink("$dirlocation/primary.sqlite");
   system("/usr/bin/bunzip2  $dirlocation/primary.sqlite.bz2");
   $olddbopensha=`/usr/bin/sha1sum $dirlocation/primary.sqlite`;
   $olddbopensha =~ s/\s+.*//;
   chomp($olddbopensha);
   my $pdbh = DBI->connect("dbi:SQLite:$dirlocation/primary.sqlite","","",{AutoCommit=>1});
   $pdbh->do('UPDATE "packages" SET "location_base" = NULL');
   $pdbh->disconnect;
   $newdbopensha=`/usr/bin/sha1sum $dirlocation/primary.sqlite`;
   system("/usr/bin/bzip2 $dirlocation/primary.sqlite");
   $newdbsha=`/usr/bin/sha1sum $dirlocation/primary.sqlite.bz2`;
   $newdbopensha =~ s/\s.*//;
   $newdbsha =~ s/\s.*//;
   chomp($newdbopensha);
   chomp($newdbsha);
  }
  open($primaryxml,"+<$dirlocation/repomd.xml");
  while (<$primaryxml>) { 
     s!xml:base="media://[^"]*"!!g;
     s!$oldsha!$newsha!g;
      s!$oldopensha!$newopensha!g;
      if ($olddbsha) { s!$olddbsha!$newdbsha!g; }
      if ($olddbsha) { s!$olddbopensha!$newdbopensha!g; }
      push @xmlines,$_;
  }
  seek($primaryxml,0,0);
  print $primaryxml (@xmlines);
  truncate($primaryxml,tell($primaryxml));
  close($primaryxml);
}


1;
