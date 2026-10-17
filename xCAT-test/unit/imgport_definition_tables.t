#!/usr/bin/env perl
use strict;
use warnings;
use DBI;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db", "$fixture/install");
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'installdir' }, { value => "$fixture/install" });

# The import locks live in /var/lock/xcat, so the test grants them.
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub { return (0, {}) };
    *xCAT::Utils::acquire_lock         = sub { return {} };
}

my $published = "image that packimage published\n";
my $sequence  = 0;
my $new       = \&xCAT::Table::new;

for my $case (map { ([ $_, 0 ], [ $_, 1 ]) } qw(osimage linuximage kit kitrepo kitcomponent)) {
    # The import cannot open a table of the image definition, or only without autocommit, as set_config opens it.
    my ($table, $transaction) = @$case;
    my $label = $transaction ? "$table without autocommit" : $table;
    my $name   = 'tables-' . ++$sequence;
    my $dest   = "$fixture/install/netboot/$name";
    my $bundle = "$fixture/bundle-$sequence";
    make_path($dest, $bundle);
    write_text("$dest/rootimg.cpio.gz",        $published);
    write_text("$dest/rootimg.cpio.gz.sha256", sha256_hex($published) . "  rootimg.cpio.gz\n");
    write_text("$dest/$_",   "published $_\n")       for qw(kernel initrd-stateless.gz);
    write_text("$bundle/$_", "$_ from the bundle\n") for qw(rootimg.cpio.gz kernel initrd-stateless.gz);
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name }, { osvers => 'rhels9.5', provmethod => 'netboot' });
    my @errors;
    my $placed;
    {
        no warnings 'redefine';
        local *xCAT::Table::new = sub {
            my (undef, $opened, %args) = @_;
            return if $opened eq $table && caller() eq 'xCAT_plugin::imgport' && (!$transaction || defined $args{-autocommit} && !$args{-autocommit});
            goto &$new;
        };
        $placed = xCAT_plugin::imgport::place_image(
            {
                rootimg => "$dest/rootimg.cpio.gz",
                kernel  => "$dest/kernel",
                ramdisk => "$dest/initrd-stateless.gz",
                osimage => { imagename => $name, osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' },
            },
            $bundle, sub { push @errors, @{ $_[0]{error} || [] } });
    }
    ok(!$placed, "$label: an import fails when it cannot open the table");
    like(join("\n", @errors), qr/Unable to open table '\Q$table\E'/, "$label: the table is reported");
    is(read_binary("$dest/rootimg.cpio.gz"), $published, "$label: the published image stays");
    is(read_binary("$dest/rootimg.cpio.gz.sha256"), sha256_hex($published) . "  rootimg.cpio.gz\n", "$label: the published checksum stays");
    is(read_binary("$dest/$_"), "published $_\n", "$label: the published $_ stays") for qw(kernel initrd-stateless.gz);
    my ($row) = xCAT::Table->new('osimage')->getAttribs({ imagename => $name }, 'osvers');
    is($row && $row->{osvers}, 'rhels9.5', "$label: the image definition stays");
}

# The database refuses each write to $table, as when it fails after the import opened the table.
sub refuse_writes {
    my ($table) = @_;
    xCAT::Table->new($table, -create => 1);
    my $dbh = DBI->connect("dbi:SQLite:dbname=$fixture/db/$table.sqlite", '', '', { RaiseError => 1, PrintError => 0, sqlite_busy_timeout => 1000 });
    $dbh->do("CREATE TRIGGER refuse_$_ BEFORE $_ ON $table BEGIN SELECT RAISE(ABORT, 'the database refuses the write'); END") for qw(INSERT UPDATE);
    return sub { $dbh->do("DROP TRIGGER refuse_$_") for qw(INSERT UPDATE); $dbh->disconnect };
}

# Another writer can take the write lock of the table, so no transaction of the import stays open.
sub table_free {
    my ($table) = @_;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$fixture/db/$table.sqlite", '', '', { RaiseError => 1, PrintError => 0, sqlite_busy_timeout => 1000 });
    my $free = eval { $dbh->do('BEGIN IMMEDIATE'); $dbh->do('ROLLBACK'); 1 };
    $dbh->disconnect;
    return $free;
}

# A column of the row of an image that the database holds, without the transaction of the test process.
sub committed {
    my ($table, $column, $name) = @_;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$fixture/db/$table.sqlite", '', '', { RaiseError => 1, PrintError => 0, sqlite_busy_timeout => 1000 });
    my ($value) = $dbh->selectrow_array("SELECT $column FROM $table WHERE imagename = ?", undef, $name);
    $dbh->disconnect;
    return $value;
}

