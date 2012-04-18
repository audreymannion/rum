package RUM::Script::Runner;

use strict;
use warnings;

use Getopt::Long;
use File::Path qw(mkpath);
use Text::Wrap qw(wrap fill);
use Carp;
use Data::Dumper;

use RUM::Directives;
use RUM::Logging;
use RUM::Workflows;
use RUM::Usage;
use RUM::Pipeline;
use RUM::Common qw(format_large_int);

use base 'RUM::Base';

our $log = RUM::Logging->get_logger;
our $LOGO;

=head1 NAME

RUM::Script::Runner

=head1 METHODS

=over 4

=cut

################################################################################
###
### Simple accessors and convenience functions
###

=item chunk_configs

Return a list of the RUM::Config objects, one for each chunk

=cut

sub chunk_configs {
    my ($self) = @_;
    map { $self->config->for_chunk($_) } $self->chunk_nums;
}

sub chunk_workflows {
    my ($self) = @_;
    map { RUM::Workflows->chunk_workflow($_) } $self->chunk_configs;
}

sub main {
    my ($class) = @_;
    $class->new->run;
}

################################################################################
###
### Parsing and validating command line options
###

=item get_options

Parse @ARGV and build a RUM::Config from it. Also set some flags in
$self->{directives} based on some boolean options.

=cut

