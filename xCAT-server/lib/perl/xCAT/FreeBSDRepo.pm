package xCAT::FreeBSDRepo;

use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK O_WRONLY O_CREAT O_EXCL S_ISREG S_ISDIR S_ISLNK);
use File::Temp;
use JSON;
use xCAT::FreeBSDPkg;

my %LIMITS = (max_entries => 100000, max_bytes => 1099511627776,
    max_file_bytes => 17179869184);
my $BASE = 'usr/freebsd-packages/offline';
my $ABI = 'FreeBSD:15:amd64';
my $CATALOGUE_LIMIT = 67108864;

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

sub _digest {
    my $value = shift;
    return defined($value) && !ref($value) && $value =~ /\A[0-9a-f]{64}\z/x;
}

sub _json {
    return JSON->new->utf8->canonical->allow_nonref->encode(shift);
}

sub _decode {
    my ($bytes, $description) = @_;
    my $decoded;
    my $ok = eval { $decoded = JSON->new->utf8->max_depth(32)->decode($bytes); 1; };
    _fail("Invalid JSON in $description") unless $ok;
    return $decoded;
}

sub _write_private {
    my ($path, $bytes) = @_;
    sysopen(my $fh, $path, O_WRONLY | O_CREAT | O_EXCL, oct('0600'))
      or _fail("Cannot create repository inspection file: $!");
    binmode($fh) or _fail("Cannot write repository inspection bytes: $!");
    print {$fh} $bytes or _fail("Cannot write repository inspection file: $!");
    close($fh) or _fail("Cannot close repository inspection file: $!");
    return;
}

sub _mkdir_private {
    my $path = shift;
    mkdir($path, oct('0700')) or _fail("Cannot create repository inspection directory: $!");
    return $path;
}

sub _file_url {
    my $path = shift;
    $path = encode_utf8($path) if utf8::is_utf8($path);
    $path =~ s{([^A-Za-z0-9_./~-])}{sprintf('%%%02X', ord($1))}egx;
    return "file://$path";
}

sub _metadata {
    my ($bytes, $description) = @_;
    my %values;
    pos($bytes) = 0;
    while ($bytes =~ /\G\s*([a-z_]+)\s*=\s*(?:"([^"\x00-\x1f]*)"|([0-9]+))\s*;/gcx) {
        _fail("Duplicate repository metadata key in $description: $1") if exists($values{$1});
        $values{$1} = defined($2) ? $2 : $3;
    }
    my $remaining = substr($bytes, pos($bytes) || 0);
    _fail("Unsupported repository metadata syntax in $description") if $remaining =~ /\S/x;
    my %fixed = (version => '2', packing_format => 'tzst', manifests => 'packagesite.yaml',
        data => 'data', manifests_archive => 'packagesite');
    for my $key (keys %fixed) {
        _fail("Unsupported repository metadata value in $description: $key")
          if !defined($values{$key}) || $values{$key} ne $fixed{$key};
    }
    _fail("Unsupported repository metadata key in $description")
      if grep { !exists($fixed{$_}) && $_ ne 'filesite' && $_ ne 'filesite_archive' } keys %values;
    for my $key (qw(filesite filesite_archive)) {
        _fail("Unsupported repository metadata value in $description: $key")
          unless defined($values{$key}) && $values{$key} =~ /\Afiles(?:ite(?:[.]yaml)?)?\z/x;
    }
    return \%values;
}

sub _native_entry {
    my ($path, $kind, $ancestor) = @_;
    my @state = lstat($path);
    _fail("Missing or unsupported native $kind: $path") unless @state;
    my %types = (directory => S_ISDIR($state[2]), file => S_ISREG($state[2]),
        link => S_ISLNK($state[2]), program => S_ISREG($state[2]) || S_ISLNK($state[2]));
    _fail("Missing or unsupported native $kind: $path") unless $types{$kind};
    _fail("Untrusted native path owner: $path") unless $state[4] == 0 || $state[4] == $>;
    return if S_ISLNK($state[2]);
    _fail("Writable native path: $path") if ($state[2] & oct('0022'))
      && !($ancestor && S_ISDIR($state[2]) && ($state[2] & oct('1000')));
    _fail("Unsafe native file links or privileges: $path") if S_ISREG($state[2])
      && ($state[3] != 1 || ($state[2] & oct('6000')));
    return;
}

sub _native_path {
    my ($path, $kind) = @_;
    _fail('Invalid protected native path') if !defined($path) || ref($path)
      || length($path) > 4096 || $path !~ m{\A/[^\x00-\x1f\x7f]+\z}x;
    my @parts = split(m{/}x, substr($path, 1), -1);
    _fail('Invalid protected native path component')
      if grep { !length($_) || $_ eq '.' || $_ eq '..' } @parts;
    pop @parts;
    _native_entry('/', 'directory', 1);
    my $parent = '';
    for my $part (@parts) {
        $parent .= "/$part";
        _native_entry($parent, 'directory', 1);
    }
    _native_entry($path, $kind, 0);
    return;
}

