package xCAT::Test::OS;

use strict;
use warnings;

#-----------------------------------------------------------------------------

=head1 NAME

xCAT::Test::OS - the operating system names xcattest matches a case against

=head1 DESCRIPTION

A test case declares the distributions it runs on in its C<os:> attribute, and xcattest compares
that list against the distribution it is running on. Both halves of the comparison live here, so a
distribution is named in one place and a unit test can call them.

=cut

#-----------------------------------------------------------------------------

#---
# =head3 linux_aliases
# Descriptions: the distributions a case's `os:Linux` stands for.
# Arguments: none
# Returns: the list of os names
#---
sub linux_aliases {
    return qw(rhels sles ubuntu openeuler);
}

#---
# =head3 current_os
# Descriptions: the os name of the running system, in the spelling a case's `os:` attribute uses.
# Arguments: $root - a path prefix, for tests
# Returns: an os name, or undef
#---
sub current_os {
    my ($root) = @_;
    $root = '' unless defined $root;

    if (-f "$root/etc/redhat-release") {
        my $text = _slurp("$root/etc/redhat-release");
        my ($major) = (defined($text) && $text =~ /(\d+)\.(\d*)/) ? ($1) : ('');
        return "rhels$major";
    }
    return 'ubuntu' if -f "$root/etc/lsb-release";

    if (-f "$root/etc/os-release") {
        my $text = _slurp("$root/etc/os-release") // '';
        return 'sles' if $text =~ /sles/;
        if ($text =~ /^ID\s*=\s*"?openeuler"?\s*$/mi) {
            my ($version) = $text =~ /^VERSION\s*=\s*"?([^"\n]+?)"?\s*$/mi;
            my $release = _openeuler_release($version);
            return defined($release) ? "openeuler$release" : 'openeuler';
        }
        return undef;
    }
    return 'sles' if -f "$root/etc/SuSE-release";
    return 'aix';
}

#---
# =head3 _openeuler_release
# Descriptions: the release token openEuler's osimage names carry, from an os-release VERSION.
# Arguments: $version - the VERSION value of /etc/os-release
# Returns: a release token, or undef
#---
sub _openeuler_release {
    my ($version) = @_;
    return undef unless defined $version;
    $version =~ s/^\s+|\s+$//g;
    my ($release, $sp) = $version =~ /\A((?:20|22|24)\.03)(?:\s*\(LTS(?:-SP([1-9][0-9]*))?\))?\z/i
        or return undef;
    return $release . (defined($sp) ? "sp$sp" : '');
}

sub _slurp {
    my ($path) = @_;
    open my $fh, '<', $path or return undef;
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}


#-------------------------------------------------------

=head3 shell_quote

    Descriptions: Quote a value so a shell passes it through unchanged.
    Arguments: the value
    Returns: the value in single quotes, with any single quote escaped
=cut

#-------------------------------------------------------
sub shell_quote
{
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/'/'\\''/g;
    return "'" . $value . "'";
}

#-------------------------------------------------------

=head3 object_definition_command

    Descriptions: The chdef command that defines one object from a conf section.
                  Attribute values are quoted, because a conf carries values a
                  shell would read as syntax: vmothersetting separates its
                  settings with a semicolon, which ends the command.
    Arguments: the object type, the object name, a hash reference of attributes
    Returns: the command
=cut

#-------------------------------------------------------
sub object_definition_command
{
    my ($type, $name, $attrs) = @_;

    my $cmd = "chdef -t " . shell_quote($type) . " -o " . shell_quote($name);
    foreach my $attr (sort keys %$attrs) {
        $cmd .= " " . shell_quote("$attr=" . $attrs->{$attr});
    }
    return $cmd;
}

#-------------------------------------------------------

=head3 parse_conf_assignment

    Descriptions: Read one "attr=value" line of a conf section.
                  The value class carries ':' and '/' so an IPv6 network
                  reaches the table: without them "net=2001:db8:176::" matched
                  "2001" and the row was written with that value. It carries
                  ';' for the same reason, because othersettings and
                  vmothersetting separate their settings with one and the row
                  was written with the first setting alone.
    Arguments: the line
    Returns: the attribute and the value, or an empty list when the line is
             not an assignment

=cut

#-------------------------------------------------------
sub parse_conf_assignment
{
    my ($line) = @_;

    return unless defined $line;
    return unless $line =~ /(\w+)\s*=\s*([:,;\w\.\-\/]+)/;
    return ($1, $2);
}

#-------------------------------------------------------

=head3 table_row_command

    Descriptions: The chtab command that writes one table row from a conf
                  section. Every argument is quoted, the row selector with
                  them: a conf carries values a shell reads as syntax, and
                  othersettings separates its settings with a semicolon, which
                  would end the command and run the rest.
    Arguments: the table name, the key column, the row name, a hash reference
               of attributes
    Returns: the command

=cut

#-------------------------------------------------------
sub table_row_command
{
    my ($table, $key, $name, $attrs) = @_;

    my $cmd = "chtab " . shell_quote("$key=$name");
    foreach my $attr (sort keys %$attrs) {
        next if $attr eq '__KEY__';
        $cmd .= " " . shell_quote("$table.$attr=" . $attrs->{$attr});
    }
    return $cmd;
}

1;
