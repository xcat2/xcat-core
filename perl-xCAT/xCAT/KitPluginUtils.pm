#!/usr/bin/env perl
## IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::KitPluginUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";

use strict;
use warnings;

require xCAT::Table;


#-------------------------------------------------------

=head3  get_kits_used_by_nodes

    Get the kits used by a list of nodes. A node uses a kit
    if one or more of the kit's components are installed
    on the node.

    Arguments: list of node names (ref)

    Returns: Return hash table which indexes the node names
    by kitname (ref)
    e.g.,
         { "kitname1" => ["node11","node12",...],
           "kitname2" => ["node21","node22",...]
           ...
         }

    Examples:
        my @nodes = ("node11", "node12",...);
        my $result = xCAT::KitPluginUtils->get_kits_used_by_nodes(\@nodes);

=cut

#-------------------------------------------------------

sub get_kits_used_by_nodes {

    my $class = shift;
    my $nodes = shift;

    # Group the nodes by what osimage they use
    my $tablename = "nodetype";
    my $table     = xCAT::Table->new($tablename);
    my $ent       = $table->getNodesAttribs($nodes, ["provmethod"]);

    my $osimage_to_nodes = {};
    foreach my $node (keys(%$ent)) {
        my $provmethod = $ent->{$node}->[0]->{"provmethod"};
        if (defined($provmethod)) {
            push(@{ $osimage_to_nodes->{$provmethod} }, $node);
        }
    }

    # Group the osimages by what kits they use
    my @osimages = keys(%$osimage_to_nodes);
    my $kits_to_osimages = xCAT::KitPluginUtils->get_kits_used_by_osimages(\@osimages);


    # Group nodes by kit
    my $kits_to_nodes = {};
    foreach my $kit (keys(%$kits_to_osimages)) {
        my $tmphash  = {};
        my $osimages = $kits_to_osimages->{$kit};
        foreach my $osimage (@$osimages) {

            # Store nodes as hash keys to eliminate duplicates
            my @nodes = @{ $osimage_to_nodes->{$osimage} };
            @$tmphash{@nodes} = ();
        }
        my @nodes = keys(%$tmphash);
        $kits_to_nodes->{$kit} = \@nodes;
    }

    return $kits_to_nodes;
}


#-------------------------------------------------------

=head3  get_kits_used_by_osimages

    Get the kits used by a list of osimages. An osimage
    uses a kit if one or more of the kit's components
    are associated with the osimage.

    Arguments: list of osimage names (ref)

    Returns: Return hash table which indexes the osimage
    names by kitname (ref)
    e.g.,
         { "kitname1" => ["osimage11","osimage12",...],
           "kitname2" => ["osimage21","osimage22",...]
           ...
         }

    Examples:
      my @osimages = ("osimage11","osimage12", ...);
      my $result = xCAT::KitPluginUtils->get_kits_used_by_osimages(\@osimages);

=cut

#-------------------------------------------------------

sub get_kits_used_by_osimages {

    my $class    = shift;
    my $osimages = shift;

    # Get the kit components used by each osimage
    my $tablename = "osimage";
    my $table     = xCAT::Table->new($tablename);

    my $osimages_str = join ",", map { '\'' . $_ . '\'' } @$osimages;
    my $filter_stmt = sprintf("imagename in (%s)", $osimages_str);
    my @table_rows = $table->getAllAttribsWhere($filter_stmt, ("imagename", "kitcomponents"));

    my $kitcomps_to_osimages = {};
    foreach my $row (@table_rows) {
        if (defined($row->{kitcomponents})) {
            my @kitcomps = split(/,/, $row->{kitcomponents});
            foreach my $kitcomp (@kitcomps) {
                push(@{ $kitcomps_to_osimages->{$kitcomp} }, $row->{imagename});
            }
        }
    }

    # Get the kit for each kit component
    $tablename = "kitcomponent";
    $table     = xCAT::Table->new($tablename);

    my $kitcomps_str = join ",", map { '\'' . $_ . '\'' } keys(%$kitcomps_to_osimages);
    $filter_stmt = sprintf("kitcompname in (%s)", $kitcomps_str);
    @table_rows = $table->getAllAttribsWhere($filter_stmt, ("kitcompname", "kitname"));

    my $kits_to_kitcomps = {};
    foreach my $row (@table_rows) {
        my $kitname     = $row->{kitname};
        my $kitcompname = $row->{kitcompname};
        push(@{ $kits_to_kitcomps->{$kitname} }, $kitcompname);
    }

    # Match up kits to osimages

    my $kits_to_osimages = {};
    foreach my $kit (keys(%$kits_to_kitcomps)) {
        my $tmphash  = {};
        my $kitcomps = $kits_to_kitcomps->{$kit};
        foreach my $kitcomp (@$kitcomps) {

            # Store osimages as hash keys to eliminate duplicates
            my @osimages = @{ $kitcomps_to_osimages->{$kitcomp} };
            @$tmphash{@osimages} = ();
        }
        my @osimages = keys(%$tmphash);
        $kits_to_osimages->{$kit} = \@osimages;
    }

    return $kits_to_osimages;
}


#-------------------------------------------------------

=head3  get_kits_used_by_image_profiles

    Get the kits used by a list of image profiles.

    Arguments: list of image profile names (ref)

    Returns: Return hash table which indexes the image
    profile names by kitname (ref)
    e.g.,
         { "kitname1" => ["imgprofile11","imgprofile12",...],
           "kitname2" => ["imgprofile21","imgprofile22",...]
           ...
         }

    Examples:
      my @imgprofiles = ("imgprofile11","imgprofile12",...);
      my $result = xCAT::KitPluginUtils->get_kits_used_by_image_profiles(\@imgprofiles);

=cut

#-------------------------------------------------------

sub get_kits_used_by_image_profiles {

    my $class = shift;
    return xCAT::KitPluginUtils->get_kits_used_by_osimages(@_);
}


