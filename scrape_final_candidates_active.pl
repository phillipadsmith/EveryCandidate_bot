#!/usr/bin/env perl 

use strict;
use warnings;
use feature 'say';

# Find modules installed w/ Carton
use FindBin;
use lib "$FindBin::Bin/local/lib/perl5";

use Config::JFDI;
use Data::Dumper;
use Date::Parse;
use FindBin qw($Bin);
use Mojo::DOM;
use Mojo::UserAgent;
use Mango;
use Mango::BSON ':bson';


my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;

my $TORONTO_CA_VOTE      = 'http://app.toronto.ca/vote/';
my $START                = $TORONTO_CA_VOTE . 'campaign.do';
my $CANDIDATES_BY_OFFICE = $TORONTO_CA_VOTE
    . 'searchCandidateByOfficeType.do?criteria.officeType=2';
my $CANDIDATE_DETAIL         = $TORONTO_CA_VOTE . 'candidateInfo.do?id=';
my $TABLE_ACTIVE_CSS_PATH    = '#activeTable';
my $DIV_FB;
my $DIV_TWIT;

my $ua = Mojo::UserAgent->new;

main();

sub main {
    my @candidates_active    = _scrape_candidate_data();
    my @oids                 = _store_candidate_data( \@candidates_active );
}

sub _scrape_candidate_data {
    my $page_start_for_session_id = $ua->get( $START => { DNT => 1 } );
    my $page_candidates
        = $ua->get( $CANDIDATES_BY_OFFICE => { DNT => 1 } )->res->body;

    my $dom               = Mojo::DOM->new( $page_candidates );
    my @rows_active       = $dom->find( '#activeTable > tbody > tr' )->each;
    my @candidates_active = _extract_active_candidate_data( \@rows_active );
    @candidates_active
        = sort { lc( $a->{'name_last'} ) cmp lc( $b->{'name_last'} ) }
        @candidates_active;

    return @candidates_active;
}

sub _extract_active_candidate_data {
    my $rows = shift;
    my @candidates;
    for my $row ( @$rows ) {
        my $name = $row->td->[0]->a->text;
        my $candidate_id
            = _extract_candidate_id( $row->td->[0]->{'onclick'} );
        say "Scraping $candidate_id ..."; 
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
            processed => '',
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

sub _extract_candidate_extra_data {
    my $candidate_id = shift;
    my $url = $CANDIDATE_DETAIL . $candidate_id;
    my $page_candidate
        = $ua->get( $CANDIDATE_DETAIL . $candidate_id => { DNT => 1 } )
        ->res->body;
    my $dom      = Mojo::DOM->new( $page_candidate );
    my $fb_link  = $dom->at( '.fb a' );
    my $tw_link  = $dom->at( '.twit a' );
    my $address  = $dom->at( '.address' );
    my $facebook = $fb_link ? $fb_link->attr( 'href' ) : '';
    my $twitter  = $tw_link ? $tw_link->text : '';
    $address  = $address ? $address->text : '';
    my %candidate_other = (
        facebook => $facebook,
        twitter  => $twitter,
        address  => $address,
    );
    my $others   = $dom->find('.other');
    my $phones   = $dom->find('.phoneNum');
    for my $number ( $phones->each ) {
        $number->text =~ /^(.*): (.*)$/;
        $candidate_other{$1} = $2;
    }
    my @others;
    for my $other ( $others->each ) {
        $other->text =~ /^(.*): (.*)$/;
        push @others, $2; 
    }
    $candidate_other{'misc'} = join(', ', @others);
    return \%candidate_other;
}

sub _extract_name {
    my $part_of_name = shift;    # First, or Last
    my $string       = shift;
    my ( $last, $first ) = split( ', ', $string );
    $part_of_name eq 'first' ? return $first : return $last;
}

sub _extract_date {
    my $date_str = shift;
    my $time     = str2time( $date_str, 'EST' );
    return $time;
}

sub _store_candidate_data {      
    my $candidates_active    = shift;

    my $mango
        = Mango->new( 'mongodb://'
            . $conf->{'mongo_user'} . ':'
            . $conf->{'mongo_pw'} . '@'
            . $conf->{'mongo_host'} . ':'
            . $conf->{'mongo_port'} . '/'
            . $conf->{'mongo_db'} );
    my @oids;

    for my $candidate_active ( @$candidates_active ) {
        # Grab the extra data here, once we have the ID
        my $extra_data = _extract_candidate_extra_data( $candidate_active->{'candidate_id'} );
        for my $key ( keys %$extra_data ) {
            $candidate_active->{ $key } = $extra_data->{ $key };
        }
        my $oid
            = $mango->db->collection( 'active' )->insert( $candidate_active, upsert => 1 );
        say "Inserting $candidate_active->{'name_last'}, $candidate_active->{'name_first'}, Ward $candidate_active->{'ward'}";
        push @oids, $oid;
    }
    return @oids;
}
