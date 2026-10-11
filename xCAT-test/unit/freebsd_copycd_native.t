#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(O_CREAT O_RDWR LOCK_EX LOCK_NB);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use POSIX qw(mkfifo);
use Storable qw(dclone);
use Test::More;
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;

my ($mount_command, $file_command);
BEGIN { ## no critic (Variables::ProhibitPackageVars, Variables::RequireLocalizedPunctuationVars)
    $INC{"xCAT/$_.pm"} = 1 for qw(Table TableUtils);
    *CORE::GLOBAL::system = sub {
        return $mount_command->(@_) if $mount_command;
        return CORE::system(@_);
    };
    *CORE::GLOBAL::readpipe = sub {
        return $file_command->(@_) if $file_command;
        return CORE::readpipe($_[0]);
    };
}
use xCAT::Utils;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
plan(skip_all => 'Native copycd tests require Linux execution') unless $^O eq 'linux';
plan(skip_all => 'Native pkg database fixtures require container root') if $> != 0;

my (%rows, %faults, @operations, @site_reads, $on_write, $on_delete, $installroot, $policy_path);
sub fault {
    my ($operation, $table) = @_;
    push @operations, [$operation, $table];
    return delete $faults{"$operation/$table"};
}

{ ## no critic (Variables::ProhibitPackageVars)
    no warnings 'once'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    *xCAT::Table::new = sub {
        my ($class, $table, %options) = @_;
        return if fault('open', $table);
        croak 'Registration must use autocommit' unless $options{-autocommit};
        return bless { table => $table }, $class;
    };
    *xCAT::Table::getAllEntries = sub {
        my ($self, $all) = @_;
        croak 'Disabled entries must be visible' unless $all;
        return if fault('read', $self->{table});
        return dclone([values %{$rows{$self->{table}} || {}}]);
    };
    *xCAT::Table::setAttribs = sub {
        my ($self, $key, $values) = @_;
        my $table = $self->{table};
        my ($name) = values %$key;
        my $failure = fault('write', $table) || '';
        $on_write->($table) if $on_write;
        croak 'injected write exception' if $failure eq 'die';
        return (undef, 'injected write failure') if $failure eq 'error';
        return 0 if $failure eq 'silent';
        $rows{$table}{$name} = {%$key, %$values};
        croak 'injected post-write exception' if $failure eq 'after';
        return 0;
    };
    *xCAT::Table::delEntries = sub {
        my ($self, $key) = @_;
        my ($name) = values %$key;
        my $failure = fault('delete', $self->{table});
        $on_delete->($self->{table}) if $on_delete;
        return if $failure;
        delete $rows{$self->{table}}{$name};
        return;
    };
    *xCAT::Table::close = sub { return; };
    *xCAT::TableUtils::getInstallDir = sub { return $installroot; };
    *xCAT::TableUtils::get_site_attribute = sub {
        my ($class, $key) = @_;
        push @site_reads, $key;
        return $policy_path if $key eq 'freebsdimportpolicy';
        return;
    };
}

my $plugin = $ENV{XCAT_FREEBSD_PLUGIN}
  || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsd.pm";
require $plugin;
my $copycds = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/copycds.pm";
require $copycds;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
    $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
    $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
    $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
}
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    return defined($bytes) ? $bytes : '';
}

