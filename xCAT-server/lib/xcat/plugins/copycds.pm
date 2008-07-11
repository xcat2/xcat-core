# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::copycds;
use Storable qw(dclone);
use xCAT::Table;
use Data::Dumper;
use Getopt::Long;
use File::Basename;
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
  $identified=0;
  $::CDMOUNTPATH="/mnt/xcat";
  my $existdir = getcwd;

  @ARGV = @{$request->{arg}};
  GetOptions(
    'n|name|osver=s' => \$distname,
    'a|arch=s' => \$arch
  );
  if ($arch and $arch =~ /i.86/) {
    $arch = x86;
  }
  my @args = @ARGV; #copy ARGV
  unless ($#args >= 0) {
    $callback->({error=>"copycds needs at least one full path to ISO currently."});
    return;
  }
  foreach (@args) {
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

    my $mntopts;
    if (-r $file and -b $file) # Block device?
      { $mntopts = "-o ro"; }
    elsif (-r $file and -f $file) # Assume ISO file
      { $mntopts = "-o ro,loop"; }
    else {
      $callback->({error=>"The management server was unable to find/read $file. Ensure that file exists on the server at the specified location."});
      return;
    }

    mkdir "/mnt/xcat";

    if (system("mount $mntopts $file /mnt/xcat")) {
      $callback->({error=>"copycds was unable to mount $file to /mnt/xcat."});
      return;
    }
    my $newreq = dclone($request);
    $newreq->{command}= [ 'copycd' ]; #Note the singular, it's different
    $newreq->{arg} = ["-p","/mnt/xcat"];
    if ($distname) {
      push @{$newreq->{arg}},("-n",$distname);
    }
    if ($arch) {
      push @{$newreq->{arg}},("-a",$arch);
    }
    $doreq->($newreq,\&take_answer);
    $::CDMOUNTPATH="";

    chdir($existdir);
    while (wait() > 0) { yield; } #Make sure all children exit before trying umount
    system("umount /mnt/xcat");
    unless ($identified) {
       $callback->({error=>["copycds could not identify the ISO supplied, you may wish to try -n <osver>"],errorcode=>[1]});
    }
  }
}

1;

# vim: set ts=2 sts=2 sw=2 et ai:
