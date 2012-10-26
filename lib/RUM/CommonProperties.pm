package RUM::CommonProperties;

use strict;
use warnings;

sub read_type {
    return RUM::Property->new(
        opt => 'type=s',
        desc => 'Whether the input contains single or paired reads',
        required => 1,
        choices => ['single', 'paired']
    );
}

sub max_pair_dist {
    return RUM::Property->new(
        opt => 'max-pair-dist=s',
        desc => 'Maximum distance between paired reads',
        default =>  500000);
}

sub genome_size {
    return RUM::Property->new(
        opt => 'genome-size=s',
        desc => 'Size of the genome',
        check => \&check_int_gte_1);
}

sub genome {
    return RUM::Property->new(
        opt => 'genome=s',
        desc => 'Genome FASTA input file');
}

sub check_int_gte_1 {
    my ($props, $prop, $val) = @_;
    if (defined($val)) {
        if ($val !~ /^\d+$/ ||
            int($val) < 1) {
            $props->errors->add($prop->options . " must be an integer greater than 1");
        }
    }
}

sub check_int_gte_0 {
    my ($props, $prop, $val) = @_;
    if (defined($val)) {
        if ($val !~ /^\d+$/ ||
            int($val) < 0) {
            $props->errors->add($prop->options . " must be an integer greater than 0");
        }
    }
}


sub unique_in {
    return RUM::Property->new(
        opt => 'unique-in=s',
        desc => 'RUM_Unique input file',
    );
}

sub non_unique_in {
    return RUM::Property->new(
        opt => 'non-unique-in=s',
        desc => 'RUM_NU input file',
    );
}

sub unique_out {
    return RUM::Property->new(
        opt => 'unique-out=s',
        desc => 'RUM_Unique output file',
    );
}

sub non_unique_out {
    return RUM::Property->new(
        opt => 'non-unique-out=s',
        desc => 'RUM_NU output file',
    );
}

sub match_length_cutoff {
    return RUM::Property->new(
        opt => 'match-length-cutoff=s',
        desc => 'The minimum match length to report',
        check => \&check_int_gte_0,
        default => 0);
}

sub faok {
    return RUM::Property->new(
        opt => 'faok',
        desc => 'Indicate that the FASTA file already has each sequence on one line');
}


1;
