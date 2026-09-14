#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use Test::More;

# The install-time post script embeds whole postscripts with "#INCLUDE:<path>#" inside a
# here-document. The template copies the file verbatim, so a line in the postscript that
# equals the here-document delimiter ends that here-document early. The generated install
# script then holds the rest of the postscript as shell code.
#
# That happened: a "cat >> ... <<EOF" added to xcatdsklspost put a line "EOF" in the file,
# post.xcat embeds it with "cat >/opt/xcat/xcatdsklspost << 'EOF'", and every diskfull
# install ran a post script that bash refused to parse. No postscript ran, so remoteshell
# never installed the root key and the node answered "Permission denied (publickey)".

my $root = "$FindBin::Bin/../..";
my $scriptdir = "$root/xCAT-server/share/xcat/install/scripts";
plan skip_all => "$scriptdir not found" unless -d $scriptdir;

# Return every (post script, delimiter, embedded file) the install scripts declare.
sub embeddings {
    my @found;
    opendir(my $dh, $scriptdir) or die "cannot read $scriptdir: $!";
    my @posts = sort grep { /^post\./ and -f "$scriptdir/$_" } readdir($dh);
    closedir $dh;

    for my $post (@posts) {
        open(my $fh, '<', "$scriptdir/$post") or die "cannot read $post: $!";
        my @lines = <$fh>;
        close $fh;
        for my $i (0 .. $#lines - 1) {
            # cat >file << 'EOF'   /   (cat  << 'EOF'
            my ($delim) = $lines[$i] =~ /<<-?\s*'([A-Za-z_][A-Za-z0-9_]*)'\s*$/;
            next unless defined $delim;
            my ($include) = $lines[$i + 1] =~ /^#INCLUDE:(.+)#\s*$/;
            next unless defined $include;
            # The include path is a template expression; only its last element names the file.
            next unless $include =~ m{/postscripts/([^/#]+)$};
            my $file = "$root/xCAT/postscripts/$1";
            next unless -f $file;
            push @found, { post => $post, delim => $delim, file => $file, name => $1 };
        }
    }
    return @found;
}

my @embeddings = embeddings();
die 'no "#INCLUDE:" inside a here-document was found; the scan no longer matches the install scripts'
    unless @embeddings;

my $scratch = tempdir(CLEANUP => 1);

for my $e (@embeddings) {
    my $label = "$e->{post} embeds $e->{name} in a <<'$e->{delim}' here-document";

    open(my $fh, '<', $e->{file}) or die "cannot read $e->{file}: $!";
    my @body = <$fh>;
    close $fh;

    my @collisions = grep { $body[$_] =~ /^\Q$e->{delim}\E\s*$/ } 0 .. $#body;
    is(scalar @collisions, 0,
        "$label, and no line of $e->{name} is \"$e->{delim}\"")
        or diag("$e->{name} line(s) " . join(', ', map { $_ + 1 } @collisions)
              . " end the here-document early");

    # Assemble the embedding the way the template does and let bash parse it. bash reads the
    # here-document up to the first delimiter line, so an early end leaves the rest of the
    # postscript as commands. -n parses and runs nothing.
    my $script = "$scratch/$e->{post}.$e->{name}.sh";
    open(my $out, '>', $script) or die "cannot write $script: $!";
    print $out "cat >\"\$1\" <<'$e->{delim}'\n", @body, "$e->{delim}\n";
    close $out;

    my $errors = qx{bash -n \Q$script\E 2>&1};
    is($?, 0, "$label, and bash parses the result")
        or diag($errors);
}

done_testing();
