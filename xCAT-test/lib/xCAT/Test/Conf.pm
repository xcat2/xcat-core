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

        The semicolon is in the value, because vm.othersettings separates its settings with
        one. chdef_command quotes what this routine returns.
    Arguments:
        $line - the line, with or without leading whitespace
    Returns:
        ($attr, $value), or the empty list when the line holds no assignment

=cut

#-------------------------------------------------------------------------------
sub object_attr {
    my ($line) = @_;
    return () unless defined $line;
    return ($1, $2) if $line =~ /(\w+)\s*=\s*([:,;\w\.\-\/]+)/;
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
    # The same value class as object_attr. A table value holds the same kinds of thing an object
    # value does: an IPv6 prefix (2001:db8::/64), a path (/install), a comma-separated list of
    # name servers. The narrower ([\w\.\-]+) this replaces stopped at the first colon or slash and
    # wrote the truncated value, so `net=2001:db8:176::/64` reached chtab as `net=2001` and
    # xcattest re-applied that row on every run. Nothing warned.
    #
    # The class holds no whitespace and no '#', so a trailing inline comment is still excluded.
    return ($1, $2) if $line =~ /(\w+)\s*=\s*([:,;\w\.\-\/]+)/;
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

        xcattest runs every command through /bin/bash -c, so each word is quoted. A
        vm.othersettings value carries a semicolon, which bash reads as a command separator.

        The assignments are sorted, so one conf builds one command.
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
    my @words = ($type, $name);
    foreach my $attr (sort keys %$attrs) {
        my $value = defined $attrs->{$attr} ? $attrs->{$attr} : '';
        push @words, "$attr=$value";
    }
    my ($qtype, $qname, @qattrs) = map { _quote($_) } @words;
    return join ' ', 'chdef', '-t', $qtype, '-o', $qname, @qattrs;
}

#-------------------------------------------------------------------------------

=head3 chtab_command

    Descriptions:
        The chtab command that applies one row of a [Table_*] block.

        xcattest runs every command through /bin/bash -c, so each word is quoted, the row
        selector too. A vm.othersettings value carries a semicolon.

        The assignments are sorted, so one conf builds one command.
    Arguments:
        $table - the table name, as the section name spells it
        $key - the key column of the row
        $name - the value of the key column
        $attrs - a hash reference of column to value
    Returns:
        the command

=cut

#-------------------------------------------------------------------------------
sub chtab_command {
    my ($table, $key, $name, $attrs) = @_;
    my @words = ("$key=$name");
    foreach my $attr (sort keys %$attrs) {
        next if $attr eq '__KEY__';
        my $value = defined $attrs->{$attr} ? $attrs->{$attr} : '';
        push @words, "$table.$attr=$value";
    }
    return join ' ', 'chtab', map { _quote($_) } @words;
}

#-------------------------------------------------------------------------------

=head3 _quote

    Descriptions:
        One word of a command for /bin/bash -c. Single quotes stop the shell from reading any
        character of the word, and a single quote inside the word closes and reopens them.
    Arguments:
        $word - the word
    Returns:
        the quoted word

=cut

#-------------------------------------------------------------------------------
sub _quote {
    my ($word) = @_;
    $word = '' unless defined $word;
    $word =~ s/'/'\\''/g;
    return "'$word'";
}

1;
