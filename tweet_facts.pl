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

my $mango
    = Mango->new( 'mongodb://'
        . $conf->{'mongo_user'} . ':'
        . $conf->{'mongo_pw'} . '@'
        . $conf->{'mongo_host'} . ':'
        . $conf->{'mongo_port'} . '/'
        . $conf->{'mongo_db'} );

my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
    consumer_key        => $conf->{'tw_con_key'},
    consumer_secret     => $conf->{'tw_con_secret'},
    access_token        => $conf->{'tw_access_tok'},
    access_token_secret => $conf->{'tw_access_key'},
    ssl                 => 1,
);

#my @suffix = (
#"-",  "st", "nd", "rd", "th", "th", "th", "th", "th", "th", "th", "th",
#"th", "th", "th", "th", "th", "th", "th", "th", "th", "st", "nd", "rd",
#"th", "th", "th", "th", "th", "th", "th", "st"
#);

my $active_candidates = $mango->db->collection( 'active' )->find->all;
my $dt = DateTime->now( time_zone => 'America/New_York' );
my $nom_close_date = DateTime->new(
    time_zone => 'America/New_York',
    year      => 2014,
    month     => 9,
    day       => 12,
    hour      => 9,
    minute    => 00,
    second    => 00,
);
my $to_go = $nom_close_date->subtract_datetime( $dt );
my $days  = $to_go->days();
my $hours = $to_go->hours();
my $mins  = $to_go->minutes();

my $data = {
    active_candidates => scalar @$active_candidates,
    days        => ( $days >= 2 ) ? "$days days" : "$days day",
    hours       => ( $hours >= 2 ) ? "$hours hours" : "$hours hour",
    minutes     => ( $mins >= 2 ) ? "$mins minutes" : "$mins minute",
};

if ( $nom_close_date > $dt ) { 
    my $loader     = Mojo::Loader->new;
    my $template   = $loader->data( __PACKAGE__, 'candidate_count' );
    my $mt         = Mojo::Template->new;
    my $status_update = $mt->render( $template, $data );
    say $status_update if $opt->debug;
    unless ( $opt->debug ) {    # Don't do anything if we're debugging
        my $result = $nt->update( $status_update );
        #say Dumper( $result );
    }
}

__DATA__
@@ candidate_count
% my ($data ) = @_;
<%= $data->{'active_candidates'} %> candidates registered to run for city council. Just <%= $data->{'days'} %>, <%= $data->{'hours'} %>, and <%= $data->{'minutes'} %> to go until nominations close. #TOpoli #TOcouncil
