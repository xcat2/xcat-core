package xCAT::FreeBSDRepo;

use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK S_ISREG);
use JSON;

my %LIMITS = (max_entries => 100000, max_bytes => 1099511627776,
    max_file_bytes => 17179869184);
my $BASE = 'usr/freebsd-packages/offline';
my $ABI = 'FreeBSD:15:amd64';

sub _fail { die "$_[0]\n"; }

sub _directory {
    my $path = shift;
    _fail("Missing or symlinked repository directory: $path")
      if !lstat($path) || !(-d _) || -l _;
    return;
}

sub _root {
    my $root = shift;
    _fail('An absolute repository directory is required') if !defined($root)
      || ref($root) || $root !~ m{\A/[^\x00\r\n]+\z}x;
    $root =~ s{/+\z}{}x;
    _fail('Repository directory must not contain dot components')
      if grep { $_ eq '.' || $_ eq '..' } split(m{/}x, $root);
    _directory($root);
    $root = abs_path($root);
    _fail('The repository root cannot be /') if !defined($root) || $root eq '/';
    return $root;
}

sub _component {
    my $name = shift;
    return defined($name) && length($name) <= 255
      && $name =~ /\A[A-Za-z0-9_.,+:~\@%=-]+\z/x && $name ne '.' && $name ne '..';
}

sub _file_bytes {
    my ($fh, $path, $limit, $contents) = @_;
    my $sha = Digest::SHA->new(256);
    my ($size, $data) = (0, '');
    while (1) {
        my $bytes = read($fh, my $buffer, 1048576);
        _fail("Cannot read repository file $path: $!") unless defined($bytes);
        last unless $bytes;
        $size += $bytes;
        _fail("Repository file exceeds $limit bytes: $path") if $size > $limit;
        $sha->add($buffer);
        $data .= $buffer if $contents;
    }
    return ({ size => $size, sha256 => $sha->hexdigest }, $data);
}

sub _file {
    my ($path, $limit, $contents) = @_;
    my @before = lstat($path);
    _fail("Missing or non-regular repository file: $path")
      if !@before || !(-f _) || -l _;
    _fail("Repository file exceeds $limit bytes: $path") if $before[7] > $limit;
    sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      or _fail("Cannot open repository file $path: $!");
    binmode($fh) or _fail("Cannot read repository bytes $path: $!");
    my @opened = stat($fh);
    _fail("Repository file changed while opening: $path") unless @opened
      && S_ISREG($opened[2]) && $opened[0] == $before[0] && $opened[1] == $before[1];
    my ($identity, $data) = _file_bytes($fh, $path, $limit, $contents);
    my @after = stat($fh);
    close($fh) or _fail("Cannot close repository file $path: $!");
    my @named = lstat($path);
    for my $state (\@opened, \@after, \@named) {
        _fail("Repository file changed during inspection: $path") if !@$state
          || !S_ISREG($state->[2]) || $state->[7] != $identity->{size}
          || grep { $state->[$_] != $before[$_] } (0, 1, 7, 9, 10);
    }
    return ($identity, $data);
}

sub _link_target {
    my ($path, $target) = @_;
    _fail("Invalid repository link target: $path") if !defined($target)
      || !length($target) || length($target) > 4096 || $target =~ m{\A/}x;
    for my $part (split(m{/}x, $target, -1)) {
        next if $part eq '' || $part eq '.' || $part eq '..';
        _fail("Invalid repository link target: $path") unless _component($part);
    }
    return $target;
}

sub _resolve_link {
    my ($path, $entries) = @_;
    my @pending = split(m{/}x, $path);
    my @resolved;
    my $hops = 0;
    while (@pending) {
        my $part = shift @pending;
        next if $part eq '' || $part eq '.';
        if ($part eq '..') {
            _fail("Repository link escapes its root: $path") unless @resolved;
            pop @resolved;
            next;
        }
        push @resolved, $part;
        my $name = join('/', @resolved);
        my $entry = $entries->{$name};
        return unless $entry;
        if ($entry->{type} eq 'link') {
            _fail("Cyclic or excessive repository links: $path")
              if ++$hops > 64;
            pop @resolved;
            @pending = (split(m{/}x, _link_target($name, $entry->{target}), -1), @pending);
        } elsif (@pending && $entry->{type} ne 'directory') {
            _fail("Repository link traverses a non-directory: $path");
        }
    }
    return join('/', @resolved);
}

sub _directory_names {
    my ($directory, $count, $limit) = @_;
    opendir(my $dh, $directory) or _fail("Cannot read repository directory $directory: $!");
    my @names;
    while (1) {
        local $! = 0;
        my $name = readdir($dh);
        _fail("Cannot read repository directory $directory: $!") if !defined($name) && $!;
        last unless defined($name);
        next if $name eq '.' || $name eq '..';
        _fail('Repository exceeds its entry limit') if ++$$count > $limit;
        push @names, $name;
    }
    closedir($dh) or _fail("Cannot close repository directory $directory: $!");
    @names = sort @names;
    return @names;
}

sub _entry {
    my ($path, $absolute, $limit) = @_;
    _fail("Cannot inspect repository entry $absolute: $!") unless lstat($absolute);
    if (-l _) {
        my $target = _link_target($path, readlink($absolute));
        return { type => 'link', target => $target };
    }
    return { type => 'directory' } if -d _;
    _fail("Unsupported repository special file: $path") unless -f _;
    my ($file) = _file($absolute, $limit, 0);
    return { type => 'file', %$file };
}

