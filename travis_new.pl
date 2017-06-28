# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Time::Local;
use File::Basename;
use File::Path;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

#---Global attributes---
my $rst = 0;

#--------------------------------------------------------
# Fuction name: runcmd
# Description:  run a command after 'cmd' label in one case
# Atrributes:
# Retrun code:
#      $::RUNCMD_RC : the return code of command
#      @$outref  : the output of command
#--------------------------------------------------------
sub runcmd
{
    my ($cmd) = @_;
    my $rc = 0;
    $::RUNCMD_RC = 0;
    my $outref = [];
    @$outref = `$cmd 2>&1`;
    if ($?)
    {
        $rc          = $?;
        $rc          = $rc >> 8;
        $::RUNCMD_RC = $rc;
    }
    chomp(@$outref);
    return @$outref;

}

#--------------------------------------------------------
# Fuction name: get_files_recursive
# Description:  Search all file in one directory recursively
# Atrributes:
#         $dir (input attribute)
#              The target scan directory
#         $files_path_ref (output attribute)
#               the reference of array where save all vaild files under $dir
# Retrun code:
#--------------------------------------------------------
sub get_files_recursive
{
    my $dir            = shift;
    my $files_path_ref = shift;

    my $fd = undef;
    opendir($fd, $dir);
    for (; ;)
    {
        my $direntry = readdir($fd);
        last unless (defined($direntry));
        next if ($direntry =~ m/^\.\w*/);
        next if ($direntry eq '..');
        my $target = "$dir/$direntry";
        if (-d $target) {
            get_files_recursive($target, $files_path_ref);
        } else {
            push(@{$files_path_ref}, glob("$target\n"));
        }
    }
    closedir($fd);
}

#--------------------------------------------------------
# Fuction name: check_pr_format
# Description:  
# Atrributes:
# Retrun code:
#--------------------------------------------------------
sub check_pr_format{
    return 0;
}

#===============Main Process=============================
my @travis_env_attr = ("TRAVIS_REPO_SLUG",
                       "TRAVIS_BRANCH",
                       "RAVIS_EVENT_TYPE",
                       "GITHUB_TOKEN",
                       "USERNAME",
                       "PASSWORD",
                       "PWD");
                       
print BOLD GREEN "------Dumper Travis Environment Attribute------\n";
foreach (@travis_env_attr){
    print "$_ = $ENV{$_}\n"; 
}

print BOLD GREEN "------To Check Pull Request Format------\n";
$rst  = check_pr_format();
if($rst){
    print RED "Check pull request format failed\n";
}

exit 0;
