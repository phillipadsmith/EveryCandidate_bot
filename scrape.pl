#!/usr/bin/env perl 

use strict;
use warnings;
use Modern::Perl '2013';

use Config::JFDI;
use Data::Dumper;
use Date::Parse;
use FindBin qw($Bin);
use Mojo::DOM;
use Mojo::UserAgent;
use Mango;
use Mango::BSON ':bson';

#TODO add GetOpt for flags

my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;

my $TORONTO_CA_VOTE      = 'http://app.toronto.ca/vote/';
my $START                = $TORONTO_CA_VOTE . 'campaign.do';
my $CANDIDATES_BY_OFFICE = $TORONTO_CA_VOTE
    . 'searchCandidateByOfficeType.do?criteria.officeType=2';
my $CANDIDATE_DETAIL         = $TORONTO_CA_VOTE . 'candidateInfo.do?id=';
my $TABLE_ACTIVE_CSS_PATH    = '#activeTable';
my $TABLE_WITHDRAWN_CSS_PATH = '#withdrawnTable';
my $DIV_FB;
my $DIV_TWIT;

my $ua = Mojo::UserAgent->new;

main();

sub main {

    my @candidates_active    = _scrape_candidate_data( 'active' );
    my @candidates_withdrawn = _scrape_candidate_data( 'withdrawn' );
    my @oids                 = _store_candidate_data( \@candidates_active,
        \@candidates_withdrawn );
    #say Dumper( @oids ); #TODO debug flag
}

sub _scrape_candidate_data {
    my $type = shift;    #TODO only scrape for type
    my $page_start_for_session_id = $ua->get( $START => { DNT => 1 } );
    my $page_candidates
        = $ua->get( $CANDIDATES_BY_OFFICE => { DNT => 1 } )->res->body;

    my $dom               = Mojo::DOM->new( $page_candidates );
    my @rows_active       = $dom->find( '#activeTable > tbody > tr' )->each;
    my @candidates_active = _extract_active_candidate_data( \@rows_active );
    @candidates_active
        = sort { fc( $a->{'name_last'} ) cmp fc( $b->{'name_last'} ) }
        @candidates_active;

    my @rows_withdrawn = $dom->find( '#withdrawnTable > tbody > tr' )->each;
    my @candidates_withdrawn
        = _extract_withdrawn_candidate_data( \@rows_withdrawn );
    @candidates_withdrawn
        = sort { fc( $a->{'name_last'} ) cmp fc( $b->{'name_last'} ) }
        @candidates_withdrawn;
    $type eq 'active'
        ? return @candidates_active
        : return @candidates_withdrawn;
}

sub _extract_active_candidate_data {
    my $rows = shift;
    my @candidates;
    for my $row ( @$rows ) {
        my $name = $row->td->[0]->a->text;
        my $candidate_id
            = _extract_candidate_id( $row->td->[0]->{'onclick'} );
        #say "Scraping $candidate_id ..."; #TODO debug flag
        my %candidate = (
            candidate_id => $candidate_id,
            name_first   => _extract_name( 'first', $name ),
            name_last    => _extract_name( 'last', $name ),
            ward         => $row->td->[1]->text,
            nomination_date =>
                bson_time( _extract_date( $row->td->[2]->text ) * 1000 ),
            email     => $row->td->[3]->a->text,
            phone     => $row->td->[4]->text,
            web       => $row->td->[5]->a->text,
            processed => 1,
            added     => bson_time( time * 1000 ),
        );
        push @candidates, \%candidate;
    }
    return @candidates;
}

sub _extract_candidate_id {
    my $string = shift;
    $string =~ m/(?<id>\d{4})/;
    my $id = $+{'id'};
    return $id;
}

