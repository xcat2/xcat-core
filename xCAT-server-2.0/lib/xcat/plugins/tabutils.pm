# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle various commands that work with the 
#     xCAT tables
#
#   Supported commands:
#         nodeadd
#         nodels
#         nodech
#         tabdump
#         tabrestore
#         noderm
#   To be implemented:
#         gettab
#         chtab
#         tabls
#         getnodecfg (?? this doesn't seem much different from gettab)
#         nr
#   These were xCAT 1.2 commands.  Are they still useful in xCAT 1.3?
#         addattr
#         delattr
#         chtype
#
#####################################################
package xCAT_plugin::tabutils;
use xCAT::Table;
use xCAT::Schema;
use Data::Dumper;
use xCAT::NodeRange;
use xCAT::Schema; #noderm will need to build list of tables..
#use Getopt::Long qw(GetOptionsFromArray);

1;

#some quick aliases to table/value
my %shortnames = (
  groups => [qw(nodelist groups)],
  tags => [qw(nodelist groups)],
  mgt => [qw(nodehm mgt)],
  switch => [qw(switch switch)],
);

#####################################################
# Return list of commands handled by this plugin
#####################################################
sub handled_commands {
  return {
    gettab => "tabutils",
    tabdump => "tabutils",
    tabrestore => "tabutils",
    tabch => "tabutils",
    nodech => "tabutils",
    nodeadd => "tabutils",
    noderm => "tabutils",
    tabls => "tabutils",
    nodels => "tabutils",
    getnodecfg => "tabutils",
    addattr => "tabutils",
    delattr => "tabutils",
    chtype => "tabutils",
    nr => "tabutils",
    tabgrep => "tabutils"
  }
}

my %usage = (
    nodech => "Usage: nodech <noderange> [table.column=value] [table.column=value] ...",
    nodeadd => "Usage: nodeadd <noderange> [table.column=value] [table.column=value] ...",
    noderm => "Usage: noderm <noderange>",
    tabdump => "Usage: tabdump <tablename>\n   where <tablename> is one of the following:\n     ".join("\n     ",keys %xCAT::Schema::tabspec),
    tabrestore => "Usage: tabrestore <tablename>.csv",
);

#####################################################
# Process the command
#####################################################
sub gettab {
    my $req = shift;
    my $callback = shift;
    my $keyspec = shift @{$req->{arg}};
    my @keypairs = split /,/,$keyspec;
    my %keyhash;
    foreach (@keypairs) {
        (my $key, my $value) = split /=/,$_;
        $keyhash{$key}=$value;
    }
    my %tabhash;
    foreach my $tabvalue (@{$req->{arg}}) {
        (my $table,my $column) = split /\./,$tabvalue;
        $tabhash{$table}->{$column} = 1;
    }
    foreach my $tabn (keys %tabhash) {
        my $tab = xCAT::Table->new($tabn);
        (my $ent) = $tab->getAttribs(\%keyhash,keys %{$tabhash{$tabn}});
        foreach my $coln (keys %{$tabhash{$tabn}}) {
            $callback->({data=>["$tabn.$coln:".$ent->{$coln}]});
        }
        $tab->close;
    }
}

sub process_request {
  use Getopt::Long;
  Getopt::Long::Configure("bundling");
  Getopt::Long::Configure("pass_through");
  
  my $request = shift;
  my $callback = shift;
  my $nodes = $request->{node};
  my $command = $request->{command}->[0];
  my $args = $request->{arg};
  unless ($args or $nodes or $request->{data}) {
      if ($usage{$command}) {
          $callback->({data=>[$usage{$command}]});
          return;
      }
  }

  if ($command eq "nodels") {
    return nodels($nodes,$args,$callback,$request->{noderange}->[0]);
  } elsif ($command eq "noderm" or $command eq "rmnode") {
    return noderm($nodes,$args,$callback);
  } elsif ($command eq "nodeadd" or $command eq "addnode") {
    return chnode($nodes,$args,$callback,1);
  } elsif ($command eq "nodech" or $command eq "chnode") {
    return chnode($nodes,$args,$callback,0);
  } elsif ($command eq "tabrestore") {
    return tabrestore($request,$callback);
  } elsif ($command eq "tabdump") {
    return tabdump($args,$callback);
  } elsif ($command eq "gettab") {
      return gettab($request,$callback);
  } elsif ($command eq "tabgrep") {
      return tabgrep($nodes,$callback);
  } else {
    print "$command not implemented yet\n";
    return (1,"$command not written yet");
  }

}


