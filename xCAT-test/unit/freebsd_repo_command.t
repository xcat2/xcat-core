#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Getopt::Long ();
use JSON;
use Storable qw(dclone);
use Test::More;
use Text::ParseWords qw(shellwords);
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;

BEGIN { ## no critic (Variables::RequireLocalizedPunctuationVars)
    $INC{"xCAT/$_.pm"} = 1 for qw(Table TableUtils);
}

my ($installroot, $policy_path, $install_before, @site_reads, @db_access);

sub table_open {
    my ($class, $table, %options) = @_;
    push @db_access, ['new', $table, { %options }];
    croak 'Unexpected image/database access';
}

sub site_attribute {
    my ($class, $key) = @_;
    push @site_reads, $key;
    croak "Unexpected site attribute $key" unless $key eq 'freebsdimportpolicy';
    return $policy_path;
}

{ ## no critic (Variables::ProhibitPackageVars)
    no warnings 'once'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    *xCAT::Table::new = \&table_open;
    *xCAT::Table::setAttribs = sub { croak 'Unexpected image table write'; };
    *xCAT::Table::delEntries = sub { croak 'Unexpected image table deletion'; };
    *xCAT::TableUtils::getInstallDir = sub { push @site_reads, 'installdir'; return $installroot; };
    *xCAT::TableUtils::get_site_attribute = \&site_attribute;
}

my $plugin = $ENV{XCAT_FREEBSD_REPO_PLUGIN}
  || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/freebsdrepo.pm";
require $plugin;
my $tmp = abs_path(tempdir(CLEANUP => 1));
my $json = JSON->new->utf8->canonical;
my $tool = { path => '/unavailable/pkg', sha256 => '0' x 64 };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);
my $signed = $fixture->new_directory();
write_file("$signed/content", 'ordinary inspection input');
my $source_tree = xCAT::FreeBSDRepo::snapshot_tree($signed);
my ($unsigned, $nested);
my $default_policy = { format => 'xcat-freebsd-import-policy-1', tool => $tool,
    releases => {}, repositories => {} };

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

sub pubkey {
    my $name = shift;
    return { type => 'pubkey', path => "$tmp/$name.pub",
        sha256 => sha256_hex(read_file("$tmp/$name.pub")) };
}

sub native_fixtures {
    $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
    if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
        $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
        $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
        $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
    }
    make_path("$tmp/empty", "$tmp/repos");
    write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
        PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
        REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
    $tool->{sha256} = sha256_hex(read_file($tool->{path}));
    is(run_pkg('-v'), "2.8.2\n", 'fixtures use the pinned native pkg version');
    for my $key_name (qw(repo wrong)) {
        command('/usr/bin/openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048', '-out', "$tmp/$key_name.key");
        chmod(oct('0600'), "$tmp/$key_name.key") or croak $!;
        command('/usr/bin/openssl', 'pkey', '-in', "$tmp/$key_name.key", '-pubout', '-out', "$tmp/$key_name.pub");
    }
    my @definitions = (['command-dep'], ['command-app', deps => {
        'command-dep' => { origin => 'misc/command-dep', version => '1' } }], ['command-unused']);
    $signed = $fixture->repository(1, \@definitions);
    $unsigned = $fixture->repository(0, \@definitions);
    $nested = $fixture->new_directory();
    command('/usr/bin/cp', '-a', $signed, "$nested/catalogue");
    $source_tree = xCAT::FreeBSDRepo::snapshot_tree($signed);
    $default_policy = { format => 'xcat-freebsd-import-policy-1', tool => $tool, releases => {},
        repositories => { approved => { trust => pubkey('repo') },
            unsigned => { trust => { type => 'operator-trusted-tree',
                digest => xCAT::FreeBSDRepo::snapshot_tree($unsigned)->{digest} } },
            nested => { trust => pubkey('repo'), catalogue_prefix => 'catalogue' },
            wrong => { trust => pubkey('wrong') } } };
    return;
}

