# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::NodeRange;
use Text::Balanced qw/extract_bracketed/;
require xCAT::Table;
require Exporter;
use strict;

#Perl implementation of noderange
our @ISA = qw(Exporter);
our @EXPORT = qw(noderange nodesmissed);
our @EXPORT_OK = qw(extnoderange abbreviate_noderange);

my $missingnodes=[];
my $nodelist; #=xCAT::Table->new('nodelist',-create =>1);
my $grptab;
#TODO: MEMLEAK note
# I've moved grptab up here to avoid calling 'new' on it on every noderange
# Something is wrong in the Table object such that it leaks
# a few kilobytes of memory, even if nodelist member is not created
# To reproduce the mem leak, move 'my $grptab' to the place where it is used
# then call 'getAllNodesAttribs' a few thousand times on some table
# No one noticed before 2.3 because the lifetime of processes doing noderange 
# expansion was short (seconds)
# In 2.3, the problem has been 'solved' for most contexts in that the DB worker
# reuses Table objects rather than ever destroying them
# The exception is when the DB worker process itself wants to expand
# a noderange, which only ever happens from getAllNodesAttribs
# in this case, we change NodeRange to reuse the same Table object
# even if not relying upon DB worker to figure it out for noderange
# This may be a good idea anyway, regardless of memory leak
# It remains a good way to induce the memleak to correctly fix it 
# rather than hiding from the problem

#my $nodeprefix = "node";
my @allnodeset;
my %allnodehash;
my @grplist;
my $didgrouplist;
my $glstamp=0;
my $allnodesetstamp=0;
my $allgrphashstamp=0;
my %allgrphash;
my $retaincache=0;
my $recurselevel=0;

my @cachedcolumns;
#TODO:  With a very large nodelist (i.e. 65k or so), deriving the members
# of a group is a little sluggish.  We may want to put in a mechanism to 
# maintain a two-way hash anytime nodelist or nodegroup changes, allowing
# nodegroup table and nodelist to contain the same information about
# group membership indexed in different ways to speed this up.
# At low scale, little to no difference/impact would be seen
# at high scale, changing nodelist or nodegroup would be perceptibly longer,
# but many other operations would probably benefit greatly.

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

