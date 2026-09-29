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
    capitalised PowerTools that Rocky 8.4 and earlier shipped after it), RHEL
    (codeready-builder-for-rhel-<major>-<arch>-rpms) and Oracle Linux
    (ol<major>_codeready_builder). Another vendor takes the community spellings, which is a
    guess.

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

1;