sub _snapshot {
    my ($root, $limits, $permitted_dangling) = @_;
    my (%entries, @directories);
    my ($count, $total) = (0, 0);
    my @pending = ('');
    while (@pending) {
        my $relative = pop @pending;
        my $directory = length($relative) ? "$root/$relative" : $root;
        _directory($directory);
        my @state = lstat($directory);
        push @directories, [$directory, \@state];
        for my $name (_directory_names($directory, \$count, $limits->{max_entries})) {
            _fail("Invalid repository entry name: $directory/$name") unless _component($name);
            my $path = length($relative) ? "$relative/$name" : $name;
            _fail("Repository path is too long or deep: $path")
              if length($path) > 4096 || scalar(split(m{/}x, $path)) > 64;
            my $absolute = "$root/$path";
            my $remaining = $limits->{max_bytes} - $total;
            my $limit = $remaining < $limits->{max_file_bytes} ? $remaining : $limits->{max_file_bytes};
            my $entry = _entry($path, $absolute, $limit);
            $entries{$path} = $entry;
            push @pending, $path if $entry->{type} eq 'directory';
            $total += $entry->{size} if $entry->{type} eq 'file';
        }
    }
    my %unresolved;
    for my $path (sort keys %entries) {
        next unless $entries{$path}{type} eq 'link';
        my $resolved = _resolve_link($path, \%entries);
        if (!defined($resolved)) {
            _fail("Dangling repository link: $path") unless
              exists($permitted_dangling->{$path})
              && $entries{$path}{target} eq $permitted_dangling->{$path};
            $unresolved{$path} = $entries{$path}{target};
        }
    }
    for my $directory_state (@directories) {
        my ($directory_path, $before) = @$directory_state;
        _directory($directory_path);
        my @after = lstat($directory_path);
        _fail("Repository directory changed during inspection: $directory_path")
          if grep { $after[$_] != $before->[$_] } (0, 1, 9, 10);
    }
    my $snapshot = { format => 'xcat-freebsd-repo-tree-1', entries => \%entries,
        bytes => $total, unresolved_links => \%unresolved, native_validated => 0 };
    return { %$snapshot, digest => sha256_hex(JSON->new->canonical->encode($snapshot)) };
}

sub snapshot_tree {
    my ($root, %options) = @_;
    _fail('Unknown repository snapshot option') if grep { !exists($LIMITS{$_}) } keys %options;
    my %limits = (%LIMITS, %options);
    for my $key (keys %limits) {
        _fail("Invalid repository limit: $key") if !defined($limits{$key})
          || ref($limits{$key}) || $limits{$key} !~ /\A[1-9][0-9]*\z/x
          || $limits{$key} > $LIMITS{$key};
    }
    return _snapshot(_root($root), \%limits, {});
}

sub _release_repository {
    my ($root, $prefix, $dangling) = @_;
    my $snapshot = _snapshot(_root($root), \%LIMITS, $dangling);
    for my $name (qw(meta meta.conf data.pkg packagesite.pkg)) {
        my $path = length($prefix) ? "$prefix/$name" : $name;
        my $entry = $snapshot->{entries}{$path};
        _fail("Missing release repository metadata: $path")
          unless $entry && $entry->{type} eq 'file' && $entry->{size};
    }
    return $snapshot;
}

sub inspect_release_tree {
    my $root = _root(shift);
    return unless -e "$root/bin/freebsd-version" || -l "$root/bin/freebsd-version";
    _directory("$root/bin");
    my ($version_file, $version) = _file("$root/bin/freebsd-version", 1048576, 1);
    my @versions = $version =~ /^USERLAND_VERSION="([^"\r\n]+)"$/mgx;
    _fail('Only FreeBSD 15.1-RELEASE media is supported')
      unless @versions == 1 && $versions[0] eq '15.1-RELEASE';
    my ($shell_file, $shell) = _file("$root/bin/sh", 16777216, 1);
    _fail('Release media must contain a FreeBSD amd64 shell')
      if length($shell) < 20 || substr($shell, 0, 8) ne "\x7fELF\x02\x01\x01\x09"
      || unpack('v', substr($shell, 18, 2)) != 62;
    _directory("$root/usr");
    _directory("$root/usr/freebsd-packages");
    my %repositories = (base => { path => $BASE, catalogue_prefix => '',
        tree => _release_repository("$root/$BASE", '', {}) });
    if (-e "$root/packages" || -l "$root/packages") {
        _directory("$root/packages");
        _directory("$root/packages/$ABI");
        $repositories{applications} = { path => 'packages', catalogue_prefix => $ABI,
            tree => _release_repository("$root/packages", $ABI,
                { "$ABI/Latest/pkg.pkg" => '../All/pkg-2.6.2_1.pkg' }) };
    }
    my $media = { format => 'xcat-freebsd-release-tree-1', release => $versions[0],
        arch => 'x86_64', media_arch => 'amd64', abi => $ABI, osversion => 1501000,
        distname => 'freebsd15.1', native_validated => 0,
        identity_files => { 'bin/freebsd-version' => $version_file, 'bin/sh' => $shell_file },
        repositories => \%repositories };
    return { %$media, digest => sha256_hex(JSON->new->canonical->encode($media)) };
}

1;
