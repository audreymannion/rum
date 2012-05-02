package RUM::Config;

use strict;
use warnings;

use Carp;
use FindBin qw($Bin);
use File::Spec;
use File::Path qw(mkpath);
use Data::Dumper;

use RUM::Logging;
use RUM::ConfigFile;

our $AUTOLOAD;
our $log = RUM::Logging->get_logger;
FindBin->again;

our $FILENAME = ".rum/job_settings";

=head1 NAME

RUM::Config - Configuration for a RUM job

=cut

our %DEFAULTS = (

    num_chunks => 1,
    ram => undef,
    genome_size => undef,
    ram_ok => 0,
    max_insertions => 1,
    strand_specific => 0,
    min_identity => 93,
    blat_min_identity => 93,
    blat_tile_size => 12,
    blat_step_size => 6,
    blat_rep_match => 256,
    blat_max_intron => 500000,

    name => undef,
    platform => "Local",

    output_dir => ".",
    rum_config_file => undef,
    reads => undef,
    user_quals => undef,
    alt_genes => undef,
    alt_quant_model => undef,

    dna => 0,
    forward => undef,
    paired_end => 0,
    bin_dir => undef,
    genome_bowtie => undef,
    genome_fa => undef,
    transcriptome_bowtie => undef,
    annotations => undef,
    read_length => undef,
    config_file => undef,
    bowtie_bin => undef,
    mdust_bin => undef,
    blat_bin => undef,
    trans_bowtie => undef,
    input_needs_splitting => undef,
    input_is_preformatted => undef,
    count_mismatches => undef,
    argv => undef,
    alt_quant => undef,
    genome_only => 0,
    blat_only => 0,
    cleanup => 1,
    junctions => 0,
    mapping_stats => undef,
    quantify => 0,
    novel_inferred_internal_exons_quantifications => 0,

    # Old defaults
    preserve_names        => 0,
    variable_length_reads => 0,
    min_length            => undef,
    max_insertions        => 1,
    limit_nu_cutoff       => undef,
    nu_limit              => undef,
    chunk                 => undef,
    bowtie_nu_limit       => undef
);

=head1 CONSTRUCTOR

=over 4

=item new(%options)

Create a new RUM::Config with the given options. %options can contain
mappings from the keys in %DEFAULTS to the values to use for those
keys.

=back

=cut

sub new {
    my ($class, %options) = @_;
    my %data = %DEFAULTS;
    
    for (keys %DEFAULTS) {
        if (exists $options{$_}) {
            $data{$_} = delete $options{$_};
        }
    }
    
    if (my @extra = keys(%options)) {
        croak "Extra arguments to Config->new: @extra";
    }

    return bless \%data, $class;
}

=head1 CLASS METHODS

=over 4

=item load_rum_config_file

Load the settings from the rum index configuration file I am
configured with. This allows you to call annotations, bowtie_bin,
blat_bin, mdust_bin, genome_bowtie, trans_bowtie, and genome_fa on me
rather than loading the config object yourself.

=cut

sub load_rum_config_file {
    my ($self) = @_;
    my $path = $self->rum_config_file or croak
        "No RUM config file was supplied";
    open my $in, "<", $path or croak "Can't open config file $path: $!";
    my $cf = RUM::ConfigFile->parse($in);
    $cf->make_absolute;
    my %data;
    $data{annotations}   = $cf->gene_annotation_file;
    $data{bowtie_bin}    = $cf->bowtie_bin;
    $data{blat_bin}      = $cf->blat_bin;
    $data{mdust_bin}     = $cf->mdust_bin;
    $data{genome_bowtie} = $cf->bowtie_genome_index;
    $data{trans_bowtie}  = $cf->bowtie_gene_index;
    $data{genome_fa}     = $cf->blat_genome_index;

    -e $data{annotations} || $self->dna or die
        "the file '$data{annotations}' does not seem to exist.";         

    -e $data{bowtie_bin} or die
        "the executable '$data{bowtie_bin}' does not seem to exist.";

    -e $data{blat_bin} or die
        "the executable '$data{blat_bin}' does not seem to exist.";

    -e $data{mdust_bin} or die
        "the executable '$data{mdust_bin}' does not seem to exist.";        

    -e $data{genome_fa} or die
        "the file '$data{genome_fa}' does not seem to exist.";
    
    local $_;
    for (keys %data) {
        $self->set($_, $data{$_});
    }
    
}

=item script($name)

Return the path to the rum script of the given name.

=cut

sub script {
    return File::Spec->catfile("$Bin/../bin", $_[1]);
}

# Utilities for modifying a filename

sub in_output_dir {
    my ($self, $file) = @_;
    my $dir = $self->output_dir;
    return $dir ? File::Spec->catfile($dir, $file) : $file;
}

sub postproc_dir {
    my ($self, $file) = @_;
    return File::Spec->catfile($self->output_dir, "postproc");
}

sub in_postproc_dir {
    my ($self, $file) = @_;
    my $dir = $self->postproc_dir;
    mkpath $dir;
    return File::Spec->catfile($dir, $file);
}

# These functions return options that the user can control.

sub opt {
    my ($self, $opt, $arg) = @_;
    return defined($arg) ? ($opt, $arg) : "";
}

