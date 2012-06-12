package RUM::Alignment;

use strict;
use warnings;

use Carp;

use base 'RUM::Identifiable';

sub new {
    my ($class, %params) = @_;
    my $self = {};

    local $_;
    for (qw(readid chr strand seq)) {
        defined($self->{$_} = delete $params{$_}) or croak "Need $_";
    }
    $self->{raw} = delete $params{raw};

    defined($self->{locs}   = delete $params{locs})
    or defined($self->{loc}   = delete $params{loc})
    or croak "Need locs or loc";

    return bless $self, $class;
}

sub copy {
    my ($self, %params) = @_;
    my %copy = %{ $self };
    while (my ($k, $v) = each %params) {
        $copy{$k} = $v;
    }
    return __PACKAGE__->new(%copy);
}

sub chromosome { $_[0]->{chr} } 
sub locs       { $_[0]->{locs} }
sub loc        { $_[0]->{loc} } 
sub strand     { $_[0]->{strand} }
sub seq        { $_[0]->{seq} } 
sub starts     { [ map { $_->[0] } @{ $_[0]->{locs} } ] }
sub raw        { $_[0]->{raw} }




1;