sub fresh {
    my $change = shift;
    @site_reads = ();
    @db_access = ();
    $installroot = $fixture->new_directory();
    $install_before = xCAT::FreeBSDRepo::snapshot_tree($installroot);
    $policy_path = $fixture->new_directory() . '/policy.json';
    my $policy = dclone($default_policy);
    $change->($policy) if $change;
    write_file($policy_path, $json->encode($policy));
    chmod(oct('0600'), $policy_path) or croak $!;
    return;
}

sub request {
    my $request = shift;
    my @responses;
    xCAT_plugin::freebsdrepo::process_request($request,
        sub { push @responses, dclone($_[0]); }, sub { croak 'Unexpected subrequest'; });
    return \@responses;
}

sub run_cli {
    my @arguments = @_;
    return request({ command => ['freebsdrepo'], arg => \@arguments });
}

sub messages {
    my ($responses, $field) = @_;
    return join('', map { @{$_->{$field} || []} } @$responses);
}

sub rejected {
    my ($responses, $pattern, $description) = @_;
    my $error = messages($responses, 'error');
    like($error, $pattern, $description);
    unlike($error, qr/[ ]at[ ][^\n]+[ ]line[ ]\d+[.]$/mx, "$description omits Perl caller details");
    is_deeply([map { @{$_->{errorcode} || []} } @$responses], [1], "$description returns error status");
    is(messages($responses, 'data'), '', "$description reports no success");
    return;
}

sub publications {
    my $parent = "$installroot/freebsd15.1/x86_64/repositories";
    return [] unless -d $parent;
    opendir(my $dh, $parent) or croak $!;
    my @names = sort grep { /\A[0-9a-f]{64}\z/x } readdir($dh);
    closedir($dh) or croak $!;
    return [map { "$parent/$_" } @names];
}

sub no_effect {
    my $description = shift;
    is_deeply(publications(), [], "$description makes no publication");
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($installroot), $install_before,
        "$description leaves the complete install tree unchanged");
    is_deeply(\@db_access, [], "$description leaves image/package selections untouched");
    return;
}

sub help_cases {
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n";
    for my $action (qw(inspect import)) {
        my $target = $signed;
        for my $flag (qw(-h --help)) {
            for my $args ([$action, $flag], [$action, $flag, $target], [$action, $target, $flag]) {
                my $description = 'subcommand help [' . join(' ', @$args) . ']';
                is_deeply(run_cli(@$args), [{ data => [$usage] }], "$description returns only successful usage");
                is_deeply(\@db_access, [], "$description does not open image tables");
                is_deeply(\@site_reads, [], "$description does not read site configuration");
            }
        }
    }
    return;
}

sub parser_cases {
    fresh();
    my $getopt_config = Getopt::Long::Configure();
    parser_requests();
    is_deeply(Getopt::Long::Configure(), $getopt_config, 'parser fixture restores global Getopt configuration');
    no_effect('parser rejection');
    return;
}