sub get_options {
    my ($self) = @_;

    my $quiet;
    Getopt::Long::Configure(qw(no_ignore_case));

    my $d = $self->{directives} = RUM::Directives->new;

    GetOptions(

        # Options for doing things other than running the RUM
        # pipeline.
        "save"         => sub { $d->set_save },
        "status"       => sub { $d->set_status },
        "kill"         => sub { $d->set_kill },
        "clean"        => sub { $d->set_clean },
        "veryclean"    => sub { $d->set_veryclean },
        "shell-script" => sub { $d->set_shell_script },
        "version|V"    => sub { $d->set_version },
        "help|h"       => sub { $d->set_help },
        "help-config"  => sub { $d->set_help_config },

        # Advanced (user shouldn't run these)
        "diagram"      => sub { $d->set_diagram },
        "child"        => sub { $d->set_child },
        "parent"       => sub { $d->set_parent },

        # Options controlling which portions of the pipeline to run.
        "preprocess"   => sub { $d->set_preprocess;  $d->unset_all; },
        "process"      => sub { $d->set_process;     $d->unset_all; },
        "postprocess"  => sub { $d->set_postprocess; $d->unset_all; },
        "chunk=s"      => \(my $chunk),

        # Options typically entered by a user to define a job.
        "config=s"    => \(my $rum_config_file),
        "output|o=s"  => \(my $output_dir),
        "name=s"      => \(my $name),
        "chunks=s" => \(my $num_chunks),
        "qsub"     => \(my $qsub),
        "platform=s" => \(my $platform),

# Good until here

        "alt-genes=s"  => \(my $alt_genes),
        "alt-quants=s" => \(my $alt_quant),
        "blat-only" => \(my $blat_only),
        "count-mismatches" => \(my $count_mismatches),
        "dna" => \(my $dna),
        "genome-only" => \(my $genome_only),
        "junctions" => \(my $junctions),
        "limit-bowtie-nu" => \(my $limit_bowtie_nu),
        "limit-nu=s"   => \(my $nu_limit),
        "max-insertions-per-read=s" => \(my $max_insertions = 1),
        "min-identity" => \(my $min_identity),
        "min-length=s" => \(my $min_length),
        "no-clean"  => \(my $no_clean),
        "preserve-names" => \(my $preserve_names),
        "quals-file|qual-file=s" => \(my $quals_file),
        "quantify" => \(my $quantify),
        "quiet|q"   => sub { $log->less_logging(1); $quiet = 1; },
        "ram=s"    => \(my $ram),
        "read-lengths=s" => \(my $read_lengths),
        "strand-specific" => \(my $strand_specific),
        "variable-read-lengths|variable-length-reads" => \(my $variable_read_lengths),
        "verbose|v" => sub { $log->more_logging(1) },

        # Options for blat
        "minIdentity|blat-min-identity=s" => \(my $blat_min_identity),
        "tileSize|blat-tile-size=s"       => \(my $blat_tile_size),
        "stepSize|blat-step-size=s"       => \(my $blat_step_size),
        "repMatch|blat-rep-match=s"       => \(my $blat_rep_match),
        "maxIntron|blat-max-intron=s"     => \(my $blat_max_intron)
    );


    my $dir = $output_dir || ".";

    my $c = RUM::Config->load($dir);
    !$c or ref($c) =~ /RUM::Config/ or confess("Not a config: $c");
    $c = RUM::Config->default unless $c;
    ref($c) =~ /RUM::Config/ or confess("Not a config: $c");
    $c->set(argv => [@ARGV]);

    # If a chunk is specified, that implies that the user wants to do
    # the 'processing' phase, so unset preprocess and postprocess
    if ($chunk) {
        RUM::Usage->bad("Can't use --preprocess with --chunk")
              if $d->preprocess;
        RUM::Usage->bad("Can't use --postprocess with --chunk")
              if $d->postprocess;
        $d->unset_all;
        $d->set_process;
    }

    my $set = sub { 
        my ($k, $v) = @_;
        return unless defined $v;
        my $existing = $c->get($k);
#        warn "Changing $k from $existing to $v" 
#            if defined($existing) && $existing ne $v;

        $c->set($k, $v);
    };

    $platform = 'SGE' if $qsub;

    $c->set('bowtie_nu_limit', 100) if $limit_bowtie_nu;
    $set->('quantify', $quantify);
    $set->('strand_specific', $strand_specific);
    $set->('ram', $ram);
    $set->('junctions', $junctions);
    $set->('count_mismatches', $count_mismatches);
    $set->('max_insertions', $max_insertions),
    $set->('cleanup', !$no_clean);
    $set->('dna', $dna);
    $set->('genome_only', $genome_only);
    $set->('chunk', $chunk);
    $set->('min_length', $min_length);
    $set->('output_dir',  $output_dir);
    $set->('num_chunks',  $num_chunks);
    $set->('reads', @ARGV ? [@ARGV] : undef);
    $set->('preserve_names', $preserve_names);
    $set->('variable_length_reads', $variable_read_lengths);
    $set->('user_quals', $quals_file);
    $set->('rum_config_file', $rum_config_file);
    $set->('name', $name);
    $set->('min_identity', $min_identity);
    $set->('nu_limit', $nu_limit);
    $set->('alt_genes', $alt_genes);
    $set->('alt_quant_model', $alt_quant);

    $set->('blat_min_identity', $blat_min_identity);
    $set->('blat_tile_size', $blat_tile_size);
    $set->('blat_step_size', $blat_step_size);
    $set->('blat_rep_match', $blat_rep_match);
    $set->('blat_max_intron', $blat_max_intron);
    $set->('blat_only', $blat_only);
    $set->('platform', $platform);
    $self->{config} = $c;
}


=item check_config

Check my RUM::Config for errors. Calls RUM::Usage->bad (which exits)
if there are any errors.

=cut

