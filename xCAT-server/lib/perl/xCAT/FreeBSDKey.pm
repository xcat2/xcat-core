package xCAT::FreeBSDKey;

use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK);
use File::Basename qw(dirname);
use File::Temp qw(tempfile);
use IO::Handle;

sub _fail { die "FreeBSD data key: $_[0]\n"; }

sub identity {
    my ($node, $pool) = @_;
    _fail('Invalid node') unless defined($node) && !ref($node) &&
        $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,246}\z/x;
    _fail('Invalid data pool') unless defined($pool) && !ref($pool) &&
        $pool =~ /\A[a-z][a-z0-9_-]{0,62}\z/x &&
        $pool !~ /\A(?:zroot|log|mirror|raidz[0-9]*|draid[0-9]*|spare|cache|special|dedup)\z/x;
    _fail('The node/pool identity exceeds the passwd key limit') if length("$node/$pool") > 128;
    return { key => 'freebsd-zfs', username => "$node/$pool" };
}

sub _parents {
    my $path = shift;
    _fail('An absolute key file path is required') unless defined($path) && !ref($path) &&
        $path =~ m{\A/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\z}x;
    my @parts = split(m{/}x, substr($path, 1));
    _fail('Invalid key path') if grep { $_ eq '.' || $_ eq '..' } @parts;
    pop @parts;
    _fail('Use a private key directory') unless @parts;
    my $parent = '';
    for my $part (@parts) {
        $parent .= "/$part";
        my @stat = lstat($parent);
        _fail('Unsafe key parent directory') unless @stat && -d _ && !-l _ &&
            $stat[4] == 0 && !($stat[2] & oct('0022'));
    }
    _fail('The key directory must be owned by root with mode 0700') unless
        ((lstat($parent))[2] & oct('07777')) == oct('0700');
}

sub read_file {
    my $path = shift;
    _parents($path);
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or _fail('Cannot open key file');
    my @stat = stat($file);
    _fail('A root-owned mode 0600 regular 32-byte key file is required') unless
        -f $file && $stat[3] == 1 && $stat[4] == 0 && $stat[5] == 0 &&
        ($stat[2] & oct('07777')) == oct('0600') && $stat[7] == 32;
    binmode($file);
    my $bytes = do { local $/; <$file> };
    close($file) or _fail('Cannot close key file');
    _fail('The key file changed while reading') unless defined($bytes) && length($bytes) == 32;
    return $bytes;
}

sub _record_key {
    my $row = shift;
    _fail('No saved key exists for this node and pool') unless ref($row) eq 'HASH';
    _fail('Invalid or disabled saved key') unless defined($row->{password}) &&
        $row->{password} =~ /\A[0-9a-f]{64}\z/x &&
        !length($row->{cryptmethod} || '') && !length($row->{authdomain} || '') &&
        ($row->{disable} || '') !~ /\A(?:yes|1)\z/ix;
    return pack('H*', $row->{password});
}

sub manage {
    my ($table, $operation, $node, $pool, $path) = @_;
    _fail('Root is required') unless $> == 0;
    _fail('Expected save or restore') unless defined($operation) && $operation =~ /\A(?:save|restore)\z/x;
    my $identity = identity($node, $pool);
    my @columns = qw(password cryptmethod authdomain disable);
    my $row = $table->getAttribs($identity, \@columns);
    if ($operation eq 'save') {
        my $bytes = read_file($path);
        if ($row) {
            _fail('A different key is already saved; refusing to replace it') unless _record_key($row) eq $bytes;
            return;
        }
        # An insert with no selector cannot overwrite a concurrent save. The
        # passwd primary key enforces one entry per node and pool.
        my @result = $table->setAttribs(undef, { %$identity, password => unpack('H*', $bytes),
            cryptmethod => '', authdomain => '', disable => 'no' });
        _fail('Cannot save key in passwd') unless @result == 1 && defined($result[0]) && $result[0] == 0;
        _fail('Saved key readback failed') unless
            _record_key($table->getAttribs($identity, \@columns)) eq $bytes;
        $table->close();
        return;
    }
    my $bytes = _record_key($row);
    _parents($path);
    if (-e $path || -l $path) {
        _fail('The destination contains a different key') unless read_file($path) eq $bytes;
        return;
    }
    my ($file, $temporary) = tempfile('.xcat-zfs-key.XXXXXXXX', DIR => dirname($path), UNLINK => 0);
    my $ok = eval {
        chown(0, 0, $temporary) or _fail('Cannot set recovered key ownership');
        chmod(0600, $temporary) or _fail('Cannot protect recovered key');
        binmode($file);
        print {$file} $bytes or _fail('Cannot write recovered key');
        $file->flush && $file->sync or _fail('Cannot sync recovered key');
        close($file) or _fail('Cannot close recovered key');
        link($temporary, $path) or _fail('Cannot publish recovered key');
        unlink($temporary) or _fail('Cannot remove temporary key');
        _fail('Recovered key readback failed') unless read_file($path) eq $bytes;
        sysopen(my $directory, dirname($path), O_RDONLY | O_NOFOLLOW) or _fail('Cannot open key directory');
        $directory->sync or _fail('Cannot sync key directory');
        close($directory) or _fail('Cannot close key directory');
        1;
    };
    my $error = $@;
    close($file) if defined(fileno($file));
    unlink($temporary) if -e $temporary;
    die $error unless $ok;
    return;
}

sub lookup {
    my ($table, $node, $pool) = @_;
    _fail('Root is required') unless $> == 0;
    return _record_key($table->getAttribs(identity($node, $pool),
        [qw(password cryptmethod authdomain disable)]));
}

1;
