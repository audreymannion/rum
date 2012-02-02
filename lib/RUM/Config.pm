#!/usr/bin/env perl
# -*- cperl -*-

=head1 NAME

RUM::Config - Utilities for parsing and formatting Rum config file

=head1 SYNOPSIS

  use RUM::Config qw(parse_config
                     format_config
                     config_fields
                     config_defaults
                     parse_organisims);

  # Parse a config file
  open my $in, "<", "rum.config_zebrafish";
  my $config_hashref = parse_config($in);

  # Format a configuration
  my $config_text = format_config(
      "gene-annotation-file" => "foo.txt",
      "bowtie-bin" => "/usr/bin/bowtie",
      ... please see config_fields() for all field names
  );

  # Get list of field names
  for my $field (@config_fields) {
    ...
  }

  my $default_config_hashref = config_defaults();

  # Parse an organisms file
  my @orgs = parse_organisims("organisms.txt");
  for my $org (@orgs) {
    my $latin_name = $org->{latin};
    my $common = $org->{common};
    my $build = $org->{build};
    my @files = @{ $org->{files} };
    ...
  }

=head1 DESCRIPTION

This package provides utilities for parsing and formatting a Rum config file.

=head2 Subroutines

=over 4

=cut

package RUM::Config;

use strict;
use warnings;

use Getopt::Long;
use FindBin qw($Bin);
use Log::Log4perl qw(:easy);
use Carp;

use Exporter 'import';
our @EXPORT_OK = qw(config_fields 
                    config_defaults
                    parse_config
                    format_config
                    parse_organisms);

our @FIELDS = qw(gene-annotation-file
                 bowtie-bin
                 blat-bin
                 mdust-bin
                 bowtie-genome-index
                 bowtie-gene-index
                 blat-genome-index
                 script-dir
                 lib-dir);

=item parse_config IN

IN must be a filehandle pointing to a file that contains one line per
field. Read in the lines and return a hash ref representing the
configuration.

=cut
sub parse_config {
    my ($in) = @_;

    my @fields = @FIELDS;
    my %config;

    while (defined(local $_ = <$in>)) {
        chomp;
        my $field = shift(@fields) 
            or croak "Too many lines in config file";
        $config{$field} = $_;
    }
    
    die "Not enough lines in config file" if @fields;
    return \%config;
}

=item format_config CONFIG

Config must be a hash with @FIELDS as its keys. Return a string
representing the corresponding config file.

=cut

sub format_config {
    my %config = @_;

    # Check for missing fields and log a warning
    my @missing = _missing_fields(%config);
    WARN "Missing these config fields: ". join(", ", @missing)
        if @missing;
            
    # Make sure are fields are defined
    my @values = map($_ || "", @config{@FIELDS});

    return join("", map("$_\n", @values));
}

=item config_defaults

Return a hashref containing sensible defaults for a configuration.

=cut

sub config_defaults {
    return {
        "bowtie-bin" => "bowtie",
        "blat-bin" => "blat",
        "mdust-bin" => "mdust",
        "script-dir" => "$Bin/../orig/scripts",
        "lib-dir"    => "$Bin/../orig/lib"
    };
}

=item config_fields

Return an array of the fields that should be in a configuration file.

=cut

sub config_fields {
    return @FIELDS;
}


=item parse_organisms IN

Parse the given organisms file and return a list of organisms, each
one as a hash ref with the following fields:

=over 4

=item latin

The latin name of the organism.

=item common

The common name of the organism.

=item build

The build identifier.

=item files

An array ref of the index files for this organism.

=back

=cut

sub _parse_organism {
    my ($in) = @_;
    my %org;
    
    # Matches lines like the following:
    #   -- Homo sapiens [build hg19] (human) start --
    #   -- Homo sapiens [build hg19] (human) end --
    my $re = qr{-- \s+
                (.*) \s+ 
                \[ build \s+ (.*)\] \s+
                \((.*)\) \s+
                (start|end) \s+
                --
           }x;

    my $started = 0;

    while (defined (local $_ = <$in>)) {
        chomp;

        if (my ($latin, $build, $common, $start_or_end) = /$re/g) {

            if ($start_or_end eq 'start') {
                $started = 1;
                $org{latin} = $latin;
                $org{build} = $build;
                $org{common} = $common;
                $org{files} = [];
            }
            
            # If we're at the end, add the org we just built up to the list
            if ($start_or_end eq 'end') {
                croak "Saw end tag before start tag" unless $started;
                return \%org;
            }
        }

        elsif ($started) {
            push @{ $org{files} }, $_;
        }
    }
    
    return;
    
}

sub parse_organisms {
    my ($in) = @_;
    my @orgs;

    while (my $org = _parse_organism($in)) {
        push @orgs, $org;
    }
    return @orgs;
}

=item _missing_fields

Given a config hash, return a list of fields that are missing from it.

=back

=head1 AUTHOR

Mike DeLaurentis (delaurentis@gmail.com)

=head1 COPYRIGHT

Copyright 2012, University of Pennsylvania

=cut

sub _missing_fields {
    my %config = @_;
   return grep { not $config{$_} } @FIELDS;
}


1;