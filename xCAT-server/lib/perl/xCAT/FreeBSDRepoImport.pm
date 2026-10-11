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
    my ($parent, $name) = @_;
    $name = '.repository-import.lock' unless defined($name);
    my $path = "$parent/$name";
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

sub registration_lock {
    _fail('Repository registration locking requires one directory') unless @_ == 1;
    return _lock(_installroot(shift), '.repository-register.lock');
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

sub _repositories {
    my ($inspection, $kind) = @_;
    my %repositories;
    if ($kind eq 'repository') {
        $repositories{repository} = { path => 'repository',
            catalogue_prefix => $inspection->{catalogue_prefix},
            tree => _derived($inspection, []), link_repairs => [] };
    } else {
        for my $name (sort keys %{$inspection->{repositories}}) {
            my $descriptor = $inspection->{repositories}{$name};
            $repositories{$name} = { path => $name,
                catalogue_prefix => $descriptor->{repository}{catalogue_prefix},
                tree => _derived($descriptor->{repository}, $descriptor->{link_repairs}),
                link_repairs => $descriptor->{link_repairs} };
        }
    }
    return \%repositories;
}

sub _manifest {
    my ($inspection, $kind, $extras) = @_;
    my $repositories = _repositories($inspection, $kind);
    my $manifest = { format => 'xcat-freebsd-repo-import-1', kind => $kind,
        source => $inspection, repositories => $repositories, trust_files => $extras,
        native_validated => 1, selection_validated => 0 };
    $manifest->{digest} = sha256_hex(_json($manifest));
    my $bytes = _json($manifest) . "\n";
    _fail('Repository import manifest is too large') if length($bytes) > 536870912;
    my %entries = (%$extras, 'manifest.json' => { type => 'file', size => length($bytes), sha256 => sha256_hex($bytes) });
    for my $name (sort keys %$repositories) {
        $entries{$name} = { type => 'directory' };
        my $tree = $repositories->{$name}{tree};
        $entries{"$name/$_"} = $tree->{entries}{$_} for keys %{$tree->{entries}};
    }
    my $expected = _tree(\%entries);
    _fail('Repository import exceeds publication limits')
      if keys(%entries) > 100000 || $expected->{bytes} > 1099511627776;
    return ($manifest, $bytes, $expected);
}

sub _publication {
    my ($source, $inspection, $kind, $trust) = @_;
    my (%sources, %extras);
    if ($kind eq 'repository') {
        $sources{repository} = $source;
        if ($trust->{type} eq 'pubkey') {
            my @state = lstat($trust->{path});
            _fail('Repository trust file is unavailable or oversized')
              if !@state || !S_ISREG($state[2]) || $state[7] > 1048576;
            $extras{'repository.pub'} = { size => $state[7], sha256 => $inspection->{trust}{sha256}, type => 'file' };
        }
    } else {
        $sources{$_} = "$source/$inspection->{repositories}{$_}{path}"
          for keys %{$inspection->{repositories}};
    }
    return (_manifest($inspection, $kind, \%extras), \%sources, \%extras);
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

sub _checked_digest {
    my ($value, $format) = @_;
    _fail("Invalid stored $format descriptor") if ref($value) ne 'HASH'
      || !defined($value->{format}) || $value->{format} ne $format
      || !defined($value->{digest}) || ref($value->{digest})
      || $value->{digest} !~ /\A[0-9a-f]{64}\z/x;
    my %content = %$value;
    delete($content{digest});
    _fail("Stored $format digest mismatch") unless sha256_hex(_json(\%content)) eq $value->{digest};
    return;
}

sub _checked_tool {
    my $tool = shift;
    _fail('Invalid stored native tool identity') if ref($tool) ne 'HASH'
      || ($tool->{version} || '') ne '2.8.2' || ($tool->{sha256} || '') !~ /\A[0-9a-f]{64}\z/x
      || grep { $_ ne 'version' && $_ ne 'sha256' && $_ ne 'library_digest' } keys %$tool;
    _fail('Invalid stored native library identity') if exists($tool->{library_digest})
      && ($tool->{library_digest} || '') !~ /\A[0-9a-f]{64}\z/x;
    return;
}

sub _checked_trust {
    my $repository = shift;
    my $trust = $repository->{trust};
    _fail('Invalid stored repository trust') if ref($trust) ne 'HASH';
    my $type = $trust->{type} || '';
    if ($type eq 'pubkey') {
        _fail('Invalid stored repository public key') if ($trust->{sha256} || '') !~ /\A[0-9a-f]{64}\z/x
          || _json($trust) ne _json({ type => $type, sha256 => $trust->{sha256} });
    } else {
        _fail('Invalid stored repository tree trust') if $type ne 'operator-trusted-tree'
          || _json($trust) ne _json({ type => $type, digest => $repository->{tree}{digest} });
    }
    return;
}

sub _checked_native {
    my $repository = shift;
    _checked_digest($repository, 'xcat-freebsd-repository-1');
    _fail('Invalid stored native repository identity') unless ($repository->{abi} || '') eq 'FreeBSD:15:amd64'
      && ($repository->{osversion} || '') eq '1501000'
      && ($repository->{native_validated} || '') eq '1'
      && defined($repository->{selection_validated}) && $repository->{selection_validated} eq '0';
    _checked_digest($repository->{tree}, 'xcat-freebsd-repo-tree-1');
    _fail('Invalid stored repository tree evidence') unless defined($repository->{tree}{native_validated})
      && $repository->{tree}{native_validated} eq '0';
    _checked_tool($repository->{tool});
    _checked_trust($repository);
    xCAT::FreeBSDRepo::validate_repository_inventory($repository);
    return;
}

sub _checked_release_header {
    my $value = shift;
    my %identity = (release => '15.1-RELEASE', arch => 'x86_64', media_arch => 'amd64',
        abi => 'FreeBSD:15:amd64', osversion => '1501000', distname => 'freebsd15.1');
    for my $key (keys %identity) {
        _fail('Invalid stored release identity') if !defined($value->{$key})
          || ref($value->{$key}) || $value->{$key} ne $identity{$key};
    }
    my $repositories = $value->{repositories};
    _fail('Invalid stored release repositories') if ref($repositories) ne 'HASH'
      || !exists($repositories->{base})
      || grep { $_ ne 'base' && $_ ne 'applications' } keys %$repositories;
    return;
}

sub _checked_release_role {
    my ($name, $descriptor, $original) = @_;
    _fail('Invalid stored release repository') if ref($descriptor) ne 'HASH' || ref($original) ne 'HASH';
    my $repository = $descriptor->{repository};
    _checked_native($repository);
    _checked_digest($original->{tree}, 'xcat-freebsd-repo-tree-1');
    my $path = $name eq 'base' ? 'usr/freebsd-packages/offline' : 'packages';
    my $prefix = $name eq 'base' ? '' : 'FreeBSD:15:amd64';
    _fail('Stored release repository provenance differs')
      unless ($descriptor->{path} || '') eq $path && ($original->{path} || '') eq $path
      && defined($original->{catalogue_prefix}) && $original->{catalogue_prefix} eq $prefix
      && defined($repository->{catalogue_prefix}) && $repository->{catalogue_prefix} eq $prefix
      && _json($repository->{tree}) eq _json($original->{tree})
      && _json($repository->{trust}) eq _json({ type => 'operator-trusted-tree', digest => $original->{tree}{digest} });
    my $summary = xCAT::FreeBSDRepo::describe_release_repository($repository, $name);
    _fail('Stored release bootstrap or repair differs')
      unless _json($summary->{bootstrap}) eq _json($descriptor->{bootstrap})
      && _json($summary->{link_repairs}) eq _json($descriptor->{link_repairs});
    return;
}

sub _checked_source {
    my ($source, $kind) = @_;
    if ($kind eq 'repository') {
        _checked_native($source);
        return;
    }
    _fail('Invalid stored import kind') unless $kind eq 'release';
    _checked_digest($source, 'xcat-freebsd-release-1');
    my $media = $source->{media};
    _checked_digest($media, 'xcat-freebsd-release-tree-1');
    _checked_release_header($source);
    _checked_release_header($media);
    _fail('Invalid stored release trust or validation evidence')
      unless ($source->{native_validated} || '') eq '1'
      && defined($source->{selection_validated}) && $source->{selection_validated} eq '0'
      && defined($media->{native_validated}) && $media->{native_validated} eq '0'
      && ref($source->{trust}) eq 'HASH' && ($source->{trust}{type} || '') eq 'operator-trusted-release'
      && ($source->{trust}{digest} || '') eq $media->{digest}
      && _json([sort keys %{$source->{repositories}}]) eq _json([sort keys %{$media->{repositories}}]);
    for my $name (sort keys %{$source->{repositories}}) {
        _checked_release_role($name, $source->{repositories}{$name}, $media->{repositories}{$name});
    }
    return;
}

sub _read_contents {
    my ($fh, $before, $description) = @_;
    my $bytes = '';
    while (length($bytes) <= $before->[7]) {
        my $remaining = $before->[7] - length($bytes) + 1;
        my $length = $remaining < 1048576 ? $remaining : 1048576;
        my $read = read($fh, my $buffer, $length);
        _fail("Cannot read $description: $!") unless defined($read);
        last unless $read;
        $bytes .= $buffer;
    }
    my @after = stat($fh);
    close($fh) or _fail("Cannot close $description: $!");
    _fail("$description changed during reading") if length($bytes) != $before->[7]
      || !@after || grep { $after[$_] != $before->[$_] } (0, 1, 7, 9, 10);
    return $bytes;
}

sub _read_manifest {
    my $path = shift;
    my @state = lstat($path);
    _fail('Missing or oversized repository import manifest') if !@state
      || !S_ISREG($state[2]) || $state[7] > 536870912;
    my ($fh, $before) = _open_source($path, { size => $state[7] });
    my $bytes = _read_contents($fh, $before, 'Repository import manifest');
    my $manifest = eval { JSON->new->utf8->max_depth(64)->decode($bytes) };
    _fail('Invalid repository import manifest JSON') if $@ || ref($manifest) ne 'HASH';
    _checked_digest($manifest, 'xcat-freebsd-repo-import-1');
    _fail('Repository import manifest is not canonical') unless _json($manifest) . "\n" eq $bytes;
    return ($manifest, $bytes);
}

sub _policy_fields {
    my ($value, $description, @allowed) = @_;
    _fail("Invalid $description object") unless ref($value) eq 'HASH';
    my %allowed = map { $_ => 1 } @allowed;
    _fail("Unknown $description field") if grep { !exists($allowed{$_}) } keys %$value;
    return;
}

sub _policy_path {
    my ($path, $description) = @_;
    _fail("Invalid $description path") if !defined($path) || ref($path)
      || length($path) > 4096 || $path !~ m{\A/[^\x00-\x1f\x7f]+\z}x
      || grep { !length($_) || $_ eq '.' || $_ eq '..' } split(m{/}x, substr($path, 1), -1);
    return $path;
}

sub _policy_digest {
    my ($digest, $description) = @_;
    _fail("Invalid $description digest") if !defined($digest) || ref($digest)
      || $digest !~ /\A[0-9a-f]{64}\z/x;
    return $digest;
}

sub _policy_tool {
    my $tool = shift;
    _policy_fields($tool, 'import policy tool', qw(path sha256 library_directory library_digest));
    _policy_path($tool->{path}, 'native pkg tool');
    _policy_digest($tool->{sha256}, 'native pkg tool');
    if (exists($tool->{library_directory}) || exists($tool->{library_digest})) {
        my $directory = _policy_path($tool->{library_directory}, 'native pkg library');
        _fail('Native pkg library directory cannot contain a colon') if $directory =~ /:/x;
        _policy_digest($tool->{library_digest}, 'native pkg library');
    }
    return;
}

sub _policy_repository {
    my $repository = shift;
    _policy_fields($repository, 'repository profile', qw(trust catalogue_prefix));
    my $trust = $repository->{trust};
    _fail('Invalid repository profile trust') if ref($trust) ne 'HASH'
      || !defined($trust->{type}) || ref($trust->{type});
    if ($trust->{type} eq 'pubkey') {
        _policy_fields($trust, 'repository public key', qw(type path sha256));
        _policy_path($trust->{path}, 'repository public key');
        _policy_digest($trust->{sha256}, 'repository public key');
    } else {
        _fail('Unsupported repository profile trust') unless $trust->{type} eq 'operator-trusted-tree';
        _policy_fields($trust, 'trusted repository tree', qw(type digest));
        _policy_digest($trust->{digest}, 'trusted repository tree');
    }
    xCAT::FreeBSDRepo::catalogue_prefix(exists($repository->{catalogue_prefix}) ? $repository->{catalogue_prefix} : '');
    return;
}

sub _validate_import_policy {
    my $policy = shift;
    _policy_fields($policy, 'FreeBSD import policy', qw(format tool releases repositories));
    _fail('Unsupported FreeBSD import policy format') if !defined($policy->{format})
      || ref($policy->{format}) || $policy->{format} ne 'xcat-freebsd-import-policy-1';
    _policy_tool($policy->{tool});
    _fail('Invalid import policy release approvals') unless ref($policy->{releases}) eq 'HASH';
    for my $digest (sort keys %{$policy->{releases}}) {
        _policy_digest($digest, 'approved release');
        my $release = $policy->{releases}{$digest};
        _policy_fields($release, 'release approval', 'iso_sha256');
        _policy_digest($release->{iso_sha256}, 'approved ISO');
    }
    _fail('Invalid import policy repository profiles') unless ref($policy->{repositories}) eq 'HASH';
    for my $profile (sort keys %{$policy->{repositories}}) {
        _fail('Invalid repository profile name') unless $profile =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\z/x;
        _policy_repository($policy->{repositories}{$profile});
    }
    return;
}

sub _policy_parents {
    my $path = shift;
    my @parts = split(m{/}x, substr($path, 1));
    pop @parts;
    my ($parent, @states) = ('');
    for my $part ('', @parts) {
        $parent .= "/$part" if length($part);
        my $state = _controlled_directory(length($parent) ? $parent : '/', 1);
        push @states, [@{$state}[0, 1, 2, 4]];
    }
    return \@states;
}

sub _protected_file {
    my ($path, $description, $before) = @_;
    my @state = lstat($path);
    _fail("$description must be a protected bounded regular file") if !@state
      || !S_ISREG($state[2]) || $state[3] != 1 || ($state[4] != 0 && $state[4] != $>)
      || ($state[2] & oct('0022')) || $state[7] > 1048576;
    _fail("$description file changed during reading")
      if $before && grep { $state[$_] != $before->[$_] } (0, 1, 2, 3, 4, 7, 9, 10);
    return \@state;
}

sub read_protected_file {
    my ($path, $description) = @_;
    _fail('Protected file reading requires a path and description') unless @_ == 2;
    _policy_path($path, $description);
    my $parents = _policy_parents($path);
    my $before = _protected_file($path, $description);
    sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      or _fail("Cannot open $description: $!");
    binmode($fh) or _fail("Cannot read $description bytes: $!");
    my @opened = stat($fh);
    _fail("$description file changed while opening") if !@opened
      || grep { $opened[$_] != $before->[$_] } (0, 1, 2, 3, 4, 7, 9, 10);
    my $bytes = _read_contents($fh, $before, $description);
    _protected_file($path, $description, $before);
    _fail("$description parent changed during reading") unless _json(_policy_parents($path)) eq _json($parents);
    return $bytes;
}

sub load_import_policy {
    _fail('Import policy loading requires one path') unless @_ == 1;
    my $bytes = read_protected_file(shift, 'FreeBSD import policy');
    my $policy = eval { JSON->new->utf8->max_depth(32)->decode($bytes) };
    _fail('Invalid FreeBSD import policy JSON') if $@;
    _validate_import_policy($policy);
    return $policy;
}

sub release_import_options {
    my ($policy, $digest) = @_;
    _fail('Release import options require a policy and digest') unless @_ == 2;
    _validate_import_policy($policy);
    _policy_digest($digest, 'selected release');
    _fail('The selected release is not approved by the import policy') unless exists($policy->{releases}{$digest});
    return { tool => { %{$policy->{tool}} }, trust => { type => 'operator-trusted-release', digest => $digest } };
}

sub repository_import_options {
    my ($policy, $profile) = @_;
    _fail('Repository import options require a policy and profile') unless @_ == 2;
    _validate_import_policy($policy);
    _fail('Invalid selected repository profile') if !defined($profile) || ref($profile)
      || $profile !~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\z/x;
    _fail('The selected repository profile is not approved by the import policy')
      unless exists($policy->{repositories}{$profile});
    my $repository = $policy->{repositories}{$profile};
    return { tool => { %{$policy->{tool}} }, trust => { %{$repository->{trust}} },
        catalogue_prefix => exists($repository->{catalogue_prefix}) ? $repository->{catalogue_prefix} : '' };
}

sub inspect_import {
    my ($root, $installroot) = @_;
    _fail('Import inspection requires a publication and install root') if @_ != 2;
    $root = _absolute($root);
    $installroot = _installroot($installroot);
    my $prefix = "$installroot/freebsd15.1/x86_64/repositories/";
    my ($digest) = $root =~ /\A\Q$prefix\E([0-9a-f]{64})\z/x;
    _fail('Invalid published repository path') unless defined($digest);
    _installroot($root);
    my ($manifest, $bytes) = _read_manifest("$root/manifest.json");
    _fail('Repository import path and digest differ') unless $digest eq $manifest->{digest};
    _fail('Invalid stored import kind') if !defined($manifest->{kind}) || ref($manifest->{kind});
    _checked_source($manifest->{source}, $manifest->{kind});
    my %extras;
    if ($manifest->{kind} eq 'repository' && ($manifest->{source}{trust}{type} || '') eq 'pubkey') {
        my @key = lstat("$root/repository.pub");
        _fail('Stored repository trust file is unavailable or oversized')
          if !@key || !S_ISREG($key[2]) || $key[7] > 1048576;
        $extras{'repository.pub'} = { size => $key[7], type => 'file', sha256 => $manifest->{source}{trust}{sha256} };
    }
    my ($expected_manifest, $expected_bytes, $expected_tree) =
      _manifest($manifest->{source}, $manifest->{kind}, \%extras);
    _fail('Stored publication differs from its source provenance') unless $bytes eq $expected_bytes;
    _verify($root, $expected_tree, oct('0555'));
    return { %$expected_manifest, path => $root };
}

1;
