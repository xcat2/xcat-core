#!/usr/bin/env perl
# The artifacts under test are an Apache configuration fragment and an RPM spec.
# Neither one executes, and in both the text IS the contract, so this test parses
# them instead of running them: the fragment into directives and enclosing
# sections, the spec into its scriptlet sections.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $wsapi_dir = 'xCAT-server/xCAT-wsapi';

#-----------------------------------------------------------------------------

=head3 parse_apache_fragment

    Descriptions: Parses an Apache configuration fragment.
    Arguments: the fragment contents
    Returns: a list of hash references, one per directive, each with the
             directive name, its arguments and the enclosing sections from the
             outside in. A section is recorded as its name plus its argument,
             for example "IfModule mod_rewrite.c".
=cut

#-----------------------------------------------------------------------------
sub parse_apache_fragment {
    my ($contents) = @_;
    my (@directives, @open_sections);

    foreach my $line ( split( /\n/, $contents ) ) {
        my $text = $line;
        $text =~ s/^\s+//;
        $text =~ s/\s+$//;
        next unless length $text;
        next if $text =~ /^#/;

        if ( $text =~ m{^</(\w+)\s*>$} ) {
            my $closed = pop @open_sections;
            die "Unbalanced </$1> in an Apache fragment" unless defined $closed;
            next;
        }
        if ( $text =~ m{^<(\w+)\s*(.*?)\s*>$} ) {
            my ( $name, $argument ) = ( $1, $2 );
            $argument =~ s/^"(.*)"$/$1/;
            push @open_sections,
              length($argument) ? "$name $argument" : $name;
            next;
        }

        my ( $directive, @arguments ) = split( /\s+/, $text );
        push @directives,
          {
            directive => $directive,
            arguments => [@arguments],
            sections  => [@open_sections],
          };
    }

    die 'An Apache fragment left a section open' if @open_sections;
    return @directives;
}

#-----------------------------------------------------------------------------

=head3 parse_spec_sections

    Descriptions: Splits an RPM spec into its sections.
    Arguments: the spec contents
    Returns: a hash reference keyed on the section name without the leading
             percent sign, each value the lines of that section.
=cut

#-----------------------------------------------------------------------------
sub parse_spec_sections {
    my ($contents) = @_;
    my %section;
    my $current = 'preamble';

    foreach my $line ( split( /\n/, $contents ) ) {
        if ( $line =~ /^%(build|install|clean|files|pre|post|preun|postun|posttrans|changelog|description|package)\b/ ) {
            $current = $1;
            $section{$current} ||= [];
            next;
        }
        push @{ $section{$current} ||= [] }, $line;
    }

    return \%section;
}

sub guarded_by {
    my ( $directive, $section ) = @_;
    return scalar grep { $_ eq $section } @{ $directive->{sections} };
}

#-----------------------------------------------------------------------------
# The fragments xCAT-server ships to the RPM families (EL, openEuler, SUSE).
# xcat-ws.conf.ubuntu is excluded on purpose: only debian/rules uses it, and
# Debian keeps its Apache modules in one stable directory on every release.
#-----------------------------------------------------------------------------
my @fragments = sort grep { !m{\.ubuntu$} }
  map { my $p = $_; $p =~ s{^.*/(xCAT-server/)}{$1}; $p }
  glob( repo_path("$wsapi_dir/xcat-ws.conf*") );

die "No Apache fragment found under $wsapi_dir; the test can measure nothing\n"
  unless @fragments;

foreach my $fragment (@fragments) {
    my @directives = parse_apache_fragment( slurp_repo_file($fragment) );

    # The defect: a LoadModule naming one distribution's MPM directory. The
    # path is absent on EL and openEuler, and absent on SUSE under any MPM but
    # prefork, and a LoadModule whose file is missing stops Apache from starting.
    my @load_module = grep { lc( $_->{directive} ) eq 'loadmodule' } @directives;
    is( scalar @load_module, 0,
        "$fragment declares no LoadModule, so the server owns module loading" )
      or diag( 'LoadModule found: '
          . join( ', ', map { join( ' ', @{ $_->{arguments} } ) } @load_module ) );

    my @absolute = grep {
        my $d = $_;
        grep { m{^/} } @{ $d->{arguments} }
    } @directives;
    is( scalar @absolute, 0,
        "$fragment names no absolute filesystem path, so no distribution layout is assumed" )
      or diag( 'absolute path in: '
          . join( ', ', map { $_->{directive} } @absolute ) );

    # One file must serve Apache 2.2 and 2.4. mod_rewrite may be absent, so the
    # redirect is guarded rather than loaded; the authorization directives come
    # in both generations' spellings, each behind its own guard.
    my @rewrite = grep { lc( $_->{directive} ) =~ /^rewrite/ } @directives;
    ok( scalar @rewrite, "$fragment still redirects http to https" );
    foreach my $directive (@rewrite) {
        ok( guarded_by( $directive, 'IfModule mod_rewrite.c' ),
            "$fragment guards $directive->{directive} with <IfModule mod_rewrite.c>" );
    }

    my @modern = grep { lc( $_->{directive} ) eq 'require' } @directives;
    my @legacy = grep { lc( $_->{directive} ) =~ /^(order|allow|deny)$/ } @directives;
    ok( scalar @modern, "$fragment grants access in the Apache 2.4 spelling" );
    ok( scalar @legacy, "$fragment grants access in the Apache 2.2 spelling" );
    foreach my $directive (@modern) {
        ok( guarded_by( $directive, 'IfModule mod_authz_core.c' ),
            "$fragment guards $directive->{directive} with <IfModule mod_authz_core.c>" );
    }
    foreach my $directive (@legacy) {
        ok( guarded_by( $directive, 'IfModule !mod_authz_core.c' ),
            "$fragment guards $directive->{directive} with <IfModule !mod_authz_core.c>" );
    }
}

#-----------------------------------------------------------------------------
# The packaging half. %post must not replace the conf the payload installed:
# every supported distribution runs Apache 2.4, so a replacement always happens
# and "rpm -V xCAT-server" then reports the file changed on every management
# node, for ever.
#-----------------------------------------------------------------------------
my $spec = parse_spec_sections( slurp_repo_file('xCAT-server/xCAT-server.spec') );

my @live_paths =
  ( '/etc/httpd/conf.d/xcat-ws.conf', '/etc/apache2/conf.d/xcat-ws.conf' );

foreach my $path (@live_paths) {
    my @post = grep { index( $_, $path ) >= 0 } @{ $spec->{post} };
    is( scalar @post, 0,
        "%post never names $path, so it cannot replace the installed payload" );
    diag("%post line: $_") foreach @post;

    my @install = grep { /^\s*cp\s.*\Q$path\E\s*$/ } @{ $spec->{install} };
    ok( scalar @install, "%install installs $path as package payload" );

    ok( scalar( grep { /^\Q$path\E\s*$/ } @{ $spec->{files} } ),
        "%files owns $path, so rpm verifies it" );
}

# The LoadModule removed from the fragment is replaced by the distribution's own
# module management. On SUSE apache2 that is a2enmod, as xCAT.spec already does
# for mod_headers; on EL conf.modules.d loads mod_rewrite already.
ok( scalar( grep { /\ba2enmod\s+rewrite\b/ } @{ $spec->{post} } ),
    '%post enables mod_rewrite where a2enmod manages modules' );

done_testing();