sub _extract_candidate_social_data {
    my $type         = shift;    #TODO only extract for type
    my $candidate_id = shift;
    my $url = $CANDIDATE_DETAIL . $candidate_id;
    my $page_candidate
        = $ua->get( $CANDIDATE_DETAIL . $candidate_id => { DNT => 1 } )
        ->res->body;
    my $dom      = Mojo::DOM->new( $page_candidate );
    my $fb_link  = $dom->at( '.fb a' );
    my $tw_link  = $dom->at( '.twit a' );
    my $facebook = $fb_link ? $fb_link->attr( 'href' ) : '';
    my $twitter  = $tw_link ? $tw_link->text : '';
    $type eq 'facebook' ? return $facebook : return $twitter;
}

sub _extract_withdrawn_candidate_data {
    my $rows = shift;
    my @candidates;
    for my $row ( @$rows ) {
        my $name      = $row->td->[0]->a->text;
        my %candidate = (
            name_first => _extract_name( 'first', $name ),
            name_last  => _extract_name( 'last',  $name ),
            ward       => $row->td->[1]->text,
            withdrawn_date =>
                bson_time( _extract_date( $row->td->[2]->text ) * 1000 ),
            processed => 1,
        );
        push @candidates, \%candidate;
    }
    return @candidates;
}

sub _extract_name {
    my $part_of_name = shift;    # First, or Last
    my $string       = shift;
    my ( $last, $first ) = split( ', ', $string );
    $part_of_name eq 'first' ? return $first : return $last;
}

sub _extract_date {
    my $date_str = shift;
    my $time     = str2time( $date_str );
    return $time;
}

sub _store_candidate_data {      #TODO get rid of duplication here
    my $candidates_active    = shift;
    my $candidates_withdrawn = shift;
    #say Dumper( $candidates_active, $candidates_withdrawn ); #TODO debug flag

    my $mango
        = Mango->new( 'mongodb://'
            . $conf->{'mongo_user'} . ':'
            . $conf->{'mongo_pw'} . '@'
            . $conf->{'mongo_host'} . ':'
            . $conf->{'mongo_port'} . '/'
            . $conf->{'mongo_db'} );
    my @oids;

    for my $candidate_active ( @$candidates_active ) {

        # Only checks that a record exists, not that it's identical #TODO fix on date
        my $record = $mango->db->collection( 'active' )->find_one(
            {   name_first => $candidate_active->{'name_first'},
                name_last  => $candidate_active->{'name_last'},
                ward       => $candidate_active->{'ward'},
                nomination_date => $candidate_active->{'nomination_date'},
            }
        );
        say "Already have $record->{'name_last'}" if $record; #TODO debug flag
        next if $record;

        # Better to grab the social data here to avoid unnecessary requests
        $candidate_active->{'facebook'}
            = _extract_candidate_social_data( 'facebook',
            $candidate_active->{'candidate_id'} );
        $candidate_active->{'twitter'}
            = _extract_candidate_social_data( 'twitter',
            $candidate_active->{'candidate_id'} );
        my $oid
            = $mango->db->collection( 'active' )->insert( $candidate_active );
        say "Inserting $candidate_active->{'name_last'}"; #TODO debug flag
        push @oids, $oid;
    }

    for my $candidate_withdrawn ( @$candidates_withdrawn ) {

        # Only checks that a record exists, not that it's identical #TODO fix on date
        my $record = $mango->db->collection( 'withdrawn' )->find_one(
            {   name_first => $candidate_withdrawn->{'name_first'},
                name_last  => $candidate_withdrawn->{'name_last'},
                ward       => $candidate_withdrawn->{'ward'},
                withdrawn_date => $candidate_withdrawn->{'withdrawn_date'},
            }
        );
        say "Already have $record->{'name_last'}" if $record; #TODO debug flag
        next if $record;
        my $oid
            = $mango->db->collection( 'withdrawn' )
            ->insert( $candidate_withdrawn );
        say "Inserting $candidate_withdrawn->{'name_last'}"; #TODO debug flag
        push @oids, $oid;
    }
    return @oids;
}
