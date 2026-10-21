#!/usr/bin/env perl
use strict;
use warnings;
BEGIN { $ENV{XCATCFG} ||= 'SQLite:/tmp'; }
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Carp ();
use Storable qw(dclone);
use Test::More;
use xCAT::DBobjUtils;
use xCAT::Schema;

for my $column (qw(imagename template pkgdir partitionfile comments disable)) {
    is(scalar(grep { $_ eq $column } @{$xCAT::Schema::tabspec{freebsdimage}{cols}}),
        1, "FreeBSD extension retains one $column column");
}
is_deeply($xCAT::Schema::tabspec{freebsdimage}{keys}, ['imagename'],
    'FreeBSD extension uses the logical image name');

my %attrs = (
    objtype => 'osimage', imagetype => 'freebsd', osname => 'FreeBSD',
    osvers => 'freebsd15.1', osarch => 'x86_64', provmethod => 'install',
    template => '/opt/xcat/share/xcat/install/freebsd/compute.tmpl',
    pkgdir => '/install/freebsd15.1/x86_64/bundle',
    partitionfile => '/install/custom/freebsd/disk.conf', usercomment => 'test image',
);
my @errors = xCAT::DBobjUtils->validate_only_if_attrs('test-image', 'osimage', \%attrs, {});
is_deeply(\@errors, [], 'object validation accepts the FreeBSD configuration fields');
for my $attr (qw(boottarget addkcmdline rootimgdir kernelver driverupdatesrc)) {
    my %invalid = (objtype => 'osimage', imagetype => 'freebsd', $attr => 'unsupported');
    my @failures = xCAT::DBobjUtils->validate_only_if_attrs('test-image', 'osimage', \%invalid, {});
    is(scalar(@failures), 1, "FreeBSD rejects unsupported $attr");
    is($failures[0]{attr}, $attr, 'validation identifies the rejected field');
}
for my $family (qw(linux windows)) {
    my %existing = (objtype => 'osimage', imagetype => $family, template => '/tmp/template');
    my @failures = xCAT::DBobjUtils->validate_only_if_attrs('existing-image', 'osimage', \%existing, {});
    is_deeply(\@failures, [], "$family template routing remains valid");
}

{
    package FreeBSDImageSchema::Table;
    sub setAttribs {
        my ($self, $keys, $updates) = @_;
        my $db = $self->{db};
        my $name = $keys->{imagename};
        Carp::croak('Fixture requires an image key') unless defined($name);
        push @{$db->{writes}}, { table => $self->{name}, keys => {%$keys}, updates => {%$updates} };
        my $row = $db->{rows}{$self->{name}}{$name} ||= { imagename => $name };
        @{$row}{keys %$updates} = values %$updates;
        return (1, undef);
    }
    sub delEntries {
        my ($self, $keys) = @_;
        push @{$self->{db}{deletes}}, $self->{name};
        my @keys = ref($keys) eq 'ARRAY' ? @$keys : ($keys);
        delete($self->{db}{rows}{$self->{name}}{$_->{imagename}}) for @keys;
        return 1;
    }
    sub getAllEntries {
        my $self = shift;
        my $rows = $self->{db}{rows}{$self->{name}} || {};
        return [map { +{ %{$rows->{$_}} } } sort keys %$rows];
    }
    sub commit { return 1; }
}

sub database {
    my ($rows, $action) = @_;
    my $db = { rows => dclone($rows), writes => [], deletes => [], messages => [] };
    local %::TableHash = (); ## no critic (Variables::ProhibitPackageVars)
    local $::ATTRLIST = '';
    local $::opt_nc = 1; ## no critic (Variables::ProhibitPackageVars)
    local $::verbose = 0; ## no critic (Variables::ProhibitPackageVars)
    local $::opt_t = 'osimage'; ## no critic (Variables::ProhibitPackageVars)
    local $::callback = sub { push @{$db->{messages}}, dclone($_[0]) }; ## no critic (Variables::ProhibitPackageVars)
    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        return bless {name => $_[1], db => $db}, 'FreeBSDImageSchema::Table';
    };
    $action->($db);
    return;
}

