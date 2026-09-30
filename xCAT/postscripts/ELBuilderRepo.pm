package ELBuilderRepo;

# The repository ids that carry the EL builder packages.
#
# xCAT-server requires perl-IO-Tty, perl-Crypt-CBC, perl-Crypt-Rijndael and perl(Expect). EL
# keeps them in the distribution builder repository, which is disabled on a fresh install, so
# dnf install xCATsn on a service node does not resolve. Every vendor names that repository
# differently and the name changed at EL9: it is not crb on EL8.
#
# This module ships in /install/postscripts and is copied to /xcatpost with the postscripts, so
# it loads on a node that has no xCAT packages yet.

use strict;
use warnings;

#-----------------------------------------------------------------------------

=head3 builder_repo_ids

    Arguments:
        $vendor  the ID field of /etc/os-release, for example almalinux, rocky, centos, rhel, ol
        $major   the EL major version, 8, 9 or 10
        $arch    the machine architecture. Only the RHEL id carries one

    Returns:
        the repository ids to try, most likely first, or an empty list when the arguments name
        no EL release. An empty list is the answer for "do not guess".

    Covered: AlmaLinux, Rocky and CentOS Stream (crb on 9 and later, powertools on 8, with the
    EL8 names it powertools, and Rocky 8.4 and earlier capitalised it. RHEL and Oracle Linux
    each have their own name. An unknown vendor takes the community spelling.

=cut

#-----------------------------------------------------------------------------
sub builder_repo_ids {
    my ($vendor, $major, $arch) = @_;

    return () unless defined $vendor && length $vendor;
    return () unless defined $major  && $major =~ /^\d+$/;
    $arch = 'x86_64' unless defined $arch && length $arch;

    return ("codeready-builder-for-rhel-$major-$arch-rpms") if $vendor eq 'rhel';
    return ("ol${major}_codeready_builder")                 if $vendor eq 'ol';
    return ('powertools', 'PowerTools')                     if $major == 8;
    return ('crb');
}

#-----------------------------------------------------------------------------

=head3 enable_repo_commands

    Arguments:
        $vendor  the ID field of /etc/os-release
        $repo    the repository id to enable
        $has_sm  true when subscription-manager is installed

    Returns:
        the commands to try, in order, until one succeeds. An empty list when there is no
        repository id.

    A vendor whose repositories come from subscription-manager gets that command first, and
    config-manager as the fallback. Every other vendor gets config-manager alone.

=cut

#-----------------------------------------------------------------------------
sub enable_repo_commands {
    my ($vendor, $repo, $has_sm) = @_;

    return () unless defined $repo && length $repo;

    my @cmds;
    push @cmds, "subscription-manager repos --enable=$repo"
      if $has_sm && uses_subscription_manager($vendor);
    push @cmds, "dnf config-manager --set-enabled $repo";
    return @cmds;
}

#-----------------------------------------------------------------------------

=head3 uses_subscription_manager

    Arguments:
        $vendor  the ID field of /etc/os-release

    Returns:
        true when this vendor keeps its repositories in a file that subscription-manager owns.

    subscription-manager rewrites /etc/yum.repos.d/redhat.repo, so a config-manager change
    there does not survive its next refresh.

=cut

#-----------------------------------------------------------------------------
sub uses_subscription_manager {
    my ($vendor) = @_;
    return defined $vendor && $vendor eq 'rhel' ? 1 : 0;
}

1;
