#!/usr/bin/env perl

use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $spec_path = File::Spec->catfile( $repo_root, 'xCAT-client/xCAT-client.spec' );

open( my $spec_fh, '<', $spec_path ) or die "Unable to read $spec_path: $!";
my $spec = do { local $/; <$spec_fh> };
close($spec_fh);

my ($profile_body) = $spec =~ m{^cat << EOF > /etc/profile\.d/xcat\.sh\n(.*?)^EOF\n}ms;
ok( defined($profile_body), 'found the RPM-generated xcat.sh profile' )
  or BAIL_OUT('Unable to extract xcat.sh from xCAT-client.spec');

my $tempdir = tempdir( CLEANUP => 1 );
my $profile_path = File::Spec->catfile( $tempdir, 'xcat.sh' );
my $install_prefix = File::Spec->catdir( $tempdir, 'opt', 'xcat' );
my $render_script = <<"RENDER";
cat << EOF > "\$1"
$profile_body
EOF
RENDER

{
    local $ENV{RPM_INSTALL_PREFIX0} = $install_prefix;
    my $render_status = system(
        'bash', '--noprofile', '--norc', '-c',
        $render_script, 'bash', $profile_path
    );
    is( $render_status, 0, 'rendered xcat.sh using the RPM heredoc' )
      or BAIL_OUT('Unable to render xcat.sh from xCAT-client.spec');
}

my @cases = (
    {
        name => 'missing local Perl path under errexit',
        inc => '/usr/lib/perl5 /usr/share/perl5',
        expected => "reached\nPERL5LIB=/usr/local/share/perl5:sentinel\n",
    },
    {
        name => 'existing local Perl path under errexit',
        inc => '/usr/lib/perl5 /usr/local/share/perl5 /usr/share/perl5',
        expected => "reached\nPERL5LIB=sentinel\n",
    },
    {
        name => 'missing local Perl path under errexit and pipefail',
        inc => '/usr/lib/perl5 /usr/share/perl5',
        pipefail => 1,
        expected => "reached\nPERL5LIB=/usr/local/share/perl5:sentinel\n",
    },
);

for my $case (@cases) {
    subtest $case->{name} => sub {
        my ( $status, $output ) = run_profile( $profile_path, $case );

        is( $status, 0, 'sourcing continues' );
        is( $output, $case->{expected}, 'PERL5LIB has the expected value' );
    };
}

done_testing;

sub run_profile {
    my ( $path, $case ) = @_;
    my $runner = <<'BASH';
perl() {
    printf '%s' "$FAKE_PERL_INC"
}
export PERL5LIB=sentinel
. "$1"
printf 'reached\nPERL5LIB=%s\n' "$PERL5LIB"
BASH

    local $ENV{FAKE_PERL_INC} = $case->{inc};
    my @command = ( 'bash', '--noprofile', '--norc', '-e' );
    push @command, ( '-o', 'pipefail' ) if $case->{pipefail};
    push @command, ( '-c', $runner, 'bash', $path );

    open( my $output_fh, '-|', @command )
      or die "Unable to run generated xcat.sh: $!";
    my $output = do { local $/; <$output_fh> };
    close($output_fh);

    my $raw_status = $?;
    my $status = $raw_status == -1
      ? -1
      : ( $raw_status & 127 )
      ? 128 + ( $raw_status & 127 )
      : $raw_status >> 8;

    return ( $status, $output );
}
