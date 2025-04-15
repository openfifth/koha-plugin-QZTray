package Koha::Plugin::Com::Organisation::PluginName;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use Koha::DateUtils;

our $VERSION = '0.0.0';
our $MINIMUM_VERSION = "22.05.00.000";

our $metadata = {
    name            => 'Plugin Name',
    author          => 'Plugin Author Name',
    description     => 'Koha Plugin Name Plugin',
    date_authored   => '2024-04-15',
    date_updated    => '2024-04-15',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub install {
    my ( $self, $args ) = @_;
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    return 1;
}

1;
