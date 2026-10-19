#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Fcntl qw(LOCK_EX LOCK_NB);
use JSON;
use Storable qw(dclone);
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::PostageFixture qw(fixture write_file read_file $root $custom $stock $expected);
use XCAT::Test::FreeBSDRepoFixture;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDRepo;
use xCAT::FreeBSDRepoImport;
use xCAT::FreeBSDPackagePlan;
use xCAT::FreeBSDPostscript;
require xCAT::Postage;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_PKG to the Linux pkg 2.8.2 executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_PKG});
plan(skip_all => 'Preparation fixtures require Linux container root') unless $^O eq 'linux' && $> == 0;

my $tmp = abs_path(tempdir(CLEANUP => 1, DIR => '/tmp'));
my $json = JSON->new->utf8->canonical;
my $tool = { path => abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG}) };
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
if (defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR})) {
    $tool->{library_directory} = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
    $tool->{library_digest} = xCAT::FreeBSDRepo::snapshot_tree($tool->{library_directory})->{digest};
    $environment{LD_LIBRARY_PATH} = $tool->{library_directory};
}

sub command {
    my @argv = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@argv, cwd => $tmp,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub run_pkg { return command($tool->{path}, '-C', "$tmp/pkg.conf", @_); }
sub fixture_write { make_path(dirname($_[0])); return write_file(@_); }

fixture(1);
my $installroot = "$root/install";
make_path("$tmp/empty", "$tmp/repos");
write_file("$tmp/pkg.conf", $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$tmp/db", PKG_CACHEDIR => "$tmp/cache", REPOS_DIR => ["$tmp/repos"],
    REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false, SYSLOG => JSON::false }));
$tool->{sha256} = sha256_hex(read_file($tool->{path}));
my $repo_fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $tmp,
    run_pkg => \&run_pkg, command => \&command, write_file => \&fixture_write);
my ($plan, $empty_plan);
subtest 'actual published package prerequisite' => sub {
    is(run_pkg('-v'), "2.8.2\n", 'fixtures use native pkg 2.8.2');
    my $source = $repo_fixture->release_tree(0);
    my $release = xCAT::FreeBSDRepoImport::import_release($source, $installroot, tool => $tool,
        trust => { type => 'operator-trusted-release', digest => xCAT::FreeBSDRepo::inspect_release_tree($source)->{digest} });
    my $resolver = { version => '2.8.2', sha256 => $tool->{sha256} };
    $resolver->{library_digest} = $tool->{library_digest} if exists($tool->{library_digest});
    my @selected = map { { repository => 0, identity => [$_, '15.1', "base/$_", 'FreeBSD:15:amd64'] } }
      qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base);
    push @selected, { repository => 0, identity => ['pkg', '2.6.2_1', 'ports-mgmt/pkg', 'FreeBSD:15:amd64'] };
    $plan = xCAT::FreeBSDPackagePlan::publish(xCAT::FreeBSDPackagePlan::compose(installroot => $installroot,
        resolver => $resolver, components => ['base', 'kernel'],
        repositories => [{ publication => $release->{path}, role => 'base' }], selected => \@selected,
        applications => []), $installroot);
    $empty_plan = xCAT::FreeBSDPackagePlan::publish(xCAT::FreeBSDPackagePlan::compose(installroot => $installroot,
        resolver => $resolver, scope => 'applications', components => [], applications => [], selected => [],
        repositories => [{ publication => $release->{path}, role => 'base' }]), $installroot);
    write_file("$tmp/base-list", "# original\nbase\nkernel\n");
    $xCAT::Table::rows{osimage}[0]{imagetype} = 'freebsd';
    $xCAT::Table::rows{osimage}[0]{osname} = 'FreeBSD';
    $xCAT::Table::rows{freebsdimage} = [{ imagename => 'image1', imageversion => '2',
        bootdir => "$tmp/boot", pkgdir => "$release->{path}/base", pkglist => "$tmp/base-list" }];
    is($release->{native_validated}, 1, 'base repository has actual native verification');
    is(xCAT::FreeBSDPackagePlan::inspect($plan->{path}, $installroot)->{digest}, $plan->{digest},
        'actual published plan verifies');
    ok(!-e '/var/db/pkg', 'default package database is absent');
    done_testing();
};

my $source_root = "$installroot/postscripts";
make_path("$source_root/nested");
write_file("$source_root/syslog", "#!/bin/sh\ntouch '$tmp/script-executed'\n");
write_file("$source_root/nested/helper", "opaque\0helper\xff");
chmod(oct('0640'), "$source_root/syslog", "$source_root/nested/helper") == 2 or croak $!;
link("$source_root/nested/helper", "$source_root/hard-helper") or croak $!;
symlink('nested/helper', "$source_root/alias") or croak $!;
my $sequence = 0;
sub store { return "$tmp/store-" . ++$sequence; }
sub prepare {
    my ($directory, $selection, @options) = @_;
    return xCAT::FreeBSDPostscript::prepare_execution('node1', 'install', directory => $directory,
        selection => $selection, plan => $plan->{path}, @options);
}
sub manifest { return $json->decode(read_file("$_[0]/$_[1]{id}/manifest.json")); }
sub source_observation {
    my %entries;
    find({ no_chdir => 1, wanted => sub {
        my $path = $File::Find::name;
        my @state = lstat($path);
        my $content = -l _ ? readlink($path) : -f _ ? sha256_hex(read_file($path)) : 'directory';
        $entries{$path} = [@state[0, 1, 2, 3, 4, 5, 7], $content];
    } }, $source_root);
    return \%entries;
}
sub reject {
    my ($operation, $description) = @_;
    my $result;
    my $ok = eval { $result = $operation->(); 1; };
    my $error = $@;
    ok(!$ok, "$description rejects the operation");
    like($error, qr/\AFreeBSD[ ]postscript[ ]preparation[ ](?:failed[ ]during[ ][a-z ]+|verification[ ]failed)\n\z/x,
        "$description returns a fixed private-stage error");
    ok(!defined($result), "$description returns no preparation");
    return;
}