sub write_file {
    my ($path, $bytes) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub command {
    my @argv = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@argv, cwd => $tmp,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub run_pkg {
    my @arguments = @_;
    return command($tool->{path}, '-C', "$tmp/pkg.conf", @arguments);
}

make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
$tool->{sha256} = sha256_hex(read_file($tool->{path}));
is(run_pkg('-v'), "2.8.2\n", 'native fixtures use the pinned pkg version');
my $disc = $fixture->release_tree(0);
my $dvd = $fixture->release_tree(1);
my %trees = map { $_ => xCAT::FreeBSDRepo::inspect_release_tree($_) } ($disc, $dvd);
my $default_policy = { format => 'xcat-freebsd-import-policy-1', tool => $tool,
    releases => { $trees{$disc}{digest} => { iso_sha256 => '1' x 64 },
        $trees{$dvd}{digest} => { iso_sha256 => '2' x 64 } }, repositories => {} };

sub fresh {
    my $change = shift;
    %rows = ();
    %faults = ();
    @operations = ();
    @site_reads = ();
    $on_write = undef;
    $on_delete = undef;
    $installroot = $fixture->new_directory();
    $policy_path = $fixture->new_directory() . '/policy.json';
    my $policy = dclone($default_policy);
    $change->($policy) if $change;
    write_file($policy_path, $json->encode($policy));
    chmod(oct('0600'), $policy_path) or croak $!;
    return;
}

sub run_copy {
    my ($source, @arguments) = @_;
    my $request = { command => ['copycd'], arg => ['-m', $source, @arguments] };
    my @responses;
    xCAT_plugin::freebsd::process_request($request,
        sub { push @responses, dclone($_[0]); }, sub { croak 'Unexpected subrequest'; });
    return ($request, \@responses);
}

sub messages {
    my ($responses, $field) = @_;
    return join('', map { ref($_->{$field}) eq 'ARRAY' ? @{$_->{$field}} : ($_->{$field} || '') } @$responses);
}

sub writes { return grep { $_->[0] eq 'write' } @operations; }
sub row_count { return scalar map { keys %$_ } values %rows; }
sub parent_directory { return "$installroot/freebsd15.1/x86_64/repositories"; }

sub publications {
    my $parent = parent_directory();
    return [] unless -d $parent;
    opendir(my $dh, $parent) or croak $!;
    my @names = sort grep { /\A[0-9a-f]{64}\z/x } readdir($dh);
    closedir($dh) or croak $!;
    return [map { "$parent/$_" } @names];
}

sub readback {
    my $paths = publications();
    is(scalar(@$paths), 1, 'one immutable publication is retained');
    return xCAT::FreeBSDRepoImport::inspect_import($paths->[0], $installroot);
}

sub registered_image {
    my @names = sort keys %{$rows{osimage} || {}};
    is(scalar(@names), 1, 'one image is registered');
    return $names[0];
}

sub without_native {
    my $action = shift;
    my $calls = 0;
    { ## no critic (TestingAndDebugging::ProhibitNoWarnings, Variables::ProhibitPackageVars)
        no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
        local *xCAT::FreeBSDPkg::run_command = sub { ++$calls; croak 'Unexpected native command'; };
        $action->();
    }
    is($calls, 0, 'rejected or inspection-only request executes no native command');
    return;
}

sub inspection_cases {
    fresh();
    my ($request, $responses) = run_copy($tmp, '-n', 'rhels9');
    is($request->{command}[0], 'copycd', 'unrelated media remains available to other plugins');
    is_deeply($responses, [], 'unrelated media produces no response');
    for my $source ($disc, $dvd) {
        fresh();
        $policy_path = '/unavailable/policy.json';
        without_native(sub { ($request, $responses) = run_copy($source, '-i'); });
        is_deeply($request, {}, 'native release inspection claims the request');
        is(messages($responses, 'error'), '', 'inspection succeeds without an import policy');
        my $digest = $trees{$source}{digest};
        like(messages($responses, 'info'), qr/TREE_DIGEST:\Q$digest\E/x, 'inspection reports selected-tree identity');
        my $roles = $source eq $disc ? 'base' : 'applications,base';
        like(messages($responses, 'info'), qr/REPOSITORIES:\Q$roles\E/x, 'inspection reports exact repository roles');
        is_deeply(\@operations, [], 'inspection does not access image tables');
        is_deeply(\@site_reads, [], 'inspection does not access the policy setting');
        is_deeply(publications(), [], 'inspection does not publish media');
    }
    return;
}

sub release_cases {
    for my $source ($disc, $dvd) {
        fresh();
        my ($request, $responses) = run_copy($source);
        is_deeply($request, {}, 'import claims native release media');
        is(messages($responses, 'error'), '', 'approved release import succeeds');
        diag(explain($responses)) if length(messages($responses, 'error'));
        my $publication = readback();
        my $name = registered_image();
        my $settings = $rows{freebsdimage}{$name};
        is($settings->{imageversion}, '2', 'release media creates an explicit v2 definition');
        is($settings->{pkgdir}, "$publication->{path}/base", 'pkgdir is the base role root');
        is($rows{osimage}{$name}{imagetype}, 'freebsd', 'generic image routes through FreeBSD');
        is_deeply([map { $_->[1] } writes()], [qw(osdistro freebsdimage osimage)],
            'generic image visibility follows dependency registration');
        ok(!exists($rows{linuximage}), 'Linux image table is untouched');
        ok(!grep({ defined($settings->{$_}) && length($settings->{$_}) } qw(bootdir pkglist otherpkglist)),
            'import chooses neither installer artifact nor package selection');
        is($publication->{selection_validated}, 0, 'repository import does not claim installation selection');
        my $iso_digest = ($source eq $disc ? '1' : '2') x 64;
        like(messages($responses, 'data'), qr/operator-recorded[ ]ISO[ ]SHA256[ ]\Q$iso_digest\E/x,
            'ISO checksum is identified as operator-recorded provenance');
        if ($source eq $dvd) {
            is($settings->{otherpkgdir}, "$publication->{path}/applications", 'DVD applications use their role root without catalogue prefix');
            is_deeply([sort keys %{$publication->{repositories}}], [qw(applications base)], 'both complete DVD repositories are retained');
            is(readlink("$publication->{path}/applications/FreeBSD:15:amd64/Latest/pkg.pkg"),
                '../All/Hashed/pkg-2.6.2_1~fixture.pkg', 'DVD bootstrap alias resolves only in the derived publication');
        } else {
            ok(!defined($settings->{otherpkgdir}), 'base-only media does not invent an applications repository');
        }
        is_deeply(xCAT::FreeBSDRepo::inspect_release_tree($source), $trees{$source}, 'original release tree remains unchanged');
    }
    return;
}

sub repeat_cases {
    fresh();
    my (undef, $responses) = run_copy($dvd, '-o');
    is(messages($responses, 'error'), '', 'noosimage import succeeds');
    is_deeply([map { $_->[1] } writes()], ['osdistro'], 'noosimage registers only the distribution');
    my $publication = readback();
    (undef, $responses) = run_copy($dvd);
    is(messages($responses, 'error'), '', 'normal retry completes image registration');
    my $name = registered_image();
    my $settings = $rows{freebsdimage}{$name};
    @{$settings}{qw(bootdir pkglist otherpkglist template partitionfile)} =
      qw(/boot/selected /policy/base /policy/apps /policy/template /policy/disks);
    $settings->{otherpkgdir} = "/repos/supplemental,$publication->{path}/applications";
    @{$rows{osimage}{$name}}{qw(profile environvar comments)} = ('storage', 'site=value', 'site policy');
    my $before = dclone(\%rows);
    @operations = ();
    (undef, $responses) = run_copy($dvd);
    is(messages($responses, 'error'), '', 'reimport accepts mutable administrator policy');
    is_deeply(\%rows, $before, 'reimport preserves all administrator fields and repository order');
    is(scalar(writes()), 0, 'reimport performs no table writes');
    (undef, $responses) = run_copy($dvd, '-w');
    like(messages($responses, 'error'), qr/destination[ ]already[ ]exists/x, 'nonoverwrite rejects an existing publication');
    is_deeply(\%rows, $before, 'nonoverwrite preserves all rows');
    delete $settings->{otherpkgdir};
    $before = dclone(\%rows);
    (undef, $responses) = run_copy($dvd);
    is(messages($responses, 'error'), '', 'reimport accepts explicitly removed applications');
    is_deeply(\%rows, $before, 'reimport does not restore an administrator-removed application role');
    is_deeply(xCAT::FreeBSDRepoImport::inspect_import($publication->{path}, $installroot), $publication,
        'registration and retries leave the immutable publication unchanged');
    return;
}

sub rejection_cases {
    for my $change (sub { $_[0]{releases} = {} }, sub { $_[0]{unknown} = 1 }) {
        fresh($change);
        my $responses;
        without_native(sub { (undef, $responses) = run_copy($disc); });
        ok(length(messages($responses, 'error')), 'unapproved or malformed policy rejects import');
        is(scalar(writes()), 0, 'policy rejection creates no image rows');
        is_deeply(publications(), [], 'policy rejection publishes no repository');
    }
    for my $option (['-n', 'freebsd15.1'], ['-a', 'x86_64'], ['-p', '/install/custom'], ['-s'], ['--unknown'], ['extra']) {
        fresh();
        my $responses;
        without_native(sub { (undef, $responses) = run_copy($disc, @$option); });
        ok(length(messages($responses, 'error')), 'unsupported copycd option is rejected');
        is(scalar(writes()), 0, 'argument rejection performs no database write');
    }
    my $bad = $fixture->release_tree(0);
    my $before = xCAT::FreeBSDRepo::inspect_release_tree($bad);
    fresh(sub { $_[0]{releases}{$before->{digest}} = {iso_sha256 => '3' x 64}; });
    write_file("$bad/usr/freebsd-packages/offline/All/pkg-2.6.2_1.pkg", 'corrupt archive');
    my $responses;
    without_native(sub { (undef, $responses) = run_copy($bad); });
    ok(length(messages($responses, 'error')), 'source changed after policy approval is rejected');
    is(scalar(writes()), 0, 'changed source creates no definition');
    is_deeply(publications(), [], 'changed source creates no publication');
    return;
}

sub reuse_definition_cases {
    for my $case (
        ['relative', 'repos/applications', 'requires canonical absolute paths'],
        ['duplicate', '/repos/apps,/repos/apps', 'contains a duplicate path'],
    ) {
        my ($label, $value, $error) = @$case;
        fresh();
        my (undef, $responses) = run_copy($dvd);
        is(messages($responses, 'error'), '', "$label case starts with a registered DVD image");
        my $publication = readback();
        my $name = registered_image();
        $rows{freebsdimage}{$name}{otherpkgdir} = $value;
        delete $rows{osimage}{$name} if $label eq 'duplicate';
        my $before = dclone(\%rows);
        @operations = ();
        (undef, $responses) = run_copy($dvd);
        like(messages($responses, 'error'), qr/FreeBSD[ ]otherpkgdir[ ]\Q$error\E/x,
            "$label application path fails reuse-time definition validation");
        is(scalar(writes()), 0, "$label invalid definition permits no registration write");
        is_deeply(\%rows, $before, "$label invalid definition preserves existing and absent rows");
        is_deeply(xCAT::FreeBSDRepoImport::inspect_import($publication->{path}, $installroot), $publication,
            "$label invalid definition leaves the publication unchanged");
    }
    return;
}

sub compensation_cases {
    for my $table (qw(osdistro freebsdimage osimage)) {
        for my $kind (qw(error silent die after)) {
            fresh();
            $faults{"write/$table"} = $kind;
            my (undef, $responses) = run_copy($disc);
            ok(length(messages($responses, 'error')), "$table $kind failure reaches caller");
            is(row_count(), 0, "$table $kind removes only newly created rows");
            like(messages($responses, 'error'), qr/Imported[ ]media[ ]retained/x, 'failure identifies retained publication');
            readback();
            (undef, $responses) = run_copy($disc);
            is(messages($responses, 'error'), '', 'retry registers retained verified media');
            is(row_count(), 3, 'retry leaves one complete image definition');
        }
    }
    fresh();
    run_copy($disc, '-o');
    my $before = dclone(\%rows);
    $faults{'write/osimage'} = 'error';
    my (undef, $responses) = run_copy($disc);
    ok(length(messages($responses, 'error')), 'partial registration failure reaches caller');
    is_deeply($rows{osdistro}, $before->{osdistro}, 'rollback preserves the pre-existing distribution');
    is(row_count(), 1, 'rollback retains only the pre-existing distribution row');
    readback();
    fresh();
    $faults{'write/osimage'} = 'error';
    $faults{'delete/freebsdimage'} = 1;
    (undef, $responses) = run_copy($disc);
    like(messages($responses, 'error'), qr/Cleanup[ ]failed[ ]for[ ]freebsdimage/x, 'failed compensation is explicit');
    is(row_count(), 1, 'other compensation continues after a failed row deletion');
    fresh();
    $faults{'write/osimage'} = 'error';
    $on_write = sub {
        return unless $_[0] eq 'osimage';
        $_->{comments} = 'concurrent policy' for values %{$rows{freebsdimage}};
        return;
    };
    (undef, $responses) = run_copy($disc);
    like(messages($responses, 'error'), qr/entry[ ]changed[ ]during[ ]registration/x, 'concurrent writer prevents destructive rollback');
    is(row_count(), 1, 'concurrent data survives compensation');
    return;
}

sub late_dvd_cases {
    fresh();
    run_copy($disc);
    my $name = registered_image();
    my $before = dclone(\%rows);
    my (undef, $responses) = run_copy($dvd);
    is(messages($responses, 'error'), '', 'later DVD import succeeds beside a base-only image');
    is_deeply($rows{freebsdimage}{$name}, $before->{freebsdimage}{$name}, 'late DVD does not attach applications to the earlier image');
    is_deeply($rows{osimage}{$name}, $before->{osimage}{$name}, 'late DVD does not replace earlier generic image policy');
    my $distro = $before->{osimage}{$name}{osdistroname};
    is_deeply($rows{osdistro}{$distro}, $before->{osdistro}{$distro}, 'earlier distribution remains unchanged');
    is(scalar(@{publications()}), 2, 'late DVD has an independent immutable publication');
    like(messages($responses, 'data'), qr{Application[ ]repository:[ ][^\n]+/applications}x,
        'late DVD exposes its role for a later explicit attachment');
    return;
}

sub preflight_cases {
    for my $table (qw(osdistro freebsdimage osimage)) {
        for my $operation (qw(open read)) {
            fresh();
            $faults{"$operation/$table"} = 1;
            my (undef, $responses) = run_copy($disc);
            like(messages($responses, 'error'), qr/Cannot[ ](?:open|read)[ ]\Q$table\E/x,
                "$table $operation preflight failure reaches caller");
            is(scalar(writes()), 0, 'all registration rows are checked before any write');
            is(row_count(), 0, 'preflight failure creates no image definition');
            readback();
        }
        fresh();
        run_copy($disc);
        my ($name) = keys %{$rows{$table}};
        $rows{$table}{$name}{disable} = 'yes';
        my $before = dclone(\%rows);
        @operations = ();
        my (undef, $responses) = run_copy($disc);
        like(messages($responses, 'error'), qr/is[ ]disabled/x, 'disabled identity collision is rejected');
        is_deeply(\%rows, $before, 'disabled registration is preserved');
        is(scalar(writes()), 0, 'disabled collision performs no table writes');
        delete $rows{$table}{$name}{disable};
        my $attribute = $table eq 'osdistro' ? 'dirpaths' : $table eq 'freebsdimage' ? 'pkgdir' : 'imagetype';
        $rows{$table}{$name}{$attribute} = 'different';
        $before = dclone(\%rows);
        (undef, $responses) = run_copy($disc);
        like(messages($responses, 'error'), qr/does[ ]not[ ]match/x, 'conflicting media identity is rejected');
        is_deeply(\%rows, $before, 'conflicting registration is preserved');
        is(scalar(writes()), 0, 'identity collision performs no table writes');
    }
    return;
}

sub make_lock {
    my ($kind, $path) = @_;
    my $held;
    if ($kind eq 'symlink') {
        symlink("$installroot/lock-target", $path) or croak $!;
    } elsif ($kind eq 'hardlink') {
        write_file("$installroot/lock-target", '');
        chmod(oct('0600'), "$installroot/lock-target") or croak $!;
        link("$installroot/lock-target", $path) or croak $!;
    } elsif ($kind eq 'fifo') {
        mkfifo($path, oct('0600')) or croak $!;
    } else {
        write_file($path, '');
        chmod($kind eq 'mode' ? oct('0666') : oct('0600'), $path) or croak $!;
        chown(65534, 65534, $path) or croak $! if $kind eq 'owner';
        if ($kind eq 'busy') {
            sysopen($held, $path, O_RDWR) or croak $!;
            flock($held, LOCK_EX | LOCK_NB) or croak $!;
        }
    }
    return $held;
}

sub lock_cases {
    for my $kind (qw(symlink hardlink fifo mode owner busy)) {
        fresh();
        my (undef, $responses) = run_copy($disc, '-o');
        is(messages($responses, 'error'), '', 'initial import prepares a protected registration parent');
        my $publication = readback();
        %rows = ();
        @operations = ();
        my $path = parent_directory() . '/.repository-register.lock';
        unlink($path) or croak "unlink fixture lock: $!";
        my $held = make_lock($kind, $path);
        (undef, $responses) = run_copy($disc);
        like(messages($responses, 'error'), qr/lock/ix, "$kind registration lock is rejected");
        is(scalar(writes()), 0, "$kind registration lock permits no database write");
        is_deeply(xCAT::FreeBSDRepoImport::inspect_import($publication->{path}, $installroot), $publication,
            'unsafe or busy sibling lock does not alter immutable publication');
        close($held) or croak $! if $held;
        ok(!-e "$installroot/lock-target", 'symlink lock target is not created') if $kind eq 'symlink';
    }
    return;
}

sub registration_lock_available {
    my $path = parent_directory() . '/.repository-register.lock';
    sysopen(my $probe, $path, O_RDWR) or croak "$path: $!";
    my $available = flock($probe, LOCK_EX | LOCK_NB);
    my $blocked = $!{EAGAIN} || $!{EWOULDBLOCK};
    croak "Cannot probe registration lock: $!" unless $available || $blocked;
    close($probe) or croak "$path: $!";
    return $available ? 1 : 0;
}

sub lock_lifetime_cases {
    for my $failure (0, 1) {
        fresh();
        my (@write_locks, @delete_locks);
        $on_write = sub { push @write_locks, [$_[0], registration_lock_available()]; return; };
        $on_delete = sub { push @delete_locks, [$_[0], registration_lock_available()]; return; };
        $faults{'write/osimage'} = 'error' if $failure;
        my (undef, $responses) = run_copy($disc);
        if ($failure) {
            like(messages($responses, 'error'), qr/injected[ ]write[ ]failure/x,
                'lock lifetime failure reaches the caller');
        } else {
            is(messages($responses, 'error'), '', 'lock lifetime success registers the image');
        }
        is_deeply(\@write_locks, [map { [$_, 0] } qw(osdistro freebsdimage osimage)],
            'registration lock excludes a separate descriptor during every write');
        is_deeply(\@delete_locks, $failure ? [['freebsdimage', 0], ['osdistro', 0]] : [],
            'registration lock excludes a separate descriptor throughout rollback');
        ok(registration_lock_available(), 'registration releases its lock after returning');
        is(row_count(), $failure ? 0 : 3, 'lock lifetime probe preserves registration outcome');
        readback();
    }
    return;
}

sub wrapper_cases {
    for my $case (['import'], ['inspection', '-i'], ['noosimage', '-o'], ['unapproved']) {
        fresh($case->[0] eq 'unapproved' ? sub { $_[0]{releases} = {} } : undef);
        my $iso = "$tmp/release.iso";
        write_file($iso, 'ISO transport fixture');
        my (@commands, @responses, @dispatched);
        $mount_command = sub { push @commands, join(' ', @_); return 0; };
        $file_command = sub { return "$iso: ISO 9660 CD-ROM filesystem data\n"; };
        local @ARGV = ();
        xCAT_plugin::copycds::process_request({ command => ['copycds'],
            arg => [@$case[1 .. $#$case], $iso], cwd => [$tmp] },
            sub { push @responses, dclone($_[0]); }, sub {
                my ($request, $callback) = @_;
                push @dispatched, dclone($request);
                $request->{arg}[1] = $disc;
                xCAT_plugin::freebsd::process_request($request, $callback);
            });
        $mount_command = undef;
        $file_command = undef;
        is(scalar(@dispatched), 1, 'public copycds dispatches one media request');
        is($dispatched[0]{command}[0], 'copycd', 'native release uses the existing copycd route');
        my $mounted = $dispatched[0]{arg}[1];
        is($commands[2], "mount -t udf,iso9660 -o ro,loop '$iso' $mounted", 'outer wrapper requests a read-only mount at the dispatched path');
        like($commands[-2], qr/\Aumount\s+\Q$mounted\E\z/x, 'outer wrapper unmounts the dispatched mountpoint');
        is($commands[-1], "rm -rf $mounted", 'outer wrapper removes only the dispatched mountpoint');
        unlike(messages(\@responses, 'error'), qr/could[ ]not[ ]identify/x, 'native release handler identifies the media');
        if ($case->[0] eq 'unapproved') {
            ok(length(messages(\@responses, 'error')), 'policy error crosses both callback boundaries');
        } else {
            is(messages(\@responses, 'error'), '', 'public copycds succeeds with native release media');
        }
        my $expected = $case->[0] eq 'import' ? 3 : $case->[0] eq 'noosimage' ? 1 : 0;
        is(row_count(), $expected, 'forwarded option controls native registration');
    }
    return;
}

subtest 'native release inspection is read-only' => \&inspection_cases;
subtest 'real base and DVD repositories import and register' => \&release_cases;
subtest 'repeat import preserves administrator policy' => \&repeat_cases;
subtest 'repeat import validates matching image definitions' => \&reuse_definition_cases;
subtest 'policy, arguments and source identity fail closed' => \&rejection_cases;
subtest 'registration failures retain verified publication' => \&compensation_cases;
subtest 'registration preflights disabled and conflicting rows' => \&preflight_cases;
subtest 'native registration locks reject unsafe or busy files' => \&lock_cases;
subtest 'native registration holds its lock through writes and rollback' => \&lock_lifetime_cases;
subtest 'late DVD import does not implicitly attach applications' => \&late_dvd_cases;
subtest 'public copycds wrapper dispatches native release media' => \&wrapper_cases;
ok(!-e "$tmp/package-script-executed", 'native inspection never executes package installation scripts');
done_testing();
