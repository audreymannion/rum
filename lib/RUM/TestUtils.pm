package RUM::TestUtils;

use strict;
no warnings;

=head1 NAME

RUM::TestUtils - Functions used by tests

=head1 SYNOPSIS

  use RUM::TestUtils qw(:all);

  # Download a file, unless the file already exists locally
  download_file("http://foo.com/bar.tab", "/some/path/bar.tab");

  # Make sure there are no diffs between two files
  no_diffs("got.tab", "expected.tab", "I got what I expected");

=head1 DESCRIPTION

=head1 Subroutines

=over 4

=cut

use Carp;
use Test::More;
use Exporter qw(import);
use File::Spec;
use FindBin qw($Bin);
use File::Temp;

use RUM::FileIterator qw(file_iterator);
use RUM::Sort qw(by_chromosome);
use RUM::Common qw(shell is_on_cluster);
use RUM::Repository qw(download);

our @EXPORT = qw(temp_filename no_diffs $INPUT_DIR $EXPECTED_DIR
                 $INDEX_CONFIG $SHARED_INPUT_DIR is_sorted_by_location same_line_count
                 $RUM_HOME);
our @EXPORT_OK = qw(download_file download_test_data no_diffs
                    is_sorted_by_location);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK]);

FindBin->again();

our $PROGRAM_NAME = do {
    local $_ = $0;
    s/^.*\///;
    s/\..*$//;
    s/^\d\d-//;
    $_;
};


# Build some paths that tests might need
our $RUM_HOME = $Bin;
$RUM_HOME =~ s/\/t(\/integration)?(\/)?$//;
our $RUM_BIN      = "$RUM_HOME/bin";
our $RUM_CONF     = "$RUM_HOME/conf";
our $RUM_INDEXES  = "$RUM_HOME/conf";
our $INDEX_CONFIG = "$RUM_CONF/rum.config_Arabidopsis";
our $GENOME_FA    = "$RUM_INDEXES/Arabidopsis_thaliana_TAIR10_genome_one-line-seqs.fa";
our $GENE_INFO    = "$RUM_INDEXES/Arabidopsis_thaliana_TAIR10_ensembl_gene_info.txt";
our $SHARED_INPUT_DIR = "$RUM_HOME/t/data/shared";
our $INPUT_DIR = "$RUM_HOME/t/data/$PROGRAM_NAME";
our $EXPECTED_DIR = "$RUM_HOME/t/expected/$PROGRAM_NAME";
our $TEST_DATA_URL = "http://pgfi.rum.s3.amazonaws.com/rum-test-data.tar.gz";

=item download_file URL, LOCAL

Download URL and save it with the given LOCAL filename, unless LOCAL
already exists or $DRY_RUN is set.

=cut

sub download_file {
    my ($url, $local) = @_;
    if (-e $local) {
        diag "$local exists, skipping";
        return;
    }

    diag "Download $url to $local";
    my (undef, $dir, undef) = File::Spec->splitpath($local);
    make_paths($dir);
    download($url, $local);
}

=item download_test_data

Download the test data tarball and unpack it, unless it already
exists or $DRY_RUN is set.

=cut

sub download_test_data {
    my ($local_file) = @_;
    diag "Making sure test data is downloaded to $local_file";

    download_file($TEST_DATA_URL, $local_file);

    # Get a list of the files in the tarball
    my $tar_out = `tar ztf $local_file`;
    croak "Error running tar: $!" if $?;
    my @files = split /\n/, $tar_out;

    # Get the absolute paths that the files should have when we unzip
    # the tarball.
    my (undef, $dir, undef) = File::Spec->splitpath($local_file);
    @files = map { "$dir/$_" } @files;

    # If all of the files already exist, don't do anything
    my @missing = grep { not -e } @files;
    if (@missing) {   
        diag "Unpack test tarball";
        shell("tar", "-zxvf", $local_file, "-C", $dir);
    }
    else {
        diag "All files exist; not unzipping";
    }
}

=item no_diffs(FILE1, FILE2, NAME)

Uses Test::More to assert that there are no differences between the
two files.

=cut

sub no_diffs {
    my ($file1, $file2, $name) = @_;
    my $diffs = `diff $file2 $file1 > /dev/null`;
    my $status = $? >> 8;
    ok($status == 0, $name);
}

=item line_count($filename)

Returns the number of lines in $filename.

=cut

sub line_count {
    my ($filename) = @_;
    open my $in, "<", $filename or die "Can't open $filename for reading: $!";
    my $count = 0;
    while (defined(<$in>)) {
        $count++;
    }
    return $count;
}

=item same_line_count(FILE1, FILE2, NAME)

Uses Test::More to assert that the two files have the same number of
lines.

=cut

sub same_line_count {
    my ($file1, $file2, $name) = @_;
    is(line_count($file1), line_count($file2), $name);
}

=item is_sorted_by_location(FILENAME)

Asserts that the given RUM file is sorted by location.

=cut

sub is_sorted_by_location {
    my ($filename) = @_;
    open my $in, "<", $filename or croak "Can't open $filename for reading: $!";
    my $it = file_iterator($in);

    my @recs;
    my @keys = qw(chr start end);
    while (my $rec = $it->("pop")) {
        my %rec;
        @rec{@keys} = @$rec{@keys};
        push @recs, \%rec;
    }

    my @sorted = sort {
        by_chromosome($a->{chr}, $b->{chr}) || $a->{start} <=> $b->{start} || $a->{end} <=> $b->{end};
    } @recs;

    is_deeply(\@recs, \@sorted, "Sorted by location");
}

=item temp_filename(%options)

Return a temporary filename using File::Temp with some sensible
defaults for a test script. 

=over 4

=item B<DIR>

The directory to store the temp file. Defaults to $Bin/tmp.

=item B<UNLINK>

Whether to unlink the file upon exit. Defaults to 1.

=item B<TEMPLATE>

The template for the filename. Defaults to a template that includes
the name of the calling function.

=back

=cut

sub temp_filename {
    my (%options) = @_;
    mkdir "$Bin/tmp";
    $options{DIR}      = "$Bin/tmp" unless exists $options{DIR};
    $options{UNLINK}   = 1        unless exists $options{UNLINK};
    $options{TEMPLATE} = "XXXXXX" unless exists $options{TEMPLATE};
    File::Temp->new(%options);
}

=item make_paths RUN_NAME

Recursively make all the paths required for the given test run name,
unless $DRY_RUN is set.

=cut

sub make_paths {
    my (@paths) = @_;

    for my $path (@paths) {
        
        if (-e $path) {
            diag "$path exists; not creating it";
        }
        else {
            print "mkdir -p $path\n";
            mkpath($path) or die "Can't make path $path: $!";
        }

    }
}




=back

=head1 AUTHOR

Mike DeLaurentis (delaurentis@gmail.com)

=head1 COPYRIGHT

Copyright University of Pennsylvania, 2012

=cut