sub scoped_preparation_cases {
    subtest 'scoped package preparation requires the matching update selection' => sub {
        my $directory = store();
        my @options = (directory => $directory, plan => $empty_plan->{path}, package_scope => 'applications');
        my $prepared = xCAT::FreeBSDPostscript::prepare_execution('node1', 'install', @options,
            selection => { kind => 'update', raw => 'otherpkgs' });
        is(read_file("$directory/$prepared->{id}/package.plan"), read_file($empty_plan->{path}),
            'empty application plan is retained without base packages');
        my $request = $json->decode(read_file("$directory/$prepared->{id}/package-request.json"));
        is($request->{scope}, 'applications', 'preparation binds the operation scope');
        is_deeply(xCAT::FreeBSDPostscript::read_execution($prepared->{id}, directory => $directory), $prepared,
            'scoped preparation verifies on readback');
        for my $kind (qw(firstboot repeat)) {
            reject(sub { xCAT::FreeBSDPostscript::prepare_execution('node1', 'install', @options,
                    selection => { kind => $kind }); }, 'scoped plan in an installation selection');
        }
        reject(sub { xCAT::FreeBSDPostscript::prepare_execution('node1', 'install',
                directory => store(), plan => $empty_plan->{path}, selection => { kind => 'update', raw => 'otherpkgs' }); },
            'scoped plan without its requested scope');
        done_testing();
    };
    return;
}

sub ssh_policy_cases {
    subtest 'admit the supplied SSH adapter only with an explicit supported image policy' => sub {
        local $xCAT::Table::rows{osimage} = dclone($xCAT::Table::rows{osimage});
        local $xCAT::Table::rows{postscripts} = [
            { node => 'xcatdefaults', postscripts => 'remoteshell', postbootscripts => 'remoteshell' },
            { node => 'node1', postscripts => '', postbootscripts => '' },
        ];
        local $::XCATSITEVALS{runbootscripts} = 'yes';
        local $::XCATSITEVALS{sshbetweennodes} = 'ALLGROUPS';
        my $image = $xCAT::Table::rows{osimage}[0];
        $image->{postscripts} = $image->{postbootscripts} = '';
        my $original = read_file($custom);
        my $template = $original;
        $template =~ s/(export[ ]ENABLESSHBETWEENNODES\n)/$1#OSIMAGE_VARS_EXPORT#\n/x;
        write_file($custom, $template);
        my $shared = "$FindBin::Bin/../../xCAT/postscripts";
        for my $name (qw(remoteshell remoteshell.freebsd)) {
            write_file("$source_root/$name", read_file("$shared/$name"));
            chmod(oct('0755'), "$source_root/$name") == 1 or croak $!;
        }
        symlink('remoteshell', "$source_root/ssh-alias") or croak $!;
        symlink('remoteshell.freebsd', "$source_root/native-alias") or croak $!;
        write_file("$source_root/nested/ssh-tool", read_file("$shared/remoteshell"));
        write_file("$source_root/nested/remoteshell.freebsd", read_file("$shared/remoteshell.freebsd"));
        my $reject_policy = sub {
            my ($selection, $label) = @_;
            my $directory = store();
            my $prepared = eval { prepare($directory, $selection); };
            my $error = $@;
            ok(!$prepared, "$label returns no preparation");
            is($error, "FreeBSD remoteshell requires osimage.environvar=ENABLESSHBETWEENNODES=NO\n",
                "$label explains the supported image setting");
            my @published = grep {
                -f "$_/manifest.json" && $json->decode(read_file("$_/manifest.json"))->{kind}
                  eq 'freebsd-postscript-preparation-v1'
            } glob("$directory/*");
            is(scalar(@published), 0, "$label publishes no execution preparation");
            return;
        };
        my @invalid = (undef, '', 'ENABLESSHBETWEENNODES=YES', 'ENABLESSHBETWEENNODES=',
            'ENABLESSHBETWEENNODES=nO', 'ENABLESSHBETWEENNODES=$POLICY',
            'ENABLESSHBETWEENNODES=NO,ENABLESSHBETWEENNODES=YES',
            'ENABLESSHBETWEENNODES=NO,ENABLESSHBETWEENNODES=NO',
            'ENABLESSHBETWEENNODES="NO', 'ENABLESSHBETWEENNODES=NO extra');
        for my $index (0 .. $#invalid) {
            $image->{environvar} = $invalid[$index];
            $reject_policy->({ kind => 'firstboot' }, "unsupported policy $index");
        }
        $image->{environvar} = undef;
        for my $selection ({ kind => 'repeat' }, { kind => 'update', raw => '' },
            map { { kind => 'update', raw => $_ } }
              qw(remoteshell ssh-alias native-alias nested/ssh-tool defaults-postscripts-start-here)) {
            $reject_policy->($selection, 'selected native adapter');
        }
        for my $value (qw(no NO No n N 0), q{'NO'}, q{"NO"}) {
            $image->{environvar} = "OTHER_SETTING=fixture,ENABLESSHBETWEENNODES=$value";
            my $directory = store();
            my $prepared = prepare($directory, { kind => 'update', raw => 'ssh-alias' });
            my $compiled = xCAT::FreeBSDPostscript::compile_execution($prepared->{id}, directory => $directory);
            is_deeply([map { pack('H*', $_->{name}) } @{$compiled->{entries}}], ['ssh-alias'],
                "supported literal $value preserves the selected alias");
            my $context = $json->decode(read_file("$directory/$prepared->{id}/context.json"));
            is($context->{image}{environvar}, $image->{environvar}, "supported literal $value is frozen");
            like($compiled->{driver}, qr/ENABLESSHBETWEENNODES='YES'\n/x,
                'the inherited sharing default remains unchanged');
            like($compiled->{driver}, qr/\n\QENABLESSHBETWEENNODES=$value\E\nexport[ ]ENABLESSHBETWEENNODES\n/x,
                'the renderer delivers the explicit image override');
        }
        $image->{environvar} = 'ENABLESSHBETWEENNODES=NO';
        my $directory = store();
        my $retained = prepare($directory, { kind => 'firstboot' });
        my $compiled = xCAT::FreeBSDPostscript::compile_execution($retained->{id}, directory => $directory);
        $image->{environvar} = undef;
        is_deeply(xCAT::FreeBSDPostscript::read_execution($retained->{id}, directory => $directory), $retained,
            'policy changes do not invalidate a retained preparation');
        is_deeply(xCAT::FreeBSDPostscript::compile_execution($retained->{id}, directory => $directory), $compiled,
            'retained execution still uses its frozen policy');
        my $unselected = prepare(store(), { kind => 'update', raw => 'syslog' });
        ok($unselected, 'an unselected native adapter imposes no policy');
        $::XCATSITEVALS{runbootscripts} = 'no';
        my $disabled_directory = store();
        my $disabled = prepare($disabled_directory, { kind => 'repeat' });
        is_deeply(xCAT::FreeBSDPostscript::compile_execution($disabled->{id}, directory => $disabled_directory)->{entries},
            [], 'disabled repeat retains an empty selection without a policy');
        my $raw = "remoteshell; echo 'opaque'";
        my $opaque_directory = store();
        my $opaque = prepare($opaque_directory, { kind => 'update', raw => $raw });
        is(read_file("$opaque_directory/$opaque->{id}/selection"), $raw, 'preparation still retains opaque raw input');
        my $unusable = eval { xCAT::FreeBSDPostscript::compile_execution($opaque->{id}, directory => $opaque_directory); };
        ok(!$unusable && $@, 'opaque shell operators remain unusable at compilation');
        write_file("$source_root/remoteshell.freebsd", "#!/bin/sh\nexit 0\n");
        ok(prepare(store(), { kind => 'update', raw => 'remoteshell' }), 'custom native adapter keeps its own policy');
        write_file("$source_root/remoteshell.freebsd", read_file("$shared/remoteshell.freebsd"));
        write_file("$source_root/remoteshell", "#!/bin/sh\nexit 0\n");
        ok(prepare(store(), { kind => 'update', raw => 'remoteshell' }), 'custom launcher keeps its own policy');
        for my $name (qw(remoteshell remoteshell.freebsd ssh-alias native-alias nested/ssh-tool nested/remoteshell.freebsd)) {
            unlink("$source_root/$name") or croak $!;
        }
        write_file($custom, $original);
        done_testing();
    };
    return;
}