sub write_objects {
    my ($db, $objects, %options) = @_;
    local %::TableHash = (); ## no critic (Variables::ProhibitPackageVars)
    local $::plus_option = $options{append} || 0; ## no critic (Variables::ProhibitPackageVars)
    local $::minus_option = $options{remove} || 0; ## no critic (Variables::ProhibitPackageVars)
    @{$db->{writes}} = ();
    @{$db->{messages}} = ();
    return xCAT::DBobjUtils->setobjdefs($objects);
}

sub read_object {
    my $name = shift;
    local %::TableHash = (); ## no critic (Variables::ProhibitPackageVars)
    my %objects = xCAT::DBobjUtils->getobjdefs({ $name => 'osimage' }, 0);
    return $objects{$name};
}

sub error_text {
    my $db = shift;
    return join("\n", map { @{$_->{error} || []} } @{$db->{messages}});
}

sub seed_image {
    my ($name, $family, $extension) = @_;
    my %table = (freebsd => 'freebsdimage', linux => 'linuximage', windows => 'winimage', NIM => 'nimimage');
    return { osimage => { $name => { imagename => $name, imagetype => $family } },
        $table{$family} => { $name => { imagename => $name, %{$extension || {}} } } };
}

sub legacy_writer_cases {
    my $db = shift;
    is(write_objects($db, { 'legacy-invalid' => { %attrs, pkglist => '/tmp/base.pkglist' } }), 1,
        'legacy FreeBSD rejects pkglist through the public object writer');
    is_deeply($db->{writes}, [], 'legacy pkglist rejection performs no table writes');
    is(write_objects($db, {'test-image' => {%attrs}}), 0, 'generic object writer accepts FreeBSD image');
    my @extensions = grep { $_->{table} =~ /image$/x && $_->{table} ne 'osimage' } @{$db->{writes}};
    is_deeply([map { $_->{table} } @extensions], ['freebsdimage'], 'configuration goes only to FreeBSD extension');
    is_deeply($extensions[0]{keys}, {imagename => 'test-image'}, 'extension row uses the image key');
    for my $attr (qw(template pkgdir partitionfile)) {
        is($extensions[0]{updates}{$attr}, $attrs{$attr}, "$attr reaches the FreeBSD extension");
    }
    is($extensions[0]{updates}{comments}, $attrs{usercomment}, 'user comment reaches the FreeBSD extension');
    is(xCAT::DBobjUtils->rmobjdefs({'test-image' => 'osimage'}), 0, 'generic object removal accepts image');
    ok(scalar(grep { $_ eq 'freebsdimage' } @{$db->{deletes}}), 'image removal includes FreeBSD extension');
    return;
}
database({}, \&legacy_writer_cases);

my %v2 = (%attrs, imageversion => '2',
    bootdir => '/install/freebsd15.1/x86_64/boot',
    pkgdir => '/install/freebsd15.1/x86_64/repositories/base',
    pkglist => '/install/custom/base.list,/install/custom/kernel.list',
    otherpkgdir => '/install/repositories/dvd,/install/repositories/site',
    otherpkglist => '/install/custom/apps.list,/install/custom/local.list',
    environvar => 'SITE=example');

sub reject_write {
    my ($updates, $rows, $pattern, $description, %options) = @_;
    database($rows, sub {
        my $db = shift;
        my $before = dclone($db->{rows});
        my $objects = { image => { objtype => 'osimage', %$updates } };
        is(write_objects($db, $objects, %options), 1, "$description returns an object error");
        is_deeply($db->{writes}, [], "$description performs no table writes");
        is_deeply($db->{rows}, $before, "$description preserves all existing rows");
        like(error_text($db), $pattern, "$description reports the rejected definition");
        ok($objects->{image}{error} && !$objects->{image}{updated}, "$description does not mark the object updated");
    });
    return;
}

