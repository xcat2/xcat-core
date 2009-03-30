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
            updategroups( $name, $db{nodelist}, $hwtype );
            $db{nodelist}{commit} = 1;

            ###########################
            # Update nodehm table
            ###########################
            $db{nodehm}->setNodeAttribs( $name, {mgt=>$hwtype} );
            if($type =~ /^lpar$/){
                $db{nodehm}->setNodeAttribs( $name, {cons=>$hwtype} );
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
    my $data   = shift;
    my @tabs   = qw(ppchcp nodehm nodelist);
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
    my $user   = @{$logon{$hwtype}}[0];
    my $pass   = @{$logon{$hwtype}}[1];

    ###########################################
    # Check passwd tab
    ###########################################
    my $tab = xCAT::Table->new( 'passwd' );
    if ( $tab ) {
        my ($ent) = $tab->getAttribs( {key=>$hwtype}, qw(username password));
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
        my ($ent) = $tab->getAttribs( {hcp=>$server}, qw(username password));
        if ( $ent){
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    ##############################################################
    # If no user/passwd found, check if there is a default group
    ##############################################################
        elsif( ($ent) = $tab->getAttribs( {hcp=>$defaultgrp{$hwtype}}, qw(username password)))
        {
            if (defined($ent->{password})) { $pass = $ent->{password}; }
            if (defined($ent->{username})) { $user = $ent->{username}; }
        }
    }
    return( $user,$pass );
}


1;

