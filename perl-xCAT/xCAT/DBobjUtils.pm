#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

#####################################################
#
#   Utility subroutines that can be used to manage xCAT data object
#                       definitions.
#
#
#####################################################
package xCAT::DBobjUtils;

require xCAT::NodeRange;
require xCAT::Schema;
require xCAT::Table;
require xCAT::Utils;
require xCAT::MsgUtils;
require xCAT::NetworkUtils;
require xCAT::ServiceNodeUtils;
use strict;

#  IPv6 not yet implemented - need Socket6
use Socket;

#----------------------------------------------------------------------------

=head3   getObjectsOfType

        Get a list of data objects of the given type.

        Arguments:
        Returns:
                undef
                @objlist - list of objects of this type
        Globals:
        Error:
        Example:
        Comments:

                @objlist = xCAT::DBobjUtils->getObjectsOfType($type);

=cut

#-----------------------------------------------------------------------------
sub getObjectsOfType
{
    my ($class, $type) = @_;

    my @objlist;

    # special case for site table
    if ($type eq 'site')
    {
        push(@objlist, 'clustersite');
        return @objlist;
    }

    # The database may be changed between getObjectsOfType calls
    # do not use cache %::saveObjList  if --nocache is specified
    if ($::saveObjList{$type} && !$::opt_nc)
    {
        @objlist = @{$::saveObjList{$type}};
    }
    else
    {

        # get the key for this type object
        # 	ex. for "network" type the key is "netname"
        # get the data type spec from Schema.pm
        my $datatype = $xCAT::Schema::defspec{$type};

        # get the key for this type object
        #   ex. for "network" type the key is "netname"
        my $objkey = $datatype->{'objkey'};

        my $table;
        my $tabkey;
        foreach my $this_attr (@{$datatype->{'attrs'}})
        {
            my $attr = $this_attr->{attr_name};
            if ($attr eq $objkey)
            {
                # get the table & key for to lookup
                # get the actual attr name to use in the table
                #   - may be different then the attr name used for the object.
                ($table, $tabkey) = split('\.', $this_attr->{tabentry});
                last;
            }
        }

        # get the whole table and add each entry in the objkey column
        #   to the list of objects.
        my @TableRowArray = xCAT::DBobjUtils->getDBtable($table);

        foreach (@TableRowArray)
        {
            push(@objlist, $_->{$tabkey});

        }

        # if this is type "group" we need to check the nodelist table
        my @nodeGroupList=();
        if ($type eq 'group')
        {
            my $table = "nodelist";
            my @TableRowArray = xCAT::DBobjUtils->getDBtable($table);
            foreach (@TableRowArray)
            {
                my @tmplist = split(',', $_->{'groups'});
                push(@nodeGroupList, @tmplist);
            }
            foreach my $n (@nodeGroupList)
            {
                if (!grep(/^$n$/, @objlist) ) {
                    push(@objlist, $n);
                }
            }
        }
		
        @{$::saveObjList{$type}} = @objlist;
    }

    return @objlist;
}

#----------------------------------------------------------------------------

=head3   getobjattrs

        Get data from tables 

                $type_hash: objectname=>objtype hash
                $attrs_ref: only get the specific attributes,
                            this can be useful especially for performance considerations
        Arguments:
        Returns:
                undef
                hash ref - (ex. $tabhash{$table}{$objname}{$attr} = $value)
        Globals:
        Error:
        Example:

                %tabhash = xCAT::DBobjUtils->getobjattrs(\%typehash);

        Comments:
			For now - only support tables that have 'node' as key !!!
=cut

#-----------------------------------------------------------------------------
sub getobjattrs
{
    my $class = shift;
    my $ref_hash = shift;
    my @attrs;
    # The $attrs is an optional argument
    if (ref $_[0]) {
        @attrs = @{shift()};
    }
    my %typehash = %$ref_hash;
    
    my %tableattrs;
    my %tabhash;
    
    # get a list of object names for each type
    my %objtypelist;
    foreach my $objname (sort (keys %typehash)) {
        # get list of objects for each type
        # $objtypelist{$typehash{$objname}}=$objname;
        push @{$objtypelist{$typehash{$objname}}}, $objname;
    }
    
    # go through each object type and look up all the info for each object
    foreach my $objtype (keys %objtypelist) {
    
    	  # only do node type for now 
         if ($objtype eq 'node') {
            # find the list of tables and corresponding attrs 
            #	- for this object type
            # get the object type decription from Schema.pm
            my $datatype = $xCAT::Schema::defspec{$objtype};
            foreach my $this_attr (@{$datatype->{'attrs'}}) {
                my $attr = $this_attr->{attr_name};
                if (scalar(@attrs) > 0) { # Only query specific attributes
                    if (!grep(/^$attr$/, @attrs)) {
                        next; # This attribute is not needed
                    }
                }
                
                # table_attr is the attr that actually appears in the
                #  table which could possibly be different then the attr
                #  used in the node def
                # ex. 'nodetype.arch'
                my ($lookup_table, $table_attr) = split('\.', $this_attr->{tabentry});
                if (!grep(/^$table_attr$/, @{$tableattrs{$lookup_table}})) {
                    push @{$tableattrs{$lookup_table}}, $table_attr;
                }
            }
            
            # foreach table look up the list of attrs for this 
            # list of object names
            foreach my $table (keys %tableattrs) {
                # open the table
                # with autocommit => 0, it does not work on Ubuntu running mysql
                my $thistable = xCAT::Table->new($table, -create => 1, -autocommit => 1);
                if (!$thistable) {
                    my $rsp;
                    $rsp->{data}->[0] = "Could not open the \'$table\' table.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    next;
                }
            
                my @objlist = @{$objtypelist{$objtype}};
                
                my $rec = $thistable->getNodesAttribs(\@objlist, @{$tableattrs{$table}});
                
                # fill in %tabhash with any values that are set
                foreach my $n (@objlist) {
                	my $tmp1=$rec->{$n}->[0];
                	foreach $a (@{$tableattrs{$table}}) {
                        if (defined($tmp1->{$a})) {
                            $tabhash{$table}{$n}{$a} = $tmp1->{$a};
                            #print "obj = $n, table = $table, attr =$a, val = $tabhash{$table}{$n}{$a}\n";
                        } else {
                            # Add a has been searched flag to improve the performance
                            $tabhash{$table}{$n}{"$a"."_hassearched"} = 1;
                        }
                	}
                }
                #$thistable->commit;
            }
        }
    }
    return %tabhash;
}

#----------------------------------------------------------------------------

=head3   getobjdefs

        Get object definitions from the DB.

                $type_hash: objectname=>objtype hash
                $verbose: optional
                $attrs_ref: only get the specific attributes,
                            this can be useful especially for performance considerations
                $chname_ref: used to get the table entries for changing the object name
        Arguments:
        Returns:
                undef - error
                hash ref - $objecthash{objectname}{attrname} = value
        Globals:
        Error:
        Example:

		To use create hash for objectname and object type
            ex. $objhash{$obj} = $type;

        - then call as follows:
			%myhash = xCAT::DBobjUtils->getobjdefs(\%objhash);

        Comments:

=cut