sub noderm {
  my $nodes = shift;
  my $args = shift;
  my $cb = shift;
  my @tablist = ("-d");
  foreach (keys %{xCAT::Schema::tabspec}) {
    if (grep /^node$/,@{$xCAT::Schema::tabspec{$_}->{cols}}) {
      push @tablist,$_; 
    }
  }
  chnode($nodes,\@tablist,$cb,0);
}
sub tabrestore {
#request->{data} is an array of CSV formatted lines
  my $request = shift;
  my $cb = shift;
  my $table = $request->{table}->[0];
  my $linenumber = 1;
  my $tab = xCAT::Table->new($table,-create =>1,-autocommit=>0);
  unless ($tab) {
    $cb->({error=>"Unable to open $table"});
    return;
  }
  $tab->delEntries(); #Yes, delete *all* entries
  my $header = shift @{$request->{data}};
  $header =~ s/"//g; #Strip " from overzealous CSV apps
  $header =~ s/^#//;
  $header =~ s/\s+$//;
  my @colns = split(/,/,$header);
  my $line;
  my $rollback=0;
  LINE: foreach $line (@{$request->{data}}) {
    $linenumber++;
    $line =~ s/\s+$//;
    my $origline = $line; #save for error reporting
    my %record;
    my $col;
    foreach $col (@colns) {
      if ($line =~ /^,/ or $line eq "") { #Match empty, or end of line that is empty
        #TODO: should we detect when there weren't enough CSV fields on a line to match colums? 
        $record{$col}=undef;
        $line =~ s/^,//;
      } elsif ($line =~ /^[^,]*"/) { # We have stuff in quotes... pain...
        #I don't know what I'm doing, so I'll do it a hard way....
        if ($line !~ /^"/) {
          $rollback = 1;
          $cb->({error=>"CSV missing opening \" for record with \" characters on line $linenumber, character ".index($origline,$line).": $origline"});
          next LINE;
        }
        my $offset=1;
        my $nextchar;
        my $ent;
        while (not defined $ent) {
          $offset = index($line,'"',$offset);
          $offset++;
          if ($offset <=0) {
            #MALFORMED CSV, request rollback, report an error
            $rollback=1;
            $cb->({error=>"CSV unmatched \" in record on line $linenumber, character ".index($origline,$line).": $origline"});
            next LINE;
          }
          $nextchar = substr($line,$offset,1);
          if ($nextchar eq '"') {
            $offset++;
          } elsif ($offset eq length($line) or $nextchar eq ',') {
            $ent = substr($line,0,$offset,'');
            $line =~ s/^,//;
            chop $ent;
            $ent = substr($ent,1);
            $ent =~ s/""/"/g;
            $record{$col}=$ent;
          } else {
            $cb->({error=>"CSV unescaped \" in record on line $linenumber, character ".index($origline,$line).": $origline"});
            $rollback=1;
            next LINE;
          }
        }
      } elsif ($line =~ /^([^,]+)/) { #easiest case, no Text::Balanced needed..
        $record{$col} = $1;
        $line =~ s/^([^,]+)(,|$)//;
      }
    }
    if ($line) {
      $rollback = 1;
      $cb->({error=>"Too many fields on line $linenumber: $origline | $line"});
      next LINE;
    }
    #TODO: check for error from DB and rollback
    my @rc =$tab->setAttribs(\%record,\%record);
    if (not defined($rc[0])) {
      $rollback = 1;
      $cb->({error=>"DB error ".$rc[1]. " with line $linenumber: ".$origline});
    }
  }
  if ($rollback) {
    $tab->rollback();
    $tab->close;
    undef $tab;
    return;
  } else {
    $tab->commit; #Made it all the way here, commit
  }
}
sub tabdump {
#TODO: need to return header for not-yet existing, but schemad tabs
#TODO: schema defined column order.
  my $args = shift;
  my $cb = shift;
  my $table="";
  foreach (@$args) {
    unless (/^-/) {
      if ($table) {
        return 1; #TODO: Error, usage
      }
      $table=$_;
    }
  }
  my $tabh = xCAT::Table->new($table);
  my %rsp;
  unless ($tabh) {
    if (defined($xCAT::Schema::tabspec{$table})) {
      my $header = join ",",@{$xCAT::Schema::tabspec{$table}->{cols}};
      $header="#".$header;
      push @{$rsp{data}},$header;
      $cb->(\%rsp);
      return;
    }
    $cb->({error=>"No such table: $table"});
    return 1;
  }
  my $recs=$tabh->getAllEntries();
  my $rec;
  my $firstline = 1;
  unless (@$recs) {
    if (defined($xCAT::Schema::tabspec{$table})) {
      my $header = join ",",@{$xCAT::Schema::tabspec{$table}->{cols}};
      $header="#".$header;
      push @{$rsp{data}},$header;
      $cb->(\%rsp);
      return;
    }
  }

  foreach $rec (@$recs) {
    my $line ='';
    if ($firstline) {
      $firstline = 0;
      $line = join ",",@{$tabh->{colnames}};
      $line =  "#".$line;
      push @{$rsp{data}},$line;
      $line = '';
    }
    foreach (@{$tabh->{colnames}}) {
      $rec->{$_} =~ s/"/""/g;
      if (defined $rec->{$_}) {
        $line = $line . '"' . $rec->{$_} . '",';
      } else {
        $line .= ',';
      }
    }
    $line =~ s/,$//;
    $line = $line . $lineappend;
    push @{$rsp{data}},$line;
  }
  $cb->(\%rsp);
}