sub version_cases {
    for my $column (qw(imageversion bootdir pkglist otherpkgdir otherpkglist)) {
        is(scalar(grep { $_ eq $column } @{xCAT::Table->getTableSchema('freebsdimage')->{cols}}),
            1, "FreeBSD extension has one $column column");
    }
    for my $version ('', '1') {
        database({}, sub {
            my $db = shift;
            is(write_objects($db, { image => { %attrs, imageversion => $version } }), 0,
                "legacy version '$version' preserves the bundle definition");
            is(read_object('image')->{pkgdir}, $attrs{pkgdir}, 'legacy bundle reference reads unchanged');
            is(read_object('image')->{imageversion}, $version, 'explicit legacy version round-trips');
        });
    }
    for my $case (['zero', 0], ['future', 3], ['padded one', '01'], ['padded two', '02'],
        ['list', '1,2'], ['leading space', ' 2'], ['trailing space', '2 '],
        ['newline', "2\n"], ['array', []], ['hash', {}]) {
        reject_write({ %attrs, imageversion => $case->[1] }, {}, qr/imageversion/,
            "$case->[0] image version");
    }
    for my $field (qw(bootdir pkglist otherpkgdir otherpkglist)) {
        for my $version (undef, '', '1') {
            my %request = (%attrs, $field => '/install/v2-only');
            $request{imageversion} = $version if defined($version);
            my $label = defined($version) ? "'$version'" : 'absent';
            reject_write(\%request, {}, qr/\Q$field\E.*imageversion=2/x,
                "$field with $label legacy version");
        }
    }
    database({}, sub {
        my $db = shift;
        is(write_objects($db, { image => { objtype => 'osimage', imagetype => 'freebsd', imageversion => '2' } }),
            0, 'an incomplete v2 definition can be recorded without deploying it');
        is(read_object('image')->{imageversion}, '2', 'incomplete version is retained');
    });
    return;
}

sub v2_routing_cases {
    database({}, sub {
        my $db = shift;
        is(write_objects($db, { image => { %v2 } }), 0, 'complete v2 definition is accepted');
        my @extensions = sort map { $_->{table} }
          grep { $_->{table} ne 'osimage' } @{$db->{writes}};
        is_deeply(\@extensions, ['freebsdimage'], 'v2 fields write only the FreeBSD extension');
        my $read = read_object('image');
        for my $field (qw(imageversion bootdir pkgdir pkglist otherpkgdir otherpkglist template partitionfile)) {
            is($db->{rows}{freebsdimage}{image}{$field}, $v2{$field}, "$field is stored in freebsdimage");
            is($read->{$field}, $v2{$field}, "$field reads through the real object router");
        }
        is($db->{rows}{osimage}{image}{environvar}, $v2{environvar}, 'environvar stays in the shared osimage table');
        ok(!exists($db->{rows}{freebsdimage}{image}{environvar}), 'FreeBSD does not duplicate environvar');
        $db->{rows}{linuximage}{image} = { imagename => 'image', pkgdir => '/wrong/linux', pkglist => '/wrong/list' };
        $db->{rows}{winimage}{image} = { imagename => 'image', template => '/wrong/windows' };
        $read = read_object('image');
        is($read->{pkgdir}, $v2{pkgdir}, 'FreeBSD reads ignore a same-named Linux extension');
        is($read->{template}, $v2{template}, 'FreeBSD reads ignore a same-named Windows extension');
    });
    for my $case (
        ['linux', 'linuximage', { template => '/linux/template', pkgdir => 'legacy,linux,paths', pkglist => 'relative-list' }],
        ['windows', 'winimage', { template => '/windows/template', installto => '0', partitionfile => 'windows-partitions' }],
        ['NIM', 'nimimage', { lpp_source => 'named-resource', spot => 'named-spot', usercomment => 'NIM image' }],
    ) {
        database({}, sub {
            my $db = shift;
            is(write_objects($db, { image => { objtype => 'osimage', imagetype => $case->[0], %{$case->[2]} } }),
                0, "$case->[0] retains its existing definition rules");
            my @tables = sort map { $_->{table} } grep { $_->{table} ne 'osimage' } @{$db->{writes}};
            is_deeply(\@tables, [$case->[1]], "$case->[0] routes only to its own extension");
            my $read = read_object('image');
            is_deeply({ map { $_ => $read->{$_} } keys %{$case->[2]} }, $case->[2], "$case->[0] fields round-trip unchanged");
        });
    }
    return;
}