sub reset_db {
#workaround, something seems to be trying to use a corrupted reference to grptab
#this allows init_dbworker to reset the object
    $grptab=0;
}
sub nodesbycriteria {
   #TODO: this should be in a common place, shared by tabutils nodech/nodels and noderange
   #there is a set of functions already, but the path is a little complicated and
   #might be hooked into the objective usage style, which this function is not trying to match
   #Return nodes by criteria.  Can accept a list reference of criteria
   #returns a hash reference of criteria expressions to nodes that meet
   my $nodes = shift; #the set from which to match
   my $critlist = shift; #list of criteria to match
   my %tables;
   my %shortnames = (
                  groups => [qw(nodelist groups)],
                  tags   => [qw(nodelist groups)],
                  mgt    => [qw(nodehm mgt)],
                  #switch => [qw(switch switch)],
                  );

   unless (ref $critlist) {
       $critlist = [ $critlist ];
   }
   my $criteria;
   my %critnodes;
   my $value;
   my $tabcol;
   my $matchtype;
   foreach $criteria (@$critlist) {
       my $table;
       my $column;
       $tabcol=$criteria;
       if ($criteria =~ /^[^=]*\!=/) {
        ($criteria,$value) = split /!=/,$criteria,2;
        $matchtype='natch';
       } elsif ($criteria =~ /^[^=]*=~/) {
        ($criteria,$value) = split /=~/,$criteria,2;
        $value =~ s/^\///;
        $value =~ s/\/$//;
        $matchtype='regex';
       } elsif ($criteria =~ /[^=]*==/) {
        ($criteria,$value) = split /==/,$criteria,2;
        $matchtype='match';
       } elsif ($criteria =~ /[^=]*=/) {
        ($criteria,$value) = split /=/,$criteria,2;
        $matchtype='match';
       } elsif ($criteria =~ /[^=]*!~/) {
        ($criteria,$value) = split /!~/,$criteria,2;
        $value =~ s/^\///;
        $value =~ s/\/$//;
        $matchtype='negex';
       }
       if ($shortnames{$criteria}) {
           ($table, $column) = @{$shortnames{$criteria}};
       } elsif ($criteria =~ /\./) {
           ($table, $column) = split('\.', $criteria, 2);
       } else {
           return undef;
       }
       unless (grep /$column/,@{$xCAT::Schema::tabspec{$table}->{cols}}) {
           return undef;
       }
       push @{$tables{$table}},[$column,$tabcol,$value,$matchtype];    #Mark this as something to get
   }
   my $tab;
   foreach $tab (keys %tables) {
       my $tabh = xCAT::Table->new($tab,-create=>0);
       unless ($tabh) { next; }
       my @cols;
       foreach (@{$tables{$tab}}) {
           push @cols, $_->[0];
        }
       if ($tab eq "nodelist") { #fun caching interaction
	 my $neednewcache=0;
	 my $nlcol;
	 foreach $nlcol (@cols) {
	   unless (grep /^$nlcol\z/,@cachedcolumns) {
	     $neednewcache=1;
	     push @cachedcolumns,$nlcol;
	   }
	 }
	 if ($neednewcache) {
	   if ($nodelist) { 
	     $nodelist->_clear_cache(); 
	     $nodelist->_build_cache(\@cachedcolumns);
	   }
	  }
	 }
        my $rechash = $tabh->getNodesAttribs($nodes,\@cols); #TODO: if not defined nodes, getAllNodesAttribs may be faster actually...
        foreach my $node (@$nodes) {
            my $recs = $rechash->{$node};
            my $critline;
            foreach $critline (@{$tables{$tab}}) {
                foreach my $rec (@$recs) {
                    my $value="";
                    if (defined $rec->{$critline->[0]}) {
                        $value = $rec->{$critline->[0]};
                    }
                    my $compstring = $critline->[2];
                    if ($critline->[3] eq 'match' and $value eq $compstring) {
                        push @{$critnodes{$critline->[1]}},$node;
                    } elsif ($critline->[3] eq 'natch' and $value ne $compstring) {
                        push @{$critnodes{$critline->[1]}},$node;
                    } elsif ($critline->[3] eq 'regex' and $value =~ /$compstring/) {
                        push @{$critnodes{$critline->[1]}},$node;
                    } elsif ($critline->[3] eq 'negex' and $value !~ /$compstring/) {
                        push @{$critnodes{$critline->[1]}},$node;
                    }
                }
            }
        }
   }
   return \%critnodes;
}

