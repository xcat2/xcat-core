# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::NameRange;
require xCAT::Table;
require Exporter;
use strict;

#Perl implementation of namerange
#  NOTE:  This is identical to xCAT::NodeRange except that no
#		  database access occurs, no nodes are verified, and 
#         no nodegroups are expanded.
#		  Made a new utility since NodeRange is used EVERYWHERE in
#		  xCAT code and did not want to risk de-stabilizing existing code.
our @ISA = qw(Exporter);
our @EXPORT = qw(namerange);

my $recurselevel=0;


sub subnodes (\@@) {
    #Subtract set of nodes from the first list
    my $nodes = shift;
    my $node;
    foreach $node (@_) {
        @$nodes = (grep(!/^$node$/,@$nodes));
    }
}

sub expandatom {
	my $atom = shift;
    my @nodes= ();
    if ($atom =~ /^\(.*\)$/) {     # handle parentheses by recursively calling namerange()
      $atom =~ s/^\((.*)\)$/$1/;
      $recurselevel++;
      return namerange($atom);
    }
    if ($atom =~ /@/) {
          $recurselevel++;
          return namerange($atom);
     }

	if ($atom =~ m/^\//) { # A regular expression - not supported in namerange
          return ($atom);
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
			my @newnodes=expandatom($_);
			@nodes=(@nodes,@newnodes);
		}
		return @nodes;
	}

	if ($atom =~ m/\+/) {  # process the + operator
		$atom =~ m/^([^0-9]*)([0-9]+)([^\+]*)\+([0-9]+)/;
		my $pref=$1;
		my $startnum=$2;
		my $suf=$3;
		my $end=$4+$startnum;
        my $endnum = sprintf("%d",$end);
        if (length ($startnum) > length ($endnum)) {
          $endnum = sprintf("%0".length($startnum)."d",$end);
        }
		foreach ("$startnum".."$endnum") {
			my @addnodes=expandatom($pref.$_.$suf);
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
         # we might not really be in range context
           return  ($atom);
        }
        my $expr="([^-]+?".("-[^-]*"x($count/2)).")-(.*)";
        $atom =~ m/$expr/;
        $left=$1;
        $right=$2;
      }
      if ($left eq $right) { #if they said node1-node1 for some strange reason
		return expandatom($left);
      }
      my @leftarr=split(/(\d+)/,$left);
      my @rightarr=split(/(\d+)/,$right);
      if (scalar(@leftarr) != scalar(@rightarr)) { #Mismatch formatting..
        # guess it's meant to be a nodename
        return  ($atom);
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
              return ($atom);
            }
            foreach ($leftarr[$idx]..$rightarr[$idx]) {
              my @addnodes=expandatom($prefix.$_.$luffix);
              @nodes=(@nodes,@addnodes);
            }
            return (@nodes); #the return has been built, return, exiting loop and all
          }
        } elsif ($leftarr[$idx] ne $rightarr[$idx]) {
          return ($atom);
        }
        $prefix .= $leftarr[$idx]; #If here, it means that the pieces were the same, but more to come
      }
      #I cannot conceive how the code could possibly be here, but whatever it is, it must be questionable
      return  ($atom);
	}

	return ($atom);
}

sub namerange {
  #We for now just do left to right operations
  my $range=shift;
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
          my @filenodes = namerange($newrange);
          foreach (@filenodes) {
            $nodes{$_}=1;
          }
        }
      }
      close(NRF);
      next;
    }

    my %newset = map { $_ =>1 } expandatom($atom);    # expand the atom and make each entry in the resulting array a key in newset

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
    }
    return sort (keys %nodes);

}


1;

=head1 NAME

xCAT::NameRange - Perl module for xCAT namerange expansion

=head1 SYNOPSIS

	use xCAT::NameRange;
	my @nodes=namerange("storage@rack1,node[1-200],^/tmp/nodelist,node300-node400,node401+10,500-550");

=head1 DESCRIPTION

namerange interprets xCAT noderange formatted strings and returns a list of 
names. The following two operations are supported on elements, and interpreted 
left to right:

  , union next element with everything to the left.

  @ take intersection of element to the right with everything on the left 
   (i.e. mask out anything to the left not belonging to what is described to 
   the right)

Each element can be a number of things:

  A node name, i.e.:

=item * node1

A hyphenated node range (only one group of numbers may differ between the left and right hand side, and those numbers will increment in a base 10 fashion):

node1-node200 node1-compute-node200-compute
node1:node200 node1-compute:node200-compute

A namerange denoted by brackets:

node[1-200] node[001-200]

A regular expression describing the namerange:

/d(1.?.?|200)

A node plus offset (this increments the first number found in nodename):

node1+199

And most of the above substituting groupnames.
3C
3C

NameRange tries to be intelligent about detecting padding, so you can:
node001-node200
And it will increment according to the pattern.


=head1 COPYRIGHT

Copyright 2007 IBM Corp.  All rights reserved.


=cut
