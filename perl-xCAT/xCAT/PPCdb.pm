# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCdb;
use strict;
use xCAT::Table;
use xCAT::GlobalDef;


###########################################
# Factory defaults
###########################################
my %logon = (
    hmc => ["hscroot","abc123"],
    ivm => ["padmin", "padmin"],
    fsp => ["admin",  "admin"],
    bpa => ["admin",  "admin"]
);

###########################################
# Tables based on HW Type
###########################################
my %hcptab = (
    hmc => "ppchcp",
    ivm => "ppchcp",
    fsp => "ppcdirect",
    bpa => "ppcdirect"
);

###########################################
# The default groups of hcp
###########################################
my %defaultgrp = (
    hmc => "hmc",
    ivm => "ivm",
    fsp => "fsp",
    bpa => "bpa"
);


##########################################################################
# Adds a node to the xCAT databases
##########################################################################
sub add_ppc {

    my $hwtype   = shift;
    my $values   = shift;
    my $not_overwrite = shift;
    my @tabs     = qw(ppc vpd nodehm nodelist nodetype); 
    my %db       = ();
    my %nodetype = (
        fsp  => $::NODETYPE_FSP,
        bpa  => $::NODETYPE_BPA,
        lpar =>"$::NODETYPE_LPAR,$::NODETYPE_OSI",
        hmc  => $::NODETYPE_HMC,
        ivm  => $::NODETYPE_IVM,
    );

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    ###################################
    # Update tables 
    ###################################
    foreach ( @$values ) {
        my ($type,
            $name,
            $id,
            $model,
            $serial,
            $server,
            $pprofile,
            $parent,
            $ips ) = split /,/;
         
        ###############################
        # Update nodetype table
        ###############################
        if ( $type =~ /^(fsp|bpa|lpar|hmc|ivm)$/ ) {
            $db{nodetype}->setNodeAttribs( $name,{nodetype=>$nodetype{$type}} );
            $db{nodetype}{commit} = 1;
        }
        ###############################
        # If cannot be overwroten, get
        # old data firstly
        ###############################
        my $mgt = $hwtype;
        my $cons= $hwtype;
        if ( $not_overwrite)
        {
            my $enthash = $db{ppc}->getNodeAttribs( $name, [qw(hcp id pprofile parent)]);
            if ( $enthash )
            {
                $server   = $enthash->{hcp} if ($enthash->{hcp});
                $id       = $enthash->{id}  if ( $enthash->{id});
                $pprofile = $enthash->{pprofile} if ( $enthash->{pprofile});
                $parent   = $enthash->{parent} if ( $enthash->{parent});
            }
            $enthash = $db{nodehm}->getNodeAttribs( $name, [qw(mgt)]);
            if ( $enthash )
            {
                $mgt= $enthash->{mgt} if ( $enthash->{mgt});
                $cons= $enthash->{cons} if ( $enthash->{cons});
            }
            $enthash = $db{vpd}->getNodeAttribs( $name, [qw(mtm serial)]);
            if ( $enthash )
            {
                $model = $enthash->{mtm} if ( $enthash->{mtm});
                $serial= $enthash->{serial} if ( $enthash->{serial});
            }
        }

        ###############################
        # Update ppc table
        ###############################
        if ( $type =~ /^(fsp|bpa|lpar)$/ ) {
            $db{ppc}->setNodeAttribs( $name,
               { hcp=>$server,
                 id=>$id,
                 pprofile=>$pprofile,
                 parent=>$parent
               }); 
            $db{ppc}{commit} = 1;

            ###########################
            # Update nodelist table
            ###########################
            updategroups( $name, $db{nodelist}, $type );
            $db{nodelist}{commit} = 1;

            ###########################
            # Update nodehm table
            ###########################
            if($type =~ /^lpar$/){
                $db{nodehm}->setNodeAttribs( $name, {mgt=>$mgt,cons=>$cons} );
            } else {
                $db{nodehm}->setNodeAttribs( $name, {mgt=>$mgt} );
            }
            $db{nodehm}{commit} = 1;
        }
        ###############################
        # Update vpd table
        ###############################
        if ( $type =~ /^(fsp|bpa)$/ ) {
            $db{vpd}->setNodeAttribs( $name, 
                { mtm=>$model,
                  serial=>$serial
                 });
            $db{vpd}{commit} = 1;
        }
    }

    ###################################
    # Commit changes 
    ###################################
    foreach ( @tabs ) {
        if ( exists( $db{$_}{commit} )) {
           $db{$_}->commit;
        }
    }
    return undef;
}

