#!/usr/bin/env perl 

use strict;
use warnings;
use utf8;
use feature 'say';

# Find modules installed w/ Carton
use FindBin;
use lib "$FindBin::Bin/local/lib/perl5";

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

my $collection_active    = $mango->db->collection( 'active' );
my $collection_withdrawn = $mango->db->collection( 'withdrawn' )->find->all;

for my $candidate ( @$collection_withdrawn ) {
    my $to_be_removed = $collection_active->find_one(
        {   name_first => $candidate->{'name_first'},
            name_last  => $candidate->{'name_last'},
            ward       => $candidate->{'ward'},
        }
    );
    if ( $to_be_removed ) {
        say "Removing: " . $to_be_removed->{'candidate_id'};
        $collection_active->remove( $to_be_removed->{'_id'} );
    }
}
