package xCAT::FreeBSDRepoImport;

use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(O_RDONLY O_WRONLY O_RDWR O_CREAT O_EXCL O_NOFOLLOW O_NONBLOCK
    LOCK_EX LOCK_NB S_ISDIR S_ISREG);
use File::Path qw(remove_tree);
use File::Temp qw(tempdir);
use JSON;
use xCAT::FreeBSDRepo;

sub _fail { die "$_[0]\n"; }
sub _json { return JSON->new->utf8->canonical->encode(shift); }

sub _absolute {
    my $path = shift;
    _fail('An absolute import directory is required') if !defined($path) || ref($path)
      || $path !~ m{\A/[^\x00\r\n]+\z}x;
    _fail('Import paths must not contain dot components')
      if grep { $_ eq '.' || $_ eq '..' } split(m{/}x, $path);
    $path =~ s{/+}{/}gx;
    $path =~ s{/\z}{}x;
    _fail('The import directory cannot be /') unless length($path);
    return $path;
}

sub _source {
    my $path = _absolute(shift);
    _fail("Missing or symlinked import source: $path")
      if !lstat($path) || !(-d _) || -l _;
    return abs_path($path);
}

sub _controlled_directory {
    my ($path, $ancestor) = @_;
    my @state = lstat($path);
    _fail("Missing or symlinked publication directory: $path")
      unless @state && S_ISDIR($state[2]);
    _fail("Untrusted publication directory owner: $path")
      unless $state[4] == $> || ($ancestor && $state[4] == 0);
    _fail("Writable publication directory: $path")
      if ($state[2] & oct('0022')) && !($ancestor && ($state[2] & oct('1000')));
    return \@state;
}

sub _installroot {
    my $root = _absolute(shift);
    my $path = '';
    my @parts = grep { length($_) } split(m{/}x, $root);
    for my $part (@parts) {
        $path .= "/$part";
        _controlled_directory($path, $path ne $root);
    }
    return $root;
}

sub _parent {
    my $root = _installroot(shift);
    my $path = $root;
    for my $part (qw(freebsd15.1 x86_64 repositories)) {
        $path .= "/$part";
        if (!lstat($path)) {
            mkdir($path, oct('0755')) or _fail("Cannot create publication directory $path: $!");
            chmod(oct('0755'), $path) or _fail("Cannot set publication directory permissions: $!");
        }
        _controlled_directory($path, 0);
    }
    return $path;
}