my $native_calls = 0;
{
    local *xCAT::FreeBSDPkg::run_command = gensym();
    *xCAT::FreeBSDPkg::run_command = sub { ++$native_calls; croak 'Preparation attempted a native command'; };
    scoped_preparation_cases();
    ssh_policy_cases();

    subtest 'freeze first and repeated boot from one source' => sub {
        my $directory = store();
        local $::XCATSITEVALS{runbootscripts} = 'yes';
        my $before = source_observation();
        my $bindings = xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path}, directory => $directory);
        is_deeply([sort keys %$bindings], [qw(firstboot repeat)], 'both boot selections are prepared');
        my %prepared = map { $_ => xCAT::FreeBSDPostscript::read_execution($bindings->{$_}, directory => $directory) }
          qw(firstboot repeat);
        is($prepared{firstboot}{source_id}, $prepared{repeat}{source_id}, 'both selections bind the same sealed source');
        for my $name (qw(context.json package.plan package-request.json)) {
            is(read_file("$directory/$bindings->{firstboot}/$name"), read_file("$directory/$bindings->{repeat}/$name"),
                "both selections bind the same $name bytes");
        }
        my %compiled = map { $_ => xCAT::FreeBSDPostscript::compile_execution($bindings->{$_}, directory => $directory) }
          qw(firstboot repeat);
        is_deeply([map { $_->{phase} } @{$compiled{firstboot}{entries}}],
            [(('postscripts') x 5), (('postbootscripts') x 3)], 'first boot preserves both ordered phases');
        is_deeply([map { pack('H*', $_->{name}) } @{$compiled{repeat}{entries}}],
            [qw(bootfirst bootimage bootlast)], 'repeated boot selects only postbootscripts');
        is_deeply(source_observation(), $before, 'pair preparation preserves original source files');
        is_deeply(xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path}, directory => $directory),
            $bindings, 'unchanged preparation is deterministic');
        my $original = read_file($custom);
        write_file($custom, 'replacement is not a template');
        for my $kind (qw(firstboot repeat)) {
            is_deeply(xCAT::FreeBSDPostscript::compile_execution($bindings->{$kind}, directory => $directory),
                $compiled{$kind}, "$kind uses frozen content after live source changes");
        }
        write_file($custom, $original);
        $::XCATSITEVALS{runbootscripts} = 'no';
        my $disabled = xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path}, directory => $directory);
        isnt($disabled->{repeat}, $bindings->{repeat}, 'changed repeat policy changes its preparation identity');
        my $repeat = xCAT::FreeBSDPostscript::compile_execution($disabled->{repeat}, directory => $directory);
        is($repeat->{enabled}, 0, 'disabled repeat policy cannot authorize another script execution');
        is_deeply($repeat->{entries}, [], 'disabled repeat has no script entries');
        done_testing();
    };

    subtest 'bind the real renderer, complete source and package request' => sub {
        my $directory = store();
        my $before = source_observation();
        my $prepared = prepare($directory, { kind => 'firstboot' });
        my $record = manifest($directory, $prepared);
        is_deeply([sort keys %$prepared], [sort qw(id kind node nodesetstate source_id package_plan_sha256 entries bytes)],
            'descriptor exposes identities and counts, not private inputs');
        is($prepared->{kind}, 'freebsd-postscript-preparation-v1', 'preparation is not an execution receipt');
        is($prepared->{package_plan_sha256}, $plan->{digest}, 'actual inspected package identity is bound');
        is(read_file("$directory/$prepared->{id}/package.plan"), read_file($plan->{path}), 'exact package bytes are retained');
        my $source = xCAT::FreeBSDPostscript::read_source($prepared->{source_id}, directory => $directory);
        is(read_file("$source->{directory}/rendered"), $expected, 'actual renderer bytes are unchanged');
        is($prepared->{entries}, $source->{entries}, 'the complete source count is retained');
        my $modes = $record->{mode_policy};
        is($modes->{name}, 'root-private-preserve-v1', 'adopted mode policy is bound as data');
        is_deeply($modes->{outer}, { mode => oct('0700'), uid => 0, gid => 0 }, 'outer target policy is private');
        is($modes->{entries}{unpack('H*', 'syslog')}{effective}{mode}, oct('0640'), 'nonexecutable administrator file is not repaired');
        is($modes->{entries}{unpack('H*', 'alias')}{type}, 'link', 'internal link remains in the policy roster');
        is_deeply(source_observation(), $before, 'source bytes, modes and links are unchanged');
        is_deeply(xCAT::FreeBSDPostscript::read_execution($prepared->{id}, directory => $directory), $prepared,
            'private readback retains the exact descriptor');
        is(prepare($directory, { kind => 'firstboot' })->{id}, $prepared->{id}, 'same inputs reuse identity with a fresh seal');
        ok(!-e "$tmp/script-executed", 'source scripts did not execute');
        done_testing();
    };

    subtest 'retain typed opaque selections and observed repeat policy' => sub {
        my $directory = store();
        my $first = prepare($directory, { kind => 'firstboot' });
        my $empty = prepare($directory, { kind => 'update', raw => '' });
        isnt($empty->{id}, $first->{id}, 'empty update differs from absent firstboot input');
        is(manifest($directory, $first)->{selection}{raw_present}, 0, 'firstboot has no raw update input');
        is(manifest($directory, $empty)->{selection}{raw_present}, 1, 'empty update input remains present');
        my $raw = "odd-start-here,custom 'two words'; echo \"x,y\"\n\0\xff";
        my $update = prepare($directory, { kind => 'update', raw => $raw });
        is(read_file("$directory/$update->{id}/selection"), $raw, 'raw shell punctuation and bytes remain opaque');
        isnt($update->{id}, $empty->{id}, 'nonempty update changes preparation identity');
        is(manifest($directory, $update)->{selection}{sha256}, sha256_hex($raw), 'raw request digest covers exact bytes');
        local $::XCATSITEVALS{runbootscripts} = 'no';
        my $repeat = prepare($directory, { kind => 'repeat' });
        my $observed = $json->decode(read_file("$directory/$repeat->{id}/context.json"));
        is($observed->{repeat}{value}, 'no', 'disabled repeat policy is retained without authorizing execution');
        $::XCATSITEVALS{runbootscripts} = 'yes';
        isnt(prepare($directory, { kind => 'repeat' })->{id}, $repeat->{id}, 'repeat policy changes identity');
        undef $::XCATSITEVALS{runbootscripts};
        my $undefined = prepare($directory, { kind => 'repeat' });
        my $missing = $json->decode(read_file("$directory/$undefined->{id}/context.json"));
        ok(!defined($missing->{repeat}{value}), 'undefined repeat value is retained');
        $::XCATSITEVALS{runbootscripts} = '';
        my $blank = prepare($directory, { kind => 'repeat' });
        my $empty_value = $json->decode(read_file("$directory/$blank->{id}/context.json"));
        is($empty_value->{repeat}{value}, '', 'empty repeat value is retained');
        isnt($blank->{id}, $undefined->{id}, 'empty and undefined repeat values have distinct identities');
        done_testing();
    };

    subtest 'reject invalid requests and node image definitions' => sub {
        for my $request ({ kind => 'update' }, { kind => 'update', raw => undef },
            { kind => 'firstboot', raw => '' }, { kind => 'private-secret=not-public' }, { kind => 'repeat', receipt => 'success' }) {
            reject(sub { prepare(store(), $request) }, 'invalid typed selection');
        }
        my $rows = dclone(\%xCAT::Table::rows);
        for my $case (
            [sub { $xCAT::Table::rows{nodelist}[0]{disable} = 'yes'; }, 'disabled node'],
            [sub { $xCAT::Table::rows{nodetype}[0]{provmethod} = 'unrelated'; }, 'missing keyed image'],
            [sub { $xCAT::Table::rows{nodetype}[0]{arch} = 'aarch64'; }, 'unsupported node architecture'],
            [sub { $xCAT::Table::rows{osimage}[0]{disable} = 'yes'; }, 'disabled OS image'],
            [sub { $xCAT::Table::rows{freebsdimage}[0]{disable} = '1'; }, 'disabled package image'],
        ) {
            $case->[0]->();
            reject(sub { prepare(store(), { kind => 'firstboot' }) }, $case->[1]);
            %xCAT::Table::rows = %{dclone($rows)};
        }
        my $getter = \&xCAT::Table::getAttribs;
        {
            local *xCAT::Table::getAttribs = gensym();
            *xCAT::Table::getAttribs = sub {
                my @found = $getter->(@_);
                return (@found, @found) if $_[0]{table} eq 'osimage';
                return wantarray ? @found : $found[0];
            };
            reject(sub { prepare(store(), { kind => 'firstboot' }) }, 'ambiguous keyed image');
        }
        reject(sub { prepare(store(), { kind => 'firstboot' }, image => { imagename => 'arbitrary' }); },
            'caller supplied image substitution');
        my $overlap = "$source_root/forbidden-private";
        reject(sub { prepare($overlap, { kind => 'firstboot' }) }, 'source-overlapping state path');
        ok(!-e $overlap, 'overlap rejection creates no source member');
        done_testing();
    };

    subtest 'detect observed drift after actual source sealing' => sub {
        my $seal = \&xCAT::FreeBSDPostscript::seal_source;
        my $rows = dclone(\%xCAT::Table::rows);
        my $list = read_file("$tmp/base-list");
        for my $case (
            [sub { $xCAT::Table::rows{nodetype}[0]{profile} = 'changed'; }, 'node definition drift'],
            [sub { write_file("$tmp/base-list", "# replaced\nbase\nkernel\n"); }, 'package source byte drift'],
        ) {
            my $calls = 0;
            {
                local *xCAT::FreeBSDPostscript::seal_source = gensym();
                *xCAT::FreeBSDPostscript::seal_source = sub {
                    my $source = $seal->(@_);
                    ++$calls;
                    $case->[0]->();
                    return $source;
                };
                reject(sub { prepare(store(), { kind => 'firstboot' }) }, $case->[1]);
            }
            is($calls, 1, "$case->[1] follows actual source sealing");
            is(length(read_file("$tmp/base-list")), length($list), "$case->[1] retains the package-list byte count");
            %xCAT::Table::rows = %{dclone($rows)};
            write_file("$tmp/base-list", $list);
        }
        done_testing();
    };

    subtest 'read retained content without current tables, render or repositories' => sub {
        my $directory = store();
        my $prepared = prepare($directory, { kind => 'update', raw => 'syslog "two words"' });
        my $prior = read_file($custom);
        write_file($custom, 'changed and no longer a template');
        rename($plan->{path}, "$plan->{path}.retained") or croak $!;
        my ($result, $compiled, $error);
        {
            local *xCAT::Table::new = gensym();
            *xCAT::Table::new = sub { croak 'Readback queried current tables'; };
            local *xCAT::FreeBSDPackagePlan::inspect_image = gensym();
            *xCAT::FreeBSDPackagePlan::inspect_image = sub { croak 'Readback inspected current repositories'; };
            $result = eval { xCAT::FreeBSDPostscript::read_execution($prepared->{id}, directory => $directory); };
            $error = $@;
            $compiled = xCAT::FreeBSDPostscript::compile_execution($prepared->{id}, directory => $directory);
        }
        rename("$plan->{path}.retained", $plan->{path}) or croak $!;
        write_file($custom, $prior);
        is($error, '', 'readback does not require current source or package publication');
        is_deeply($result, $prepared, 'readback returns the retained preparation');
        is($compiled->{manifest}{preparation_id}, $prepared->{id}, 'driver binds the retained preparation');
        is($compiled->{manifest}{source_id}, $prepared->{source_id}, 'driver binds the retained source');
        is_deeply([map { pack('H*', $_->{name}) } @{$compiled->{entries}}], ['syslog'],
            'driver selects the retained explicit script');
        is(pack('H*', $compiled->{entries}[0]{raw}), 'syslog "two words"', 'driver retains exact argument quoting');
        is($compiled->{id}, sha256_hex($json->encode($compiled->{manifest}) . "\n"), 'driver identity binds its complete manifest');
        for my $name (qw(selection context.json package.plan package-request.json manifest.json)) {
            my $path = "$directory/$prepared->{id}/$name";
            my $bytes = read_file($path);
            write_file($path, $bytes . 'x');
            reject(sub { xCAT::FreeBSDPostscript::read_execution($prepared->{id}, directory => $directory); },
                "altered retained $name");
            write_file($path, $bytes);
        }
        is_deeply(xCAT::FreeBSDPostscript::read_execution($prepared->{id}, directory => $directory), $prepared,
            'restored retained bytes verify');
        done_testing();
    };

    subtest 'reject special modes, bounds and incomplete publication' => sub {
        chmod(oct('04640'), "$source_root/syslog") == 1 or croak $!;
        reject(sub { prepare(store(), { kind => 'firstboot' }) }, 'special source permission');
        chmod(oct('0640'), "$source_root/syslog") == 1 or croak $!;
        rename($custom, "$tmp/custom-retained") or croak $!;
        my $stock_mode = (lstat($stock))[2] & oct('7777');
        chmod(oct('04644'), $stock) == 1 or croak $!;
        reject(sub { prepare(store(), { kind => 'firstboot' }) }, 'special stock template permission');
        chmod($stock_mode, $stock) == 1 or croak $!;
        rename("$tmp/custom-retained", $custom) or croak $!;
        my $directory = store();
        my $prepared = prepare($directory, { kind => 'update', raw => '1234' }, preparation_limits => { max_selection_bytes => 4 });
        is(read_file("$directory/$prepared->{id}/selection"), '1234', 'exact reduced selection bound is admitted');
        reject(sub { prepare(store(), { kind => 'update', raw => '12345' }, preparation_limits => { max_selection_bytes => 4 }); },
            'one byte beyond selection bound');
        reject(sub { prepare(store(), { kind => 'firstboot' }, preparation_limits => { max_selection_bytes => 1048577 }); },
            'increased preparation limit');
        for my $limit (qw(max_context_bytes max_plan_bytes max_request_bytes max_manifest_bytes)) {
            reject(sub { prepare(store(), { kind => 'firstboot' }, preparation_limits => { $limit => 1 }); },
                "reduced $limit overflow");
        }
        my $write = \&xCAT::FreeBSDPostscript::_write;
        my $injected = 0;
        {
            local *xCAT::FreeBSDPostscript::_write = gensym();
            *xCAT::FreeBSDPostscript::_write = sub {
                $write->(@_);
                if ($_[0] =~ m{/content/context[.]json\z}x) { ++$injected; croak 'Storage failure after actual write'; }
                return;
            };
            reject(sub { prepare(store(), { kind => 'firstboot' }) }, 'failed private content write');
        }
        is($injected, 1, 'publication fault follows an actual private write');
        done_testing();
    };
}
is($native_calls, 0, 'preparation and readback invoke no native command or solver');

