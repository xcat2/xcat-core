# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::copycds;
use strict;
use warnings;
use Storable qw(dclone);
use xCAT::Table;
use Thread qw(yield);
use Data::Dumper;
use Getopt::Long;
use File::Basename;
use File::Spec;
use Digest::MD5 qw(md5_hex);
use Cwd;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $processed = 0;
my $callback;

sub handled_commands {
  return {
    copycds => "copycds",
  }
}
 
my $identified;
  
sub take_answer {
#TODO: Intelligently filter and decide things
  my $resp = shift;
  $callback->($resp);
  $identified=1;
}

sub process_request {
  my $request = shift;
  $callback = shift;
  my $doreq = shift;
  my $distname = undef;
  my $arch = undef;
  my $help = undef;
  my $inspection=undef;
  my $path=undef;	
  my $noosimage=undef;
  my $nonoverwrite=undef;

  $identified=0;
  $::CDMOUNTPATH="/var/run/xcat/mountpoint";
  my $existdir = getcwd;

  if ($request->{arg}) {
      @ARGV = @{$request->{arg}};
  }
  GetOptions(
    'n|name|osver=s' => \$distname,
    'a|arch=s' => \$arch,
    'h|help' => \$help,
    'i|inspection' => \$inspection,
    'p|path=s' => \$path, 
    'o|noosimage' => \$noosimage,
    'w|nonoverwrite' => \$nonoverwrite,
 );
  if ($help) {
     $callback->({info=>"copycds [{-p|--path}=path] [{-n|--name|--osver}=distroname] [{-a|--arch}=architecture] [-i|--inspection] [{-o|--noosimage}] [{-w|--nonoverwrite}] 1st.iso [2nd.iso ...]."});    
     return;
  }
  if ($arch and $arch =~ /i.86/) {
    $arch = 'x86';
  }
  my @args = @ARGV; #copy ARGV
  unless ($#args >= 0) {
	$callback->({error=>"copycds needs at least one full path to ISO currently.",errorcode=>[1]});    
	return;
  }
  my $file;
  foreach (@args) {
    $identified=0;

    unless (/^\//) { #If not an absolute path, concatenate with client specified cwd
      s/^/$request->{cwd}->[0]\//;
    }

    # /dev/cdrom is a symlink on some systems. We need to be able to determine
    # if the arg points to a block device.
    if (-l $_) { 
      my $link = readlink($_);

      # Symlinks can be relative, i.e., "../../foo"
      if ($link =~ m{^/})
        { $file = $link; }
      else
        { $file = dirname($_) . "/" . $link; } # Unix can handle "/foo/../bar"
    }
    else { $file = $_; }

    # handle the copycds for tar file
    # if the source file is tar format, call the 'copytar' command to handle it.
    # currently it's used for Xeon Phi (mic) support
    if (-r $file) {
        my @filestat = `file $file`;
        if (grep /tar archive/, @filestat) {
            # this is a tar file, call the 'copytar' to generate the image
            my $newreq = dclone($request);
            $newreq->{command}= [ 'copytar' ]; #Note the singular, it's different
            $newreq->{arg} = ["-f", $file, "-n", $distname];
            $doreq->($newreq, $callback);

            return;
        }
    }

    my $mntopts = "-t udf,iso9660"; #Prefer udf formate to iso when media supports both, like MS media
    if (-r $file and -b $file) # Block device?
      { $mntopts .= " -o ro"; }
    elsif (-r $file and -f $file) # Assume ISO file
      { $mntopts .= " -o ro,loop"; }
    else {
       $callback->({error=>"The management server was unable to find/read $file. Ensure that file exists on the server at the specified location.",errorcode=>[1]});      
       return;
    }

#let the MD5 Digest of isofullpath as the default mount point of the iso
    my $isofullpath=File::Spec->rel2abs($file);
    my $mntpath=File::Spec->catpath("" ,$::CDMOUNTPATH,md5_hex($isofullpath)); 
    
    system("mkdir -p $mntpath");
    system("umount $mntpath >/dev/null 2>&1");
     


    if (system("mount $mntopts '$file' $mntpath")) {
	eval { $callback->({error=>"copycds was unable to mount $file to $mntpath.",errorcode=>[1]}) };
	chdir("/"); 
        system("umount  $mntpath"); 
      	return;
    }
    eval {
    my $newreq = dclone($request);
    $newreq->{command}= [ 'copycd' ]; #Note the singular, it's different
    $newreq->{arg} = ["-m",$mntpath];

    if($path)
    {
        push @{$newreq->{arg}},("-p",$path);
    }

    if($inspection)
    {
      push @{$newreq->{arg}},("-i");
      $callback->({info=>"OS Image:".$_});
    }

    if ($distname) {
      if($inspection){
      $callback->({warning=>"copycds: option --inspection specified, argument specified with option --name is ignored"});
      }
      else{
        push @{$newreq->{arg}},("-n",$distname);
      }
     }
    if ($arch) {
      if($inspection){
      $callback->({warning=>"copycds: option --inspection specified, argument specified with option --arch is ignored"});
      }
      else{
      push @{$newreq->{arg}},("-a",$arch);
      }
    }

    if (! -l $file) {
        push @{$newreq->{arg}},("-f",$file);    
    }


    if ($noosimage) {
        push @{$newreq->{arg}},("-o");    
    }
     
    if ($nonoverwrite) {
        push @{$newreq->{arg}},("-w"); 
    }

    $doreq->($newreq,\&take_answer);
    #$::CDMOUNTPATH="";

    chdir($existdir);
    while (wait() > 0) { yield(); } #Make sure all children exit before trying umount
    };
    chdir("/");;
    system("umount  $mntpath");
    system("rm -rf $mntpath");
    unless ($identified) {
       $callback->({error=>["copycds could not identify the ISO supplied, you may wish to try -n <osver>"],errorcode=>[1]});
    }
  }
}

1;

# vim: set ts=2 sts=2 sw=2 et ai:
