#!/usr/bin/perl
## IBM(c) 2017 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::OPENBMC;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use HTTP::Async;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Cookies;
use Data::Dumper;
use Time::HiRes qw(sleep time);
use JSON;
use File::Path;
use xCAT_monitoring::monitorctrl;
use xCAT::TableUtils;

my $PYTHON_AGENT_FILE = "/opt/xcat/lib/python/agent/agent.py";

my $header = HTTP::Headers->new('Content-Type' => 'application/json');
# Currently not used, example of header to use for authorization
#my $header = HTTP::Headers->new('X-Auth-Token' => 'xfMHrrxdMgbiITnX0TlN');

sub new {
    my $async = shift;
    $async = shift if (($async) && ($async =~ /OPENBMC/));
    my $url = shift;
    my $content = shift;
    my $method = 'POST';

    my $id = send_request( $async, $method, $url, $content );

    return $id;
}

sub send_request {
    my $async = shift;
    $async = shift if (($async) && ($async =~ /OPENBMC/));
    my $method = shift;
    my $url = shift;
    my $content = shift;
    my $username = shift;
    my $password = shift;

    my $request = HTTP::Request->new( $method, $url, $header, $content );
    if (defined $username and defined $password) {
        # If username and password were passed in use authorization_basic()
        # This is required to connect to BMC with OP940 level, ignored for 
        # lower OP levels
        $request->authorization_basic($username, $password);
    }
    my $id = $async->add_with_opts($request, {});
    return $id;
}

#--------------------------------------------------------------------------------

=head3 run_cmd_in_perl
      Check if specified command should run in perl
      The policy is:
            Get value from `openbmcperl`, `XCAT_OPENBMC_DEVEL`, agent.py:

            1. If agent.py does not exist:                          ==> 1: Go Perl
            2. If `openbmcperl` not set or doesn't contain command: ==> 0: Go Python
            3. If `openbmcperl` lists the command OR set to "ALL"   ==> 1: Go Perl
            4. If command is one of unsupported commands AND
                  a. XCAT_OPENBMC_DEVEL = YES                       ==> 0: Go Python
                  b. XCAT_OPENBMC_DEVEL = NO or not set             ==> 1: Go Perl
=cut

#--------------------------------------------------------------------------------
sub run_cmd_in_perl {
    my ($class, $command, $env) = @_;
    if (! -e $PYTHON_AGENT_FILE) {
        return (1, ''); # Go Perl: agent file is not there
    }

    my @entries = xCAT::TableUtils->get_site_attribute("openbmcperl");
    my $site_entry = $entries[0];
    my $support_obmc = undef;
    if (ref($env) eq 'ARRAY' and ref($env->[0]->{XCAT_OPENBMC_DEVEL}) eq 'ARRAY') {
        $support_obmc = $env->[0]->{XCAT_OPENBMC_DEVEL}->[0];
    } elsif (ref($env) eq 'ARRAY') {
        $support_obmc = $env->[0]->{XCAT_OPENBMC_DEVEL};
    } else {
        $support_obmc = $env->{XCAT_OPENBMC_DEVEL};
    }
    if ($support_obmc and uc($support_obmc) ne 'YES' and uc($support_obmc) ne 'NO') {
        return (-1, "Invalid value $support_obmc for XCAT_OPENBMC_DEVEL, only 'YES' and 'NO' are supported.");
    }
    if ($site_entry and ($site_entry =~ $command or uc($site_entry) eq "ALL")) {
        return (1, ''); # Go Perl: command listed in "openbmcperl" or "ALL"
    }

    # List of commands currently not supported in Python
    my @unsupported_in_python_commands = ('rflash', 'getopenbmccons');

    my @temp = grep ({$command =~ $_ } @unsupported_in_python_commands);
    if ( $command eq $temp[0]) {
        # Command currently not supported in Python
        if ($support_obmc and uc($support_obmc) eq 'YES') {
            return (0, ''); # Go Python: unsuppored command, but XCAT_OPENBMC_DEVEL=YES overrides
        } else {
            return (1, ''); # Go Perl: unsuppored command
        }
    }

    return (0, ''); # Go Python: default
}

1;