# Imports a bundle over an image while the database refuses the writes to $case->{refuse}, or a call fails the way
# $case->{fail} names.
sub failed_import {
    my ($case) = @_;
    my $name   = 'failed-' . ++$sequence;
    my $dest   = "$fixture/install/netboot/$name";
    my $bundle = "$fixture/bundle-$sequence";
    make_path($dest, $bundle);
    write_text("$bundle/$_", "$_ from the bundle\n") for qw(rootimg.cpio.gz kernel initrd-stateless.gz);
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name }, { osvers => 'rhels9.5', provmethod => 'netboot' });
    my $fail  = $case->{fail} // '';
    my $allow = $case->{refuse} ? refuse_writes($case->{refuse}) : sub { };

    # The database worker keeps one osimage table for the requests of xcatd, so they share its transaction.
    my $shared;
    if ($case->{pending}) {
        $shared = xCAT::Table->new('osimage', -create => 1, -autocommit => 0);
        $shared->setAttribs({ imagename => "$name-other" }, { osvers => 'other' });
    }
    my (@errors, @warnings, @messages, $placed);
    {
        no warnings 'redefine';
        my ($set, $commit, $commit_failed) = (\&xCAT::Table::setAttribs, \&xCAT::Table::commit, 0);

        # The database worker passes the exception of a failed call to the caller, and returns undef when it does not answer.
        local *xCAT::Table::setAttribs = sub {
            goto &$set if caller() ne 'xCAT_plugin::imgport' || $_[0]{tabname} ne 'osimage' || !$fail || $fail eq 'die in the commit';
            die "the database is gone\n" if $fail eq 'die';
            return undef if $fail eq 'no reply';    ## no critic (Subroutines::ProhibitExplicitReturnUndef)
            $set->(@_);
            die "a notification failed\n";
        };
        local *xCAT::Table::commit = sub {
            die "the database is gone\n" if $fail eq 'die in the commit' && $_[0]{tabname} eq 'linuximage' && caller() eq 'xCAT_plugin::imgport' && !$commit_failed++;
            goto &$commit;
        };
        local *xCAT::Table::new = sub {
            return $shared if $shared && $_[1] eq 'osimage' && ((caller(1))[3] // '') eq 'xCAT_plugin::imgport::set_config';
            goto &$new;
        };
        $placed = eval {
            xCAT_plugin::imgport::place_image(
                {
                    rootimg    => "$dest/rootimg.cpio.gz",
                    kernel     => "$dest/kernel",
                    ramdisk    => "$dest/initrd-stateless.gz",
                    osimage    => { imagename => $name, osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' },
                    linuximage => { imagename => $name, rootimgdir => $dest },
                },
                $bundle, sub { push @errors, @{ $_[0]{error} || [] }; push @warnings, @{ $_[0]{warning} || [] }; push @messages, @{ $_[0]{data} || [] } });
        };
        push @errors, "place_image died: $@" if $@;
    }
    my $free = table_free($case->{refuse} // 'osimage');
    $allow->();
    return { placed => $placed, errors => join("\n", @errors), warnings => join("\n", @warnings), messages => join("\n", @messages),
        free => $free, osvers => committed('osimage', 'osvers', $name), rootimgdir => committed('linuximage', 'rootimgdir', $name),
        other => committed('osimage', 'osvers', "$name-other") };
}

my $refused = qr/Cannot write the (\w+) table: .*the database refuses the write/;
for my $case (
    { refuse => 'osimage',           osvers => 'rhels9.5' },
    { refuse => 'linuximage' },
    { fail => 'die',                 pending => 1, osvers => 'rhels9.5', error => qr/Cannot write the osimage table: the database is gone/ },
    { fail => 'no reply',            osvers => 'rhels9.5', error => qr/Cannot write the osimage table: no reply from the database/ },
    { fail => 'die in the commit',   error => qr/Cannot commit the linuximage table: the database is gone/ },
    { fail => 'die after the write', osvers => 'rhels9.6', imported => 1, warning => qr/The osimage table holds the new row, but its write reported: a notification failed/ },
  ) {
    my $label  = $case->{fail} // "refused $case->{refuse} write";
    my $result = failed_import($case);
    if ($case->{imported}) {
        ok($result->{placed}, "$label: the import succeeds, as the row is written") or diag($result->{errors});
        like($result->{warnings}, $case->{warning}, "$label: the failure after the write is reported");
    } else {
        ok(!$result->{placed}, "$label: the import fails");
        like($result->{errors}, $case->{error} // $refused, "$label: the failure is reported");
    }
    ok($result->{free}, "$label: no transaction of the import stays open");
    is($result->{other}, 'other', "$label: the pending write of another request stays") if $case->{pending};
    is($result->{osvers}, $case->{osvers}, "$label: the osimage row holds only what was written") if $case->{osvers};
}

done_testing();