#-----------------------------------------------------------------------------
sub getobjdefs
{
    my ($class, $hash_ref, $verbose, $attrs_ref, $chname_ref) = @_;
    my %objhash;
    my %typehash = %$hash_ref;
    my %tabhash;
    my @attrs;
    if (ref($attrs_ref))
    {
        @attrs = @$attrs_ref;
    }

    @::foundTableList = ();
    
    if ($::ATTRLIST eq "none") {
        # just return the list of obj names
        foreach my $objname (sort (keys %typehash))
        {
            my $type = $typehash{$objname};
            $objhash{$objname}{'objtype'} = $type;
        }
        return %objhash;
    }

    # see if we need to get any objects of type 'node' 
    my $getnodes=0;
    foreach my $objname (keys %typehash) {
        if ($typehash{$objname} eq 'node') {
            $getnodes=1;
        }
    }

    # if so then get node info from tables now
    #   still may need to look up values in some tables using
    #   other keys - also need to figure out what tables to take
    #   values from when using 'only_if' - see below
    # - but this saves lots of time
    if ($getnodes) {
        if (scalar(@attrs) > 0) # Only get specific attributes of the node
        {
            # find the onlyif key for the attributes
            REDO: my $datatype = $xCAT::Schema::defspec{'node'};
            foreach my $this_attr (@{$datatype->{'attrs'}}) {
                my $attr = $this_attr->{attr_name};
                if (exists($this_attr->{only_if})) {
                    my ($onlyif_key, $onlyif_value) = split('\=', $this_attr->{only_if});
                    if (!grep (/^$onlyif_key$/, @attrs)) {
                        push @attrs, $onlyif_key;
                        goto REDO;
                    }
                }
            }
            %tabhash = xCAT::DBobjUtils->getobjattrs(\%typehash, \@attrs);
        }
        else
        {
            %tabhash = xCAT::DBobjUtils->getobjattrs(\%typehash);
        }
    }

    # Classify the nodes with type
    my %type_obj = ();
    foreach my $objname (keys %typehash) {
        push @{$type_obj{$typehash{$objname}}}, $objname;
    }

    foreach my $objtype (sort (keys %type_obj)) {
        if ($objtype eq 'site') {
            my @TableRowArray = xCAT::DBobjUtils->getDBtable('site');
            foreach my $objname (sort @{$type_obj{$objtype}}) {
                if (@TableRowArray)
                {
                    my $foundinfo = 0;
                    foreach (@TableRowArray)
                    {
                        if ($_->{key})
                        {
                            if (defined($_->{value}) ) {
                                $foundinfo++;
                                if ($verbose == 1) {
                                    $objhash{$objname}{$_->{key}} = "$_->{value}\t(Table:site - Key:$_->{key})";
                                } else {
                                    $objhash{$objname}{$_->{key}} = $_->{value};
                                }
                            }
                        }
                    }
                    if ($foundinfo)
                    {
                        $objhash{$objname}{'objtype'} = 'site';
                    }
                }
                else
                {
                    my $rsp;
                    $rsp->{data}->[0] ="Could not read the \'$objname\' object from the \'site\' table.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);	
                }
            }
        } elsif ($objtype eq 'monitoring') {
            # need a special case for the monitoring table
            # 	- need to check the monsetting table for entries that contain
            #	 the same name as the monitoring table entry.
            my @TableRowArray = xCAT::DBobjUtils->getDBtable('monsetting');
            foreach my $objname (sort @{$type_obj{$objtype}}) {
                if (@TableRowArray) {
                    my $foundinfo = 0;
                    foreach (@TableRowArray) {                     
                        if ($_->{name} eq $objname ) {
                            if ($_->{key})
                            {
                                if (defined($_->{value}) ) {
                                    $foundinfo++;
                                    if ($verbose == 1) {
                                        $objhash{$objname}{$_->{key}} = "$_->{value}\t(Table:monsetting)";
                                    } else {
                                        $objhash{$objname}{$_->{key}} = $_->{value};
                                    }
                                }
                            }
                        }
                    }
                    if ($foundinfo)
                    {
                        $objhash{$objname}{'objtype'} = 'monitoring';
                    }
                }
                else
                {
                    my $rsp;
                    $rsp->{data}->[0] ="Could not read the \'$objname\' object from the \'monsetting\' table.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);	
                }
            }
        } elsif (($objtype eq 'auditlog') || ($objtype eq 'eventlog')) {
            # Special case for auditlog/eventlog
            # All the auditlog/eventlog attributes are in auditlog/eventlog table,
            # Do not need to read the table multiple times for each attribute.
            # The auditlog/eventlog is likely be very big over time,
            # performance is a big concern with the general logic
            my @TableRowArray = xCAT::DBobjUtils->getDBtable($objtype);
            foreach my $objname (sort @{$type_obj{$objtype}}) {
                if (@TableRowArray)
                {
                    my $foundinfo = 0;
                    foreach my $entry (@TableRowArray)
                    {
                        if ($entry->{recid} eq $objname)
                        {
                            foreach my $k (keys %{$entry})
                            {
                                # recid is the object name, do not need to be in the attributes list
                                if ($k eq 'recid') { next; }
                                if (defined($entry->{$k}) ) {
                                    $foundinfo++;
                                    if ($verbose == 1) {
                                        $objhash{$objname}{$k} = "$entry->{$k}\t(Table:$objtype - Key:$k)";
                                    } else {
                                        $objhash{$objname}{$k} = $entry->{$k};
                                    }
                                }
                            }
                            if ($foundinfo)
                            {
                                $objhash{$objname}{'objtype'} = $objtype;
                            }
                            # There should not be multiple entries with the same recid
                            last;
                        } # end if($entry->
                    } # end foreach my $entry
               } # end if(@TableTowArray
           } # end foreach my $objname
        } else {
            # get the object type decription from Schema.pm
            my $datatype = $xCAT::Schema::defspec{$objtype};
            # get the key to look for, for this object type
            my $objkey = $datatype->{'objkey'};

           # go through the list of valid attrs
           foreach my $this_attr (@{$datatype->{'attrs'}})
           {
                my $ent;
                my $attr = $this_attr->{attr_name};
    
                # skip the key attr  ???
                if ($attr eq $objkey)
                {
                    next;
                }
                # skip the attributes that does not needed for node type
                if ($getnodes) {
                    if (scalar(@attrs) > 0 && !grep(/^$attr$/, @attrs)) {
                        next;
                    } 
                }
 
                #  OK - get the info needed to access the DB table
                #   - i.e. table name, key name, attr names
    
                # need the actual table attr name corresponding
                #   to the object attr name
                #  ex. noderes.nfsdir
                my ($tab, $tabattr) = split('\.', $this_attr->{tabentry});
    
                foreach my $objname (sort @{$type_obj{$objtype}}) {
                    # get table lookup info from Schema.pm
                    #  !!!! some tables depend on the value of certain attrs
                    #   we need to look up attrs in the correct order or we will
                    #   not be able to determine what tables to look
                    #	in for some attrs.
                    if (exists($this_attr->{only_if}))
                    {
                         my ($check_attr, $check_value) = split('\=', $this_attr->{only_if});
                         # if the object value is not the value we need
                         #   to match then try the next only_if value
                         next if ( !($objhash{$objname}{$check_attr} =~ /\b$check_value\b/) );
                    }
                    
                    
                    $objhash{$objname}{'objtype'} = $objtype;
                    my %tabentry = ();
                    # def commands need to support multiple keys in one table
                    # the subroutine parse_access_tabentry is used for supporting multiple keys
                    my $rc = xCAT::DBobjUtils->parse_access_tabentry($objname, 
                                                                     $this_attr->{access_tabentry}, \%tabentry);
                    if ($rc != 0)
                    {
                         my $rsp;
                         $rsp->{data}->[0] =
                           "access_tabentry \'$this_attr->{access_tabentry}\' is not valid.";
                          xCAT::MsgUtils->message("E", $rsp, $::callback);
                         next;
                    }
                    #
                    # Only allow one table in the access_tabentry
                    # use multiple tables to look up tabentry does not make any sense
                    my $lookup_table = $tabentry{'lookup_table'};
                    my $intabhash = 0;
                    my $notsearched = 0;
                    foreach my $lookup_attr (keys %{$tabentry{'lookup_attrs'}})
                    {
                        # Check whether the attribute is already in %tabhash
                        # The %tabhash is for performance considerations
                        if ( ($lookup_attr eq 'node') && ($objtype eq 'node') ){ 
                            if (defined($tabhash{$lookup_table}{$objname}{$tabattr})) {
                                if ($verbose == 1)
                                {
                                    $objhash{$objname}{$attr} = "$tabhash{$lookup_table}{$objname}{$tabattr}\t(Table:$lookup_table - Key:$lookup_attr - Column:$tabattr)";
                                }
                                else
                                {
                                    $objhash{$objname}{$attr} = $tabhash{$lookup_table}{$objname}{$tabattr};
                                }
                                if (defined $chname_ref) {
                                    push @{$chname_ref->{$lookup_table}}, ($tabentry{'lookup_attrs'}, $lookup_attr);
                                }
                                $intabhash = 1;
                                last;
                            } elsif (! defined($tabhash{$lookup_table}{$objname}{"$tabattr"."_hassearched"})) {
                                $notsearched = 1;
                            } 
                        } else {
                            $notsearched = 1;
                        }
                    }

                    # Not in tabhash,
                    # Need to lookup the table
                    if ($intabhash == 0 && $notsearched == 1)
                    {
                        # look up attr values
                        my @rows = xCAT::DBobjUtils->getDBtable($lookup_table);
                        if (@rows)
                        {
                            foreach my $rowent (@rows)
                            {
                                my $match = 1;
                                my $matchedattr;
                                # Again, multiple keys support needs the "foreach"
                                foreach my $lookup_attr (keys %{$tabentry{'lookup_attrs'}})
                                {
                                    if ($rowent->{$lookup_attr} ne $tabentry{'lookup_attrs'}{$lookup_attr})
                                    {
                                        $match = 0;
                                        last;
                                    }
                                }
                                if ($match == 1)
                                {
                                     if ($verbose == 1)
                                     {
                                         my @lookup_attrs = keys %{$tabentry{'lookup_attrs'}};
                                         $objhash{$objname}{$attr} = "$rowent->{$tabattr}\t(Table:$lookup_table - Key: @lookup_attrs - Column:$tabattr)";
                                     }
                                     else 
                                     {
                                         $objhash{$objname}{$attr} = $rowent->{$tabattr};
                                     }
                                     if (defined $chname_ref) {
                                         push @{$chname_ref->{$lookup_table}}, ($tabentry{'lookup_attrs'}, (keys %{$tabentry{'lookup_attrs'}}) [0]);
                                     }
                                 } #end if ($match...
                            } #end foreach
                        } # end if (defined...
                    } #end if ($intabhash...
                }

            }
        }
        
    } #foreach my $objtype

    return %objhash;
}

#----------------------------------------------------------------------------

=head3   getDBtable

        Get a DB table, cache it , & return list of rows from the table.

        Arguments:
        Returns:
                undef - error
                @rows - of table
        Globals:
        Error:
        Example:

        call as follows
          my @TableRowArray= xCAT::DBobjUtils->getDBtable($tablename); 

        Comments:

=cut

#-----------------------------------------------------------------------------
sub getDBtable
{
    my ($class, $table) = @_;
    my @rows = [];

	# save this table info - in case this subr gets called multiple times
    # --nocache flag specifies not to use cahe
    if (grep(/^$table$/, @::foundTableList) && !$::opt_nc)
    {

        # already have this
        @rows = @{$::TableHash{$table}};

    }
    else
    {

    	# need to get info from DB
    	my $thistable = xCAT::Table->new($table, -create => 1, -autocommit => 0);
    	if (!$thistable)
    	{
        	return undef;
    	}

    	#@rows = $thistable->getTable;
	@rows = @{$thistable->getAllEntries()};

    	#   !!!! this routine returns rows even if the table is empty!!!!!!

		#  keep track of the fact that we checked this table
        #   - even if it's empty!
        push(@::foundTableList, $thistable->{tabname});

        @{$::TableHash{$table}} = @rows;

    	#$thistable->commit;

	} # end if not cached

   	if (@rows)
   	{
       	return @rows;
   	}
   	else
   	{
       	return undef;
    }
}

#----------------------------------------------------------------------------

=head3   setobjdefs

        Set the object definitions in the DB.
            - Handles the Schema lookup and updating the DB tables.

        Arguments:
        Returns:
                1 - error
                0 - OK
        Globals:
        Error:
        Example:

        To use:
		 	-create hash for objectname and object type
            	ex. $objhash{$object}{$attribute} = value;

			-then call as follows:
				if (xCAT::DBobjUtils->setobjdefs(\%objhash) != 0)

        Comments:

=cut