# Expand one part of the noderange from the noderange() function.  Initially, one part means the
# substring between commas in the noderange.  But expandatom also calls itself recursively to
# further expand some parts.
# Input args:
#  - atom to expand
#  - verify: whether or not to require that the resulting nodenames exist in the nodelist table
#  - options: genericrange - a purely syntactical expansion of the range, not using the db at all, e.g not expanding group names
sub expandatom {
	my $atom = shift;
    if ($recurselevel > 4096) { die "NodeRange seems to be hung on evaluating $atom, recursion limit hit"; } 
    unless (scalar(@allnodeset) and (($allnodesetstamp+5) > time())) { #Build a cache of all nodes, some corner cases will perform worse, but by and large it will do better.  We could do tests to see where the breaking points are, and predict how many atoms we have to evaluate to mitigate, for now, implement the strategy that keeps performance from going completely off the rails
	$allnodesetstamp=time();
	$nodelist->_set_use_cache(1);
        @allnodeset = $nodelist->getAllAttribs('node','groups');
        %allnodehash = map { $_->{node} => 1 } @allnodeset;
    }
	my $verify = (scalar(@_) >= 1 ? shift : 1);
  my %options = @_;      # additional options
        my @nodes= ();
    #TODO: these env vars need to get passed by the client to xcatd
	my $nprefix=(defined ($ENV{'XCAT_NODE_PREFIX'}) ? $ENV{'XCAT_NODE_PREFIX'} : 'node');
	my $nsuffix=(defined ($ENV{'XCAT_NODE_SUFFIX'}) ? $ENV{'XCAT_NODE_SUFFIX'} : '');

	if (not $options{genericrange} and  $allnodehash{$atom}) {		#The atom is a plain old nodename
		return ($atom);
	}
    if ($atom =~ /^\(.*\)$/) {     # handle parentheses by recursively calling noderange()
      $atom =~ s/^\((.*)\)$/$1/;
      $recurselevel++;
      return noderange($atom,$verify,1,%options);
    }
    if ($atom =~ /@/) {
          $recurselevel++;
          return noderange($atom,$verify,1,%options);
     }

    # Try to match groups?
    unless ($options{genericrange}) {
        unless ($grptab) {
           $grptab = xCAT::Table->new('nodegroup');
        }
        if ($grptab and (($glstamp < (time()-5)) or (not $didgrouplist and not scalar @grplist))) { 
            $didgrouplist = 1;
	    $glstamp=time();
            @grplist = @{$grptab->getAllEntries()};
        }
        my $isdynamicgrp = 0;
        foreach my $grpdef_ref (@grplist) {
            my %grpdef = %$grpdef_ref;
            # Try to match a dynamic node group
            # do not try to match the static node group from nodegroup table,
            # the static node groups are stored in nodelist table.
            if (($grpdef{'groupname'} eq $atom) && ($grpdef{'grouptype'} eq 'dynamic'))
            {
                $isdynamicgrp = 1;
                my $grpname = $atom;
                my %grphash;
                $grphash{$grpname}{'objtype'} = 'group';
                $grphash{$grpname}{'grouptype'} = 'dynamic';
                $grphash{$grpname}{'wherevals'} = $grpdef{'wherevals'};
                my $memberlist = xCAT::DBobjUtils->getGroupMembers($grpname, \%grphash);
                foreach my $grpmember (split ",", $memberlist)
                {
                    push @nodes, $grpmember;
                }
                last; #there should not be more than one group with the same name
             }
         }
         # The atom is not a dynamic node group, is it a static node group???
         if(!$isdynamicgrp)
         {
            unless (scalar %allgrphash and (time() < ($allgrphashstamp+5))) { #build a group membership cache
		$allgrphashstamp=time();
        	%allgrphash=();
                my $nlent;
	            foreach $nlent (@allnodeset) { 
	                my @groups=split(/,/,$nlent->{groups}); 
                    my $grp;
                    foreach $grp (@groups) {
                        push @{$allgrphash{$grp}},$nlent->{node};
                    }
                }
            }
            if ($allgrphash{$atom})  {
                push @nodes,@{$allgrphash{$atom}};
	        }
          }

  # check to see if atom is a defined group name that didn't have any current members                                               
  if ( scalar @nodes == 0 ) {                                                                                                       
    if(scalar @grplist) { #Use previously constructed cache to avoid hitting DB worker so much
        #my @grouplist = $grptab->getAllAttribs('groupname');
        for my $row ( @grplist ) { 
            if ( $row->{groupname} eq $atom ) { 
                return ();                                                                                                                  
            } 
        }
     }
  }
}

    # node selection based on db attribute values (nodetype.os==rhels5.3)
    if ($atom =~ m/[=~]/) { #TODO: this is the clunky, slow code path to acheive the goal.  It also is the easiest to write, strange coincidence.  Aggregating multiples would be nice
        my @nodes;
        foreach (@allnodeset) {
            push @nodes,$_->{node};
        }
        my $nbyc_ref = nodesbycriteria(\@nodes,[$atom]);
        if ($nbyc_ref)
        {
            my $nbyc = $nbyc_ref->{$atom};
            if (defined $nbyc) {
                return @$nbyc;
            }
        }
        return ();
    }
	if ($atom =~ m/^[0-9]+\z/) {    # if only numbers, then add the prefix
		my $nodename=$nprefix.$atom.$nsuffix;
		return expandatom($nodename,$verify,%options);
	}
	my $nodelen=@nodes;
	if ($nodelen > 0) {
		return @nodes;
	}

	if ($atom =~ m/^\//) { # A regular expression
        if ($verify==0 or $options{genericrange}) { # If not in verify mode, regex makes zero possible sense
          return ($atom);
        }
		#TODO: check against all groups
		$atom = substr($atom,1);
		foreach (@allnodeset) { #$nodelist->getAllAttribs('node')) {
			if ($_->{node} =~ m/^${atom}$/) {
				push(@nodes,$_->{node});
			}
		}
		return(@nodes);
	}

	if ($atom =~ m/(.+?)\[(.+?)\](.*)/) { # square bracket range
		# if there is more than 1 set of [], we picked off just the 1st.  If there more sets of [], we will expand
    # the 1st set and create a new set of atom by concatenating each result in the 1st expandsion with the rest
    # of the brackets.  Then call expandatom() recursively on each new atom.
		my @subelems = split(/([\,\-\:])/,$2);    # $2 is the range inside the 1st set of brackets
		my $subrange="";
    my $subelem;
    my $start = $1;   # the text before the 1st set of brackets
    my $ending = $3;    # the text after the 1st set of brackets (could contain more brackets)
    my $morebrackets = $ending =~ /\[.+?\]/;	# if there are more brackets, we have to expand just the 1st part, then add the 2nd part later
		while (scalar @subelems) {    # this while loop turns something like a[1-3] into a1-a3 because another section of expand atom knows how to expand that
      my $subelem = shift @subelems;
			my $subop=shift @subelems;
			$subrange=$subrange."$start$subelem" . ($morebrackets?'':$ending) . "$subop";
		}
		foreach (split /,/,$subrange) {   # this foreach is in case there were commas inside the brackets originally, e.g.: a[1,3,5]b[1-2]
      # this expandatom just expands the part of the noderange that contains the 1st set of brackets
      # e.g. if noderange is a[1-2]b[1-2] it will create newnodes of a1 and a2
			my @newnodes=expandatom($_, ($morebrackets?0:$verify), genericrange=>($morebrackets||$options{genericrange}));
			if (!$morebrackets) { push @nodes,@newnodes; }
			else {
				# for each of the new nodes (prefixes), add the rest of the brackets and then expand recursively
				foreach my $n (@newnodes) {
					push @nodes, expandatom("$n$ending", $verify, %options);
				}
			}
		}
		return @nodes;
	}

	if ($atom =~ m/\+/) {  # process the + operator
		$atom =~ m/^(.*)([0-9]+)([^0-9\+]*)\+([0-9]+)/;
                my ($front, $increment) = split(/\+/, $atom, 2);
                my ($pref, $startnum, $dom) = $front =~ /^(.*?)(\d+)(\..+)?$/;
		my $suf=$3;
		my $end=$startnum+$increment;
        my $endnum = sprintf("%d",$end);
        if (length ($startnum) > length ($endnum)) {
          $endnum = sprintf("%0".length($startnum)."d",$end);
        }
		if (($pref eq "") && ($suf eq "")) {
			$pref=$nprefix;
			$suf=$nsuffix;
		}
		foreach ("$startnum".."$endnum") {
			my @addnodes=expandatom($pref.$_.$suf,$verify,%options);
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
		return expandatom($left,$verify,%options);
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
              my @addnodes=expandatom($prefix.$_.$luffix,$verify,%options);
              push @nodes,@addnodes;
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

	if ($verify) {
    	push @$missingnodes,$atom;
		return ();
	} else {
		return ($atom);
	}
}

sub retain_cache { #A semi private operation to be used *ONLY* in the interesting Table<->NodeRange module interactions.
    $retaincache=shift;
    unless ($retaincache) { #take a call to retain_cache(0) to also mean that any existing
        #cache must be zapped
        if ($nodelist) { $nodelist->_build_cache(1); }
	$glstamp=0;
	$allnodesetstamp=0;
	$allgrphashstamp=0;
        undef $nodelist;
        @allnodeset=();
        %allnodehash=();
        @grplist=();
        $didgrouplist = 0;
        %allgrphash=();
    }
}
sub extnoderange { #An extended noderange function.  Needed by the GUI as the more straightforward function return format too simple for this.
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
            $nlent=$nodelist->getNodeAttribs($_,['groups']); #TODO: move to noderange side cache
            if ($nlent and $nlent->{groups}) {
                foreach (split /,/,$nlent->{groups}) {
                    $grouphash{$_}=1;
                }
            }
        }
        $return->{intersectinggroups}=[sort keys %grouphash];
    }
    return $return;
}
sub abbreviate_noderange { 
    #takes a list of nodes or a string and reduces it by replacing a list of nodes that make up a group with the group name itself
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
        #skip single node sized groups, these outliers frequently pasted into non-noderange capable contexts
        if (scalar @{$grouphash{$group}} < 2) { next; }
        push @{$sizedgroups{scalar @{$grouphash{$group}}}},$group;
    }
    my $node;
    #use Data::Dumper;
    #print Dumper(\%sizedgroups);
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

