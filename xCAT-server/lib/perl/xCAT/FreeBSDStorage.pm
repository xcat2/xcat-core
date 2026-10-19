package xCAT::FreeBSDStorage;

use strict;
use warnings;
use Carp qw(croak);
use File::Temp qw(tempfile);
use MIME::Base64 qw(encode_base64);
use xCAT::FreeBSDKey;
use xCAT::FreeBSDPkg;

sub _fail { die "FreeBSD storage policy: $_[0]\n"; }

sub sections {
    my $text = shift;
    _fail('Invalid partitionfile contents') if !defined($text) || ref($text) || length($text) > 65536;
    _fail('Configuration contains control characters') if $text =~ /[^\x09\x0a\x20-\x7e]/x;
    my ($os, $section, $seen_os) = ('', undef, 0);
    my (%pools, %datasets);
    my $kind = 'data pool';
    for my $line (split(/\n/x, $text)) {
        if ($line eq '[os]') {
            _fail('The OS section must precede data pools and occur once')
              if $seen_os++ || length($os) || keys(%pools) || keys(%datasets);
            next;
        }
        if ($line =~ /\A\[pool[ ]([a-z][a-z0-9_-]{0,62})\]\z/x) {
            my $name = $1;
            _fail('Duplicate data pool section') if exists($pools{$name});
            $pools{$name} = {};
            $section = $pools{$name};
            $kind = 'data pool';
            next;
        }
        if ($line =~ /\A\[dataset[ ]([A-Za-z0-9_.\/-]+)\]\z/x) {
            my $name = $1;
            _fail('Duplicate dataset section') if exists($datasets{$name});
            $datasets{$name} = {};
            $section = $datasets{$name};
            $kind = 'dataset';
            next;
        }
        next if $line =~ /\A\s*(?:[#].*)?\z/x;
        if (!defined($section)) {
            $os .= "$line\n";
            next;
        }
        my ($key, $value) = $line =~ /\A([a-z_]+)=([^\x09]*)\z/x;
        _fail("Expected a $kind key=value setting") unless defined($key);
        _fail("Duplicate $kind setting") if exists($section->{$key});
        $section->{$key} = $value;
    }
    _fail('An OS disk policy is required') unless length($os);
    return ($os, \%pools, \%datasets);
}

sub _plan {
    my ($policy, $planner, $automatic) = @_;
    my ($file, $path) = tempfile('xcat-data-policy-XXXXXXXX', TMPDIR => 1, UNLINK => 1);
    print {$file} $policy or _fail('Cannot stage data pool policy');
    close($file) or _fail('Cannot close staged data pool policy');
    my $result = xCAT::FreeBSDPkg::run_command(['/usr/bin/awk',
        ($automatic ? ('-v', 'mode=compile-auto') : ()), '-f', $planner, $path],
        environment => { LC_ALL => 'C' }, timeout => 15, stdout_limit => 131072, stderr_limit => 4096);
    _fail($result->{stderr} || 'Storage planner failed') if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub _compile_pool {
    my ($values, $planner) = @_;
    my $plan = _plan(join('', map { "$_=$values->{$_}\n" } sort keys %$values), $planner,
        $values->{os_disks} eq 'auto');
    _fail('Data pool planner returned no policy') unless $plan =~ /\AK\tformat\txcat-freebsd-data-1\n/x;
    my @members;
    for my $line (split(/\n/x, $plan)) {
        my ($kind, $key, $value, $serial) = split(/\t/x, $line);
        $values->{$key} = $value if $kind eq 'K';
        push @members, "$value\@$serial" if $kind eq 'D' && $key ne 'os';
    }
    return (join('', map { "$_=$values->{$_}\n" } sort keys %$values), \@members);
}

sub _os_members {
    my $os = shift;
    return ['auto'] if ($os->{disk_selection} || '') eq 'empty';
    my @os = exists($os->{zfs_vdevs}) ? split(/[,;]/x, $os->{zfs_vdevs})
      : (($os->{target_disk} || '') . '@' . ($os->{target_disk_ident} || ''));
    for my $role (qw(log cache special)) {
        my $value = $os->{"zfs_${role}_vdevs"} || '-';
        push @os, split(/[,;]/x, $value) if $value ne '-';
    }
    for my $identity (@os) {
        _fail('OS disk identities are required before declaring data pools') unless $identity =~ /\A[^@]+@[^@]+\z/x;
    }
    return \@os;
}

sub _pool {
    my ($node, $name, $settings, $os_members, $planner) = @_;
    xCAT::FreeBSDKey::identity($node, $name);
    my %allowed = map { $_ => 1 } qw(action guid topology vdevs log_vdevs cache_vdevs
        special_vdevs compression ashift special_small_blocks encryption key_source mountpoint);
    my %values = %$settings;
    _fail('Unsupported data pool setting') if grep { !$allowed{$_} } keys %values;
    my $key_source = delete $values{key_source};
    if (($values{encryption} || 'off') eq 'aes-256-gcm') {
        _fail('Encrypted pools require key_source=passwd') unless defined($key_source) && $key_source eq 'passwd';
        $values{keyfile} = "/etc/xcat/keys/$name.key";
    } else {
        _fail('A key source requires encrypted data') if defined($key_source);
    }
    @values{qw(format pool os_disks)} = ('xcat-freebsd-data-1', $name, join(',', @$os_members));
    my ($policy, $members) = _compile_pool(\%values, $planner);
    return ({ name => $name, policy => $policy,
        defined($key_source) ? (key_source => $key_source) : () }, $members, $values{mountpoint});
}

sub compile {
    my ($node, $os, $sections, $planner) = @_;
    return unless keys %$sections;
    _fail('A shared data pool planner is required') if !defined($planner) || ref($planner)
      || $planner !~ m{\A/}x || !-f $planner || -l $planner;
    my $os_members = _os_members($os);
    my (%devices, %serials, %mountpoints, %preserved);
    for my $os_member (@$os_members) {
        next if $os_member eq 'auto';
        my ($device, $serial) = split(/@/x, $os_member);
        $devices{$device} = $serials{$serial} = 1;
    }
    my @pools;
    for my $name (sort keys %$sections) {
        my ($pool, $members, $mountpoint) = _pool($node, $name, $sections->{$name}, $os_members, $planner);
        _fail('Data pools require distinct mountpoints') if $mountpoints{$mountpoint}++;
        for my $data_member (@$members) {
            my ($device, $serial) = split(/@/x, $data_member);
            _fail('OS and data pools must use distinct device names and serials') if $devices{$device}++ || $serials{$serial}++;
            $preserved{$data_member} = 1;
        }
        push @pools, $pool;
    }
    if (exists($os->{zfs_vdevs}) || ($os->{disk_selection} || '') eq 'empty') {
        for my $member (split(/,/x, $os->{preserve_disks} || '-')) {
            $preserved{$member} = 1 if $member ne '-';
        }
        $os->{preserve_disks} = join(',', sort keys %preserved);
    }
    return { pools => \@pools };
}

sub datasets {
    my ($os, $storage, $sections, $planner) = @_;
    my %pools = $storage ? map { $_->{name} => $_ } @{$storage->{pools}} : ();
    my %grouped;
    for my $name (sort keys %$sections) {
        my ($pool) = split(m{/}x, $name);
        _fail('A dataset requires its declared pool') unless $pool eq 'zroot' || exists($pools{$pool});
        $grouped{$pool} .= "[dataset $name]\n" . join('',
            map { "$_=$sections->{$name}{$_}\n" } sort keys %{$sections->{$name}});
    }
    for my $pool (sort keys %grouped) {
        my ($kind, $mountpoint) = ('os', '/');
        if ($pool eq 'zroot') {
            _fail('OS datasets require an explicit ZFS disk policy') unless
                ($os->{filesystem} || '') eq 'zfs' && exists($os->{zfs_vdevs});
        } else {
            $kind = 'data';
            ($mountpoint) = $pools{$pool}{policy} =~ /^mountpoint=(.*)$/mx;
        }
        my $policy = "format=xcat-freebsd-datasets-1\nkind=$kind\npool=$pool\nmountpoint=$mountpoint\n$grouped{$pool}";
        _fail('Dataset planner returned no plan') unless length(_plan($policy, $planner));
        if ($kind eq 'os') {
            $os->{zfs_datasets_base64} = encode_base64($policy, '');
        } else {
            $pools{$pool}{datasets} = $policy;
        }
    }
    return;
}

sub files {
    my ($node, $storage) = @_;
    _fail('Invalid compiled storage policy') unless ref($storage) eq 'HASH'
      && ref($storage->{pools}) eq 'ARRAY' && @{$storage->{pools}};
    my (%files, @names);
    my $table;
    my $ok = eval {
        for my $pool (@{$storage->{pools}}) {
            my $name = $pool->{name};
            xCAT::FreeBSDKey::identity($node, $name);
            _fail('Duplicate compiled data pool') if exists($files{"$name.conf"});
            _fail('Invalid compiled data policy') if !defined($pool->{policy}) || ref($pool->{policy})
              || length($pool->{policy}) > 32768 || $pool->{policy} !~ /^pool=\Q$name\E$/mx;
            $files{"$name.conf"} = $pool->{policy};
            $files{"$name.datasets"} = $pool->{datasets} if exists($pool->{datasets});
            push @names, $name;
            if (exists($pool->{key_source})) {
                _fail('Unsupported compiled key source') unless $pool->{key_source} eq 'passwd';
                unless ($table) {
                    require xCAT::Table;
                    $table = xCAT::Table->new('passwd', -create => 0);
                    _fail('Cannot open the credential table') unless $table;
                }
                $files{"$name.key"} = xCAT::FreeBSDKey::lookup($table, $node, $name);
            }
        }
        1;
    };
    my $error = $@;
    $table->close() if $table;
    croak $error unless $ok;
    $files{pools} = join('', map { "$_\n" } @names);
    return \%files;
}

1;