sub parser_requests {
    my ($native_calls, $tree_reads) = (0, 0);
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Unexpected native execution'; };
    local *xCAT::FreeBSDRepo::snapshot_tree = sub { ++$tree_reads; croak 'Unexpected tree inspection'; };
    my $getopt_config = Getopt::Long::Configure(qw(auto_abbrev ignore_case require_order));
    my $hostile_config = Getopt::Long::Configure();
    is_deeply(xCAT_plugin::freebsdrepo::handled_commands(), { freebsdrepo => 'freebsdrepo' }, 'command dispatch is dedicated');
    is_deeply(request({ command => ['copycd'], arg => ['--help'] }), [], 'unrelated command is not claimed');
    for my $flag (qw(-h --help)) {
        my $responses = run_cli($flag);
        like(messages($responses, 'data'), qr/Usage:[ ]freebsdrepo[ ]inspect/x, "$flag prints global usage");
        is(messages($responses, 'error'), '', "$flag succeeds");
    }
    help_cases();
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n";
    my $parse_prefix = 'Invalid freebsdrepo arguments: ';
    my $arity_error = "$parse_prefix\n$usage";
    my $policy_error = "${parse_prefix}Option policy requires an argument\n\n$usage";
    my $inspect_error = "Repository inspection does not accept --policy or -w\n";
    my $import_error = "Repository import requires exactly one --policy profile\n";
    my @bad = (
        [[], $usage],
        [['Inspect', $signed], $usage],
        [['IMPORT', $signed], $usage],
        [['inspect'], $arity_error],
        [['import'], $arity_error],
        [['inspect', $signed, 'extra'], $arity_error],
        [['import', $signed, 'extra', '--policy', 'approved'], $arity_error],
        [['inspect', $signed, '--policy', 'approved'], $inspect_error],
        [['inspect', $signed, '-w'], $inspect_error],
        [['inspect', '--help', $signed, 'extra'], $arity_error],
        [['import', '--help', $signed, 'extra'], $arity_error],
        [['import', $signed], $import_error],
        [['import', $signed, '--policy'], $policy_error],
        [['import', $signed, '--policy='], $policy_error],
        [['import', $signed, '--policy', 'approved', '--policy', 'wrong'], $import_error],
        [['import', $signed, '--policy', 'approved', '--policy', 'approved'], $import_error],
        [['import', $signed, '--pol', 'approved'], "${parse_prefix}Unknown option: pol\n\n$usage"],
        [['import', $signed, '--Policy', 'approved'], "${parse_prefix}Unknown option: Policy\n\n$usage"],
        [['import', $signed, '--policy', 'approved', '-W'], "${parse_prefix}Unknown option: W\n\n$usage"],
        [['import', $signed, '--unknown'], "${parse_prefix}Unknown option: unknown\n\n$usage"],
        [['--help', 'extra'], $usage],
        [['--HELP'], $usage],
        [['-h', 'inspect', $signed], $usage],
    );
    for my $case (@bad) {
        my ($args, $expected) = @$case;
        rejected(run_cli(@$args), qr/\A\Q$expected\E\z/x,
            'invalid arguments [' . join(' ', @$args) . ']');
    }
    is($native_calls, 0, 'parser does not execute native commands');
    is($tree_reads, 0, 'parser does not inspect source paths');
    is_deeply(\@site_reads, [], 'parser and help do not read configuration');
    is_deeply(Getopt::Long::Configure(), $hostile_config, 'parser preserves global Getopt configuration');
    Getopt::Long::Configure($getopt_config);
    return;
}

sub inspect_cases {
    fresh();
    unlink($policy_path) or croak $!;
    my $before = xCAT::FreeBSDRepo::snapshot_tree($installroot);
    my $native_calls = 0;
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Unexpected native execution'; };
    my $responses = run_cli('inspect', $signed);
    is(messages($responses, 'error'), '', 'inspection succeeds without policy');
    is(messages($responses, 'data'), "TREE_DIGEST:$source_tree->{digest}\nBYTES:$source_tree->{bytes}\n",
        'inspection reports the complete original tree digest and bytes');
    for my $path ('relative/tree', "$tmp/missing") {
        rejected(run_cli('inspect', $path), qr/./sx, "invalid inspection path $path");
    }
    is($native_calls, 0, 'inspection does not execute pkg or another command');
    is_deeply(\@site_reads, [], 'inspection does not read policy or installroot');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'inspection leaves source unchanged');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($installroot), $before, 'inspection makes no output changes');
    no_effect('inspection');
    return;
}

