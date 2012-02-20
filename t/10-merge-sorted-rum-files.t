#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use RUM::Workflow qw(make_paths report);
use RUM::TestUtils qw(:all);

our $ROOT = "$Bin/../_testing";
our $TEST_DATA_TARBALL   = "$ROOT/rum-test-data.tar.gz";
our $OUT_DIR = "$ROOT/10-merge-sorted-rum-files";
our $IN_DIR = "$ROOT/rum-test-data/merge-sorted-rum-files/";
download_test_data($TEST_DATA_TARBALL);
make_paths($OUT_DIR);
our $SCRIPT = "$Bin/../orig/scripts/merge_sorted_RUM_files.pl";

{
    my @in = map "$IN_DIR/RUM_Unique.sorted.$_", 1..2;
    my $out = "$OUT_DIR/unique";
    my $expected = "$IN_DIR/RUM_Unique.sorted";
    system "perl", $SCRIPT, $out, @in;
    no_diffs $out, $expected, "merge-sorted-rum-files-unique"
}


