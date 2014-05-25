#!/usr/bin/env perl 

use strict;
use warnings;
use Modern::Perl '2013';

use Config::JFDI;
use Data::Dumper;
use DateTime;
use Date::Parse;
use FindBin qw($Bin);
use Mojo::DOM;
use Mojo::UserAgent;
use Mango;
use Mango::BSON ':bson';
use Mojo::Template;
use Mojo::Loader;
use Net::Twitter::Lite::WithAPIv1_1;
use Scalar::Util 'blessed';

#TODO add GetOpt for flags

my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;

my $dt = DateTime->now( time_zone => 'America/New_York' );

my $mango
    = Mango->new( 'mongodb://'
        . $conf->{'mongo_user'} . ':'
        . $conf->{'mongo_pw'} . '@'
        . $conf->{'mongo_host'} . ':'
        . $conf->{'mongo_port'} . '/'
        . $conf->{'mongo_db'} );

my $collection = $mango->db->collection( 'alerts' );
my $query = $collection->find( { twitter_update => { '$exists' => undef } } );
my $query_results = $query->all;

my $nt;    # Variable for the Net::Twitter object

if ( $query_results ) {    # Only if needed
    $nt = Net::Twitter::Lite::WithAPIv1_1->new(
        consumer_key        => $conf->{'tw_con_key'},
        consumer_secret     => $conf->{'tw_con_secret'},
        access_token        => $conf->{'tw_access_tok'},
        access_token_secret => $conf->{'tw_access_key'},
        ssl                 => 1,
    );
}

my @suffix = (
    "-",  "st", "nd", "rd", "th", "th", "th", "th", "th", "th", "th", "th",
    "th", "th", "th", "th", "th", "th", "th", "th", "th", "st", "nd", "rd",
    "th", "th", "th", "th", "th", "th", "th", "st"
);

for my $doc ( @$query_results ) {
    my $event_date;
    if ( $doc->{'nomination_date'} ) {
        $event_date = $doc->{'nomination_date'};
    }
    else {
        $event_date = $doc->{'withdrawn_date'};
    }
    my $epoch = $event_date / 1000;
    my $type; # Entered or exited
    if ( $doc->{'nomination_date'} ) {
        $type = 'entered';
    }
    else {
        $type = 'exited';
    }
    my $doc_copy = { %$doc }; # Make a copy for the update
    my $date     = DateTime->from_epoch(
        epoch     => $epoch,
        time_zone => 'America/New_York'
    );
    my $status_update = Mojo::Template->new->render(
        Mojo::Loader->new->data( __PACKAGE__, $type ), ( $doc, $date, \@suffix ) );
    say $status_update; # TODO If debug
    my $result = $nt->update( $status_update );
    $doc_copy->{'twitter_update'} = $result;
    $collection->update( $doc, $doc_copy );
}

__DATA__
@@ entered
% my ($doc, $date, $suffix ) = @_;
<%= $doc->{'name_first'} %> <%= $doc->{'name_last'} %> was nominated to run in #Ward<%= $doc->{'ward'} %> on <%= $date->month_abbr %> <%= $date->day %><%= $suffix->[ $date->day ] %>. Got tips? Send them our way. #TOpoli #TOcouncil

@@ exited
% my ($doc, $date, $suffix ) = @_;
<%= $doc->{'name_first'} %> <%= $doc->{'name_last'} %> withdrew from the race in #Ward<%= $doc->{'ward'} %> on <%= $date->month_abbr %> <%= $date->day %><%= $suffix->[ $date->day ] %>. Got tips? Send them our way. #TOpoli #TOcouncil
