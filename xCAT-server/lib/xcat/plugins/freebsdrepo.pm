package xCAT_plugin::freebsdrepo;

use strict;
use warnings;
use Getopt::Long ();
use xCAT::Table;
use xCAT::TableUtils;

sub handled_commands {
    return { freebsdrepo => 'freebsdrepo' };
}

sub _arguments {
    my ($args, $usage) = @_;
    my (@profiles, @errors);
    my ($help, $nonoverwrite) = (0, 0);
    my $parsed;
    {
        local $SIG{__WARN__} = sub { push @errors, @_ };
        my $parser = Getopt::Long::Parser->new(config => [qw(default permute no_auto_abbrev no_ignore_case)]);
        $parsed = $parser->getoptionsfromarray($args,
            'policy=s@' => \@profiles, 'w' => \$nonoverwrite, 'h|help' => \$help);
    }
    die "Invalid freebsdrepo arguments: @errors\n$usage\n"
      if !$parsed || ($help ? @$args > 1 : @$args != 1);
    return (\@profiles, $nonoverwrite, $help);
}

sub _run_action {
    my ($action, $args, $profiles, $nonoverwrite) = @_;
    require xCAT::FreeBSDRepoImport;
    if ($action eq 'inspect') {
        die "Repository inspection does not accept --policy or -w\n" if @$profiles || $nonoverwrite;
        my $tree = xCAT::FreeBSDRepo::snapshot_tree($args->[0]);
        return ["TREE_DIGEST:$tree->{digest}\nBYTES:$tree->{bytes}\n"];
    }
    die "Repository import requires exactly one --policy profile\n" unless @$profiles == 1;
    my ($policy_path) = xCAT::TableUtils->get_site_attribute('freebsdimportpolicy');
    die "site.freebsdimportpolicy is not set\n"
      if !defined($policy_path) || (!ref($policy_path) && $policy_path eq '');
    my $policy = xCAT::FreeBSDRepoImport::load_import_policy($policy_path);
    my $options = xCAT::FreeBSDRepoImport::repository_import_options($policy, $profiles->[0]);
    my $publication = xCAT::FreeBSDRepoImport::import_repository($args->[0],
        xCAT::TableUtils->getInstallDir(), %$options, nonoverwrite => $nonoverwrite);
    my $message = $publication->{reused}
      ? "Verified existing FreeBSD repository at $publication->{path}"
      : "Imported FreeBSD repository to $publication->{path}";
    return [$message, "Repository: $publication->{path}/repository"];
}

sub process_request {
    my ($request, $callback) = @_;
    return unless $request->{command}->[0] eq 'freebsdrepo';
    my @args = @{$request->{arg} || []};
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]";
    if (@args == 1 && ($args[0] eq '-h' || $args[0] eq '--help')) {
        $callback->({ data => ["$usage\n"] });
        return;
    }
    my $ok = eval {
        my $action = shift @args;
        die "$usage\n" unless defined($action) && ($action eq 'inspect' || $action eq 'import');
        my ($profiles, $nonoverwrite, $help) = _arguments(\@args, $usage);
        if ($help) {
            $callback->({ data => ["$usage\n"] });
            return 1;
        }
        my $data = _run_action($action, \@args, $profiles, $nonoverwrite);
        $callback->({ data => $data });
        1;
    };
    $callback->({ error => [$@ || 'FreeBSD repository command failed'], errorcode => [1] }) unless $ok;
    return;
}

1;