sub read_length_opt         { $_[0]->opt("--read-length", $_[0]->read_length) }
sub min_overlap_opt         { $_[0]->opt("--min-overlap", $_[0]->min_length) }
sub max_insertions_opt      { $_[0]->opt("--max-insertions", $_[0]->max_insertions) }
sub match_length_cutoff_opt { $_[0]->opt("--match-length-cutoff", $_[0]->min_length) }
sub limit_nu_cutoff_opt     { $_[0]->opt("--cutoff", $_[0]->nu_limit) }
sub bowtie_cutoff_opt       { my $x = $_[0]->bowtie_nu_limit; $x ? "-k $x" : "-a" }
sub faok_opt                { $_[0]->{faok} ? "--faok" : ":" }
sub count_mismatches_opt    { $_[0]->{count_mismatches} ? "--count-mismatches" : "" } 
sub paired_end_opt          { $_[0]->{paired_end} ? "--paired" : "--single" }
sub dna_opt                 { $_[0]->{dna} ? "--dna" : "" }

sub blat_opts {
    # TODO: Allow me to be configured
    my ($self) = @_;
    my %opts = (
        minIdentity => $self->blat_min_identity,
        tileSize => $self->blat_tile_size,
        stepSize => $self->blat_step_size,
        repMatch => $self->blat_rep_match,
        maxIntron => $self->blat_max_intron);

    return map("-$_=$opts{$_}", sort keys %opts);
}

# $quantify and $quantify_specified default to false
# Both set to true if --quantify is given
# $quantify set to true if --dna is not given
# If $genomeonly, $quantify set to $quantify_specified
# So quantify if 

sub quant {
    my ($self, %opts) = @_;

    my $chunk = $opts{chunk};
    my $strand = $opts{strand};
    my $sense  = $opts{sense};
    if ($strand && $sense) {
        my $name = "quant.$strand$sense";
        return $chunk ? $self->chunk_file($name, $chunk) : $self->in_output_dir($name);
    }

    if ($chunk) {
        return $self->chunk_file("quant", $chunk);
    }
    return $self->in_output_dir("feature_quantifications_" . $self->name);
}

sub alt_quant {
    my ($self, %opts) = @_;
    my $chunk  = $opts{chunk};
    my $strand = $opts{strand};
    my $sense  = $opts{sense};
    my $name;

    if ($strand && $sense) {
        $name = "feature_quantifications.altquant.$strand$sense";
    }
    else {
        $name = "feature_quantifications_" . $self->name . ".altquant";
    }

    return $chunk ? $self->chunk_file($name, $chunk) : $self->in_output_dir($name);
}

# TODO: Maybe support name mapping?
sub name_mapping_opt   { "" } 

sub is_property {
    my $name = shift;
    exists $DEFAULTS{$name};
}

sub set {
    my ($self, $key, $value) = @_;
    confess "No such property $key" unless is_property($key);
    $self->{$key} = $value;
}

sub should_quantify {
    my ($self) = @_;
    return !($self->dna || $self->genome_only) || $self->quantify;
}

sub should_do_junctions {
    my ($self) = @_;
    return !$self->dna || $self->genome_only || $self->junctions;
}

sub novel_inferred_internal_exons_quantifications {
    my ($self) = @_;
    return $self->in_output_dir("novel_inferred_internal_exons_quantifications_"
                                    .$self->name);
}

sub ram_opt {
    return $_[0]->ram ? ("--ram", $_[0]->ram) : ();
}

sub save {
    my ($self) = @_;
    $log->debug("Saving config file, chunks is " . $self->num_chunks);
    my $filename = $self->in_output_dir($FILENAME);
    open my $fh, ">", $filename or croak "$filename: $!";
    print $fh Dumper($self);
}

sub load {
    my ($class, $dir, $force) = @_;
    my $filename = "$dir/$FILENAME";

    unless (-e $filename) {
        if ($force) {
            die "$dir doesn't seem to be a RUM output directory\n";
        }
        else {
            return;
        }
    }
    my $conf = do $filename;
    ref($conf) =~ /$class/ or croak "$filename did not return a $class";
    return $conf;
}

sub get {
    my ($self, $name) = @_;
    is_property($name) or croak "No such property $name";
    
    exists $self->{$name} or croak "Property $name was not set";

    return $self->{$name};
}

sub properties {
    sort keys %DEFAULTS;
}

sub settings_filename {
    my ($self) = @_;
    return ($self->in_output_dir($FILENAME));
}

sub lock_file {
    my ($self) = @_;
    $self->in_output_dir(".rum/lock");
}

sub min_ram_gb {
    my ($self) = @_;
    my $genome_size = $self->genome_size;
    defined($genome_size) or croak "Can't get min ram without genome size";
    my $gsz = $genome_size / 1000000000;
    my $min_ram = int($gsz * 1.67)+1;
    return $min_ram;
}

sub u_footprint { shift->in_postproc_dir("u_footprint.txt") }
sub nu_footprint { shift->in_postproc_dir("nu_footprint.txt") }
sub mapping_stats_final {
    $_[0]->in_output_dir("mapping_stats.txt");
}

sub sam_header { shift->in_postproc_dir("sam_header") }

sub in_chunk_dir {
    my ($self, $name) = @_;
    my $path = File::Spec->catfile($self->output_dir, "chunks", $name);
}

sub chunk_file {
    my ($self, $name, $chunk) = @_;
    $chunk or croak "chunk file called without chunk for $name";
    return $self->in_chunk_dir("$name.$chunk");
}

sub chunk_sam_header { $_[0]->chunk_file("sam_header", $_[1]) }

sub chunk_dir {
    my ($self) = @_;
    return File::Spec->catfile($self->output_dir, "chunks");
}

sub temp_dir {
    my ($self) = @_;
    return File::Spec->catfile($self->output_dir, "tmp");
}

sub AUTOLOAD {
    my ($self) = @_;
    
    my @parts = split /::/, $AUTOLOAD;
    my $name = $parts[-1];
    
    return if $name eq "DESTROY";
    
    return $self->get($name);
}

1;
