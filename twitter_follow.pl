#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

# Find modules installed w/ Carton
use FindBin;
use lib "$FindBin::Bin/local/lib/perl5";

use Config::JFDI;
use Data::Dumper;
use DateTime;
use Date::Parse;
use FindBin qw($Bin);
use Getopt::Long::Descriptive;
use Net::Twitter::Lite::WithAPIv1_1;
use Net::Google::Spreadsheets;
use Scalar::Util 'blessed';

my ( $opt, $usage )
    = describe_options( '%c %o',
    [ 'debug|d', "don't actually do anything, but be verbose" ],
    [ 'council|c', "follow council" ],
    [ 'trustees|t', "follow trustees" ],
    );
say "Not doing anything because the debug flag is set..." if $opt->debug;

print($usage->text), exit unless $opt->council or $opt->trustees;

my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;
say Dumper( $conf ) if $opt->debug;

my $office_worksheet = $opt->council ? 'council_worksheet_title' : 'tdsb_worksheet_title';
say "Using the worksheet: $office_worksheet" if $opt->debug;

my $nt;    # Variable for the Net::Twitter object
$nt = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key        => $conf->{'tw_con_key'},
    consumer_secret     => $conf->{'tw_con_secret'},
    access_token        => $conf->{'tw_access_tok'},
    access_token_secret => $conf->{'tw_access_key'},
    ssl                 => 1,
);



main();

sub main {
    my $service = Net::Google::Spreadsheets->new(
        username => $conf->{'google_user'},
        password => $conf->{'google_pass'},
    );
    my $worksheet = get_worksheet_from_google( $service );  
    my $urls_to_parse = get_twitter_urls( $worksheet );
    #say Dumper( $urls_to_parse );
    my $usernames = parse_twitter_usernames( $urls_to_parse );
    say Dumper( $usernames );
    my $results = follow_twitter_users( $usernames );
    say Dumper( $results );
}

sub get_worksheet_from_google {
    my $service = shift;

    # find a spreadsheet by title
    my $spreadsheet = $service->spreadsheet(
        { title => $conf->{'google_spreadsheet_title'} } );

    #find a worksheet by title
    my $worksheet = $spreadsheet->worksheet(
        { title => $conf->{ $office_worksheet } } );
    return $worksheet;
}

sub get_twitter_urls {
    my $worksheet = shift;
    my @rows = $worksheet->rows;
    my @twitter_urls;
    for my $row ( @rows ) {
        my $r = $row->{'content'};
        push @twitter_urls, $r->{'twitter'} if $r->{'twitter'};
    }
    return \@twitter_urls;
}

sub parse_twitter_usernames {
    my $urls = shift;
    my @twitter_users;
    for my $url ( @$urls ) {
       my $user = parse_twitter_username( $url );
       push @twitter_users, $user;
    }
    return \@twitter_users;
}

sub parse_twitter_username {
    my $url = shift;
    my ( $username ) = ( $url =~ /twitter.com\/(.*)$/ );
    return $username;
}

sub follow_twitter_users {
    my $users = shift;
    my @results;
    for my $user ( @$users ) {
       #next if $nt->follows({ user_a => 'everycandidate', user_b => $user });
       say "Working on $user";
       my $result = follow_twitter_user( $user );
       say $result->{'description'};
       push @results, $result;
    }
    return \@results;
}

sub follow_twitter_user {
    my $user = shift;
    my $result = $nt->create_friend({ screen_name => $user });
    return $result;
}
