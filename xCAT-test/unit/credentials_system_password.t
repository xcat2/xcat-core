#!/usr/bin/env perl
## no critic (TestingAndDebugging::ProhibitNoStrict)
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

BEGIN {
    package xCAT::Table;
    our %rows;
    our @opened;
    sub import { }
    sub new {
        my ($class, $table, @options) = @_;
        push @opened, [ $table, @options ];
        return bless { table => $table }, $class;
    }
    sub getAttribs {
        my ($self, $key, @columns) = @_;
        foreach my $row ( @{ $rows{ $self->{table} } || [] } ) {
            next if grep { !defined($row->{$_}) or $row->{$_} ne $key->{$_} } keys %$key;
            return { map { $_ => $row->{$_} } @columns };
        }
        return;
    }
    sub getNodeAttribs {
        my ($self, $node, $columns) = @_;
        return $self->getAttribs({ node => $node }, @$columns);
    }
    sub close { }
    $INC{'xCAT/Table.pm'} = 1;

    package xCAT::NodeRange;
    sub import {
        no strict 'refs';
        *{ caller() . '::noderange' } = \&noderange;
    }
    sub noderange { return ( $_[0] ); }
    $INC{'xCAT/NodeRange.pm'} = 1;

    package xCAT::Zone;
    sub import { }
    $INC{'xCAT/Zone.pm'} = 1;

    package xCAT::Utils;
    sub import { }
    sub isAIX { return 0; }
    sub isServiceNode { return 0; }
    $INC{'xCAT/Utils.pm'} = 1;

    package xCAT::NetworkUtils;
    sub import { }
    sub getipaddr { return (); }
    $INC{'xCAT/NetworkUtils.pm'} = 1;

    package xCAT::PasswordUtils;
    our @calls;
    sub import { }
    sub crypt_system_password {
        my ( $table, $key, $fields ) = @_;
        $key ||= { key => 'system', username => 'root' };
        push @calls, [ $table, {%$key}, $fields ? [@$fields] : undef ];
        return '$6$salt$' . $key->{username};
    }
    $INC{'xCAT/PasswordUtils.pm'} = 1;

    package xCAT::TableUtils;
    sub import { }
    sub get_site_attribute { return ('192.0.2.10'); }
    $INC{'xCAT/TableUtils.pm'} = 1;

    package xCAT::MsgUtils;
    our @traces;
    sub import { }
    sub trace { push @traces, [@_]; }
    sub message {
        my ( $class, $type, $rsp, $callback ) = @_;
        $callback->($rsp) if ref($callback) eq 'CODE';
    }
    $INC{'xCAT/MsgUtils.pm'} = 1;

    package LWP;
    sub import { }
    $INC{'LWP.pm'} = 1;

    package LWP::UserAgent;
    sub new { return bless {}, shift; }

    package HTTP::Request::Common;
    sub import {
        no strict 'refs';
        *{ caller() . '::GET' } = sub { return $_[0]; };
    }
    $INC{'HTTP/Request/Common.pm'} = 1;
}

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile(
    $repo_root, qw(xCAT-server lib xcat plugins credentials.pm)
);
require $plugin;

# The node callback on port 300 is the only part that needs a live node.
{
    no warnings qw(redefine once);
    *xCAT_plugin::credentials::ok_with_node = sub { return 1; };
}

sub request_hash {
    my ( $node, $parameter ) = @_;
    my @responses;
    @xCAT::PasswordUtils::calls = ();
    @xCAT::Table::opened        = ();
    @xCAT::MsgUtils::traces     = ();
    xCAT_plugin::credentials::process_request(
        {
            command          => ['getcredentials'],
            arg              => [$parameter],
            _xcat_clienthost => [$node],
            callback_port    => [300],
        },
        sub { push @responses, @_; }
    );
    return \@responses;
}

sub served_hash {
    my ($responses) = @_;
    my ($data) = grep { $_->{data} } @$responses;
    return unless $data;
    return ( $data->{data}->[0]->{content}->[0], $data->{data}->[0]->{desc}->[0] );
}

sub served_error {
    my ($responses) = @_;
    my ($error) = grep { $_->{error} } @$responses;
    return unless $error;
    return $error->{error}->[0];
}

%xCAT::Table::rows = (
    passwd => [
        { key => 'system', username => 'root', password => 'rootpw',   cryptmethod => undef },
        { key => 'system', username => 'xcat', password => 'sudoerpw', cryptmethod => 'sha512' },
        { key => 'system', username => 'ops',  password => 'opspw',    cryptmethod => undef },
        { key => 'system', username => 'img',  password => 'imgpw',    cryptmethod => undef },
        { key => 'system', username => 'nopw', password => undef,      cryptmethod => undef },
    ],
    postscripts => [
        { node => 'xcatdefaults', postscripts => 'syslog,remoteshell', postbootscripts => 'otherpkgs' },
        { node => 'compute-01',   postscripts => 'sudoer,confignetwork', postbootscripts => undef },
        { node => 'compute-02',   postscripts => undef, postbootscripts => 'sudoer -u ops' },
        { node => 'compute-03',   postscripts => 'confignetwork', postbootscripts => undef },
        { node => 'compute-04',   postscripts => undef, postbootscripts => undef },
        { node => 'compute-05',   postscripts => 'sudoer -unopw', postbootscripts => undef },
    ],
    nodetype => [
        { node => 'compute-01', provmethod => 'install' },
        { node => 'compute-04', provmethod => 'alma9-x86_64-install-compute' },
    ],
    osimage => [
        { imagename => 'alma9-x86_64-install-compute', postscripts => 'sudoer -u img', postbootscripts => undef },
    ],
);