#-----------------------------------------------------------------------------
sub setobjdefs
{
    my ($class, $hash_ref) = @_;
    my %objhash = %$hash_ref;
    my %settableref;
    my $ret = 0;
    my %allupdates;
    my $setattrs=0;

    # get the attr=vals for these objects from the DB - if any
    #       - so we can figure out where to put additional attrs
    # The getobjdefs call was in the foreach loop,
    # it caused mkdef/chdef performance issue,
    # so it is moved out of the foreach loop

    my %DBhash;
    my @attrs;
    foreach my $objname (keys %objhash)
    {
        my $type = $objhash{$objname}{objtype};
        $DBhash{$objname} = $type;
        @attrs = keys %{$objhash{$objname}};
    }

    my %DBattrvals;
    %DBattrvals = xCAT::DBobjUtils->getobjdefs(\%DBhash, 0, \@attrs);

    # for each object figure out:
    #	- what tables to update
    #	- which table attrs correspond to which object attrs
    #	- what the keys are for each table
    # update the tables a row at a time
    foreach my $objname (keys %objhash)
    {

        # get attr=val that are set in the DB ??
        my $type = $objhash{$objname}{objtype};

		# handle the monitoring table as a special case !!!!!
        if ($type eq 'monitoring')
        {

            # Get the names of the attrs stored in monitoring table
            # get the object type decription from Schema.pm
            my $datatype = $xCAT::Schema::defspec{$type};
            
            #  get a list of valid attr names
            #  for this type object
            my @attrlist;
            foreach my $entry (@{$datatype->{'attrs'}})
            {
            	   push(@attrlist, $entry->{'attr_name'});
            }

            # open the tables (monitoring and monsetting)
            my $montable = xCAT::Table->new('monitoring', -create => 1, -autocommit => 0);
            if (!$montable)
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not set the \'$montable\' table.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }
            # open the table
            my $monsettable = xCAT::Table->new('monsetting', -create => 1, -autocommit => 0);
            if (!$monsettable)
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not set the \'$monsettable\' table.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }

            my %keyhash; 
            my %updates;
            
            foreach my $attr (keys %{$objhash{$objname}})
            {
                my $val;
                if ($attr eq 'objtype')
                {
                    next;
                }

                # determine the value if we have plus or minus
                if ($::plus_option)
                {
                    # add new to existing - at the end - comma separated
                    if (defined($DBattrvals{$objname}{$attr}))
                    {
                        $val = "$DBattrvals{$objname}{$attr},$objhash{$objname}{$attr}";
                    }
                    else
                    {
                        $val = "$objhash{$objname}{$attr}";
                    }
                }
                elsif ($::minus_option)
                {
                    # remove the specified list of values from the current
                    #   attr values.
                    if ($DBattrvals{$objname}{$attr})
                    {
                        # get the list of attrs to remove
                        my @currentList = split(/,/, $DBattrvals{$objname}{$attr});
                        my @minusList   = split(/,/, $objhash{$objname}{$attr});

                        # make a new list without the one specified
                        my $first = 1;
                        my $newlist;
                        foreach my $i (@currentList)
                        {
                            chomp $i;
                            if (!grep(/^$i$/, @minusList))
                            {
                                # set new groups list for node
                                if (!$first)
                                {
                                    $newlist .= ",";
                                }
                                $newlist .= $i;
                                $first = 0;
                            }
                        }
                        $val = $newlist;
                    }
                }
                else
                {
                    #just set the attr to what was provided! - replace
                    $val = $objhash{$objname}{$attr};
                }

                if (grep(/^$attr$/, @attrlist)) {
                    # if the attr belong in the monitoring tabel
                    %keyhash=(name=>$objname);
                    %updates=($attr=>$val);
                    $montable->setAttribs(\%keyhash, \%updates);
                } else {
                    # else it belongs in the monsetting table
                    $keyhash{name} = $objname;
                    $keyhash{key} = $attr;
                    $updates{value} = $val;
                    $monsettable->setAttribs(\%keyhash, \%updates);
                }
            }
                
            $montable->commit;
            $monsettable->commit;
            next;
        } #if ($type eq 'monitoring')

        # handle the site table as a special case !!!!!
        if ($type eq 'site')
        {
            # open the table
            my $thistable =
            xCAT::Table->new('site', -create => 1, -autocommit => 0);
            if (!$thistable)
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not set the \'$thistable\' table.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }

            foreach my $attr (keys %{$objhash{$objname}})
            {
                if ($attr eq 'objtype')
                {
                    next;
                }

                my %keyhash;
                $keyhash{key} = $attr;

                my $val;
                if ($::plus_option)
                {
                    # add new to existing - at the end - comma separated
                    if (defined($DBattrvals{$objname}{$attr}))
                    {
                        $val =
                          "$DBattrvals{$objname}{$attr},$objhash{$objname}{$attr}";
                    }
                    else
                    {
                        $val = "$objhash{$objname}{$attr}";
                    }
                }
                elsif ($::minus_option)
                {
                    # remove the specified list of values from the current
                    #   attr values.
                    if ($DBattrvals{$objname}{$attr})
                    {
                        # get the list of attrs to remove
                        my @currentList = split(/,/, $DBattrvals{$objname}{$attr});
                        my @minusList   = split(/,/, $objhash{$objname}{$attr});

                        # make a new list without the one specified
                        my $first = 1;
                        my $newlist;
                        foreach my $i (@currentList)
                        {
                            chomp $i;
                            if (!grep(/^$i$/, @minusList))
                            {
                                # set new groups list for node
                                if (!$first)
                                {
                                    $newlist .= ",";
                                }
                                $newlist .= $i;
                                $first = 0;
                            }
                        }
                        $val = $newlist;
                    }
                }
                else
                {

                    #just set the attr to what was provided! - replace
                    $val = $objhash{$objname}{$attr};

                }

                if ( $val eq "") { # delete the line
                    $thistable->delEntries(\%keyhash);
                }  else { # change the attr
                
                my %updates;
                $updates{value} = $val;
                
                my ($rc, $str) = $thistable->setAttribs(\%keyhash, \%updates);
                if (!defined($rc))
                {
                    if ($::verbose)
                    {
                        my $rsp;
                        $rsp->{data}->[0] =
                        	"Could not set the \'$attr\' attribute of the \'$objname\' object in the xCAT database.";
                        $rsp->{data}->[1] =
                        	"Error returned is \'$str->errstr\'.";
                        xCAT::MsgUtils->message("I", $rsp, $::callback);
                    }
                        $ret = 1;
                    }
                }

            }

            $thistable->commit;

            next;
        } #if ($type eq 'site')



        #
        #  handle the rest of the object types
        #

        # get the object type decription from Schema.pm
        my $datatype = $xCAT::Schema::defspec{$type};

		# get the object key to look for, for this object type
        my $objkey = $datatype->{'objkey'};

        #  get a list of valid attr names
        #     for this type object
        my %attrlist;
        foreach my $entry (@{$datatype->{'attrs'}})
        {
            #push(@{$attrlist{$type}}, $entry->{'attr_name'});
            $attrlist{$type}{$entry->{'attr_name'}} = 1;
        }

        my @attrprovided=();

        # check FINALATTRS to see if all the attrs are valid
        foreach my $attr (keys %{$objhash{$objname}})
        {

            if ($attr eq $objkey)
            {
                next;
            }

            if ($attr eq "objtype")
            {
                # objtype not stored in object definition
                next;
            }

            if (!defined($attrlist{$type}{$attr}))
            {
                if ($::verbose)
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "\'$attr\' is not a valid attribute for type \'$type\'.";
                    $rsp->{data}->[1] = "Skipping to the next attribute.";
                    xCAT::MsgUtils->message("I", $rsp, $::callback);
                }
                next;
            }
            push(@attrprovided, $attr); 
        }

        #   we need to figure out what table to
        #      store each attr
        #   And we must do this in the order given in defspec!!

        my @setattrlist=();
        my %checkedattrs;
        my $invalidattr;

        foreach my $this_attr (@{$datatype->{'attrs'}})
        {
            my %keyhash;
            my %updates;
            my %tabentry;
            my ($lookup_table, $lookup_attr, $lookup_data);
            my $attr_name = $this_attr->{attr_name};

            if ($attr_name eq $objkey)
            {
                next;
            }

            # if we have a value for this attribute then process it
            #   - otherwise go to the next attr
            if (defined($objhash{$objname}{$attr_name}))
            {
                # check the defspec to see where this attr goes

                # the table for this attr might depend on the
                #       value of some other attr
                # need to check the only_if entries to find one where the
                #       other attr value matches what we have
                #       ex. like if I want to set hdwctrlpoint I will have
                #               to match the right value for mgtmethod
                if (exists($this_attr->{only_if}))
                {
                    my ($check_attr, $check_value) =
                      split('\=', $this_attr->{only_if});

                    # if my attr value for the attr to check doesn't
                    #   match this then try the next one
                    # ex. say I want to set hdwctrlpoint, the table
                    #   will depend on the mgtmethod attr - so I need
                    #   to find the 'only_if' that matches the value
                    #   specified for that attr (ex. mgtmethod=hmc)

                    # need to check the attrs we are setting for the object
                    #   as well as the attrs for this object that may be
                   	#   already set in DB

                    if ( !($objhash{$objname}{$check_attr})  && !($DBattrvals{$objname}{$check_attr}) ) {
                        # if I didn't already check for this attr
                        my $rsp;
                        if (!defined($checkedattrs{$attr_name})) {
                            push @{$rsp->{data}}, "Cannot set the \'$attr_name\' attribute unless a value is provided for \'$check_attr\'.";

                            foreach my $tmp_attr (@{$datatype->{'attrs'}}) {
                                my $attr = $tmp_attr->{attr_name};
                                if ($attr eq $check_attr) {
                                    my ($tab, $at) = split(/\./, $tmp_attr->{tabentry});
                                    my $schema = xCAT::Table->getTableSchema($tab);
                                    my $desc = $schema->{descriptions}->{$at};
                                    push @{$rsp->{data}}, "$check_attr => $desc";
                                }
                            }
                        }
                        xCAT::MsgUtils->message("I", $rsp, $::callback);
                        $checkedattrs{$attr_name} = 1;
                        if ( $invalidattr->{$attr_name}->{valid} ne 1 ) {
                            $invalidattr->{$attr_name}->{valid} = 0;
                            $invalidattr->{$attr_name}->{condition} = "\'$check_attr=$check_value\'";
                        }

                        next;
                    }

                    if ( !($objhash{$objname}{$check_attr} =~ /\b$check_value\b/) && !($DBattrvals{$objname}{$check_attr}  =~ /\b$check_value\b/) )
                    {
                        if ( $invalidattr->{$attr_name}->{valid} ne 1 ) {
                            $invalidattr->{$attr_name}->{valid} = 0;
                            $invalidattr->{$attr_name}->{condition} = "\'$check_attr=$check_value\'";

                        }

                        next;
                    }
                }
                $invalidattr->{$attr_name}->{valid} = 1;

                #  get the info needed to write to the DB table
                #
                # get the actual attr name to use in the table
                #    - may be different then the attr name used for the object.
                my $ntab;
                ($ntab, $::tabattr) = split('\.', $this_attr->{tabentry});

                my $rc = xCAT::DBobjUtils->parse_access_tabentry($objname, 
                                                                $this_attr->{access_tabentry}, \%tabentry);
                if ($rc != 0)
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "access_tabentry \'$this_attr->{access_tabentry}\' is not valid.";
                     xCAT::MsgUtils->message("E", $rsp, $::callback);
                     next;
                }
                $lookup_table = $tabentry{'lookup_table'};
                # Set the lookup criteria for this attribute into %allupdates
                # the key is 'lookup_attrs'
                foreach my $lookup_attr (keys %{$tabentry{'lookup_attrs'}})
                {
                    $allupdates{$lookup_table}{$objname}{$attr_name}{'lookup_attrs'}{$lookup_attr} 
                                             =$tabentry{'lookup_attrs'}{$lookup_attr};
                }
            }
            else
            {
                next;
            }

            my $val;
            my $delim = ',';
            if(($type eq 'group') && ($DBattrvals{$objname}{'grouptype'} eq 'dynamic')) 
            {
                # dynamic node group selection string use "::" as delimiter
                $delim = '::';
            }
            
            if ($::plus_option)
            {

                # add new to existing - at the end - comma separated
                if (defined($DBattrvals{$objname}{$attr_name}))
                {
                    # add the attr into the list if it's not already in the list!
                    # and avoid the duplicate values
                    my @DBattrarray = split(/$delim/, $DBattrvals{$objname}{$attr_name});
                    my @objhasharray = split(/$delim/, $objhash{$objname}{$attr_name});
                    foreach my $objattr (@objhasharray)
                    {
                        if (!grep(/^\Q$objattr\E$/, @DBattrarray))
                        {
                            push @DBattrarray, $objattr;
                        }
                     }
                     $val = join($delim, @DBattrarray);
                }
                else
                {
                    $val = "$objhash{$objname}{$attr_name}";
                }

            }
            elsif ($::minus_option)
            {

                # remove the specified list of values from the current
                #	attr values.
                if ($DBattrvals{$objname}{$attr_name})
                {

                    # get the list of attrs to remove
                    my @currentList =
                      split(/$delim/, $DBattrvals{$objname}{$attr_name});
                    my @minusList = split(/$delim/, $objhash{$objname}{$attr_name});

                    foreach my $em (@minusList)
                    {
                        if (!(grep {$_ eq $em} @currentList))
                        {
                            if (($::opt_t eq 'group') && ($DBattrvals{$objname}{'grouptype'} ne 'dynamic'))
                            {
                                my $rsp;
			        $rsp->{data}->[0] = "$objname is not a member of \'$em\'.";
			        xCAT::MsgUtils->message("W", $rsp, $::callback);
                             } else {
                                my $rsp;
			        $rsp->{data}->[0] = "$em is not in the attribute of \'$attr_name\' for the \'$objname\' definition.";
			        xCAT::MsgUtils->message("W", $rsp, $::callback);
                             }
                        }
                    }
                    # make a new list without the one specified
                    my $first = 1;
                    my $newlist;
                    foreach my $i (@currentList)
                    {
                        chomp $i;
                        if (!grep(/^\Q$i\E$/, @minusList))
                        {

                            # set new list for node
                            if (!$first)
                            {
                                $newlist .= "$delim";
                            }
                            $newlist .= $i;
                            $first = 0;
                        }
                    }
                    $val = $newlist;
                }

            }
            else
            {

                #just set the attr to what was provided! - replace
                $val = $objhash{$objname}{$attr_name};

            }

            # Set the values into %allupdates
            # the key is 'tabattrs'
            $allupdates{$lookup_table}{$objname}{$attr_name}{'tabattrs'}{$::tabattr} = $val;
            $setattrs=1;
            
            push(@setattrlist, $attr_name);

        }    # end - foreach attribute

        my $rsp;
        foreach my $att (keys %$invalidattr) {
            if ( $invalidattr->{$att}->{valid} ne 1) {
my $tt = $invalidattr->{$att}->{valid};
                push @{$rsp->{data}}, "Cannot set the attr=\'$att\' attribute unless $invalidattr->{$att}->{condition}.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
            }
        }


