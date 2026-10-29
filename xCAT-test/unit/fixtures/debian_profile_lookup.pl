use strict;
use warnings;
use JSON::PP qw(encode_json);

BEGIN {
    *CORE::GLOBAL::exit = sub { die "genimage exit $_[0]\n" };
}

my ($script, $osver, $profile, $arch, $base, $ext) = @ARGV;
@ARGV = ('-o', $osver, '-p', $profile, '-a', $arch);
my $startup;
{
    local $0 = $script;
    local *STDOUT;
    open STDOUT, '>', \$startup or die "capture stdout: $!";
    do $script;
    die "genimage did not stop at argument validation: $@ $!\n"
      unless $@ eq "genimage exit 1\n";
}
print encode_json([main::get_profile_def_filename($base, $ext)]);