sub _native_libraries {
    my $directory = shift;
    _native_path($directory, 'directory');
    my $libraries = snapshot_tree($directory);
    for my $path (sort keys %{$libraries->{entries}}) {
        _native_entry("$directory/$path", $libraries->{entries}{$path}{type}, 0);
    }
    return $libraries;
}

sub _native_context {
    my ($tool, $scratch) = @_;
    _fail('A pinned native pkg tool is required') if ref($tool) ne 'HASH'
      || !_digest($tool->{sha256}) || !defined($tool->{path}) || ref($tool->{path})
      || $tool->{path} !~ m{\A/[^\x00\r\n]+\z}x;
    _fail('Unknown native pkg tool option')
      if grep { $_ !~ /\A(?:path|sha256|library_directory|library_digest)\z/x } keys %$tool;
    _native_path($tool->{path}, 'file');
    my ($binary) = _file($tool->{path}, 536870912, 0);
    _fail('Native pkg executable checksum mismatch') if $binary->{sha256} ne $tool->{sha256};
    _fail('Native pkg tool is not executable') unless -x $tool->{path};
    my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C');
    my $identity = { version => '2.8.2', sha256 => $binary->{sha256} };
    if (exists($tool->{library_directory}) || exists($tool->{library_digest})) {
        _fail('A pinned native pkg library directory is required') unless _digest($tool->{library_digest});
        _native_path($tool->{library_directory}, 'directory');
        my $directory = _root($tool->{library_directory});
        _fail('Native pkg library directory cannot contain a colon') if $directory =~ /:/x;
        _fail('Native pkg library directory cannot contain loader separators or variables') if $directory =~ /[;\$]/x;
        my $libraries = _native_libraries($directory);
        _fail('Native pkg library checksum mismatch') if $libraries->{digest} ne $tool->{library_digest};
        $environment{LD_LIBRARY_PATH} = $directory;
        $identity->{library_digest} = $libraries->{digest};
    }
    return { executable => $tool->{path}, environment => \%environment,
        scratch => $scratch, identity => $identity };
}

sub _native_config {
    my ($context, $name, $repository) = @_;
    return _native_config_map($context, $name,
        $repository ? { xcat_freebsd => $repository } : {});
}

sub _native_config_map {
    my ($context, $name, $repositories) = @_;
    my $root = _mkdir_private("$context->{scratch}/$name");
    my $repos = _mkdir_private("$root/repos");
    _write_private("$repos/native.conf", _json($repositories)) if keys %$repositories;
    my $config = { ABI => $ABI, OSVERSION => 1501000, PKG_DBDIR => "$root/db",
        PKG_CACHEDIR => "$root/cache", REPOS_DIR => [$repos], REPO_AUTOUPDATE => JSON::false,
        CONSERVATIVE_UPGRADE => JSON::true,
        PKG_ENABLE_PLUGINS => JSON::false, PKG_TRIGGERS_ENABLE => JSON::false,
        HANDLE_RC_SCRIPTS => JSON::false, SYSLOG => JSON::false, IGNORE_OSVERSION => JSON::false,
        ASSUME_ALWAYS_YES => JSON::false, FETCH_RETRY => 1, FETCH_TIMEOUT => 3 };
    _write_private("$root/pkg.conf", _json($config));
    return "$root/pkg.conf";
}

sub _native_run {
    my ($context, $config, @arguments) = @_;
    return xCAT::FreeBSDPkg::run_command([$context->{executable}, '-C', $config, @arguments],
        cwd => "$context->{scratch}", environment => $context->{environment}, timeout => 60,
        stdout_limit => $CATALOGUE_LIMIT, stderr_limit => 1048576);
}

