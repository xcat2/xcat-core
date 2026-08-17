#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Version;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
    unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";

# do not put a use or require for  xCAT::Table here. Add to each new routine
# needing it to avoid reprocessing of user tables ( ExtTab.pm) for each command call
use strict;

#-------------------------------------------------------------------------------

=head3   Version
    Arguments:
        Optional 'short' string to request only the version;
    Returns:
       xcat Version number
    Globals:
        none
    Error:
        none
    Example:
         $version=xCAT::Version->Version();
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub Version
{

    #The following tags tells the build script where to append build info
    my $version = shift;
    if ($version eq 'short')
    {
        $version = ''    #XCATVERSIONSUBHERE ;
    }
    else
    {
        $version = 'Version '    #XCATVERSIONSUBHERE #XCATSVNBUILDSUBHERE ;
    }
    return $version;

}

#-------------------------------------------------------------------------------

=head3   Release
    Arguments:
        Optional version string; defaults to Version();
    Returns:
        the release part of the version, without the build-specific
        decoration the build stamps on, such as " (git commit <hash>)",
        so two nodes at the same release built from different snapshots
        compare equal.
    Globals:
        none
    Error:
        none
    Example:
         $release=xCAT::Version->Release($someversion);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub Release
{
    my $class = shift;
    my $version = shift;
    $version = $class->Version() unless defined $version;
    $version =~ s/\s*\(.*//s;
    return $version;
}

1;
