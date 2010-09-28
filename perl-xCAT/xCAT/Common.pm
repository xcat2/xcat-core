# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

#This contains functions common to most plugins

package xCAT::Common;

use File::stat;
use File::Copy;
use xCAT::Usage;
use Thread qw/yield/;

BEGIN
{
      $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}


# forward_data is a function used to aggregate output passed up from a set of 
# children.  This is commonly used due to make absolutely certain multiple 
# writers trying to use a common file descriptor wouldn't corrupt each other.
# So instead, each child is given a dedicated filehandle and the parent 
# uses this function to organize child data and send it up.
# locking might be a more straightforward approach, but locking experiments
# weren't as successful.
sub forward_data {
  my $callback = shift;
  my $fds = shift;
  my @ready_fds = $fds->can_read(1);
  my $rfh;
  my $rc = @ready_fds;
  foreach $rfh (@ready_fds) {
    my $data;
    if ($data = <$rfh>) {
      while ($data !~ /ENDOFFREEZE6sK4ci/) {
        $data .= <$rfh>;
      }
      eval { print $rfh "ACK\n"; }; #Ignore ack loss due to child giving up and exiting, we don't actually explicitly care about the acks
      my $responses=thaw($data);
      foreach (@$responses) {
        $callback->($_);
      }
    } else {
      $fds->remove($rfh);
      close($rfh);
    }
  }
  yield(); #Try to avoid useless iterations as much as possible
  return $rc;
}

#This function pairs with the above.
#It either accepts pre-structured responses or the common ':' delimeted description/value pairs
#for example:
#  send_data('n1',"Temperature: cold","Voltage: normal"); #report normal text, two pieces of data
#  send_data('n1',[1,"Timeout communicationg with foobar]); #Report an error with a code
#  send_data({<custom response packet>},{<other custome response>});
sub send_data {
    my $node;
    if (not ref $_[0]) {
        $node = shift;
    }
    foreach(@_) {
      my %output;
      if (ref($_) eq HASH) {
          print $out freeze([$_]);
          print $out "\nENDOFFREEZE6sK4ci\n";
          yield();
          waitforack($out);
          next;
      }
      my $line;
      my $rc;
      if (ref($_) eq ARRAY) {
          $rc = $_->[0];
          $line = $_->[1];
      } else {
          $line = $_;
      }

      
      (my $desc,my $text) = split (/:/,$line,2);
      unless ($text) {
        $text=$desc;
      } else {
        $desc =~ s/^\s+//;
        $desc =~ s/\s+$//;
        if ($desc) {
          $output{node}->[0]->{data}->[0]->{desc}->[0]=$desc;
        }
      }
      $text =~ s/^\s+//;
      $text =~ s/\s+$//;
      $output{node}->[0]->{name}->[0]=$node;
      if ($rc) {
          $output{node}->[0]->{errorcode} = $rc;
          $output{node}->[0]->{error}->[0]->{contents}->[0]=$text;
      } else {
          $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
      }
      print $out freeze([\%output]);
      print $out "\nENDOFFREEZE6sK4ci\n";
      yield();
      waitforack($out);
    }
}

#This function is intended to be used to process a request through the usage
#module.
sub usage_noderange { 
  my $request = shift;
  my $callback=shift;

  #display usage statement if -h is present or no noderage is specified
  my $noderange = $request->{node}; #Should be arrayref
  my $command = $request->{command}->[0];
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }

  my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
  if ($usage_string) {
    $callback->({data=>$usage_string});
    $request = {};
    return;
  }

  if (!$noderange) {
    $usage_string="Missing Noderange\n";
    $usage_string .=xCAT::Usage->getUsage($command);
    $callback->({error=>[$usage_string],errorcode=>[1]});
    $request = {};
    return;
  }   
}

# copy, overwriting only if the source file is newer
sub copy_if_newer {
  my ($source, $dest) = @_;

  die "ERROR: source file doesn't exist\n" unless (-e $source);

  # resolve destination path
  if ($dest =~ m/\/$/ || -d $dest) {
    $dest .= '/' if ($dest !~ m/\/$/);
    $dest .= $1 if $source =~ m/([^\/]+)$/;
  }

  if (-e $dest) {
    my $smtime = stat($source)->mtime;
    my $dmtime = stat($dest)->mtime;

    return if ($smtime < $dmtime);
  }

  copy($source, $dest);
}

1;