# TODO - need to get back to this
if (0) {
		#
		#  check to see if all the attrs got set
		#

		my @errlist;
		foreach $a (@attrprovided)
        {	
			#  is this attr was not set then add it to the error list
			if (!grep(/^$a$/, @setattrlist))
			{			
				push(@errlist, $a);
				$ret = 2;
			}

		}
		if ($ret == 2) {
			my $rsp;
			$rsp->{data}->[0] = "Could not set the following attributes for the \'$objname\' definition in the xCAT database: \'@errlist\'";
			xCAT::MsgUtils->message("E", $rsp, $::callback);
		}

}

    }    # end - foreach object
#==========================================================#
#%allupdates structure:
# for command: chdef -t node -o node1 groups=all 
#              usercomment=ddee passwd.HMC=HMC 
#              passwd.admin=cluster passwd.general=abc123
# the %allupdates will be:
#0  'ppcdirect'
#1  HASH(0x12783d30)
#   'node1' => HASH(0x12783cc4)
#      'passwd.HMC' => HASH(0x12783ed4)
#         'lookup_attrs' => HASH(0x12783f70)
#            'hcp' => 'node1'
#            'username' => 'HMC'
#         'tabattrs' => HASH(0x12783e8c)
#            'password' => 'HMC'
#      'passwd.admin' => HASH(0x12783c64)
#         'lookup_attrs' => HASH(0x12784000)
#            'hcp' => 'node1'
#            'username' => 'admin'
#         'tabattrs' => HASH(0x12783f64)
#            'password' => 'cluster'
#      'passwd.general' => HASH(0x12783a6c)
#         'lookup_attrs' => HASH(0x12784198)
#            'hcp' => 'node1'
#            'username' => 'general'
#         'tabattrs' => HASH(0x12783aa8)
#            'password' => 'abc123'
#2  'nodelist'
#3  HASH(0x127842b8)
#   'node1' => HASH(0x12784378)
#      'groups' => HASH(0x12784090)
#         'lookup_attrs' => HASH(0x127844bc)
#            'node' => 'node1'
#         'tabattrs' => HASH(0x1277fd34)
#            'groups' => 'all'
#      'usercomment' => HASH(0x12784318)
#         'lookup_attrs' => HASH(0x12780550)
#            'node' => 'node1'
#         'tabattrs' => HASH(0x127842f4)
#            'comments' => 'ddee'
#=================================================================#
	# now set the attribute values in the tables
	#   - handles all except site, monitoring & monsetting for now
	if ($setattrs) {
            foreach my $table (keys %allupdates) {
            
            # get the keys for this table
            my $schema = xCAT::Table->getTableSchema($table);
            my $keys = $schema->{keys};
            
            # open the table
            my $thistable = xCAT::Table->new($table, -create => 1, -autocommit => 0);
            if (!$thistable) {
            	my $rsp;
            	$rsp->{data}->[0] = "Could not set the \'$thistable\' table.";
            	xCAT::MsgUtils->message("E", $rsp, $::callback);
            	return 1;
            }
            
            # Special case for the postscripts table
            # Does not set the postscripts to the postscripts table
            # if the postscripts already in xcatdefaults
            # for code logic, it will be clearer to put the special case into defch,
            # but putting it into defch will introduce additional table access for postscripts table.
            # accessing table is time consuming.
            if ($table eq "postscripts") {
                my $xcatdefaultsps;
                my $xcatdefaultspbs;
                my @TableRowArray = xCAT::DBobjUtils->getDBtable('postscripts');
                if (@TableRowArray)
                {
                    foreach my $tablerow (@TableRowArray)
                    {
                        if(($tablerow->{node} eq 'xcatdefaults') && !($tablerow->{disable}))
                        {
                            $xcatdefaultsps = $tablerow->{postscripts};
                            $xcatdefaultspbs = $tablerow->{postbootscripts};
                            last;
                        }
                    }
                }
                my @xcatdefps = split(/,/, $xcatdefaultsps);
                my @xcatdefpbs = split(/,/, $xcatdefaultspbs);
                foreach my $obj(keys %{$allupdates{$table}}) {
                    if ($obj eq 'xcatdefaults') {
                        #xcatdefaults can be treated as a node?
                        next;
                    }
                    my @newps;
                    if (defined($allupdates{$table}{$obj}{'postscripts'}) 
                                   && defined($allupdates{$table}{$obj}{'postscripts'}{'tabattrs'}{'postscripts'})) {
                        foreach my $tempps (split(/,/, $allupdates{$table}{$obj}{'postscripts'}{'tabattrs'}{'postscripts'})) {
                            if (grep(/^$tempps$/, @xcatdefps)) {
                                 my $rsp;
                                 $rsp->{data}->[0] = "$obj: postscripts \'$tempps\' is already included in the \'xcatdefaults\'.";
                                 xCAT::MsgUtils->message("E", $rsp, $::callback);
                             } else {
                                 push @newps, $tempps;
                             }
                        }
                        $allupdates{$table}{$obj}{'postscripts'}{'tabattrs'}{'postscripts'} = join(',', @newps);
                    }
                    my @newpbs;
                    if (defined($allupdates{$table}{$obj}{'postbootscripts'}) 
                                     && defined($allupdates{$table}{$obj}{'postbootscripts'}{'tabattrs'}{'postbootscripts'})) {
                        foreach my $temppbs (split(/,/, $allupdates{$table}{$obj}{'postbootscripts'}{'tabattrs'}{'postbootscripts'})) {
                            if (grep(/^$temppbs$/, @xcatdefpbs)) {
                                my $rsp;
                                $rsp->{data}->[0] = "$obj: postbootscripts \'$temppbs\' is already included in the \'xcatdefaults\'.";
                                xCAT::MsgUtils->message("E", $rsp, $::callback);
                            } else {
                                push @newpbs, $temppbs;
                            }
                        }
                        $allupdates{$table}{$obj}{'postbootscripts'}{'tabattrs'}{'postbootscripts'} = join(',', @newpbs);
                     }
                }
            }

            my $commit_manually = 0;
            my %node_updates;
            OBJ: foreach my $obj (keys %{$allupdates{$table}}) {
                my %keyhash;
                my %updates;
                my $firsttime = 1;
                ROW: foreach my $row (keys %{$allupdates{$table}{$obj}}) {
                    # make sure we have a value for each key
                    foreach my $k (@$keys) {
                        if (!$allupdates{$table}{$obj}{$row}{'lookup_attrs'}) {
                            my $rsp;
                            $rsp->{data}->[0] = "\nMissing required attribute values for the \'$obj\' object. The required attributes are: @$keys";
                            xCAT::MsgUtils->message("E", $rsp, $::callback);
                            $ret = 1;
                            next ROW;
                        }
                    }
                    
                    if ($firsttime) {
                        # lookup keys in %hashkey
                        # ex. $keyhash{'hcp'} = node1
                        foreach my $key (keys %{$allupdates{$table}{$obj}{$row}{'lookup_attrs'}}) {
                            $keyhash{$key} = $allupdates{$table}{$obj}{$row}{'lookup_attrs'}{$key};
                        }
                        $firsttime = 0;
                    } else {
                        # check if the look_attrs is the same as the %keyhash
                        foreach my $key (keys %{$allupdates{$table}{$obj}{$row}{'lookup_attrs'}}) {
                            # The lookup_attrs can be different for tables with more than one keys such as ppcdirect
                            if ((scalar(keys %keyhash) != scalar(keys %{$allupdates{$table}{$obj}{$row}{'lookup_attrs'}})) 
                               || !defined($keyhash{$key}) 
                               ||($keyhash{$key} ne $allupdates{$table}{$obj}{$row}{'lookup_attrs'}{$key})) {
                                # different keys, set the existing attributes into database
                                # update the %keyhash and clean up the %updates hash
                                if (%updates) {
                                    $commit_manually = 1;
                                    my ($rc, $str) = $thistable->setAttribs(\%keyhash, \%updates);
                                }
                                foreach my $key (keys %{$allupdates{$table}{$obj}{$row}{'lookup_attrs'}}) {
                                    $keyhash{$key} = $allupdates{$table}{$obj}{$row}{'lookup_attrs'}{$key};
                                }
                                %updates = ();
                            }
                        }
                    }
                    
                    # set values in %updates
                    # ex. $updates{'groups'} = 'all,lpar'
                    foreach my $attr (keys %{$allupdates{$table}{$obj}{$row}{'tabattrs'}}) {
                        if (scalar(keys %keyhash) == 0 && $keyhash{'node'} && $keyhash{'node'} eq "node") {
                            $node_updates{$obj}{$attr} = $allupdates{$table}{$obj}{$row}{'tabattrs'}{$attr};
                        } else {
                            $updates{$attr} = $allupdates{$table}{$obj}{$row}{'tabattrs'}{$attr};
                        }
                    }

                } #end foreach my $row
                # only uses the setAttribs to set attribute one by one when the obj type is NOT 'node'
                if (%updates) {
                    $commit_manually = 1;
                    my ($rc, $str) = $thistable->setAttribs(\%keyhash, \%updates);
                }
            } #end foreach my $obj
            if ($commit_manually) {
                $thistable->commit;
            }
            if (%node_updates) {
                $thistable->setNodesAttribs(\%node_updates);
            }
        } #end forach my $table
    }
    return $ret;
}