sub _lock {
    my $parent = shift;
    my $path = "$parent/.repository-import.lock";
    sysopen(my $fh, $path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
      or _fail("Cannot open repository import lock: $!");
    my @state = stat($fh);
    _fail('Unsafe repository import lock') unless @state && S_ISREG($state[2])
      && $state[3] == 1 && $state[4] == $> && ($state[2] & oct('7777')) == oct('0600')
      && $state[7] == 0;
    flock($fh, LOCK_EX | LOCK_NB) or _fail("Repository import is busy or cannot be locked: $!");
    my @named = lstat($path);
    _fail('Repository import lock changed') unless @named
      && $named[0] == $state[0] && $named[1] == $state[1] && $named[3] == 1;
    return $fh;
}

sub _tree {
    my $entries = shift;
    my $bytes = 0;
    $bytes += $_->{size} for grep { $_->{type} eq 'file' } values %$entries;
    my $tree = { format => 'xcat-freebsd-repo-tree-1', entries => $entries,
        bytes => $bytes, unresolved_links => {}, native_validated => 0 };
    return { %$tree, digest => sha256_hex(_json($tree)) };
}

sub _derived {
    my ($repository, $repairs) = @_;
    my %entries = map { $_ => { %{$repository->{tree}{entries}{$_}} } }
      keys %{$repository->{tree}{entries}};
    my %unresolved = %{$repository->{tree}{unresolved_links}};
    for my $repair (@$repairs) {
        my $entry = $entries{$repair->{path}};
        my $archive = $entries{$repair->{archive}};
        _fail('Inconsistent validated repository link repair') unless $entry
          && $entry->{type} eq 'link' && $entry->{target} eq $repair->{from}
          && exists($unresolved{$repair->{path}}) && $archive && $archive->{type} eq 'file'
          && $archive->{sha256} eq $repair->{sha256};
        $entry->{target} = $repair->{to};
        delete($unresolved{$repair->{path}});
    }
    _fail('Unresolved repository links remain after repair') if %unresolved;
    return _tree(\%entries);
}

sub _open_source {
    my ($path, $expected) = @_;
    sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      or _fail("Cannot open import source file $path: $!");
    binmode($fh) or _fail("Cannot read import source bytes: $!");
    my @state = stat($fh);
    _fail("Import source file changed: $path") unless @state && S_ISREG($state[2])
      && $state[7] == $expected->{size};
    _fail("Import source file needs a positive timestamp: $path") if $state[9] <= 0;
    return ($fh, \@state);
}

sub _copy_file {
    my ($source, $target, $expected) = @_;
    my ($input, $before) = _open_source($source, $expected);
    sysopen(my $output, $target, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, oct('0600'))
      or _fail("Cannot create staged repository file $target: $!");
    binmode($output) or _fail("Cannot write staged repository bytes: $!");
    my ($size, $sha) = (0, Digest::SHA->new(256));
    while (1) {
        my $remaining = $expected->{size} - $size + 1;
        my $length = $remaining < 1048576 ? $remaining : 1048576;
        my $read = read($input, my $buffer, $length);
        _fail("Cannot read import source file $source: $!") unless defined($read);
        last unless $read;
        $size += $read;
        _fail("Import source file grew: $source") if $size > $expected->{size};
        $sha->add($buffer);
        print {$output} $buffer or _fail("Cannot write staged repository file $target: $!");
    }
    my @after = stat($input);
    close($input) or _fail("Cannot close import source file $source: $!");
    close($output) or _fail("Cannot close staged repository file $target: $!");
    _fail("Import source file changed during copying: $source")
      if $size != $expected->{size} || $sha->hexdigest ne $expected->{sha256}
      || !@after || grep { $after[$_] != $before->[$_] } (0, 1, 7, 9, 10);
    utime($before->[9], $before->[9], $target) == 1
      or _fail("Cannot preserve repository file timestamp: $!");
    chmod(oct('0444'), $target) or _fail("Cannot protect repository file: $!");
    return;
}

sub _copy_tree {
    my ($source, $target, $tree) = @_;
    mkdir($target, oct('0700')) or _fail("Cannot create repository stage: $!");
    my @directories = ($target);
    for my $path (sort keys %{$tree->{entries}}) {
        my $entry = $tree->{entries}{$path};
        my $destination = "$target/$path";
        if ($entry->{type} eq 'directory') {
            mkdir($destination, oct('0700')) or _fail("Cannot stage repository directory $path: $!");
            push @directories, $destination;
        } elsif ($entry->{type} eq 'link') {
            symlink($entry->{target}, $destination) or _fail("Cannot stage repository link $path: $!");
        } else {
            _copy_file("$source/$path", $destination, $entry);
        }
    }
    for my $directory (reverse @directories) {
        chmod(oct('0555'), $directory) or _fail("Cannot protect repository directory: $!");
    }
    return;
}

sub _write_manifest {
    my ($path, $bytes) = @_;
    sysopen(my $fh, $path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, oct('0600'))
      or _fail("Cannot create import manifest: $!");
    binmode($fh) or _fail("Cannot write import manifest bytes: $!");
    print {$fh} $bytes or _fail("Cannot write import manifest: $!");
    close($fh) or _fail("Cannot close import manifest: $!");
    chmod(oct('0444'), $path) or _fail("Cannot protect import manifest: $!");
    return;
}

sub _operational_metadata {
    my ($root, $tree, $root_mode) = @_;
    my @paths = (['', 'directory', $root_mode]);
    push @paths, map { [$_, $tree->{entries}{$_}{type},
        $tree->{entries}{$_}{type} eq 'directory' ? oct('0555') : oct('0444')] }
      sort keys %{$tree->{entries}};
    for my $item (@paths) {
        my ($path, $type, $mode) = @$item;
        my $absolute = length($path) ? "$root/$path" : $root;
        my @state = lstat($absolute);
        _fail("Published repository entry disappeared: $path") unless @state;
        _fail("Published repository entry has a different owner: $path") if $state[4] != $>;
        next if $type eq 'link';
        _fail("Published repository permissions differ: $path")
          if ($state[2] & oct('7777')) != $mode;
        _fail("Published repository file has invalid operational metadata: $path")
          if $type eq 'file' && ($state[3] != 1 || $state[9] <= 0);
    }
    return;
}

sub _verify {
    my ($root, $expected, $mode) = @_;
    my $actual = xCAT::FreeBSDRepo::snapshot_tree($root);
    _fail('Published repository differs from its validated import')
      if _json($actual) ne _json($expected);
    _operational_metadata($root, $expected, $mode);
    return;
}

sub _remove_stage {
    my $path = shift;
    my $errors;
    remove_tree($path, { error => \$errors });
    _fail('Cannot remove repository stage: ' . join('; ', map { join(': ', %$_) } @$errors))
      if $errors && @$errors;
    return;
}

sub _rename {
    my ($source, $target) = @_;
    rename($source, $target) or _fail("Cannot publish repository import: $!");
    return;
}

sub _publication {
    my ($source, $inspection, $kind, $trust) = @_;
    my (%repositories, %sources, %extras);
    if ($kind eq 'repository') {
        $sources{repository} = $source;
        $repositories{repository} = { path => 'repository',
            catalogue_prefix => $inspection->{catalogue_prefix},
            tree => _derived($inspection, []), link_repairs => [] };
        if ($trust->{type} eq 'pubkey') {
            my @state = lstat($trust->{path});
            _fail('Repository trust file is unavailable or oversized')
              if !@state || !S_ISREG($state[2]) || $state[7] > 1048576;
            $extras{'repository.pub'} = { size => $state[7], sha256 => $inspection->{trust}{sha256}, type => 'file' };
        }
    } else {
        for my $name (sort keys %{$inspection->{repositories}}) {
            my $descriptor = $inspection->{repositories}{$name};
            $sources{$name} = "$source/$descriptor->{path}";
            $repositories{$name} = { path => $name,
                catalogue_prefix => $descriptor->{repository}{catalogue_prefix},
                tree => _derived($descriptor->{repository}, $descriptor->{link_repairs}),
                link_repairs => $descriptor->{link_repairs} };
        }
    }
    my $manifest = { format => 'xcat-freebsd-repo-import-1', kind => $kind,
        source => $inspection, repositories => \%repositories, trust_files => \%extras,
        native_validated => 1, selection_validated => 0 };
    $manifest->{digest} = sha256_hex(_json($manifest));
    my $bytes = _json($manifest) . "\n";
    _fail('Repository import manifest is too large') if length($bytes) > 536870912;
    my %entries = (%extras, 'manifest.json' => { type => 'file', size => length($bytes), sha256 => sha256_hex($bytes) });
    for my $name (sort keys %repositories) {
        $entries{$name} = { type => 'directory' };
        my $tree = $repositories{$name}{tree};
        $entries{"$name/$_"} = $tree->{entries}{$_} for keys %{$tree->{entries}};
    }
    my $expected = _tree(\%entries);
    _fail('Repository import exceeds publication limits')
      if keys(%entries) > 100000 || $expected->{bytes} > 1099511627776;
    return ($manifest, $bytes, $expected, \%sources, \%extras);
}

sub _publish {
    my ($source, $installroot, $inspection, $kind, $options) = @_;
    my ($manifest, $bytes, $expected, $sources, $extras) =
      _publication($source, $inspection, $kind, $options->{trust});
    my $parent = "$installroot/freebsd15.1/x86_64/repositories";
    _fail('The publication directory cannot be inside its source')
      if $parent eq $source || index($parent, "$source/") == 0;
    $parent = _parent($installroot);
    my $parent_state = _controlled_directory($parent, 0);
    my $lock = _lock($parent);
    my $destination = "$parent/$manifest->{digest}";
    if (lstat($destination)) {
        _fail("Repository destination already exists: $destination") if $options->{nonoverwrite};
        _verify($destination, $expected, oct('0555'));
        return { %$manifest, path => $destination, reused => 1 };
    }
    my $stage = tempdir('.repository-stage.XXXXXXXX', DIR => $parent, CLEANUP => 0);
    my $ok = eval {
        for my $name (sort keys %{$manifest->{repositories}}) {
            _copy_tree($sources->{$name}, "$stage/$name", $manifest->{repositories}{$name}{tree});
        }
        _copy_file($options->{trust}{path}, "$stage/repository.pub", $extras->{'repository.pub'}) if %$extras;
        _write_manifest("$stage/manifest.json", $bytes);
        _verify($stage, $expected, oct('0700'));
        my $after = $kind eq 'release' ? xCAT::FreeBSDRepo::inspect_release_tree($source)
          : xCAT::FreeBSDRepo::snapshot_tree($source);
        my $before = $kind eq 'release' ? $inspection->{media} : $inspection->{tree};
        _fail('Import source changed during publication') if !$after || $after->{digest} ne $before->{digest};
        my $current_parent = _parent($installroot);
        my $current_state = _controlled_directory($current_parent, 0);
        _fail('Publication parent changed during import') if $current_parent ne $parent
          || $current_state->[0] != $parent_state->[0] || $current_state->[1] != $parent_state->[1];
        _fail('Repository destination appeared during import') if lstat($destination);
        chmod(oct('0555'), $stage) or _fail("Cannot protect repository import: $!");
        _rename($stage, $destination);
        1;
    };
    unless ($ok) {
        my $error = $@ || "Unknown repository import failure\n";
        eval { _remove_stage($stage); 1 } or $error .= $@;
        _fail($error);
    }
    return { %$manifest, path => $destination, reused => 0 };
}

sub _options {
    my @arguments = @_;
    _fail('Repository import options must be pairs') if @arguments % 2;
    my %options;
    while (@arguments) {
        my ($key, $value) = splice(@arguments, 0, 2);
        _fail('Unknown or duplicate repository import option') if !defined($key) || ref($key)
          || $key !~ /\A(?:tool|trust|catalogue_prefix|nonoverwrite)\z/x || exists($options{$key});
        $options{$key} = $value;
    }
    _fail('Invalid repository nonoverwrite policy') if defined($options{nonoverwrite})
      && (ref($options{nonoverwrite}) || $options{nonoverwrite} !~ /\A[01]\z/x);
    return \%options;
}

sub import_repository {
    my ($source, $installroot, @arguments) = @_;
    my $options = _options(@arguments);
    $source = _source($source);
    $installroot = _installroot($installroot);
    my %native = %$options;
    delete($native{nonoverwrite});
    my $inspection = xCAT::FreeBSDRepo::inspect_repository($source, %native);
    return _publish($source, $installroot, $inspection, 'repository', $options);
}

sub import_release {
    my ($source, $installroot, @arguments) = @_;
    my $options = _options(@arguments);
    _fail('Release imports do not accept a catalogue prefix') if exists($options->{catalogue_prefix});
    $source = _source($source);
    $installroot = _installroot($installroot);
    my %native = %$options;
    delete($native{nonoverwrite});
    my $inspection = xCAT::FreeBSDRepo::inspect_release($source, %native);
    _fail('The source is not supported FreeBSD release media') unless $inspection;
    return _publish($source, $installroot, $inspection, 'release', $options);
}

1;
