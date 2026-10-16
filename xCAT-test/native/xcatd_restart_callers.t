#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Lifecycle;

plan skip_all => 'Run on Linux; missing namespace or RPM spec tools fail' unless $^O eq 'linux';

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag "$result[1]$result[2]";
}

for my $live (0, 1) {
    for my $event (qw(upgrade remove purge abort-upgrade)) {
      for my $installed (0, 1) {
        my $root = XCAT::Test::Lifecycle->new;
        $root->{live} = $live;
        $root->record_command('/opt/xcat/sbin/restartxcatd') if $installed;
        $root->write('/calls', '');
        succeeds("Debian perl-xCAT $event (proc=$live)", $root->run('/bin/sh',
            '/source/perl-xCAT/debian/postrm', $event, '2.20.0'));
        is($root->read('/calls'), $live && $installed && $event eq 'upgrade' ? "restartxcatd <-r>\n" : '',
            'only an upgrade with proc and an installed helper requests a fast reload');
      }
    }
}

for my $package (qw(xCAT-OpenStack xCAT-UI perl-xCAT)) {
    my $records = XCAT::Test::Lifecycle::checked('rpmspec', '-q', '--qf', "%{NAME}\x1e%{POSTIN}\x1e",
        '--define', 'version 2.20.0', '--define', 'release 1', '--define', 'gitinfo test',
        repo_path("$package/$package.spec"));
    my %scriptlets = split /\x1e/, $records;
    my $script = $scriptlets{$package};
    die "Missing $package post-install script" unless defined($script) && $script ne '(none)';
    for my $live (0, 1) {
        for my $event (1, 2) {
          for my $installed (0, 1) {
            my $root = XCAT::Test::Lifecycle->new;
            $root->{live} = $live;
            $root->write('/postin', $script);
            $root->write('/calls', '');
            $root->write('/etc/profile.d/xcat.sh', "printf 'profile\\n' >> /calls\n");
            for my $name (qw(restartxcatd xcatd chtab)) {
                $root->record_command("/opt/xcat/sbin/$name") if $installed || $name eq 'chtab';
            }
            $root->record_command('/etc/init.d/httpd');
            $root->record_command('/test-bin/hostname');
            $root->write('/etc/redhat-release', 'test');
            $root->write('/etc/shadow', "root:*:0:0:0:0:0:0:0\n");
            $root->write('/etc/php.ini', "output_buffering = 4096\n");
            $root->write('/opt/xcat/ui/.fixture', '');
            succeeds("$package event $event (proc=$live)", $root->run('env',
                'RPM_INSTALL_PREFIX0=/opt/xcat', '/bin/sh', '/postin', $event));
            my $calls = $root->read('/calls');
            if ($package eq 'perl-xCAT') {
                is($calls, $live && $installed && $event == 2 ? "profile\n" : '',
                    'upgrade detects the server without a legacy init script');
            } else {
                my @restarts = $calls =~ /^(restartxcatd[^\n]*)$/mg;
                is_deeply(\@restarts, $installed && ($package eq 'xCAT-UI' || $live) ? ['restartxcatd'] : [],
                    'package preserves fast restart semantics');
            }
          }
        }
    }
}

done_testing();