sub chnode {
  my $nodes=shift;
  my $args=shift;
  my $callback=shift;
  my $addmode=shift;
  print $addmode;
  if ($addmode) {
    my $idx=0;
    foreach my $arg (@$args) {
      unless ($arg =~ /^-/) {
        $nodes = [noderange($arg,0)];
        splice(@$args,$idx,1);
        last;
      }
      $idx++;
    }
    unless ($nodes) {
      $callback->({error=>"No range to add detected\n"});
      return;
    }
  }
  my $column;
  my $value;
  my $temp;
  my %tables;
  my $tab;
  my $deletemode;

  #No GetOptionsFromArray... 
  #GetOptionsFromArray($args,"d|delete" => \$deletemode);
  #print Dumper($deletemode);
  foreach (@$args) {
    if (m/^-/) {  #A quick and dirty option parser in lieu of lacking Getoptinos
      if (m/^--/) {
        if (m/--delete/) {
          $deletemode=1;
          next;
        } else {
          $callback->({data=>["ERROR: Malformed argument $_ ignored"]});
          next;
        }
      } else {
        if (m/^-d$/) {
          $deletemode=1;
          next;
        } else {
          $callback->({data=>["ERROR: Malformed argument $_ ignored"]});
          next;
        }
      }
    }

    if ($deletemode) {
      if (m/[=\.]/) {
        $callback->({data=>["ERROR: . and = not valid in delete mode"]});
        next;
      }
      $tables{$_} = 1;
      next;
    }
    unless (m/=/) {
      $callback->({data=>["ERROR: Malformed argument $_ ignored"]});
      next;
    }
    ($temp,$value)=split('=',$_,2);
    my $op='=';
    if ($temp =~ /,$/) {
      $op=',=';
      chop($temp);
    } elsif ($temp =~ /\^$/) {
      $op='^=';
      chop($temp);
    }

    if ($shortnames{$temp}) {
      ($table,$column) = @{$shortnames{$temp}};
    } else {
      ($table,$column) = split('\.',$temp,2);
    }
    $tables{$table}->{$column}=[$value,$op];
  }
  foreach $tab (keys %tables) {
    my $tabhdl = xCAT::Table->new($tab,-create => 1,-autocommit => 0);
    if ($tabhdl) {
      foreach (@$nodes) {
        if ($deletemode) {
          $tabhdl->delEntries({'node'=>$_});
        } else {
          #$tabhdl->setNodeAttribs($_,$tables{$tab});
          my %uhsh;
          my $node = $_;
          foreach (keys %{$tables{$tab}}) {
            my $op = $tables{$tab}->{$_}->[1];
            my $val =  $tables{$tab}->{$_}->[0];
            my $key = $_;
            if ($op eq '=') {
              $uhsh{$key}=$val;
            } elsif ($op eq ',=') { #splice assignment
              my $cent = $tabhdl->getNodeAttribs($node,[$key]);
              my $curval;
              if ($cent) { $curval = $cent->{$key}; }
              if ($curval) { 
                my @vals = split(/,/,$curval);
                unless (grep /^$val$/,@vals) {
                  @vals=(@vals,$val);
                  my $newval = join(',',@vals);
                  $uhsh{$key}=$newval;
                }
              } else {
                $uhsh{$key}=$val;
              }
            } elsif ($op eq '^=') {
              my $cent = $tabhdl->getNodeAttribs($node,[$key]);
              my $curval;
              if ($cent) { $curval = $cent->{$key}; }
              if ($curval) { 
                my @vals = split(/,/,$curval);
                if (grep /^$val$/,@vals) { #only bother if there
                  @vals = grep(!/^$val$/,@vals);
                  my $newval = join(',',@vals);
                  $uhsh{$key}=$newval;
                }
              } #else, what they asked for is the case alredy


            }
          }
          if (keys %uhsh) {
            $tabhdl->setNodeAttribs($node,\%uhsh);
          }
        }
      }
      $tabhdl->commit;
    } else {
      $callback->({data=>["ERROR: Unable to open table $tab in configuration"]});
    }
  }
}