subtest 'partitionfile pools become a private firstboot operation' => sub {
    my $directory = store();
    local %xCAT::Table::rows = %{dclone(\%xCAT::Table::rows)};
    local $::XCATSITEVALS{runbootscripts} = 'yes';
    $xCAT::Table::rows{postscripts} = [{node => 'xcatdefaults', postscripts => 'syslog', postbootscripts => 'syslog'}];
    $xCAT::Table::rows{osimage}[0]{postscripts} = '';
    $xCAT::Table::rows{osimage}[0]{postbootscripts} = '';
    my $syslog_mode = (stat("$source_root/syslog"))[2] & oct('7777');
    chmod(oct('0755'), "$source_root/syslog") or croak $!;
    my @helpers = qw(configstorage.freebsd configzfs.freebsd configzfs-freebsd.awk);
    for my $helper (@helpers) {
        write_file("$source_root/$helper", read_file("$FindBin::Bin/../../xCAT/postscripts/$helper"));
        chmod($helper =~ /[.]awk\z/x ? oct('0644') : oct('0755'), "$source_root/$helper") or croak $!;
    }
    require xCAT::FreeBSDStorage;
    my ($os_text, $sections) = xCAT::FreeBSDStorage::sections(
        "filesystem=zfs\n[pool tank]\naction=create\ntopology=mirror\nvdevs=vtbd2\@DATA2,vtbd3\@DATA3\n"
        . "encryption=aes-256-gcm\nkey_source=passwd\n"
        . "[pool archive]\naction=create\ntopology=stripe\nvdevs=vtbd4\@DATA4\n");
    my $storage = xCAT::FreeBSDStorage::compile('node1',
        { zfs_vdevs => 'vtbd0@OS0,vtbd1@OS1' }, $sections,
        abs_path("$FindBin::Bin/../../xCAT/postscripts/configzfs-freebsd.awk"));
    my $raw_key = pack('C*', 0 .. 31);
    $xCAT::Table::rows{passwd} = [{ key => 'freebsd-zfs', username => 'node1/tank',
        password => unpack('H*', $raw_key), disable => 'no' }];
    my $before = source_observation();
    my $tables = dclone(\%xCAT::Table::rows);
    my $bindings = eval { xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path},
        directory => $directory, data_storage => $storage); };
    ok($bindings, 'boot preparation accepts the compiled partitionfile storage');
    if (!$bindings) {
        diag($@);
        unlink(map { "$source_root/$_" } @helpers) == @helpers or croak $!;
        chmod($syslog_mode, "$source_root/syslog") or croak $!;
        done_testing();
        return;
    }
    is_deeply(source_observation(), $before, 'preparation does not put generated policies or keys in the public tree');
    is_deeply(\%xCAT::Table::rows, $tables, 'preparation does not change administrator tables');
    is_deeply(xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path},
        directory => $directory, data_storage => $storage), $bindings, 'same declaration and key reuse the exact snapshot');
    my %prepared = map { $_ => xCAT::FreeBSDPostscript::read_execution($bindings->{$_}, directory => $directory) }
      qw(firstboot repeat);
    isnt($prepared{firstboot}{source_id}, $prepared{repeat}{source_id}, 'only firstboot binds the private storage payload');
    for my $kind (qw(firstboot repeat)) {
        my $compiled = xCAT::FreeBSDPostscript::compile_execution($bindings->{$kind}, directory => $directory);
        my @names = map { pack('H*', $_->{name}) } @{$compiled->{entries}};
        if ($kind eq 'firstboot') {
            is($names[0], 'configstorage.freebsd', 'storage precedes all administrator postscripts');
            is(scalar(grep { $_ eq 'configstorage.freebsd' } @names), 1, 'exactly one automatic storage entry');
        } else {
            ok(!grep({ $_ eq 'configstorage.freebsd' } @names), 'repeated boot does not replay storage creation');
        }
        my $run = ($kind eq 'firstboot' ? 'b' : 'c') x 32;
        my $export = xCAT::FreeBSDPostscript::export_execution($bindings->{$kind}, directory => $directory,
            run => $run, generation => '2' x 32, attempt => '3' x 32, boot => '4' x 64);
        my $target = "$tmp/storage-$kind";
        mkdir($target, oct('0700')) or croak $!;
        command('/bin/tar', '-xpf', $export->{archive}{path}, '-C', $target);
        my $payload = "$target/tree/xcat-storage.d";
        if ($kind eq 'firstboot') {
            is(read_file("$payload/pools"), "archive\ntank\n", 'real export carries the complete ordered pool roster');
            is(read_file("$payload/tank.key"), $raw_key, 'private SSH export carries the exact enrolled key bytes');
            is((stat($payload))[2] & oct('7777'), oct('0700'), 'payload directory is private');
            for my $name (qw(pools archive.conf tank.conf tank.key)) {
                is((stat("$payload/$name"))[2] & oct('7777'), oct('0600'), "$name is private in the delivered tree");
            }
            like(read_file("$payload/archive.conf"), qr/^pool=archive$/mx, 'second pool policy is included');
            unlike(read_file("$target/driver"), qr/\Q$raw_key\E/x, 'key bytes are absent from the command driver');
        } else {
            ok(!-e $payload, 'repeated boot exports neither generated policies nor keys');
        }
    }
    $xCAT::Table::rows{passwd}[0]{password} = unpack('H*', reverse($raw_key));
    my $changed = xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path},
        directory => $directory, data_storage => $storage);
    isnt($changed->{firstboot}, $bindings->{firstboot}, 'credential changes alter the firstboot preparation identity');
    is($changed->{repeat}, $bindings->{repeat}, 'credential changes do not alter repeated boot');
    is_deeply(xCAT::FreeBSDPostscript::read_execution($bindings->{firstboot}, directory => $directory),
        $prepared{firstboot}, 'earlier preparation remains immutable');
    $xCAT::Table::rows{passwd} = [];
    my $missing = eval { xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path},
        directory => store(), data_storage => $storage); };
    ok(!$missing && $@, 'missing enrolled key prevents boot preparation');
    is_deeply(source_observation(), $before, 'failure also leaves public sources unchanged');
    unlink(map { "$source_root/$_" } @helpers) == @helpers or croak $!;
    chmod($syslog_mode, "$source_root/syslog") or croak $!;
    done_testing();
};

