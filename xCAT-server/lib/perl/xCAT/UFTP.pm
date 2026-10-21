package xCAT::UFTP;

=head1 NAME

xCAT::UFTP - validation and request helpers for UFTP root image distribution

=head1 DESCRIPTION

genimage records which initial ramdisk carries the UFTP receiver. nodeset
turns that record and the listener configuration into kernel arguments.
xcat-uftp-listener sends a root image that packimage published with its
SHA-256 checksum, and keeps its transfer jobs with the subs in this module.
All of them share the checks in this module.

=cut

use strict;
use warnings;

use Cwd ();
use Digest::SHA ();
use Errno qw(ENOENT);
use Fcntl qw(:mode O_RDONLY O_NOFOLLOW);
use File::Basename ();
use File::Path ();
use IO::Handle ();
use Socket ();

our $CONFIG_FILE   = '/etc/xcat/uftp/listener.conf';
our $HELPER        = 'xcat-rootimg-fetch.sh';
our $TARGET_PREFIX = '/xcat-uftp/v1';
our @ARTIFACTS     = qw(rootimg.cpio.gz rootimg.cpio.xz rootimg.tar.gz rootimg.tar.xz rootimg.sfs);
our @RECEIVERS     = qw(/usr/sbin/uftpd /usr/bin/uftpd);
our @BOOT_KEYS     = qw(xcat.uftp xcat.uftpfp);
our $KILL_GRACE    = 5;

my $MAX_PATH     = 1024;
my $MAX_SEGMENTS = 64;
my $MAX_REQUEST  = 8192;
my $MAX_FINISHED = 1024;
my $SEGMENT      = qr/[A-Za-z0-9_+-][A-Za-z0-9._+-]{0,254}/;
my $SHA256       = qr/[0-9a-f]{64}/;
my $FINGERPRINT  = qr/(?:[0-9A-F]{2}:){19}[0-9A-F]{2}/;

my %ELF_MACHINE = (
    x86     => [ 1, 3 ],
    x86_64  => [ 2, 62 ],
    ppc64   => [ 2, 21, 2 ],
    ppc64le => [ 2, 21, 1 ],
    ppc64el => [ 2, 21, 1 ],
    aarch64 => [ 2, 183 ],
    riscv64 => [ 2, 243 ],
    s390x   => [ 2, 22 ],
);

my %CONFIG = (
    listen_address      => { type => 'ipv4', required => 1 },
    listen_port         => { type => 'int', default => 1045, min => 1, max => 65535 },
    allowed_networks    => { type => 'networks', default => '' },
    multicast_interface => { type => 'ipv4' },
    image_roots         => { type => 'dirs', default => '/install/netboot' },
    udp_port            => { type => 'int', default => 1044, min => 1, max => 65535 },
    public_multicast    => { type => 'mcast', default => '230.4.4.1' },
    private_multicast   => { type => 'mcast_pattern', default => '230.5.5.x' },
    ttl                 => { type => 'int', default => 1, min => 1, max => 255 },
    rate_kbps           => { type => 'int', default => 100000, min => 1, max => 100000000 },
    # uftp accepts block sizes from 512 to 8800 bytes.
    block_size          => { type => 'int', default => 1300, min => 512, max => 8800 },
    batch_delay         => { type => 'int', default => 30, min => 0, max => 3600 },
    transfer_timeout    => { type => 'int', default => 1800, min => 1, max => 86400 },
    max_transfers       => { type => 'int', default => 4, min => 1, max => 64 },
    max_queued_jobs     => { type => 'int', default => 32, min => 1, max => 1024 },
    max_clients_per_job => { type => 'int', default => 1000, min => 1, max => 100000 },
    max_connections     => { type => 'int', default => 64, min => 1, max => 1024 },
    request_timeout     => { type => 'int', default => 10, min => 1, max => 300 },
    job_retention       => { type => 'int', default => 600, min => 0, max => 86400 },
    encryption          => { type => 'enum', default => 'aes256-gcm',
                             values => [qw(aes128-gcm aes256-gcm aes128-ccm aes256-ccm)] },
    key_file            => { type => 'abspath', default => '/etc/xcat/uftp/server.key' },
    fingerprint_file    => { type => 'abspath', default => '/etc/xcat/uftp/server.fingerprint' },
    uftp                => { type => 'abspath', default => '/usr/bin/uftp' },
    uftp_keymgt         => { type => 'abspath', default => '/usr/bin/uftp_keymgt' },
    log_dir             => { type => 'abspath', default => '/var/log/xcat-uftp' },
);

sub artifact_name_ok {
    my ($name) = @_;
    return defined($name) && grep { $_ eq $name } @ARTIFACTS;
}