sub path_cases {
    for my $field (qw(bootdir pkgdir pkglist otherpkgdir otherpkglist)) {
        for my $case (['relative', 'relative'], ['reference', []]) {
            reject_write({ %v2, $field => $case->[1] }, {}, qr/\Q$field\E/x, "$field $case->[0] path");
        }
    }
    for my $field (qw(bootdir pkgdir)) {
        reject_write({ %v2, $field => '/install/one,/install/two' }, {}, qr/\Q$field\E/x,
            "$field with multiple paths");
    }
    for my $field (qw(pkglist otherpkgdir otherpkglist)) {
        for my $case (['leading empty', ',/install/one'], ['middle empty', '/install/one,,/install/two'],
            ['trailing empty', '/install/one,'], ['duplicate', '/install/one,/install/one']) {
            reject_write({ %v2, $field => $case->[1] }, {}, qr/\Q$field\E/x, "$field $case->[0] member");
        }
    }
    for my $case (['double leading slash', '//install/one'], ['empty component', '/install//one'],
        ['trailing slash', '/install/one/'], ['dot component', '/install/./one'], ['dotdot component', '/install/../one'],
        ['NUL', "/install/one\0two"], ['newline', "/install/one\ntwo"], ['tab', "/install/one\ttwo"],
        ['carriage return', "/install/one\rtwo"], ['DEL', "/install/one\x7f"], ['oversize member', '/' . ('x' x 4096)]) {
        reject_write({ %v2, otherpkgdir => $case->[1] }, {}, qr/otherpkgdir/, "$case->[0] repository path");
    }
    database({}, sub {
        my $db = shift;
        my $path = '/' . ('x' x 4095);
        my $lists = $path . ',/' . ('y' x 4095);
        is(write_objects($db, { image => { %v2, pkgdir => $path, otherpkglist => $lists,
            pkglist => '/install/base list,/install/second list' } }), 0,
            'path limits apply to each member and ordinary spaces remain valid');
        my $read = read_object('image');
        is($read->{pkgdir}, $path, 'a 4096-byte scalar path is preserved');
        is($read->{otherpkglist}, $lists, 'two maximum-length list members retain their order');
        is($read->{pkglist}, '/install/base list,/install/second list', 'path spaces are not trimmed or split');
    });
    return;
}

sub partial_cases {
    my %extension = map { $_ => $v2{$_} } qw(imageversion bootdir pkgdir pkglist otherpkgdir otherpkglist);
    my $stored = seed_image('image', 'freebsd', \%extension);
    database($stored, sub {
        my $db = shift;
        is(write_objects($db, { image => { objtype => 'osimage', pkglist => '/install/revised.list' } }),
            0, 'partial v2 update uses the stored family and version');
        my $read = read_object('image');
        is($read->{pkglist}, '/install/revised.list', 'partial list update is stored');
        is($read->{bootdir}, $v2{bootdir}, 'partial update preserves the independent boot reference');
        is($read->{otherpkgdir}, $v2{otherpkgdir}, 'partial update preserves repository precedence');
        my @tables = map { $_->{table} } @{$db->{writes}};
        is_deeply(\@tables, ['freebsdimage'], 'partial update does not write another family or shared attributes');
    });
    for my $version ('1', '') {
        reject_write({ imageversion => $version }, $stored, qr/imageversion=2/x,
            "downgrade to '$version' with retained v2 fields");
    }
    database($stored, sub {
        my $db = shift;
        is(write_objects($db, { image => { objtype => 'osimage', imageversion => '1',
            bootdir => '', pkglist => '', otherpkgdir => '', otherpkglist => '', pkgdir => $attrs{pkgdir} } }),
            0, 'explicitly clearing v2 fields permits a legacy downgrade');
        my $read = read_object('image');
        is($read->{imageversion}, '1', 'downgrade stores the requested version over the prior version');
        is_deeply([@{$read}{qw(bootdir pkglist otherpkgdir otherpkglist)}], ['', '', '', ''], 'all v2-only fields are cleared');
    });
    database(seed_image('image', 'freebsd', { pkgdir => $attrs{pkgdir} }), sub {
        my $db = shift;
        is(write_objects($db, { image => { objtype => 'osimage', imageversion => '2', bootdir => '/install/boot',
            pkgdir => '/install/base', pkglist => '/install/base.list' } }), 0, 'explicit version upgrade uses final requested values');
        is(read_object('image')->{imageversion}, '2', 'upgrade replaces the missing legacy version');
    });
    reject_write({ pkglist => '/install/new.list' }, seed_image('image', 'freebsd', { pkgdir => $attrs{pkgdir} }),
        qr/pkglist.*imageversion=2/x, 'partial legacy update cannot bypass v1 pkglist rejection');
    return;
}