subtest 'export the frozen tree, driver and full native verification manifests' => sub {
    my $directory = store();
    my $unexecutable = prepare($directory, { kind => 'update', raw => 'syslog' });
    my %options = (directory => $directory, run => '1' x 32, generation => '2' x 32, attempt => '3' x 32);
    my $denied = eval { xCAT::FreeBSDPostscript::export_execution($unexecutable->{id}, %options); };
    ok(!$denied && $@, 'selected nonexecutable script prevents export');
    ok(!-e "$directory/export-$options{run}", 'rejected selection publishes nothing');
    chmod(oct('0751'), "$source_root/syslog") == 1 or croak $!;
    link("$source_root/alias", "$source_root/alias-hard") or croak $!;
    write_file("$source_root/nested/space #=\\\n\xff", "binary\0bytes\xff");
    chmod(oct('0444'), "$source_root/nested/space #=\\\n\xff") == 1 or croak $!;
    symlink('syslog', "$source_root/run-alias") or croak $!;
    my $prepared = prepare($directory, { kind => 'update', raw => "run-alias 'two words',syslog same" });
    my $compiled = xCAT::FreeBSDPostscript::compile_execution($prepared->{id}, directory => $directory);
    my $original = read_file("$source_root/syslog");
    write_file("$source_root/syslog", "changed live script\n");
    my $export = xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %options);
    is($export->{scripts}, 2, 'both explicit selections are exported');
    is($export->{archive}{sha256}, sha256_hex(read_file($export->{archive}{path})), 'archive descriptor covers exact bytes');
    is((stat($export->{archive}{path}))[2] & oct('7777'), oct('0400'), 'retained archive is private');
    my $target = "$tmp/extracted";
    mkdir($target, oct('0700')) or croak $!;
    command('/bin/tar', '-xpf', $export->{archive}{path}, '-C', $target);
    is(read_file("$target/tree/syslog"), $original, 'live script changes do not replace the sealed script');
    is(read_file("$target/driver"), $compiled->{driver}, 'actual compiler output is delivered unchanged');
    is((stat("$target/tree/syslog"))[2] & oct('7777'), oct('0751'), 'original ordinary executable mode is preserved');
    is((stat("$target/tree/nested/helper"))[1], (stat("$target/tree/hard-helper"))[1], 'file hard links survive archival');
    is((lstat("$target/tree/alias"))[1], (lstat("$target/tree/alias-hard"))[1], 'symlink hard links survive archival');
    is(readlink("$target/tree/run-alias"), 'syslog', 'selected symbolic link survives archival');
    is(read_file("$target/tree/nested/space #=\\\n\xff"), "binary\0bytes\xff", 'unselected unusual names and bytes survive archival');
    my @entries = map { [split(/\t/x, $_)] } split(/\n/x, read_file("$target/entries"));
    is_deeply([map { $_->[4] } @entries], [qw(run-alias syslog)], 'entry roster retains selected paths');
    is_deeply([map { $_->[3] } @entries], [(sha256_hex($original)) x 2], 'both paths bind resolved executable bytes');
    is($entries[0][2], sha256_hex("run-alias 'two words'"), 'entry roster binds the exact raw invocation');
    my $manifest = read_file("$target/manifest");
    is(sha256_hex($manifest), $export->{snapshot}, 'snapshot identity covers the worker manifest');
    like($manifest, qr/^package-mode\tverify$/mx, 'ordinary export verifies packages without requesting updates');
    my $plan_bytes = read_file($plan->{path});
    is(read_file("$target/package.plan"), $plan_bytes, 'exact canonical plan accompanies execution');
    my @packages = grep { /\Apackage\t/x } split(/(?<=\n)/x, $plan_bytes);
    my $archives = "$tmp/export-reference-archives";
    mkdir($archives, oct('0700')) or croak $!;
    xCAT::FreeBSDPackagePlan::stage_archives($plan_bytes, $installroot, $archives);
    my $request = "format\txcat-freebsd-local-manifests-1\nplan\t$plan->{digest}\n";
    for my $line (@packages) {
        chomp($line);
        my @fields = split(/\t/x, $line);
        my $expected = command('/usr/bin/tar', '-xOf', "$archives/$fields[1].pkg", '+MANIFEST');
        $request .= join("\t", $line, length($expected), sha256_hex($expected)) . "\n";
        ok(!-e "$target/archives/$fields[1].pkg", "$fields[1] export contains no package payload");
        next unless ok(-f "$target/archives/$fields[1].manifest", "$fields[1] full manifest is delivered");
        is(read_file("$target/archives/$fields[1].manifest"), $expected, "$fields[1] full native metadata is preserved");
        is((stat("$target/archives/$fields[1].manifest"))[2] & oct('7777'), oct('0400'), "$fields[1] manifest is private");
    }
    is(read_file("$target/request"), $request, 'native request binds the complete canonical roster and full manifest digests');
    is((stat("$target/archives"))[2] & oct('7777'), oct('0500'), 'archive directory is sealed');
    my $archive = read_file($export->{archive}{path});
    rename("$directory/$prepared->{id}", "$directory/preparation-retained") or croak $!;
    rename("$directory/$prepared->{source_id}", "$directory/source-retained") or croak $!;
    rename($plan->{path}, "$plan->{path}.retained") or croak $!;
    {
        local *xCAT::Table::new = gensym();
        *xCAT::Table::new = sub { croak 'Export retry queried current tables'; };
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub { croak 'Export retry launched a command'; };
        is_deeply(xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %options), $export,
            'retry needs no preparation, source, published plan, tables or command');
        is_deeply(xCAT::FreeBSDPostscript::read_export($options{run}, directory => $directory), $export,
            'independent readback returns the same retained archive');
    }
    for my $change ([entry_timeout => 301], [generation => '4' x 32], [package_mode => 'update']) {
        my %changed = (%options, @$change);
        my $value = eval { xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %changed); };
        ok(!$value && $@, 'same run cannot replace a binding');
        is(read_file($export->{archive}{path}), $archive, 'conflict leaves the retained archive unchanged');
    }
    write_file($export->{archive}{path}, $archive . 'corrupt');
    my $corrupt = eval { xCAT::FreeBSDPostscript::read_export($options{run}, directory => $directory); };
    ok(!$corrupt && $@, 'altered retained archive is rejected');
    write_file($export->{archive}{path}, $archive);
    my $extra = "$directory/export-$options{run}/extra";
    write_file($extra, 'unexpected');
    my $unexpected = eval { xCAT::FreeBSDPostscript::read_export($options{run}, directory => $directory); };
    ok(!$unexpected && $@, 'unexpected export member is rejected');
    unlink($extra) or croak $!;
    rename("$directory/preparation-retained", "$directory/$prepared->{id}") or croak $!;
    rename("$directory/source-retained", "$directory/$prepared->{source_id}") or croak $!;
    rename("$plan->{path}.retained", $plan->{path}) or croak $!;
    write_file("$source_root/syslog", $original);
    done_testing();
};

