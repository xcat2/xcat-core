# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Time::Local;
use File::Basename;
use File::Path;
use File::Find; 
use LWP::UserAgent;
use HTTP::Request;
use Encode;  
use Encode::CN; 
use JSON;  
use URI::Escape;  
use LWP::Simple;
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
    if($ENV{'TRAVIS_EVENT_TYPE'} eq "pull_request"){
        my $pr_url = "https://api.github.com/repos/$ENV{'TRAVIS_REPO_SLUG'}/pulls/$ENV{'TRAVIS_PULL_REQUEST'}";
        my $pr_url_resp = get($pr_url);
        my $pr_content = decode_json($pr_url_resp);
        my $pr_title = $pr_content->{title};
        my $pr_body  = $pr_content->{body};
        
        my $comment_url = "https://api.github.com/repos/$ENV{'TRAVIS_REPO_SLUG'}/issues/$ENV{'TRAVIS_PULL_REQUEST'}/comments";
        my $comment_url_resp = get($comment_url);
        my $json = new JSON;
        my $comment_content = $json->decode($comment_url_resp);
        
        
        #my $content_type = "Content-Type: application/json";
        print ">>>>>Dumper pr_content:\n";
        print Dumper $pr_content;
        print ">>>>>pr title = $pr_title\n";
        print ">>>>>pr body = $pr_body \n";
        
        print ">>>>>Dumper comment_content:\n";
        print Dumper $comment_content;
        
    }
    return 0;
}

#===============Main Process=============================

print BOLD GREEN "\n------Dumper Travis Environment Attribute------\n";
my @travis_env_attr = ("TRAVIS_REPO_SLUG",
                       "TRAVIS_BRANCH",
                       "TRAVIS_EVENT_TYPE",
                       "TRAVIS_PULL_REQUEST",
                       "GITHUB_TOKEN",
                       "USERNAME",
                       "PASSWORD",
                       "PWD");
foreach (@travis_env_attr){
    print "$_ = $ENV{$_}\n"; 
}

print BOLD GREEN "\n------To Check Pull Request Format------\n";
$rst  = check_pr_format();
if($rst){
    print RED "Check pull request format failed\n";
}

exit 0;
