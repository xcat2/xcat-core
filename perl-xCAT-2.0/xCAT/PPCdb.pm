# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCdb;
use strict;
use Getopt::Long;
use xCAT::Table;
use xCAT::GlobalDef;


##########################################################################
# Adds a node to the xCAT databases
##########################################################################
sub add_ppc {

    my $hwtype = shift;
    my $values = shift;
    my @tabs   = qw(ppc vpd nodehm nodelist nodetype); 
    my %db     = ();

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
        if ( $type =~ /^fsp|bpa|lpar|hmc|ivm$/ ) {
            my ($k,$u);
            my %nodetype = (
                 fsp  => $::NODETYPE_FSP,
                 bpa  => $::NODETYPE_BPA,
                 lpar =>"$::NODETYPE_LPAR,$::NODETYPE_OSI",
                 hmc  => $::NODETYPE_HMC,
                 ivm  => $::NODETYPE_IVM,
            );
            $k->{node}     = $name;
            $u->{nodetype} = $nodetype{$type};
            $db{nodetype}->setAttribs( $k,$u );
            $db{nodetype}{commit} = 1;
        }
        ###############################
        # Update ppc table
        ###############################
        if ( $type =~ /^fsp|bpa|lpar$/ ) {
            my ($k,$u);
            $k->{node}     = $name;
            $u->{hcp}      = $server;
            $u->{id}       = $id;
            $u->{pprofile} = $pprofile;
            $u->{parent}   = $parent;
            $db{ppc}->setAttribs( $k, $u );
            $db{ppc}{commit} = 1;

            ###########################
            # Update nodelist table
            ###########################
            my ($k1,$u1);
            $k1->{node}     = $name;
            $u1->{groups}   = lc($hwtype).",all";
            $db{nodelist}->setAttribs( $k1,$u1 );
            $db{nodelist}{commit} = 1;

            ###########################
            # Update nodehm table
            ###########################
            my ($k2,$u2);
            $k2->{node} = $name;
            $u2->{mgt}  = $hwtype;
            $db{nodehm}->setAttribs( $k2,$u2 );
            $db{nodehm}{commit} = 1;
        }
        ###############################
        # Update vpd table
        ###############################
        if ( $type =~ /^fsp|bpa$/ ) {
            my ($k,$u);
            $k->{node}   = $name;
            $u->{serial} = $serial;
            $u->{mtm}    = $model;
            $db{vpd}->setAttribs( $k,$u );
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
# Adds a hardware control point to the xCAT database
##########################################################################
sub add_ppch {

    my $hwtype  = shift;
    my $uid     = shift;
    my $pw      = shift;
    my $name    = shift;
    my $k;
    my $u;

    ###################################
    # Update HWCtrl Point table
    ###################################
    my $tab = xCAT::Table->new( 'ppch', -create=>1, -autocommit=>0 );
    if ( !$tab ) {
        return( "Error opening 'ppch'" );
    }
    $k->{hcp}      = $name;
    $u->{username} = $uid;
    $u->{password} = $pw;

    $tab->setAttribs( $k, $u );
    $tab->commit;
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

    my $type = shift;
    my $data = shift;
    my @tabs = qw(mpa mp nodehm nodelist);
    my %db   = ();

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
    # Update mpa table
    ###################################
    my ($k1,$u1);
    my $name = @$data[4];

    ####################################
    # N/A Values
    ####################################
    my $uid = undef;
    my $pw  = undef;

    $k1->{mpa}      = $name;
    $u1->{username} = $uid;
    $u1->{password} = $pw;
    $db{mpa}->setAttribs( $k1, $u1 );
    $db{mpa}->commit;

    ###################################
    # Update mp table
    ###################################
    my ($k2,$u2);
    $k2->{node} = $name;
    $u2->{mpa}  = $name;
    $u2->{id}   = "0";
    $db{mp}->setAttribs( $k2, $u2 );
    $db{mp}->commit;

    ###################################
    # Update nodehm table
    ###################################
    my ($k3,$u3);
    $k3->{node} = $name;
    $u3->{mgt}  = "blade";
    $db{nodehm}->setAttribs( $k3, $u3 );
    $db{nodehm}->commit;

    ###################################
    # Update nodelist table
    ###################################
    my ($k4,$u4);
    $k4->{node}   = $name;
    $u4->{groups} = lc($type).",all";
    $db{nodelist}->setAttribs( $k4, $u4 );
    $db{nodelist}->commit;

}



##########################################################################
# Get userids and passwords from tables
##########################################################################
sub credentials {

    my $server = shift;
    my $hwtype = shift;
    my %db = (
        hmc => "ppchcp",
        ivm => "ppchcp",
        fsp => "ppcdirect"
    );

    ###########################################
    # Get userid/password based on HwCtrl Pt
    ###########################################
    my $tab = xCAT::Table->new( $db{$hwtype} );
    if ( $tab ) {
        my ($ent) = $tab->getAttribs({'hcp'=>$server},'username','password');
        if ( defined( $ent ) ) {
            return( $ent->{username},$ent->{password} );
        }
    }
    ###########################################
    # Get userid/password based on type
    ###########################################
    $tab = xCAT::Table->new( 'passwd' );
    if ( $tab ) {
        my ($ent) = $tab->getAttribs({'key'=>$hwtype},'username','password');
        if ( defined( $ent ) ) {
            return( $ent->{username},$ent->{password} );
        }
    }
    ###########################################
    # Use factory defaults
    ###########################################
    my %logon = (
        hmc => ["hscroot","abc123"],
        ivm => ["padmin", "padmin"],
        fsp => ["admin",  "admin"]
    );
    return( @{$logon{$hwtype}}[0], @{$logon{$hwtype}}[1] );
}


1;