subtest 'boot exports bind one boot and preserve current package verification' => sub {
    my $directory = store();
    local %xCAT::Table::rows = %{dclone(\%xCAT::Table::rows)};
    local $::XCATSITEVALS{runbootscripts} = 'yes';
    $xCAT::Table::rows{postscripts} = [{node => 'xcatdefaults', postscripts => 'syslog', postbootscripts => 'syslog'}];
    $xCAT::Table::rows{osimage}[0]{postscripts} = '';
    $xCAT::Table::rows{osimage}[0]{postbootscripts} = '';
    my $paired = xCAT::FreeBSDPostscript::prepare_boot('node1', $plan->{path}, directory => $directory);
    my %options = (directory => $directory, generation => '2' x 32, attempt => '3' x 32, boot => '4' x 64);
    for my $kind (qw(firstboot repeat)) {
        my $identity = ($kind eq 'firstboot' ? '6' : '7') x 32;
        my $export = eval { xCAT::FreeBSDPostscript::export_execution($paired->{$kind}, %options, run => $identity); };
        ok($export, "$kind exports a boot-bound selection");
        if (!$export) { diag($@); return; }
        is($export->{binding}{boot}, $options{boot}, 'export readback retains the boot identity');
        my $target = "$tmp/boot-$kind";
        mkdir($target, oct('0700')) or croak $!;
        command('/bin/tar', '-xpf', $export->{archive}{path}, '-C', $target);
        my $manifest = read_file("$target/manifest");
        like($manifest, qr/^format\txcat-freebsd-postscript-bundle-3$/mx, 'boot binding selects the versioned native contract');
        like($manifest, qr/^boot\t\Q$options{boot}\E$/mx, 'native manifest binds the same boot');
        is(read_file("$target/package.plan"), read_file($plan->{path}), 'frozen installation plan remains as provenance');
        my $request = read_file("$target/request");
        if ($kind eq 'firstboot') {
            like($request, qr/\Aformat\txcat-freebsd-local-manifests-1\nplan\t\Q$plan->{digest}\E\n/x,
                'first boot requests full native metadata verification');
            my @rows = grep { /\Apackage\t/x } split(/\n/x, $request);
            is(join('', map { my @fields = split(/\t/x, $_); join("\t", @fields[0 .. 11]) . "\n" } @rows),
                join('', grep { /\Apackage\t/x } split(/(?<=\n)/x, read_file($plan->{path}))),
                'first boot retains every original package provenance field');
        } else {
            is($request, "format\txcat-freebsd-local-request-1\nplan\t$plan->{digest}\n",
                'repeat boot verifies the current managed identities');
        }
        my @archives = glob("$target/archives/*");
        is(scalar(@archives), $kind eq 'firstboot' ? 5 : 0, "$kind delivers only the required manifests");
        is(scalar(grep { !/[.]manifest\z/x } @archives), 0, 'verification delivers no package payload');
        is((stat("$target/archives"))[2] & oct('7777'), oct('0500'), 'package payload is sealed even when empty');
        is_deeply(xCAT::FreeBSDPostscript::export_execution($paired->{$kind}, %options, run => $identity),
            $export, 'same-boot retry reuses the exact export');
        my %changed = (%options, boot => '5' x 64, run => $identity);
        my $conflict = eval { xCAT::FreeBSDPostscript::export_execution($paired->{$kind}, %changed); };
        ok(!$conflict && $@, 'another boot cannot reuse the retained run identity');
        is_deeply(xCAT::FreeBSDPostscript::read_export($identity, directory => $directory), $export,
            'boot conflict preserves the accepted export');
    }
    my $update = prepare($directory, {kind => 'update', raw => 'syslog'});
    my $wrong_kind = eval { xCAT::FreeBSDPostscript::export_execution($update->{id}, %options, run => '8' x 32); };
    ok(!$wrong_kind && $@, 'an explicit update cannot claim an automatic boot binding');
    for my $boot (undef, '', 'a' x 63, 'A' x 64, []) {
        my %invalid = (%options, run => '9' x 32, boot => $boot);
        my $result = eval { xCAT::FreeBSDPostscript::export_execution($paired->{repeat}, %invalid); };
        ok(!$result && $@, 'invalid boot identity cannot publish a bundle');
        ok(!-e "$directory/export-$invalid{run}", 'invalid boot identity leaves no export');
    }
    done_testing();
};

