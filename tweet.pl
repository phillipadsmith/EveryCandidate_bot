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

my $nt; 

if ( $query_results )  { # Only if needed
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
    my $epoch    = $doc->{'nomination_date'} / 1000;
    my $doc_copy = {%$doc};
    my $date     = DateTime->from_epoch(
        epoch     => $epoch,
        time_zone => 'America/New_York'
    );

    #TODO make templates for the various updates
    my $status_update
        = $doc->{'name_first'} . ' '
        . $doc->{'name_last'}
        . ' was nominated to run in #ward'
        . $doc->{'ward'} . ' on '
        . $date->month_abbr . ' '
        . $date->day
        . $suffix[ $date->day ] . ' '
        . $date->year . '. '
        . 'Got tips? Send them our way. #TOpoli #TOcouncil';
    say $status_update;
    my $result = $nt->update( $status_update );
    $doc_copy->{'twitter_update'} = $result;
    $collection->update( $doc, $doc_copy );
}