sub check_config {
    my ($self) = @_;

    my @errors;

    my $c = $self->config;
    $c->output_dir or push @errors,
        "Please specify an output directory with --output or -o";
    
    # Job name
    if ($c->name) {
        length($c->name) <= 250 or push @errors,
            "The name must be less than 250 characters";
        $c->set('name', fix_name($c->name));
    }
    else {
        push @errors, "Please specify a name with --name";
    }

    $c->rum_config_file or push @errors,
        "Please specify a rum config file with --config";
    $c->load_rum_config_file if $c->rum_config_file;

    my $reads = $c->reads;

    $reads && (@$reads == 1 || @$reads == 2) or push @errors,
        "Please provide one or two read files";
    if ($reads && @$reads == 2) {
        $reads->[0] ne $reads->[1] or push @errors,
        "You specified the same file for the forward and reverse reads, ".
            "must be an error";
    }
    
    if (defined($c->user_quals)) {
        $c->quals_file =~ /\// or push @errors,
            "do not specify -quals file with a full path, ".
                "put it in the '". $c->output_dir."' directory.";
    }

    $c->min_identity =~ /^\d+$/ && $c->min_identity <= 100 or push @errors,
        "--min-identity must be an integer between zero and 100. You
        have given '".$c->min_identity."'.";

    if (defined($c->min_length)) {
        $c->min_length =~ /^\d+$/ && $c->min_length >= 10 or push @errors,
            "--min-length must be an integer >= 10. You have given '".
                $c->min_length."'.";
    }
    
    if (defined($c->nu_limit)) {
        $c->nu_limit =~ /^\d+$/ && $c->nu_limit > 0 or push @errors,
            "--limit-nu must be an integer greater than zero. You have given '".
                $c->nu_limit."'.";
    }

    $c->preserve_names && $c->variable_read_lengths and push @errors,
        "Cannot use both --preserve-names and --variable-read-lengths at ".
            "the same time. Sorry, we will fix this eventually.";

    local $_ = $c->blat_min_identity;
    /^\d+$/ && $_ <= 100 or push @errors,
        "--blat-min-identity or --minIdentity must be an integer between ".
            "0 and 100.";

    @errors = map { wrap('* ', '  ', $_) } @errors;

    my $msg = "Usage errors:\n\n" . join("\n", @errors);
    RUM::Usage->bad($msg) if @errors;    
    
    if ($c->alt_genes) {
        -r $c->alt_genes or die
            "Can't read from alt gene file ".$c->alt_genes.": $!";
    }
    if ($c->alt_quant_model) {
        -r $c->alt_quant_model or die
            "Can't read from ".$c->alt_quant_model.": $!";
    }
    
}

################################################################################
###
### High-level orchestration
###

sub run {
    my ($self) = @_;
    $self->get_options();
    my $d = $self->directives;
    if ($d->version) {
        $self->say("RUM version $RUM::Pipeline::VERSION, released $RUM::Pipeline::RELEASE_DATE");
    }
    elsif ($d->help) {
        RUM::Usage->help;
    }
    elsif ($d->help_config) {
        $self->say($RUM::ConfigFile::DOC);
    }
    elsif ($d->shell_script) {
        $self->export_shell_script;
    }
    elsif ($d->kill) {
        $self->stop;
    }
    else {
        $self->run_pipeline;
    }
}

sub platform {
    my ($self) = @_;

    my $name = $self->directives->child ? "Local" : $self->config->platform;
    my $class = "RUM::Platform::$name";
    my $file = "RUM/Platform/$name.pm";
    require $file;
    my $platform = $class->new($self->config, $self->directives);
}

sub run_pipeline {
    my ($self) = @_;

    my $d = $self->directives;
    $self->check_config;        
    $self->check_gamma;
    $self->setup;

    if ($d->save) {
        $self->say("Saving configuration");
        $self->config->save;
    }
    elsif ($d->diagram) {
        $self->diagram;
    }
    elsif ($d->status) {
        $self->print_processing_status if $d->process || $d->all;
        $self->print_postprocessing_status if $d->postprocess || $d->all;
    }
    elsif ($d->clean || $d->veryclean) {
        $self->say("Cleaning up");
        $self->clean;
    }
    else {

        $self->show_logo;

        $self->check_ram unless $d->child;

        $self->dump_config;

        my $platform = $self->platform;

        if ( ref($platform) !~ /Local/ && ! ( $d->parent || $d->child ) ) {
            $self->say("Submitting tasks and exiting");
            $platform->start_parent;
            return;
        }

        if ($d->preprocess || $d->all) {
            $platform->preprocess;
        }
        if ($d->process || $d->all) {
            $platform->process;
        }
        if ($d->postprocess || $d->all) {
            $platform->postprocess;
        }
    }
}


