package xCAT::FreeBSDPostscript;

use strict;
use warnings;
use Carp qw(croak);
use Cwd qw(realpath);
use Digest::SHA qw(sha256_hex);
use Encode qw(encode FB_CROAK);
use File::Basename qw(dirname);
use File::Path qw(remove_tree);
use Fcntl qw(O_RDONLY O_WRONLY O_RDWR O_CREAT O_EXCL O_NOFOLLOW O_NONBLOCK
    LOCK_EX LOCK_NB S_ISDIR S_ISREG S_ISLNK);
use File::Temp qw(tempdir);
use IO::Handle;
use JSON;
use POSIX qw(ceil);
use Text::ParseWords qw(shellwords);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use xCAT::FreeBSDPkg;

my $render_limit = 8388608;
my $diagnostic_limit = 1048576;
my $json = JSON->new->canonical->utf8->max_depth(32);
my %source_limits = (max_entries => 4096, max_bytes => 67108864,
    max_file_bytes => 16777216, max_manifest_bytes => 4194304,
    max_component_bytes => 255, max_path_bytes => 4096, max_depth => 64, max_link_hops => 64);
my %execution_limits = (max_selection_bytes => 1048576, max_plan_bytes => 8388608,
    max_context_bytes => 16777216, max_request_bytes => 67108864, max_manifest_bytes => 4194304);

sub _fail { die "$_[0]\n"; }
sub _json { return $json->encode(shift); }

