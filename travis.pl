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
my $retries = 5; # Try this many times to get response
my $check_result_str="``CI CHECK RESULT`` : ";
my $last_func_start = timelocal(localtime());
my $GITHUB_API = "https://api.github.com";

#--------------------------------------------------------
# Fuction name: runcmd
# Description:  run a command after 'cmd' label in one case
# Attributes:
# Return code:
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
# Attributes:
#         $dir (input attribute)
#              The target scan directory
#         $files_path_ref (output attribute)
#               the reference of array where save all vaild files under $dir
# Return code:
#--------------------------------------------------------
sub get_files_recursive
{
    my $dir            = shift;
    my $files_path_ref = shift;

    my $fd = undef;
    if(!opendir($fd, $dir)){
        print "[get_files_recursive]: failed to open $dir :$!\n";
        return 1;
    }

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
    return 0;
}

#--------------------------------------------------------
# Fuction name: check_pr_format
# Description:
# Attributes:
# Return code:
#--------------------------------------------------------
sub check_pr_format{
    if($ENV{'TRAVIS_EVENT_TYPE'} eq "pull_request"){
        my $pr_url = "$GITHUB_API/repos/$ENV{'TRAVIS_REPO_SLUG'}/pulls/$ENV{'TRAVIS_PULL_REQUEST'}";
        my $pr_url_resp;
        my $counter = 1;
        while($counter <= $retries) {
            $pr_url_resp = get($pr_url);
            if ($pr_url_resp) {
                last; # Got response, no more retries
            } else {
                sleep($counter*2); # Sleep and try again
                print "[check_pr_format] $counter Did not get response, sleeping ". $counter*2 . "\n";
                $counter++;
            }
        }
        unless ($pr_url_resp) {
            print "[check_pr_format] After $retries retries, not able to get response from $pr_url \n";
            # Failed after trying a few times, return error
            return $counter;
        }
        my $pr_content = decode_json($pr_url_resp);
        my $pr_title = $pr_content->{title};
        my $pr_body  = $pr_content->{body};
        my $pr_milestone = $pr_content->{milestone};
        my $pr_labels_len = @{$pr_content->{labels}};

        #print "[check_pr_format] Dumper pr_content:\n";
        #print Dumper $pr_content;
        print "[check_pr_format] pr title = $pr_title\n";
        print "[check_pr_format] pr body = $pr_body \n";

        my $checkrst="";
        if(! $pr_title){
            $checkrst.="Missing title.";
        }
        if(! $pr_body){
             $checkrst.="Missing description.";
        }

        if(! $pr_milestone){
             $checkrst.="Missing milestone.";
        }

        if(! $pr_labels_len){
             $checkrst.="Missing labels.";
        }

        # Guard against root user making commits
        $checkrst.=check_commit_owner('root');

        if(length($checkrst) == 0){
            $check_result_str .= "> **PR FORMAT CORRECT**";
            send_back_comment("$check_result_str");
        }else{
            # Warning if missing milestone or labels, others are errors
            if($checkrst =~ /milestone/ || $checkrst =~ /labels/){
                $check_result_str .= "> **PR FORMAT WARNING** : $checkrst";
                send_back_comment("$check_result_str");
            }else{
                $check_result_str .= "> **PR FORMAT ERROR** : $checkrst";
                send_back_comment("$check_result_str");
                return 1;
            }
        }
    }
    return 0;
}