sub policy_path_cases {
    my $native_calls = 0;
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Unexpected native execution'; };
    for my $case ([undef, 'unset'], ['', 'empty'], ['0', 'zero'], [' ', 'whitespace'],
        ['relative/policy', 'relative'], [{}, 'structured']) {
        fresh();
        ($policy_path, my $name) = @$case;
        my $pattern = $name eq 'unset' || $name eq 'empty'
          ? qr/\Asite[.]freebsdimportpolicy[ ]is[ ]not[ ]set\n\z/x
          : qr/\AInvalid[ ]FreeBSD[ ]import[ ]policy[ ]path\n\z/x;
        rejected(run_cli('import', $signed, '--policy', 'approved'), $pattern, "$name site policy");
        is_deeply(\@site_reads, ['freebsdimportpolicy'], "$name policy does not read installroot");
        no_effect("$name site policy");
    }
    is($native_calls, 0, 'invalid site policy never invokes native preparation');
    return;
}

sub import_cases {
    fresh();
    my $responses = run_cli('import', $signed, '--policy', 'approved', '-w');
    is(messages($responses, 'error'), '', 'approved signed repository imports');
    my $paths = publications();
    is(scalar(@$paths), 1, 'one immutable publication is created');
    return unless @$paths == 1;
    my $path = $paths->[0];
    is_deeply($responses,
        [{ data => ["Imported FreeBSD repository to $path", "Repository: $path/repository"] }],
        'output identifies publication and repository root');
    is_deeply(\@site_reads, [qw(freebsdimportpolicy installdir)], 'import uses configured policy and installroot');
    my $manifest = xCAT::FreeBSDRepoImport::inspect_import($path, $installroot);
    is($manifest->{kind}, 'repository', 'readback proves repository publication');
    is($manifest->{native_validated}, 1, 'publication manifest records native validation');
    is($manifest->{selection_validated}, 0, 'publication does not claim package selection');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$path/repository"), $source_tree, 'complete published tree matches source');
    my $before = xCAT::FreeBSDRepo::snapshot_tree($path);
    is_deeply(run_cli('import', '--policy=approved', $signed),
        [{ data => ["Verified existing FreeBSD repository at $path", "Repository: $path/repository"] }],
        'repeat import with permuted option reports verified reuse');
    is_deeply(publications(), [$path], 'repeat keeps the same publication identity');
    rejected(run_cli('import', $signed, '--policy', 'approved', '-w'), qr/already[ ]exists/x, '-w forbids reuse');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($path), $before, 'retry and -w leave publication unchanged');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'import leaves input bytes and links unchanged');
    is_deeply(\@db_access, [], 'import/retry never opens image or package-selection tables');
    return;
}

sub profile_cases {
    for my $case ([$unsigned, 'unsigned'], [$nested, 'nested']) {
        fresh();
        my ($source, $profile) = @$case;
        is(messages(run_cli('import', $source, '--policy', $profile), 'error'), '', "$profile profile imports");
        my $paths = publications();
        is(scalar(@$paths), 1, "$profile creates one publication");
        next unless @$paths == 1;
        my $manifest = xCAT::FreeBSDRepoImport::inspect_import($paths->[0], $installroot);
        is($manifest->{native_validated}, 1, "$profile manifest records native validation");
        is_deeply(\@db_access, [], "$profile does not attach to an image");
    }
    return;
}

sub policy_cases {
    my @cases = (
        ['missing profile', sub { return; }, $signed, 'absent', qr/(?:approved|profile)/x],
        ['wrong selected key', sub { return; }, $signed, 'wrong', qr/(?:native|signature|catalogue)/ix],
        ['unsigned under signed policy', sub { return; }, $unsigned, 'approved', qr/(?:native|signature|catalogue)/ix],
        ['wrong tool pin', sub { $_[0]{tool}{sha256} = '0' x 64; }, $signed, 'approved', qr/(?:tool|executable|SHA256|digest)/ix],
        ['wrong tree approval', sub { $_[0]{repositories}{unsigned}{trust}{digest} = '0' x 64; },
            $unsigned, 'unsigned', qr/(?:trust|digest|approval)/ix]);
    for my $case (@cases) {
        my ($name, $change, $source, $profile, $pattern) = @$case;
        fresh($change);
        rejected(run_cli('import', $source, '--policy', $profile), $pattern, $name);
        no_effect($name);
    }
    fresh();
    unlink($policy_path) or croak $!;
    rejected(run_cli('import', $signed, '--policy', 'approved'), qr/(?:policy|path)/ix, 'missing configured policy');
    no_effect('missing policy');
    fresh();
    chmod(oct('0666'), $policy_path) or croak $!;
    rejected(run_cli('import', $signed, '--policy', 'approved'), qr/(?:policy|writable|permission)/ix, 'unsafe policy permissions');
    no_effect('unsafe policy');
    return;
}

