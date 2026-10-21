package xCAT::Test::Conf;

use strict;
use warnings;

#-------------------------------------------------------------------------------

=head1 NAME

xCAT::Test::Conf - the lines and commands of an xcattest configuration file

=head1 DESCRIPTION

xcattest reads a configuration file and applies its [Object_*] and [Table_*] blocks to the
xCAT database before the first case runs. The routines here read one line of such a block and
build the command that applies it. Each one takes its input and returns its answer, so the
reader and the command can be measured without a database.

=cut

#-------------------------------------------------------------------------------

=head3 object_attr

    Descriptions:
        The attribute and value of one line of an [Object_*] block.
    Arguments:
        $line - the line, with or without leading whitespace
    Returns:
        ($attr, $value), or the empty list when the line holds no assignment

=cut

#-------------------------------------------------------------------------------
sub object_attr {
    my ($line) = @_;
    return () unless defined $line;
    return ($1, $2) if $line =~ /(\w+)\s*=\s*([:,\w\.\-\/]+)/;
    return ();
}

#-------------------------------------------------------------------------------

=head3 table_attr

    Descriptions:
        The attribute and value of one line of a [Table_*] block.
    Arguments:
        $line - the line, with or without leading whitespace
    Returns:
        ($attr, $value), or the empty list when the line holds no assignment

=cut

#-------------------------------------------------------------------------------
sub table_attr {
    my ($line) = @_;
    return () unless defined $line;
    return ($1, $2) if $line =~ /(\w+)\s*=\s*([\w\.\-]+)/;
    return ();
}

#-------------------------------------------------------------------------------

=head3 var_attr

    Descriptions:
        The name and value of one line of the [System] or [Custom] block.
    Arguments:
        $line - the line, with or without leading whitespace
    Returns:
        ($name, $value), or the empty list when the line holds no assignment

=cut

#-------------------------------------------------------------------------------
sub var_attr {
    my ($line) = @_;
    return () unless defined $line;
    return ($1, $2) if $line =~ /(\w+)\s*=\s*([\w\.\-\+\ \/:]+)/;
    return ();
}

#-------------------------------------------------------------------------------

=head3 chdef_command

    Descriptions:
        The chdef command that applies one object of an [Object_*] block.
    Arguments:
        $type - the object type, as the section name spells it
        $name - the object name
        $attrs - a hash reference of attribute to value
    Returns:
        the command

=cut

#-------------------------------------------------------------------------------
sub chdef_command {
    my ($type, $name, $attrs) = @_;
    my $cmd = "chdef -t $type -o $name";
    foreach my $attr (keys %$attrs) {
        $cmd .= " $attr=$attrs->{$attr}";
    }
    return $cmd;
}

1;