#--------------------------------------------------------
# Fuction name: check_commit_owner
# Description: Verify commits are not done by specified user
# Attributes: user login to reject
# Return:
#     Error string -User rejected,
#     Empty string -User not rejected
#--------------------------------------------------------
sub check_commit_owner{
    my $invalid_user = shift;
    if($ENV{'TRAVIS_EVENT_TYPE'} eq "pull_request"){
        my $commits_content;
        my $commits_len = 0;
        my $json = new JSON;
        my $commits_url = "$GITHUB_API/repos/$ENV{'TRAVIS_REPO_SLUG'}/pulls/$ENV{'TRAVIS_PULL_REQUEST'}/commits";
        my $commits_url_resp;
        my $counter = 1;
        while($counter <= $retries) {
            $commits_url_resp = get($commits_url);
            if ($commits_url_resp) {
                last; # Got response, no more retries
            } else {
                sleep($counter*2); # Sleep and try again
                print "[check_commit_owner] $counter Did not get response, sleeping ". $counter*2 . "\n";
                $counter++;
            }
        }
        if ($commits_url_resp) {
            $commits_content = $json->decode($commits_url_resp);
            $commits_len = @$commits_content;
        } else {
            print "[check_commit_owner] After $retries retries, not able to get response from $commits_url \n";
            return "Unable to verify login of committer.";
        }

        if($commits_len > 0) {
            foreach my $commit (@{$commits_content}){
                my $committer = $commit->{committer};
                my $committer_login  = $committer->{login};
                print "[check_commit_owner] Committer login $committer_login \n";
                if($committer_login =~ /^$invalid_user$/) {
                    # Committer logins matches
                    return "Commits by $invalid_user not allowed";
                }
            }
        }
    }
    return "";
}
#--------------------------------------------------------
# Fuction name: send_back_comment
# Description: Append to comment of the PR passed $message
# Attributes: Message to append to PR
# Return code:
#--------------------------------------------------------
sub send_back_comment{
    my $message = shift;

    my $comment_url = "$GITHUB_API/repos/$ENV{'TRAVIS_REPO_SLUG'}/issues/$ENV{'TRAVIS_PULL_REQUEST'}/comments";
    my $json = new JSON;
    my $comment_len = 0;
    my $comment_content;
    my $comment_url_resp;
    my $counter = 1;
    while($counter <= $retries) {
        $comment_url_resp = get($comment_url);
        if ($comment_url_resp) {
            last; # Got response, no more retries
        } else {
            sleep($counter*2); # Sleep and try again
            print "[send_back_comment] $counter Did not get response, sleeping ". $counter*2 . "\n";
            $counter++;
        }
    }
    unless ($comment_url_resp) {
        print "[send_back_comment] After $retries retries, not able to get response from $comment_url \n";
        # Failed after trying a few times, return
        return;
    }
    print "\n\n>>>>>Dumper comment_url_resp:\n";
    print Dumper $comment_url_resp;

    $comment_content = $json->decode($comment_url_resp);
    $comment_len = @$comment_content;

    my $post_url = $comment_url;
    my $post_method = "POST";
    if($comment_len > 0){
        foreach my $comment (@{$comment_content}){
            if($comment->{'body'} =~ /CI CHECK RESULT/) {
                 $post_url = $comment->{'url'};
                 $post_method = "PATCH";
            }
        }
    }

    print "[send_back_comment] method = $post_method to $post_url. Message = $message\n";
    if ( $ENV{'xcatbotuser'} and $ENV{'xcatbotpw'}) {
        `curl -u "$ENV{'xcatbotuser'}:$ENV{'xcatbotpw'}" -X $post_method -d '{"body":"$message"}' $post_url`;
    }
    else {
        print "Not able to update pull request with message: $message\n";
    }
}

