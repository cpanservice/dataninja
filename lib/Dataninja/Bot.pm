#!/usr/bin/env perl
package Dataninja::Bot;
use Moose;
use DateTime;
use Path::Dispatcher;
use Dataninja::Bot::Dispatcher;
use Dataninja::Bot::Plugin;
use List::Util qw/first/;
use MooseX::NonMoose;

extends 'Bot::BasicBot';

=head1 DESCRIPTION

Dataninja::Bot is an extension of Bot::BasicBot. This is the core
interface needed to run Dataninja.

=head1 ATTRIBUTES

=head2 dispatcher

(Path::Dispatcher) The object that Dataninja uses to parse the IRC users' input.

=head2 assigned_network

(Str) The network on which the Dataninja process resides.

=head2 config

(Dataninja::Config) The configuration structure loaded from YAML file(s).

=head2 schema

(Dataninja::Schema) The interface that Dataninja uses to interact with the
database.

=cut

has dispatcher => (
    is => 'rw',
    isa => 'Path::Dispatcher',
    default => sub { Path::Dispatcher->new },
);

has assigned_network => (
    is => 'rw',
    isa => 'Str',
    default => '',
);

has config => (
    is => 'rw',
    isa => 'Dataninja::Config',
);

has schema => (
    is => 'rw',
    isa => 'Dataninja::Schema',
);

=head1 METHODS

=head2 load_modules

Loads all the commands for the bot to use on IRC.

=cut

=head2 init

Overridden method for loading the modules.

=cut

sub init {
    my $self = shift;
    return 1;
}

=head2 new NETWORK

Overridden to specify a network as a string for the param.

=cut

around 'new' => sub {
    my $orig = shift;
    my $class = shift;
    my $config = $_[0];
    my $assigned_network = $_[1] || 'dev';
    my $schema = $_[2];

    my %networks = %{$config->site->{networks}};
    my %network_lookup = map { ($_ => 1) } keys(%networks);

    die "Unidentified network" unless $network_lookup{$assigned_network};

    my %args = (
        server => $networks{$assigned_network}->{server},
        port   => "6667",
        channels => [
            map {
                $_->{name}
            } @{$networks{$assigned_network}->{channels}}
        ],

        nick      => $config->site->{nick},
        alt_nicks => $config->site->{nick} . '2',
        username  => $config->site->{nick},
        name      => "IRC Bot",
    );

    my $self = $class->$orig(%args);
    $self->assigned_network($assigned_network);
    $self->config($config);
    $self->schema($schema);
    return $self;
};

=head2 record_and_say

A wrapper around 'say' that logs the IRC message to the database as well as
talk to the IRC channel.

=cut

sub record_and_say {
    my $self = shift;
    my %args = @_;

    $self->schema->resultset('Message')->create({
        nick    => lc $self->config->site->{nick},
        message => $args{body},
        channel => $args{channel},
        network => $self->assigned_network,
        moment  => DateTime->now,
    });

    $self->say(%args);
}

sub _said {
    my $self = shift;
    my $args = shift;
    warn sprintf('< %s> %s', $args->{'who'}, $args->{'body'});

    $args->{'network'} = $self->assigned_network;
    my $message_data = $self->schema->resultset('Message')->create({
        nick    => lc $args->{'who'},
        message => $args->{'body'},
        channel => $args->{'channel'},
        network => $args->{'network'},
        moment  => DateTime->now,
    });

    my $bot_nick = $self->config->site->{'nick'};
    my $network_config = $self->config->site->{'networks'}->{$args->{'network'}};

    my $channel_config =
        first { $_->{'name'} eq $args->{'channel'} }
        @{$network_config->{'channels'}};

    my $set_prefix = exists $channel_config->{'prefix'}
        ? $channel_config->{'prefix'}
        : $network_config->{'prefix'};

    my $prefix_rule;
    {
        no warnings 'uninitialized';
        $prefix_rule = Path::Dispatcher::Rule::Regex->new(
            prefix => 1,
            regex => qr{^($bot_nick: |$set_prefix)},
        );
    }

    my $dispatcher = Dataninja::Bot::Dispatcher->new(
        prefix    => $prefix_rule,
        data_for_plugins => Dataninja::Bot::Plugin->new(
            message_data => $message_data,
            schema   => $self->schema,
        )
    );
    warn $args->{body};
    my $dispatch = $dispatcher->dispatch($args->{'body'});
    return undef unless $dispatch->has_matches;
    my $match = ($dispatch->matches)[0];
    return $dispatch->run(defined $match->result ? $match->result->[0] : undef);
}

=head2 said [HASHREF]

Overridden method from Bot::BasicBot that parses IRC input (public msg). The
appropriate response is returned. The method returns undef if the bot doesn't
want to respond.

=cut

sub said {
    my $self = shift;
    my $args = shift;
#    my $message = Dataninja::Model::Message->new;

    # B:BB strips the address if we are addressed
    $args->{body} = "$args->{address}: $args->{body}"
        if $args->{address} && $args->{address} ne 'msg';

    my $said = $self->_said($args, @_);
    $self->schema->resultset('Message')->create({
        nick    => lc $self->config->site->{'nick'},
        message => $said,
        channel => $args->{channel},
        moment  => DateTime->now,
        network => $self->assigned_network,
    }) if defined($said);

    substr($said, 512) = q{} if $said && length($said) > 512;
    return $said;
}

=head2 run

The method to run the Dataninja bot.

=cut

sub run {
    my $self = shift;
    $self->SUPER::run(@_);
}

=head2 tick

This was overridden to probe the reminders table for any reminders that need
mentioned to its corresponding remindee.

=cut

sub tick {
    my $self = shift;
    my $reminder = $self->schema->resultset('Reminder')->search(
        {
            network  => $self->assigned_network,
            reminded => 0,
            canceled => 0,
            moment => {'<' => DateTime->now }
        },
        { rows => 1 },
    )->single;

    if ($reminder) {
        $self->record_and_say(
            channel => $reminder->channel,
            body => sprintf(
                '%s: %s',
                $reminder->remindee,
                $reminder->description
            )
        );

        $reminder->update({reminded => 1});
    }

    my $interjection = $self->schema->resultset('Interjection')->search(
        {
            network     => $self->assigned_network,
            interjected => 0,
        },
        { rows => 1 },
    )->single;
    if ($interjection) {
        $self->record_and_say(
            channel => $interjection->channel,
            body    => $interjection->message
        );


        $interjection->update({interjected => 1});
    }
    return 5;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
