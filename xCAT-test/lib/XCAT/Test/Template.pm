package XCAT::Test::Template;

use strict;
use warnings;
use Exporter qw(import);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use File::Slurper qw(write_text);
use JSON::PP qw(encode_json);
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

our @EXPORT_OK = qw(template_database set_row render_template);

sub template_database {
    my $dir = tempdir(CLEANUP => 1);
    make_path("$dir/db", "$dir/install");
    symlink(repo_path('xCAT/postscripts'), "$dir/install/postscripts") or die $!;
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG} = "SQLite:$dir/db";
    require xCAT::Table;
    require xCAT::Template;
    require xCAT::Postage;
    my %site = (
        installdir => "$dir/install", tftpdir => "$dir/tftpboot",
        master => '192.0.2.1', timezone => 'UTC', domain => 'example.invalid',
        xcatiport => 3002, xcatdport => 3001, httpport => 8080,
        xcatdebugmode => 0, nodestatus => 1, secureroot => 1,
        managedaddressmode => 'dhcp',
    );
    set_row('site', {key => $_}, {value => $site{$_}}) for keys %site;
    %::XCATSITEVALS = %site;
    set_row('nodelist', {node => 'node'}, {groups => 'all'});
    set_row('noderes', {node => 'node'}, {
        xcatmaster => '192.0.2.1', nfsserver => '192.0.2.1', installnic => 'mac',
    });
    set_row('mac', {node => 'node'}, {mac => '52:54:00:12:34:56'});
    set_row('bootparams', {node => 'node'}, {kcmdline => 'console=ttyS0 quiet'});
    return $dir;
}

sub set_row {
    my ($name, $key, $values) = @_;
    my $table = xCAT::Table->new($name, -create => 1) or die "Cannot create $name";
    $table->setAttribs($key, $values);
    $table->close();
    return;
}

sub render_template {
    my ($database, @arguments) = @_;
    my $root = sandbox_root();
    write_text("$root/arguments.json", encode_json(\@arguments));
    write_text("$root/render.pl", <<'PERL');
use strict;
use warnings;
use File::Slurper qw(read_text);
use JSON::PP qw(decode_json);
use xCAT::Template;
use xCAT::Postage;
my $site = xCAT::Table->new('site');
my @attributes = $site->getAllAttribs('key', 'value');
%::XCATSITEVALS = map { $_->{key} => $_->{value} } @attributes;
$site->close();
my $arguments = decode_json(read_text('/fixture/arguments.json'));
my $error = xCAT::Template->subvars(@$arguments);
die "$error\n" if $error;
PERL
    my $source = repo_path('.');
    my ($status, $output) = sandbox_run($root, {
        read_only => {$source => $source, repo_path('xCAT/postscripts') => '/install/postscripts'},
        writable => {$database => $database},
        env => {XCATROOT => $ENV{XCATROOT}, XCATCFG => $ENV{XCATCFG}},
    }, $^X, '-I' . repo_path('perl-xCAT'), '-I' . repo_path('xCAT-server/lib/perl'), '/fixture/render.pl');
    die "Template rendering failed ($status): $output" if $status;
    return;
}

1;