##########################################################################
# Update nodes in the xCAT databases
##########################################################################
sub update_ppc {

    my $hwtype   = shift;
    my $values   = shift;
    my $not_overwrite = shift;
    my @tabs     = qw(ppc vpd nodehm nodelist nodetype ppcdirect); 
    my %db       = ();
    my %nodetype = (
        fsp  => $::NODETYPE_FSP,
        bpa  => $::NODETYPE_BPA,
        lpar =>"$::NODETYPE_LPAR,$::NODETYPE_OSI",
        hmc  => $::NODETYPE_HMC,
        ivm  => $::NODETYPE_IVM,
    );
    my @update_list = ();

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    my @vpdlist = $db{vpd}->getAllNodeAttribs(['node','serial','mtm']);
    my @ppclist = $db{ppc}->getAllNodeAttribs(['node','hcp','id',
                                               'pprofile','parent','supernode',
                                               'comments', 'disable']);
    ###################################
    # Update FSP in tables 
    ###################################
    foreach my $value ( @$values ) {
        my ($type,
            $name,
            $id,
            $model,
            $serial,
            $server,
            $pprofile,
            $parent,
            $ips ) = split /,/, $value;
         
        next if ( $type ne 'fsp' );

        my $predefined_node = undef;
        foreach my $vpdent (@vpdlist)
        {
            if ( $vpdent->{mtm} eq $model && $vpdent->{serial} eq $serial)
            {
                $predefined_node = $vpdent->{node};
                last;
            }
        }

        next if ( !$predefined_node);
        
        if ( update_node_attribs($hwtype, $type, $name, $id, $model, $serial, 
                            $server, $pprofile, $parent, $ips, 
                            \%db, $predefined_node, \@ppclist))
        {
            push @update_list, $value;
        }
    }

    ###################################
    # Update BPA in tables 
    ###################################
    foreach my $value ( @$values ) {
        my ($type,
            $name,
            $id,
            $model,
            $serial,
            $server,
            $pprofile,
            $parent,
            $ips ) = split /,/;
         
        next if ( $type ne 'bpa');

        my $predefined_node = undef;
        foreach my $vpdent (@vpdlist)
        {
            if ( $vpdent->{mtm} eq $model && $vpdent->{serial} eq $serial)
            {
                $predefined_node = $vpdent->{node};
                last;
            }
        }

        next if ( !$predefined_node);
        
        if (update_node_attribs($hwtype, $type, $name, $id, $model, $serial, 
                            $server, $pprofile, $parent, $ips, 
                            \%db, $predefined_node, \@ppclist))
        {
            push @update_list, $value;
        }
    }

    ###################################
    # Commit changes 
    ###################################
    foreach ( @tabs ) {
        if ( exists( $db{$_}{commit} )) {
           $db{$_}->commit;
        }
    }
    return \@update_list;
}

