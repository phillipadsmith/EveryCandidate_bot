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

my $mango
    = Mango->new( 'mongodb://'
        . $conf->{'mongo_user'} . ':'
        . $conf->{'mongo_pw'} . '@'
        . $conf->{'mongo_host'} . ':'
        . $conf->{'mongo_port'} . '/'
        . $conf->{'mongo_db'} );

main();

sub main {
    my $collection = $mango->db->collection( 'active' );
    my $service = Net::Google::Spreadsheets->new(
        username => $conf->{'google_user'},
        password => $conf->{'google_pass'},
    );
    my $active     = get_active_candidates( $collection );
    my $worksheet = add_columns_to_worksheet($active, $service);
    add_candidates_to_google( $active, $worksheet );
}

sub get_active_candidates {
    my $collection    = shift;
    my $query         = $collection->find( {} );
    my $query_results = $query->all;
    say Dumper( $query_results ) if $opt->debug;
    return $query_results;
}

sub add_columns_to_worksheet {
    my $candidates = shift;
    my $service = shift;
    my $spreadsheet
        = $service->spreadsheet( { key => $conf->{'google_sheet_key'} } );
    #find a worksheet by title
    my $worksheet = $spreadsheet->worksheet(
        { title => $conf->{'google_worksheet_title'} } );
    my @columns;
    for my $candidate ( @$candidates ) {
        # Add the keys to an array
        delete $candidate->{'_id'};
        delete $candidate->{'added'};
        delete $candidate->{'processed'};
        $candidate->{'nomination_date_nice'} = '';
        push @columns, keys %$candidate;
    } 
    my %seen = ();
     @columns = grep { ! $seen{$_}++ } @columns;
    # create a worksheet
    my @cells_to_add;
    my $col;
    for my $column ( sort @columns ) {
        $column = lc($column);
        push @cells_to_add, { row => 1, col => $col++, input_value => $column };
    }
    $worksheet->batchupdate_cell(
        @cells_to_add
    );
    return $worksheet;
}

sub add_candidates_to_google {
    my $candidates = shift;
    my $worksheet = shift;
    for my $candidate ( @$candidates ) {
        add_candidate_to_google( $candidate, $worksheet );
    }
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
    $candidate->{'nomination_date'} = $dt->datetime() . 'Z',   #'2014-07-20T05:00:00Z'
    $candidate->{'nomination_date_nice'} = $dt->month_name . ' ' . $dt->day . ' ' . $dt->year;
    my $doc;
    for my $key ( keys %$candidate ) {
        my $slug = lc( $key );
        $slug =~ s/\W//g;
        $slug =~ s/_//g;
        $slug =~ s/-//g;
        $doc->{ $slug } = $candidate->{ $key };
    }
    my $new_row = $worksheet->add_row( $doc );
    if ( $new_row ) {
        my $candidate_id = $new_row->param('candidateid');
        say "Added candidate $candidate_id to Google Sheet";
    }
}
