# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#TODO: delete entries not being refreshed if no noderange
package xCAT_plugin::conserver;
use xCAT::Table;
use strict;
use Data::Dumper;
my @cservers = qw(mrv cyclades);
my %termservers; #list of noted termservers

sub handled_commands {
  return {
    makeconservercf => "conserver"
  }
}

sub process_request {
  my $req = shift;
  my $cb = shift;
  if ($req->{command}->[0] eq "makeconservercf") {
    makeconservercf($req,$cb);
  }
}

sub docfheaders {
# Put in standard headers common to all conserver.cf files
  my $content = shift;
  my $numlines = @$content;
  my @meat = grep(!/^#/,@$content);
  unless (grep(/^config \* {/,@meat)) {
    push @$content,"config * {\n";
    push @$content,"  sslrequired yes;\n";
    push @$content,"  sslauthority /etc/xcat/ca/ca-cert.pem;\n";
    push @$content,"  sslcredentials /etc/xcat/cert/server-cred.pem;\n";
    push @$content,"}\n";
  }
  unless (grep(/^default full/,@meat)) {
    push @$content,"default full { rw *; }\n";
  }
  unless (grep(/^default cyclades/,@meat)) {
    push @$content,"default cyclades { type host; portbase 7000; portinc 1; }\n"
  }
  unless (grep(/^default mrv/,@meat)) {
    push @$content,"default mrv { type host; portbase 2000; portinc 100; }\n"
  }
  unless (grep(/^access \*/,@meat)) {
#TODO: something intelligent, allowing other hosts in
    #push @$content,"#xCAT BEGIN ACCESS\n";
    push @$content,"access * {\n";
    push @$content,"  trusted 127.0.0.1;\n";
    push @$content,"}\n";
    #push @$content,"#xCAT END ACCESS\n";
  }
  unless (grep(/^default \*/,@meat)) {
    push @$content,"default * {\n";
    push @$content,"  logfile /var/log/consoles/&;\n";
    push @$content,"  timestamp 1hab;\n";
    push @$content,"  include full;\n";
    push @$content,"  master localhost;\n";
    push @$content,"}\n";
  }


}
sub makeconservercf {
  my $req = shift;
  %termservers = (); #clear hash of existing entries
  my $cb = shift;
  my $nodes = $req->{node};
  my $cfile;
  my @filecontent;
  open $cfile,'/etc/conserver.cf';
  while (<$cfile>) {
    push @filecontent,$_;
  }
  close $cfile;
  docfheaders(\@filecontent);
  my $hmtab = xCAT::Table->new('nodehm');
  my @cfgents = $hmtab->getAllNodeAttribs(['mgt','cons']);
#cfgents should now have all the nodes, so we can fill in our hashes one at a time.
  foreach (@cfgents) {
    unless ($_->{cons}) {$_->{cons} = $_->{mgt};} #populate with fallback
    my $cmeth=$_->{cons};
    if (grep(/^$cmeth$/,@cservers)) { #terminal server, more attribs needed
      my $node = $_->{node};
      my $tent = $hmtab->getNodeAttribs($node,["termserver","termport"]);
      $_->{termserver} = $tent->{termserver};
      $termservers{$tent->{termserver}} = 1;
      $_->{termport}= $tent->{termport};
    }
  }
  if (($nodes and @$nodes > 0) or $req->{noderange}->[0]) {
    foreach (@$nodes) {
      my $node = $_;
      foreach (@cfgents) {
        if ($_->{node} eq $node) {
          if ($_->{termserver} and $termservers{$_->{termserver}}) {
            dotsent($_,\@filecontent);
            delete $termservers{$_->{termserver}}; #prevent needless cycles being burned
          }
          donodeent($_,\@filecontent);
        }
      }
    }
  } else { #no nodes specified, do em all up
    zapcfg(\@filecontent); # strip all xCAT configured stuff from config
    
    # filter out node types without console support
    my $typetab = xCAT::Table->new('nodetype');
    my %type;

    if ( defined($typetab)) {
      my @ents = $typetab->getAllNodeAttribs([qw(node nodetype)]);
      foreach (@ents) {
        $type{$_->{node}}=$_->{nodetype};
      }
    }
    foreach (@cfgents) {
      if ($_->{termserver} and $termservers{$_->{termserver}}) {
        dotsent($_,\@filecontent);
        delete $termservers{$_->{termserver}}; #prevent needless cycles being burned
      }
      if ( $type{$_->{node}} !~ /fsp|bpa|hmc|ivm/ ) {
        donodeent($_,\@filecontent);
      }
    }
  }
  open $cfile,'>','/etc/conserver.cf';
  foreach (@filecontent) {
    print $cfile $_;
  }
  close $cfile;
}

sub dotsent {
  my $cfgent = shift;
  my $tserv = $cfgent->{termserver};
  my $content = shift;
  my $idx = 0;
  my $toidx = -1;
  my $skip = 0;
  my $skipnext = 0;
  while ($idx < $#$content) { # Go through and delete that which would match my entry
    if ($content->[$idx] =~ /^#xCAT BEGIN $tserv TS/) {
      $toidx=$idx; #TODO put it back right where I found it
      $skip = 1;
      $skipnext=1;
    } elsif ($content->[$idx] =~ /^#xCAT END $tserv TS/) {
      $skipnext = 0;
    }
    if ($skip) {
      splice (@$content,$idx,1);
    } else {
      $idx++;
    }
    $skip = $skipnext;
  }
  push @$content,"#xCAT BEGIN $tserv TS\n";
  push @$content,"default $tserv {\n";
  push @$content,"  include ".$cfgent->{cons}.";\n";
  push @$content,"  host $tserv;\n";
  push @$content,"}\n";
  push @$content,"#xCAT END $tserv TS\n";
}
sub donodeent {
  my $cfgent = shift;
  my $node = $cfgent->{node};
  my $content = shift;
  my $idx=0;
  my $toidx=-1;
  my $skip = 0;
  my $skipnext = 0;
  while ($idx < $#$content) { # Go through and delete that which would match my entry
    if ($content->[$idx] =~ /^#xCAT BEGIN $node CONS/) {
      $toidx=$idx; #TODO put it back right where I found it
      $skip = 1;
      $skipnext=1;
    } elsif ($content->[$idx] =~ /^#xCAT END $node CONS/) {
      $skipnext = 0;
    }
    if ($skip) {
      splice (@$content,$idx,1);
    } else {
      $idx++;
    }
    $skip = $skipnext;
  }
  push @$content,"#xCAT BEGIN $node CONS\n";
  push @$content,"console $node {\n";
  #if ($cfgent->{cons} 
  my $cmeth=$cfgent->{cons};
  print $cmeth."\n";
  if (grep(/^$cmeth$/,@cservers)) { 
    push @$content," include ".$cfgent->{termserver}.";\n";
    push @$content," port ".$cfgent->{termport}.";\n";
  } else { #a script method...
    push @$content,"  type exec;\n";
    push @$content,"  exec ".$::XCATROOT."/share/xcat/cons/".$cmeth." ".$node.";\n"
  }
  push @$content,"}\n";
  push @$content,"#xCAT END $node CONS\n";
}

sub zapcfg {
  my $content = shift;
  my $idx=0;
  my $toidx=-1;
  my $skip = 0;
  my $skipnext = 0;
  while ($idx <= $#$content) { # Go through and delete that which would match my entry
    if ($content->[$idx] =~ /^#xCAT BEGIN/) {
      $toidx=$idx; #TODO put it back right where I found it
      $skip = 1;
      $skipnext=1;
    } elsif ($content->[$idx] =~ /^#xCAT END/) {
      $skipnext = 0;
    }
    if ($skip) {
      splice (@$content,$idx,1);
    } else {
      $idx++;
    }
    $skip = $skipnext;
  }
}

1;