sub source_failure_cases {
    for my $kind (qw(missing corrupt)) {
        my $source = $fixture->new_directory();
        command('/usr/bin/cp', '-a', "$signed/.", $source);
        my $archive = "$source/All/command-app-1.pkg";
        if ($kind eq 'missing') {
            unlink($archive) or croak $!;
        } else {
            write_file($archive, read_file($archive) . 'corrupt');
        }
        fresh();
        rejected(run_cli('import', $source, '--policy', 'approved'),
            qr/(?:archive|package|checksum|digest)/ix, "$kind signed package archive");
        no_effect("$kind archive");
    }
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($signed), $source_tree, 'negative fixtures leave shared signed input intact');
    return;
}

sub client_stub {
    return <<'CLIENT';
package xCAT::Client;
use strict;
use warnings;
use JSON;
our $EXITCODE = 0;
sub handle_response { return; }
sub submit_request {
    print JSON->new->canonical->encode($_[0]);
    return;
}
1;
CLIENT
}

sub rpm_aliases {
    my $path = shift;
    my @rpm;
    my $install_section = 0;
    my $conditional_depth = 0;
    my %sections = map { $_ => 1 } qw(install prep build check clean files pre post preun postun changelog);
    for my $line (split(/\n/x, read_file($path))) {
        ++$conditional_depth if $line =~ /\A%if(?:n?arch|n?os)?(?:\s|\z)/x;
        --$conditional_depth if $line =~ /\A%endif(?:\s|\z)/x;
        if ($line =~ /\A%(\w+)(?:\s|\z)/x && $sections{$1}) {
            $install_section = $1 eq 'install';
        }
        next unless $install_section && $line =~ /\Aln\s/x;
        my @words = shellwords($line);
        next unless @words && $words[0] eq 'ln' && $words[-1] =~ m{/sbin/freebsdrepo\z}x;
        is($conditional_depth, 0, 'RPM client alias is outside conditional sections');
        push @rpm, \@words;
    }
    return \@rpm;
}

sub alias_declarations {
    my $root = "$FindBin::Bin/../../xCAT-client";
    my $rpm = rpm_aliases("$root/xCAT-client.spec");
    is_deeply($rpm, [['ln', '-sf', '../bin/xcatclientnnr', '$RPM_BUILD_ROOT/%{prefix}/sbin/freebsdrepo']],
        'RPM installation artifact declares the supported client alias');
    my @deb = map { [split(/\s+/x, $_)] }
      grep { m{\sopt/xcat/sbin/freebsdrepo\z}x } split(/\n/x, read_file("$root/debian/xcat-client.links"));
    is_deeply(\@deb, [['opt/xcat/bin/xcatclientnnr', 'opt/xcat/sbin/freebsdrepo']],
        'Debian link artifact declares the supported client alias');
    return [] unless @$rpm == 1 && @deb == 1;
    my %targets = map { $_ => 1 } ($rpm->[0][2], '../bin/' . (split(m{/}x, $deb[0][0]))[-1]);
    return [sort keys %targets];
}