################################################################################
###
### Other tasks not directly involved with running the pipeline
###

sub stop {
    my ($self) = @_;
    $self->say("Killing job");
    $self->platform->stop;
}

sub cleanup_reads_and_quals {
    my ($self) = @_;
    for my $c ($self->chunk_configs) {
        unlink($c->chunk_suffixed("quals.fa"),
               $c->chunk_suffixed("reads.fa"));
    }

}

sub clean {
    my ($self) = @_;
    my $c = $self->config;
    my $d = $self->directives;

    # If user ran rum_runner --clean, clean up all the results from
    # the chunks; just leave the merged files.
    if ($d->all) {
        $self->cleanup_reads_and_quals;
        for my $w ($self->chunk_workflows) {
            $w->clean(1);
        }
        RUM::Workflows->postprocessing_workflow($c)->clean($d->veryclean);
    }

    # Otherwise just clean up whichever phases they asked
    elsif ($d->preprocess) {
        $self->cleanup_reads_and_quals;
    }

    # Otherwise just clean up whichever phases they asked
    elsif ($d->process) {
        for my $w ($self->chunk_workflows) {
            $w->clean($d->veryclean);
        }
    }

    if ($d->postprocess) {
        RUM::Workflows->postprocessing_workflow($c)->clean($d->veryclean);
    }
}

sub diagram {
    my ($self) = @_;

    print "My num chunks is ", $self->config->num_chunks, "\n";
    my $d = $self->directives;
    if ($d->process || $d->all) {
        for my $c ($self->chunk_configs) {
            my $dot = $self->config->in_output_dir(sprintf("chunk%03d.dot", $c->chunk));
            my $pdf = $self->config->in_output_dir(sprintf("chunk%03d.pdf", $c->chunk));
            open my $dot_out, ">", $dot;
            RUM::Workflows->chunk_workflow($c)->state_machine->dotty($dot_out);
            close $dot_out;
            system("dot -o$pdf -Tpdf $dot");
        }
    }

    if ($d->postprocess || $d->all) {
        my $dot = $self->config->in_output_dir("postprocessing.dot");
        my $pdf = $self->config->in_output_dir("postprocessing.pdf");
        open my $dot_out, ">", $dot;
        RUM::Workflows->postprocessing_workflow($self->config)->state_machine->dotty($dot_out);
        close $dot_out;
        system("dot -o$pdf -Tpdf $dot");
    }
}

sub setup {
    my ($self) = @_;
    my $output_dir = $self->config->output_dir;
    unless (-d $output_dir) {
        mkpath($output_dir) or die "mkdir $output_dir: $!";
    }

}


sub new {
    my ($class) = @_;
    my $self = {};
    $self->{config} = undef;
    $self->{directives} = undef;
    bless $self, $class;
}

sub show_logo {
    my ($self) = @_;
    my $msg = <<EOF;

RUM Version $RUM::Pipeline::VERSION

$LOGO
EOF
    $self->say($msg);

}

sub fix_name {
    local $_ = shift;

    my $name_o = $_;
    s/\s+/_/g;
    s/^[^a-zA-Z0-9_.-]//;
    s/[^a-zA-Z0-9_.-]$//g;
    s/[^a-zA-Z0-9_.-]/_/g;
    
    return $_;
}

sub check_gamma {
    my ($self) = @_;
    my $host = `hostname`;
    if ($host =~ /login.genomics.upenn.edu/ && !$self->config->platform eq 'Local') {
        die("you cannot run RUM on the PGFI cluster without using the --qsub option.");
    }
}