##########################################################################
# Update one node in the xCAT databases
##########################################################################
sub update_node_attribs
{
    my $mgt = shift;
    my $type = shift;
    my $name = shift;
    my $id = shift;
    my $model = shift;
    my $serial = shift;
    my $server = shift;
    my $pprofile = shift;
    my $parent = shift;
    my $ips = shift;
    my $db = shift;
    my $predefined_node = shift;
    my $ppclist = shift;

    my $updated = undef;
    my $namediff = $name ne $predefined_node;
    my $key_col = { node=>$predefined_node};

    #############################
    # update vpd table
    #############################
    my $vpdhash = $db->{vpd}->getNodeAttribs( $name, [qw(mtm serial)]);
    if ( $model ne $vpdhash->{mtm} or $serial ne $vpdhash->{serial} or $namediff)
    {
        $db->{vpd}->delEntries( $key_col) if ( $namediff);
        $db->{vpd}->setNodeAttribs( $name, { mtm=>$model, serial=>$serial});
        $db->{vpd}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update ppcdirect table
    ###########################
    my $pwhash = $db->{ppcdirect}->getNodeAttribs( $predefined_node, [qw(username password comments disable)]);
    if ( $pwhash)
    {
        if ( $namediff)
        {
            $db->{ppcdirect}->delEntries( {hcp=>$predefined_node}) if ( $namediff);;
            $db->{ppcdirect}->setAttribs({hcp=>$name},
                    {username=>$pwhash->{username},
                    password=>$pwhash->{password},
                    comments=>$pwhash->{comments},
                    disable=>$pwhash->{disable}});
            $db->{vpd}->{commit} = 1;
            $updated = 1;
        }
    }

    #############################
    # update ppc table
    #############################
    my $ppchash = $db->{ppc}->getNodeAttribs( $name, [qw(hcp id pprofile parent)]);
    if ( $server ne $ppchash->{hcp} or
         $id     ne $ppchash->{id} or
         $pprofile ne $ppchash->{pprofile} or
         $parent ne $ppchash->{parent} or
         $namediff)
    {
        $db->{ppc}->delEntries( $key_col) if ( $namediff);
        $db->{ppc}->setNodeAttribs( $name,
                { hcp=>$server,
                id=>$id,
                pprofile=>$pprofile,
                parent=>$parent
                }); 
        if ( $namediff)
        {
            for my $ppcent (@$ppclist)
            {
                next if ($ppcent->{node} eq $predefined_node);
                if ($ppcent->{parent} eq $predefined_node)
                {
                    $db->{ppc}->setNodeAttribs( $ppcent->{node}, {parent=>$name});
                }
            }
        }
        $db->{ppc}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update nodehm table
    ###########################
    my $nodehmhash = $db->{nodehm}->getNodeAttribs( $name, [qw(mgt)]);
    if ( $mgt ne $nodehmhash->{mgt} or $namediff)
    {
        $db->{nodehm}->delEntries( $key_col) if ( $namediff);
        $db->{nodehm}->setNodeAttribs( $name, {mgt=>$mgt} );
        $db->{nodehm}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update nodetype table
    ###########################
    my $nodetypehash = $db->{nodetype}->getNodeAttribs( $name, [qw(nodetype)]);
    if ( $type ne $nodetypehash->{nodetype} or $namediff)
    {
        $db->{nodetype}->delEntries( $key_col) if ( $namediff);
        $db->{nodetype}->setNodeAttribs( $name,{nodetype=>$type} );
        $db->{nodetype}->{commit} = 1;
        $updated = 1;
    }

    ###########################
    # Update nodelist table
    ###########################
    my $nodelisthash = $db->{nodelist}->getNodeAttribs( $name, [qw(groups status appstatus primarysn comments disable)]);
    if ( $namediff)
    {
        updategroups( $name, $db->{nodelist}, $type );
        $db->{nodelist}->setNodeAttribs( $name, {status=>$nodelisthash->{status},
                                                 appstatus=>$nodelisthash->{appstatus},
                                                 primarysn=>$nodelisthash->{primarysn},
                                                 comments=>$nodelisthash->{comments},
                                                 disable=>$nodelisthash->{disable}
                                               });
        $db->{nodelist}->delEntries( $key_col);
        $db->{nodelist}->{commit} = 1;
        $updated = 1;
    }
    return $updated;
}

##########################################################################
# Updates the nodelist.groups attribute 
##########################################################################
sub updategroups {

    my $name   = shift;
    my $tab    = shift;
    my $hwtype = shift;

    ###############################
    # Get current value 
    ###############################
    my ($ent) = $tab->getNodeAttribs( $name, ['groups'] );
    my @list = ( lc($hwtype), "all" );

    ###############################
    # Keep any existing groups
    ###############################
    if ( defined($ent) and $ent->{groups} ) {
        push @list, split( /,/, $ent->{groups} );
    }
    ###############################
    # Remove duplicates
    ###############################
    my %saw;
    @saw{@list} = ();
    @list = keys %saw;

    $tab->setNodeAttribs( $name, {groups=>join(",",@list)} );
}


##########################################################################
# Adds an HMC/IVM to the xCAT database
##########################################################################
sub add_ppchcp {

    my $hwtype = shift;
    my $name   = shift;
    my @tabs   = qw(ppchcp nodehm nodelist nodetype);
    my %db     = ();

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>1 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    ###################################
    # Update ppchcp table
    ###################################
    my ($ent) = $db{ppchcp}->getAttribs({ hcp=>$name},'hcp');
    if ( !defined($ent) ) {
        $db{ppchcp}->setAttribs( {hcp=>$name}, 
            { username=>"",
              password=>""
            });
    }
    ###################################
    # Update nodehm table
    ###################################
    $db{nodehm}->setNodeAttribs( $name, {mgt=>lc($hwtype)} );
    
    ###################################
    # Update nodetype table
    ###################################
    $db{nodetype}->setNodeAttribs( $name, {nodetype=>lc($hwtype)});

    ###################################
    # Update nodelist table
    ###################################
    updategroups( $name, $db{nodelist}, $hwtype );
    return undef;
}


##########################################################################
# Removes a node from the xCAT databases
##########################################################################
sub rm_ppc {

    my $node = shift;
    my @tabs = qw(ppc nodehm nodelist);

    foreach ( @tabs ) {
        ###################################
        # Open table
        ###################################
        my $tab = xCAT::Table->new($_);
        if ( !$tab ) {
            return( "Error opening '$_'" );
        }
        ###############################
        # Remove entry
        ###############################
        $tab->delEntries( {'node'=>$node} );
    }
    return undef;
}



##########################################################################
# Adds a Management-Module or RSA to the appropriate tables
##########################################################################
sub add_systemX {

    my $hwtype = shift;
    my $data   = shift;
    my @tabs   = qw(mpa mp nodehm nodelist);
    my %db     = ();
    my $name   = @$data[4];

    ###################################
    # Open database needed
    ###################################
    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>1 );
        if ( !$db{$_} ) {
            return( "Error opening '$_'" );
        }
    }
    ###################################
    # Update mpa table
    ###################################
    my ($ent) = $db{mpa}->getAttribs({ mpa=>$name},'mpa');
    if ( !defined($ent) ) {
        $db{mpa}->setAttribs( {mpa=>$name}, 
            { username=>"",
              password=>""
            });
    }
    ###################################
    # Update mp table
    ###################################
    $db{mp}->setNodeAttribs( $name,
        { mpa=>$name,
          id=>"0"
        }); 

    ###################################
    # Update nodehm table
    ###################################
    $db{nodehm}->setNodeAttribs( $name, {mgt=>"blade"} );

    ###################################
    # Update nodelist table
    ###################################
    updategroups( $name, $db{nodelist}, $hwtype );
    return undef;
}



##########################################################################
# Get userids and passwords from tables
##########################################################################
sub credentials {

    my $server = shift;
    my $hwtype = shift;
    my $user   = shift;
    my $pass   = undef;
    my $user_specified = $user;
    if ( !$user_specified or $user eq @{$logon{$hwtype}}[0])
    {
        $user = @{$logon{$hwtype}}[0];
        $pass   = @{$logon{$hwtype}}[1];
    }

    ###########################################
    # Check passwd tab
    ###########################################
    my $tab = xCAT::Table->new( 'passwd' );
    if ( $tab ) {
        my $ent;
        if ( $user_specified)
        {
            ($ent) = $tab->getAttribs( {key=>$hwtype,username=>$user},qw(password));
        }
        else
        {
            ($ent) = $tab->getAttribs( {key=>$hwtype}, qw(username password));
        }
        if ( $ent ) {
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    }
    ##########################################
    # Check table based on specific node 
    ##########################################
    $tab = xCAT::Table->new( $hcptab{$hwtype} );
    if ( $tab ) {
        my $ent;
        if ( $user_specified)
        {
            ($ent) = $tab->getAttribs( {hcp=>$server,username=>$user},qw(password));
        }
        else
        {
            ($ent) = $tab->getAttribs( {hcp=>$server}, qw(username password));
        }
        if ( $ent){
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    ##############################################################
    # If no user/passwd found, check if there is a default group
    ##############################################################
        elsif( ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype}}, qw(username password)))
        {
            if ( $user_specified)
            {
                ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype},username=>$user},qw(password));
            }
            else
            {
                ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype}}, qw(username password));
            }
            if ( $ent){
                if (defined($ent->{password})) { $pass = $ent->{password}; }
                if (defined($ent->{username})) { $user = $ent->{username}; }
            }
        }
    }
    return( $user,$pass );
}


1;

