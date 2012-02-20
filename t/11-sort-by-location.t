#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use RUM::Workflow qw(make_paths report);
use RUM::TestUtils qw(:all);

our $ROOT = "$Bin/../_testing";
our $TEST_DATA_TARBALL   = "$ROOT/rum-test-data.tar.gz";
our $OUT_DIR = "$ROOT/11-sort-by-location";
our $IN_DIR = "$ROOT/rum-test-data/sort-by-location/";
download_test_data($TEST_DATA_TARBALL);
make_paths($OUT_DIR);

our $SCRIPT = "$Bin/../orig/scripts/sort_by_location.pl";

{
    my $in = "$IN_DIR/junctions_all.bed";
    my $out = "$OUT_DIR/all_bed";
    my $expected = "$IN_DIR/junctions_all.bed";
    my @args = ("-location_columns", "1,2,3", "-skip", "1");
    system "perl", $SCRIPT, $in, $out, @args;
    no_diffs $out, $expected, "sort-by-location-all-bed"
}

{
    my $in = "$IN_DIR/junctions_high-quality.bed";
    my $out = "$OUT_DIR/high-quality_bed";
    my $expected = "$IN_DIR/junctions_high-quality.bed";
    my @args = ("-location_columns", "1,2,3", "-skip", "1");
    system "perl", $SCRIPT, $in, $out, @args;
    no_diffs $out, $expected, "sort-by-location-high-quality-bed"
}



{
    my $in = "$IN_DIR/junctions_all.rum";
    my $out = "$OUT_DIR/all_rum";
    my $expected = "$IN_DIR/junctions_all.rum";
    my @args = ("-location_column", "1", "-skip", "1");
    system "perl", $SCRIPT, $in, $out, @args;
    no_diffs $out, $expected, "sort-by-location-all-rum"
}