sub sha256_fh {
    my ($fh) = @_;
    my $sha  = Digest::SHA->new(256);
    my $size = 0;
    while (1) {
        my $count = sysread($fh, my $buffer, 1048576);
        return (undef, undef, "read failed: $!") unless defined($count);
        last if $count == 0;
        $size += $count;
        $sha->add($buffer);
    }
    return ($sha->hexdigest, $size, undef);
}

sub sha256_file {
    my ($path) = @_;
    sysopen(my $fh, $path, O_RDONLY | O_NOFOLLOW)
      or return (undef, undef, "Cannot open $path: $!");
    binmode($fh);
    my ($digest, $size, $error) = sha256_fh($fh);
    unless (close($fh)) {
        $error ||= "close failed: $!";
    }
    return (undef, undef, "Cannot read $path: $error") if $error;
    return ($digest, $size, undef);
}

sub _read_text {
    my ($path, $follow) = @_;
    sysopen(my $fh, $path, $follow ? O_RDONLY : O_RDONLY | O_NOFOLLOW) or return (undef, "$!");
    my $text = '';
    while (1) {
        my $count = sysread($fh, my $buffer, 65536);
        return (undef, "$!") unless defined($count);
        last if $count == 0;
        $text .= $buffer;
        return (undef, 'file too large') if length($text) > 65536;
    }
    close($fh) or return (undef, "$!");
    return ($text, undef);
}

sub _write_atomic {
    my ($path, $content, $mode) = @_;
    my $temp = File::Basename::dirname($path) . '/.' . File::Basename::basename($path) . ".tmp$$";
    unlink($temp);
    sysopen(my $fh, $temp, Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_EXCL(), 0600)
      or return "Cannot create $temp: $!";
    my $fail = sub {
        my ($message) = @_;
        close($fh);
        unlink($temp);
        return $message;
    };
    my $written = syswrite($fh, $content);
    return $fail->("Cannot write $temp: $!") unless defined($written) && $written == length($content);
    return $fail->("Cannot flush $temp: $!") unless $fh->sync;
    unless (close($fh)) {
        my $message = "Cannot close $temp: $!";
        unlink($temp);
        return $message;
    }
    unless (chmod($mode, $temp) && rename($temp, $path)) {
        my $message = "Cannot publish $path: $!";
        unlink($temp);
        return $message;
    }
    return undef;
}

sub write_file_atomic {
    my ($path, $content, $mode) = @_;
    return _write_atomic($path, $content, $mode);
}

sub normalize_image_path {
    my ($path) = @_;
    return undef unless defined($path) && length($path) <= $MAX_PATH;
    return undef unless $path =~ m{^/};
    $path =~ s{/+}{/}g;
    $path =~ s{(?<=.)/$}{};
    my @segments = split m{/}, substr($path, 1);
    return undef unless @segments && @segments <= $MAX_SEGMENTS;
    for my $segment (@segments) {
        return undef unless $segment =~ /^$SEGMENT$/;
    }
    return '/' . join('/', @segments);
}

sub parse_transfer_target {
    my ($target) = @_;
    my $prefix = quotemeta("$TARGET_PREFIX/transfer/");
    return (undef, undef, 'unknown request target')
      unless defined($target) && $target =~ m{^$prefix($SHA256)(/.*)$};
    my ($digest, $path) = ($1, $2);
    my $normalized = normalize_image_path($path);
    return (undef, undef, 'malformed image path')
      unless defined($normalized) && $normalized eq $path;
    return (undef, undef, 'unsupported image artifact')
      unless artifact_name_ok(File::Basename::basename($path));
    return ($digest, $path, undef);
}

sub parse_job_target {
    my ($target) = @_;
    my $prefix = quotemeta("$TARGET_PREFIX/job/");
    return (undef, 'unknown request target')
      unless defined($target) && $target =~ m{^$prefix([0-9a-f]{16})$};
    return ($1, undef);
}

sub _trusted_entry {
    my ($path, $want_dir) = @_;
    my @st = lstat($path);
    return "$path does not exist" unless @st;
    return "$path is a symbolic link" if S_ISLNK($st[2]);
    return "$path is not a directory" if $want_dir && !S_ISDIR($st[2]);
    return "$path is not a regular file" if !$want_dir && !S_ISREG($st[2]);
    return "$path is not owned by root" unless $st[4] == 0 || $st[4] == $>;
    return "$path is writable by other users" if $st[2] & 022;
    return undef;
}

sub _contained {
    my ($path, $root) = @_;
    return 1 if $root eq '/';
    return $path eq $root || index($path, "$root/") == 0;
}

# Returns the lines of a checksum file in sha256sum format as pairs of digest and file name.
sub checksum_lines {
    my ($text) = @_;
    return map { /^($SHA256) [ *](\S+)$/ ? [ $1, $2 ] : () } split /\n/, $text // '';
}

