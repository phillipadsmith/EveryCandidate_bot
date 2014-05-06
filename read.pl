#!/usr/bin/env perl 

use strict;
use warnings;
use Modern::Perl '2013';

use Config::JFDI;
use Data::Dumper;
use DateTime;
use FindBin qw($Bin);
use Mango;
use Mango::BSON ':bson';

#TODO add GetOpt for flags

my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;

my $mango
    = Mango->new( 'mongodb://'
        . $conf->{'mongo_user'} . ':'
        . $conf->{'mongo_pw'} . '@'
        . $conf->{'mongo_host'} . ':'
        . $conf->{'mongo_port'} . '/'
        . $conf->{'mongo_db'} );

my $dt_active = DateTime->today()->subtract( days => 1 );

my $collection_active     = $mango->db->collection( 'active' ); #TODO only reading active. Need withdrawn.
my $query_active          = $collection_active->find(
    { nomination_date => { '$gte' => bson_time( $dt_active->epoch * 1000 ) }, processed => { '$ne' => 1 } })->sort( bson_doc( nomination_date => -1 ) );
my $query_results_active = $query_active->all;

for my $doc ( @$query_results_active ) {
    #say Dumper( $doc );
    my $doc_copy = { %$doc };
    $doc_copy->{'processed'} = 1;
    $collection_active->update( $doc, $doc_copy );
    #TODO probably best to do an upsert, otherwise risk a duplicate key error
    # if there's bad data coming from the collection
    my $oid = $mango->db->collection( 'alerts' )->insert( $doc );
    say "Inserted $oid"; #TODO debug flag only
}

my $dt_withdrawn = DateTime->today()->subtract( days => 1 );

my $collection_withdrawn     = $mango->db->collection( 'withdrawn' ); 
my $query_withdrawn          = $collection_withdrawn->find(
    { withdrawn_date => { '$gte' => bson_time( $dt_withdrawn->epoch * 1000 ) }, processed => { '$ne' => 1 } })->sort( bson_doc( widthdrawn_date => -1 ) );
my $query_results_widthdrawn = $query_withdrawn->all;

for my $doc_w ( @$query_results_widthdrawn ) {
    #say Dumper( $doc );
    my $doc_copy = { %$doc_w };
    $doc_copy->{'processed'} = 1;
    $collection_withdrawn->update( $doc_w, $doc_copy );
    #TODO probably best to do an upsert, otherwise risk a duplicate key error
    # if there's bad data coming from the collection
    my $oid = $mango->db->collection( 'alerts' )->insert( $doc_w );
    say "Inserted $oid"; #TODO debug flag only
}


# Other useful queries
# my $all_results    = $collection->find;
# my $sorted_results = $all_results->sort( bson_doc( nomination_date => -1 ) );
# my $docs_all       = $sorted_results->all;