subtest 'export admission, serialization and failed archive retry' => sub {
    my $directory = store();
    my $prepared = prepare($directory, { kind => 'update', raw => 'syslog' });
    my %options = (directory => $directory, run => '5' x 32, generation => '2' x 32, attempt => '3' x 32);
    for my $change ([run => '../escape'], [generation => 'short'], [entry_timeout => 0], [run_timeout => 7201],
        [log_limit => 4097], [package_mode => 'install'], [unknown => 1]) {
        my %changed = (%options, @$change);
        my $result = eval { xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %changed); };
        ok(!$result && $@, 'malformed export option is rejected');
    }
    my $first = prepare($directory, { kind => 'firstboot' });
    my $updated = eval { xCAT::FreeBSDPostscript::export_execution($first->{id}, %options, package_mode => 'update'); };
    ok(!$updated && $@, 'first boot cannot request installed package updates');
    open(my $lock, '>', "$directory/export-$options{run}.lock") or croak $!;
    chmod(oct('0600'), "$directory/export-$options{run}.lock") == 1 or croak $!;
    flock($lock, LOCK_EX | LOCK_NB) or croak $!;
    my $busy = eval { xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %options); };
    ok(!$busy && $@, 'held run lock prevents a competing exporter');
    close($lock) or croak $!;
    {
        local *xCAT::FreeBSDPkg::run_command = gensym();
        *xCAT::FreeBSDPkg::run_command = sub { return { exitcode => 1, signal => 0, stdout => '', stderr => 'Injected tar failure' }; };
        my $failed = eval { xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %options); };
        ok(!$failed && $@, 'failed archiver returns no export');
        ok(!-e "$directory/export-$options{run}", 'failed archive is not published');
    }
    my $retried = xCAT::FreeBSDPostscript::export_execution($prepared->{id}, %options, package_mode => 'update');
    is($retried->{binding}{package_mode}, 'update', 'retry after unpublished failure can bind an explicit update');
    is_deeply(xCAT::FreeBSDPostscript::read_export($options{run}, directory => $directory), $retried,
        'completed retry has full archive readback');
    done_testing();
};