#--------------------------------------------------------
# Fuction name: build_xcat_core
# Description:
# Attributes:
# Return code:
#--------------------------------------------------------
sub build_xcat_core{
    my @output;
    #my @cmds = ("gpg --list-keys",
    #            "sed -i '/SignWith: /d' $ENV{'PWD'}/build-ubunturepo");
    #foreach my $cmd (@cmds){
    #    print "[build_xcat_core] running $cmd\n";
    #    @output = runcmd("$cmd");
    #    if($::RUNCMD_RC){
    #        print "[build_xcat_core] $cmd ....[Failed]\n";
    #        send_back_comment("> **BUILD ERROR** : $cmd failed. Please click ``Details`` label in ``Merge pull request`` box for detailed information");
    #        return 1;
    #    }
    #}

    my $cmd = "sudo ./build-ubunturepo -c UP=0 BUILDALL=1 GPGSIGN=0";
    @output = runcmd("$cmd");
    print ">>>>>Dumper the output of '$cmd'\n";
    print Dumper \@output;
    if($::RUNCMD_RC){
        my $lastline = $output[-1];
        $lastline =~ s/[\r\n\t\\"']*//g;
        print "[build_xcat_core] $cmd ....[Failed]\n";
        #print ">>>>>Dumper the output of '$cmd'\n";
        #print Dumper \@output;
        $check_result_str .= "> **BUILD ERROR**, Please click ``Details`` label in ``Merge pull request`` box for detailed information";
        send_back_comment("$check_result_str");
        return 1;
    }else{
        print "[build_xcat_core] $cmd ....[Pass]\n";
        $check_result_str .= "> **BUILD SUCCESSFUL** ";
        send_back_comment("$check_result_str");
    }

#    my $buildpath ="/home/travis/build/xcat-core/";
#    my @buildfils = ();
#    get_files_recursive("$buildpath", \@buildfils);
#    print "\n-----------Dumper build files-----------\n";
#    print Dumper \@buildfils;

    return 0;
}

#--------------------------------------------------------
# Fuction name: install_xcat
# Description:
# Attributes:
# Return code:
#--------------------------------------------------------
sub install_xcat{

    my @cmds = ("cd ./../../xcat-core && sudo ./mklocalrepo.sh",
               "sudo chmod 777 /etc/apt/sources.list",
               "sudo echo \"deb [arch=amd64 allow-insecure=yes] http://xcat.org/files/xcat/repos/apt/devel/xcat-dep bionic main\" >> /etc/apt/sources.list",
               "sudo echo \"deb [arch=ppc64el allow-insecure=yes] http://xcat.org/files/xcat/repos/apt/devel/xcat-dep bionic main\" >> /etc/apt/sources.list",
               "sudo wget -q -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add -",
               "sudo apt-get -qq --allow-insecure-repositories update");
    my @output;
    foreach my $cmd (@cmds){
        print "[install_xcat] running $cmd\n";
        @output = runcmd("$cmd");
        if($::RUNCMD_RC){
            print RED "[install_xcat] $cmd. ...[Failed]\n";
            print "[install_xcat] error message:\n";
            print Dumper \@output;
            $check_result_str .= "> **INSTALL XCAT ERROR** : Please click ``Details`` label in ``Merge pull request`` box for detailed information ";
            send_back_comment("$check_result_str");
            return 1;
        }
    }

    my $cmd = "sudo apt-get install xcat --allow-remove-essential --allow-unauthenticated";
    @output = runcmd("$cmd");
    #print ">>>>>Dumper the output of '$cmd'\n";
    #print Dumper \@output;
    if($::RUNCMD_RC){
        my $lastline = $output[-1];
        $lastline =~ s/[\r\n\t\\"']*//g;
        print "[install_xcat] $cmd ....[Failed]\n";
        print ">>>>>Dumper the output of '$cmd'\n";
        print Dumper \@output;
        $check_result_str .= "> **INSTALL XCAT ERROR** : Please click ``Details`` label in ``Merge pull request`` box for detailed information";
        send_back_comment("$check_result_str");
        return 1;
    }else{
        print "[install_xcat] $cmd ....[Pass]\n";

        print "\n------Config xcat and verify xcat is working correctly-----\n";
        @cmds = ("sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis",
                 "sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow",
                 ". /etc/profile.d/xcat.sh && tabdump policy",
                 ". /etc/profile.d/xcat.sh && tabdump site",
                 ". /etc/profile.d/xcat.sh && lsxcatd -a",
                 "ls /opt/xcat/sbin",
                 "service xcatd status");
        my $ret = 0;
        foreach my $cmd (@cmds){
            print "\n[install_xcat] running $cmd.....\n";
            @output = runcmd("$cmd");
            print Dumper \@output;
            if($::RUNCMD_RC){
               print RED "[install_xcat] $cmd. ...[Failed]\n";
               #print Dumper \@output;
               $ret = 1;
            }else{
               print "[install_xcat] $cmd....[Pass]\n";
            }
        }
        $cmd = "sudo apt-get install xcat-probe --allow-remove-essential --allow-unauthenticated";
        @output = runcmd("$cmd");
        if($::RUNCMD_RC){
            print RED "[install_xcat] $cmd ....[Failed]\n";
            print Dumper \@output;
            $ret = 1;
        }else{
            print "[install_xcat] $cmd ....[Pass]:\n";
        }

        if($ret){
            $check_result_str .= "> **INSTALL XCAT ERROR** : Please click ``Details`` label in ``Merge pull request`` box for detailed information";
            send_back_comment("$check_result_str");
            return 1;
        }

        $check_result_str .= "> **INSTALL XCAT SUCCESSFUL**";
        send_back_comment("$check_result_str");
    }
    return 0;
}


#--------------------------------------------------------
# Fuction name: check_syntax
# Description:
# Attributes:
# Return code:
#--------------------------------------------------------
sub check_syntax{
    my @output;
    my @syntax_err;
    my $ret = 0;

    my @target_dirs=("/opt/xcat",
                     "/install");
    foreach my $dir (@target_dirs){
        my @files    = ();
        get_files_recursive("$dir", \@files);

        foreach my $file (@files) {
            next if($file =~ /\/opt\/xcat\/share\/xcat\/netboot\/genesis\//);
            next if($file =~ /\/opt\/xcat\/probe\//);

            @output = runcmd("file $file");
            if($output[0] =~ /perl /i){
                @output = runcmd("sudo bash -c '. /etc/profile.d/xcat.sh && perl -I /opt/xcat/lib/perl -I /opt/xcat/lib -I /usr/lib/perl5 -I /usr/share/perl -c $file'");
                if($::RUNCMD_RC){
                    push @syntax_err, @output;
                    $ret = 1;
                }
            #}elsif($output[0] =~ /shell/i){
            #    @output = runcmd("sudo bash -c '. /etc/profile.d/xcat.sh && sh -n $file'");
            #    if($::RUNCMD_RC){
            #        push @syntax_err, @output;
            #        $ret = 1;
            #    }
            }
        }
    }

    if(@syntax_err){
        print "[check_syntax] syntax checking ....[Failed]\n";
        print "[check_syntax] Dumper error message:\n";
        print Dumper @syntax_err;
        $check_result_str .= "> **CODE SYNTAX ERROR** : Please click ``Details`` label in ``Merge pull request`` box for detailed information";
        send_back_comment("$check_result_str");
    }else{
        print "[check_syntax] syntax checking ....[Pass]\n";
        $check_result_str .= "> **CODE SYNTAX CORRECT**";
        send_back_comment("$check_result_str");
    }

    return $ret;
}

#--------------------------------------------------------
# Fuction name: run_fast_regression_test
# Description:
# Attributes:
# Return code:
#--------------------------------------------------------
sub run_fast_regression_test{
    my $cmd = "sudo apt-get install xcat-test --allow-remove-essential --allow-unauthenticated";
    my @output = runcmd("$cmd");
    if($::RUNCMD_RC){
         print RED "[run_fast_regression_test] $cmd ....[Failed]\n";
         print Dumper \@output;
         return 1;
    }else{
        print "[run_fast_regression_test] $cmd .....:\n";
        print Dumper \@output;
    }

    $cmd = "sudo bash -c '. /etc/profile.d/xcat.sh && xcattest -h'";
    @output = runcmd("$cmd");
    if($::RUNCMD_RC){
         print RED "[run_fast_regression_test] $cmd ....[Failed]\n";
         print "[run_fast_regression_test] error dumper:\n";
         print Dumper \@output;
         return 1;
    }else{
         print "[run_fast_regression_test] $cmd .....:\n";
         print Dumper \@output;
    }

    my $hostname = `hostname`;
    chomp($hostname);
    print "hostname = $hostname\n";
    my $conf_file = "$ENV{'PWD'}/regression.conf";
    $cmd = "echo '[System]' > $conf_file; echo 'MN=$hostname' >> $conf_file; echo '[Table_site]' >> $conf_file; echo 'key=domain' >>$conf_file; echo 'value=pok.stglabs.ibm.com' >> $conf_file";
    @output = runcmd("$cmd");
    if($::RUNCMD_RC){
         print RED "[run_fast_regression_test] $cmd ....[Failed]";
         print "[run_fast_regression_test] error dumper:\n";
         print Dumper \@output;
         return 1;
    }

    print "Dumper regression conf file:\n";
    @output = runcmd("cat $conf_file");
    print Dumper \@output;

    $cmd = "sudo bash -c '. /etc/profile.d/xcat.sh && xcattest -s \"ci_test\" -l'";
    my  @caseslist = runcmd("$cmd");
    if($::RUNCMD_RC){
         print RED "[run_fast_regression_test] $cmd ....[Failed]\n";
         print "[run_fast_regression_test] error dumper:\n";
         print Dumper \@caseslist;
         return 1;
    }else{
         print "[run_fast_regression_test] $cmd .....:\n";
         print Dumper \@caseslist;
    }


    #my @caseslist = runcmd("sudo bash -c '. /etc/profile.d/xcat.sh && xcattest -l caselist -b MN_basic.bundle'");
    my $casenum = @caseslist;
    my $x = 0;
    my @failcase;
    my $passnum = 0;
    my $failnum = 0;
    foreach my $case (@caseslist){
        ++$x;
        $cmd = "sudo bash -c '. /etc/profile.d/xcat.sh &&  xcattest -f $conf_file -t $case'";
        print "[run_fast_regression_test] run $x: $cmd\n";
        @output = runcmd("$cmd");
        #print Dumper \@output;
        for(my $i = $#output; $i>-1; --$i){
            if($output[$i] =~ /------END::(.+)::Failed/){
                push @failcase, $1;
                ++$failnum;
                print Dumper \@output;
                last;
             }elsif ($output[$i] =~ /------END::(.+)::Passed/){
                ++$passnum;
                last;
             }
         }
    }

    if($failnum){
        my $log_str = join (",", @failcase );
        $check_result_str .= "> **FAST REGRESSION TEST Failed**: Totalcase $casenum Passed $passnum Failed $failnum FailedCases: $log_str.  Please click ``Details`` label in ``Merge pull request`` box for detailed information";
        send_back_comment("$check_result_str");
        return 1;
    }else{
        $check_result_str .= "> **FAST REGRESSION TEST Successful**: Totalcase $casenum Passed $passnum Failed $failnum";
        send_back_comment("$check_result_str");
    }

    return 0;
}

#--------------------------------------------------------
# Fuction name: mark_time
# Description:
# Attributes:
# Return code:
#--------------------------------------------------------
sub mark_time{
    my $func_name=shift;
    my $nowtime    = timelocal(localtime());
    my $nowtime_str = scalar(localtime());
    my $duration = $nowtime - $last_func_start;
    $last_func_start = $nowtime;
    print "[mark_time] $nowtime_str, ElapsedTime of $func_name is $duration s\n";
}

#===============Main Process=============================

#Dumper Travis Environment Attribute
print GREEN "\n------ Travis Environment Attributes ------\n";
my @travis_env_attr = ("TRAVIS_REPO_SLUG",
                       "TRAVIS_BRANCH",
                       "TRAVIS_EVENT_TYPE",
                       "TRAVIS_PULL_REQUEST",
                       "GITHUB_TOKEN",
                       "USERNAME",
                       "PASSWORD",
                       "PWD");
foreach (@travis_env_attr){
    if($ENV{$_}) {
        print "$_ = '$ENV{$_}'\n";
    } else {
        print "$_ = ''\n";
    }
}

my @os_info = runcmd("cat /etc/os-release");
print "Current OS information:\n";
print Dumper \@os_info;

my @perl_vserion = runcmd("perl -v");
print "Current perl information:\n";
print Dumper \@perl_vserion;

#my @sh_version = runcmd("sudo bash -c 'sh --version'");
#print "Current sh information:\n";
#print Dumper \@sh_version;

my @disk = runcmd("df -h");
print "Disk information:\n";
print Dumper \@disk;

# Hacking the netmask. Not sure if we need to recover it after finish xcattest
# Note: Here has an assumption from Travis VM: only 1 UP Ethernet interface available (CHANGEME if it not as is)
my @intfinfo = runcmd("ip -o link |grep 'link/ether'|grep 'state UP' |awk -F ':' '{print \$2}'|head -1");
foreach my $nic (@intfinfo) {
    print "Hacking the netmask length to 16 if it is 32: $nic\n";
    runcmd("ip -4 addr show $nic|grep 'inet'|grep -q '/32' && sudo ip addr add \$(hostname -I|awk '{print \$1}')/16 dev $nic");
}
my @ipinfo = runcmd("ip addr");
print "Networking information:\n";
print Dumper \@ipinfo;

#Start to check the format of pull request
$last_func_start = timelocal(localtime());
print GREEN "\n------ Checking Pull Request Format ------\n";
$rst  = check_pr_format();
my $redo_check_pr = 0;
if($rst){
     if($rst <= $retries) {
        print RED "Check of pull request format failed\n";
        exit $rst;
    }
    $redo_check_pr = 1;
}
mark_time("check_pr_format");

#Start to build xcat core

print GREEN "\n------ Building xCAT core package ------\n";
$rst = build_xcat_core();
if($rst){
    print RED "Build of xCAT core package failed\n";
    exit $rst;
}
mark_time("build_xcat_core");

#Start to install xcat
print GREEN "\n------Installing xCAT ------\n";
$rst = install_xcat();
if($rst){
    print RED "Install of xCAT failed\n";
    exit $rst;
}
mark_time("install_xcat");

#Check the syntax of changing code
print GREEN "\n------ Checking the syntax of changed code------\n";
$rst = check_syntax();
if($rst){
    print RED "Check syntax of changed code failed\n";
    exit $rst;
}
mark_time("check_syntax");

#run fast regression
print GREEN "\n------Running fast regression test ------\n";
$rst = run_fast_regression_test();
if($rst){
    print RED "Run of fast regression test failed\n";
    exit $rst;
}
mark_time("run_fast_regression_test");

if ($redo_check_pr) {
    print GREEN "\n------ Checking Pull Request Format ------\n";
    $rst  = check_pr_format();
    if($rst){
        print RED "Check of pull request format failed\n";
        exit $rst;
    }
    mark_time("check_pr_format");
}

exit 0;