{
    my ( $hash, $desc ) = served_hash( request_hash( 'compute-03', 'xcat_secure_pw:root' ) );
    is( $hash, '$6$salt$root', 'root hash is served without a sudoer entry' );
    is( $desc, 'xcat_secure_pw:root', 'the reply names the requested credential' );
    is_deeply(
        $xCAT::PasswordUtils::calls[0],
        [ 'passwd', { key => 'system', username => 'root' }, [ 'password', 'cryptmethod' ] ],
        'root is hashed from the passwd row key=system,username=root'
    );
}

{
    my ( $hash, $desc ) = served_hash( request_hash( 'compute-01', 'xcat_secure_pw:xcat' ) );
    is( $hash, '$6$salt$xcat', 'the default sudoer of a node with the sudoer postscript gets its hash' );
    is( $desc, 'xcat_secure_pw:xcat', 'the reply names the sudoer credential' );
    is_deeply(
        $xCAT::PasswordUtils::calls[0],
        [ 'passwd', { key => 'system', username => 'xcat' }, [ 'password', 'cryptmethod' ] ],
        'the sudoer is hashed from the passwd row key=system,username=xcat'
    );
}

{
    my $responses = request_hash( 'compute-01', 'xcat_secure_pw:ops' );
    ok( !defined( ( served_hash($responses) )[0] ), 'a user that is not the configured sudoer gets no hash' );
    like( served_error($responses), qr/ops is not a configured sudoer of compute-01/,
        'the reply says the user is not configured for the node' );
    is( scalar @xCAT::PasswordUtils::calls, 0, 'nothing is hashed for an unconfigured user' );
}

{
    my ( $hash ) = served_hash( request_hash( 'compute-02', 'xcat_secure_pw:ops' ) );
    is( $hash, '$6$salt$ops', 'a sudoer named with -u in postbootscripts gets its hash' );
    my $responses = request_hash( 'compute-02', 'xcat_secure_pw:xcat' );
    like( served_error($responses), qr/xcat is not a configured sudoer/,
        'the default name is not served when the node names another sudoer' );
}

{
    my $responses = request_hash( 'compute-03', 'xcat_secure_pw:xcat' );
    ok( !defined( ( served_hash($responses) )[0] ), 'a node without the sudoer postscript gets no hash' );
    like( served_error($responses), qr/not a configured sudoer of compute-03/,
        'the reply names the node without the postscript' );
}

{
    my ( $hash ) = served_hash( request_hash( 'compute-04', 'xcat_secure_pw:img' ) );
    is( $hash, '$6$salt$img', 'a sudoer configured on the osimage of provmethod gets its hash' );
}

{
    local $xCAT::Table::rows{postscripts}->[0]->{postbootscripts} = 'otherpkgs,sudoer -u ops';
    my ( $hash ) = served_hash( request_hash( 'compute-03', 'xcat_secure_pw:ops' ) );
    is( $hash, '$6$salt$ops', 'a sudoer configured in xcatdefaults applies to every node' );
}

{
    my ( $field, $desc ) = served_hash( request_hash( 'compute-05', 'xcat_secure_pw:nopw' ) );
    is( $field, '!', 'a sudoer row without a password gets the locked field' );
    is( $desc, 'xcat_secure_pw:nopw', 'the locked reply names the sudoer credential' );
    is( scalar @xCAT::PasswordUtils::calls, 0, 'nothing is hashed for an empty password' );
}

{
    local $xCAT::Table::rows{passwd} = [ grep { $_->{username} ne 'xcat' } @{ $xCAT::Table::rows{passwd} } ];
    my ( $field ) = served_hash( request_hash( 'compute-01', 'xcat_secure_pw:xcat' ) );
    is( $field, '!', 'a sudoer without a passwd row gets the locked field' );
}

{
    local $xCAT::Table::rows{passwd} = [ grep { $_->{username} ne 'root' } @{ $xCAT::Table::rows{passwd} } ];
    my $responses = request_hash( 'compute-01', 'xcat_secure_pw:root' );
    ok( !defined( ( served_hash($responses) )[0] ), 'root without a passwd row is not locked' );
    like( served_error($responses), qr/no password in the passwd table for root/,
        'root without a passwd row answers with an error' );
}

{
    my $responses = request_hash( 'compute-01', 'xcat_secure_pw:../root' );
    ok( !defined( ( served_hash($responses) )[0] ), 'an invalid user name gets no hash' );
    like( served_error($responses), qr/invalid user name/, 'the reply carries an error for an invalid name' );
    is( scalar @xCAT::Table::opened, 0, 'an invalid user name never reaches a table' );
}

{
    my $responses = request_hash( 'compute-01', 'xcat_secure_pw:' );
    ok( !defined( ( served_hash($responses) )[0] ), 'a missing user name gets no hash' );
    is( scalar @xCAT::Table::opened, 0, 'a missing user name never reaches a table' );
}

done_testing();