subtest 'reject frozen input changes after compilation' => sub {
    my $directory = store();
    my $prepared = prepare($directory, { kind => 'update', raw => 'syslog' });
    my $compile = \&xCAT::FreeBSDPostscript::compile_execution;
    my $number = 6;
    for my $case ([preparation => "$directory/$prepared->{id}/manifest.json"],
        [source => "$directory/$prepared->{source_id}/manifest.json"], [context => "$directory/$prepared->{id}/context.json"]) {
        my ($label, $path) = @$case;
        my $before = read_file($path);
        my $run = sprintf('%032x', $number++);
        my ($result, $error);
        {
            local *xCAT::FreeBSDPostscript::compile_execution = gensym();
            *xCAT::FreeBSDPostscript::compile_execution = sub {
                my $compiled = $compile->(@_);
                write_file($path, $before . "\n");
                return $compiled;
            };
            $result = eval { xCAT::FreeBSDPostscript::export_execution($prepared->{id}, directory => $directory,
                run => $run, generation => '2' x 32, attempt => '3' x 32); };
            $error = $@;
        }
        write_file($path, $before);
        ok(!$result && $error, "changed $label after compilation prevents export");
        ok(!-e "$directory/export-$run", "changed $label publishes no archive");
    }
    done_testing();
};

ok(!-e "$tmp/package-script-executed" && !-e "$tmp/script-executed", 'neither package scripts nor source scripts executed');
ok(!-e '/var/db/pkg', 'default package database remains absent');
done_testing();