#----------------------------------------------------------------------------

=head3   rmobjdefs

        Remove object definitions from the DB.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

		To use create hash for object name and object type
            ex. $objhash{$obj} = $type;
        - then call as follows:
			xCAT::DBobjUtils->rmobjdefs(\%objhash);

        Comments:

=cut

#-----------------------------------------------------------------------------
sub rmobjdefs
{
    my ($class, $hash_ref) = @_;

    my %tablehash;

    my %typehash = %$hash_ref;

    # get the attr=vals for these objects so we know how to
    #   find what tables have to be modified

    foreach my $objname (sort (keys %typehash))
    {
        my $type = $typehash{$objname};

        # special handling for site table
        if ($type eq 'site')
        {
            my %DBattrvals = xCAT::DBobjUtils->getobjdefs(\%typehash);
            my $thistable =
              xCAT::Table->new('site', -create => 1, -autocommit => 0);
            my %keyhash;
            foreach my $attr (keys %{$DBattrvals{$objname}})
            {

                # ex.  key = attr
                $keyhash{key} = $attr;

                $thistable->delEntries(\%keyhash);

            }
            $thistable->commit();
            next;
        }

        # get the object type decription from Schema.pm
        my $datatype = $xCAT::Schema::defspec{$type};

        # go through the list of valid attrs
        #  - need to delete the row with a $key value of $objname from $table
        #  - make a hash containing $delhash{$table}{$key}= $objname
        foreach my $this_attr (@{$datatype->{'attrs'}})
        {
            my $attr = $this_attr->{attr_name};

            # get table lookup info from Schema.pm
            # def commands need to support multiple keys in one table
            # the subroutine parse_access_tabentry is used for supporting multiple keys
            my %tabentry = ();
            my $rc = xCAT::DBobjUtils->parse_access_tabentry($objname, $this_attr->{access_tabentry}, \%tabentry);
            if ($rc != 0)
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "access_tabentry \'$this_attr->{access_tabentry}\' is not valid.";
                 xCAT::MsgUtils->message("E", $rsp, $::callback);
                 next;
            }

            # Only allow one table in the access_tabentry
            # use multiple tables to look up tabentry does not make any sense
            my $lookup_table = $tabentry{'lookup_table'};
            # The attr_name is the *def attribute name instead of db column
            my $attr_name = $this_attr->{'attr_name'};
            # we'll need table name, object name, attribute name and the lookup entries
            # put this info in a hash - we'll process it later - below
            foreach my $lookup_attr (keys %{$tabentry{'lookup_attrs'}})
            {
                $tablehash{$lookup_table}{$objname}{$attr_name}{$lookup_attr} 
                                    = $tabentry{'lookup_attrs'}{$lookup_attr};
            }

        }
    }
#=============================================#
# The tablehash looks like this
 # DB<5> x %tablehash
 # 'bootparams'
 # HASH(0x1280828c)
 #  'node1' => HASH(0x127bca50)
 #     'addkcmdline' => HASH(0x127fb114)
 #        'node' => 'node1'
 #     'initrd' => HASH(0x127bcb40)
 #        'node' => 'node1'
 #     'kcmdline' => HASH(0x127fb24c)
 #        'node' => 'node1'
 #     'kernel' => HASH(0x127b2e80)
 #        'node' => 'node1'
 #  'testfsp' => HASH(0x1280e71c)
 #     'addkcmdline' => HASH(0x1280e7a0)
 #        'node' => 'testfsp'
 #     'initrd' => HASH(0x1280e740)
 #        'node' => 'testfsp'
 #     'kcmdline' => HASH(0x1280e77c)
 #        'node' => 'testfsp'
 #     'kernel' => HASH(0x1280e758)
 #        'node' => 'testfsp'
 #...
 # 'ppcdirect'
 # HASH(0x1278fe1c)
 #  'node1' => HASH(0x12808370)
 #     'passwd.HMC' => HASH(0x128083e8)
 #        'hcp' => 'node1'
 #        'username' => 'HMC'
 #     'passwd.admin' => HASH(0x128081c0)
 #        'hcp' => 'node1'
 #        'username' => 'admin'
 #     'passwd.general' => HASH(0x128075d8)
 #        'hcp' => 'node1'
 #        'username' => 'general'
 #  'testfsp' => HASH(0x12790620)
 #     'passwd.HMC' => HASH(0x1280ee84)
 #        'hcp' => 'testfsp'
 #        'username' => 'HMC'
 #     'passwd.admin' => HASH(0x128082f8)
 #        'hcp' => 'testfsp'
 #        'username' => 'admin'
 #     'passwd.general' => HASH(0x1280843c)
 #        'hcp' => 'testfsp'
 #        'username' => 'general'
 #...