sub resolve_artifact {
    my ($roots, $image_path, $digest) = @_;
    my $name = File::Basename::basename($image_path);
    my $dir  = File::Basename::dirname($image_path);
    my $real = Cwd::realpath($dir);
    return (undef, 'image directory does not exist') unless defined($real) && -d $real;
    return (undef, 'image directory is outside the configured image roots')
      unless grep { _contained($real, $_) } @$roots;

    my $archive = "$real/$name";
    for my $check ([$real, 1], [$archive, 0], ["$archive.sha256", 0]) {
        my $error = _trusted_entry(@$check);
        return (undef, "image is not published: $error") if $error;
    }

    # packimage publishes the archive with its checksum file, which lists the previous archive too while it replaces it.
    my ($sums, $error) = _read_text("$archive.sha256");
    return (undef, "cannot read the checksum of the image: $error") unless defined($sums);
    return (undef, 'requested image generation is not the published one')
      unless grep { $_->[0] eq $digest && $_->[1] eq $name } checksum_lines($sums);

    my @link = lstat($archive);
    sysopen(my $fh, $archive, O_RDONLY | O_NOFOLLOW)
      or return (undef, "cannot open published image: $!");
    binmode($fh);
    my @st = stat($fh);
    unless (@st && @link && S_ISREG($st[2]) && $st[0] == $link[0] && $st[1] == $link[1]) {
        close($fh);
        return (undef, 'published image changed during validation');
    }
    unless ($st[7] > 0) {
        close($fh);
        return (undef, 'published image is empty');
    }
    return ({
        fh     => $fh,
        dev    => $st[0],
        ino    => $st[1],
        size   => $st[7],
        sha256 => $digest,
        name   => $name,
        path   => $archive,
    }, undef);
}

my %REASONS = (
    200 => 'OK',
    400 => 'Bad Request',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    408 => 'Request Timeout',
    413 => 'Content Too Large',
    500 => 'Internal Server Error',
    503 => 'Service Unavailable',
);

