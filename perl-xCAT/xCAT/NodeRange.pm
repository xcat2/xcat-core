# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::NodeRange;
require xCAT::Table;
require Exporter;
use strict;

#Perl implementation of noderange
our @ISA = qw(Exporter);
our @EXPORT = qw(noderange nodesmissed);
our @EXPORT_OK = qw(extnoderange abbreviate_noderange);

my $missingnodes=[];
my $nodelist; #=xCAT::Table->new('nodelist',-create =>1);
#my $nodeprefix = "node";
my @allnodeset;
my $retaincache=0;
my $recurselevel=0;


sub subnodes (\@@) {
    #Subtract set of nodes from the first list
    my $nodes = shift;
    my $node;
    foreach $node (@_) {
        @$nodes = (grep(!/^$node$/,@$nodes));
    }
}
sub nodesmissed {
  return @$missingnodes;
}

sub expandatom {
	my $atom = shift;
	my $verify = (scalar(@_) == 1 ? shift : 1);
        my @nodes= ();
    #TODO: these env vars need to get passed by the client to xcatd
	my $nprefix=(defined ($ENV{'XCAT_NODE_PREFIX'}) ? $ENV{'XCAT_NODE_PREFIX'} : 'node');
	my $nsuffix=(defined ($ENV{'XCAT_NODE_SUFFIX'}) ? $ENV{'XCAT_NODE_SUFFIX'} : '');
	if ($nodelist->getAttribs({node=>$atom},'node')) {		#The atom is a plain old nodename
		return ($atom);
	}
    if ($atom =~ /^\(.*\)$/) {     # handle parentheses by recursively calling noderange()
      $atom =~ s/^\((.*)\)$/$1/;
      $recurselevel++;
      return noderange($atom);
    }
    if ($atom =~ /@/) {
          $recurselevel++;
          return noderange($atom);
     }

    # Try to match groups?
	foreach($nodelist->getAllAttribs('node','groups')) {
		my @groups=split(/,/,$_->{groups}); #The where clause doesn't guarantee the atom is a full group name, only that it could be
		if (grep { $_ eq "$atom" } @groups ) {
			push @nodes,$_->{node};
		}
	}

	if ($atom =~ m/^[0-9]+\z/) {    # if only numbers, then add the prefix
		my $nodename=$nprefix.$atom.$nsuffix;
		return expandatom($nodename,$verify);
	}
	my $nodelen=@nodes;
	if ($nodelen > 0) {
		return @nodes;
	}

	if ($atom =~ m/^\//) { # A regular expression
        unless ($verify) { # If not in verify mode, regex makes zero possible sense
          return ($atom);
        }
		#TODO: check against all groups
		$atom = substr($atom,1);
        unless (scalar(@allnodeset)) {
            @allnodeset = $nodelist->getAllAttribs('node');
        }
		foreach (@allnodeset) { #$nodelist->getAllAttribs('node')) {
			if ($_->{node} =~ m/^${atom}$/) {
				push(@nodes,$_->{node});
			}
		}
		return(@nodes);
	}

	if ($atom =~ m/(.*)\[(.*)\](.*)/) { # square bracket range
	#for the time being, we are only going to consider one [] per atom
	#xcat 1.2 does no better
		my @subelems = split(/([\,\-\:])/,$2);
		my $subrange="";
		while (my $subelem = shift @subelems) {
			my $subop=shift @subelems;
			$subrange=$subrange."$1$subelem$3$subop";
		}
		foreach (split /,/,$subrange) {
			my @newnodes=expandatom($_,$verify);
			@nodes=(@nodes,@newnodes);
		}
		return @nodes;
	}

	if ($atom =~ m/\+/) {  # process the + operator
		$atom =~ m/^(.*)([0-9]+)([^0-9\+]*)\+([0-9]+)/;
		my $pref=$1;
		my $startnum=$2;
		my $suf=$3;
		my $end=$4+$startnum;
        my $endnum = sprintf("%d",$end);
        if (length ($startnum) > length ($endnum)) {
          $endnum = sprintf("%0".length($startnum)."d",$end);
        }
		if (($pref eq "") && ($suf eq "")) {
			$pref=$nprefix;
			$suf=$nsuffix;
		}
		foreach ("$startnum".."$endnum") {
			my @addnodes=expandatom($pref.$_.$suf,$verify);
			@nodes=(@nodes,@addnodes);
		}
		return (@nodes);
	}

    if ($atom =~ m/[-:]/) { # process the minus range operator
      my $left;
      my $right;
      if ($atom =~ m/:/) {
        ($left,$right)=split /:/,$atom;
      } else {
        my $count= ($atom =~ tr/-//);
        if (($count % 2)==0) { #can't understand even numbers of - in range context
          if ($verify) {
            push @$missingnodes,$atom;
            return ();
          } else { #but we might not really be in range context, if noverify
            return  ($atom);
          }
        }
        my $expr="([^-]+?".("-[^-]*"x($count/2)).")-(.*)";
        $atom =~ m/$expr/;
        $left=$1;
        $right=$2;
      }
      if ($left eq $right) { #if they said node1-node1 for some strange reason
		return expandatom($left,$verify);
      }
      my @leftarr=split(/(\d+)/,$left);
      my @rightarr=split(/(\d+)/,$right);
      if (scalar(@leftarr) != scalar(@rightarr)) { #Mismatch formatting..
        if ($verify) {
          push @$missingnodes,$atom;
          return (); #mismatched range, bail.
        } else { #Not in verify mode, just have to guess it's meant to be a nodename
          return  ($atom);
        }
      }
      my $prefix = "";
      my $suffix = "";
      foreach (0..$#leftarr) {
        my $idx = $_;
        if ($leftarr[$idx] =~ /^\d+$/ and $rightarr[$idx] =~ /^\d+$/) { #pure numeric component
          if ($leftarr[$idx] ne $rightarr[$idx]) { #We have found the iterator (only supporting one for now)
            my $prefix = join('',@leftarr[0..($idx-1)]); #Make a prefix of the pre-validated parts
            my $luffix; #However, the remainder must still be validated to be the same
            my $ruffix;
            if ($idx eq $#leftarr) {
              $luffix="";
              $ruffix="";
            } else {
              $ruffix = join('',@rightarr[($idx+1)..$#rightarr]);
              $luffix = join('',@leftarr[($idx+1)..$#leftarr]);
            }
            if ($luffix ne $ruffix) { #the suffixes mismatched..
              if ($verify) {
                push @$missingnodes,$atom;
                return ();
              } else {
                return ($atom);
              }
            }
            foreach ($leftarr[$idx]..$rightarr[$idx]) {
              my @addnodes=expandatom($prefix.$_.$luffix,$verify);
              @nodes=(@nodes,@addnodes);
            }
            return (@nodes); #the return has been built, return, exiting loop and all
          }
        } elsif ($leftarr[$idx] ne $rightarr[$idx]) {
          if ($verify) {
            push @$missingnodes,$atom;
            return ();
          } else {
            return ($atom);
          }
        }
        $prefix .= $leftarr[$idx]; #If here, it means that the pieces were the same, but more to come
      }
      #I cannot conceive how the code could possibly be here, but whatever it is, it must be questionable
      if ($verify) {
        push @$missingnodes,$atom;
        return (); #mismatched range, bail.
      } else { #Not in verify mode, just have to guess it's meant to be a nodename
        return  ($atom);
      }
	}

    push @$missingnodes,$atom;
	if ($verify) {
		return ();
	} else {
		return ($atom);
	}
}

sub retain_cache { #A semi private operation to be used *ONLY* in the interesting Table<->NodeRange module interactions.
    $retaincache=shift;
}
sub extnoderange { #An extended noderange function.  Needed as the more straightforward function return format too simple for this.
    my $range = shift;
    my $namedopts = shift;
    my $verify=1;
    if ($namedopts->{skipnodeverify}) {
        $verify=0;
    }
    my $return;
    $retaincache=1;
    $return->{node}=[noderange($range,$verify)];
    if ($namedopts->{intersectinggroups}) {
        my %grouphash=();
        my $nlent;
        foreach (@{$return->{node}}) {
            $nlent=$nodelist->getNodeAttribs($_,['groups']);
            if ($nlent and $nlent->{groups}) {
                foreach (split /,/,$nlent->{groups}) {
                    $grouphash{$_}=1;
                }
            }
        }
        $return->{intersectinggroups}=[sort keys %grouphash];
    }
    $retaincache=0;
    undef ($nodelist);
    @allnodeset=();
    return $return;
}
sub abbreviate_noderange { 
    #takes a list of nodes or a string and abbreviates
    my $nodes=shift;
    my %grouphash;
    my %sizedgroups;
    my %nodesleft;
    my %targetelems;
    unless (ref $nodes) {
        $nodes = noderange($nodes);
    }
    %nodesleft = map { $_ => 1 } @{$nodes};
    unless ($nodelist) { 
        $nodelist =xCAT::Table->new('nodelist',-create =>1); 
    }
    my $group;
	foreach($nodelist->getAllAttribs('node','groups')) {
		my @groups=split(/,/,$_->{groups}); #The where clause doesn't guarantee the atom is a full group name, only that it could be
        foreach $group (@groups) {
            push @{$grouphash{$group}},$_->{node};
        }
    }

    foreach $group (keys %grouphash) {
        push @{$sizedgroups{scalar @{$grouphash{$group}}}},$group;
    }
    my $node;
    use Data::Dumper;
    print Dumper(\%sizedgroups);
    foreach (reverse sort {$a <=> $b} keys %sizedgroups) {
        GROUP: foreach $group (@{$sizedgroups{$_}}) {
                foreach $node (@{$grouphash{$group}}) {
                    unless (grep $node eq $_,keys %nodesleft) {
                    #this group contains a node that isn't left, skip it
                        next GROUP;
                    }
                }
                foreach $node (@{$grouphash{$group}}){
                    delete $nodesleft{$node};
                }
                $targetelems{$group}=1;
        }
    }
    return (join ',',keys %targetelems,keys %nodesleft);
}

sub noderange {
  $missingnodes=[];
  #We for now just do left to right operations
  my $range=shift;
  my $verify = (scalar(@_) == 1 ? shift : 1);
  unless ($nodelist) { 
    $nodelist =xCAT::Table->new('nodelist',-create =>1); 
    $nodelist->{_use_cache} = 0; #TODO: a more proper external solution
    $nodelist->_build_cache(['node','groups']);
    $nodelist->{_use_cache} = 1; #TODO: a more proper external solution
  }
  my %nodes = ();
  my %delnodes = ();
  my $op = ",";
  my @elems = split(/(,(?![^[]*?])(?![^\(]*?\)))/,$range); # commas outside of [] or ()
  if (scalar(@elems)==1) {
      @elems = split(/(@(?![^\(]*?\)))/,$range);  # only split on @ when no , are present (inner recursion)
  }

  while (my $atom = shift @elems) {
    if ($atom =~ /^-/) {           # if this is an exclusion, strip off the minus, but remember it
      $atom = substr($atom,1);
      $op = $op."-";
    }

    if ($atom =~ /^\^(.*)$/) {    # get a list of nodes from a file
      open(NRF,$1);
      while (<NRF>) {
        my $line=$_;
        unless ($line =~ m/^[\^#]/) {
          $line =~ m/^([^:	 ]*)/;
          my $newrange = $1;
          chomp($newrange);
          $recurselevel++;
          my @filenodes = noderange($newrange);
          foreach (@filenodes) {
            $nodes{$_}=1;
          }
        }
      }
      close(NRF);
      next;
    }

    my %newset = map { $_ =>1 } expandatom($atom,$verify);    # expand the atom and make each entry in the resulting array a key in newset

    if ($op =~ /@/) {       # compute the intersection of the current atom and the node list we have received before this
      foreach (keys %nodes) {
        unless ($newset{$_}) {
          delete $nodes{$_};
        }
      }
    } elsif ($op =~ /,-/) {        # add the nodes from this atom to the exclude list
		foreach (keys %newset) {
			$delnodes{$_}=1; #delay removal to end
		}
	} else {          # add the nodes from this atom to the total node list
		foreach (keys %newset) {
			$nodes{$_}=1;
		}
	}
	$op = shift @elems;

    }    # end of main while loop

    # Now remove all the exclusion nodes
    foreach (keys %nodes) {
		if ($delnodes{$_}) {
			delete $nodes{$_};
		}
    }
    if ($recurselevel) {
        $recurselevel--;
    } else {
        unless ($retaincache) {
            undef $nodelist;
            @allnodeset=();
        }
    }
    return sort (keys %nodes);

}


1;

=head1 NAME

xCAT::NodeRange - Perl module for xCAT noderange expansion

=head1 SYNOPSIS

	use xCAT::NodeRange;
	my @nodes=noderange("storage@rack1,node[1-200],^/tmp/nodelist,node300-node400,node401+10,500-550");

=head1 DESCRIPTION

noderange interprets xCAT noderange formatted strings and returns a list of xCAT nodelists.  The following two operations are supported on elements, and interpreted left to right:

, union next element with everything to the left.

@ take intersection of element to the right with everything on the left (i.e. mask out anything to the left not belonging to what is described to the right)

Each element can be a number of things:

A node name, i.e.:

=item * node1

A hyphenated node range (only one group of numbers may differ between the left and right hand side, and those numbers will increment in a base 10 fashion):

node1-node200 node1-compute-node200-compute
node1:node200 node1-compute:node200-compute

A noderange denoted by brackets:

node[1-200] node[001-200]

A regular expression describing the noderange:

/d(1.?.?|200)

A node plus offset (this increments the first number found in nodename):

node1+199

And most of the above substituting groupnames.
3C
3C

NodeRange tries to be intelligent about detecting padding, so you can:
node001-node200
And it will increment according to the pattern.


=head1 AUTHOR

Jarrod Johnson (jbjohnso@us.ibm.com)

=head1 COPYRIGHT

Copyright 2007 IBM Corp.  All rights reserved.


=cut
