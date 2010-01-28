package xCAT_plugin::offline;
BEGIN
{
	$::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use Getopt::Long;
use File::Basename;
use File::Path;
use File::Copy;
use File::Find;
use Cwd;
use File::Temp;
use xCAT::SvrUtils;
use Data::Dumper;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $verbose = "0";

sub handled_commands {
        return {
                "offline" => "offline"
        }
}


# function to handle request.  Basically, get the information
# about the image and then do the action on it.  Is that vague enough?
sub process_request {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;

	GetOptions(
		"version|v" => \$version,
	);

	if ($version) {
		my $version = xCAT::Utils->Version();
		$callback->({info=>[$version]});
		return;
	}
	if ($help) {
		$callback->({info=>["This command really doesn't do anything"]});
		return;
	}

	if($request->{node}){
		$noderange = $request->{node};
	}else{
		$callback->({error=>["No nodes specified in request for offline"]});
	}
	

	my @nodes = @{$noderange};
	foreach my $n (@nodes){
		$callback->({info=>["$n: offline"]});
	}
}

1;