sub _options {
    my @arguments = @_;
    _fail('Capture options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fail('Unknown capture option') if grep { $_ ne 'directory' && $_ ne 'timeout' } keys %options;
    $options{directory} = '/var/lib/xcat/freebsd-postscripts' unless exists($options{directory});
    $options{timeout} = 60 unless exists($options{timeout});
    _fail('Invalid capture timeout') if !defined($options{timeout}) || ref($options{timeout})
      || $options{timeout} !~ /\A(?:[0-9]+(?:[.][0-9]+)?|[.][0-9]+)\z/x
      || $options{timeout} <= 0 || $options{timeout} > 60;
    return \%options;
}

sub _directory {
    my ($path, $ancestor) = @_;
    my @state = lstat($path);
    _fail('Unsafe capture directory') if !@state || !S_ISDIR($state[2])
      || ($state[4] != $> && (!$ancestor || $state[4] != 0))
      || (($state[2] & oct('0022')) && !($ancestor && ($state[2] & oct('01000'))))
      || (!$ancestor && ($state[2] & oct('07077')));
    return \@state;
}

sub _root {
    my ($options, $create) = @_;
    my $root = $options->{directory};
    _fail('Invalid capture directory') if !defined($root) || ref($root)
      || $root !~ m{\A/[^\x00\r\n]+\z}x || $root =~ m{//|/\z}x
      || grep { $_ eq '.' || $_ eq '..' } split(m{/}x, $root);
    my $path = '';
    _directory('/', 1);
    for my $part (split(m{/}x, substr($root, 1))) {
        $path .= "/$part";
        if ($path eq $root && $create && !lstat($path)) {
            mkdir($path, 0700) or _fail('Cannot create capture directory');
        }
        _directory($path, $path ne $root);
    }
    my $canonical = realpath($root);
    _fail('Capture directory is not canonical') unless defined($canonical) && $canonical eq $root;
    _sync_directory(dirname($root), 1) if $create;
    return $root;
}

sub _file_state {
    my ($path, $limit) = @_;
    my @state = lstat($path);
    _fail('Unsafe capture file') if !@state || !S_ISREG($state[2]) || $state[3] != 1
      || $state[4] != $> || ($state[2] & oct('07177')) || $state[7] > $limit;
    return \@state;
}

sub _read {
    my ($path, $limit, $digest_only) = @_;
    my $before = _file_state($path, $limit);
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or _fail('Cannot open capture file');
    binmode($file) or _fail('Cannot read capture bytes');
    my @opened = stat($file);
    _fail('Capture file changed while opening') if !@opened
      || grep { $opened[$_] != $before->[$_] } (0, 1, 2, 3, 4, 5, 7, 9, 10);
    my $bytes = '';
    my $length = 0;
    my $digest = $digest_only ? Digest::SHA->new(256) : undef;
    while ($length <= $before->[7]) {
        my $size = $before->[7] - $length + 1;
        $size = 1048576 if $size > 1048576;
        my $count = sysread($file, my $part, $size);
        _fail('Cannot read capture file') unless defined($count);
        last unless $count;
        $length += $count;
        if ($digest_only) { $digest->add($part); }
        else { $bytes .= $part; }
    }
    my @after = stat($file);
    close($file) or _fail('Cannot close capture file');
    my $named = _file_state($path, $limit);
    _fail('Capture file changed while reading') if $length != $before->[7] || !@after
      || grep { $after[$_] != $before->[$_] || $named->[$_] != $before->[$_] } (0, 1, 2, 3, 4, 5, 7, 9, 10);
    return $digest_only ? { bytes => $length, sha256 => $digest->hexdigest } : $bytes;
}

sub _write {
    my ($path, $bytes, $limit) = @_;
    _fail('Capture output exceeds its limit') if length($bytes) > $limit;
    sysopen(my $file, $path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600)
      or _fail('Cannot create private capture file');
    binmode($file) or _fail('Cannot write capture bytes');
    print {$file} $bytes or _fail('Cannot write private capture file');
    $file->flush or _fail('Cannot flush capture file');
    $file->sync or _fail('Cannot sync capture file');
    close($file) or _fail('Cannot close capture file');
    _fail('Capture file readback differs') unless _read($path, $limit) eq $bytes;
    return;
}

sub _sync_directory {
    my ($path, $ancestor) = @_;
    my $before = _directory($path, $ancestor);
    sysopen(my $directory, $path, O_RDONLY | O_NOFOLLOW) or _fail('Cannot open capture directory');
    my @opened = stat($directory);
    _fail('Capture directory changed while opening') if !@opened
      || grep { $opened[$_] != $before->[$_] } (0, 1, 2, 4, 5);
    $directory->sync or _fail('Cannot sync capture directory');
    close($directory) or _fail('Cannot close capture directory');
    my $after = _directory($path, $ancestor);
    _fail('Capture directory changed while syncing') if grep { $after->[$_] != $before->[$_] } (0, 1, 2, 4, 5);
    return;
}

sub _discard_attempt {
    my $path = shift;
    my $before = _directory($path, 0);
    opendir(my $directory, $path) or _fail('Cannot inspect completed attempt');
    my @members = grep { $_ ne '.' && $_ ne '..' } readdir($directory);
    closedir($directory) or _fail('Cannot close completed attempt');
    _file_state("$path/$_", $diagnostic_limit + 2) for @members;
    my $after = _directory($path, 0);
    _fail('Completed attempt directory changed') if grep { $before->[$_] != $after->[$_] } (0, 1, 2, 4, 5, 9, 10);
    for my $name (@members) {
        unlink("$path/$name") or _fail('Cannot remove completed attempt file');
    }
    rmdir($path) or _fail('Cannot remove completed attempt directory');
    _sync_directory(dirname($path));
    return;
}

sub _discard_stage {
    my $path = shift;
    _directory($path, 0);
    my $errors;
    remove_tree($path, { error => \$errors });
    _fail('Cannot remove private postscript stage') if @$errors || lstat($path);
    _sync_directory(dirname($path));
    return;
}

sub _markers {
    my ($bytes) = @_;
    my (@ranges, @open, %seen);
    my $offset = 0;
    my $outer = 0;
    for my $line (split(/(?<=\n)/x, $bytes)) {
        if ($line =~ /\A[\#][ ]((?:(?:defaults|osimage|node)-)?(?:postscripts|postbootscripts))-(start|end)-here(?:\n|\z)/x) {
            my ($name, $edge) = ($1, $2);
            my ($section, $phase) = $name =~ /\A(?:(defaults|osimage|node)-)?(postscripts|postbootscripts)\z/x;
            if ($edge eq 'start') {
                _fail('Duplicate capture marker') if $seen{$name}++;
                if (defined($section)) {
                    _fail('Misplaced capture section') unless @open == 1 && $open[0]{name} eq $phase;
                } else {
                    _fail('Misordered capture phases') if @open || $outer > 1
                      || $phase ne ($outer ? 'postbootscripts' : 'postscripts');
                    ++$outer;
                }
                my $range = { name => $name, begin => $offset, body => $offset + length($line) };
                push @open, $range;
                push @ranges, $range;
            } else {
                _fail('Unbalanced capture marker') unless @open && $open[-1]{name} eq $name;
                my $range = pop @open;
                $range->{end} = $offset;
                $range->{after} = $offset + length($line);
            }
        }
        $offset += length($line);
    }
    _fail('Incomplete capture markers') if @open || $outer != 2;
    return \@ranges;
}

sub _capture_request {
    my ($node, $state) = @_;
    _fail('Invalid capture node') if !defined($node) || ref($node)
      || $node !~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/x;
    _fail('Invalid capture nodeset state') if defined($state)
      && (ref($state) || $state !~ /\A[A-Za-z0-9_.-]{1,64}\z/x);
    return;
}

sub _manifest {
    my ($node, $state, $bytes) = @_;
    _capture_request($node, $state);
    return { kind => 'freebsd-postscript-render-v1', node => $node, nodesetstate => $state,
        rendered => { bytes => length($bytes), sha256 => sha256_hex($bytes) }, markers => _markers($bytes) };
}

sub _descriptor {
    my ($root, $id) = @_;
    _fail('Invalid capture identity') unless defined($id) && !ref($id) && $id =~ /\A[0-9a-f]{64}\z/x;
    my $path = "$root/$id";
    my $before = _directory($path, 0);
    opendir(my $directory, $path) or _fail('Cannot inspect capture members');
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir($directory);
    closedir($directory) or _fail('Cannot close capture member directory');
    _fail('Unexpected capture members') unless _json(\@names) eq _json([qw(manifest.json rendered)]);
    my $record = _read("$path/manifest.json", 65536);
    _fail('Capture manifest identity differs') unless sha256_hex($record) eq $id;
    my $manifest = eval { $json->decode($record) };
    _fail('Invalid capture manifest') unless ref($manifest) eq 'HASH';
    my $rendered = _read("$path/rendered", $render_limit);
    my $expected = _manifest($manifest->{node}, $manifest->{nodesetstate}, $rendered);
    _fail('Capture manifest differs from content') unless _json($expected) . "\n" eq $record;
    my $after = _directory($path, 0);
    _fail('Capture directory changed during reading') if grep { $before->[$_] != $after->[$_] } (0, 1, 2, 4, 5, 9, 10);
    return { id => $id, directory => $path, node => $manifest->{node}, nodesetstate => $manifest->{nodesetstate},
        rendered_sha256 => $manifest->{rendered}{sha256}, rendered_bytes => $manifest->{rendered}{bytes} };
}

sub _render {
    my ($node, $state, $attempt, $source_context) = @_;
    require xCAT::Postage;
    _source_context_matches($source_context) if $source_context;
    my @site = xCAT::TableUtils->get_site_attribute('installdir');
    my $custom = ($site[0] || '/install') . '/postscripts/mypostscript.tmpl';
    _fail('Custom template is unreadable') if lstat($custom) && !-r $custom;
    sysopen(my $callbacks, "$attempt/callbacks.jsonl", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600)
      or _fail('Cannot create private callback capture');
    binmode($callbacks) or _fail('Cannot capture callback bytes');
    my ($used, $reported_error) = (0, 0);
    my $callback = sub {
        my ($response) = @_;
        _fail('Invalid render callback') unless ref($response) eq 'HASH';
        my $encoded = _json($response) . "\n";
        _fail('Render callbacks exceed their limit') if $used + length($encoded) > $diagnostic_limit;
        print {$callbacks} $encoded or _fail('Cannot capture render callback');
        $used += length($encoded);
        for my $field (qw(error errorcode)) {
            next unless exists($response->{$field});
            my @values = ref($response->{$field}) eq 'ARRAY' ? @{$response->{$field}} : ($response->{$field});
            $reported_error = 1 if grep { defined($_) && (ref($_) || ($_ ne '' && $_ ne '0')) } @values;
        }
        return;
    };
    my $rendered = xCAT::Postage::makescript([$node], $state, $callback, 1, 1, 'memory');
    _source_context_matches($source_context) if $source_context;
    _fail('Postscript rendering failed') if $reported_error || !defined($rendered) || ref($rendered);
    $rendered = encode('UTF-8', $rendered, FB_CROAK) if utf8::is_utf8($rendered);
    $callbacks->flush or _fail('Cannot flush render callbacks');
    $callbacks->sync or _fail('Cannot sync render callbacks');
    close($callbacks) or _fail('Cannot close render callbacks');
    _write("$attempt/rendered", $rendered, $render_limit);
    _sync_directory($attempt);
    return 0;
}

sub _diagnostics {
    my ($attempt, $outcome) = @_;
    my %record = %$outcome;
    for my $stream (qw(stdout stderr setup)) {
        my $bytes = delete $record{$stream};
        $bytes = '' unless defined($bytes);
        _write("$attempt/$stream", $bytes, $stream eq 'setup' ? 1024 : $diagnostic_limit);
        $record{$stream} = { bytes => length($bytes), sha256 => sha256_hex($bytes) };
    }
    _write("$attempt/outcome.json", _json(\%record) . "\n", 65536);
    _sync_directory($attempt);
    return;
}

sub _publish {
    my ($root, $attempt, $node, $state) = @_;
    my $bytes = _read("$attempt/rendered", $render_limit);
    _read("$attempt/callbacks.jsonl", $diagnostic_limit);
    my $record = _json(_manifest($node, $state, $bytes)) . "\n";
    my $id = sha256_hex($record);
    sysopen(my $lock, "$root/$id.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0600)
      or _fail('Cannot open capture lock');
    my @locked = stat($lock);
    _fail('Unsafe capture lock') if !@locked || !S_ISREG($locked[2]) || $locked[3] != 1
      || $locked[4] != $> || ($locked[2] & oct('07177'));
    flock($lock, LOCK_EX | LOCK_NB) or _fail('Capture identity is busy');
    if (!lstat("$root/$id")) {
        my $stage = tempdir('.content.XXXXXXXX', DIR => $root, CLEANUP => 0);
        _directory($stage, 0);
        _sync_directory($root);
        _write("$stage/rendered", $bytes, $render_limit);
        _write("$stage/manifest.json", $record, 65536);
        _sync_directory($stage);
        rename($stage, "$root/$id") or _fail('Cannot publish capture');
        _sync_directory($root);
    }
    my $descriptor = _descriptor($root, $id);
    close($lock) or _fail('Cannot close capture lock');
    return $descriptor;
}

sub _capture {
    my ($node, $state, $source_context, @arguments) = @_;
    my ($attempt, $result);
    my $phase = 'request';
    my $ok = eval {
        my $options = _options(@arguments);
        _capture_request($node, $state);
        $phase = 'private storage';
        my $root = _root($options, 1);
        $attempt = tempdir('.attempt.XXXXXXXX', DIR => $root, CLEANUP => 0);
        _directory($attempt, 0);
        _sync_directory($root);
        $phase = 'rendering';
        my %environment = map { defined($ENV{$_}) ? ($_ => $ENV{$_}) : () } keys %ENV;
        my $outcome = xCAT::FreeBSDPkg::run_in_child(sub { return _render($node, $state, $attempt, $source_context); },
            timeout => $options->{timeout}, environment => \%environment,
            stdout_limit => $diagnostic_limit, stderr_limit => $diagnostic_limit);
        _diagnostics($attempt, $outcome);
        _fail('Incomplete postscript render') if defined($outcome->{failure}) || !$outcome->{callback_complete}
          || !$outcome->{streams_complete} || !defined($outcome->{exitcode}) || $outcome->{exitcode} != 0
          || !defined($outcome->{signal}) || $outcome->{signal} != 0;
        $phase = 'artifact validation';
        $result = _publish($root, $attempt, $node, $state);
        $result->{attempt} = $attempt;
        1;
    };
    if (!$ok) {
        my $error = substr($@ || 'Unknown capture failure', 0, 8192);
        eval { _write("$attempt/failure", $error, 8192); _sync_directory($attempt); } if defined($attempt);
        _fail("FreeBSD postscript capture failed during $phase");
    }
    return $result;
}

sub capture {
    my ($node, $state, @arguments) = @_;
    return _capture($node, $state, undef, @arguments);
}

sub read_capture {
    my ($id, @arguments) = @_;
    my $result = eval { _descriptor(_root(_options(@arguments), 0), $id); };
    _fail('FreeBSD postscript capture verification failed') unless $result;
    return $result;
}

sub _source_options {
    my @arguments = @_;
    _fail('Source options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fail('Duplicate source option') if keys(%options) != @arguments / 2;
    my $limits = delete $options{limits};
    $limits = {} unless defined($limits);
    _fail('Invalid source limits') unless ref($limits) eq 'HASH';
    _fail('Unknown source limit') if grep { !exists($source_limits{$_}) } keys %$limits;
    my %bounded = (%source_limits, %$limits);
    for my $key (keys %bounded) {
        _fail('Invalid source limit') if !defined($bounded{$key}) || ref($bounded{$key})
          || $bounded{$key} !~ /\A[1-9][0-9]*\z/x || $bounded{$key} > $source_limits{$key};
        $bounded{$key} = 0 + $bounded{$key};
    }
    return (_options(%options), \%bounded);
}

sub _source_hex {
    my $bytes = shift;
    $bytes = encode('UTF-8', $bytes, FB_CROAK) if utf8::is_utf8($bytes);
    return unpack('H*', $bytes);
}

sub _source_unhex {
    my $value = shift;
    _fail('Invalid source byte encoding') if !defined($value) || ref($value)
      || $value !~ /\A(?:[0-9a-f]{2})*\z/x;
    return pack('H*', $value);
}

sub _source_identity {
    my $state = shift;
    return [@$state[0, 1, 2, 3, 4, 5, 7, 9, 10]];
}

sub _source_state {
    my ($path, $ancestor) = @_;
    my @state = lstat($path);
    _fail('Missing or unsupported source member') unless @state
      && (S_ISDIR($state[2]) || S_ISREG($state[2]) || S_ISLNK($state[2]));
    _fail('Untrusted source owner') unless $state[4] == 0 || $state[4] == $>;
    _fail('Writable source member') if !S_ISLNK($state[2]) && ($state[2] & oct('0022'))
      && !($ancestor && S_ISDIR($state[2]) && ($state[2] & oct('1000')));
    return \@state;
}

sub _source_path {
    my $path = shift;
    _fail('Invalid source root') if !defined($path) || ref($path)
      || $path !~ m{\A/[^\x00\r\n]+\z}x || $path =~ m{//|/\z}x
      || grep { $_ eq '.' || $_ eq '..' } split(m{/}x, $path);
    my $prefix = '';
    _source_state('/', 1);
    for my $part (split(m{/}x, substr($path, 1))) {
        $prefix .= "/$part";
        my $state = _source_state($prefix, $prefix ne $path);
        _fail('Symlinked or non-directory source ancestor') unless S_ISDIR($state->[2]);
    }
    _fail('Noncanonical source root') unless (realpath($path) || '') eq $path;
    return $path;
}

sub _source_context {
    require xCAT::Postage;
    my @site = xCAT::TableUtils->get_site_attribute('installdir');
    my $install = $site[0] || '/install';
    my $root = _source_path("$install/postscripts");
    my $custom = "$root/mypostscript.tmpl";
    my $kind = lstat($custom) ? 'custom' : 'stock';
    _fail('Missing stock template context') if $kind eq 'stock' && (!defined($::XCATROOT) || ref($::XCATROOT));
    my $selected = $kind eq 'custom' ? $custom : "$::XCATROOT/share/xcat/mypostscript/mypostscript.tmpl";
    _fail('Unreadable source template') unless -r $selected;
    _source_path(dirname($selected)) if $kind eq 'stock';
    my $resolved = realpath($selected);
    _fail('Escaping source template') unless defined($resolved)
      && ($kind eq 'stock' ? $resolved eq $selected : index($resolved, "$root/") == 0);
    my $template_state = _source_state($resolved, 0);
    _fail('Nonregular source template') unless S_ISREG($template_state->[2]);
    return { root => _source_hex($root), install => _source_hex($install),
        stockroot => defined($::XCATROOT) ? _source_hex($::XCATROOT) : undef,
        kind => $kind, selected => _source_hex($selected), resolved => _source_hex($resolved),
        root_state => _source_identity(_source_state($root, 0)),
        template_state => _source_identity($template_state) };
}

sub _source_context_matches {
    my $expected = shift;
    _fail('Source selection context changed') unless _json(_source_context()) eq _json($expected);
    return;
}

sub _source_name {
    my ($path, $limits) = @_;
    _fail('Source path exceeds its limit') if length($path) > $limits->{max_path_bytes};
    return if $path eq '';
    my @parts = split(m{/}x, $path, -1);
    _fail('Source path exceeds its depth limit') if @parts > $limits->{max_depth};
    _fail('Invalid source path component') if grep { !length($_) || $_ eq '.' || $_ eq '..'
        || index($_, "\0") >= 0 || length($_) > $limits->{max_component_bytes} } @parts;
    return;
}

sub _source_blob {
    my ($stage, $bytes) = @_;
    my $digest = sha256_hex($bytes);
    if (defined($stage)) {
        my $path = "$stage/blob-$digest";
        if (lstat($path)) {
            _fail('Source blob collision') unless _read($path, $source_limits{max_file_bytes}) eq $bytes;
        } else {
            _write($path, $bytes, $source_limits{max_file_bytes});
        }
    }
    return { bytes => length($bytes), sha256 => $digest };
}

sub _source_file {
    my ($path, $limit, $stage) = @_;
    my $before = _source_state($path, 0);
    _fail('Oversize or nonregular source file') unless S_ISREG($before->[2]) && $before->[7] <= $limit;
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or _fail('Cannot open source file');
    binmode($file) or _fail('Cannot read source bytes');
    my @opened = stat($file);
    _fail('Source changed while opening') unless @opened
      && _json(_source_identity(\@opened)) eq _json(_source_identity($before));
    my $bytes = '';
    while (length($bytes) <= $before->[7]) {
        my $wanted = $before->[7] - length($bytes) + 1;
        $wanted = 1048576 if $wanted > 1048576;
        my $count = sysread($file, my $part, $wanted);
        _fail('Cannot read source file') unless defined($count);
        last unless $count;
        $bytes .= $part;
    }
    my @after = stat($file);
    close($file) or _fail('Cannot close source file');
    _fail('Source changed while reading') unless length($bytes) == $before->[7] && @after
      && _json(_source_identity(\@after)) eq _json(_source_identity($before))
      && _json(_source_identity(_source_state($path, 0))) eq _json(_source_identity($before));
    return _source_blob($stage, $bytes);
}

sub _source_resolve {
    my ($path, $entries, $limits) = @_;
    my @pending = split(m{/}x, $path, -1);
    my (@resolved, $hops);
    $hops = 0;
    while (@pending) {
        my $part = shift @pending;
        next if $part eq '' || $part eq '.';
        if ($part eq '..') {
            _fail('Source link escapes its tree') unless @resolved;
            pop @resolved;
            next;
        }
        push @resolved, $part;
        my $entry = $entries->{_source_hex(join('/', @resolved))};
        _fail('Dangling source link') unless $entry;
        if ($entry->{type} eq 'link') {
            _fail('Cyclic or excessive source links') if ++$hops > $limits->{max_link_hops};
            my $target = _source_unhex($entry->{target});
            _fail('Invalid source link target') if !length($target) || $target =~ m{\A/|\x00}x
              || length($target) > $limits->{max_path_bytes};
            pop @resolved;
            @pending = (split(m{/}x, $target, -1), @pending);
        } elsif (@pending && $entry->{type} ne 'directory') {
            _fail('Source link traverses a non-directory');
        }
    }
    return _source_hex(join('/', @resolved));
}

sub _source_links {
    my ($entries, $limits) = @_;
    my (%edges, %incoming);
    for my $path (keys %$entries) {
        $incoming{$path} = 0 if $entries->{$path}{type} eq 'directory';
    }
    for my $path (sort keys %$entries) {
        next if $path eq '';
        my $raw = _source_unhex($path);
        my $parent = dirname($raw);
        $parent = '' if $parent eq '.';
        $parent = _source_hex($parent);
        _fail('Missing source directory parent') unless exists($incoming{$parent});
        my $target = $entries->{$path}{type} eq 'link' ? _source_resolve($raw, $entries, $limits) : $path;
        next unless $entries->{$target}{type} eq 'directory';
        push @{$edges{$parent}}, $target;
        ++$incoming{$target};
    }
    my @pending = grep { !$incoming{$_} } keys %incoming;
    my $seen = 0;
    while (@pending) {
        my $path = pop @pending;
        ++$seen;
        for my $target (@{$edges{$path} || []}) {
            push @pending, $target if --$incoming{$target} == 0;
        }
    }
    _fail('Cyclic source directory links') unless $seen == keys(%incoming);
    return;
}

sub _source_tree {
    my ($context, $limits, $stage) = @_;
    my $root = _source_unhex($context->{root});
    my (%entries, %observed, %groups);
    my @pending = ('');
    my ($total, $count) = (0, 1);
    while (@pending) {
        my $relative = pop @pending;
        _source_name($relative, $limits);
        my $path = length($relative) ? "$root/$relative" : $root;
        my $state = _source_state($path, 0);
        my $key = _source_hex($relative);
        $observed{$key} = _source_identity($state);
        my $entry = { mode => $state->[2] & oct('7777'), uid => $state->[4], gid => $state->[5] };
        if (S_ISDIR($state->[2])) {
            $entry->{type} = 'directory';
            opendir(my $directory, $path) or _fail('Cannot open source directory');
            my @opened = stat($directory);
            _fail('Source directory changed while opening') unless @opened
              && _json(_source_identity(\@opened)) eq _json($observed{$key});
            while (1) {
                local $! = 0;
                my $name = readdir($directory);
                _fail('Cannot read source directory') if !defined($name) && $!;
                last unless defined($name);
                next if $name eq '.' || $name eq '..';
                _fail('Source exceeds its entry limit') if ++$count > $limits->{max_entries};
                push @pending, length($relative) ? "$relative/$name" : $name;
            }
            closedir($directory) or _fail('Cannot close source directory');
        } else {
            $entry->{links} = $state->[3];
            push @{$groups{"$state->[0]:$state->[1]"}}, $key;
            if (S_ISLNK($state->[2])) {
                $entry->{type} = 'link';
                my $target = readlink($path);
                _fail('Cannot read source link') unless defined($target);
                $entry->{target} = _source_hex($target);
            } else {
                $entry->{type} = 'file';
                my $remaining = $limits->{max_bytes} - $total;
                my $limit = $remaining < $limits->{max_file_bytes} ? $remaining : $limits->{max_file_bytes};
                my $file = _source_file($path, $limit, $stage);
                @{$entry}{qw(bytes sha256)} = @{$file}{qw(bytes sha256)};
                $total += $entry->{bytes};
            }
        }
        $entries{$key} = $entry;
    }
    for my $members (values %groups) {
        my @names = sort @$members;
        for my $name (@names) {
            _fail('Source has an external hard-link alias') unless $entries{$name}{links} == @names;
            $entries{$name}{group} = $names[0];
        }
    }
    _source_links(\%entries, $limits);
    for my $key (keys %observed) {
        my $relative = _source_unhex($key);
        my $path = length($relative) ? "$root/$relative" : $root;
        _fail('Source member changed during traversal') unless
          _json(_source_identity(_source_state($path, 0))) eq _json($observed{$key});
    }
    my $template;
    if ($context->{kind} eq 'custom') {
        my $selected = _source_resolve('mypostscript.tmpl', \%entries, $limits);
        _fail('Template source identity differs') unless "$root/" . _source_unhex($selected)
          eq _source_unhex($context->{resolved});
        $template = { kind => 'custom', member => $selected };
    } else {
        _fail('Source exceeds its entry limit') if ++$count > $limits->{max_entries};
        my $path = _source_unhex($context->{resolved});
        my $remaining = $limits->{max_bytes} - $total;
        my $limit = $remaining < $limits->{max_file_bytes} ? $remaining : $limits->{max_file_bytes};
        my $state = _source_state($path, 0);
        _fail('Stock template has an external hard-link alias') unless $state->[3] == 1;
        $template = { kind => 'stock', file => { mode => $state->[2] & oct('7777'), uid => $state->[4],
            gid => $state->[5], %{_source_file($path, $limit, $stage)} } };
        $total += $template->{file}{bytes};
    }
    return { entries => \%entries, template => $template, bytes => $total, count => $count, observed => \%observed };
}

sub _source_fields {
    my ($record, @fields) = @_;
    _fail('Invalid source record fields') unless ref($record) eq 'HASH'
      && _json([sort keys %$record]) eq _json([sort @fields]);
    return;
}

sub _source_number {
    my ($number, $maximum) = @_;
    _fail('Invalid source record number') if !defined($number) || ref($number)
      || $number !~ /\A(?:0|[1-9][0-9]*)\z/x || $number > $maximum;
    return;
}

sub _source_metadata {
    my ($entry, $link) = @_;
    _source_number($entry->{mode}, oct('7777'));
    _source_number($entry->{uid}, 4294967295);
    _source_number($entry->{gid}, 4294967295);
    _fail('Untrusted recorded source owner') unless $entry->{uid} == 0 || $entry->{uid} == $>;
    _fail('Writable recorded source member') if !$link && ($entry->{mode} & oct('0022'));
    return;
}

sub _source_check_blob {
    my ($path, $entry, $limits, $members) = @_;
    _source_number($entry->{bytes}, $limits->{max_file_bytes});
    _fail('Invalid source blob digest') unless defined($entry->{sha256}) && !ref($entry->{sha256})
      && $entry->{sha256} =~ /\A[0-9a-f]{64}\z/x;
    my $name = "blob-$entry->{sha256}";
    my $bytes = _read("$path/$name", $limits->{max_file_bytes});
    _fail('Source blob differs from manifest') unless length($bytes) == $entry->{bytes}
      && sha256_hex($bytes) eq $entry->{sha256};
    $members->{$name} = 1;
    return;
}

sub _source_descriptor {
    my ($root, $id) = @_;
    _fail('Invalid source identity') unless defined($id) && !ref($id) && $id =~ /\A[0-9a-f]{64}\z/x;
    my $path = "$root/$id";
    my $before = _directory($path, 0);
    my $record = _read("$path/manifest.json", $source_limits{max_manifest_bytes});
    _fail('Source manifest identity differs') unless sha256_hex($record) eq $id;
    my $manifest = $json->decode($record);
    _source_fields($manifest, qw(kind capture_id capture limits entries template bytes count));
    _fail('Invalid source manifest kind') unless $manifest->{kind} eq 'freebsd-postscript-source-v1';
    _source_fields($manifest->{limits}, keys %source_limits);
    my (undef, $limits) = _source_options(limits => $manifest->{limits});
    _fail('Invalid canonical source limits') unless _json($limits) eq _json($manifest->{limits});
    _fail('Source manifest exceeds its recorded limit') if length($record) > $limits->{max_manifest_bytes};
    my $rendered = _read("$path/rendered", $render_limit);
    my $capture = $manifest->{capture};
    _fail('Invalid source render record') unless ref($capture) eq 'HASH';
    my $expected = _manifest($capture->{node}, $capture->{nodesetstate}, $rendered);
    _fail('Source capture binding differs') unless _json($expected) eq _json($capture)
      && $manifest->{capture_id} eq sha256_hex(_json($expected) . "\n");
    my $entries = $manifest->{entries};
    _fail('Invalid source entry roster') unless ref($entries) eq 'HASH' && keys(%$entries) <= $limits->{max_entries}
      && ref($entries->{''}) eq 'HASH' && $entries->{''}{type} eq 'directory';
    my (%members, %groups);
    @members{qw(manifest.json rendered)} = (1, 1);
    my ($total, $count) = (0, scalar(keys %$entries));
    for my $key (sort keys %$entries) {
        _source_name(_source_unhex($key), $limits);
        my $entry = $entries->{$key};
        _fail('Invalid source member kind') unless ref($entry) eq 'HASH' && defined($entry->{type})
          && $entry->{type} =~ /\A(?:directory|file|link)\z/x;
        my @fields = qw(type mode uid gid);
        push @fields, qw(group links) unless $entry->{type} eq 'directory';
        push @fields, qw(bytes sha256) if $entry->{type} eq 'file';
        push @fields, 'target' if $entry->{type} eq 'link';
        _source_fields($entry, @fields);
        _source_metadata($entry, $entry->{type} eq 'link');
        if ($entry->{type} ne 'directory') {
            _source_number($entry->{links}, $limits->{max_entries});
            _source_name(_source_unhex($entry->{group}), $limits);
            push @{$groups{$entry->{group}}}, $key;
        }
        if ($entry->{type} eq 'file') {
            _source_check_blob($path, $entry, $limits, \%members);
            $total += $entry->{bytes};
        }
        _fail('Source exceeds its byte limit') if $total > $limits->{max_bytes};
    }
    for my $group (keys %groups) {
        my @names = sort @{$groups{$group}};
        _fail('Invalid source hard-link group') unless $group eq $names[0];
        for my $name (@names) {
            _fail('Source hard-link metadata differs') unless $entries->{$name}{links} == @names
              && _json($entries->{$name}) eq _json($entries->{$group});
        }
    }
    _source_links($entries, $limits);
    my $template = $manifest->{template};
    _fail('Invalid source template record') unless ref($template) eq 'HASH' && defined($template->{kind});
    if ($template->{kind} eq 'custom') {
        _source_fields($template, qw(kind member));
        my $resolved = _source_resolve('mypostscript.tmpl', $entries, $limits);
        _fail('Invalid custom template binding') unless $template->{member} eq $resolved && $entries->{$resolved}{type} eq 'file';
    } else {
        _source_fields($template, qw(kind file));
        _fail('Invalid stock template selection') unless $template->{kind} eq 'stock' && !exists($entries->{_source_hex('mypostscript.tmpl')});
        _source_fields($template->{file}, qw(mode uid gid bytes sha256));
        _source_metadata($template->{file}, 0);
        _source_check_blob($path, $template->{file}, $limits, \%members);
        $total += $template->{file}{bytes};
        ++$count;
    }
    _source_number($manifest->{count}, $limits->{max_entries});
    _source_number($manifest->{bytes}, $limits->{max_bytes});
    _fail('Source manifest accounting differs') unless $count <= $limits->{max_entries} && $total <= $limits->{max_bytes}
      && $manifest->{count} == $count && $manifest->{bytes} == $total;
    _fail('Noncanonical source manifest') unless _json($manifest) . "\n" eq $record;
    opendir(my $directory, $path) or _fail('Cannot inspect source members');
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir($directory);
    closedir($directory) or _fail('Cannot close source members');
    _fail('Unexpected source members') unless _json(\@names) eq _json([sort keys %members]);
    my $after = _directory($path, 0);
    _fail('Source artifact changed while reading') if grep { $after->[$_] != $before->[$_] } (0, 1, 2, 4, 5, 9, 10);
    return { id => $id, kind => $manifest->{kind}, directory => $path, node => $capture->{node},
        nodesetstate => $capture->{nodesetstate}, capture_id => $manifest->{capture_id},
        entries => $count, bytes => $total };
}

sub _source_publish {
    my ($root, $attempt, $stage, $manifest, $limits) = @_;
    my $record = _json($manifest) . "\n";
    _write("$stage/manifest.json", $record, $limits->{max_manifest_bytes});
    my $id = sha256_hex($record);
    sysopen(my $lock, "$root/$id.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
      or _fail('Cannot open source identity lock');
    _file_state("$root/$id.lock", 0);
    my @opened = stat($lock);
    my $named = _file_state("$root/$id.lock", 0);
    _fail('Source identity lock changed') unless @opened && $opened[0] == $named->[0] && $opened[1] == $named->[1];
    flock($lock, LOCK_EX | LOCK_NB) or _fail('Source identity is busy');
    _sync_directory($stage);
    if (!lstat("$root/$id")) {
        rename($stage, "$root/$id") or _fail('Cannot publish source artifact');
        _sync_directory($attempt);
        _sync_directory($root);
    }
    my $descriptor = _source_descriptor($root, $id);
    close($lock) or _fail('Cannot close source identity lock');
    return $descriptor;
}

sub seal_source {
    my ($node, $state, @arguments) = @_;
    my ($attempt, $result);
    my $phase = 'request';
    my $ok = eval {
        my ($options, $limits) = _source_options(@arguments);
        _capture_request($node, $state);
        $phase = 'source admission';
        my $context = _source_context();
        my $source = _source_unhex($context->{root});
        my $destination = $options->{directory};
        _fail('Overlapping source and private storage') if defined($destination) && !ref($destination)
          && ($destination eq $source || index($destination, "$source/") == 0 || index($source, "$destination/") == 0);
        my $root = _root($options, 1);
        $attempt = tempdir('.source-attempt.XXXXXXXX', DIR => $root, CLEANUP => 0);
        my $stage = "$attempt/content";
        mkdir($stage, oct('0700')) or _fail('Cannot create source stage');
        _directory($attempt, 0);
        _directory($stage, 0);
        _sync_directory($attempt);
        _sync_directory($root);
        my $tree = _source_tree($context, $limits, $stage);
        _write("$attempt/source-before.json", _json({ context => $context, observed => $tree->{observed} }) . "\n",
            $source_limits{max_manifest_bytes});
        _source_context_matches($context);
        $phase = 'rendering';
        my $capture = _capture($node, $state, $context, %$options);
        _write("$attempt/capture.json", _json($capture) . "\n", 65536);
        $phase = 'source revalidation';
        _source_context_matches($context);
        my $after = _source_tree($context, $limits, undef);
        _write("$attempt/source-after.json", _json({ context => _source_context(), observed => $after->{observed} }) . "\n",
            $source_limits{max_manifest_bytes});
        _fail('Source tree changed during capture') unless _json($tree) eq _json($after);
        _source_context_matches($context);
        my $capture_record = _read("$capture->{directory}/manifest.json", 65536);
        _descriptor($root, $capture->{id});
        my $rendered = _read("$capture->{directory}/rendered", $render_limit);
        _write("$stage/rendered", $rendered, $render_limit);
        my $manifest = { kind => 'freebsd-postscript-source-v1', capture_id => $capture->{id},
            capture => $json->decode($capture_record), limits => $limits,
            map { $_ => $tree->{$_} } qw(entries template bytes count) };
        $phase = 'source publication';
        $result = _source_publish($root, $attempt, $stage, $manifest, $limits);
        $result->{attempt} = $attempt;
        1;
    };
    if (!$ok) {
        my $error = substr($@ || 'Unknown source sealing failure', 0, 8192);
        eval { _write("$attempt/failure", $error, 8192); _sync_directory($attempt); } if defined($attempt);
        _fail("FreeBSD postscript source sealing failed during $phase");
    }
    return $result;
}

sub read_source {
    my ($id, @arguments) = @_;
    my $result = eval {
        my $options = _options(@arguments);
        _source_descriptor(_root($options, 0), $id);
    };
    _fail('FreeBSD postscript source verification failed') unless $result;
    return $result;
}

sub _execution_limits {
    my $limits = shift;
    $limits = {} unless defined($limits);
    _fail('Invalid preparation limits') unless ref($limits) eq 'HASH';
    _fail('Unknown preparation limit') if grep { !exists($execution_limits{$_}) } keys %$limits;
    my %bounded = (%execution_limits, %$limits);
    for my $key (keys %bounded) {
        _fail('Invalid preparation limit') if !defined($bounded{$key}) || ref($bounded{$key})
          || $bounded{$key} !~ /\A[1-9][0-9]*\z/x || $bounded{$key} > $execution_limits{$key};
        $bounded{$key} = 0 + $bounded{$key};
    }
    return \%bounded;
}

sub _execution_selection {
    my ($request, $limits) = @_;
    _fail('Invalid preparation selection') unless ref($request) eq 'HASH'
      && defined($request->{kind}) && !ref($request->{kind})
      && $request->{kind} =~ /\A(?:firstboot|repeat|update)\z/x;
    my $update = $request->{kind} eq 'update';
    _source_fields($request, 'kind', $update ? ('raw') : ());
    my $bytes = $update ? $request->{raw} : '';
    _fail('Invalid raw preparation selection') if !defined($bytes) || ref($bytes)
      || !utf8::downgrade($bytes, 1) || length($bytes) > $limits->{max_selection_bytes};
    return ({ kind => $request->{kind}, raw_present => $update ? 1 : 0,
        bytes => length($bytes), sha256 => sha256_hex($bytes), rules => 'xcat-postscript-request-v1' }, $bytes);
}

sub _execution_row {
    my ($table, $key, $name, $fields, $effective) = @_;
    my $handle = xCAT::Table->new($table, -create => 0, -autocommit => 1);
    _fail('Cannot open preparation table') unless $handle;
    my @rows;
    my $ok = eval {
        @rows = $effective ? $handle->getNodeAttribs($name, $fields)
          : $handle->getAttribs({ $key => $name }, $fields);
        1;
    };
    my $closed = eval { $handle->close(); 1; };
    _fail('Cannot read preparation table') unless $ok && $closed;
    _fail('Missing or ambiguous preparation row') unless @rows == 1 && ref($rows[0]) eq 'HASH';
    my %row = map { exists($rows[0]{$_}) ? ($_ => $rows[0]{$_}) : () } @$fields;
    _fail('Invalid preparation row') if grep { ref($_) } values %row;
    _fail('Preparation row key differs') unless $effective
      || (defined($row{$key}) && $row{$key} eq $name);
    _fail('Disabled preparation row') if defined($row{disable}) && $row{disable} =~ /\A(?:yes|1)\z/ix;
    return \%row;
}

sub _execution_context {
    my $node = shift;
    require xCAT::Postage;
    my $listed = _execution_row('nodelist', 'node', $node, [qw(node disable)], 0);
    my $type = _execution_row('nodetype', 'node', $node, [qw(os arch profile provmethod disable)], 1);
    _fail('Unsupported preparation node') unless ($type->{os} || '') eq 'freebsd15.1'
      && ($type->{arch} || '') eq 'x86_64';
    my $name = $type->{provmethod};
    _fail('Preparation requires an explicit image') unless defined($name)
      && $name =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,246}\z/x
      && $name !~ /\A(?:install|netboot|statelite)\z/x;
    my $image = _execution_row('osimage', 'imagename', $name,
        [qw(imagename imagetype osname osvers osarch provmethod disable profile
            postscripts postbootscripts environvar synclists kitcomponents)], 0);
    my $settings = _execution_row('freebsdimage', 'imagename', $name,
        [qw(imagename imageversion bootdir pkgdir pkglist otherpkgdir otherpkglist disable)], 0);
    my @repeat = xCAT::TableUtils->get_site_attribute('runbootscripts');
    _fail('Ambiguous repeat policy') if @repeat > 1 || grep { ref($_) } @repeat;
    my $installroot = _source_path(xCAT::TableUtils->getInstallDir());
    return { node => $node, nodelist => $listed, nodetype => $type, image => $image,
        settings => $settings, installroot => $installroot,
        repeat => { value => @repeat ? $repeat[0] : undef } };
}

sub _execution_package {
    my ($path, $context, @scope) = @_;
    require xCAT::FreeBSDPackagePlan;
    my $package = xCAT::FreeBSDPackagePlan::inspect_image($path, $context->{installroot},
        { %{$context->{image}}, %{$context->{settings}} }, @scope);
    _fail('Package inspection lacks canonical bytes') unless defined($package->{bytes}) && !ref($package->{bytes})
      && sha256_hex($package->{bytes}) eq $package->{digest};
    return $package;
}

sub _execution_modes {
    my $source = shift;
    my $record = _read("$source->{directory}/manifest.json", $source_limits{max_manifest_bytes});
    _fail('Source mode identity differs') unless sha256_hex($record) eq $source->{id};
    my $manifest = $json->decode($record);
    my %modes;
    for my $path (keys %{$manifest->{entries}}) {
        my $entry = $manifest->{entries}{$path};
        _fail('Special source permissions prevent preparation') if $entry->{mode} & oct('7000');
        $modes{$path} = { type => $entry->{type}, original => { map { $_ => $entry->{$_} } qw(mode uid gid) },
            effective => { mode => $entry->{mode}, uid => 0, gid => 0 } };
    }
    my $template;
    if ($manifest->{template}{kind} eq 'stock') {
        my $entry = $manifest->{template}{file};
        _fail('Special template permissions prevent preparation') if $entry->{mode} & oct('7000');
        $template = { original => { map { $_ => $entry->{$_} } qw(mode uid gid) },
            effective => { mode => $entry->{mode}, uid => 0, gid => 0 } };
    }
    return { name => 'root-private-preserve-v1', outer => { mode => oct('0700'), uid => 0, gid => 0 },
        entries => \%modes, stock_template => $template };
}

sub _execution_content {
    my ($bytes) = @_;
    return { bytes => length($bytes), sha256 => sha256_hex($bytes) };
}

sub _execution_manifest {
    my ($source, $selection, $context, $package, $request, $limits) = @_;
    return { kind => 'freebsd-postscript-preparation-v1', node => $source->{node},
        nodesetstate => $source->{nodesetstate}, source_id => $source->{id},
        selection => $selection, context => _execution_content($context),
        package_plan => _execution_content($package), package_request => _execution_content($request),
        limits => $limits, mode_policy => _execution_modes($source) };
}

sub _execution_descriptor {
    my ($root, $id) = @_;
    _fail('Invalid preparation identity') unless defined($id) && !ref($id) && $id =~ /\A[0-9a-f]{64}\z/x;
    my $path = "$root/$id";
    my $before = _directory($path, 0);
    my $record = _read("$path/manifest.json", $execution_limits{max_manifest_bytes});
    _fail('Preparation identity differs') unless sha256_hex($record) eq $id;
    my $manifest = $json->decode($record);
    _source_fields($manifest, qw(kind node nodesetstate source_id selection context package_plan package_request limits mode_policy));
    _source_fields($manifest->{limits}, keys %execution_limits);
    my $limits = _execution_limits($manifest->{limits});
    _fail('Preparation exceeds its manifest limit') if length($record) > $limits->{max_manifest_bytes};
    my $source = read_source($manifest->{source_id}, directory => $root);
    my $raw = _read("$path/selection", $limits->{max_selection_bytes});
    my $selected = $manifest->{selection};
    _fail('Invalid preparation selection record') unless ref($selected) eq 'HASH';
    my ($selection) = _execution_selection({ kind => $selected->{kind},
        $selected->{raw_present} ? (raw => $raw) : () }, $limits);
    _fail('Unexpected absent selection bytes') if !$selected->{raw_present} && length($raw);
    my $context = _read("$path/context.json", $limits->{max_context_bytes});
    my $observed = $json->decode($context);
    _source_fields($observed, qw(node nodelist nodetype image settings installroot repeat));
    _fail('Preparation node binding differs') unless $observed->{node} eq $source->{node}
      && ref($observed->{nodetype}) eq 'HASH' && ref($observed->{image}) eq 'HASH'
      && ref($observed->{settings}) eq 'HASH'
      && $observed->{nodetype}{provmethod} eq $observed->{image}{imagename}
      && $observed->{image}{imagename} eq $observed->{settings}{imagename};
    my $package = _read("$path/package.plan", $limits->{max_plan_bytes});
    require xCAT::FreeBSDPackagePlan;
    my $parsed_package = xCAT::FreeBSDPackagePlan::parse($package);
    my $request = _read("$path/package-request.json", $limits->{max_request_bytes});
    my $requested = $json->decode($request);
    _source_fields($requested, qw(image lists repositories components applications),
        exists($requested->{scope}) ? ('scope') : ());
    _fail('Preparation package scope differs') unless ($requested->{scope} || 'all') eq ($parsed_package->{scope} || 'all');
    _fail('Scoped packages require an update run') if exists($parsed_package->{scope}) && $selection->{kind} ne 'update';
    _fail('Noncanonical preparation observation') unless _json($observed) . "\n" eq $context
      && _json($requested) . "\n" eq $request;
    my $expected = _execution_manifest($source, $selection, $context, $package, $request, $limits);
    _fail('Preparation manifest differs from content') unless _json($expected) . "\n" eq $record;
    opendir(my $directory, $path) or _fail('Cannot inspect preparation members');
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir($directory);
    closedir($directory) or _fail('Cannot close preparation members');
    _fail('Unexpected preparation members') unless _json(\@names)
      eq _json([qw(context.json manifest.json package-request.json package.plan selection)]);
    my $after = _directory($path, 0);
    _fail('Preparation changed while reading') if grep { $before->[$_] != $after->[$_] } (0, 1, 2, 4, 5, 9, 10);
    return { id => $id, kind => $manifest->{kind}, node => $source->{node}, nodesetstate => $source->{nodesetstate},
        source_id => $source->{id}, package_plan_sha256 => sha256_hex($package), entries => $source->{entries}, bytes => $source->{bytes} };
}

sub _execution_publish {
    my ($root, $attempt, $stage, $manifest, $limits) = @_;
    my $record = _json($manifest) . "\n";
    _write("$stage/manifest.json", $record, $limits->{max_manifest_bytes});
    my $id = sha256_hex($record);
    sysopen(my $lock, "$root/$id.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
      or _fail('Cannot open preparation identity lock');
    _file_state("$root/$id.lock", 0);
    my @opened = stat($lock);
    my $named = _file_state("$root/$id.lock", 0);
    _fail('Preparation lock changed') unless @opened && $opened[0] == $named->[0] && $opened[1] == $named->[1];
    flock($lock, LOCK_EX | LOCK_NB) or _fail('Preparation identity is busy');
    _sync_directory($stage);
    if (!lstat("$root/$id")) {
        rename($stage, "$root/$id") or _fail('Cannot publish preparation');
        _sync_directory($attempt);
        _sync_directory($root);
    }
    my $descriptor = _execution_descriptor($root, $id);
    close($lock) or _fail('Cannot close preparation lock');
    return $descriptor;
}

sub prepare_execution {
    my ($node, $state, @arguments) = @_;
    return _prepare_execution($node, $state, undef, @arguments);
}

sub _execution_ssh_policy {
    my ($source, $context, $selection, $raw) = @_;
    my $bytes = _read("$source->{directory}/manifest.json", $source_limits{max_manifest_bytes});
    _fail('SSH policy source changed') unless sha256_hex($bytes) eq $source->{id};
    my $manifest = $json->decode($bytes);
    my $native = '5261a51fe998d40c2f9fff02b18b75fa729706057cd8e5d256e9c589f8025531';
    my $launcher = '5b0b35feae45a3e9fc0f1bbc1d3f5b8217cca5d1ec198bef980efcdabe2c2e86';
    return 1 unless grep { $_->{type} eq 'file' && $_->{sha256} eq $native } values %{$manifest->{entries}};
    my $rendered = _read("$source->{directory}/rendered", $render_limit);
    _fail('SSH policy render changed') unless sha256_hex($rendered) eq $manifest->{capture}{rendered}{sha256};
    my $compiled = eval { _driver($rendered, { kind => $selection->{kind},
        $selection->{raw_present} ? (raw => $raw) : () }, $context->{repeat}{value}); };
    # Preparation retains opaque requests; compilation still rejects unusable selections.
    return 1 unless $compiled;
    my $required;
    for my $entry (@{$compiled->{entries}}) {
        my $name = _source_unhex($entry->{name});
        next unless exists($manifest->{entries}{_source_hex($name)});
        my $key = _source_resolve($name, $manifest->{entries}, \%source_limits);
        my $file = $manifest->{entries}{$key};
        next unless $file->{type} eq 'file';
        if ($file->{sha256} eq $launcher) {
            my $directory = dirname($name);
            my $adapter = ($directory eq '.' ? '' : "$directory/") . 'remoteshell.freebsd';
            $key = _source_resolve($adapter, $manifest->{entries}, \%source_limits);
            $file = $manifest->{entries}{$key};
        }
        $required = 1 if $file->{type} eq 'file' && $file->{sha256} eq $native;
    }
    return 1 unless $required;
    my @configured = grep { /\A\s*ENABLESSHBETWEENNODES\s*=/x }
      split(/,/x, $context->{image}{environvar} || '', -1);
    return 0 unless @configured == 1;
    my @words = shellwords($configured[0]);
    return @words == 1 && $words[0] =~ /\AENABLESSHBETWEENNODES=(?:no|NO|No|n|N|0)\z/x;
}

sub _prepare_execution {
    my ($node, $state, $source_id, @arguments) = @_;
    my ($attempt, $result, $public_error);
    my $phase = 'request';
    my $ok = eval {
        _capture_request($node, $state);
        _fail('Preparation options must be unique pairs') if @arguments % 2;
        my %options = @arguments;
        _fail('Duplicate preparation option') unless keys(%options) == @arguments / 2;
        my $plan = delete $options{plan};
        my @scope = exists($options{package_scope}) ? (delete $options{package_scope}) : ();
        my $request = delete $options{selection};
        my $limits = _execution_limits(delete $options{preparation_limits});
        my ($storage, $source_bounds) = _source_options(%options);
        my ($selection, $raw) = _execution_selection($request, $limits);
        $phase = 'image binding';
        my $context = _execution_context($node);
        my $source_path = "$context->{installroot}/postscripts";
        my $destination = $storage->{directory};
        _fail('Overlapping preparation storage') if defined($destination) && !ref($destination)
          && ($destination eq $source_path || index($destination, "$source_path/") == 0
            || index($source_path, "$destination/") == 0);
        $phase = 'private storage';
        my $root = _root($storage, 1);
        $attempt = tempdir('.preparation-attempt.XXXXXXXX', DIR => $root, CLEANUP => 0);
        _directory($attempt, 0);
        _sync_directory($root);
        $phase = 'image binding';
        my $context_bytes = _json($context) . "\n";
        _write("$attempt/context-before.json", $context_bytes, $limits->{max_context_bytes});
        my $package = _execution_package($plan, $context, @scope);
        my $package_request = _json($package->{request}) . "\n";
        _write("$attempt/package.plan", $package->{bytes}, $limits->{max_plan_bytes});
        _write("$attempt/package-request.json", $package_request, $limits->{max_request_bytes});
        $phase = 'source sealing';
        my $source = defined($source_id) ? read_source($source_id, directory => $root)
          : seal_source($node, $state, %$storage, limits => $source_bounds);
        _fail('Preparation source belongs to another request')
          unless $source->{node} eq $node && $source->{nodesetstate} eq $state;
        _write("$attempt/source.json", _json($source) . "\n", 65536);
        $phase = 'request revalidation';
        my $after = _execution_context($node);
        _write("$attempt/context-after.json", _json($after) . "\n", $limits->{max_context_bytes});
        _fail('Preparation node or image changed') unless _json($after) . "\n" eq $context_bytes;
        my $checked = _execution_package($plan, $after, @scope);
        _fail('Preparation package request changed') unless $checked->{bytes} eq $package->{bytes}
          && $checked->{digest} eq $package->{digest} && _json($checked->{request}) . "\n" eq $package_request;
        $phase = 'native script policy';
        unless (_execution_ssh_policy($source, $after, $selection, $raw)) {
            $public_error = 'FreeBSD remoteshell requires osimage.environvar=ENABLESSHBETWEENNODES=NO';
            _fail($public_error);
        }
        $phase = 'preparation publication';
        $source = read_source($source->{id}, directory => $root);
        my $stage = "$attempt/content";
        mkdir($stage, oct('0700')) or _fail('Cannot create preparation stage');
        _directory($stage, 0);
        _sync_directory($attempt);
        _write("$stage/selection", $raw, $limits->{max_selection_bytes});
        _write("$stage/context.json", $context_bytes, $limits->{max_context_bytes});
        _write("$stage/package.plan", $package->{bytes}, $limits->{max_plan_bytes});
        _write("$stage/package-request.json", $package_request, $limits->{max_request_bytes});
        my $manifest = _execution_manifest($source, $selection, $context_bytes, $package->{bytes}, $package_request, $limits);
        $result = _execution_publish($root, $attempt, $stage, $manifest, $limits);
        1;
    };
    if (!$ok) {
        my $error = substr($@ || 'Unknown preparation failure', 0, 8192);
        eval { _write("$attempt/failure", $error, 8192); _sync_directory($attempt); } if defined($attempt);
        _fail($public_error || "FreeBSD postscript preparation failed during $phase");
    }
    return $result;
}

sub read_execution {
    my ($id, @arguments) = @_;
    my $result = eval { _execution_descriptor(_root(_options(@arguments), 0), $id); };
    _fail('FreeBSD postscript preparation verification failed') unless $result;
    return $result;
}

sub prepare_boot {
    my ($node, $plan, @arguments) = @_;
    _fail('Boot preparation options must be unique pairs') if @arguments % 2;
    my %arguments = @arguments;
    _fail('Duplicate boot preparation option') unless keys(%arguments) == @arguments / 2;
    my $storage = delete $arguments{data_storage};
    my $options = _options(%arguments);
    my $context = _json(_execution_context($node)) . "\n";
    my $source = seal_source($node, 'install', %$options);
    my $root = _root($options, 0);
    my $firstboot = defined($storage) ? _storage_source($root, $source, $storage) : $source;
    my (%preparations, %package_bytes);
    for my $kind (qw(firstboot repeat)) {
        my $selected = $kind eq 'firstboot' ? $firstboot : $source;
        my $prepared = _prepare_execution($node, 'install', $selected->{id}, %$options,
            plan => $plan, selection => { kind => $kind });
        _fail('Boot context changed during preparation')
          unless _read("$root/$prepared->{id}/context.json", $execution_limits{max_context_bytes}) eq $context;
        for my $input (['package.plan', 'max_plan_bytes'], ['package-request.json', 'max_request_bytes']) {
            my ($name, $limit) = @$input;
            my $bytes = _read("$root/$prepared->{id}/$name", $execution_limits{$limit});
            _fail('Boot package request changed during preparation')
              if exists($package_bytes{$name}) && $package_bytes{$name} ne $bytes;
            $package_bytes{$name} = $bytes;
        }
        compile_execution($prepared->{id}, directory => $root);
        $preparations{$kind} = $prepared->{id};
    }
    _fail('Boot context changed after preparation') unless _json(_execution_context($node)) . "\n" eq $context;
    return \%preparations;
}

sub _storage_source {
    my ($root, $source, $storage) = @_;
    my $attempt = tempdir('.storage-source.XXXXXXXX', DIR => $root, CLEANUP => 0);
    my $result;
    my $ok = eval {
        $result = _storage_source_stage($root, $source, $storage, $attempt);
        1;
    };
    my $error = $@;
    _discard_stage($attempt);
    croak $error unless $ok;
    return $result;
}

sub _storage_source_stage {
    my ($root, $source, $storage, $attempt) = @_;
    require xCAT::FreeBSDStorage;
    my $path = $source->{directory};
    my $manifest_bytes = _read("$path/manifest.json", $source_limits{max_manifest_bytes});
    _fail('Storage source identity changed') unless sha256_hex($manifest_bytes) eq $source->{id};
    my $manifest = $json->decode($manifest_bytes);
    my $entries = $manifest->{entries};
    my $limits = $manifest->{limits};
    my $prefix = 'xcat-storage.d';
    _fail('The storage payload directory is reserved') if exists($entries->{_source_hex($prefix)});
    for my $name (qw(configstorage.freebsd configzfs.freebsd configzfs-freebsd.awk)) {
        my $resolved = _source_resolve($name, $entries, $limits);
        my $entry = $entries->{$resolved};
        _fail('Missing storage postscript or planner') unless $entry->{type} eq 'file'
          && ($name =~ /[.]awk\z/x || ($entry->{mode} & oct('0111')));
    }
    if (grep { exists($_->{datasets}) } @{$storage->{pools}}) {
        my $resolved = _source_resolve('configzfs-datasets.awk', $entries, $limits);
        _fail('Missing dataset planner') unless $entries->{$resolved}{type} eq 'file';
    }
    my $files = xCAT::FreeBSDStorage::files($source->{node}, $storage);
    my $stage = "$attempt/content";
    mkdir($stage, oct('0700')) or _fail('Cannot create storage source stage');
    my %blobs = map { $_->{type} eq 'file' ? ($_->{sha256} => 1) : () } values %$entries;
    $blobs{$manifest->{template}{file}{sha256}} = 1 if $manifest->{template}{kind} eq 'stock';
    for my $source_digest (sort keys %blobs) {
        _write("$stage/blob-$source_digest", _read("$path/blob-$source_digest", $limits->{max_file_bytes}), $limits->{max_file_bytes});
    }
    $entries->{_source_hex($prefix)} = { type => 'directory', mode => oct('0700'), uid => 0, gid => 0 };
    ++$manifest->{count};
    for my $name (sort keys %$files) {
        _fail('Invalid generated storage filename') unless $name eq 'pools'
          || $name =~ /\A[a-z][a-z0-9_-]{0,62}[.](?:conf|key|datasets)\z/x;
        my $bytes = $files->{$name};
        my $digest = sha256_hex($bytes);
        if (!$blobs{$digest}++) {
            _write("$stage/blob-$digest", $bytes, $limits->{max_file_bytes});
        }
        my $key = _source_hex("$prefix/$name");
        $entries->{$key} = { type => 'file', mode => oct('0600'), uid => 0, gid => 0,
            links => 1, group => $key, bytes => length($bytes), sha256 => $digest };
        ++$manifest->{count};
        $manifest->{bytes} += length($bytes);
    }
    my $rendered = _read("$path/rendered", $render_limit);
    _fail('Missing firstboot storage insertion point') unless
      $rendered =~ s/^([#][ ]postscripts-start-here\n)/$1configstorage.freebsd\n/mx;
    _write("$stage/rendered", $rendered, $render_limit);
    $manifest->{capture} = _manifest($source->{node}, $source->{nodesetstate}, $rendered);
    $manifest->{capture_id} = sha256_hex(_json($manifest->{capture}) . "\n");
    _sync_directory($attempt);
    _sync_directory($root);
    return _source_publish($root, $attempt, $stage, $manifest, $limits);
}

sub prepare_update {
    my ($node, $selection, @arguments) = @_;
    require xCAT::FreeBSDInstall;
    require xCAT::FreeBSDRepoImport;
    require xCAT::FreeBSDPackagePlan;
    require xCAT::Utils;
    _fail('Update options must be pairs') if @arguments % 2;
    my %update_options = @arguments;
    my $require_packages = delete $update_options{require_packages};
    _fail('Invalid required package update') if defined($require_packages)
      && (ref($require_packages) || $require_packages !~ /\A[01]\z/x);
    my $options = _options(%update_options);
    my $state = xCAT::FreeBSDInstall::state($node);
    _fail('Postscript update requires an installed FreeBSD node') unless $state
      && $state->{phase} =~ /\A(?:installed|booted)\z/x;
    my $context = _execution_context($node);
    my $source = seal_source($node, 'install', %$options);
    my $scope = _update_package_scope($source, $selection, $context->{repeat}{value});
    _fail('FreeBSD software update requires the supplied ospkgs, otherpkgs and xcatpackages.freebsd adapters')
      if $require_packages && (!defined($scope) || $scope ne 'all');
    my @policy_paths = xCAT::TableUtils->get_site_attribute('freebsdimportpolicy');
    _fail('Postscript update requires one import policy') unless @policy_paths == 1;
    my $policy = xCAT::FreeBSDRepoImport::load_import_policy($policy_paths[0]);
    my $planning = xCAT::FreeBSDRepoImport::package_plan_options($policy);
    my $plan = xCAT::FreeBSDPackagePlan::publish_image(installroot => $context->{installroot},
        image => { %{$context->{image}}, %{$context->{settings}} }, %$planning,
        defined($scope) ? (scope => $scope) : ());
    my $prepared = _prepare_execution($node, 'install', $source->{id}, %$options, plan => $plan->{path},
        defined($scope) ? (package_scope => $scope) : (),
        selection => { kind => 'update', raw => $selection });
    my $root = _root($options, 0);
    _fail('Update context changed during preparation')
      unless _read("$root/$prepared->{id}/context.json", $execution_limits{max_context_bytes}) eq _json($context) . "\n";
    my $current = xCAT::FreeBSDInstall::state($node);
    _fail('Installation changed during postscript preparation') unless $current
      && $current->{phase} =~ /\A(?:installed|booted)\z/x
      && $current->{generation} eq $state->{generation} && $current->{attempt} eq $state->{attempt};
    my $run = xCAT::Utils::genUUID();
    $run =~ s/-//gx;
    return export_execution($prepared->{id}, directory => $options->{directory}, run => $run,
        generation => $state->{generation}, attempt => $state->{attempt}, package_mode => defined($scope) ? 'update' : 'verify');
}

sub _update_package_scope {
    my ($source, $selection, $repeat) = @_;
    my $source_bytes = _read("$source->{directory}/manifest.json", $source_limits{max_manifest_bytes});
    _fail('Update source changed') unless sha256_hex($source_bytes) eq $source->{id};
    my $manifest = $json->decode($source_bytes);
    my $rendered = _read("$source->{directory}/rendered", $render_limit);
    _fail('Update render changed') unless sha256_hex($rendered) eq $manifest->{capture}{rendered}{sha256};
    my $compiled = _driver($rendered, { kind => 'update', raw => $selection }, $repeat);
    my $prefix = <<'PREFIX';
#!/bin/sh
if [ "$(uname -s)" = FreeBSD ]; then
    exec "$(dirname "$0")/xcatpackages.freebsd" "$@"
fi
PREFIX
    my %selected;
    for my $entry (@{$compiled->{entries}}) {
        my $name = _source_unhex($entry->{name});
        next unless $name eq 'ospkgs' || $name eq 'otherpkgs';
        my $key = _source_resolve($name, $manifest->{entries}, \%source_limits);
        my $file = $manifest->{entries}{$key};
        _fail('Package postscript is not a file') unless $file->{type} eq 'file';
        my $bytes = _read("$source->{directory}/blob-$file->{sha256}", $source_limits{max_file_bytes});
        _fail('Update package postscript changed') unless sha256_hex($bytes) eq $file->{sha256};
        next unless index($bytes, $prefix) == 0;
        my $adapter = _source_resolve('xcatpackages.freebsd', $manifest->{entries}, \%source_limits);
        # A custom native adapter must retain its own package behavior.
        next unless $manifest->{entries}{$adapter}{type} eq 'file'
          && $manifest->{entries}{$adapter}{sha256} eq 'a00a0aaaf992d227e09a0a3b73d73f80c224a00bca45c9260870a017f76460ba';
        my @words = shellwords(_source_unhex($entry->{raw}));
        _fail('FreeBSD package postscripts do not accept repository options') unless @words == 1;
        $selected{$name} = 1;
    }
    return 'all' if $selected{ospkgs} && $selected{otherpkgs};
    return 'base' if $selected{ospkgs};
    return 'applications' if $selected{otherpkgs};
    return;
}

sub _driver_entry {
    my ($raw, $phase, $section, $entries) = @_;
    _fail('Unusable postscript entry') if $raw =~ /[\x00\r\n]/x;
    my ($quote, $escaped) = ('', 0);
    my @characters = split(//x, $raw);
    for my $index (0 .. $#characters) {
        my $character = $characters[$index];
        if ($escaped) { $escaped = 0; next; }
        if ($quote eq q{'}) { $quote = '' if $character eq q{'}; next; }
        if ($character eq "\\") { $escaped = 1; next; }
        _fail('Postscript command substitution is unsupported')
          if $character eq q{`} || ($character eq '$' && ($characters[$index + 1] || '') eq '(');
        if ($quote eq q{"}) { $quote = '' if $character eq q{"}; next; }
        if ($character eq q{'} || $character eq q{"}) { $quote = $character; next; }
        _fail('Postscript shell operators are unsupported') if $character =~ /[;&|<>()]/x;
    }
    _fail('Incomplete postscript quoting') if length($quote) || $escaped;
    my @words = shellwords($raw);
    my $name = $words[0];
    _fail('Postscript requires a literal relative script name') unless defined($name)
      && $name =~ m{\A[A-Za-z0-9_./+-]+\z}x && $name !~ m{\A/}x;
    $name =~ s{\A[.]/}{}x;
    _fail('Invalid postscript path') if grep { !length($_) || $_ eq '.' || $_ eq '..' } split(m{/}x, $name, -1);
    my $number = @$entries + 1;
    _fail('Too many selected postscripts') if $number > 4096;
    push @$entries, { number => $number, phase => $phase, section => $section,
        name => _source_hex($name), raw => _source_hex($raw), sha256 => sha256_hex($raw) };
    return '/usr/local/libexec/xcat-postscript begin "$xcat_postscript_run" ' . $number . " || exit 125\n"
      . "xcat_postscript_entry $number $raw\n";
}

sub _driver {
    my ($rendered, $selection, $repeat) = @_;
    my $ranges = _markers($rendered);
    my ($selected) = _execution_selection($selection, \%execution_limits);
    _fail('Unusable postscript render') if $rendered =~ /\x00/x;
    my $kind = $selected->{kind};
    my $enabled = $kind ne 'repeat' || (defined($repeat) && $repeat =~ /\A(?:1|yes|y)\z/ix);
    my ($chosen_phase, $chosen_section, @explicit);
    $chosen_phase = 'postbootscripts' if $kind eq 'repeat';
    if ($kind eq 'update' && length($selection->{raw})) {
        my $raw = $selection->{raw};
        _fail('Unusable postscript selection') if $raw =~ /[\x00\r\n]/x;
        if (index($raw, 'start-here') >= 0) {
            $raw =~ s/\A[\#][ ]?//x;
            $raw =~ s/-start-here\z//x;
            my @parts = split(/-/x, $raw);
            $chosen_phase = pop @parts;
            $chosen_section = pop @parts;
            _fail('Unknown postscript section selector') if @parts || !defined($chosen_phase)
              || $chosen_phase !~ /\A(?:postscripts|postbootscripts)\z/x
              || (defined($chosen_section) && $chosen_section !~ /\A(?:defaults|osimage|node)\z/x);
        } else {
            @explicit = split(/,/x, $raw, -1);
            _fail('Empty explicit postscript entry') if grep { !/\S/x } @explicit;
        }
    }
    my @entries;
    my $driver = <<'DRIVER';
#!/bin/sh
xcat_postscript_run=$1
readonly xcat_postscript_run
shift
xcat_postscript_entry()
{
    /usr/local/libexec/xcat-postscript execute "$xcat_postscript_run" "$@" || exit 125
}
DRIVER
    my %edges;
    for my $range (@$ranges) {
        my @parts = split(/-/x, $range->{name});
        my $outer = pop @parts;
        my $inner = pop @parts;
        $edges{$range->{begin}} = [$outer, $inner, 1];
        $edges{$range->{end}} = [$outer, $inner, 0];
    }
    my $offset = 0;
    my ($phase, $section);
    for my $line (split(/(?<=\n)/x, $enabled ? $rendered : '')) {
        my $edge = $edges{$offset};
        $offset += length($line);
        if ($edge) {
            my ($outer, $inner, $start) = @$edge;
            if (defined($inner)) { $section = $start ? $inner : undef; }
            else { $phase = $start ? $outer : undef; }
            $driver .= $line;
            next;
        }
        if (!defined($phase)) {
            $line =~ s/\AUPDATENODE=0(?=\n|\z)/UPDATENODE=1/x if $kind eq 'update';
            $driver .= $line;
            next;
        }
        next if @explicit || (defined($chosen_phase) && $phase ne $chosen_phase)
          || (defined($chosen_section) && defined($section) && $section ne $chosen_section);
        if ($line =~ /\A\s*(?:[\#]|\z)/x) { $driver .= $line; next; }
        $line =~ s/\n\z//x;
        $driver .= _driver_entry($line, $phase, $section, \@entries);
    }
    $driver .= "\n" unless $driver =~ /\n\z/x;
    for my $raw (@explicit) {
        $driver .= _driver_entry($raw, 'postscripts', undef, \@entries);
    }
    $driver .= '/usr/local/libexec/xcat-postscript driver-complete "$xcat_postscript_run" ' . @entries . "\n";
    return { driver => $driver, entries => \@entries, enabled => $enabled ? 1 : 0 };
}

sub compile_execution {
    my ($id, @arguments) = @_;
    my $result = eval {
        my $root = _root(_options(@arguments), 0);
        my $prepared = _execution_descriptor($root, $id);
        my $manifest_bytes = _read("$root/$id/manifest.json", $execution_limits{max_manifest_bytes});
        _fail('Compilation preparation changed') unless sha256_hex($manifest_bytes) eq $id;
        my $manifest = $json->decode($manifest_bytes);
        my $context_bytes = _read("$root/$id/context.json", $execution_limits{max_context_bytes});
        my $context = $json->decode($context_bytes);
        my $raw = _read("$root/$id/selection", $execution_limits{max_selection_bytes});
        my $source = read_source($prepared->{source_id}, directory => $root);
        my $source_bytes = _read("$source->{directory}/manifest.json", $source_limits{max_manifest_bytes});
        _fail('Compilation source changed') unless sha256_hex($source_bytes) eq $source->{id};
        my $source_manifest = $json->decode($source_bytes);
        my $rendered = _read("$source->{directory}/rendered", $render_limit);
        _fail('Compilation inputs changed') unless sha256_hex($context_bytes) eq $manifest->{context}{sha256}
          && sha256_hex($raw) eq $manifest->{selection}{sha256}
          && sha256_hex($rendered) eq $source_manifest->{capture}{rendered}{sha256};
        my $compiled = _driver($rendered, { kind => $manifest->{selection}{kind},
            $manifest->{selection}{raw_present} ? (raw => $raw) : () }, $context->{repeat}{value});
        my $record = { kind => 'freebsd-postscript-driver-v1', preparation_id => $id,
            source_id => $prepared->{source_id}, enabled => $compiled->{enabled},
            driver => _execution_content($compiled->{driver}), entries => $compiled->{entries} };
        +{ %$compiled, manifest => $record, id => sha256_hex(_json($record) . "\n") };
    };
    _fail('FreeBSD postscript compilation failed') unless $result;
    return $result;
}

sub _export_binding {
    my $binding = shift;
    _source_fields($binding, qw(preparation run generation attempt package_mode entry_timeout run_timeout log_limit),
        exists($binding->{boot}) ? ('boot') : ());
    _fail('Invalid export boot identity') if exists($binding->{boot})
      && (!defined($binding->{boot}) || ref($binding->{boot}) || $binding->{boot} !~ /\A[0-9a-f]{64}\z/x);
    for my $key (qw(preparation run generation attempt)) {
        my $length = $key eq 'preparation' ? 64 : 32;
        _fail('Invalid export identity') unless defined($binding->{$key}) && !ref($binding->{$key})
          && $binding->{$key} =~ /\A[0-9a-f]{$length}\z/x;
    }
    _fail('Invalid export package operation') unless defined($binding->{package_mode}) && !ref($binding->{package_mode})
      && $binding->{package_mode} =~ /\A(?:verify|update)\z/x;
    for my $limit ([entry_timeout => 1, 1800], [run_timeout => 1, 7200], [log_limit => 4096, 1048576]) {
        my ($key, $minimum, $maximum) = @$limit;
        _source_number($binding->{$key}, $maximum);
        _fail('Export limit is too small') if $binding->{$key} < $minimum;
    }
    _fail('Invalid export log block size') if $binding->{log_limit} % 512;
    return;
}

sub _mtree_escape {
    my $bytes = shift;
    $bytes =~ s{([^A-Za-z0-9_./+-])}{sprintf('\\%03o', ord($1))}gex;
    return $bytes;
}

sub _export_tree {
    my ($source, $manifest, $destination) = @_;
    my $entries = $manifest->{entries};
    my $specification = '';
    for my $key (sort keys %$entries) {
        my $entry = { %{$entries->{$key}} };
        my $relative = _source_unhex($key);
        my $path = length($relative) ? "$destination/$relative" : $destination;
        my $type = $entry->{type};
        my $mode = $entry->{mode};
        _fail('Special source permissions prevent export') if $mode & oct('7000');
        if ($type eq 'directory') {
            mkdir($path, oct('0700')) or _fail('Cannot create exported source directory');
        } elsif ($entry->{group} ne $key) {
            link("$destination/" . _source_unhex($entry->{group}), $path)
              or _fail('Cannot create exported hard link');
        } elsif ($type eq 'link') {
            symlink(_source_unhex($entry->{target}), $path) or _fail('Cannot create exported source link');
        } else {
            my $bytes = _read("$source/blob-$entry->{sha256}", $source_limits{max_file_bytes});
            _fail('Exported source blob differs') unless length($bytes) == $entry->{bytes}
              && sha256_hex($bytes) eq $entry->{sha256};
            _write($path, $bytes, $source_limits{max_file_bytes});
        }
        my $name = length($relative) ? './' . _mtree_escape($relative) : '.';
        my %types = (directory => 'dir', file => 'file', link => 'link');
        $specification .= "$name type=$types{$type} uid=0 gid=0 mode=" . sprintf('%04o', $mode);
        $specification .= " nlink=$entry->{links}" unless $type eq 'directory';
        $specification .= " size=$entry->{bytes} sha256digest=$entry->{sha256}" if $type eq 'file';
        $specification .= ' link=' . _mtree_escape(_source_unhex($entry->{target})) if $type eq 'link';
        $specification .= "\n";
    }
    for my $key (reverse sort keys %$entries) {
        my $entry = $entries->{$key};
        my $relative = _source_unhex($key);
        my $path = length($relative) ? "$destination/$relative" : $destination;
        next if $entry->{type} eq 'link';
        chown(0, 0, $path) == 1 or _fail('Cannot set exported source owner');
        chmod($entry->{mode}, $path) == 1 or _fail('Cannot set exported source mode');
    }
    my $template = $manifest->{template};
    my $context = { root => _source_hex($destination), kind => $template->{kind},
        resolved => _source_hex($template->{kind} eq 'stock'
            ? "$source/blob-$template->{file}{sha256}"
            : "$destination/" . _source_unhex($template->{member})) };
    my $observed = _source_tree($context, $manifest->{limits}, undef);
    my %expected = map { $_ => { %{$entries->{$_}}, uid => 0, gid => 0 } } keys %$entries;
    _fail('Exported source metadata or content differs') unless _json($observed->{entries}) eq _json(\%expected);
    return $specification;
}

sub _export_retirement_bytes {
    my ($root, $run, $manifest_bytes, $export) = @_;
    my $bytes = _read("$root/delivery-$run.result", 4096);
    my $receipt = _delivery_receipt($bytes, $export);
    _fail('Only committed terminal exports can be retired')
      unless $receipt->{format} =~ /\Axcat-freebsd-postscript-result-[13]\z/x && $receipt->{complete} eq 'yes';
    return _json({ kind => 'freebsd-postscript-export-retirement-v1', run => $run,
        manifest => sha256_hex($manifest_bytes), receipt => sha256_hex($bytes) }) . "\n";
}

sub _export_archive {
    my ($root, $run, $manifest_bytes, $manifest, $observing) = @_;
    my $path = "$root/export-$run";
    my $retired = lstat("$root/export-$run.retired");
    if ($retired) {
        _fail('Export retirement differs') unless _read("$root/export-$run.retired", 1024)
          eq _export_retirement_bytes($root, $run, $manifest_bytes, $manifest);
    }
    my $present = lstat("$path/bundle.tar");
    _fail('Export archive is missing without retirement') unless $present || $retired;
    my $admitted;
    if ($observing && !$retired && lstat("$root/delivery-$run.admitted")) {
        $admitted = _delivery_status(_read("$root/delivery-$run.admitted", 4096), $manifest);
        _fail('Retained admission is incomplete') unless $admitted->{state} eq 'admitted';
    }
    if ($present) {
        if ($admitted) {
            # Observation uses the already verified node copy. Hash the local
            # payload again when retiring it, before deleting any bytes.
            my $state = _file_state("$path/bundle.tar", 68987912192);
            _fail('Export archive size differs') if $state->[7] != $manifest->{archive}{bytes};
        } else {
            my $archive = _read("$path/bundle.tar", 68987912192, 1);
            _fail('Export archive differs') unless _json($manifest->{archive}) eq _json($archive);
        }
    }
    opendir(my $directory, $path) or _fail('Cannot inspect export members');
    my @members = sort grep { $_ ne '.' && $_ ne '..' } readdir($directory);
    closedir($directory) or _fail('Cannot close export members');
    my @expected = ($present ? ('bundle.tar') : (), 'manifest.json');
    _fail('Unexpected export member') unless _json(\@members) eq _json(\@expected);
    return { %{$manifest->{archive}}, path => "$path/bundle.tar" };
}

sub _export_descriptor {
    my ($root, $run, $observing) = @_;
    _fail('Invalid export run') unless defined($run) && !ref($run) && $run =~ /\A[0-9a-f]{32}\z/x;
    my $path = "$root/export-$run";
    _directory($path, 0);
    my $record = _read("$path/manifest.json", 16384);
    my $manifest = $json->decode($record);
    _source_fields($manifest, qw(kind binding node source snapshot scripts archive));
    _export_binding($manifest->{binding});
    _fail('Export run binding differs') unless $manifest->{binding}{run} eq $run
      && $manifest->{kind} eq 'freebsd-postscript-export-v1';
    _capture_request($manifest->{node}, 'install');
    for my $key (qw(source snapshot)) {
        _fail('Invalid export digest') unless defined($manifest->{$key}) && !ref($manifest->{$key})
          && $manifest->{$key} =~ /\A[0-9a-f]{64}\z/x;
    }
    _source_number($manifest->{scripts}, 4096);
    _source_fields($manifest->{archive}, qw(bytes sha256));
    _source_number($manifest->{archive}{bytes}, 68987912192);
    _fail('Invalid export archive identity') if $manifest->{archive}{bytes} < 1024
      || $manifest->{archive}{bytes} % 512 || !defined($manifest->{archive}{sha256})
      || ref($manifest->{archive}{sha256}) || $manifest->{archive}{sha256} !~ /\A[0-9a-f]{64}\z/x;
    _fail('Export manifest is not canonical') unless $record eq _json($manifest) . "\n";
    return { %$manifest, archive => _export_archive($root, $run, $record, $manifest, $observing) };
}

sub _retire_export {
    my ($root, $run, $export, $receipt) = @_;
    return unless $receipt->{format} =~ /\Axcat-freebsd-postscript-result-[13]\z/x && $receipt->{complete} eq 'yes';
    my $manifest_bytes = _read("$root/export-$run/manifest.json", 16384);
    my $bytes = _export_retirement_bytes($root, $run, $manifest_bytes, $export);
    my $path = "$root/export-$run.retired";
    if (lstat($path)) {
        _fail('Export retirement differs') unless _read($path, 1024) eq $bytes;
    } else {
        if (lstat("$path.next")) {
            _fail('Staged export retirement differs') unless _read("$path.next", 1024) eq $bytes;
            unlink("$path.next") or _fail('Cannot replace staged export retirement');
        }
        _write("$path.next", $bytes, 1024);
        rename("$path.next", $path) or _fail('Cannot publish export retirement');
    }
    _sync_directory($root);
    if (lstat($export->{archive}{path})) {
        my $archive = _read($export->{archive}{path}, 68987912192, 1);
        _fail('Retiring export archive differs') unless $archive->{sha256} eq $export->{archive}{sha256}
          && $archive->{bytes} == $export->{archive}{bytes};
        unlink($export->{archive}{path}) or _fail('Cannot retire export archive');
    }
    _sync_directory("$root/export-$run");
    return;
}

sub read_export {
    my ($run, @arguments) = @_;
    my $result = eval { _export_descriptor(_root(_options(@arguments), 0), $run); };
    _fail('FreeBSD postscript export verification failed') unless $result;
    return $result;
}

sub export_execution {
    my ($id, @arguments) = @_;
    my ($result, $attempt);
    my $phase = 'request';
    my $ok = eval {
        _fail('Export requires Linux root') unless $^O eq 'linux' && $> == 0;
        _fail('Export options must be unique pairs') if @arguments % 2;
        my %options = @arguments;
        _fail('Duplicate export option') unless keys(%options) == @arguments / 2;
        my %binding = (preparation => $id, package_mode => 'verify',
            entry_timeout => 300, run_timeout => 3600, log_limit => 1048576);
        for my $key (qw(run generation attempt boot package_mode entry_timeout run_timeout log_limit)) {
            $binding{$key} = delete $options{$key} if exists($options{$key});
        }
        _export_binding(\%binding);
        my $root = _root(_options(%options), 0);
        my $run = $binding{run};
        my $lock_path = "$root/export-$run.lock";
        sysopen(my $lock, $lock_path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
          or _fail('Cannot open export run lock');
        my $named = _file_state($lock_path, 0);
        my @opened = stat($lock);
        _fail('Export lock changed') unless @opened && $opened[0] == $named->[0] && $opened[1] == $named->[1];
        flock($lock, LOCK_EX | LOCK_NB) or _fail('Export run is busy');
        if (lstat("$root/export-$run")) {
            $result = _export_descriptor($root, $run);
            _fail('Export run already binds different inputs') unless _json($result->{binding}) eq _json(\%binding);
        } else {
            $phase = 'preparation';
            my $prepared = _execution_descriptor($root, $id);
            my $compiled = compile_execution($id, directory => $root);
            my $selection_bytes = _read("$root/$id/manifest.json", $execution_limits{max_manifest_bytes});
            _fail('Export preparation changed') unless sha256_hex($selection_bytes) eq $id;
            my $selection = $json->decode($selection_bytes);
            my $kind = $selection->{selection}{kind};
            _fail('Package update requires an update run') if $binding{package_mode} eq 'update' && $kind ne 'update';
            _fail('Boot binding requires a boot selection and package verification')
              if exists($binding{boot}) && ($kind eq 'update' || $binding{package_mode} ne 'verify');
            my $current_packages = exists($binding{boot}) && $kind eq 'repeat';
            my $source = "$root/$prepared->{source_id}";
            my $source_bytes = _read("$source/manifest.json", $source_limits{max_manifest_bytes});
            _fail('Export source changed') unless sha256_hex($source_bytes) eq $prepared->{source_id};
            my $source_manifest = $json->decode($source_bytes);
            my $entries = '';
            for my $entry (@{$compiled->{entries}}) {
                my $name = _source_unhex($entry->{name});
                my $resolved = _source_resolve($name, $source_manifest->{entries}, $source_manifest->{limits});
                my $file = $source_manifest->{entries}{$resolved};
                _fail('Selected postscript is not executable') unless $file->{type} eq 'file' && ($file->{mode} & oct('0111'));
                $entries .= join("\t", $entry->{number}, $entry->{phase}, $entry->{sha256}, $file->{sha256}, $name) . "\n";
            }
            $attempt = tempdir('.export-attempt.XXXXXXXX', DIR => $root, CLEANUP => 0);
            my $content = "$attempt/content";
            my $output = "$attempt/output";
            mkdir($content, oct('0700')) && mkdir($output, oct('0700')) or _fail('Cannot create export stage');
            $phase = 'source tree';
            my $tree = _export_tree($source, $source_manifest, "$content/tree");
            _write("$content/tree.mtree", $tree, $source_limits{max_manifest_bytes});
            _write("$content/driver", $compiled->{driver}, $render_limit);
            _write("$content/entries", $entries, 1048576);
            my $plan = _read("$root/$id/package.plan", $execution_limits{max_plan_bytes});
            my $digest = sha256_hex($plan);
            _fail('Export package binding changed') unless $digest eq $prepared->{package_plan_sha256};
            my $request = "format\txcat-freebsd-local-request-1\nplan\t$digest\n"
              . ($current_packages ? '' : join('', grep { /\Apackage\t/x } split(/(?<=\n)/x, $plan)));
            _write("$content/package.plan", $plan, $execution_limits{max_plan_bytes});
            $phase = 'package payload';
            my $context_bytes = _read("$root/$id/context.json", $execution_limits{max_context_bytes});
            _fail('Export context changed') unless sha256_hex($context_bytes) eq $selection->{context}{sha256};
            my $context = $json->decode($context_bytes);
            mkdir("$content/archives", oct('0700')) or _fail('Cannot create archive stage');
            if ($current_packages) {
                chmod(oct('0500'), "$content/archives") == 1 or _fail('Cannot protect empty package payload');
            } elsif ($binding{package_mode} eq 'verify') {
                my $staged = xCAT::FreeBSDPackagePlan::stage_manifests($plan, $context->{installroot}, "$content/archives");
                $request = $staged->{request};
            } else {
                xCAT::FreeBSDPackagePlan::stage_archives($plan, $context->{installroot}, "$content/archives");
            }
            _write("$content/request", $request, 8388608);
            my @fields = ([format => exists($binding{boot}) ? 'xcat-freebsd-postscript-bundle-3'
                : 'xcat-freebsd-postscript-bundle-2'], [run => $run], [node => $prepared->{node}],
                [generation => $binding{generation}], [attempt => $binding{attempt}], [kind => $kind],
                [preparation => $id], [source => $prepared->{source_id}], [plan => $digest],
                [request => sha256_hex($request)], ['package-mode' => $binding{package_mode}],
                [driver => sha256_hex($compiled->{driver})], [entries => sha256_hex($entries)], [tree => sha256_hex($tree)],
                [scripts => scalar(@{$compiled->{entries}})], ['entry-timeout' => $binding{entry_timeout}],
                ['run-timeout' => $binding{run_timeout}], ['log-limit' => $binding{log_limit}]);
            push @fields, [boot => $binding{boot}] if exists($binding{boot});
            my $manifest = join('', map { join("\t", @$_) . "\n" } @fields);
            _write("$content/manifest", $manifest, 8192);
            $phase = 'archive';
            my $command = xCAT::FreeBSDPkg::run_command(['/bin/tar', '--format=pax', '--sort=name',
                '--pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime', '--mtime=@0',
                '--owner=0', '--group=0', '--numeric-owner', '-cpf', "$output/bundle.tar", '-C', $content, '.'],
                cwd => $attempt, environment => { PATH => '/usr/bin:/bin', LC_ALL => 'C' }, timeout => 600);
            _fail('Cannot create export archive') if $command->{exitcode} || $command->{signal};
            chmod(oct('0400'), "$output/bundle.tar") == 1 or _fail('Cannot protect export archive');
            sysopen(my $archive, "$output/bundle.tar", O_RDONLY | O_NOFOLLOW) or _fail('Cannot open export archive');
            $archive->sync or _fail('Cannot sync export archive');
            close($archive) or _fail('Cannot close export archive');
            my $record = { kind => 'freebsd-postscript-export-v1', binding => \%binding, node => $prepared->{node},
                source => $prepared->{source_id}, snapshot => sha256_hex($manifest), scripts => scalar(@{$compiled->{entries}}),
                archive => _read("$output/bundle.tar", 68987912192, 1) };
            _write("$output/manifest.json", _json($record) . "\n", 16384);
            _sync_directory($output);
            $phase = 'publication';
            rename($output, "$root/export-$run") or _fail('Cannot publish export');
            _sync_directory($attempt);
            _sync_directory($root);
            $result = _export_descriptor($root, $run);
        }
        close($lock) or _fail('Cannot close export run lock');
        1;
    };
    if (defined($attempt)) {
        _discard_stage("$attempt/$_") for grep { lstat("$attempt/$_") } qw(content output);
        _discard_attempt($attempt) if $ok;
    }
    unless ($ok) {
        eval { _write("$attempt/failure", "$phase\n", 128); } if defined($attempt);
        _fail("FreeBSD postscript export failed during $phase");
    }
    return $result;
}

sub _delivery_fields {
    my ($bytes, @names) = @_;
    _fail('Invalid delivery response') if !defined($bytes) || ref($bytes)
      || length($bytes) > 4096 || $bytes !~ /\n\z/x;
    my @lines = split(/\n/x, $bytes);
    _fail('Unexpected delivery fields') unless @lines == @names;
    my %fields;
    for my $name (@names) {
        my $line = shift @lines;
        my ($value) = $line =~ /\A\Q$name\E\t([^\x00-\x20\x7f-\xff]+)\z/x;
        _fail('Invalid delivery field') unless defined($value);
        $fields{$name} = $value;
    }
    return \%fields;
}

sub _delivery_status {
    my ($bytes, $export) = @_;
    my $status = _delivery_fields($bytes, qw(format run snapshot archive-sha256 archive-bytes state path));
    my $run = $export->{binding}{run};
    _fail('Delivery response differs') unless $status->{format} eq 'xcat-freebsd-postscript-delivery-status-1'
      && $status->{run} eq $run && $status->{snapshot} eq $export->{snapshot}
      && $status->{'archive-sha256'} eq $export->{archive}{sha256}
      && $status->{'archive-bytes'} eq $export->{archive}{bytes}
      && $status->{state} =~ /\A(?:upload|admitted)\z/x
      && $status->{path} eq ($status->{state} eq 'upload'
        ? "/var/db/xcat/postscripts/incoming/$run.delivery/bundle.tar" : '-');
    return $status;
}

sub _delivery_sync_receipt {
    my ($receipt, $export) = @_;
    _fail('Invalid synchronization receipt') unless $receipt->{complete} eq 'no'
      && $receipt->{outcome} eq 'pending';
    for my $bound (['sync-ordinal' => $export->{scripts}], ['sync-timeout' => $export->{binding}{entry_timeout}]) {
        my ($key, $maximum) = @$bound;
        _source_number($receipt->{$key}, $maximum);
        _fail('Invalid synchronization receipt bound') if $receipt->{$key} == 0;
    }
    return;
}

sub _delivery_terminal_receipt {
    my ($receipt, $export) = @_;
    _fail('Terminal receipt context differs') unless $receipt->{node} eq $export->{node}
      && $receipt->{generation} eq $export->{binding}{generation}
      && $receipt->{attempt} eq $export->{binding}{attempt}
      && $receipt->{entries} eq $export->{scripts} && $receipt->{complete} eq 'yes'
      && $receipt->{outcome} =~ /\A(?:success|failed)\z/x;
    for my $key (qw(plan results-sha256 packages-sha256 stdout-sha256 stderr-sha256)) {
        _fail('Invalid receipt digest') unless $receipt->{$key} =~ /\A[0-9a-f]{64}\z/x;
    }
    if ($receipt->{format} eq 'xcat-freebsd-postscript-result-3') {
        _fail('Invalid failure inventory digest') unless $receipt->{'inventory-sha256'} =~ /\A[0-9a-f]{64}\z/x;
    }
    _fail('Failed run claims success') if $receipt->{format} =~ /\Axcat-freebsd-postscript-result-[23]\z/x
      && $receipt->{outcome} ne 'failed';
    return;
}

sub _delivery_receipt {
    my ($bytes, $export) = @_;
    my @fields = $bytes =~ /\Aformat\txcat-freebsd-postscript-result-[123]\n/x
      ? qw(format run node generation attempt snapshot plan entries results-sha256 packages-sha256 stdout-sha256 stderr-sha256 outcome complete)
      : qw(format run snapshot outcome complete);
    splice(@fields, -2, 0, 'inventory-sha256') if $bytes =~ /\Aformat\txcat-freebsd-postscript-result-3\n/x;
    push @fields, qw(sync-ordinal sync-timeout) if $bytes =~ /\Aformat\txcat-freebsd-postscript-status-2\n/x;
    my $receipt = _delivery_fields($bytes, @fields);
    _fail('Receipt identity differs') unless $receipt->{run} eq $export->{binding}{run}
      && $receipt->{snapshot} eq $export->{snapshot};
    if ($receipt->{format} =~ /\Axcat-freebsd-postscript-result-[123]\z/x) {
        _delivery_terminal_receipt($receipt, $export);
    } elsif ($receipt->{format} eq 'xcat-freebsd-postscript-status-2') {
        _delivery_sync_receipt($receipt, $export);
    } elsif ($receipt->{format} eq 'xcat-freebsd-postscript-status-3') {
        _fail('Invalid busy receipt') unless $receipt->{complete} eq 'no' && $receipt->{outcome} eq 'busy';
    } else {
        _fail('Invalid pending receipt') unless $receipt->{format} eq 'xcat-freebsd-postscript-status-1'
          && $receipt->{complete} eq 'no' && $receipt->{outcome} =~ /\A(?:admitted|pending|uncertain)\z/x;
    }
    return $receipt;
}

sub _delivery_lines {
    my ($value, $node, $state) = @_;
    for my $line (split(/\n/x, $value)) {
        next unless length($line);
        _fail('Transport node differs') unless $line =~ s/\A\Q$node\E:[ ]//x;
        if ($line eq 'Remote_command_successful') { ++$state->{successful}; }
        elsif ($line =~ /\ARemote_command_failed(?:,|\z)/x) { $state->{failed} = 1; }
        else { push @{$state->{lines}}, $line; }
    }
    return;
}

sub _delivery_response {
    my ($response, $node, $state) = @_;
    _fail('Invalid transport response') unless ref($response) eq 'HASH';
    my $bytes = _json($response);
    $state->{size} += length($bytes) + 1;
    _fail('Transport response exceeds its limit') if $state->{size} > 1048576;
    push @{$state->{responses}}, $bytes;
    for my $key (keys %$response) {
        next if $key eq 'NoErrorPrefix' || $key eq 'xcatdsource' || $key eq 'serverdone';
        _fail('Unexpected transport response') unless $key =~ /\A(?:data|info|sinfo|status|error|errorcode)\z/x;
        my $values = $response->{$key};
        $values = [$values] if $key eq 'errorcode' && !ref($values);
        _fail('Invalid transport response values') unless ref($values) eq 'ARRAY';
        for my $value (@$values) {
            if (!defined($value)) {
                _fail('Missing transport status') if $key eq 'errorcode';
                next;
            }
            _fail('Invalid transport value') if ref($value);
            if ($key eq 'errorcode') { $state->{failed} = 1 unless $value =~ /\A0\z/x; }
            elsif ($key eq 'error') { $state->{failed} = 1 if length($value); }
            else { _delivery_lines($value, $node, $state); }
        }
    }
    return;
}

sub _delivery_command {
    my ($transport, $command, $arguments) = @_;
    my $node = $transport->{export}{node};
    my $prefix = "$transport->{attempt}/$transport->{phase}";
    my $timeout = $transport->{timeout} || 600;
    my $request = { command => [$command], node => [$node], arg => ['--nodestatus', '-t', "$timeout", @$arguments] };
    $request->{_xcatpreprocessed} = [1] if $command eq 'xdsh';
    $request->{username} = $transport->{username} if defined($transport->{username});
    $request->{env} = $transport->{environment} if defined($transport->{environment});
    _write("$prefix.request.json", _json($request) . "\n", 16384);
    my $state = { size => 0, successful => 0, failed => 0, lines => [], responses => [] };
    my $completed = eval {
        $transport->{subrequest}->($request, sub { _delivery_response(shift, $node, $state); });
        1;
    };
    my $error = substr($@, 0, 8192);
    _write("$prefix.responses.json", '[' . join(',', @{$state->{responses}}) . "]\n", 1048578);
    if (!$completed || $state->{failed}
      || ($transport->{multiple} ? !$state->{successful} : $state->{successful} != 1)) {
        _sync_directory($transport->{attempt});
        _fail("Transport command did not complete; responses: $prefix.responses.json\n$error");
    }
    return @{$state->{lines}} ? join("\n", @{$state->{lines}}) . "\n" : '';
}

sub sync_files {
    my ($node, $subrequest, $timeout, @arguments) = @_;
    require xCAT::SvrUtils;
    _capture_request($node, undef);
    _fail('File synchronization requires a subrequest') unless ref($subrequest) eq 'CODE';
    _source_number($timeout, 7200);
    _fail('Invalid file synchronization timeout') unless $timeout;
    my ($options, $username) = _delivery_options(@arguments);
    my $root = _root($options, 1);
    my $selected = xCAT::SvrUtils->getsynclistfile([$node]);
    _fail('Cannot resolve file synchronization lists') unless ref($selected) eq 'HASH';
    my $raw = $selected->{$node};
    _fail('Invalid file synchronization selection') if defined($raw) && ref($raw);
    my @paths = defined($raw) && length($raw) ? split(/,/x, $raw, -1) : ();
    _fail('Too many file synchronization lists') if @paths > $source_limits{max_entries};
    my $stage = tempdir("sync-$node-XXXXXXXX", DIR => $root, CLEANUP => 0);
    _directory($stage, 0);
    my (@lists, @output);
    my $total = 0;
    for my $path (@paths) {
        _source_path(dirname($path));
        my $content = _source_file($path, $source_limits{max_file_bytes}, $stage);
        $total += $content->{bytes};
        _fail('File synchronization lists exceed their bound') if $total > $source_limits{max_bytes};
        push @lists, { path => _source_hex($path), %$content };
    }
    my $selection = { node => $node, lists => \@lists };
    _write("$stage/selection.json", _json($selection) . "\n", $source_limits{max_manifest_bytes});
    _sync_directory($stage);
    _sync_directory($root);
    my $transport = { attempt => $stage, export => { node => $node },
        subrequest => $subrequest, username => $username, timeout => $timeout, multiple => 1 };
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + $timeout;
    my $ok = eval {
        for my $index (0 .. $#lists) {
            my $remaining = $deadline - clock_gettime(CLOCK_MONOTONIC);
            _fail('File synchronization timed out') if $remaining <= 0;
            $transport->{timeout} = ceil($remaining);
            my $list = $lists[$index];
            my $frozen = "$stage/blob-$list->{sha256}";
            _fail('Frozen synchronization list changed') unless sha256_hex(_read($frozen, $source_limits{max_file_bytes}))
              eq $list->{sha256};
            $transport->{phase} = 'list-' . ($index + 1);
            $transport->{environment} = ["DSH_RSYNC_FILE=$frozen"];
            push @output, _delivery_command($transport, 'xdcp',
                ['-F', $frozen, '-o', '--rsync-path=/usr/local/bin/rsync']);
        }
        1;
    };
    my $error = $@;
    _write("$stage/result.json", _json({ complete => $ok ? 1 : 0,
        lists => scalar(@lists), completed => scalar(@output) }) . "\n", 4096);
    _sync_directory($stage);
    _fail("File synchronization failed: $error Evidence: $stage") unless $ok;
    return { directory => $stage, lists => scalar(@lists), output => \@output };
}

sub _retain_boot_observation {
    my ($root, $stage, $node, $bytes) = @_;
    my $retained = "$root/boot-$node-" . sha256_hex($bytes);
    unless (rename($stage, $retained)) {
        _directory($retained, 0);
        _fail('Retained boot observation differs') unless _read("$retained/context", 4096) eq $bytes;
        _discard_attempt($stage);
    }
    _sync_directory($root);
    return $retained;
}

sub observe_boot {
    my ($node, $generation, $attempt, $run, $subrequest, @arguments) = @_;
    _capture_request($node, 'install');
    _fail('Boot observation requires a subrequest') unless ref($subrequest) eq 'CODE';
    for my $identity ($generation, $attempt) {
        _fail('Invalid boot deployment identity') unless defined($identity) && !ref($identity)
          && $identity =~ /\A[0-9a-f]{32}\z/x;
    }
    _fail('Invalid observed run') unless defined($run) && !ref($run)
      && $run =~ /\A(?:-|[0-9a-f]{32})\z/x;
    my ($options, $username) = _delivery_options(@arguments);
    my $root = _root($options, 1);
    my $stage = tempdir(".boot-$node.XXXXXXXX", DIR => $root, CLEANUP => 0);
    _directory($stage, 0);
    _sync_directory($root);
    my $transport = { export => { node => $node }, attempt => $stage,
        subrequest => $subrequest, username => $username, timeout => 20, phase => 'context' };
    my $command = join(' ', '/usr/local/libexec/xcat-postscript', 'boot-context', $generation, $attempt, $run);
    my $bytes = _delivery_command($transport, 'xdsh', [$command]);
    my $context = _delivery_fields($bytes, qw(format node generation attempt boot run snapshot run-boot outcome complete released));
    _fail('Boot observation deployment differs') unless $context->{format} eq 'xcat-freebsd-boot-context-1'
      && $context->{node} eq $node && $context->{generation} eq $generation && $context->{attempt} eq $attempt
      && $context->{run} eq $run && $context->{boot} =~ /\A[0-9a-f]{64}\z/x;
    _fail('Invalid boot observation outcome') unless $context->{outcome} =~ /\A(?:absent|incomplete|admitted|pending|uncertain|success|failed)\z/x
      && $context->{complete} eq ($context->{outcome} =~ /\A(?:success|failed)\z/x ? 'yes' : 'no')
      && $context->{released} =~ /\A(?:yes|no)\z/x
      && ($context->{released} eq 'no' || $context->{outcome} eq 'uncertain');
    if ($context->{outcome} eq 'absent' || $context->{outcome} eq 'incomplete') {
        _fail('Invalid absent boot observation') unless $context->{snapshot} eq '-'
          && $context->{'run-boot'} eq '-' && $context->{released} eq 'no'
          && ($run ne '-' || $context->{outcome} eq 'absent');
    } else {
        _fail('Invalid observed run binding') unless $run ne '-'
          && $context->{snapshot} =~ /\A[0-9a-f]{64}\z/x && $context->{'run-boot'} =~ /\A[0-9a-f]{64}\z/x;
        _fail('Invalid active boot observation') if $context->{outcome} eq 'pending'
          && $context->{'run-boot'} ne $context->{boot};
    }
    _write("$stage/context", $bytes, 4096);
    _sync_directory($stage);
    return { %$context, directory => _retain_boot_observation($root, $stage, $node, $bytes) };
}

sub _delivery_sync_copy {
    my ($transport, $receipt, $result) = @_;
    my $ok = eval {
        my $timeout = $receipt->{'sync-timeout'} - 2;
        _fail('Synchronization entry deadline expired') if $timeout <= 0;
        my $copied = sync_files($transport->{export}{node}, $transport->{subrequest}, $timeout,
            directory => $transport->{root}, username => $transport->{username});
        $result->{directory} = $copied->{directory};
        $result->{lists} = $copied->{lists};
        1;
    };
    $result->{outcome} = $ok ? 'success' : 'failed';
    $result->{status} = $ok ? 0 : 1;
    $result->{error} = substr($@, 0, 8192) unless $ok;
    return;
}

sub _delivery_sync_result {
    my ($bytes, $identity) = @_;
    my $result = decode_json($bytes);
    _fail('Invalid retained synchronization result') unless ref($result) eq 'HASH';
    for my $key (keys %$identity, qw(outcome status)) {
        _fail('Invalid retained synchronization value') if !defined($result->{$key}) || ref($result->{$key});
    }
    _fail('Retained synchronization identity differs') if grep { $result->{$_} ne $identity->{$_} } keys %$identity;
    _fail('Invalid retained synchronization outcome') unless $result->{outcome} =~ /\A(?:success|failed|uncertain)\z/x
      && $result->{status} eq ($result->{outcome} eq 'success' ? '0' : '1');
    return $result;
}

sub _delivery_sync {
    my ($transport, $receipt, $remote) = @_;
    my $export = $transport->{export};
    my $run = $export->{binding}{run};
    my $ordinal = $receipt->{'sync-ordinal'};
    my $prefix = "$transport->{root}/delivery-$run.sync-$ordinal";
    my $identity = { format => 'freebsd-postscript-sync-v1', run => $run,
        snapshot => $export->{snapshot}, ordinal => 0 + $ordinal };
    my $intent = _json($identity) . "\n";
    $transport->{phase} = 'synchronization';
    my $result_path = "$prefix.result";
    unless (lstat($result_path)) {
        my $result = { %$identity, outcome => 'uncertain', status => 1 };
        if (lstat("$prefix.intent")) {
            _fail('Synchronization intent differs') unless _read("$prefix.intent", 4096) eq $intent;
        } else {
            _write("$prefix.intent", $intent, 4096);
            _sync_directory($transport->{root});
            _delivery_sync_copy($transport, $receipt, $result);
        }
        my $pending = "$transport->{attempt}/sync-result";
        _write($pending, _json($result) . "\n", 16384);
        _sync_directory($transport->{attempt});
        rename($pending, $result_path) or _fail('Cannot publish synchronization result');
        _sync_directory($transport->{attempt});
        _sync_directory($transport->{root});
    }
    _fail('Synchronization intent differs') unless _read("$prefix.intent", 4096) eq $intent;
    my $bytes = _read($result_path, 16384);
    my $result = _delivery_sync_result($bytes, $identity);
    $transport->{phase} = 'synchronization acknowledgement';
    my $output = $remote->('sync-result', $run, $export->{snapshot}, $ordinal, $result->{status}, sha256_hex($bytes));
    _fail('Unexpected synchronization acknowledgement') if length($output);
    return;
}

sub _delivery_archive {
    my ($transport, $remote) = @_;
    my $export = $transport->{export};
    my $run = $export->{binding}{run};
    my $admitted = "$transport->{root}/delivery-$run.admitted";
    $transport->{phase} = 'admission readback';
    if (lstat($admitted)) {
        my $status = _delivery_status(_read($admitted, 4096), $export);
        _fail('Retained admission is incomplete') unless $status->{state} eq 'admitted';
        _sync_directory($transport->{root});
        return;
    }
    my @identity = ($run, $export->{snapshot}, $export->{archive}{sha256}, $export->{archive}{bytes});
    $transport->{phase} = 'delivery';
    my $bytes = $remote->('delivery', @identity);
    return _delivery_receipt($bytes, $export) if $bytes =~ /\Aformat\txcat-freebsd-postscript-status-3\n/x;
    my $delivery = _delivery_status($bytes, $export);
    if ($delivery->{state} eq 'upload') {
        $transport->{phase} = 'transfer';
        my $output = _delivery_command($transport, 'xdcp', [$export->{archive}{path}, $delivery->{path}]);
        _fail('Unexpected transfer output') if length($output);
        $transport->{phase} = 'receive';
        $bytes = $remote->('receive', @identity);
        return _delivery_receipt($bytes, $export) if $bytes =~ /\Aformat\txcat-freebsd-postscript-status-3\n/x;
        $delivery = _delivery_status($bytes, $export);
        _fail('Reception did not admit the bundle') unless $delivery->{state} eq 'admitted';
    }
    $transport->{phase} = 'admission publication';
    _write("$transport->{attempt}/admitted", $bytes, 4096);
    _sync_directory($transport->{attempt});
    rename("$transport->{attempt}/admitted", $admitted) or _fail('Cannot publish delivery admission');
    _sync_directory($transport->{attempt});
    _sync_directory($transport->{root});
    return;
}

sub _delivery_attempt {
    my $transport = shift;
    my $export = $transport->{export};
    my $run = $export->{binding}{run};
    my $remote = sub {
        return _delivery_command($transport, 'xdsh', [join(' ', '/usr/local/libexec/xcat-postscript', @_)]);
    };
    my $waiting = _delivery_archive($transport, $remote);
    return $waiting if defined($waiting);
    $transport->{phase} = 'receipt';
    my $bytes = $remote->('receipt', $run);
    my $result = _delivery_receipt($bytes, $export);
    if ($result->{outcome} eq 'admitted') {
        $transport->{phase} = 'start';
        my $started = $remote->('start', $run);
        if (length($started)) {
            my $observed = _delivery_receipt($started, $export);
            return $observed if $observed->{outcome} eq 'busy';
        }
        $transport->{phase} = 'started-receipt';
        $bytes = $remote->('receipt', $run);
        $result = _delivery_receipt($bytes, $export);
    }
    if (exists($result->{'sync-ordinal'})) {
        _delivery_sync($transport, $result, $remote);
        $transport->{phase} = 'synchronized-receipt';
        $bytes = $remote->('receipt', $run);
        $result = _delivery_receipt($bytes, $export);
    }
    $transport->{phase} = 'receipt publication';
    _write("$transport->{attempt}/receipt", $bytes, 4096);
    _sync_directory($transport->{attempt});
    if ($result->{complete} eq 'yes') {
        rename("$transport->{attempt}/receipt", $transport->{terminal}) or _fail('Cannot publish delivery receipt');
        _sync_directory($transport->{attempt});
        _sync_directory($transport->{root});
    }
    return $result;
}

sub _delivery_options {
    my @arguments = @_;
    _fail('Delivery options must be unique pairs') if @arguments % 2;
    my %options = @arguments;
    _fail('Duplicate delivery option') unless keys(%options) == @arguments / 2;
    my $username = delete $options{username};
    _fail('Invalid delivery username') if defined($username) && (ref($username) ne 'ARRAY'
      || @$username != 1 || !defined($username->[0]) || ref($username->[0])
      || $username->[0] !~ /\A[A-Za-z0-9_.@-]{1,255}\z/x);
    _fail('Unknown delivery option') if grep { $_ ne 'directory' } keys %options;
    return (_options(%options), $username);
}

sub deliver_execution {
    my ($run, $subrequest, @arguments) = @_;
    my ($result, $attempt);
    my $transport = { phase => 'request', subrequest => $subrequest };
    my $ok = eval {
        _fail('Delivery requires a subrequest') unless ref($subrequest) eq 'CODE';
        my ($options, $username) = _delivery_options(@arguments);
        my $root = _root($options, 0);
        _fail('Unsupported delivery path') unless $root =~ m{\A/[A-Za-z0-9_./-]+\z}x;
        my $export = _export_descriptor($root, $run, 1);
        my $lock_path = "$root/delivery-$run.lock";
        sysopen(my $lock, $lock_path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
          or _fail('Cannot open delivery lock');
        my $named = _file_state($lock_path, 0);
        my @opened = stat($lock);
        _fail('Delivery lock changed') unless @opened && $opened[0] == $named->[0] && $opened[1] == $named->[1];
        flock($lock, LOCK_EX | LOCK_NB) or _fail('Delivery is busy');
        my $terminal = "$root/delivery-$run.result";
        if (lstat($terminal)) {
            $result = _delivery_receipt(_read($terminal, 4096), $export);
            _fail('Retained receipt is incomplete') unless $result->{complete} eq 'yes';
            _sync_directory($root);
        } else {
            $attempt = tempdir(".delivery-$run.XXXXXXXX", DIR => $root, CLEANUP => 0);
            _directory($attempt, 0);
            _sync_directory($root);
            _write("$attempt/export.json", _json($export) . "\n", 16384);
            @{$transport}{qw(root export attempt terminal username)} = ($root, $export, $attempt, $terminal, $username);
            $result = _delivery_attempt($transport);
            _discard_attempt($attempt);
            undef $attempt;
        }
        $transport->{phase} = 'payload retirement';
        _retire_export($root, $run, $export, $result);
        close($lock) or _fail('Cannot close delivery lock');
        1;
    };
    unless ($ok) {
        my $error = substr($@ || 'Unknown delivery failure', 0, 8192);
        my $diagnostic = '';
        if (defined($attempt)) {
            my $recorded = eval {
                _write("$attempt/failure", $error, 8192);
                _sync_directory($attempt);
                1;
            };
            $diagnostic = $recorded ? "; diagnostic: $attempt/failure" : "; diagnostic retention failed: $attempt";
        }
        $error =~ s/[\x00-\x20\x7f]+/ /gx;
        $error =~ s/[ ]+\z//x;
        $error = substr($error, 0, 512);
        _fail("FreeBSD postscript delivery failed during $transport->{phase}: $error$diagnostic");
    }
    return $result;
}

sub release_execution {
    my ($run, $subrequest, @arguments) = @_;
    _fail('Release requires a subrequest') unless ref($subrequest) eq 'CODE';
    my ($options, $username) = _delivery_options(@arguments);
    my $root = _root($options, 0);
    my $export = _export_descriptor($root, $run);
    my $attempt = tempdir(".release-$run.XXXXXXXX", DIR => $root, CLEANUP => 0);
    _directory($attempt, 0);
    _sync_directory($root);
    my $transport = { root => $root, export => $export, attempt => $attempt,
        username => $username, subrequest => $subrequest, phase => 'release' };
    my $command = join(' ', '/usr/local/libexec/xcat-postscript', 'release-after-reboot', $run, $export->{snapshot});
    my $result = _delivery_receipt(_delivery_command($transport, 'xdsh', [$command]), $export);
    _fail('Released run has an unexpected outcome') unless $result->{outcome} eq 'uncertain';
    _discard_attempt($attempt);
    return $result;
}

sub _report_status {
    my ($bytes, $export, $receipt) = @_;
    my $status = _delivery_fields($bytes, qw(format run snapshot receipt-sha256 archive-sha256 archive-bytes path));
    my $run = $export->{binding}{run};
    my $observation = _delivery_receipt($receipt, $export);
    my $partial = $observation->{outcome} eq 'uncertain';
    my $version = $partial ? 2 : $observation->{format} eq 'xcat-freebsd-postscript-result-2' ? 3
      : $observation->{format} eq 'xcat-freebsd-postscript-result-3' ? 4 : 1;
    _fail('Execution is still mutable') unless $observation->{complete} eq 'yes' || $partial;
    _fail('Evidence response differs') unless $status->{format} eq "xcat-freebsd-postscript-evidence-$version"
      && $status->{run} eq $run && $status->{snapshot} eq $export->{snapshot}
      && $status->{'receipt-sha256'} =~ /\A[0-9a-f]{64}\z/x
      && $status->{'archive-sha256'} =~ /\A[0-9a-f]{64}\z/x
      && $status->{'archive-bytes'} =~ /\A[1-9][0-9]{0,8}\z/x
      && $status->{path} eq "/var/db/xcat/postscripts/runs/$run/evidence/archive.tar";
    _fail('Evidence archive exceeds its limit') if $status->{'archive-bytes'} > 134217728;
    _fail('Evidence receipt differs') if !$partial && $status->{'receipt-sha256'} ne sha256_hex($receipt);
    return $status;
}

sub _report_member {
    my ($member, $limits, $seen) = @_;
    my $name = $member->full_path;
    _fail('Unexpected evidence member') if !exists($limits->{$name}) || !$member->is_file
      || $member->linkname || $member->size > $limits->{$name} || $member->uid != 0 || $member->gid != 0
      || ($member->mode != oct('0400') && $member->mode != oct('0600'));
    _fail('Duplicate evidence member') if exists($seen->{$name}) && $seen->{$name} != $member;
    $seen->{$name} = $member;
    return 1;
}

sub _report_limits {
    my ($export, $partial, $rejected, $failure) = @_;
    my $log_limit = $export->{binding}{log_limit};
    if ($rejected) {
        return { 'bundle/manifest' => 4096, 'bundle/entries' => 1048576, snapshot => 65, started => 1024,
            result => 4096, results => 4194304, 'packages.rejected' => 1024,
            'prerequisite.stdout' => $log_limit, 'prerequisite.stderr' => $log_limit,
            'packages/local-update.rejected' => 1024, 'packages/local-verify.rejected' => 1024 };
    }
    my %limits = ('bundle/manifest' => 4096, 'bundle/entries' => 1048576,
        snapshot => 65, started => 1024, 'driver.complete' => 64, result => 4096,
        results => 4194304, 'driver.stdout' => $log_limit, 'driver.stderr' => $log_limit,
        'packages.result' => 4096);
    if ($partial || $failure) {
        delete $limits{result};
        @limits{qw(released interrupted.results interrupted.inventory interrupted.receipt packages/stdout packages/stderr)}
          = (1024, 4194304, 4194304, 4096, $log_limit, $log_limit);
        @limits{qw(prerequisite.stdout prerequisite.stderr)} = ($log_limit, $log_limit);
        @limits{qw(packages.recovered packages/recovery.result packages/recovery.capture
            packages/recovery.stdout packages/recovery.stderr)} = (4096, 1536, 1024, $log_limit, $log_limit);
        @limits{qw(packages.preserved packages/local-update.rejected packages/local-verify.rejected)} = (1024, 1024, 1024);
        @limits{qw(supervision release.process release.captures framework.packages framework.driver framework.finalization)}
          = (1024, 1024, 4194304, 1024, 1024, 1024);
        @limits{qw(framework.stdout framework.stderr supervisor.stderr)} = ($log_limit, $log_limit, 1048576);
    }
    if ($failure) {
        delete @limits{qw(released release.process release.captures interrupted.results interrupted.inventory interrupted.receipt
            packages.recovered packages/recovery.result packages/recovery.capture packages/recovery.stdout packages/recovery.stderr
            packages.preserved packages/local-update.rejected packages/local-verify.rejected)};
        @limits{qw(result failure.results failure.inventory failure.captures)} = (4096, 4194304, 4194304, 4194304);
    }
    for my $ordinal (1 .. $export->{scripts}) {
        for my $member (qw(started result argv stdout stderr sync.request sync.result)) {
            $limits{"entries/$ordinal/$member"} = $member eq 'argv' ? 65536
              : $member eq 'stdout' || $member eq 'stderr' ? $log_limit : 1024;
        }
    }
    return \%limits;
}

sub _report_members {
    my ($archive, $export, $status) = @_;
    my $identity = _read($archive, 134217728, 1);
    _fail('Evidence archive differs') unless $identity->{bytes} == $status->{'archive-bytes'}
      && $identity->{sha256} eq $status->{'archive-sha256'};
    my $partial = $status->{format} eq 'xcat-freebsd-postscript-evidence-2';
    my $rejected = $status->{format} eq 'xcat-freebsd-postscript-evidence-3';
    my $failure = $status->{format} eq 'xcat-freebsd-postscript-evidence-4';
    my %limits = %{_report_limits($export, $partial, $rejected, $failure)};
    require Archive::Tar;
    my $tar = Archive::Tar->new;
    my %seen;
    sysopen(my $file, $archive, O_RDONLY | O_NOFOLLOW) or _fail('Cannot open evidence archive');
    my $read = $tar->read($file, 0, { filter_cb => sub { _report_member(shift, \%limits, \%seen); } });
    close($file) or _fail('Cannot close evidence archive');
    _fail('Cannot read evidence archive') if !$read || $tar->error;
    my %members;
    for my $member ($tar->get_files) {
        my $name = $member->full_path;
        _fail('Unexpected evidence content') if !exists($limits{$name}) || exists($members{$name})
          || !$member->is_file || length($member->get_content) != $member->size;
        $members{$name} = $member->get_content;
    }
    _report_required_members(\%members, \%limits, $partial, $rejected, $failure);
    _report_sync(\%members, $export);
    _fail('Evidence archive changed') unless _json(_read($archive, 134217728, 1)) eq _json($identity);
    return \%members;
}

sub _report_required_members {
    my ($members, $limits, $partial, $rejected, $failure) = @_;
    if ($failure) {
        _fail('Missing framework failure evidence') if grep { !exists($members->{$_}) }
          qw(bundle/manifest bundle/entries snapshot started result packages.result supervision
            framework.stdout framework.stderr failure.results failure.inventory failure.captures);
    } elsif ($partial) {
        _fail('Missing interrupted evidence') if grep { !exists($members->{$_}) }
          qw(bundle/manifest bundle/entries snapshot started released interrupted.results interrupted.inventory interrupted.receipt);
    } else {
        my @required = grep { !m{/sync[.](?:request|result)\z}x
          && !($rejected && m{\Apackages/local-(?:update|verify)[.]rejected\z}x) } keys %$limits;
        _fail('Evidence member roster differs') if grep { !exists($members->{$_}) } @required;
    }
    return;
}

sub _report_sync {
    my ($members, $export) = @_;
    for my $ordinal (1 .. $export->{scripts}) {
        my $prefix = "entries/$ordinal/sync";
        for my $kind (qw(request result)) {
            next unless exists($members->{"$prefix.$kind"});
            _fail('Missing synchronization request') unless exists($members->{"$prefix.request"})
              && exists($members->{"entries/$ordinal/started"});
            my @fields = qw(format run snapshot ordinal);
            push @fields, qw(status evidence) if $kind eq 'result';
            my $sync = _delivery_fields($members->{"$prefix.$kind"}, @fields);
            _fail('Synchronization evidence identity differs') unless $sync->{format}
              eq "xcat-freebsd-postscript-sync-$kind-1" && $sync->{run} eq $export->{binding}{run}
              && $sync->{snapshot} eq $export->{snapshot} && $sync->{ordinal} eq $ordinal;
            if ($kind eq 'result') {
                _fail('Invalid synchronization evidence result') unless $sync->{status} =~ /\A[01]\z/x
                  && $sync->{evidence} =~ /\A[0-9a-f]{64}\z/x;
            }
        }
    }
    return;
}

sub _report_times {
    my ($started, $result, $bytes) = @_;
    _fail('Entry timestamps differ') unless $result->{'started-sha256'} eq sha256_hex($bytes)
      && $started->{'started-epoch'} =~ /\A[1-9][0-9]{0,11}\z/x
      && $result->{'finished-epoch'} =~ /\A[1-9][0-9]{0,11}\z/x;
    return;
}

sub _report_start {
    my ($bytes, $row) = @_;
    my ($version) = $bytes =~ /\Aformat\txcat-freebsd-postscript-entry-start-([1234])\n/x;
    _fail('Invalid entry start format') unless defined $version;
    my $timed = $version >= 2;
    my @fields = qw(format ordinal raw-sha256 script-sha256);
    push @fields, 'started-epoch' if $timed;
    push @fields, 'started-uptime' if $version >= 3;
    my $started = _delivery_fields($bytes, @fields);
    _fail('Entry start differs') unless $started->{format} eq "xcat-freebsd-postscript-entry-start-$version"
      && $started->{ordinal} eq $row->[0] && $started->{'raw-sha256'} eq $row->[2]
      && $started->{'script-sha256'} eq $row->[3];
    _fail('Invalid entry start time') if $timed && $started->{'started-epoch'} !~ /\A[1-9][0-9]{0,11}\z/x;
    _fail('Invalid monotonic entry start') if $version >= 3
      && $started->{'started-uptime'} !~ /\A(?:0|[1-9][0-9]{0,11})\z/x;
    return ($started, $version);
}

sub _report_capture {
    my ($entry, $result, $export) = @_;
    my $limit = int(67108864 / (2 * $export->{scripts}));
    $limit = $export->{binding}{log_limit} if $export->{binding}{log_limit} < $limit;
    _fail('Entry log limit differs') unless $result->{'log-limit'} eq "$limit";
    _report_capture_streams($entry, $result, $limit);
    return;
}

sub _report_capture_streams {
    my ($entry, $result, $limit) = @_;
    for my $stream (qw(stdout stderr)) {
        my $bytes = $entry->{$stream}{bytes};
        _fail('Entry log size differs') unless $result->{"$stream-bytes"} eq "$bytes";
        _fail('Entry log exceeds its bound') if $bytes > $limit;
        _fail('Invalid entry output flag') unless $result->{"$stream-truncated"} =~ /\A(?:yes|no)\z/x
          && $result->{"$stream-open"} =~ /\A(?:yes|no)\z/x;
        _fail('Truncated entry log is short') if $result->{"$stream-truncated"} eq 'yes' && $bytes != $limit;
        @{$entry->{$stream}}{qw(limit truncated open_after_exit)} = ($limit,
            $result->{"$stream-truncated"} eq 'yes' ? 1 : 0, $result->{"$stream-open"} eq 'yes' ? 1 : 0);
    }
    return;
}

sub _report_entry {
    my ($members, $row, $identity, $path, $export) = @_;
    my ($status, $digest) = @$identity;
    my ($ordinal, $phase, $raw, $script, $name) = @$row;
    my $prefix = "entries/$ordinal";
    my $started_bytes = $members->{"$prefix/started"};
    my $result_bytes = $members->{"$prefix/result"};
    _fail('Entry result digest differs') unless sha256_hex($result_bytes) eq $digest;
    my ($started, $version) = _report_start($started_bytes, $row);
    my $timed = $version >= 2;
    my @result_fields = qw(format ordinal status);
    push @result_fields, qw(started-sha256 finished-epoch) if $timed;
    push @result_fields, 'finished-uptime' if $version >= 3;
    push @result_fields, qw(argv-sha256 stdout-sha256 stderr-sha256);
    push @result_fields, qw(log-limit stdout-bytes stderr-bytes stdout-truncated stderr-truncated stdout-open stderr-open)
      if $version == 4;
    push @result_fields, 'complete';
    my $result = _delivery_fields($result_bytes, @result_fields);
    _fail('Entry receipt differs') unless $result->{format} eq "xcat-freebsd-postscript-entry-result-$version"
      && $result->{ordinal} eq $ordinal
      && $result->{status} eq $status && $result->{complete} eq 'yes';
    _report_times($started, $result, $started_bytes) if $timed;
    _fail('Invalid monotonic entry finish') if $version >= 3
      && ($result->{'finished-uptime'} !~ /\A(?:0|[1-9][0-9]{0,11})\z/x
      || $result->{'finished-uptime'} < $started->{'started-uptime'});
    my $entry = { ordinal => 0 + $ordinal, phase => $phase, script => $name,
        raw_sha256 => $raw, script_sha256 => $script, status => 0 + $status,
        started_epoch => $timed ? 0 + $started->{'started-epoch'} : undef,
        finished_epoch => $timed ? 0 + $result->{'finished-epoch'} : undef,
        started_uptime => $version >= 3 ? 0 + $started->{'started-uptime'} : undef,
        finished_uptime => $version >= 3 ? 0 + $result->{'finished-uptime'} : undef };
    for my $stream (qw(argv stdout stderr)) {
        my $bytes = $members->{"$prefix/$stream"};
        my $sha = sha256_hex($bytes);
        _fail('Entry stream differs') unless $sha eq $result->{"$stream-sha256"};
        $entry->{$stream} = { path => "$path/entries.$ordinal.$stream", sha256 => $sha, bytes => length($bytes) };
    }
    _report_capture($entry, $result, $export) if $version == 4;
    return $entry;
}

sub _report_selection {
    my ($members, $export) = @_;
    my @selected = split(/\n/x, $members->{'bundle/entries'});
    _fail('Evidence selection count differs') unless @selected == $export->{scripts};
    my @rows;
    for my $ordinal (1 .. @selected) {
        my @row = split(/\t/x, $selected[$ordinal - 1]);
        _fail('Invalid evidence selection') unless @row == 5 && $row[0] eq $ordinal
          && $row[1] =~ /\A(?:postscripts|postbootscripts)\z/x
          && $row[2] =~ /\A[0-9a-f]{64}\z/x && $row[3] =~ /\A[0-9a-f]{64}\z/x
          && $row[4] =~ m{\A[A-Za-z0-9_.+/-]+\z}x;
        push @rows, \@row;
    }
    return \@rows;
}

sub _report_entries {
    my ($members, $export, $path) = @_;
    my $selected = _report_selection($members, $export);
    my @results = split(/\n/x, $members->{results});
    _fail('Evidence entry count differs') unless @results == @$selected;
    my @entries;
    my $outcome = 'success';
    for my $ordinal (1 .. @$selected) {
        my @result = split(/\t/x, $results[$ordinal - 1]);
        _fail('Invalid evidence result') unless @result == 3 && $result[0] eq $ordinal
          && $result[1] =~ /\A(?:0|[1-9][0-9]{0,2})\z/x
          && $result[2] =~ /\A[0-9a-f]{64}\z/x;
        _fail('Invalid child status') if $result[1] > 255;
        push @entries, _report_entry($members, $selected->[$ordinal - 1], [@result[1, 2]], $path, $export);
        $outcome = 'failed' if $result[1];
    }
    return (\@entries, $outcome);
}

sub _report_manifest {
    my ($members, $export) = @_;
    my $bound = exists($export->{binding}{boot});
    my $manifest = _delivery_fields($members->{'bundle/manifest'}, qw(format run node generation attempt kind
        preparation source plan request package-mode driver entries tree scripts entry-timeout run-timeout log-limit),
        $bound ? ('boot') : ());
    _fail('Evidence bundle format differs') unless $manifest->{format}
      eq ($bound ? 'xcat-freebsd-postscript-bundle-3' : 'xcat-freebsd-postscript-bundle-2');
    if ($bound) {
        my $started = _delivery_fields($members->{started}, qw(format run snapshot boot pid process));
        _fail('Evidence boot binding differs') unless $manifest->{boot} eq $export->{binding}{boot}
          && $manifest->{kind} =~ /\A(?:firstboot|repeat)\z/x && $manifest->{'package-mode'} eq 'verify'
          && $started->{format} eq 'xcat-freebsd-postscript-start-1'
          && $started->{run} eq $export->{binding}{run} && $started->{snapshot} eq $export->{snapshot}
          && $started->{boot} eq $manifest->{boot}
          && $started->{pid} =~ /\A[1-9][0-9]{0,7}\z/x && $started->{process} =~ /\A[0-9a-f]{64}\z/x;
    }
    return $manifest;
}

sub _report_content {
    my ($members, $export, $receipt_bytes, $status, $path) = @_;
    return _report_interrupted($members, $export, $status, $path)
      if $status->{format} eq 'xcat-freebsd-postscript-evidence-2';
    return _report_rejected($members, $export, $receipt_bytes, $status, $path)
      if $status->{format} eq 'xcat-freebsd-postscript-evidence-3';
    return _report_failure($members, $export, $receipt_bytes, $status, $path)
      if $status->{format} eq 'xcat-freebsd-postscript-evidence-4';
    my $receipt = _delivery_receipt($receipt_bytes, $export);
    _fail('Evidence receipt is incomplete') unless $receipt->{complete} eq 'yes';
    _fail('Evidence context differs') unless $members->{result} eq $receipt_bytes
      && $members->{snapshot} eq "$export->{snapshot}\n"
      && sha256_hex($members->{'bundle/manifest'}) eq $export->{snapshot}
      && $members->{'driver.complete'} eq "$export->{scripts}\n";
    my $manifest = _report_manifest($members, $export);
    _fail('Evidence selection differs') unless $manifest->{entries} eq sha256_hex($members->{'bundle/entries'})
      && $manifest->{plan} eq $receipt->{plan};
    for my $pair ([results => 'results-sha256'], ['packages.result' => 'packages-sha256'],
        ['driver.stdout' => 'stdout-sha256'], ['driver.stderr' => 'stderr-sha256']) {
        _fail('Aggregate evidence differs') unless sha256_hex($members->{$pair->[0]}) eq $receipt->{$pair->[1]};
    }
    my ($entries, $outcome) = _report_entries($members, $export, $path);
    _fail('Evidence outcome differs') unless $outcome eq $receipt->{outcome};
    return { kind => 'freebsd-postscript-report-v1', receipt => $receipt, entries => $entries,
        archive => { path => "$path/archive.tar", sha256 => $status->{'archive-sha256'},
            bytes => 0 + $status->{'archive-bytes'} } };
}

sub _report_native_rejection {
    my ($bytes, $package, $manifest) = @_;
    my $native = _delivery_fields($bytes,
        qw(format scope plan-reference request-sha256 prior-request-sha256 config-sha256 pkg apply outcome complete));
    _fail('Native rejection contract differs') unless $native->{format} eq 'xcat-freebsd-local-rejection-1'
      && $native->{scope} eq "local-$package->{mode}" && $native->{'plan-reference'} eq $package->{plan}
      && $native->{'request-sha256'} eq $manifest->{request} && $native->{pkg} eq '2.6.2'
      && $native->{apply} eq 'not-started' && $native->{outcome} eq 'rejected' && $native->{complete} eq 'yes';
    for my $key (qw(prior-request-sha256 config-sha256)) {
        _fail('Invalid native rejection digest') unless $native->{$key} =~ /\A[0-9a-f]{64}\z/x;
    }
    return;
}

sub _report_package_rejection {
    my ($members, $receipt, $manifest) = @_;
    my $package = _delivery_fields($members->{'packages.rejected'},
        qw(format run snapshot plan mode phase previous-head-sha256 native-sha256 complete));
    _fail('Package rejection context differs') unless $package->{format} eq 'xcat-freebsd-postscript-package-rejection-1'
      && $package->{run} eq $receipt->{run} && $package->{snapshot} eq $receipt->{snapshot}
      && $package->{plan} eq $receipt->{plan} && $package->{mode} eq $manifest->{'package-mode'}
      && $package->{mode} =~ /\A(?:verify|update)\z/x && $package->{complete} eq 'yes'
      && $package->{'previous-head-sha256'} =~ /\A(?:-|[0-9a-f]{64})\z/x;
    my $native_name = "packages/local-$package->{mode}.rejected";
    my @native = grep { m{\Apackages/}x } keys %$members;
    if ($package->{phase} eq 'preparation') {
        _fail('Preparation rejection has native evidence') if @native || $package->{'native-sha256'} ne '-';
    } elsif ($package->{phase} eq 'native') {
        _fail('Native rejection roster differs') unless @native == 1 && $native[0] eq $native_name
          && $package->{'native-sha256'} eq sha256_hex($members->{$native_name});
        _report_native_rejection($members->{$native_name}, $package, $manifest);
    } else {
        _fail('Invalid package rejection phase');
    }
    return $package;
}

sub _report_prerequisite_logs {
    my ($members, $path) = @_;
    my %logs;
    for my $stream (qw(stdout stderr)) {
        my $name = "prerequisite.$stream";
        next unless exists($members->{$name});
        $logs{$stream} = { path => "$path/$name", sha256 => sha256_hex($members->{$name}),
            bytes => length($members->{$name}) };
    }
    return \%logs;
}

sub _report_rejected {
    my ($members, $export, $receipt_bytes, $status, $path) = @_;
    my $receipt = _delivery_receipt($receipt_bytes, $export);
    _fail('Invalid rejected execution') unless $receipt->{format} eq 'xcat-freebsd-postscript-result-2'
      && $members->{result} eq $receipt_bytes && sha256_hex($receipt_bytes) eq $status->{'receipt-sha256'}
      && $members->{snapshot} eq "$export->{snapshot}\n"
      && sha256_hex($members->{'bundle/manifest'}) eq $export->{snapshot};
    my $manifest = _report_manifest($members, $export);
    _fail('Rejected selection differs') unless $manifest->{entries} eq sha256_hex($members->{'bundle/entries'})
      && $manifest->{plan} eq $receipt->{plan};
    my $started = _delivery_fields($members->{started}, qw(format run snapshot boot pid process));
    _fail('Rejected worker binding differs') unless $started->{format} eq 'xcat-freebsd-postscript-start-1'
      && $started->{run} eq $receipt->{run} && $started->{snapshot} eq $receipt->{snapshot}
      && $started->{boot} =~ /\A[0-9a-f]{64}\z/x && $started->{pid} =~ /\A[1-9][0-9]{0,7}\z/x
      && $started->{process} =~ /\A[0-9a-f]{64}\z/x;
    for my $pair ([results => 'results-sha256'], ['packages.rejected' => 'packages-sha256'],
        ['prerequisite.stdout' => 'stdout-sha256'], ['prerequisite.stderr' => 'stderr-sha256']) {
        _fail('Rejected execution evidence differs') unless sha256_hex($members->{$pair->[0]}) eq $receipt->{$pair->[1]};
    }
    my $package = _report_package_rejection($members, $receipt, $manifest);
    my $selected = _report_selection($members, $export);
    my @rows = split(/\n/x, $members->{results});
    _fail('Rejected entry count differs') unless @rows == @$selected;
    my @entries;
    for my $ordinal (1 .. @$selected) {
        _fail('Rejected entry claims execution') unless $rows[$ordinal - 1] eq "$ordinal\tnot-run\t-\t-\t-";
        my $entry = _report_unfinished_entry($members, $selected->[$ordinal - 1], $path);
        $entry->{state} = 'not-run';
        push @entries, $entry;
    }
    my $prerequisite = { phase => $package->{phase}, mode => $package->{mode},
        %{_report_prerequisite_logs($members, $path)} };
    return { kind => 'freebsd-postscript-report-v3', receipt => $receipt, entries => \@entries,
        prerequisite => $prerequisite,
        archive => { path => "$path/archive.tar", sha256 => $status->{'archive-sha256'}, bytes => 0 + $status->{'archive-bytes'} } };
}

sub _report_failure {
    my ($members, $export, $receipt_bytes, $status, $path) = @_;
    my $receipt = _delivery_receipt($receipt_bytes, $export);
    _fail('Framework failure context differs') unless $receipt->{format} eq 'xcat-freebsd-postscript-result-3'
      && $members->{result} eq $receipt_bytes && sha256_hex($receipt_bytes) eq $status->{'receipt-sha256'}
      && $members->{snapshot} eq "$export->{snapshot}\n" && sha256_hex($members->{'bundle/manifest'}) eq $export->{snapshot};
    my $manifest = _report_manifest($members, $export);
    _fail('Framework failure selection differs') unless $manifest->{entries} eq sha256_hex($members->{'bundle/entries'})
      && $manifest->{plan} eq $receipt->{plan};
    for my $pair (['failure.results' => 'results-sha256'], ['failure.inventory' => 'inventory-sha256'],
        ['packages.result' => 'packages-sha256'], ['framework.stdout' => 'stdout-sha256'], ['framework.stderr' => 'stderr-sha256']) {
        _fail('Framework failure digest differs') unless sha256_hex($members->{$pair->[0]}) eq $receipt->{$pair->[1]};
    }
    _report_inventory($members, 'failure');
    my $started = _delivery_fields($members->{started}, qw(format run snapshot boot pid process));
    _fail('Framework failure worker differs') unless $started->{format} eq 'xcat-freebsd-postscript-start-1'
      && $started->{run} eq $receipt->{run} && $started->{snapshot} eq $receipt->{snapshot}
      && $started->{boot} =~ /\A[0-9a-f]{64}\z/x && $started->{pid} =~ /\A[1-9][0-9]{0,7}\z/x
      && $started->{process} =~ /\A[0-9a-f]{64}\z/x;
    _report_supervision($members, $started);
    _report_capture_inventory($members->{'failure.captures'}, $export);
    my $selected = _report_selection($members, $export);
    my @results = split(/\n/x, $members->{'failure.results'});
    _fail('Framework failure entry count differs') unless @results == @$selected;
    my @entries;
    for my $ordinal (1 .. @$selected) {
        my @result = split(/\t/x, $results[$ordinal - 1]);
        push @entries, _report_interrupted_entry($members, $selected->[$ordinal - 1], \@result, $path, $export);
    }
    return { kind => 'freebsd-postscript-report-v4', receipt => $receipt, entries => \@entries,
        framework_logs => _report_framework_logs($members, $path),
        archive => { path => "$path/archive.tar", sha256 => $status->{'archive-sha256'}, bytes => 0 + $status->{'archive-bytes'} } };
}

sub _report_inventory {
    my ($members, $prefix) = @_;
    $prefix //= 'interrupted';
    my %expected = %$members;
    delete @expected{"$prefix.inventory", $prefix eq 'failure' ? 'result' : 'interrupted.receipt'};
    my %seen;
    my $inventory = $members->{"$prefix.inventory"};
    _fail('Incomplete interrupted inventory') unless $inventory =~ /\n\z/x;
    for my $line (split(/\n/x, $inventory)) {
        my @row = split(/\t/x, $line);
        _fail('Invalid interrupted inventory') unless @row == 3
          && $row[1] =~ /\A(?:0|[1-9][0-9]{0,7})\z/x && $row[2] =~ /\A[0-9a-f]{64}\z/x;
        _fail('Interrupted inventory differs') if !exists($expected{$row[0]}) || $seen{$row[0]}++
          || length($expected{$row[0]}) != $row[1] || sha256_hex($expected{$row[0]}) ne $row[2];
    }
    _fail('Interrupted inventory roster differs') unless _json([sort keys %seen]) eq _json([sort keys %expected]);
    return;
}

sub _report_release {
    my ($members, $export) = @_;
    my $started = _delivery_fields($members->{started}, qw(format run snapshot boot pid process));
    my $observed = $members->{released} =~ /\Aformat\txcat-freebsd-postscript-release-2\n/x;
    my @fields = qw(format run snapshot boot);
    push @fields, qw(proof started-sha256 supervision-sha256 process-sha256 captures-sha256) if $observed;
    my $released = _delivery_fields($members->{released}, @fields);
    _fail('Invalid interrupted worker') unless $started->{format} eq 'xcat-freebsd-postscript-start-1'
      && $started->{pid} =~ /\A[1-9][0-9]{0,7}\z/x && $started->{process} =~ /\A[0-9a-f]{64}\z/x;
    _fail('Invalid interrupted release') unless $released->{format} eq 'xcat-freebsd-postscript-release-' . ($observed ? 2 : 1);
    for my $record ($started, $released) {
        _fail('Interrupted release binding differs') unless $record->{run} eq $export->{binding}{run}
          && $record->{snapshot} eq $export->{snapshot} && $record->{boot} =~ /\A[0-9a-f]{64}\z/x;
    }
    if ($observed) {
        _report_release_observations($members, $export, $started, $released);
    } else {
        _fail('Interrupted release did not change boot') if $started->{boot} eq $released->{boot};
        _fail('Unexpected release observations') if exists($members->{'release.process'}) || exists($members->{'release.captures'});
    }
    return;
}

sub _report_release_observations {
    my ($members, $export, $started, $released) = @_;
    _fail('Missing release observations') if grep { !exists($members->{$_}) } qw(supervision release.process release.captures);
    _fail('Observed release context differs') unless $released->{boot} eq $started->{boot}
      && $released->{proof} =~ /\Arelease[.][A-Za-z0-9]{8}\z/x;
    for my $pair ([started => 'started'], [supervision => 'supervision'], [process => 'release.process'], [captures => 'release.captures']) {
        _fail('Release observation digest differs') unless $released->{"$pair->[0]-sha256"} eq sha256_hex($members->{$pair->[1]});
    }
    _report_supervision($members, $started);
    _report_process_observation($members->{'release.process'}, $started);
    _report_capture_inventory($members->{'release.captures'}, $export);
    return;
}

sub _report_supervision {
    my ($members, $started) = @_;
    my $supervision = _delivery_fields($members->{supervision}, qw(format run snapshot started-sha256 helper-sha256 capture-version));
    _fail('Invalid run supervision') unless $supervision->{format} eq 'xcat-freebsd-postscript-supervision-1'
      && $supervision->{run} eq $started->{run} && $supervision->{snapshot} eq $started->{snapshot}
      && $supervision->{'started-sha256'} eq sha256_hex($members->{started})
      && $supervision->{'helper-sha256'} =~ /\A[0-9a-f]{64}\z/x && $supervision->{'capture-version'} eq '1';
    return;
}

sub _report_process_observation {
    my ($bytes, $started) = @_;
    my $process = _delivery_fields($bytes, qw(format pid state identity));
    _fail('Invalid original worker observation') unless $process->{format} eq 'xcat-freebsd-process-state-1'
      && $process->{pid} eq $started->{pid} && $process->{state} =~ /\A(?:absent|zombie|running)\z/x;
    if ($process->{state} eq 'absent') {
        _fail('Absent worker claims an identity') unless $process->{identity} eq '-';
    } else {
        _fail('Invalid observed worker identity') unless $process->{identity} =~ /\A\Q$started->{pid}\E:[0-9]+[.][0-9]{6}\z/x;
        _fail('Released original worker is still running') if $process->{state} eq 'running'
          && sha256_hex($process->{identity}) eq $started->{process};
    }
    return;
}

sub _report_capture_observation {
    my ($line, $export) = @_;
    my @row = split(/\t/x, $line);
    _fail('Invalid capture observation') unless @row == 9 && $row[0] eq sha256_hex("$row[1]\n");
    _fail('Invalid capture digest') if grep { $_ !~ /\A[0-9a-f]{64}\z/x } @row[2 .. 4];
    _fail('Invalid captured command outcome') unless $row[6] =~ /\A(?:0|[1-9][0-9]{0,2})\z/x
      && $row[7] =~ /\A(?:yes|no)\z/x && $row[8] =~ /\A(?:yes|no)\z/x;
    _fail('Captured status exceeds its bound') if $row[6] > 255;
    my $mode = 'guard';
    if ($row[1] =~ /\A(?:framework|prerequisite|driver)[.]stdout\z/x) {
        $mode = 'inherit';
    } elsif ($row[1] =~ m{\Aentries/([1-9][0-9]{0,3})/stdout\z}x) {
        _fail('Capture entry exceeds selection') if $1 > $export->{scripts};
    } elsif ($row[1] =~ m{\Apackages/(?:stdout|recovery[.][A-Za-z0-9]{8}[.]stdout)\z}x) {
        _fail('Package capture remains open') unless $row[7] eq 'no' && $row[8] eq 'no';
    } else {
        _fail('Unexpected capture observation path');
    }
    _fail('Capture lock policy differs') unless $row[5] eq $mode;
    return $row[1];
}

sub _report_capture_inventory {
    my ($bytes, $export) = @_;
    _fail('Incomplete capture inventory') unless length($bytes) && $bytes =~ /\n\z/x;
    my @rows = split(/\n/x, $bytes);
    _fail('Capture inventory exceeds its bound') if @rows > $export->{scripts} + 1028;
    my %seen;
    for my $line (@rows) {
        my $path = _report_capture_observation($line, $export);
        _fail('Duplicate capture observation') if $seen{$path}++;
    }
    _fail('Framework completion was not observed') unless $seen{'framework.stdout'};
    return;
}

sub _report_unfinished_entry {
    my ($members, $row, $path) = @_;
    my ($ordinal, $phase, $raw, $script, $name) = @$row;
    my $prefix = "entries/$ordinal";
    my $entry = { ordinal => 0 + $ordinal, phase => $phase, script => $name, raw_sha256 => $raw,
        script_sha256 => $script, status => undef, started_epoch => undef, finished_epoch => undef,
        started_uptime => undef, finished_uptime => undef };
    if (exists($members->{"$prefix/started"})) {
        my $started = eval { my ($value) = _report_start($members->{"$prefix/started"}, $row); $value; };
        $entry->{started_record_valid} = $started ? 1 : 0;
        $entry->{started_epoch} = 0 + $started->{'started-epoch'} if $started && exists($started->{'started-epoch'});
        $entry->{started_uptime} = 0 + $started->{'started-uptime'} if $started && exists($started->{'started-uptime'});
    }
    for my $stream (qw(argv stdout stderr)) {
        $entry->{$stream} = exists($members->{"$prefix/$stream"})
          ? { path => "$path/entries.$ordinal.$stream", sha256 => sha256_hex($members->{"$prefix/$stream"}),
              bytes => length($members->{"$prefix/$stream"}) } : undef;
    }
    return $entry;
}

sub _report_interrupted_entry {
    my ($members, $row, $result, $path, $export) = @_;
    my ($ordinal, $phase, $raw, $script, $name) = @$row;
    my ($number, $state, $status, $start_digest, $result_digest) = @$result;
    _fail('Invalid interrupted entry') unless @$result == 5 && $number eq $ordinal
      && $state =~ /\A(?:complete|uncertain|not-run)\z/x;
    my $prefix = "entries/$ordinal";
    for my $pair ([started => $start_digest], [result => $result_digest]) {
        my $expected = exists($members->{"$prefix/$pair->[0]"}) ? sha256_hex($members->{"$prefix/$pair->[0]"}) : '-';
        _fail('Interrupted entry binding differs') unless $pair->[1] eq $expected;
    }
    my $entry;
    if ($state eq 'complete') {
        _fail('Invalid completed child status') unless $status =~ /\A(?:0|[1-9][0-9]{0,2})\z/x;
        _fail('Invalid completed child status') if $status > 255;
        _fail('Missing completed evidence') if grep { !exists($members->{"$prefix/$_"}) } qw(started result argv stdout stderr);
        $entry = _report_entry($members, $row, [$status, $result_digest], $path, $export);
    } else {
        _fail('Unfinished entry claims an exit status') unless $status eq '-';
        _fail('Unstarted entry has a journal') if $state eq 'not-run'
          && grep { exists($members->{"$prefix/$_"}) } qw(started result argv stdout stderr);
        $entry = _report_unfinished_entry($members, $row, $path);
    }
    $entry->{state} = $state;
    return $entry;
}

sub _report_interrupted {
    my ($members, $export, $status, $path) = @_;
    my $bytes = $members->{'interrupted.receipt'};
    my $receipt = _delivery_fields($bytes, qw(format run node generation attempt snapshot plan entries results-sha256 inventory-sha256 outcome complete));
    _fail('Interrupted receipt differs') unless $receipt->{format} eq 'xcat-freebsd-postscript-interrupted-1'
      && sha256_hex($bytes) eq $status->{'receipt-sha256'} && $receipt->{outcome} eq 'uncertain' && $receipt->{complete} eq 'no'
      && $receipt->{run} eq $export->{binding}{run} && $receipt->{node} eq $export->{node}
      && $receipt->{generation} eq $export->{binding}{generation} && $receipt->{attempt} eq $export->{binding}{attempt}
      && $receipt->{snapshot} eq $export->{snapshot} && $receipt->{entries} eq $export->{scripts};
    _fail('Interrupted selection differs') unless $members->{snapshot} eq "$export->{snapshot}\n"
      && sha256_hex($members->{'bundle/manifest'}) eq $export->{snapshot};
    my $manifest = _report_manifest($members, $export);
    _fail('Interrupted package or entry binding differs') unless $manifest->{plan} eq $receipt->{plan}
      && $manifest->{entries} eq sha256_hex($members->{'bundle/entries'});
    _fail('Interrupted inventory digest differs') unless $receipt->{'inventory-sha256'} eq sha256_hex($members->{'interrupted.inventory'})
      && $receipt->{'results-sha256'} eq sha256_hex($members->{'interrupted.results'});
    _report_inventory($members);
    _report_release($members, $export);
    my $selected = _report_selection($members, $export);
    my @results = split(/\n/x, $members->{'interrupted.results'});
    _fail('Interrupted result count differs') unless @results == @$selected;
    my @entries;
    for my $ordinal (1 .. @$selected) {
        my @result = split(/\t/x, $results[$ordinal - 1]);
        push @entries, _report_interrupted_entry($members, $selected->[$ordinal - 1], \@result, $path, $export);
    }
    my $prerequisite_logs = _report_prerequisite_logs($members, $path);
    my $framework_logs = _report_framework_logs($members, $path);
    my $recovery = _report_package_recovery($members, $receipt, $manifest, $export, $path);
    my $preservation = _report_package_preservation($members, $receipt, $manifest);
    _report_package_phase($members, $recovery, $preservation, \@entries);
    return { kind => 'freebsd-postscript-report-v2', receipt => $receipt, entries => \@entries,
        %$prerequisite_logs ? (prerequisite_logs => $prerequisite_logs) : (),
        %$framework_logs ? (framework_logs => $framework_logs) : (),
        $recovery ? (package_recovery => $recovery) : (),
        $preservation ? (package_preservation => $preservation) : (),
        archive => { path => "$path/archive.tar", sha256 => $status->{'archive-sha256'}, bytes => 0 + $status->{'archive-bytes'} } };
}

sub _report_framework_logs {
    my ($members, $path) = @_;
    my %logs = map { $_ => { path => "$path/$_", sha256 => sha256_hex($members->{$_}),
          bytes => length($members->{$_}) } } grep { exists($members->{$_}) }
      qw(framework.stdout framework.stderr supervisor.stderr);
    return \%logs;
}

sub _report_package_phase {
    my ($members, $recovery, $preservation, $entries) = @_;
    return unless $recovery || $preservation;
    _fail('Conflicting package provenance evidence') if ($recovery && $preservation)
      || exists($members->{'packages.result'});
    _fail('Interrupted package phase claims script execution') if grep { $_->{state} ne 'not-run' } @$entries;
    return;
}

sub _report_preserved_rejection {
    my ($members, $package, $manifest, $native_members) = @_;
    my $name = "packages/local-$package->{mode}.rejected";
    _fail('Preserved native rejection differs') unless @$native_members == 1 && $native_members->[0] eq $name
      && $package->{'native-sha256'} eq sha256_hex($members->{$name});
    my $native = _delivery_fields($members->{$name}, qw(format scope plan-reference request-sha256
        prior-request-sha256 config-sha256 pkg apply outcome complete));
    _fail('Preserved native rejection context differs') unless $native->{format} eq 'xcat-freebsd-local-rejection-1'
      && $native->{scope} eq "local-$package->{mode}" && $native->{'plan-reference'} eq $package->{plan}
      && $native->{'request-sha256'} eq $manifest->{request} && $native->{pkg} eq '2.6.2'
      && $native->{apply} eq 'not-started' && $native->{outcome} eq 'rejected' && $native->{complete} eq 'yes';
    for my $key (qw(prior-request config)) {
        _fail('Invalid preserved rejection digest') unless $native->{"$key-sha256"} =~ /\A[0-9a-f]{64}\z/x;
    }
    return;
}

sub _report_package_preservation {
    my ($members, $receipt, $manifest) = @_;
    my @native_members = grep { exists($members->{$_}) } qw(packages/local-update.rejected packages/local-verify.rejected);
    return unless exists($members->{'packages.preserved'}) || @native_members;
    _fail('Missing package preservation evidence') unless exists($members->{'packages.preserved'});
    my $package = _delivery_fields($members->{'packages.preserved'}, qw(format run snapshot plan mode
        initial-sha256 previous-sha256 reason native-sha256 execution complete));
    _fail('Package preservation context differs') unless $package->{format} eq 'xcat-freebsd-postscript-package-preserved-1'
      && $package->{run} eq $receipt->{run} && $package->{snapshot} eq $receipt->{snapshot}
      && $package->{plan} eq $receipt->{plan} && $package->{mode} eq $manifest->{'package-mode'}
      && $package->{mode} =~ /\A(?:verify|update)\z/x
      && $package->{'initial-sha256'} =~ /\A[0-9a-f]{64}\z/x && $package->{'previous-sha256'} =~ /\A[0-9a-f]{64}\z/x
      && $package->{execution} eq 'uncertain' && $package->{complete} eq 'yes';
    if ($package->{reason} eq 'no-actions') {
        _fail('Unexpected preservation rejection') unless $package->{'native-sha256'} eq '-' && @native_members == 0;
    } elsif ($package->{reason} eq 'native-rejected') {
        _report_preserved_rejection($members, $package, $manifest, \@native_members);
    } else {
        _fail('Invalid package preservation reason');
    }
    return { scope => 'previous-provenance', execution => 'uncertain', reason => $package->{reason},
        receipt_sha256 => sha256_hex($members->{'packages.preserved'}) };
}

sub _report_native_package_recovery {
    my ($bytes, $package) = @_;
    my $native = _delivery_fields($bytes, qw(format scope plan-reference
        request-sha256 prior-request-sha256 started-sha256 before-sha256 observed-sha256 managed-request-sha256
        operation-scope actions-sha256 rejected-sha256 pkg packages execution complete));
    _fail('Native package recovery context differs') unless $native->{format} eq 'xcat-freebsd-local-recover-1'
      && $native->{scope} eq 'provenance-only' && $native->{'plan-reference'} eq $package->{plan}
      && $native->{'request-sha256'} eq $package->{'request-sha256'}
      && $native->{'managed-request-sha256'} eq $package->{'managed-sha256'}
      && $native->{'operation-scope'} eq "local-$package->{mode}" && $native->{pkg} eq '2.6.2'
      && $native->{packages} =~ /\A[1-9][0-9]{0,3}\z/x
      && $native->{execution} eq 'uncertain' && $native->{complete} eq 'yes';
    _fail('Native package recovery count exceeds its bound') if $native->{packages} > 8192;
    for my $key (qw(prior-request started before observed)) {
        _fail('Invalid native recovery digest') unless $native->{"$key-sha256"} =~ /\A[0-9a-f]{64}\z/x;
    }
    for my $key (qw(actions rejected)) {
        _fail('Invalid native recovery authorization digest') unless $native->{"$key-sha256"} =~ /\A(?:-|[0-9a-f]{64})\z/x;
    }
    return $native;
}

sub _report_package_recovery {
    my ($members, $receipt, $manifest, $export, $path) = @_;
    my @required = qw(packages.recovered packages/recovery.result packages/recovery.capture
        packages/recovery.stdout packages/recovery.stderr);
    return unless grep { exists($members->{$_}) } @required;
    _fail('Incomplete package recovery evidence') if grep { !exists($members->{$_}) } @required;
    my $package = _delivery_fields($members->{'packages.recovered'}, qw(format run snapshot plan mode
        initial-sha256 previous-sha256 request-sha256 config-sha256 attempt native-sha256 managed-sha256
        capture-sha256 stdout-sha256 stderr-sha256 execution complete));
    _fail('Package recovery context differs') unless $package->{format} eq 'xcat-freebsd-postscript-package-recovery-1'
      && $package->{run} eq $receipt->{run} && $package->{snapshot} eq $receipt->{snapshot}
      && $package->{plan} eq $receipt->{plan} && $package->{mode} eq $manifest->{'package-mode'}
      && $package->{mode} =~ /\A(?:verify|update)\z/x && $package->{'request-sha256'} eq $manifest->{request}
      && $package->{attempt} =~ /\Arecovery[.][A-Za-z0-9]{8}\z/x
      && $package->{execution} eq 'uncertain' && $package->{complete} eq 'yes';
    for my $key (qw(initial previous request config native managed capture stdout stderr)) {
        _fail('Invalid package recovery digest') unless $package->{"$key-sha256"} =~ /\A[0-9a-f]{64}\z/x;
    }
    for my $binding ([native => 'result'], [capture => 'capture'], [stdout => 'stdout'], [stderr => 'stderr']) {
        _fail('Package recovery evidence differs') unless $package->{"$binding->[0]-sha256"}
          eq sha256_hex($members->{"packages/recovery.$binding->[1]"});
    }
    my $native = _report_native_package_recovery($members->{'packages/recovery.result'}, $package);
    my $capture = _delivery_fields($members->{'packages/recovery.capture'}, qw(format status stdout-bytes
        stderr-bytes stdout-truncated stderr-truncated stdout-open stderr-open));
    _fail('Package recovery execution differs') unless $capture->{format} eq 'xcat-freebsd-postscript-capture-1'
      && $capture->{status} eq '0' && $capture->{'stdout-open'} eq 'no' && $capture->{'stderr-open'} eq 'no';
    my %logs = map { $_ => { path => "$path/packages.recovery.$_", bytes => length($members->{"packages/recovery.$_"}),
          sha256 => sha256_hex($members->{"packages/recovery.$_"}) } } qw(stdout stderr);
    _report_capture_streams(\%logs, $capture, $export->{binding}{log_limit});
    return { scope => 'provenance-only', execution => 'uncertain', packages => 0 + $native->{packages},
        attempt => $package->{attempt}, receipt_sha256 => sha256_hex($members->{'packages.recovered'}), %logs };
}

sub _report_files {
    my ($path, $members, $write) = @_;
    for my $name (sort keys %$members) {
        (my $flat = $name) =~ s{/}{.}gx;
        _write("$path/$flat", $members->{$name}, 4194304) if $write;
        _fail('Retained evidence file differs') unless _read("$path/$flat", 4194304) eq $members->{$name};
    }
    return;
}

sub _collect_report {
    my ($transport, $receipt, $path) = @_;
    my $export = $transport->{export};
    my $run = $export->{binding}{run};
    my $attempt = $transport->{attempt};
    $transport->{phase} = 'evidence';
    my $bytes = _delivery_command($transport, 'xdsh', ["/usr/local/libexec/xcat-postscript evidence $run"]);
    my $status = _report_status($bytes, $export, $receipt);
    my $stage = "$attempt/content";
    mkdir($stage, oct('0700')) or _fail('Cannot create report stage');
    _write("$stage/status", $bytes, 4096);
    _write("$stage/observation", $receipt, 4096);
    $transport->{phase} = 'evidence transfer';
    my $output = _delivery_command($transport, 'xdcp', ['-P', $status->{path}, $stage]);
    _fail('Unexpected evidence transfer output') if length($output);
    my $archive = "$stage/archive.tar._$export->{node}";
    $transport->{phase} = 'evidence validation';
    my $members = _report_members($archive, $export, $status);
    my $report = _report_content($members, $export, $receipt, $status, $path);
    _report_files($stage, $members, 1);
    rename($archive, "$stage/archive.tar") or _fail('Cannot retain evidence archive');
    sysopen(my $file, "$stage/archive.tar", O_RDONLY | O_NOFOLLOW) or _fail('Cannot open evidence archive');
    $file->sync or _fail('Cannot sync evidence archive');
    close($file) or _fail('Cannot close evidence archive');
    _write("$stage/report.json", _json($report) . "\n", 16777216);
    _sync_directory($stage);
    $transport->{phase} = 'report publication';
    rename($stage, $path) or _fail('Cannot publish report');
    _sync_directory($attempt);
    _sync_directory($transport->{root});
    return $report;
}

sub collect_execution {
    my ($run, $subrequest, @arguments) = @_;
    my ($report, $attempt);
    my $transport = { phase => 'request', subrequest => $subrequest };
    my $ok = eval {
        _fail('Reporting requires a subrequest') unless ref($subrequest) eq 'CODE';
        my ($options, $username) = _delivery_options(@arguments);
        my $root = _root($options, 0);
        _fail('Unsupported report path') unless $root =~ m{\A/[A-Za-z0-9_./-]+\z}x;
        my $export = _export_descriptor($root, $run);
        my $lock_path = "$root/report-$run.lock";
        sysopen(my $lock, $lock_path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, oct('0600'))
          or _fail('Cannot open report lock');
        my $named = _file_state($lock_path, 0);
        my @opened = stat($lock);
        _fail('Report lock changed') unless @opened && $opened[0] == $named->[0] && $opened[1] == $named->[1];
        flock($lock, LOCK_EX | LOCK_NB) or _fail('Reporting is busy');
        my $path = "$root/report-$run";
        if (lstat($path)) {
            $transport->{phase} = 'retained report';
            _directory($path, 0);
            my $receipt = _read(lstat("$path/observation") ? "$path/observation" : "$root/delivery-$run.result", 4096);
            my $status = _report_status(_read("$path/status", 4096), $export, $receipt);
            my $members = _report_members("$path/archive.tar", $export, $status);
            $report = _report_content($members, $export, $receipt, $status, $path);
            _report_files($path, $members, 0);
            _fail('Retained report differs') unless _read("$path/report.json", 16777216) eq _json($report) . "\n";
            _sync_directory($root);
        } else {
            $attempt = tempdir(".report-$run.XXXXXXXX", DIR => $root, CLEANUP => 0);
            _directory($attempt, 0);
            _sync_directory($root);
            @{$transport}{qw(root export attempt username)} = ($root, $export, $attempt, $username);
            $transport->{phase} = 'current receipt';
            my $receipt = lstat("$root/delivery-$run.result") ? _read("$root/delivery-$run.result", 4096)
              : _delivery_command($transport, 'xdsh', ["/usr/local/libexec/xcat-postscript receipt $run"]);
            my $observed = _delivery_receipt($receipt, $export);
            _fail('Execution is still mutable') unless $observed->{complete} eq 'yes' || $observed->{outcome} eq 'uncertain';
            $report = _collect_report($transport, $receipt, $path);
            _discard_attempt($attempt);
            undef $attempt;
        }
        close($lock) or _fail('Cannot close report lock');
        1;
    };
    unless ($ok) {
        if (defined($attempt)) {
            my $recorded = eval { _write("$attempt/failure", "$transport->{phase}\n", 128); 1; };
            _fail('FreeBSD postscript reporting failed during failure retention') unless $recorded;
        }
        _fail("FreeBSD postscript reporting failed during $transport->{phase}");
    }
    return $report;
}

1;
