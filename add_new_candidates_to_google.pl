#!/usr/bin/env perl 

use strict;
use warnings;
use feature 'say';

use Config::JFDI;
use Data::Dumper;
use DateTime;
use FindBin qw($Bin);
use Getopt::Long::Descriptive;
use Mango;
use Mango::BSON ':bson';
use Net::Google::Spreadsheets;
use List::Compare;

my ( $opt, $usage )
    = describe_options( '%c %o',
    [ 'debug|d', "don't actually do anything, but be verbose" ],
    );
say "Not doing anything because the debug flag is set..." if $opt->debug;

my $config
    = Config::JFDI->new( name => "everycandidate_bot", path => "$Bin" );
my $conf = $config->get;
say Dumper( $conf ) if $opt->debug;

main();

sub main {
    my $mango
        = Mango->new( 'mongodb://'
            . $conf->{'mongo_user'} . ':'
            . $conf->{'mongo_pw'} . '@'
            . $conf->{'mongo_host'} . ':'
            . $conf->{'mongo_port'} . '/'
            . $conf->{'mongo_db'} );

    my $collection = $mango->db->collection( 'active' );
    my $service = Net::Google::Spreadsheets->new(
        username => $conf->{'google_user'},
        password => $conf->{'google_pass'},
    );

    my $active     = get_active_candidates( $collection );
    my $mongo_ids  = get_candidate_ids_from_mongo( $active, $collection );
    my $worksheet  = get_worksheet_from_google( $service );
    my $google_ids = get_candidate_ids_from_google( $worksheet );
    my $missing    = list_ids_not_on_google( $mongo_ids, $google_ids );
    add_missing_candidates_to_google( $missing, $worksheet, $collection );
}

sub get_active_candidates {
    my $collection    = shift;
    my $query         = $collection->find( {} );
    my $query_results = $query->all;
    say Dumper( $query_results ) if $opt->debug;
    return $query_results;
}

sub get_candidate_ids_from_mongo {
    my $active_records = shift;
    my @candidate_ids = map { $_->{'candidate_id'} } @$active_records;
    say Dumper( \@candidate_ids ) if $opt->debug;
    return \@candidate_ids;
}

sub get_worksheet_from_google {
    my $service = shift;

    # find a spreadsheet by title
    my $spreadsheet
        = $service->spreadsheet( { key => $conf->{'google_sheet_key'} } );

    #find a worksheet by title
    my $worksheet = $spreadsheet->worksheet(
        { title => $conf->{'google_worksheet_title'} } );
    return $worksheet;
}

sub get_candidate_ids_from_google {
    my $worksheet     = shift;
    my @rows          = $worksheet->rows;
    my @candidate_ids = map { $_->content->{'candidateid'} } @rows;
    say Dumper ( \@candidate_ids ) if $opt->debug;
    return \@candidate_ids;
}

sub list_ids_not_on_google {
    my $mongo  = shift;
    my $google = shift;
    my $lc     = List::Compare->new(
        {   lists       => [ $mongo, $google ],
            accelerated => 1,
        }
    );
    my @missing = $lc->get_unique;
    say Dumper( \@missing ) if $opt->debug;
    return \@missing;
}

sub add_missing_candidates_to_google {
    my $missing_ids = shift;
    my $worksheet   = shift;
    my $collection  = shift;
    for my $id ( @$missing_ids ) {
        say "Adding candidate $id to Google" if $opt->debug;
        my $candidate = get_candidate_by_id_from_master( $id, $collection );
        say Dumper( $candidate ) if $opt->debug;
        if ( $candidate ) {
            add_candidate_to_google( $candidate, $worksheet );
        }
        else {
            # log some error
        }
    }
}

sub get_candidate_by_id_from_master {
    my $candidate_id = shift;
    my $collection   = shift;
    my $candidate
        = $collection->find_one( { candidate_id => $candidate_id } );
    say Dumper( $candidate ) if $opt->debug;
    return $candidate;
}

sub add_candidate_to_google {
    my $candidate = shift;
    my $worksheet = shift;
    my $epoch
        = $candidate->{'nomination_date'} / 1000;    # From bson_time to epoch
    my $dt = DateTime->from_epoch(
        epoch     => $epoch,
        time_zone => 'America/New_York'
    );
    my $new_row = $worksheet->add_row(
        {
            #'linkedin' => 'linkedin',
            twitter     => $candidate->{'twitter'},
            ward        => $candidate->{'ward'},
            phone       => $candidate->{'phone'},
            web         => $candidate->{'web'},
            namelast    => $candidate->{'name_last'},
            emailcity   => $candidate->{'email'},
            candidateid => $candidate->{'candidate_id'},
            facebook    => $candidate->{'facebook'},
            namefirst   => $candidate->{'name_first'},
            nominationdate => $dt->datetime() . 'Z',   #'2014-07-20T05:00:00Z'
        }
    );
    if ( $new_row ) {
        my $candidate_id = $new_row->param('candidateid');
        say "Added candidate $candidate_id to Google Sheet";
    }
}