sub print_processing_status {
    my ($self) = @_;

    local $_;
    my $c = $self->config;

    my @steps;
    my %num_completed;
    my %comments;
    my %progress;
    my @chunks;

    if ($c->chunk) {
        push @chunks, $c->chunk;
    }
    else {
        push @chunks, (1 .. $c->num_chunks || 1);
    }

    for my $chunk (@chunks) {
        my $w = RUM::Workflows->chunk_workflow($c->for_chunk($chunk));
        my $handle_state = sub {
            my ($name, $completed) = @_;
            unless (exists $num_completed{$name}) {
                $num_completed{$name} = 0;
                $progress{$name} = "";
                $comments{$name} = $w->comment($name);
                push @steps, $name;
            }
            $progress{$name} .= $completed ? "X" : " ";
            $num_completed{$name} += $completed;
        };

        $w->walk_states($handle_state);
    }

    my $n = @chunks;
    #my $digits = num_digits($n);
    #my $h1     = "   Chunks ";
    #my $h2     = "Done / Total";
    #my $format =  "%4d /  %4d ";

    $self->say("Processing in $n chunks");
    $self->say("-----------------------");
    #$self->say($h1);
    #$self->say($h2);
    for (@steps) {
        #my $progress = sprintf $format, $num_completed{$_}, $n;
        my $progress = $progress{$_} . " ";
        my $comment   = $comments{$_};
        my $indent = ' ' x length($progress);
        $self->say(wrap($progress, $indent, $comment));
    }

}

sub print_postprocessing_status {
    my ($self) = @_;
    my $c = $self->config;

    $self->say();
    $self->say("Postprocessing");
    $self->say("--------------");
    my $postproc = RUM::Workflows->postprocessing_workflow($c);
    my $handle_state = sub {
        my ($name, $completed) = @_;
        $self->say(($completed ? "X" : " ") . " " . $postproc->comment($name));
    };
    $postproc->walk_states($handle_state);
}


sub export_shell_script {
    my ($self) = @_;

    $self->say("Generating pipeline shell script for each chunk");
    for my $chunk ($self->chunk_nums) {
        my $config = $self->config->for_chunk($chunk);
        my $w = RUM::Workflows->chunk_workflow($chunk);
        my $file = IO::File->new($config->pipeline_sh);
        open my $out, ">", $file or die "Can't open $file for writing: $!";
        $w->shell_script($out);
    }
}


sub dump_config {
    my ($self) = @_;
    $log->debug("-" x 40);
    $log->debug("Job configuration");
    $log->debug("RUM Version: $RUM::Pipeline::VERSION");
    
    for my $key ($self->config->properties) {
        my $val = $self->config->get($key);
        next unless defined $val;
        $val = Data::Dumper->new([$val])->Indent(0)->Dump if ref($val);
        $log->debug("$key: $val");
    }
    $log->debug("-" x 40);
}

################################################################################
###
### Checking available memory
###

sub genome_size {
    my ($self) = @_;

    $self->say("Determining how much RAM you need based on your genome.");

    my $c = $self->config;
    my $genome_blat = $c->genome_fa;

    my $gs1 = -s $genome_blat;
    my $gs2 = 0;
    my $gs3 = 0;

    open my $in, "<", $genome_blat or croak "$genome_blat: $!";

    local $_;
    while (defined($_ = <$in>)) {
        next unless /^>/;
        $gs2 += length;
        $gs3 += 1;
    }

    my $genome_size = $gs1 - $gs2 - $gs3;
    my $gs4 = &format_large_int($genome_size);
    my $gsz = $genome_size / 1000000000;
    my $min_ram = int($gsz * 1.67)+1;
}