sub client_requests {
    my ($target, $arguments) = @_;
    my $client = "$FindBin::Bin/../../xCAT-client/bin/xcatclientnnr";
    my $root = $fixture->new_directory();
    make_path("$root/bin", "$root/sbin");
    copy($client, "$root/bin/xcatclientnnr") or croak $!;
    symlink($target, "$root/sbin/freebsdrepo") or croak $!;
    write_file("$root/lib/perl/xCAT/Client.pm", client_stub());
    my @requests;
    for my $argv (["$root/sbin/freebsdrepo", @$arguments],
        ["$root/bin/xcatclientnnr", 'freebsdrepo', @$arguments]) {
        my %env = (%environment, XCATROOT => $root, TERM => 'dumb', SHELL => '/bin/sh');
        my $result = xCAT::FreeBSDPkg::run_command([$^X, @$argv], cwd => $tmp,
            environment => \%env, timeout => 10, stdout_limit => 1048576);
        is($result->{exitcode}, 0, 'actual client exits successfully at submit_request boundary');
        is($result->{signal}, 0, 'client is not killed');
        my $received = $json->decode($result->{stdout});
        my @expected = @$argv;
        shift @expected;
        shift @expected if $expected[0] eq 'freebsdrepo';
        is_deeply($received->{command}, ['freebsdrepo'], 'client preserves dedicated command name');
        is_deeply($received->{arg}, \@expected, 'client preserves every argument');
        is_deeply([sort grep { /\A(?:node|noderange|range)\z/x } keys %$received], [],
            'client omits node and range fields');
        push @requests, $received;
    }
    return @requests;
}

sub transport_cases {
    my $targets = alias_declarations();
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n";
    for my $target (@$targets) {
        for my $case (['inspect', $signed], ['--help']) {
            for my $received (client_requests($target, $case)) {
                fresh();
                my $data = $case->[0] eq 'inspect'
                  ? "TREE_DIGEST:$source_tree->{digest}\nBYTES:$source_tree->{bytes}\n" : $usage;
                is_deeply(request($received), [{ data => [$data] }],
                    'transported read-only request returns the exact successful response');
                is_deeply(\@site_reads, [], 'transported read-only request does not read site configuration');
                no_effect('transported read-only request');
            }
        }
    }
    return;
}

sub import_transport_cases {
    for my $target (@{alias_declarations()}) {
        for my $received (client_requests($target, ['import', $signed, '--policy', 'approved'])) {
            fresh();
            my $responses = request($received);
            my $paths = publications();
            is(scalar(@$paths), 1, 'transported import creates one immutable publication');
            next unless @$paths == 1;
            my $path = $paths->[0];
            is_deeply($responses,
                [{ data => ["Imported FreeBSD repository to $path", "Repository: $path/repository"] }],
                'transported import returns the exact successful response');
            my $manifest = xCAT::FreeBSDRepoImport::inspect_import($path, $installroot);
            is($manifest->{native_validated}, 1, 'transported publication manifest records native validation');
            is_deeply(xCAT::FreeBSDRepo::snapshot_tree("$path/repository"), $source_tree,
                'transported import publishes the complete source snapshot');
            is_deeply(\@db_access, [], 'transported import leaves image/package selections untouched');
        }
    }
    return;
}

sub native_cases {
    plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG for native repository cases')
      unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
    plan(skip_all => 'Native repository cases require Linux') unless $^O eq 'linux';
    plan(skip_all => 'Native repository cases require container root') if $> != 0;
    native_fixtures();
    subtest 'native import and nonoverwrite' => \&import_cases;
    subtest 'explicit independent profiles' => \&profile_cases;
    subtest 'policy and trust failures' => \&policy_cases;
    subtest 'signed source integrity failures' => \&source_failure_cases;
    subtest 'transported imports publish complete repositories' => \&import_transport_cases;
    return;
}

subtest 'strict parser and global help' => \&parser_cases;
subtest 'read-only inspection' => \&inspect_cases;
subtest 'site policy presence and path validation' => \&policy_path_cases;
subtest 'packaged alias and client transport' => \&transport_cases;
subtest 'native repository operations' => \&native_cases;
ok(!-e "$tmp/package-script-executed", 'no package installation script executed');
ok(!-e '/var/db/pkg', 'default package database remains absent');
done_testing();
