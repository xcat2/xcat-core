#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use xCAT::Template;

local $::XCATROOT = '/opt/xcat-from-package';

{
    local $ENV{XCATROOT} = '/opt/xcat-from-environment';
    is(
        xCAT::Template::envvar('XCATROOT'),
        '/opt/xcat-from-environment',
        'an explicit XCATROOT environment value keeps precedence',
    );
}

{
    local $ENV{XCATROOT};
    delete $ENV{XCATROOT};
    is(
        xCAT::Template::envvar('$XCATROOT'),
        '/opt/xcat-from-package',
        'the package global supplies XCATROOT when the environment omits it',
    );
}

{
    local $ENV{XCATROOT} = '';
    is(
        xCAT::Template::envvar('XCATROOT'),
        '',
        'an explicitly empty XCATROOT is not replaced by the fallback',
    );
}

{
    local $ENV{TEMPLATE_ENVVAR_TEST} = 'from-environment';
    is(
        xCAT::Template::envvar('TEMPLATE_ENVVAR_TEST'),
        'from-environment',
        'other template environment variables remain unchanged',
    );
}

done_testing();