sub _native_output {
    my ($context, $config, $description, @arguments) = @_;
    my $result;
    if ($description eq 'dependency resolution' || $description eq 'resolver catalogue update'
        || $description eq 'resolver catalogue query') {
        my $ok = eval { $result = _native_run($context, $config, @arguments); 1; };
        _fail("Native pkg $description failed")
          if !$ok || $result->{exitcode} || $result->{signal} || length($result->{stderr});
        return $result->{stdout};
    }
    $result = _native_run($context, $config, @arguments);
    _fail("Native pkg $description failed: " . substr($result->{stderr}, 0, 1024))
      if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub _native_elf_magic {
    my $path = shift;
    sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      or _fail("Cannot open native ELF file: $!");
    binmode($fh) or _fail("Cannot read native ELF bytes: $!");
    my $read = read($fh, my $magic, 4);
    _fail("Cannot read native ELF header: $!") unless defined($read);
    close($fh) or _fail("Cannot close native ELF file: $!");
    return $read == 4 && $magic eq "\x7fELF";
}

sub _native_elf {
    my ($path, $directory, $scratch, $readelf) = @_;
    _fail('Native planning requires ELF executables and libraries') unless _native_elf_magic($path);
    my $result = xCAT::FreeBSDPkg::run_command(
        [$readelf, '--file-header', '--dynamic', '--wide', $path], cwd => "$scratch",
        environment => { PATH => '/usr/bin:/bin', LC_ALL => 'C' }, timeout => 60,
        stdout_limit => 1048576, stderr_limit => 65536);
    _fail('Native ELF inspection failed') if $result->{exitcode} || $result->{signal};
    my $output = $result->{stdout};
    _fail('Unsupported native planning ELF format')
      unless $output =~ /^\s*Class:\s+ELF(?:32|64)\s*$/mx
      && $output =~ /^\s*Type:\s+(?:DYN|EXEC)\b/mx;
    my @needed;
    for my $line (split(/\n/x, $output)) {
        next unless $line =~ /^\s*0x[0-9a-f]+\s+\((\w+)\)\s+(.*)$/ix;
        my ($tag, $value) = ($1, $2);
        _fail('Native ELF loader forwarding is not supported') if $tag =~ /\A(?:FILTER|AUXILIARY|AUDIT|DEPAUDIT)\z/x;
        next unless $tag =~ /\A(?:NEEDED|RPATH|RUNPATH)\z/x;
        my ($reference) = $value =~ /\[([^\[\]\x00-\x1f]+)\]\s*\z/x;
        _fail('Invalid native ELF library reference') unless defined($reference);
        if ($tag eq 'NEEDED') {
            _fail('Native ELF dependencies must be library basenames') unless $reference =~ /\A[A-Za-z0-9_.+-]+\z/x;
            push @needed, $reference;
        } else {
            _fail('Native ELF loader path differs from the pinned library directory') unless $reference eq $directory;
        }
    }
    return \@needed;
}

sub _native_solver_libraries {
    my ($tool, $context, $resolver) = @_;
    _native_path('/usr/bin/readelf', 'program');
    my $readelf = abs_path('/usr/bin/readelf');
    _native_path($readelf, 'file');
    _fail('Native ELF inspector is not executable') unless -x $readelf;
    my $directory = $context->{environment}{LD_LIBRARY_PATH};
    my $libraries = _native_libraries($directory);
    _fail('Native pkg library checksum mismatch') if $libraries->{digest} ne $tool->{library_digest};
    my @libpkg;
    for my $client ($context, $resolver) {
        my $needed = _native_elf($client->{executable}, $directory, $context->{scratch}, $readelf);
        my @names = grep { /\Alibpkg[.]so[.][0-9]+\z/x } @$needed;
        _fail('Native planning executable names multiple libpkg ABIs') if @names > 1;
        push @libpkg, @names ? $names[0] : undef;
    }
    _fail('Native resolver must name one pinned libpkg ABI') unless defined($libpkg[1]);
    _fail('Native planning executables require different libpkg ABIs')
      if defined($libpkg[0]) && $libpkg[0] ne $libpkg[1];
    my $target = _resolve_link($libpkg[1], $libraries->{entries});
    _fail('Native libpkg dependency is absent from the pinned library directory')
      unless defined($target) && $libraries->{entries}{$target}{type} eq 'file'
      && _native_elf_magic("$directory/$target");
    for my $path (sort keys %{$libraries->{entries}}) {
        next unless $libraries->{entries}{$path}{type} eq 'file' && _native_elf_magic("$directory/$path");
        my $needed = _native_elf("$directory/$path", $directory, $context->{scratch}, $readelf);
        _fail('Native library requires a different libpkg ABI')
          if grep { /\Alibpkg[.]so/x && $_ ne $libpkg[1] } @$needed;
    }
    return;
}

sub _solver_key {
    my ($key, $destination) = @_;
    _fail('Invalid resolver public-key pin') if ref($key) ne 'HASH'
      || !_digest($key->{sha256}) || !defined($key->{path}) || ref($key->{path})
      || $key->{path} !~ m{\A/[^\x00\r\n]+\z}x;
    _fail('Unknown resolver public-key field') if grep { $_ ne 'path' && $_ ne 'sha256' } keys %$key;
    my ($actual, $bytes) = _file($key->{path}, 1048576, 1);
    _fail('Resolver public key differs from its verified import') if $actual->{sha256} ne $key->{sha256};
    _write_private("$destination/repository.pub", $bytes) if defined($destination);
    return defined($destination)
      ? { signature_type => 'pubkey', pubkey => "$destination/repository.pub" } : {};
}

sub _solver_file {
    my ($path, $expected, $destination) = @_;
    _fail('Invalid resolver catalogue file pin') if ref($expected) ne 'HASH'
      || !_digest($expected->{sha256}) || !defined($expected->{size})
      || ref($expected->{size}) || $expected->{size} !~ /\A[1-9][0-9]{0,8}\z/x
      || $expected->{size} > $CATALOGUE_LIMIT;
    _fail('Unknown resolver catalogue file pin')
      if grep { $_ ne 'size' && $_ ne 'sha256' } keys %$expected;
    my ($actual, $bytes) = _file($path, $CATALOGUE_LIMIT, 1);
    _fail('Resolver catalogue differs from its verified import')
      if $actual->{size} != $expected->{size} || $actual->{sha256} ne $expected->{sha256};
    _write_private($destination, $bytes) if defined($destination);
    return;
}

sub _solver_catalogue {
    my ($reference, $destination) = @_;
    _fail('Invalid resolver catalogue reference') if ref($reference) ne 'HASH'
      || !defined($reference->{directory}) || ref($reference->{directory})
      || ref($reference->{files}) ne 'HASH';
    _fail('Unknown resolver catalogue field')
      if grep { $_ !~ /\A(?:directory|files|key)\z/x } keys %$reference;
    my $directory = _root($reference->{directory});
    my %required = map { $_ => 1 } qw(meta.conf data.pkg packagesite.pkg);
    _fail('Invalid resolver catalogue file roster')
      if keys(%{$reference->{files}}) != 3
      || grep { !$required{$_} } keys %{$reference->{files}};
    for my $name (sort keys %required) {
        _solver_file("$directory/$name", $reference->{files}{$name},
            defined($destination) ? "$destination/$name" : undef);
    }
    return exists($reference->{key}) ? _solver_key($reference->{key}, $destination)
      : { signature_type => 'none' };
}

sub _solver_request {
    my $names = shift;
    _fail('Invalid native resolver root list') if ref($names) ne 'ARRAY' || @$names > 8192;
    my %seen;
    for my $name (@$names) {
        _fail('Invalid native resolver package name') if !defined($name) || ref($name)
          || !length($name) || length($name) > 1024 || $name =~ /[\x00-\x1f\x7f]/x || $seen{$name}++;
    }
    my $request = encode_utf8(join('', map { "$_\n" } @$names));
    _fail('Native resolver request exceeds its size limit') if length($request) > 8388608;
    return $request;
}

sub _solver_response {
    my $bytes = shift;
    my $result = _decode($bytes, 'native dependency resolution');
    _fail('Invalid native resolver response') if ref($result) ne 'HASH'
      || !defined($result->{format}) || ref($result->{format})
      || $result->{format} ne 'xcat-freebsd-resolver-1'
      || !defined($result->{version}) || ref($result->{version}) || $result->{version} ne '2.8.2'
      || ref($result->{jobs}) ne 'ARRAY' || !@{$result->{jobs}} || @{$result->{jobs}} > 8192;
    _fail('Unknown native resolver response field')
      if grep { $_ !~ /\A(?:format|version|jobs)\z/x } keys %$result;
    return $result->{jobs};
}

sub _solver_executable {
    my $solver = shift;
    _fail('A pinned native resolver is required') if ref($solver) ne 'HASH'
      || !_digest($solver->{sha256}) || !defined($solver->{path}) || ref($solver->{path})
      || $solver->{path} !~ m{\A/[^\x00\r\n]+\z}x;
    _fail('Unknown native resolver executable option') if grep { $_ ne 'path' && $_ ne 'sha256' } keys %$solver;
    return $solver;
}

sub _solver_dependencies {
    my ($package, $providers) = @_;
    return unless exists($package->{deps});
    _fail('Native resolver catalogue differs from its verified import')
      unless ref($package->{deps}) eq 'HASH';
    my %dependencies;
    for my $name (keys %{$package->{deps}}) {
        _fail('Native resolver catalogue differs from its verified import')
          unless ref($package->{deps}{$name}) eq 'HASH';
        my %dependency = %{$package->{deps}{$name}};
        my @versions = exists($providers->{$name}) ? values %{$providers->{$name}} : ();
        _fail('Native resolver catalogue differs from its verified import') if @versions > 1;
        # Native dependency readback uses the same repository's provider version.
        delete($dependency{version});
        $dependency{version} = $versions[0] if @versions;
        $dependencies{$name} = \%dependency;
    }
    $package->{deps} = \%dependencies;
    return;
}

sub _solver_readback {
    my ($context, $config, $count) = @_;
    for my $index (0 .. $count - 1) {
        my $name = "r$index";
        my $expected = _original_catalogues($context, "$context->{scratch}/$name");
        my $bytes = _native_output($context, $config, 'resolver catalogue query',
            'search', '-U', '-r', $name, '--raw', '--raw-format', 'json-compact', '-g', '*');
        my $actual = _records(_decode($bytes, 'resolver catalogue query'),
            'resolver catalogue query');
        my (%planning, %native, %providers);
        for my $package (values %$expected) {
            $providers{$package->{name}}{_json($package->{version})} = $package->{version};
        }
        for my $identity (keys %$actual) {
            my %package = %{$actual->{$identity}};
            _fail('Native resolver catalogue differs from its verified import')
              unless ref($package{licenses}) eq 'ARRAY' && @{$package{licenses}} == 1
                && _json($package{licenses}[0]) =~ /\A"/x;
            # The remote license aggregate does not preserve license identities.
            delete($package{licenses});
            $native{$identity} = \%package;
        }
        for my $identity (keys %$expected) {
            my %package = %{$expected->{$identity}};
            _solver_dependencies(\%package, \%providers);
            delete($package{licenses});
            if (exists($actual->{$identity})) {
                # These fields do not constrain a fresh INSTALL selection.
                delete @package{grep { !exists($actual->{$identity}{$_}) }
                    qw(vital messages shlibs_required_ignore users groups shlibs_provided_ignore)};
            }
            $planning{$identity} = \%package;
        }
        _fail('Native resolver catalogue differs from its verified import')
          if _json(\%native) ne _json(\%planning);
    }
    return;
}

sub solve_catalogues {
    my ($references, $names, @arguments) = @_;
    _fail('Native resolver options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fail('Unknown native resolver option') if grep { $_ ne 'tool' && $_ ne 'solver' } keys %options;
    _fail('Invalid native resolver repository list') if ref($references) ne 'ARRAY'
      || !@$references || @$references > 32;
    my $request = _solver_request($names);
    my $solver = _solver_executable($options{solver});
    _fail('Native planning requires a pinned library directory') unless ref($options{tool}) eq 'HASH'
      && exists($options{tool}{library_directory}) && _digest($options{tool}{library_digest});
    my $scratch = File::Temp->newdir('xcat-freebsd-solver-XXXXXXXX', DIR => '/tmp');
    my $empty_root = _mkdir_private("$scratch/empty-root");
    _native_path($empty_root, 'directory');
    my $context = _native_context($options{tool}, $scratch);
    my %solver_tool = (%{$options{tool}}, %$solver);
    my $resolver = _native_context(\%solver_tool, $scratch);
    _native_solver_libraries($options{tool}, $context, $resolver);
    my %repositories;
    for my $index (0 .. $#$references) {
        my $directory = _mkdir_private("$scratch/r$index");
        my $signature = _solver_catalogue($references->[$index], $directory);
        $repositories{"r$index"} = { %$signature, url => _file_url($directory),
            enabled => JSON::true, priority => 1000 - $index };
    }
    my $config = _native_config_map($context, 'resolve', \%repositories);
    for my $client ($context, $resolver) {
        _fail('Native resolver requires pkg version 2.8.2')
          if _native_output($client, $config, 'version check', '-v') ne "2.8.2\n";
    }
    _write_private("$scratch/request", $request);
    _native_output($context, $config, 'resolver catalogue update', 'update', '-f');
    _solver_readback($context, $config, scalar(@$references));
    my $jobs = @$names ? _solver_response(_native_output($resolver, $config, 'dependency resolution',
        'resolve', "$scratch/request", $empty_root)) : [];
    _native_path($empty_root, 'directory');
    my $root_entries = 0;
    _fail('Native resolver root is not empty')
      if _directory_names($empty_root, \$root_entries, 1);
    _solver_catalogue($_, undef) for @$references;
    _native_context($options{tool}, $scratch);
    _native_context(\%solver_tool, $scratch);
    return { resolver => $resolver->{identity}, jobs => $jobs };
}

sub _repository_trust {
    my ($trust, $tree, $scratch) = @_;
    _fail('An explicit repository trust policy is required') if ref($trust) ne 'HASH'
      || !defined($trust->{type}) || ref($trust->{type});
    if ($trust->{type} eq 'operator-trusted-tree') {
        _fail('Unknown trusted-tree option') if grep { $_ ne 'type' && $_ ne 'digest' } keys %$trust;
        _fail('Trusted repository tree checksum mismatch')
          if !_digest($trust->{digest}) || $trust->{digest} ne $tree->{digest};
        return ({ signature_type => 'none' }, { type => $trust->{type}, digest => $tree->{digest} });
    }
    _fail('Unsupported repository trust policy') if $trust->{type} ne 'pubkey';
    _fail('Unknown repository public-key option') if grep { $_ !~ /\A(?:type|path|sha256)\z/x } keys %$trust;
    _fail('A pinned repository public key is required') if !_digest($trust->{sha256})
      || !defined($trust->{path}) || ref($trust->{path}) || $trust->{path} !~ m{\A/[^\x00\r\n]+\z}x;
    my ($identity, $bytes) = _file($trust->{path}, 1048576, 1);
    _fail('Repository public-key checksum mismatch') if $identity->{sha256} ne $trust->{sha256};
    _write_private("$scratch/repository.pub", $bytes);
    return ({ signature_type => 'pubkey', pubkey => "$scratch/repository.pub" },
        { type => 'pubkey', sha256 => $identity->{sha256} });
}

sub _catalogue_member {
    my ($context, $archive, $member) = @_;
    my $result = xCAT::FreeBSDPkg::run_command(['/usr/bin/tar', '-xOf', $archive, $member],
        cwd => "$context->{scratch}", environment => { PATH => '/usr/bin:/bin', LC_ALL => 'C' },
        timeout => 60, stdout_limit => $CATALOGUE_LIMIT);
    _fail("Cannot read repository catalogue member: $member") if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

sub _records {
    my ($records, $description) = @_;
    _fail("Invalid package array in $description") if ref($records) ne 'ARRAY'
      || !@$records || @$records > 100000;
    my %indexed;
    for my $package (@$records) {
        _fail("Invalid package record in $description") unless ref($package) eq 'HASH';
        for my $field (qw(name version origin abi)) {
            my $value = $package->{$field};
            _fail("Invalid package $field in $description") if !defined($value) || ref($value)
              || !length($value) || length($value) > 1024 || $value =~ /[\x00-\x1f\x7f]/x;
        }
        my $key = join("\0", @$package{qw(name version origin abi)});
        _fail("Duplicate package identity in $description") if exists($indexed{$key});
        $indexed{$key} = $package;
    }
    return \%indexed;
}

sub _original_catalogues {
    my ($context, $view) = @_;
    my $data = _decode(_catalogue_member($context, "$view/data.pkg", 'data'), 'data catalogue');
    _fail('Invalid data catalogue object') unless ref($data) eq 'HASH';
    _fail('Unsupported data catalogue field')
      if grep { $_ !~ /\A(?:packages|groups|expired_packages)\z/x } keys %$data;
    for my $field (qw(groups expired_packages)) {
        _fail("Unsupported nonempty data catalogue $field")
          if ref($data->{$field}) ne 'ARRAY' || @{$data->{$field}};
    }
    my $bytes = _catalogue_member($context, "$view/packagesite.pkg", 'packagesite.yaml');
    my @manifests = map { _decode($_, 'packagesite catalogue') } grep { length($_) } split(/\n/x, $bytes);
    my $primary = _records($data->{packages}, 'data catalogue');
    my $fallback = _records(\@manifests, 'packagesite catalogue');
    _fail('Repository catalogue records disagree') if _json($primary) ne _json($fallback);
    return $primary;
}

sub _native_catalogue {
    my ($context, $view, $name, $signature) = @_;
    my $directory = _mkdir_private("$context->{scratch}/source-$name");
    for my $file ('meta.conf', "$name.pkg") {
        my (undef, $bytes) = _file("$view/$file", $CATALOGUE_LIMIT, 1);
        _write_private("$directory/$file", $bytes);
    }
    my $config = _native_config($context, "query-$name", { %$signature,
        url => _file_url($directory), enabled => JSON::true });
    _native_output($context, $config, 'catalogue update', 'update', '-f');
    my $bytes = _native_output($context, $config, 'catalogue query', 'search', '-U', '-r',
        'xcat_freebsd', '--raw', '--raw-format', 'json-compact', '-g', '*');
    return _records(_decode($bytes, 'native catalogue query'), "native $name query");
}

sub _archive_path {
    my ($package, $tree, $prefix) = @_;
    my $path = $package->{repopath};
    _fail('Invalid package archive path') if !defined($path) || ref($path)
      || length($path) > 4096 || $path !~ /[.]pkg\z/x
      || grep { !_component($_) } split(m{/}x, $path, -1);
    _fail('Conflicting package archive paths') if exists($package->{path})
      && (!defined($package->{path}) || ref($package->{path}) || $package->{path} ne $path);
    $path = length($prefix) ? "$prefix/$path" : $path;
    my $resolved = _resolve_link($path, $tree->{entries});
    my $entry = defined($resolved) ? $tree->{entries}{$resolved} : undef;
    _fail('Missing package archive') unless $entry && $entry->{type} eq 'file';
    my $size = $package->{pkgsize};
    _fail('Package archive size mismatch') if !defined($size) || ref($size)
      || $size !~ /\A[0-9]+\z/x || $size != $entry->{size};
    return ($resolved, $entry);
}

sub _package_compatibility {
    my $package = shift;
    my $abi = lc($package->{abi});
    _fail("Unsupported package ABI: $package->{name}") unless
      $abi =~ /\Afreebsd(?::(?:[*]|15(?::(?:[*]|amd64))?))?\z/x;
    my $annotations = $package->{annotations};
    return unless defined($annotations);
    _fail('Invalid package annotations') unless ref($annotations) eq 'HASH';
    return unless exists($annotations->{FreeBSD_version});
    my $version = $annotations->{FreeBSD_version};
    _fail("Incompatible package OSVERSION: $package->{name}") if !defined($version) || ref($version)
      || $version !~ /\A[0-9]+\z/x || $version < 1 || $version > 1501000;
    return;
}

sub _package_archive {
    my ($key, $package, $tree, $prefix) = @_;
    _package_compatibility($package);
    my ($path, $entry) = _archive_path($package, $tree, $prefix);
    my $sum = $package->{sum};
    _fail('Invalid package archive checksum') if !defined($sum) || ref($sum)
      || !length($sum) || length($sum) > 256 || $sum =~ /[^A-Za-z0-9\$]/x;
    return ($path, { %$entry, package_identity => $key, native_sum => $sum });
}

sub _archive_metadata {
    my ($context, $config, $source, $packages) = @_;
    my %archives;
    for my $key (sort keys %$packages) {
        my $package = $packages->{$key};
        my ($path, $archive) = _package_archive($key, $package, $source->{tree}, $source->{prefix});
        _fail('An archive is assigned to multiple package identities') if exists($archives{$path});
        _native_output($context, $config, 'archive checksum', 'checksum', '-q', '-c', $archive->{native_sum}, '--', "$source->{root}/$path");
        my $inside = _decode(_native_output($context, $config, 'archive manifest', 'info', '-F',
            "$source->{root}/$path", '--raw', '--raw-format', 'json-compact'), 'archive manifest');
        _fail('Invalid embedded package manifest') unless ref($inside) eq 'HASH';
        for my $field (keys %$package) {
            next if $field =~ /\A(?:path|repopath|pkgsize|sum)\z/x;
            _fail("Package archive metadata mismatch: $package->{name} $field")
              if !exists($inside->{$field}) || _json($inside->{$field}) ne _json($package->{$field});
        }
        $archives{$path} = $archive;
    }
    return \%archives;
}

sub _archive_inventory {
    my ($tree, $prefix, $archives) = @_;
    my %catalogues = map { (length($prefix) ? "$prefix/$_" : $_) => 1 } qw(data.pkg packagesite.pkg);
    for my $path (sort keys %{$tree->{entries}}) {
        next if $path !~ /[.]pkg\z/x || $tree->{entries}{$path}{type} eq 'directory';
        next if exists($tree->{unresolved_links}{$path});
        my $resolved = _resolve_link($path, $tree->{entries});
        _fail("Uncatalogued package archive: $path")
          if !defined($resolved) || (!exists($archives->{$resolved}) && !exists($catalogues{$resolved}));
    }
    return;
}

sub catalogue_prefix {
    my $prefix = shift;
    _fail('Invalid repository catalogue prefix') if !defined($prefix) || ref($prefix)
      || length($prefix) > 4096
      || (length($prefix) && grep { !_component($_) } split(m{/}x, $prefix, -1));
    return $prefix;
}

sub validate_repository_inventory {
    my $repository = shift;
    _fail('Invalid stored repository inventory') if ref($repository->{packages}) ne 'HASH'
      || ref($repository->{archives}) ne 'HASH';
    my $prefix = catalogue_prefix($repository->{catalogue_prefix});
    my $packages = _records([values %{$repository->{packages}}], 'stored repository inventory');
    _fail('Stored package identities disagree') if _json($packages) ne _json($repository->{packages});
    my %archives;
    for my $key (sort keys %$packages) {
        my ($path, $archive) = _package_archive($key, $packages->{$key}, $repository->{tree}, $prefix);
        _fail('An archive is assigned to multiple package identities') if exists($archives{$path});
        $archives{$path} = $archive;
    }
    _fail('Stored repository archive inventory disagrees') if _json(\%archives) ne _json($repository->{archives});
    _archive_inventory($repository->{tree}, $prefix, \%archives);
    return;
}

sub _inspect_repository {
    my ($root, $options, $tree) = @_;
    my $prefix = $options->{catalogue_prefix};
    my $source = length($prefix) ? "$root/$prefix" : $root;
    my $scratch = File::Temp->newdir('xcat-freebsd-repository-XXXXXXXX', TMPDIR => 1);
    my ($signature, $trust) = _repository_trust($options->{trust}, $tree, "$scratch");
    my $context = _native_context($options->{tool}, $scratch);
    my $empty_config = _native_config($context, 'inspection', undef);
    _fail('Native pkg version 2.8.2 is required') if
      _native_output($context, $empty_config, 'version check', '-v') ne "2.8.2\n";
    my $view = _mkdir_private("$scratch/catalogues");
    my (undef, $meta) = _file("$source/meta.conf", 65536, 1);
    my $metadata = _metadata($meta, 'meta.conf');
    if (-e "$source/meta" || -l "$source/meta") {
        my (undef, $other) = _file("$source/meta", 65536, 1);
        _fail('Repository metadata files disagree') if _json(_metadata($other, 'meta')) ne _json($metadata);
    }
    _write_private("$view/meta.conf", $meta);
    for my $name (qw(data packagesite)) {
        my (undef, $bytes) = _file("$source/$name.pkg", $CATALOGUE_LIMIT, 1);
        _write_private("$view/$name.pkg", $bytes);
    }
    my $records = _original_catalogues($context, $view);
    my $data = _native_catalogue($context, $view, 'data', $signature);
    my $manifests = _native_catalogue($context, $view, 'packagesite', $signature);
    _fail('Native repository catalogue views disagree') if _json($data) ne _json($manifests);
    _fail('Native repository package identities disagree') if
      _json([sort keys %$records]) ne _json([sort keys %$data]);
    my $archives = _archive_metadata($context, $empty_config,
        { root => $root, tree => $tree, prefix => $prefix }, $records);
    _archive_inventory($tree, $prefix, $archives);
    _fail('Repository changed during native inspection')
      if _snapshot($root, \%LIMITS, $tree->{unresolved_links})->{digest} ne $tree->{digest};
    _native_context($options->{tool}, $scratch);
    my $result = { format => 'xcat-freebsd-repository-1', abi => $ABI, osversion => 1501000,
        catalogue_prefix => $prefix, tree => $tree, trust => $trust, tool => $context->{identity},
        packages => $records, archives => $archives, metadata => $metadata,
        native_validated => 1, selection_validated => 0 };
    return { %$result, digest => sha256_hex(_json($result)) };
}

sub inspect_repository {
    my ($root, @arguments) = @_;
    _fail('Native repository options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fail('Unknown native repository option') if grep { $_ !~ /\A(?:tool|trust|catalogue_prefix)\z/x } keys %options;
    $root = _root($root);
    $options{catalogue_prefix} = catalogue_prefix(
        defined($options{catalogue_prefix}) ? $options{catalogue_prefix} : '');
    return _inspect_repository($root, \%options, snapshot_tree($root));
}

sub _bootstrap {
    my $repository = shift;
    my @keys = grep { $repository->{packages}{$_}{name} eq 'pkg' } keys %{$repository->{packages}};
    _fail('Release repository requires exactly one pkg bootstrap package') if @keys != 1;
    my $key = $keys[0];
    my $package = $repository->{packages}{$key};
    _fail('Incompatible release pkg bootstrap identity') if $package->{origin} ne 'ports-mgmt/pkg'
      || $package->{abi} ne $ABI;
    my ($path) = grep { $repository->{archives}{$_}{package_identity} eq $key } keys %{$repository->{archives}};
    return { path => $path, version => $package->{version}, %{$repository->{archives}{$path}} };
}

sub _base_release {
    my $repository = shift;
    my %required = map { $_ => 1 } qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base);
    for my $package (values %{$repository->{packages}}) {
        next if $package->{name} eq 'pkg';
        my $name = $package->{name};
        _fail("Incompatible release base package: $name") if $name !~ /\AFreeBSD-/x
          || $package->{version} ne '15.1' || $package->{origin} ne "base/$name" || $package->{abi} ne $ABI
          || !defined($package->{annotations}{FreeBSD_version}) || $package->{annotations}{FreeBSD_version} ne '1501000';
        delete($required{$name});
    }
    _fail('Missing release base packages: ' . join(', ', sort keys %required)) if %required;
    return;
}

sub _bootstrap_repairs {
    my ($repository, $bootstrap) = @_;
    my @repairs;
    my $prefix = $repository->{catalogue_prefix};
    my $alias = length($prefix) ? "$prefix/Latest/pkg.pkg" : 'Latest/pkg.pkg';
    if (exists($repository->{tree}{entries}{$alias}) && !exists($repository->{tree}{unresolved_links}{$alias})) {
        my $resolved = _resolve_link($alias, $repository->{tree}{entries});
        _fail('Release bootstrap alias names a different archive')
          if !defined($resolved) || $resolved ne $bootstrap->{path};
    }
    for my $path (sort keys %{$repository->{tree}{unresolved_links}}) {
        _fail('Unsupported release bootstrap link repair') if $path ne "$ABI/Latest/pkg.pkg"
          || $repository->{tree}{unresolved_links}{$path} ne '../All/pkg-2.6.2_1.pkg'
          || $bootstrap->{version} ne '2.6.2_1' || $bootstrap->{path} !~ m{\A\Q$ABI\E/All/}x;
        my $target = '../' . substr($bootstrap->{path}, length($ABI) + 1);
        push @repairs, { path => $path, from => $repository->{tree}{unresolved_links}{$path},
            to => $target, archive => $bootstrap->{path}, sha256 => $bootstrap->{sha256} };
    }
    return \@repairs;
}

sub describe_release_repository {
    my ($repository, $kind) = @_;
    _fail('Unknown release repository role') unless defined($kind)
      && ($kind eq 'base' || $kind eq 'applications');
    _base_release($repository) if $kind eq 'base';
    my $bootstrap = _bootstrap($repository);
    return { bootstrap => $bootstrap,
        link_repairs => _bootstrap_repairs($repository, $bootstrap) };
}

sub inspect_release {
    my ($root, @arguments) = @_;
    _fail('Native release options must be pairs') if @arguments % 2;
    my %options = @arguments;
    _fail('Unknown native release option') if grep { $_ ne 'tool' && $_ ne 'trust' } keys %options;
    $root = _root($root);
    my $media = inspect_release_tree($root);
    return unless $media;
    my $trust = $options{trust};
    _fail('A pinned operator-trusted release is required') if ref($trust) ne 'HASH'
      || !defined($trust->{type}) || $trust->{type} ne 'operator-trusted-release'
      || grep { $_ ne 'type' && $_ ne 'digest' } keys %$trust;
    _fail('Trusted release checksum mismatch') if !_digest($trust->{digest}) || $trust->{digest} ne $media->{digest};
    my %repositories;
    for my $kind (sort keys %{$media->{repositories}}) {
        my $source = $media->{repositories}{$kind};
        my $repository = _inspect_repository("$root/$source->{path}",
            { tool => $options{tool}, catalogue_prefix => $source->{catalogue_prefix},
                trust => { type => 'operator-trusted-tree', digest => $source->{tree}{digest} } }, $source->{tree});
        $repositories{$kind} = { path => $source->{path}, repository => $repository,
            %{describe_release_repository($repository, $kind)} };
    }
    my $after = inspect_release_tree($root);
    _fail('Release changed during native inspection') if !$after || $after->{digest} ne $media->{digest};
    my $result = { format => 'xcat-freebsd-release-1', release => $media->{release}, arch => $media->{arch},
        media_arch => $media->{media_arch}, abi => $ABI, osversion => 1501000, distname => $media->{distname},
        media => $media, trust => { %$trust }, repositories => \%repositories,
        native_validated => 1, selection_validated => 0 };
    return { %$result, digest => sha256_hex(_json($result)) };
}

1;
