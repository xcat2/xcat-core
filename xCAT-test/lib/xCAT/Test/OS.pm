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

1;