sub set_arith {
    my $operand = shift;
    my $op = shift;
    my $newset = shift;
    if ($op =~ /@/) {       # compute the intersection of the current atom and the node list we have received before this
      foreach (keys %$operand) {
        unless ($newset->{$_}) {
          delete $operand->{$_};
        }
      }
    } elsif ($op =~ /,-/) {        # add the nodes from this atom to the exclude list
		foreach (keys %$newset) {
            delete $operand->{$_}
		}
	} else {          # add the nodes from this atom to the total node list
		foreach (keys %$newset) {
			$operand->{$_}=1;
		}
	}
}
# Expand the given noderange
# Input args:
#  - noderange to expand
#  - verify: whether or not to require that the resulting nodenames exist in the nodelist table
#  - exsitenode: whether or not to honor site.excludenodes to automatically exclude those nodes from all noderanges
#  - options: genericrange - a purely syntactical expansion of the range, not using the db at all, e.g not expanding group names
sub noderange {
  $missingnodes=[];
  #We for now just do left to right operations
  my $range=shift;
  $range =~ s/['"]//g;
  my $verify = (scalar(@_) >= 1 ? shift : 1);
  my $exsitenode = (scalar(@_) >= 1 ? shift : 1);   # if 1, honor site.excludenodes
  my %options = @_;      # additional options

  unless ($nodelist) { 
    $nodelist =xCAT::Table->new('nodelist',-create =>1); 
    $nodelist->_set_use_cache(0); #TODO: a more proper external solution
    @cachedcolumns = ('node','groups');
    $nodelist->_build_cache(\@cachedcolumns,noincrementref=>1);
    $nodelist->_set_use_cache(1); #TODO: a more proper external solution
  }
  my %nodes = ();
  my %delnodes = ();
  if ($range =~ /\(/) {
    my ($middle, $end, $start) =
        extract_bracketed($range, '()', qr/[^()]*/);
    unless ($middle) { die "Unbalanced parentheses in noderange" }
    $middle = substr($middle,1,-1);
    my $op = ",";
    if ($start =~ m/-$/) { #subtract the parenthetical
       $op .= "-"
    } elsif ($start =~ m/\@$/) {
        $op = "@"
    }
    $start =~ s/,-$//;
    $start =~ s/,$//;
    $start =~ s/\@$//;
    %nodes = map { $_ => 1 } noderange($start,$verify,$exsitenode,%options);
    my %innernodes = map { $_ => 1 } noderange($middle,$verify,$exsitenode,%options);
    set_arith(\%nodes,$op,\%innernodes);
    $range = $end;
  }

  my $op = ",";
  my @elems = split(/(,(?![^[]*?])(?![^\(]*?\)))/,$range); # commas outside of [] or ()
  if (scalar(@elems)==1) {
      @elems = split(/(@(?![^\(]*?\)))/,$range);  # only split on @ when no , are present (inner recursion)
  }

  while (defined(my $atom = shift @elems)) {
    if ($atom eq '') { next; }
    if ($atom eq ',') {
        next;
    }
    if ($atom =~ /^-/) {           # if this is an exclusion, strip off the minus, but remember it
      $atom = substr($atom,1);
      $op = $op."-";
    } elsif ($atom =~ /^\@/) {           # if this is an exclusion, strip off the minus, but remember it
      $atom = substr($atom,1);
      $op = "@";
    }
    if ($atom eq '') { next; }

    if ($atom =~ /^\^(.*)$/) {    # get a list of nodes from a file
      open(NRF,$1);
      while (<NRF>) {
        my $line=$_;
        unless ($line =~ m/^[\^#]/) {
          $line =~ m/^([^:	 ]*)/;
          my $newrange = $1;
          chomp($newrange);
          $recurselevel++;
          my @filenodes = noderange($newrange,$verify,$exsitenode,%options);
          foreach (@filenodes) {
            $nodes{$_}=1;
          }
        }
      }
      close(NRF);
      next;
    }

    my %newset = map { $_ =>1 } expandatom($atom,$verify,%options);    # expand the atom and make each entry in the resulting array a key in newset

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


    # Exclude the nodes in site attribute excludenodes?
    if ($exsitenode) {
        my $badnoderange = 0;
        my @badnodes = ();
	if ($::XCATSITEVALS{excludenodes}) {
                @badnodes = noderange($::XCATSITEVALS{excludenodes}, 1, 0, %options);
                foreach my $bnode (@badnodes) {
                    if (!$delnodes{$bnode}) {
                        $delnodes{$bnode} = 1;
                    }
		}
        }
    }

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
