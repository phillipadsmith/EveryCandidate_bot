#!/usr/bin/env perl

use strict;
use warnings;
use Modern::Perl '2013';

use Config::JFDI;
use Data::Dumper;
use DateTime;
use Date::Parse;
use FindBin qw($Bin);
use Getopt::Long::Descriptive;
use Mojo::DOM;
use Mojo::UserAgent;
use Mango;
use Mango::BSON ':bson';
use Mojo::Template;
use Mojo::Loader;
use Net::Twitter::Lite::WithAPIv1_1;
use Scalar::Util 'blessed';

my ( $opt, $usage )
    = describe_options( '%c %o',
    [ 'debug|d', "don't actually do anything, but be verbose" ],
    );
say "Not doing anything because the debug flag is set..." if $opt->debug;

my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;
say Dumper( $conf ) if $opt->debug;

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
say Dumper( $query_results ) if $opt->debug;

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
    say Dumper( $doc ) if $opt->debug;
    my $event_date;
    if ( $doc->{'nomination_date'} ) {
        $event_date = $doc->{'nomination_date'};
    }
    else {
        $event_date = $doc->{'withdrawn_date'};
    }
    my $epoch = $event_date / 1000;
    my $type;    # Entered or exited
    if ( $doc->{'nomination_date'} ) {
        $type = 'entered';
    }
    else {
        $type = 'exited';
    }
    say $type if $opt->debug;
    my $doc_copy = {%$doc};                # Make a copy for the update
    my $date     = DateTime->from_epoch(
        epoch     => $epoch,
        time_zone => 'America/New_York'
    );
    my $status_update
        = Mojo::Template->new->render(
        Mojo::Loader->new->data( __PACKAGE__, $type ),
        ( $doc, $date, \@suffix ) );
    say $status_update if $opt->debug;
    unless ( $opt->debug ) {    # Don't do anything if we're debugging
        my $result = $nt->update( $status_update );
        $doc_copy->{'twitter_update'} = $result;
        $collection->update( $doc, $doc_copy );
    }
}

__DATA__
@@ entered
% my ($doc, $date, $suffix ) = @_;
<%= $doc->{'name_first'} %> <%= $doc->{'name_last'} %> has registered to run in #Ward<%= $doc->{'ward'} %> on <%= $date->month_abbr %> <%= $date->day %><%= $suffix->[ $date->day ] %>. Got tips? Send them our way. #TOpoli #TOcouncil

@@ exited
% my ($doc, $date, $suffix ) = @_;
<%= $doc->{'name_first'} %> <%= $doc->{'name_last'} %> withdrew from the race in #Ward<%= $doc->{'ward'} %> on <%= $date->month_abbr %> <%= $date->day %><%= $suffix->[ $date->day ] %>. Got tips? Send them our way. #TOpoli #TOcouncil
