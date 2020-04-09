#!/usr/bin/perl
use strict;
use warnings;
use HTTP::Request;
use JSON;
#use LWP::Simple;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);

# first, create your message
=pod
use Email::MIME;
my $message = Email::MIME->create(
  header_str => [
    From    => 'Nicmays334@gmail.com',
    To      => 'Nicolas.Mays@ibm.com',
    Subject => 'Happy birthday!',
  ],
  attributes => {
    encoding => 'quoted-printable',
    charset  => 'ISO-8859-1',
  },
  body_str => "Happy birthday to you!\n",
);

# send the message
use Email::Sender::Simple qw(sendmail);
sendmail($message);
=cut

my $commit_api_ep = "https://api.github.com/repos/xcat2/xcat-core/git/commits";
my $commit_hash = "39fa3f2ba662e31268790788de97e4d9b8a370c1";
my $fully_qualified_url = $commit_api_ep . $commit_hash;
print $fully_qualified_url."\n";
my $pr_url_resp;
#$pr_url_resp = get($fully_qualified_url);
$pr_url_resp = `curl $commit_api_ep/$commit_hash`;
#print $pr_url_resp;

my $pr_content = decode_json($pr_url_resp);
my $pr_title = $pr_content->{author}->{email};
print "nic $pr_title\n";
my $pr_body  = $pr_content->{body};

my $reviewer_email = '38794505+besawn@users.noreply.github.com';


my $nic = 'hi nic';
print $nic;

=pod
my $message = Email::MIME->create(
  header_str => [
    From    => 'xCatBot@gmail.com',
    To      => 'besawn@us.ibm.com',
    Subject => 'xcatbot test',
  ],
  attributes => {
    encoding => 'quoted-printable',
    charset  => 'ISO-8859-1',
  },
  body_str => "This was sent from a stand-alone perl script",
);

# send the message
sendmail($message);
=cut