sub list_cases {
    my $stored = seed_image('image', 'freebsd', { imageversion => '2', otherpkgdir => '/install/one,/install/two' });
    database($stored, sub {
        my $db = shift;
        is(write_objects($db, { image => { objtype => 'osimage', otherpkgdir => '/install/two,/install/three,/install/one' } }, append => 1),
            0, 'append validates the deduplicated effective list');
        is(read_object('image')->{otherpkgdir}, '/install/one,/install/two,/install/three', 'append preserves old order and appends only new members');
        is(write_objects($db, { image => { objtype => 'osimage', otherpkgdir => '/install/two' } }, remove => 1),
            0, 'remove validates the remaining effective list');
        is(read_object('image')->{otherpkgdir}, '/install/one,/install/three', 'remove preserves the surviving order');
        is(write_objects($db, { image => { objtype => 'osimage', otherpkgdir => '/install/one,/install/three' } }, remove => 1),
            0, 'removing every member is an allowed clear');
        my $value = read_object('image')->{otherpkgdir};
        ok(!defined($value) || $value eq '', 'remove-all leaves no repository reference');
    });
    reject_write({ otherpkgdir => 'relative' }, $stored, qr/otherpkgdir/, 'append of an invalid effective member', append => 1);
    database(seed_image('image', 'freebsd', { imageversion => '2', otherpkgdir => '/install/one,relative' }), sub {
        my $db = shift;
        is(write_objects($db, { image => { objtype => 'osimage', otherpkgdir => 'relative' } }, remove => 1),
            0, 'removal can repair an invalid stored list before validation');
        is(read_object('image')->{otherpkgdir}, '/install/one', 'repair persists only the valid remaining member');
    });
    return;
}

sub family_cases {
    for my $family ('linux', 'windows', 'NIM', '', 'freebsd,linux', 'linux,freebsd', 'FreeBSD') {
        reject_write({ imagetype => $family }, seed_image('image', 'freebsd', { imageversion => '1' }),
            qr/(?:FreeBSD|imagetype)/x, "in-place FreeBSD transition to '$family'");
    }
    for my $family (qw(linux windows NIM)) {
        reject_write({ %v2 }, seed_image('image', $family, {}), qr/(?:FreeBSD|imagetype)/x,
            "in-place $family transition to FreeBSD");
    }
    for my $family ('freebsd,linux', 'linux,freebsd', 'FreeBSD', 'FREEBSD') {
        reject_write({ imagetype => $family }, {}, qr/imagetype/, "new noncanonical '$family' selector");
    }
    return;
}

sub multiobject_cases {
    database({}, sub {
        my $db = shift;
        my $objects = {
            invalid => { %attrs, pkglist => '/install/forbidden.list' },
            native => { %v2 },
            linux => { objtype => 'osimage', imagetype => 'linux', pkglist => 'legacy-list' },
        };
        is(write_objects($db, $objects), 1, 'mixed request reports its invalid FreeBSD member');
        my @invalid = grep { $_->{keys}{imagename} eq 'invalid' } @{$db->{writes}};
        is_deeply(\@invalid, [], 'rejected member writes neither osimage nor an extension');
        ok(!exists($db->{rows}{osimage}{invalid}) && !exists($db->{rows}{freebsdimage}{invalid}), 'invalid member has no partial definition');
        is(read_object('native')->{bootdir}, $v2{bootdir}, 'valid FreeBSD member is still updated');
        is(read_object('linux')->{pkglist}, 'legacy-list', 'valid Linux member is still updated');
        ok($objects->{invalid}{error} && !$objects->{invalid}{updated}, 'invalid member retains its per-object error');
        ok($objects->{native}{updated} && $objects->{linux}{updated}, 'valid members retain their update status');
        like(error_text($db), qr/invalid:.*pkglist/x, 'diagnostic identifies the rejected member and attribute');
    });
    return;
}

subtest 'explicit image versions retain legacy definitions' => \&version_cases;
subtest 'v2 fields use native read and write routing' => \&v2_routing_cases;
subtest 'v2 references use canonical ordered paths' => \&path_cases;
subtest 'partial updates and version changes use effective values' => \&partial_cases;
subtest 'append and remove validate existing list operations' => \&list_cases;
subtest 'FreeBSD family changes cannot route through two extensions' => \&family_cases;
subtest 'invalid objects do not prevent valid updates' => \&multiobject_cases;
done_testing();