sub check_ram {

    my ($self) = @_;

    my $c = $self->config;

    return if $c->ram_ok;

    if (!$c->ram) {
        $self->say("I'm going to try to figure out how much RAM ",
                   "you have. If you see some error messages here, ",
                   " don't worry, these are harmless.");
        my $available = $self->available_ram;
        $c->set('ram', $available);
    }

    my $genome_size = $self->genome_size;
    my $gs4 = &format_large_int($genome_size);
    my $gsz = $genome_size / 1000000000;
    my $min_ram = int($gsz * 1.67)+1;
    
    $self->say();

    my $totalram = $c->ram;
    my $RAMperchunk;
    my $ram;

    # We couldn't figure out RAM, warn user.
    if ($totalram) {
        $RAMperchunk = $totalram / ($c->num_chunks||1);
    } else {
        warn("Warning: I could not determine how much RAM you " ,
             "have.  If you have less than $min_ram gigs per ",
             "chunk this might not work. I'm going to ",
             "proceed with fingers crossed.\n");
        $ram = $min_ram;      
    }
    
    if ($totalram) {

        if($RAMperchunk >= $min_ram) {
            $self->say(sprintf(
                "It seems like you have %.2f Gb of RAM on ".
                "your machine. Unless you have too much other stuff ".
                "running, RAM should not be a problem.", $RAMperchunk));
        } else {
            $self->say(
                "Warning: you have only $RAMperchunk Gb of RAM ",
                "per chunk.  Based on the size of your genome ",
                "you will probably need more like $min_ram Gb ",
                "per chunk. Anyway I can try and see what ",
                "happens.");
            print("Do you really want me to proceed?  Enter 'Y' or 'N': ");
            local $_ = <STDIN>;
            if(/^n$/i) {
                exit();
            }
        }
        $self->say();
        $ram = $min_ram;
        if($ram < 6 && $ram < $RAMperchunk) {
            $ram = $RAMperchunk;
            if($ram > 6) {
                $ram = 6;
            }
        }

        $c->set('ram', $ram);
        $c->set('ram_ok', 1);
        $c->save;
        # sleep($PAUSE_TIME);
    }

}

sub available_ram {

    my ($self) = @_;

    my $c = $self->config;

    return $c->ram if $c->ram;

    local $_;

    # this should work on linux
    $_ = `free -g 2>/dev/null`; 
    if (/Mem:\s+(\d+)/s) {
        return $1;
    }

    # this should work on freeBSD
    $_ = `grep memory /var/run/dmesg.boot 2>/dev/null`;
    if (/avail memory = (\d+)/) {
        return int($1 / 1000000000);
    }

    # this should work on a mac
    $_ = `top -l 1 | grep free`;
    if (/(\d+)(.)\s+used, (\d+)(.) free/) {
        my $used = $1;
        my $type1 = $2;
        my $free = $3;
        my $type2 = $4;
        if($type1 eq "K" || $type1 eq "k") {
            $used = int($used / 1000000);
        }
        if($type2 eq "K" || $type2 eq "k") {
            $free = int($free / 1000000);
        }
        if($type1 eq "M" || $type1 eq "m") {
            $used = int($used / 1000);
        }
        if($type2 eq "M" || $type2 eq "m") {
            $free = int($free / 1000);
        }
        return $used + $free;
    }
    return 0;
}

$LOGO = <<'EOF';
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                 _   _   _   _   _   _    _
               // \// \// \// \// \// \/
              //\_//\_//\_//\_//\_//\_//
        o_O__O_ o
       | ====== |       .-----------.
       `--------'       |||||||||||||
        || ~~ ||        |-----------|
        || ~~ ||        | .-------. |
        ||----||        ! | UPENN | !
       //      \\        \`-------'/
      // /!  !\ \\        \_  O  _/
     !!__________!!         \   /
     ||  ~~~~~~  ||          `-'
     || _        ||
     |||_|| ||\/|||
     ||| \|_||  |||
     ||          ||
     ||  ~~~~~~  ||
     ||__________||
.----|||        |||------------------.
     ||\\      //||                 /|
     |============|                //
     `------------'               //
---------------------------------'/
---------------------------------'
  ____________________________________________________________
- The RNA-Seq Unified Mapper (RUM) Pipeline has been initiated -
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
EOF


################################################################################
###
### Finishing up
###



1;

