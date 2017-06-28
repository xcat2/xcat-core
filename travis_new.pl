# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Time::Local;
use File::Basename;
use File::Path;
use File::Find; 
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;
use LWP::UserAgent;
use HTTP::Request;
use Encode;  
use Encode::CN; 
use JSON;  
use URI::Escape;  
use LWP::Simple;

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
        
   
        #my $content_type = "Content-Type: application/json";
        print ">>>>>Dumper pr_content:\n";
        print Dumper $pr_content;
        print ">>>>>pr title = $pr_title\n";
        print ">>>>>pr body = $pr_body \n";
        
        
        
    }
    return 0;
}

sub send_back_comment{
    my $message = shift;
   
    my $comment_url = "https://api.github.com/repos/$ENV{'TRAVIS_REPO_SLUG'}/issues/$ENV{'TRAVIS_PULL_REQUEST'}/comments";
    my $comment_url_resp = get($comment_url);
    my $json = new JSON;
    my $comment_content = $json->decode($comment_url_resp);
    my $comment_len = @$comment_content;
    
    print ">>>>>Dumper comment_content:\n";
    print Dumper $comment_content;
    
    my $post_url = undef;
    my $post_method = undef;
    if($comment_len > 1){
        foreach my $comment (@{$comment_content}){
            if($comment->{'body'} =~ /SYNTAX/){
                $post_url = "https://api.github.com/repos/$ENV{'TRAVIS_REPO_SLUG'}/issues/comments/$comment->{'id'}";
            }elsif($comment->{'body'} =~ /BUILD/){
                $post_url = "https://api.github.com/repos/$ENV{'TRAVIS_REPO_SLUG'}/issues/comments/$comment->{'id'}";
            }elsif($comment->{'body'} =~ /INSTALL/){
                $post_url = "https://api.github.com/repos/$ENV{'TRAVIS_REPO_SLUG'}/issues/comments/$comment->{'id'}";
            }
        }
        $post_method = "PATCH";
    }else{
        $post_url = $comment_url;
        $post_method = "POST";
    }
    
    `curl -u "$username:$password" -X $post_method -d '{"body":"$message"}' $post_url`;
}
#--------------------------------------------------------
# Fuction name: build_xcat_core
# Description:  
# Atrributes:
# Retrun code:
#--------------------------------------------------------
sub build_xcat_core{
    my $cmd = "gpg --list-keys";
    my @output = runcmd("$cmd");
    if($::RUNCMD_RC){
        print "[build_xcat_core] $cmd ....[Failed]\n";
        return 1;
    }
    
    $cmd = "sudo ./build-ubunturepo -c UP=0 BUILDALL=1";
    @output = runcmd("$cmd");
    print ">>>>>Dumper the output of '$cmd'\n";
    print Dumper \@output;
    if($::RUNCMD_RC){
        my $lastline = $output[-1];
        $lastline =~ s/[\r\n\t\\"']*//g;
        print "[build_xcat_core] $cmd ....[Failed]\n";
        send_back_comment("> **BUILD_ERROR**  :  $lastline");
        return 1;        
    }else{
        print "[build_xcat_core] $cmd ....[Pass]\n";
        send_back_comment("> **BUILD SUCCESSFUL**");
    }
   
    return 0;
}

#--------------------------------------------------------
# Fuction name: install_xcat
# Description:  
# Atrributes:
# Retrun code:
#--------------------------------------------------------
sub install_xcat{
    return 0;
}


#--------------------------------------------------------
# Fuction name: check_syntax
# Description:  
# Atrributes:
# Retrun code:
#--------------------------------------------------------
sub check_syntax{
    return 0;
}

#--------------------------------------------------------
# Fuction name: run_fast_regression_test
# Description:  
# Atrributes:
# Retrun code:
#--------------------------------------------------------
sub run_fast_regression_test{
    return 0;
}

#===============Main Process=============================

#Dumper Travis Environment Attribute
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

#Start to check the format of pull request
print BOLD GREEN "\n------To Check Pull Request Format------\n";
$rst  = check_pr_format();
if($rst){
    print RED "Check pull request format failed\n";
}

#Start to build xcat core 
print BOLD GREEN "\n------To Build xCAT core package------\n";
$rst = build_xcat_core();
if($rst){
    print RED "Build xCAT core package failed\n";
}

#Start to install xcat
print BOLD GREEN "\n------To install xcat------\n";
$rst = install_xcat();
if($rst){
    print RED "Install xcat failed\n";
}

#Check the syntax of changing code 
print BOLD GREEN "\n------To check the syntax of changing code------\n";
$rst = check_syntax();
if($rst){
    print RED "check the syntax of changing code failed\n";
}

#run fast regression
print BOLD GREEN "\n------To run fast regression test------\n";
$rst = run_fast_regression_test();
if($rst){
    print RED "Run fast regression test failed\n";
}

exit 0;