sub tabgrep {
  my $node=shift;
  my @tablist;
  my $callback=shift;

  foreach (keys %{xCAT::Schema::tabspec}) {
    if (grep /^node$/,@{$xCAT::Schema::tabspec{$_}->{cols}}) {
      push @tablist,$_; 
    }
  }
  foreach (@tablist) {
    my $tab=xCAT::Table->new($_);
    if ($tab->getNodeAttribs($node->[0],["node"])) {
			$callback->({data=>[$_]});
		}
	}
}

    

#####################################################
#  nodels command
#####################################################
sub nodels {
  my $nodes=shift;
  my $args=shift;
  my $callback=shift;
  my $noderange=shift;

  my $VERSION;
  my $HELP;

  sub nodels_usage {
     my %rsp;
     $rsp->{data}->[0]= "Usage:";
     $rsp->{data}->[1]= "  nodels [-?|-h|--help] ";
     $rsp->{data}->[2]= "  nodels [-v|--version] ";
     $rsp->{data}->[3]= "  nodels [noderange] ";
#####  xcat 1.2 nodels usage: 
#     $rsp->{data}->[1]= "  nodels [noderange] [group|pos|type|rg|install|hm|all]";
#     $rsp->{data}->[2]= " ";
#     $rsp->{data}->[3]= "  nodels [noderange] hm.{power|reset|cad|vitals|inv|cons}"; 
#     $rsp->{data}->[4]= "                     hm.{bioscons|eventlogs|getmacs|netboot}";
#     $rsp->{data}->[5]= "                     hm.{eth0|gcons|serialbios|beacon}";
#     $rsp->{data}->[6]= "                     hm.{bootseq|serialbps|all}";
#     $rsp->{data}->[7]= " ";
#     $rsp->{data}->[8]= "  nodels [noderange] rg.{tftp|nfs_install|install_dir|serial}";
#     $rsp->{data}->[9]= "                     rg.{usenis|install_roll|acct|gm|pbs}";
#     $rsp->{data}->[10]="                     rg.{access|gpfs|netdevice|prinic|all}";
     $callback->($rsp);
  }

  @ARGV=@{$args};
  if ( !GetOptions(
                    'h|?|help'   => \$HELP,
                    'v|version'  => \$VERSION,
                   ) ) {
        &nodels_usage;
  }

  # Help
  if ($HELP) { 
     &nodels_usage; 
     return; 
  }

  # Version
  if ($VERSION) { 
    my %rsp;
    $rsp->{data}->[0]= "1.3";
    $callback->($rsp);
    return;
  }

  # TODO -- Parse command arguments
#  my $opt;
#  my %attrs;
#  foreach $opt (@ARGV) {
#     if ($opt =~ /^group/) { 
#     }
#  }
  my $argc = @ARGV;


  if (@$nodes > 0 or $noderange) { #Make sure that there are zero nodes *and* that a noderange wasn't requested
  # TODO - gather data for each node
  #        for now just return the flattened list of nodes)
     my %rsp; #build up fewer requests, be less chatty
     if ($argc) {
       my %tables;
       foreach (@ARGV) {
         my $table;
         my $column;
         my $temp=$_;
         if ($shortnames{$temp}) {
           ($table,$column) = @{$shortnames{$temp}};
         } else {
           ($table,$column) = split('\.',$temp,2);
         }
         unless (grep /^$column$/,@{$tables{$table}}) {
          push @{$tables{$table}},[$column,$temp]; #Mark this as something to get
         }
       }
       my $tab;
       my %noderecs;
       foreach $tab (keys %tables) {
         my $tabh = xCAT::Table->new($tab);
         unless ($tabh) { next; }
         #print Dumper($tables{$tab});
         my $node;
         foreach $node (@$nodes) {
           my @cols;
           my %labels;
           foreach (@{$tables{$tab}}) {
             push @cols,$_->[0];
             $labels{$_->[0]}=$_->[1];
           }
           my $rec=$tabh->getNodeAttribs($node,\@cols);
           foreach (keys %$rec) {
             my %datseg;
             $datseg{data}->[0]->{desc} = [$labels{$_}];
             $datseg{data}->[0]->{contents} = [$rec->{$_}];
             $datseg{name} = [$node]; #{}->{contents} = [$rec->{$_}];
             push @{$noderecs{$node}},\%datseg;
           }
         }
         #$rsp->{node}->[0]->{data}->[0]->{desc}->[0] = $_;
         #$rsp->{node}->[0]->{data}->[0]->{contents}->[0] = $_;
         $tabh->close();
         undef $tabh;
       }
       foreach (sort (keys %noderecs)) {
         push @{$rsp->{"node"}},@{$noderecs{$_}};
       }
    } else { 
      foreach (@$nodes) {
        my $noderec;
        $noderec->{name}->[0]=($_);
        push @{$rsp->{node}},$noderec;
      }
    }
    $callback->($rsp);
  } else {
  # no noderange specified on command line, return list of all nodes
     my $nodelisttab;
     if ($nodelisttab=xCAT::Table->new("nodelist")) {
        my @attribs=("node");
        my @ents=$nodelisttab->getAllAttribs(@attribs);
        foreach (@ents) {
           my %rsp;
           if ($_->{node}) {
              $rsp->{node}->[0]->{name}->[0]=($_->{node});
#              $rsp->{node}->[0]->{data}->[0]->{contents}->[0]="$_->{node} node contents";
#              $rsp->{node}->[0]->{data}->[0]->{desc}->[0]="$_->{node} node desc";
              $callback->($rsp);
           }
        }
     }
  }

  return 0;
}