sub parse_http_request {
    my ($buffer) = @_;
    my ($end) = grep { $_ >= 0 } sort { $a <=> $b } (index($buffer, "\r\n\r\n"), index($buffer, "\n\n"));
    return { incomplete => 1 } unless defined($end);
    my @lines = split /\r?\n/, substr($buffer, 0, $end);
    my $line = shift(@lines) // '';
    return { status => 400, reason => 'malformed request line' }
      unless $line =~ m{^([A-Z]{1,16}) (\S{1,2048}) HTTP/1\.[01]$};
    my ($method, $target) = ($1, $2);
    return { status => 400, reason => 'too many header lines' } if @lines > 64;
    for my $header (@lines) {
        return { status => 400, reason => 'malformed header line' }
          unless $header =~ /^[!#\$%&'*+.^_`|~0-9A-Za-z-]{1,64}:[\t\x20-\x7e]*$/;
    }
    return { status => 405, reason => 'only GET is supported' } unless $method eq 'GET';
    return { status => 400, reason => 'malformed request target' }
      unless $target =~ m{^/[A-Za-z0-9._+/-]*$};
    return { method => $method, target => $target };
}

sub http_response {
    my ($status, $body) = @_;
    $body = '' unless defined($body);
    my $reason = $REASONS{$status} || 'Error';
    return "HTTP/1.0 $status $reason\r\nContent-Type: text/plain\r\n"
      . 'Content-Length: ' . length($body) . "\r\nConnection: close\r\n\r\n$body";
}

sub format_record {
    my (@pairs) = @_;
    my $text = '';
    while (@pairs) {
        my ($key, $value) = splice(@pairs, 0, 2);
        $text .= "$key=$value\n";
    }
    return $text;
}

sub ipv4_ok {
    my ($address) = @_;
    return 0 unless defined($address) && $address =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
    for my $octet ($1, $2, $3, $4) {
        return 0 if $octet > 255 || $octet =~ /^0\d/;
    }
    return 1;
}

sub ipv4_number {
    my ($address) = @_;
    return unpack('N', Socket::inet_aton($address));
}

sub address_allowed {
    my ($networks, $address) = @_;
    return 1 unless $networks && @$networks;
    my $number = ipv4_number($address);
    for my $network (@$networks) {
        return 1 if ($number & $network->[1]) == $network->[0];
    }
    return 0;
}

sub _config_value {
    my ($key, $spec, $value) = @_;
    my $type = $spec->{type};
    if ($type eq 'int') {
        return (undef, "$key must be an integer") unless $value =~ /^(?:0|[1-9][0-9]{0,8})$/;
        return (undef, "$key must be between $spec->{min} and $spec->{max}")
          if $value < $spec->{min} || $value > $spec->{max};
        return ($value + 0, undef);
    }
    if ($type eq 'ipv4') {
        return (undef, "$key must be an IPv4 address") unless ipv4_ok($value);
        return ($value, undef);
    }
    if ($type eq 'mcast') {
        return (undef, "$key must be an IPv4 multicast address")
          unless ipv4_ok($value) && $value =~ /^(\d+)\./ && $1 >= 224 && $1 <= 239;
        return ($value, undef);
    }
    if ($type eq 'mcast_pattern') {
        (my $probe = $value) =~ s/\bx\b/1/g;
        return (undef, "$key must be an IPv4 multicast address pattern")
          unless $value =~ /^\d/ && ipv4_ok($probe) && $probe =~ /^(\d+)\./ && $1 >= 224 && $1 <= 239;
        return ($value, undef);
    }
    if ($type eq 'enum') {
        return (undef, "$key must be one of " . join(', ', @{ $spec->{values} }))
          unless grep { $_ eq $value } @{ $spec->{values} };
        return ($value, undef);
    }
    if ($type eq 'abspath') {
        return (undef, "$key must be an absolute path") unless $value =~ m{^/[^\0\s]*$};
        return ($value, undef);
    }
    if ($type eq 'dirs') {
        my @dirs;
        for my $dir (split /\s*,\s*/, $value) {
            return (undef, "$key entries must be absolute paths") unless $dir =~ m{^/};
            my $real = Cwd::realpath($dir);
            return (undef, "$key entry $dir is not a directory") unless defined($real) && -d $real;
            push @dirs, $real;
        }
        return (undef, "$key must list at least one directory") unless @dirs;
        return (\@dirs, undef);
    }
    if ($type eq 'networks') {
        my @networks;
        for my $entry (split /\s*,\s*/, $value) {
            return (undef, "$key entry $entry must be address/prefix")
              unless $entry =~ m{^([^/]+)/(\d{1,2})$} && ipv4_ok($1) && $2 <= 32;
            my $mask = $2 ? (0xffffffff << (32 - $2)) & 0xffffffff : 0;
            push @networks, [ ipv4_number($1) & $mask, $mask ];
        }
        return (\@networks, undef);
    }
    return (undef, "$key has an unknown type");
}

sub load_listener_config {
    my ($path) = @_;
    $path ||= $CONFIG_FILE;
    my ($text, $error) = _read_text($path, 1);
    return (undef, "Cannot read $path: $error") unless defined($text);
    my %raw;
    my $number = 0;
    for my $line (split /\n/, $text) {
        $number++;
        next if $line =~ /^\s*(?:#|$)/;
        return (undef, "$path line $number: expected key = value")
          unless $line =~ /^\s*([a-z_]+)\s*=\s*(.*?)\s*$/;
        my ($key, $value) = ($1, $2);
        return (undef, "$path line $number: unknown key '$key'") unless $CONFIG{$key};
        return (undef, "$path line $number: duplicate key '$key'") if exists($raw{$key});
        $raw{$key} = $value;
    }
    my %config;
    for my $key (sort keys %CONFIG) {
        my $spec = $CONFIG{$key};
        my $value = ($raw{$key} // '') ne '' ? $raw{$key} : $spec->{default};
        if (!defined($value) || $value eq '' && $spec->{type} ne 'networks') {
            return (undef, "$path: $key is required") if $spec->{required};
            next;
        }
        my ($parsed, $value_error) = _config_value($key, $spec, $value);
        return (undef, "$path: $value_error") if $value_error;
        $config{$key} = $parsed;
    }
    $config{multicast_interface} ||= $config{listen_address};
    $config{server_id} = sprintf('0x%08X', ipv4_number($config{multicast_interface}));
    return (\%config, undef);
}

sub parse_fingerprint {
    my ($text) = @_;
    return undef unless defined($text);
    return $1 if $text =~ /(?:^|fingerprint:\s*)($FINGERPRINT)\s*$/m;
    return undef;
}

sub read_fingerprint {
    my ($path) = @_;
    my ($text, $error) = _read_text($path, 1);
    return (undef, "Cannot read UFTP server fingerprint $path: $error") unless defined($text);
    my $fingerprint = parse_fingerprint($text);
    return (undef, "$path does not hold a UFTP key fingerprint") unless $fingerprint;
    return ($fingerprint, undef);
}

sub uftp_command {
    my ($config, $name, $hostlist) = @_;
    return (
        $config->{uftp},
        '-I', $config->{multicast_interface},
        '-U', $config->{server_id},
        '-p', $config->{udp_port},
        '-M', $config->{public_multicast},
        '-P', $config->{private_multicast},
        '-t', $config->{ttl},
        '-R', $config->{rate_kbps},
        '-b', $config->{block_size},
        # Abort a receiver that misses nearly every block of a section, so it cannot hold the group open.
        # uftp leaves up to 7 NAKs of each section uncounted, so a limit of 99 never aborts one.
        '-N', 98,
        '-Y', $config->{encryption},
        '-h', 'sha256',
        '-k', $config->{key_file},
        '-H', "\@$hostlist",
        '-x', 2,
        '-l',
        '-D', $name,
        '/dev/fd/3',
    );
}

# Returns the fingerprint of the server key, or undef and why the listener cannot send.
# $key_fingerprint returns the fingerprint that uftp_keymgt reports for the key, or undef and an error.
sub check_listener_runtime {
    my ($config, $key_fingerprint) = @_;
    return (undef, "UFTP sender $config->{uftp} is not executable; install the uftp package")
      unless -f $config->{uftp} && -x _;
    if (my $version_error = uftp_version_error($config->{uftp})) {
        return (undef, $version_error);
    }
    my @st = stat($config->{key_file});
    return (undef, "UFTP server key $config->{key_file} is missing; run xcat-uftp-listener --init-key")
      unless @st;
    return (undef, "UFTP server key $config->{key_file} must not be accessible by other users")
      if $st[2] & 077;
    my ($fingerprint, $error) = $key_fingerprint->();
    return (undef, $error) if $error;
    my ($published, $read_error) = read_fingerprint($config->{fingerprint_file});
    return (undef, "$read_error; run xcat-uftp-listener --init-key") if $read_error;
    return (undef, "$config->{fingerprint_file} does not match $config->{key_file}; run xcat-uftp-listener --init-key")
      unless $published eq $fingerprint;
    unless (-d $config->{log_dir}) {
        eval { File::Path::make_path($config->{log_dir}, { mode => 0750 }) };
        return (undef, "Cannot create $config->{log_dir}") unless -d $config->{log_dir};
    }

    # The file test operators ignore read-only mounts, such as those of the service sandbox.
    my $probe = "$config->{log_dir}/.write-check.$$";
    unlink($probe);
    sysopen(my $fh, $probe, Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_EXCL(), 0600)
      or return (undef, "Cannot write to $config->{log_dir}: $!");
    close($fh);
    unlink($probe);
    return ($fingerprint, undef);
}

# The listener keeps its transfer jobs in this state. spawn starts a sender for a job and returns its PID,
# or undef and an error. signal sends a signal to a sender.
sub listener_state {
    my ($config, %args) = @_;
    return {
        config  => $config,
        workdir => $args{workdir},
        log     => $args{log} || sub { },
        spawn   => $args{spawn},
        signal  => $args{signal} || sub { kill($_[0], $_[1]) },
        jobs    => {},
        pending => {},
        senders => {},
    };
}

sub _job_id {
    my ($state) = @_;
    my $bytes = '';
    if (open(my $random, '<:raw', '/dev/urandom')) {
        read($random, $bytes, 8);
        close($random);
    }
    $bytes = pack('N2', int(rand(2**32)), int(rand(2**32))) unless length($bytes) == 8;
    my $id = unpack('H16', $bytes);
    return exists($state->{jobs}{$id}) ? _job_id($state) : $id;
}

sub _jobs_in {
    my ($state, @states) = @_;
    my %want = map { $_ => 1 } @states;
    return grep { $want{ $_->{state} } } values %{ $state->{jobs} };
}

sub _request_transfer {
    my ($state, $peer, $target, $now) = @_;
    my ($config, $log) = @$state{qw(config log)};
    my ($digest, $path, $error) = parse_transfer_target($target);
    if ($error) {
        $log->('warning', "$peer: rejected request: $error");
        return (400, "error=$error\n");
    }
    my ($image, $resolve_error) = resolve_artifact($config->{image_roots}, $path, $digest);
    if ($resolve_error) {
        $log->('warning', "$peer: rejected $path: $resolve_error");
        return (403, "error=image is not published\n");
    }
    my $key = join(':', $image->{dev}, $image->{ino}, $digest, $config->{udp_port});
    my $job = $state->{pending}{$key};
    my $repeated;
    if ($job) {
        close($image->{fh});
        $repeated = $job->{clients}{$peer};
        unless ($repeated) {
            if (keys(%{ $job->{clients} }) >= $config->{max_clients_per_job}) {
                $log->('warning', "$peer: job $job->{id} is full");
                return (503, "error=transfer is full\n");
            }
            $job->{clients}{$peer} = 1;
        }
    } else {
        if (_jobs_in($state, 'pending', 'running') >= $config->{max_queued_jobs}) {
            close($image->{fh});
            $log->('warning', "$peer: too many queued transfers");
            return (503, "error=too many queued transfers\n");
        }
        $job = {
            %$image,
            id       => _job_id($state),
            key      => $key,
            clients  => { $peer => 1 },
            created  => $now,
            start_at => $now + $config->{batch_delay},
            state    => 'pending',
        };
        $state->{pending}{$key} = $job;
        $state->{jobs}{ $job->{id} } = $job;
        $log->('info', "job $job->{id}: queued $path ($digest) for $config->{batch_delay}s");
    }
    $log->('info', $repeated ? "job $job->{id}: $peer asked again" : "job $job->{id}: added $peer");
    return (200, format_record(
        status    => 'queued',
        job       => $job->{id},
        file      => $job->{name},
        size      => $job->{size},
        port      => $config->{udp_port},
        mcast     => $config->{public_multicast},
        server_id => $config->{server_id},
        server_ip => $config->{multicast_interface},
        client_ip => $peer,
        start_in  => $job->{start_at} > $now ? $job->{start_at} - $now : 0,
        timeout   => $config->{transfer_timeout},
    ));
}

sub _job_status {
    my ($state, $peer, $target, $now) = @_;
    my ($id, $error) = parse_job_target($target);
    return (400, "error=$error\n") if $error;
    my $job = $state->{jobs}{$id};
    return (404, "error=unknown job\n") unless $job && $job->{clients}{$peer};
    my @fields = (state => $job->{state});
    push @fields, (start_in => $job->{start_at} > $now ? $job->{start_at} - $now : 0)
      if $job->{state} eq 'pending';
    push @fields, (timeout => $state->{config}{transfer_timeout});
    push @fields, (reason => $job->{reason}) if $job->{reason};
    return (200, format_record(@fields));
}

# Returns the status and body of the reply to the request that $peer sent in $buffer, or an empty list
# while the request is incomplete.
sub listener_reply {
    my ($state, $peer, $buffer, $now) = @_;
    return (413, "error=request too large\n") if length($buffer) > $MAX_REQUEST;
    my $request = parse_http_request($buffer);
    return () if $request->{incomplete};
    return ($request->{status}, "error=$request->{reason}\n") if $request->{status};
    my $target = $request->{target};
    return _request_transfer($state, $peer, $target, $now) if index($target, "$TARGET_PREFIX/transfer/") == 0;
    return _job_status($state, $peer, $target, $now) if index($target, "$TARGET_PREFIX/job/") == 0;
    return (404, "error=unknown request target\n");
}

# Returns the status and body that refuse a new connection from $peer while $open connections are open,
# or an empty list to accept it.
sub connection_refusal {
    my ($state, $open, $peer) = @_;
    my $config = $state->{config};
    return (503, "error=too many connections\n") if $open >= $config->{max_connections};
    unless (address_allowed($config->{allowed_networks}, $peer)) {
        $state->{log}->('warning', "$peer: address is not in allowed_networks");
        return (403, "error=client address is not allowed\n");
    }
    return ();
}

sub _finish_job {
    my ($state, $job, $result, $reason, $now) = @_;
    close($job->{fh}) if $job->{fh};
    delete $job->{fh};
    my $pending = $state->{pending};
    delete $pending->{ $job->{key} } if $pending->{ $job->{key} } && $pending->{ $job->{key} } == $job;
    unlink($job->{hostlist}) if $job->{hostlist};
    $job->{state}    = $result;
    $job->{reason}   = $reason if $reason;
    $job->{finished} = $now;
    $state->{log}->($result eq 'done' ? 'info' : 'error', "job $job->{id}: $result" . ($reason ? " ($reason)" : ''));
}

sub _start_job {
    my ($state, $job, $now) = @_;
    my $config = $state->{config};
    delete $state->{pending}{ $job->{key} };
    my $hostlist = "$state->{workdir}/$job->{id}.hosts";
    my $hosts = join('', map { "$_\n" } sort keys %{ $job->{clients} });
    if (my $error = _write_atomic($hostlist, $hosts, 0600)) {
        return _finish_job($state, $job, 'failed', $error, $now);
    }
    $job->{hostlist} = $hostlist;
    my $log = "$config->{log_dir}/job-$job->{id}.log";
    my ($pid, $error) = $state->{spawn}->($job, $log, uftp_command($config, $job->{name}, $hostlist));
    return _finish_job($state, $job, 'failed', $error, $now) unless $pid;
    close($job->{fh});
    delete $job->{fh};
    $state->{senders}{$pid} = $job;
    $job->{pid}      = $pid;
    $job->{state}    = 'running';
    $job->{started}  = $now;
    $job->{deadline} = $now + $config->{transfer_timeout};
    $state->{log}->('info', "job $job->{id}: sending $job->{name} to "
          . scalar(keys %{ $job->{clients} }) . " client(s), pid $pid, log $log");
}

# Starts each pending job whose batch delay has passed while fewer than max_transfers senders run,
# stops senders that exceed transfer_timeout, and forgets finished jobs after job_retention.
sub run_jobs {
    my ($state, $now) = @_;
    my $config  = $state->{config};
    my $running = _jobs_in($state, 'running');
    for my $job (sort { $a->{start_at} <=> $b->{start_at} || $a->{created} <=> $b->{created} }
        _jobs_in($state, 'pending')) {
        if ($now > $job->{start_at} + $config->{transfer_timeout}) {
            _finish_job($state, $job, 'failed', 'no transfer slot became free', $now);
            next;
        }
        next if $job->{start_at} > $now || $running >= $config->{max_transfers};
        _start_job($state, $job, $now);
        $running++ if $job->{state} eq 'running';
    }
    for my $job (_jobs_in($state, 'running')) {
        if (!$job->{timed_out} && $now >= $job->{deadline}) {
            $job->{timed_out} = $now;
            $state->{signal}->('TERM', $job->{pid});
        } elsif ($job->{timed_out} && $now >= $job->{timed_out} + $KILL_GRACE) {
            $state->{signal}->('KILL', $job->{pid});
        }
    }
    my @finished = sort { $a->{finished} <=> $b->{finished} } _jobs_in($state, 'done', 'failed');
    while (@finished && ($finished[0]{finished} + $config->{job_retention} <= $now
            || @finished > $MAX_FINISHED)) {
        delete $state->{jobs}{ shift(@finished)->{id} };
    }
}

# Finishes the job of the sender $pid, which exited with the wait status $status. $reason replaces the
# reason that the status gives.
sub sender_exited {
    my ($state, $pid, $status, $now, $reason) = @_;
    my $job = delete $state->{senders}{$pid} or return;
    unless ($reason) {
        if ($job->{timed_out}) {
            $reason = "transfer exceeded $state->{config}{transfer_timeout}s";
        } elsif ($status & 127) {
            $reason = 'uftp killed by signal ' . ($status & 127);
        } elsif ($status >> 8) {
            $reason = 'uftp exited with status ' . ($status >> 8);
        }
    }
    _finish_job($state, $job, $reason ? 'failed' : 'done', $reason, $now);
}

sub sender_pids {
    my ($state) = @_;
    return keys %{ $state->{senders} };
}

# Fails the jobs that still wait for a sender when the listener stops.
sub stop_jobs {
    my ($state, $now) = @_;
    _finish_job($state, $_, 'failed', 'listener stopped', $now) for _jobs_in($state, 'pending');
}

sub image_receiver {
    my ($rootimg_dir) = @_;
    for my $receiver (@RECEIVERS) {
        return $receiver if -f "$rootimg_dir$receiver" && -x _;
    }
    return undef;
}

sub elf_arch_error {
    my ($path, $arch) = @_;
    my $want = $ELF_MACHINE{$arch};
    return "UFTP receivers are not supported for architecture $arch" unless $want;
    open(my $fh, '<:raw', $path) or return "Cannot read $path: $!";
    my $count = read($fh, my $header, 20);
    close($fh);
    return "$path is not an ELF executable"
      unless defined($count) && $count == 20 && substr($header, 0, 4) eq "\x7fELF";
    my $class   = ord(substr($header, 4, 1));
    my $data    = ord(substr($header, 5, 1));
    my $machine = unpack($data == 2 ? 'n' : 'v', substr($header, 18, 2));
    my ($want_class, $want_machine, $want_data) = @$want;
    unless ($class == $want_class && $machine == $want_machine
        && (!defined($want_data) || $data == $want_data)) {
        return "$path was built for another architecture than $arch (ELF class $class, machine $machine)";
    }
    return undef;
}

# The uftp package of xcat-dep marks its build, which carries fixes that stock UFTP 5 lacks.
sub uftp_version_error {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return "Cannot read $path: $!";
    my $content = do { local $/; <$fh> } // '';
    close($fh);
    my ($version, $mark) = $content =~ /UFTP version (\d+\.\d+(?:\.\d+)?)( \(xCAT build \d+\))?/;
    return "Cannot find the UFTP version in $path" unless defined($version);
    return "$path is UFTP $version; UFTP 5.x is required" unless $version =~ /^5\./;
    return "$path is UFTP $version without the xCAT fixes; use the uftp package of xcat-dep" unless $mark;
    return undef;
}

sub usable_receiver {
    my ($rootimg_dir, $arch) = @_;
    my $receiver = image_receiver($rootimg_dir);
    return (undef, undef) unless $receiver;
    my $error = elf_arch_error("$rootimg_dir$receiver", $arch)
      || uftp_version_error("$rootimg_dir$receiver");
    return (undef, "$error; the initial ramdisk will not receive the root image over UFTP") if $error;
    return ($receiver, undef);
}

sub initrd_missing_files {
    my ($listing) = @_;
    my @paths = map { (split /\s+/, $_)[-1] // '' } @$listing;
    my %required = (
        uftpd     => qr{^(?:usr/)?s?bin/uftpd$},
        sha256sum => qr{^(?:usr/)?bin/sha256sum$},
        $HELPER   => qr{^(?:usr/)?lib/\Q$HELPER\E$},
    );
    return grep { my $re = $required{$_}; !grep { $_ =~ $re } @paths } sort keys %required;
}

# The marker holds the SHA-256 of the ramdisk, so a replaced ramdisk does not match it.
sub write_initrd_marker {
    my ($initrd) = @_;
    my ($digest, undef, $error) = sha256_file($initrd);
    return $error if $error;
    return _write_atomic("$initrd.uftp", "sha256=$digest\n", 0644);
}

sub remove_initrd_marker {
    my ($initrd) = @_;
    return undef if unlink("$initrd.uftp") || $! == ENOENT;
    return "Cannot remove $initrd.uftp: $!";
}

# $initrd can be the copy that nodes boot, and $marker the one genimage wrote next to the ramdisk it built.
sub verify_initrd_marker {
    my ($initrd, $marker) = @_;
    $marker //= "$initrd.uftp";
    my $hint = 'install the uftp package in the image and run genimage again';
    return "$initrd was not built with the UFTP receiver; $hint" unless -e $marker;
    my ($text, $error) = _read_text($marker);
    return "Cannot read $marker: $error" unless defined($text);
    my ($recorded) = $text =~ /^sha256=($SHA256)\n?$/ or return "$marker is not a UFTP receiver marker";
    my ($digest, undef, $hash_error) = sha256_file($initrd);
    return $hash_error if $hash_error;
    return "$initrd is not the initial ramdisk that genimage built with the UFTP receiver; $hint"
      unless $digest eq $recorded;
    return undef;
}

sub managed_boot_keys {
    my ($kcmdline) = @_;
    return () unless defined($kcmdline);
    my %keys = map { $_ => 1 } @BOOT_KEYS;
    my %found;
    for my $token (split /\s+/, $kcmdline) {
        my ($key) = split /=/, $token, 2;
        $found{$key} = 1 if defined($key) && $keys{$key};
    }
    return sort keys %found;
}

# nodeset checks every node, so each version of an initial ramdisk and its marker is hashed once.
my %initrd_marker_errors;

# Returns the kernel arguments for receiving the root image over UFTP, or undef and why a node cannot.
sub boot_arguments {
    my (%args) = @_;
    my ($rootimgdir, $artifact) = @args{qw(rootimgdir artifact)};
    return (undef, 'UFTP sends only the compressed root image of a stateless image') if $args{statelite};
    return (undef, "UFTP needs the root image checksum, so set the rootimgchecksum attribute of the image to yes")
      unless $args{checksum};
    return (undef, "$rootimgdir has no root image that UFTP can send; run packimage") unless artifact_name_ok($artifact);
    return (undef, "$rootimgdir/$artifact has a BitTorrent .metainfo file; UFTP cannot be combined with packimage --tracker")
      if -e "$rootimgdir/$artifact.metainfo";

    my $httpmethod = $args{httpmethod} || 'http';
    return (undef, "UFTP image distribution requires site.httpmethod=http, not $httpmethod")
      unless $httpmethod eq 'http';

    for my $source ([ 'linuximage.addkcmdline', $args{addkcmdline} ], [ 'bootparams.addkcmdline', $args{node_addkcmdline} ]) {
        my @managed = managed_boot_keys($source->[1]);
        return (undef, "$source->[0] must not set " . join(', ', @managed) . '; nodeset generates them for UFTP images')
          if @managed;
    }

    my $marker = $args{marker} // "$args{initrd}.uftp";
    my $key = join(':', map { my @stat = stat($_); ($_, @stat ? @stat[ 0, 1, 7, 9 ] : '-') } $args{initrd}, $marker);
    my $error = $initrd_marker_errors{$key} //= verify_initrd_marker($args{initrd}, $marker) // '';
    return (undef, $error) if $error;

    my ($config, $config_error) = load_listener_config($args{config});
    return (undef, "UFTP listener configuration: $config_error") if $config_error;
    return (undef, "$rootimgdir has a character that a UFTP request cannot carry; use only letters, digits and ._+- in its path")
      unless normalize_image_path("$rootimgdir/$artifact");
    my $real = Cwd::realpath($rootimgdir);
    return (undef, "$rootimgdir is outside the image_roots of the UFTP listener in " . ($args{config} || $CONFIG_FILE))
      unless defined($real) && grep { _contained($real, $_) } @{ $config->{image_roots} };
    my ($fingerprint, $fingerprint_error) = read_fingerprint($config->{fingerprint_file});
    return (undef, $fingerprint_error) if $fingerprint_error;
    return ("xcat.uftp=$config->{listen_port} xcat.uftpfp=$fingerprint ", undef);
}

1;