##=========================================================#
    # now for each table - clear the entry
    foreach my $table (keys %tablehash)
    {
        my @all_keyhash;

        my $thistable =
          xCAT::Table->new($table, -create => 1, -autocommit => 0);

        foreach my $obj (keys %{$tablehash{$table}}) {
            my %keyhash;
            foreach my $attr (keys %{$tablehash{$table}{$obj}})
            {
                foreach my $key (keys %{$tablehash{$table}{$obj}{$attr}})
                {

                    #multiple keys support
                    if (defined($keyhash{$key}) && ($keyhash{$key} ne $tablehash{$table}{$obj}{$attr}{$key}))
                    {
                        my %tmpkeyhash;
                        # copy hash
                        foreach my $hashkey (keys %keyhash)
                        {
                            $tmpkeyhash{$hashkey} = $keyhash{$hashkey};
                        }
                        push @all_keyhash, \%tmpkeyhash;
                        #$thistable->delEntries(\@all_keyhash);
                    }
                    # ex. $keyhash{node}=c68m3hvp01
                    $keyhash{$key} = $tablehash{$table}{$obj}{$attr}{$key};
                }
            }
            push @all_keyhash, \%keyhash;
        }
        # ex. delete the c68m3hvp01 entry of the node column in the
        #       nodelist table
        $thistable->delEntries(\@all_keyhash);

        $thistable->commit();
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   readFileInput

        Process the command line input piped in from a file.
		 	(Support stanza or xml format.)

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Error:
        Example:

        Comments:
			Set @::fileobjtypes, @::fileobjnames, %::FILEATTRS
				(i.e.- $::FILEATTRS{objname}{attr}=val)

=cut

#-----------------------------------------------------------------------------
sub readFileInput
{
    my ($class, $filedata) = @_;
	my ($objectname, $junk1, $junk2);

    @::fileobjnames = ();

    my @lines = split /\n/, $filedata;

    my $header = $lines[0];

    # to do
    #if ($header =~/<xCAT data object stanza file>/) {
    # do stanza file parsing
    # } elsis ($header =~/<xCAT data object XML file>/) {
    # do XML parsing
    #}

    my $look_for_colon = 1;    # start with first line that has a colon
	my $objtype;

    foreach my $l (@lines)
    {

        # skip blank and comment lines
        next if ($l =~ /^\s*$/ || $l =~ /^\s*#/);

        # see if it's a stanza name
        if (grep(/:\s*$/, $l))
        {

            $look_for_colon = 0;    # ok - we have a colon

            # Remove any trailing whitespace
            $l =~ s/\s*$//;

            # IPv6 network names could be something like fd59::/64
            # Use all the characters before the last ":" as the object name
            # .* means greedy regular expression
            $l =~ /^(.*):(.*?)$/;
            ($objectname, $junk2) = ($1, $2);

            # if $junk2 is defined or there's an = 
            if ($junk2 || grep(/=/, $objectname))
            {

                # error - invalid header $line in node definition file
                #         skipping to next node stanza
                # Skipping to the next valid header.
                $look_for_colon++;
                next;
            }

            $objectname =~ s/^\s*//;    # Remove any leading whitespace
            $objectname =~ s/\s*$//;    # Remove any trailing whitespace

            #  could have different default stanzas for different object types

            if ($objectname =~ /default/)
            {

                ($junk1, $objtype) = split(/-/, $objectname);

                if ($objtype)
                {
                    $objectname = 'default';
                }

                next;
            }

            push(@::fileobjnames, $objectname);

        }
        elsif (($l =~ /^\s*(.*?)\s*=\s*(.*)\s*/) && (!$look_for_colon))
        {
            my $attr = $1;
            my $val  = $2;
            $attr =~ s/^\s*//;    # Remove any leading whitespace
            $attr =~ s/\s*$//;    # Remove any trailing whitespace
            $val  =~ s/^\s*//;
            $val  =~ s/\s*$//;

            # remove spaces and quotes so createnode won't get upset
            $val =~ s/^\s*"\s*//;
            $val =~ s/\s*"\s*$//;

            if ($objectname eq "default")
            {

                # set the default for this attribute
                $::defAttrs{$objtype}{$attr} = $val;

            }
            else
            {

                # set the value in the hash for this object
                $::FILEATTRS{$objectname}{$attr} = $val;

                # if the attr being set is "objtype" then check
                # 	to see if we have any defaults set for this type
                # the objtype should be the first etntry in each stanza
                #	so after we set the defaults they will be overwritten
                #	by any values that appear in the rest of the stanza
                if ($attr eq 'objtype')
                {
                    push(@::fileobjtypes, $val);

                    #  $val will be the object type ex. site, node etc.
                    foreach my $a (keys %{$::defAttrs{$val}})
                    {

                        # set the default values for this object hash
                        $::FILEATTRS{$objectname}{$a} = $::defAttrs{$val}{$a};
                    }
                }
            }

        }
        else
        {

            # error - invalid line in node definition file
            $look_for_colon++;
        }

    }    # end while - go to next line

    return 0;

}

#----------------------------------------------------------------------------

=head3   getGroupMembers

        Get the list of members for the specified group.

        Arguments:
        Returns:
            undef - error
            $members - comma-separated list of group members
        Globals:
        Error:
        Example:
			To use:
            - create hash for objectname and and attr values  (need group 
				name (object), and grouptype  & members attr values at a
				minimum.)
			
                ex. $objhash{$obj}{$attr} = value;

            - then call as follows:
                xCAT::DBobjUtils->getGroupMembers($objectname, \%objhash);

        Comments:

=cut

#-----------------------------------------------------------------------------
sub getGroupMembers
{
    my ($class, $objectname, $hash_ref) = @_;

    my $members;

    my %objhash = %$hash_ref;

    # set 'static' as the dafault of nodetype
    if (!defined($objhash{$objectname}{'grouptype'}) ||
          $objhash{$objectname}{'grouptype'} eq "") {
        $objhash{$objectname}{'grouptype'} = 'static';
    }

    if ($objhash{$objectname}{'grouptype'} eq 'static')
    {

        my $table = "nodelist";

        my @TableRowArray = xCAT::DBobjUtils->getDBtable($table);

        my $first = 1;
        foreach (@TableRowArray)
        {

            # if find the group name in the "groups" attr value then add the
            #	 node name to the member list
            #if ($_->{'groups'} =~ /$objectname/)

            my @nodeGroupList = split(',', $_->{'groups'});
            if (grep(/^$objectname$/, @nodeGroupList))

            {
                chomp($_->{'node'});
                if (!$first)
                {
                    $members .= ",";
                }
                $members .= $_->{'node'};
                $first = 0;
            }
        }

    }
    elsif ($objhash{$objectname}{'grouptype'} eq 'dynamic')
    {

        # find all nodes that satisfy the criteria specified in "wherevals"
        #	value
        my %whereHash;
        my %tabhash;

        # remove spaces and quotes so createnode won't get upset
        #$val =~ s/^\s*"\s*//;
        #$val =~ s/\s*"\s*$//;

        my @tmpWhereList = split('::', $objhash{$objectname}{'wherevals'});
        my $rc = xCAT::Utils->parse_selection_string(\@tmpWhereList, \%whereHash);
        if ($rc != 0)
        {
            my $rsp;
            $rsp->{data}->[0] =
              "The \'-w\' option has an incorrect attr*val pair.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
        }

        # see what nodes have these attr=values
        # get a list of all nodes
        my @tmplist = xCAT::DBobjUtils->getObjectsOfType('node');

        # create a hash of obj names and types
		my %tmphash;
        foreach my $n (@tmplist)
        {
            $tmphash{$n} = 'node';
        }

        # Only get the specific attributes of the node
        my @whereattrs = keys %whereHash;
        my %nodeattrhash = xCAT::DBobjUtils->getobjdefs(\%tmphash, 0, \@whereattrs);

        # The attribute 'node' can be used as a key of selection string,
        # however, the 'node' attribute is not included in the getobjdefs hash
        foreach my $objname (keys %nodeattrhash)
        {
            $nodeattrhash{$objname}{'node'} = $objname;
        }
        my $first = 1;
        foreach my $objname (keys %nodeattrhash)
        {
            if (xCAT::Utils->selection_string_match(\%nodeattrhash, $objname, \%whereHash))
            {
                chomp($objname);
                if (!$first)
                {
                    $members .= ",";
                }
                $members .= $objname;
                $first = 0;
            }
        }

    }
    return $members;
}

#----------------------------------------------------------------------------

=head3   getNetwkInfo

        Get the network info from the database for a list of nodes.

        Arguments:
        Returns:
                undef
                hash ref - ex. $nethash{nodename}{networks attr name} = value
        Globals:
        Error:
        Example:

                %nethash = xCAT::DBobjUtils->getNetwkInfo(\@targetnodes);

		Comments:

=cut

#-----------------------------------------------------------------------------
sub getNetwkInfo
{
	my ($class, $ref_nodes) = @_;
	my @nodelist    = @$ref_nodes;

	my %nethash;
	my @attrnames;

	# get the current list of network attrs (networks table columns)
    my $datatype = $xCAT::Schema::defspec{'network'};
	foreach my $a (@{$datatype->{'attrs'}}) {
		my $attr = $a->{attr_name};
		push(@attrnames, $attr);
	}

	# read the networks table
	my @TableRowArray = xCAT::DBobjUtils->getDBtable('networks');
	if (! @TableRowArray)
    {
		return undef;
	}

	# for each node - get the network info
	foreach my $node (@nodelist)
    {

		# get, check, split the node IP
		my $IP = xCAT::NetworkUtils->getipaddr($node);
		chomp $IP;
		unless (($IP =~ /\d+\.\d+\.\d+\.\d+/) || ($IP =~ /:/))
		{
    		next;
		}
		my ($ia, $ib, $ic, $id) = split('\.', $IP);

		# check the entries of the networks table
		# - if the bitwise AND of the IP and the netmask gives you 
		#	the "net" name then that is the entry you want.
		foreach (@TableRowArray) {
			my $NM = $_->{'mask'};
			my $net=$_->{'net'};
			chomp $NM;
			chomp $net;

                        if(xCAT::NetworkUtils->ishostinsubnet($IP, $NM, $net))
                        {
				# fill in the hash - 
				foreach my $attr (@attrnames) {
					if ( defined($_->{$attr}) ) {
						$nethash{$node}{$attr} = $_->{$attr};
					}
                                }
                                if($nethash{$node}{'gateway'} eq '<xcatmaster>')
                                {
                                    if(xCAT::NetworkUtils->ip_forwarding_enabled())
                                    {
                                        $nethash{$node}{'gateway'} = xCAT::NetworkUtils->my_ip_in_subnet($net, $NM);
                                    }
                                    else
                                    {
                                        $nethash{$node}{'gateway'} = '';
                                    }
                                    $nethash{$node}{'myselfgw'} = 1;
                                    # For hwctrl commands, it is possible that this subroutine is called
                                    # on MN instead of SN, if the hcp SN is not set
                                    if (xCAT::Utils->isMN() && !$nethash{$node}{'gateway'})
                                    {
                                        # does not have ip address in this subnet,
                                        # use the node attribute 'xcatmaster' or site.master
                                        my @nodes = ("$node");
                                        my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes,"xcat","Node");
                                        my $snkey = (keys %{$sn})[0];
                                        my $gw = xCAT::NetworkUtils->getipaddr($snkey);
                                        # two possible cases when this code is run:
                                        # 1. flat cluster: ip forwarding is not enabled on MN
                                        # 2. hw ctrl in hierarchy cluster, in which HCP SN is not set
                                        # in either case, MN itself should not be the gateway
                                         if (xCAT::NetworkUtils->thishostisnot($gw)) {
                                             $nethash{$node}{'gateway'} = $gw;
                                         }
                                    }
                                
                                }
                                next;
                        }
                            
		}

	} #end - for each node

	return %nethash;
}
#----------------------------------------------------------------------------

=head3   parse_access_tabentry

        Parse the access_tabentry field in Schema.pm.
        We needs to support multiple keys in the table
        Arguments:
                $objname: objectname=>objtype hash
                $access_tabentry: the access_tabentry defined in Schema.pm
                $tabentry_ref: return the parsed result through this hash ref 
                                  The structure of the hash is:
                                  {
                                      'lookup_tables' => <table_name>
                                      'lookup_attrs' =>
                                      {
                                          'attr1' => 'val1'
                                          'attr2' => 'val2'
                                          ...
                                       }
                                  }
        Returns:
                0 - success
                1 - failed
        Globals:
        Error:
        Example:

		To parse the access_tabentry field

                my $rc = xCAT::DBobjUtils->parse_access_tabentry($objname, $this_attr->{access_tabentry}, \%tabentry);

        Comments:

=cut

#-----------------------------------------------------------------------------
sub parse_access_tabentry()
{
    my ($class, $objname, $access_tabentry, $tabentry_ref) = @_;

    # ex. 'nodelist.node', 'attr:node'
    foreach my $ent (split('::', $access_tabentry))
    {
        # ex. 'nodelist.node', 'attr:node'
        my ($lookup_key, $lookup_value) = split('\=', $ent);

        # ex. 'nodelist', 'node'
        my ($lookup_table, $lookup_attr) = split('\.', $lookup_key);

        # ex. 'attr', 'node'
        my ($lookup_type, $lookup_data) = split('\:', $lookup_value);

        if (!defined($tabentry_ref->{'lookup_table'}))
        {
            $tabentry_ref->{'lookup_table'} = $lookup_table;
        }

        # Only support one lookup table in the access_tabentry
        # Do we need to support multiple tables in one access_tabentry ????
        # has not seen any requirement...
        if ($lookup_table ne $tabentry_ref->{'lookup_table'})
        {
            my $rsp;
            $rsp->{data}->[0] =
                  "The access_tabentry \"$access_tabentry\" is not valid, can not specify more than one tables to look up.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;
        }

       if ($lookup_type eq 'attr')
       {
           # TODO: may need to update in the future
           # for now, the "val" in attr:val in 
           # Schema.pm can only be the object name
           # In the future, even if we need to change here,
           # be caution about the performance
           # looking up table is time consuming
           $tabentry_ref->{'lookup_attrs'}->{$lookup_attr} = $objname;
       }
       elsif ($lookup_type eq 'str')
       {
           $tabentry_ref->{'lookup_attrs'}->{$lookup_attr} = $lookup_data;
       } 
       else
       {
           my $rsp;
           $rsp->{data}->[0] =
                 "The access_tabentry \"$access_tabentry\" is not valid, the lookup type can only be 'attr' or 'str'.";
           xCAT::MsgUtils->message("E", $rsp, $::callback);
           return 1;
       }
    }
    return 0;
}
#-------------------------------------------------------------------------------

=head3   getchildren
    Arguments:
        single hostname
        optional port number
    Returns:
       array of fsp/bpa hostnames (IPs)
       if specified port, it will just return nodes within the port.
    Globals:
        %PPCHASH - HASH of nodename -> array of ip addresses
                     where the nodetype is fsp or bpa 
    Error:
       $::RUNCMD_RC = 1; 
       Writes error to syslog
    Example:
         $c1 = getchildren($nodetocheck);
         $c1 = getchildren($nodetocheck,$port);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------

my %PPCHASH;
sub getchildren
{
    my $parent = shift;
    if (($parent) && ($parent =~ /xCAT::/))
    {
        $parent = shift;
    }
    $::RUNCMD_RC = 0;
    my $port   = shift;
    my @tabletype = qw(ppc zvm);
    my @children = ();
    my @children_port = ();
    if (!%PPCHASH) {
        my $ppctab  = xCAT::Table->new( 'ppc' );
        unless ($ppctab) {   # cannot open  the table return with error
          xCAT::MsgUtils->message('S', "getchildren:Unable to open ppc table.\n");
          $::RUNCMD_RC = 1; 
          return undef; 
        }
        my @ps = $ppctab->getAllNodeAttribs(['node','parent','nodetype','hcp']);
        foreach my $entry ( @ps ) {
            my $p = $entry->{parent};
            my $c = $entry->{node};
            my $t = $entry->{nodetype};
            if ( $p and $c) {
              if ($t)  {  # the nodetype exists in the ppc table, use it
                if ( $t eq 'fsp' or $t eq 'bpa') {
                    # build hash of ppc.parent -> ppc.node 
                    push @{$PPCHASH{$p}}, $c;
                }   
                elsif ($t eq 'blade') {
                    push @{$PPCHASH{$c}}, $entry->{hcp};
                }
              } else { # go look in the nodetype table to find nodetype 
                 my $type = getnodetype($c, "ppc");
                 if ( $type eq 'fsp' or $type eq 'bpa')
                 {
                     # build hash of ppc.parent -> ppc.node 
                      push @{$PPCHASH{$p}}, $c;
                 }
                 elsif ($type eq "blade") {
                     push @{$PPCHASH{$c}}, $entry->{hcp};
                 }
              }
            }  # not $p and $c
        }
        # Find parent in the hash and build return values 
        foreach (@{$PPCHASH{$parent}}) {
            push @children, $_;
        }
    } else {
        if (exists($PPCHASH{$parent})) {
            foreach (@{$PPCHASH{$parent}}) {
                push @children, $_;
            }
        }
    }
    # if port not input
    if ( !defined($port ))
    {
        return \@children;
    } else {
     if (@children) { 
       my $vpdtab = xCAT::Table->new( 'vpd' );
       unless ($vpdtab) {   # cannot open  the table return with error
       xCAT::MsgUtils->message('S', "getchildren:Unable to open vpd table.\n");
          $::RUNCMD_RC = 1; 
          return undef; 
       }
       my $sides = $vpdtab->getNodesAttribs(\@children, ['side']);
       if(!$sides)
       {
           return undef;
       }
       foreach my $n (@children)
       {
            my $nside = $sides->{$n}->[0];
            if ($nside->{side} =~ /$port/)
            {
                push @children_port, $n;
            }
        }
        return \@children_port;
     } else {  # no children 
         return undef;
     }
    }
}
#-------------------------------------------------------------------------------

=head3   getnodetype
    Query ppc table, if no type found query nodetype table
    Arguments:
       An array of nodenames or 1 nodename 
    Returns:
        If the input is an array, it returns a hash, 
        for the nodes that can't get node type, it will be 'node' => undef;
        If the input is not an array, it returns the value of type,
        for the node that can't get node type, it will be undef;
    Globals:
        %NODETYPEHASH
    Error:
        $::RUNCMD_RC = 1; 
        Errors written to syslog
    Example:
         $type = xCAT::DBobjUtils->getnodetype($node, "ppc");
         $type = xCAT::DBobjUtils->getnodetype($node);
         $typerefer = xCAT::DBobjUtils->getnodetype(\@nodes, "PPC");
         $typerefer = xCAT::DBobjUtils->getnodetype(\@nodes);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
my %NODETYPEHASH;
sub getnodetype
{
    my $nodes = shift;
    if (($nodes) && ($nodes =~ /xCAT::/))
    {
        $nodes = shift;
    }
    my $table = shift;
    my $rsp;
    my @tabletype = qw(ppc zvm);
    my %typehash;
    my %tablehash;
    $::RUNCMD_RC = 0; 
    
    my @failnodes;
    my @failnodes1;
    ######################################################################
    # if the table arg is set, go to the specified table first
    # if can't get anything from the specified table, go to nodetype table
    ######################################################################
    if ($table) {
        my $nodetypetab = xCAT::Table->new( $table );
        unless ($nodetypetab) {   
            xCAT::MsgUtils->message('S', "getnodetype:Unable to open $table table.\n");
            $::RUNCMD_RC = 1; 
            if ( $nodes =~ /^ARRAY/) {
                foreach my $tn (@$nodes) {
                    $typehash{$tn} = undef;
                }
            } else {
                $typehash{$nodes} = undef; 
            }            
            return \%typehash; 
        }
        ############################################
        # if the input node arg is an array,
        # query table and don't use the global hash
        ############################################
        if ( $nodes =~ /^ARRAY/) {
            my $nodetypes = $nodetypetab->getNodesAttribs($nodes, ['nodetype']);
            foreach my $tn (@$nodes) {
                my $gottype = $nodetypes->{$tn}->[0]->{'nodetype'};
                if ( $gottype ) {         
                    $NODETYPEHASH{$tn} = $gottype;
                    $typehash{$tn} = $gottype;  
                } else {
                    push @failnodes, $tn;
                }
            }
            ################################################
            # for the failed nodes, go to nodetype table 
            ################################################
            if ( @failnodes ) {
                my $typetable = xCAT::Table->new( 'nodetype' );
                unless ($typetable) {   # cannot open  the table return with error
                    xCAT::MsgUtils->message('S', "getnodetype:Unable to open nodetype table.\n");
                    $::RUNCMD_RC = 1; 
                    foreach my $tn (@failnodes) {
                        $typehash{$tn} = undef;
                    }
                } else {
                    my $nodetypes = $nodetypetab->getNodesAttribs(\@failnodes, ['nodetype']);
                    foreach my $tn ( @failnodes ) {
                        if ( $nodetypes->{$tn}->[0] ) {
                            $NODETYPEHASH{$tn} = $nodetypes->{$tn}->[0]->{'nodetype'};
                            $typehash{$tn} = $nodetypes->{$tn}->[0]->{'nodetype'};
                        } else {
                            push @failnodes1, $tn;
                            $typehash{$tn} = undef;  
                        }
                        ##################################################
                        # give error msg for the nodes can't get nodetype
                        ##################################################
                    }  
                    if ( @failnodes1 ) {
                        my $nodelist =  join(",", @failnodes1);
                        xCAT::MsgUtils->message('S', "getnodetype:Can't find these nodes' type: $nodelist.\n");
                    } 
                }                    
            } 
            #####################
            # return the result
            #####################      
            return \%typehash;
                
        } else {
        ############################################
        # if the input node arg is not an array,
        # query table and use the global hash first
        ############################################
            if ( $NODETYPEHASH{$nodes} ) {
                return $NODETYPEHASH{$nodes}; 
            } else {
                my $typep = $nodetypetab->getNodeAttribs($nodes, ['nodetype']);
                if ( $typep->{nodetype} ) {
                    $NODETYPEHASH{$nodes} = $typep->{nodetype};
                    return $typep->{nodetype};
                } else { #if not find in the specified table, go to nodetype table
                    my $typetable = xCAT::Table->new( 'nodetype' );
                    unless ($typetable) {   # cannot open  the table return with error
                        xCAT::MsgUtils->message('S', "getnodetype:Unable to open nodetype table.\n");
                        $::RUNCMD_RC = 1; 
                        return undef;
                    }
                    my $typep  = $typetable->getNodeAttribs($nodes, ['nodetype']);
                    if ( $typep->{nodetype} ) {
                        $NODETYPEHASH{$nodes} = $typep->{nodetype};
                        return  $typep->{nodetype};
                    } else {
                        return undef;
                    }    
                }
            }
        }
    } else {
    ######################################################################
    # if the table arg is not set, go to the nodetype table first
    # if can't get anything from the specified table, go to nodetype table
    ######################################################################
        my $nodetypetab = xCAT::Table->new( 'nodetype' );
        unless ($nodetypetab) {   
            xCAT::MsgUtils->message('S', "getnodetype:Unable to open $table table.\n");
            $::RUNCMD_RC = 1; 
            if ( $nodes =~ /^ARRAY/) {
                foreach my $tn (@$nodes) {
                    $typehash{$tn} = undef;
                }
            } else {
                $typehash{$nodes} = undef; 
            }            
            return \%typehash; 
        }
        ############################################
        # if the input node arg is an array,
        # query table and don't use the global hash
        ############################################
        if ( $nodes =~ /^ARRAY/) {
            my $nodetypes = $nodetypetab->getNodesAttribs($nodes, ['nodetype']);
            foreach my $tn (@$nodes) {
                my $gottype = $nodetypes->{$tn}->[0]->{'nodetype'};
                if ( $gottype) {
                    if ($gottype =~ /,/) {   #if find ppc,osi
                        my @tbty = split /,/, $gottype;
                        foreach my $ttable (@tbty){
                            if (grep(/$ttable/, @tabletype)){
                            $tablehash{ $tn } = $ttable;
                            last;
                            }
                        }
                    } elsif (grep(/$gottype/, @tabletype)){    #if find ppc or zvm
                        $tablehash{ $tn } = $gottype;  
                    } else {                         
                        $NODETYPEHASH{ $tn } = $gottype;
                        $typehash{ $tn } = $gottype;     
                    }                    
                } else {
                    $typehash{ $tn } = undef;
                }
            }
            ################################################
            # for the failed nodes, go to related tables 
            ################################################
            if ( %tablehash ) {
                foreach my $ttable (@tabletype) {
                    my @nodegroup;
                    foreach my $fnode (keys %tablehash) {
                        if ($tablehash{$fnode} eq $ttable) {
                            push @nodegroup, $fnode;
                        }
                    }   
                    next unless (@nodegroup);                    
                    my $typetable = xCAT::Table->new( $ttable);
                    unless ($typetable) {
                        my $failnodes = join(",", @nodegroup);
                        xCAT::MsgUtils->message('S', "getnodetype:Unable to open $ttable table, can't find $failnodes type.\n");
                        $::RUNCMD_RC = 1; 
                        foreach (@nodegroup) {
                            $typehash{$_} = undef;
                        }
                    } else {
                        my $typep  = $typetable->getNodesAttribs(\@nodegroup, ['nodetype']);
                        foreach my $fn (@nodegroup) {
                            if ( $typep->{$fn}->[0]->{'nodetype'} ) {
                                $typehash{$fn} = $typep->{$fn}->[0]->{'nodetype'};
                                $NODETYPEHASH{$fn} = $typep->{$fn}->[0]->{'nodetype'};
                            } else {
                                $typehash{$fn} = undef;
                            }
                        }                          
                    }
                }
            }   
            return \%typehash;  
        } else { # if not an array
            if ( $NODETYPEHASH{$nodes} ) {
                return $NODETYPEHASH{$nodes}; 
            } else {
                my $typep = $nodetypetab->getNodeAttribs($nodes, ["nodetype"]);
                if ( $typep->{nodetype} and !(grep(/$typep->{nodetype}/, @tabletype))) {
                    $NODETYPEHASH{$nodes} = $typep->{nodetype};
                    return $typep->{nodetype};
                } elsif ( grep(/$typep->{nodetype}/, @tabletype) ) {
                    my $typetable = xCAT::Table->new( $typep->{nodetype} );
                    unless ($typetable) {
                        xCAT::MsgUtils->message('S', "getnodetype:Unable to open nodetype table.\n");
                        $::RUNCMD_RC = 1; 
                        return undef;
                    }
                    my $typep = $typetable->getNodeAttribs($nodes, ["nodetype"]);
                    if ( $typep->{nodetype} ) {
                        $NODETYPEHASH{$nodes} = $typep->{nodetype};
                        return $typep->{nodetype};
                    } else {
                        return undef;
                    }    
                }
            }
        }
    }
}
#-------------------------------------------------------------------------------

=head3   getcecchildren
    returns cec of the specified frame,
    Arguments:
        frame name
    Returns:
        Array of cec hostnames
    Globals:
        %PARENT_CHILDREN_CEC 
    Error:
        none
    Example:
         @frame_members = getcecchildren($frame);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
my %PARENT_CHILDREN_CEC;
sub getcecchildren
{
    my $parent = shift;
    if (($parent) && ($parent =~ /xCAT::/))
    {
        $parent = shift;
    }
    my @children = ();
    if (!%PARENT_CHILDREN_CEC) {
        my $ppctab  = xCAT::Table->new( 'ppc' );
        unless ($ppctab) {   # cannot open  the table return with error
          xCAT::MsgUtils->message('S', "getcecchildren:Unable to open ppc table.\n");
          $::RUNCMD_RC = 1; 
          return undef; 
        }
        if ($ppctab)
        {
            my @ps = $ppctab->getAllNodeAttribs(['node','parent','nodetype']);
            foreach my $entry ( @ps ) {
                my $p = $entry->{parent};
                my $c = $entry->{node};
                my $t = $entry->{nodetype};
                if ( $p and $c) {
                   if ($t)  {  # the nodetype exists in the ppc table, use it
                     if ( $t eq 'cec') {
                       # build hash of ppc.parent -> ppc.node 
                       push @{$PARENT_CHILDREN_CEC{$p}}, $c;
                     }   
                   } else { # go look in the nodetype table to find nodetype 
                     my $type = getnodetype($c);
                     if ( $type eq 'cec') {
                        push @{$PARENT_CHILDREN_CEC{$p}}, $c;
                     }
                   }
                }
            }
            # find a match for the parent and build the return array        
            foreach (@{$PARENT_CHILDREN_CEC{$parent}}) {
                push @children, $_;        
            }
  	    return \@children;
        }	
    } else {  # already built the HASH
        if (exists($PARENT_CHILDREN_CEC{$parent})) {
            foreach (@{$PARENT_CHILDREN_CEC{$parent}}) {
                push @children, $_;
            }
	    return \@children;			
        }
    }
    return undef;
}
#-------------------------------------------------------------------------------

=head3   judge_node
    judge the node is a real FSP/BPA, 
    use to distinguish if the data is defined in xCAT 2.5 or later
    Arguments:
        node name
    Returns:
        0  is a fake FSP/BPA,defined in xCAT 2.5
        1  is a real FSP/BPA,defined in xCAT 2.6 or later
    Error:
        none
    Example:
         $result = judge_node($nodetocheck);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub judge_node
{
    my $node = shift;
    if (($node) && ($node =~ /xCAT::/))
    {
        $node = shift;
    }    
    my $type = shift;
    my $flag = 0;
    my $parenttype;
    my $nodeparent;
    my $ppctab  = xCAT::Table->new( 'ppc' );    
    if ( $ppctab ) {
        $nodeparent = $ppctab->getNodeAttribs($node, ["parent"]);
        if ($nodeparent and $nodeparent->{parent}) {
            $parenttype = getnodetype($nodeparent->{parent});
        }
    }
    
    if ($type =~ /^fsp$/) {
        if ($parenttype =~ /^cec$/)
        {
            $flag = 1;
        } else
        {
            $flag = 0;
        }
    }

    if ($type =~ /^bpa$/) {
        if ($parenttype =~ /^frame$/)
        {
            $flag = 1;
        } else
        {
            $flag = 0;
        }
    }        
      
    return $flag;            
}


#-------------------------------------------------------------------------------

=head3   expandnicsattr
    Expand the nics related attributes into the readable format,
    for example, the nicsips=eth0!1.1.1.1|2.1.1.1,eth1!3.1.1.1|4.1.1.1
    expanded format:
    nicsips.eth0=1.1.1.1|2.1.1.1
    nicsips.eth1=3.1.1.1|4.1.1.1

    Arguments:
        nicsattr value, like niccsips=eth0!1.1.1.1|2.1.1.1,eth1!3.1.1.1|4.1.1.1 
        nicnames: only return the value for specific nics, like "eth0,eth1"
    Returns:
        expanded format, like:
        nicsips.eth0=1.1.1.1|2.1.1.1
        nicsips.eth1=3.1.1.1|4.1.1.1
    Error:
        none

    Example:
        my $nicsstr = xCAT::DBobjUtils->expandnicsattr($attrval);

    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub expandnicsattr()
{
    my $nicstr = shift;
    if (($nicstr) && ($nicstr =~ /xCAT::/))
    {
        $nicstr = shift;
    }
    my $nicnames = shift;

    my $ret; 

    $nicstr =~ /^(.*?)=(.*?)$/;

    #Attribute: nicips, nichostnamesuffix, etc.
    my $nicattr = $1;

    # Value: eth0!1.1.1.1|2.1.1.1,eth1!3.1.1.1|4.1.1.1
    my $nicval=$2;

    # $nicarr[0]: eth0!1.1.1.1|2.1.1.1
    # $nicarr[1]: eth1!3.1.1.1|4.1.1.1 
    my @nicarr = split(/,/, $nicval);
    
    foreach my $nicentry (@nicarr)
    {
        #nicentry: eth0!1.1.1.1|2.1.1.1
        # $nicv[0]: eth0
        # $nicv[1]: 1.1.1.1|2.1.1.1
        my @nicv = split(/!/, $nicentry);

        # only return nic* attr for these specific nics
        if ($nicnames)
        {
            my @nics = split(/,/, $nicnames);
            if ($nicv[0])
            {
                # Do not need to return the nic attr for this nic
                if (!grep(/^$nicv[0]$/, @nics))
                {
                    next;
                }
            }
        }

        # ignore the line that does not have nicname or value
        if ($nicv[0] && $nicv[1])
        {
            $ret .= "    $nicattr.$nicv[0]=$nicv[1]\n";
        }
    }

    chomp($ret);
    return $ret;

}


#-------------------------------------------------------------------------------

=head3   collapsenicsattr
    Collapse the nics related attributes into the database format,
    for example, 
    nicsips.eth0=1.1.1.1|2.1.1.1
    nicsips.eth1=3.1.1.1|4.1.1.1
    
    the collapsed format:
    nicsips=eth0!1.1.1.1|2.1.1.1,eth1!3.1.1.1|4.1.1.1
    
    The collapse will be done against the hash %::FILEATTRS or %::CLIATTRS,
    remove the nicips.thx attributes from %::FILEATTRS or %::CLIATTRS,
    add the collapsed info nicips into %::FILEATTRS or %::CLIATTRS.

    Arguments:
        $::FILEATTRS{$objname} or $::CLIATTRS{$objname}
        $objname

    Returns:
        None, update %::FILEATTRS or %::CLIATTRS directly

    Error:
        none

    Example:
        xCAT::DBobjUtils->collapsenicsattr($nodeattrhash);

    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub collapsenicsattr()
{
    my $nodeattrhash = shift;
    if (($nodeattrhash) && ($nodeattrhash =~ /xCAT::/))
    {
        $nodeattrhash = shift;
    }
    my $objname = shift;

    my %nicattrs = ();
    foreach my $nodeattr (keys %{$nodeattrhash})
    {       
        # e.g nicips.eth0
        # do not need to handle nic attributes without the postfix .ethx,
        # it will be overwritten by the attributes with the postfix .ethx,
        if ($nodeattr =~ /^(nic\w+)\.(\w+)$/)
        {       
           if ($1 && $2)
           {       
               # chdef <noderange> nicips.eth2= to remove the definition for eth2
               # in this case, the $nodeattrhash->{'nicips.eth0'} is blank
               if ($nodeattrhash->{$nodeattr})
               {
                   # $nicattrs{nicips}{eth0} = "1.1.1.1|1.2.1.1"
                   $nicattrs{$1}{$2} = $nodeattrhash->{$nodeattr}; 
               }

               # remove nicips.eth0 from the %::FILEATTRS
               delete $nodeattrhash->{$nodeattr};
           }       
        }       
    }       
    # $nicattrs{'nicips'}{'eth0'} = "1.1.1.1|1.2.1.1"
    # $nicattrs{'nicips'}{'eth1'} = "2.1.1.1|2.2.1.1"
    foreach my $nicattr (keys %nicattrs)
    {       
       my @tmparray = ();
       foreach my $nicname (keys %{$nicattrs{$nicattr}})
       {       
           # eth0!1.1.1.1|1.2.1.1
           push @tmparray, "$nicname!$nicattrs{$nicattr}{$nicname}";
       }       
       # eth0!1.1.1.1|1.2.1.1,eth1!2.1.1.1|2.2.1.1
       $nodeattrhash->{$nicattr} = join(',', @tmparray);
    }       
}

1;
