package Dataninja::Bot::Plugin::Last;
use App::Nopaste 'nopaste';
use Moose;
extends 'Dataninja::Bot::Plugin::Base';

sub _line {
    my ($timestamp, $nick, $message) = @_;
    return sprintf("%s <%s> %s", $timestamp, $nick, $message);
}

around 'command_setup' => sub {
    my $orig = shift;
    my $self = shift;

    $self->command(
        'last' => sub {
            my $command_args = shift;

            my $rows = defined $command_args ? $command_args : 25;
            $rows = 200 if $rows > 200;
            $rows = 10 if $rows < 10;

            my @messages = $self->rs('Message')->search(
                {
                    network => $self->network,
                    channel => $self->channel,
                },
                { rows => $rows, order_by => 'moment desc'}
            );

            return "Last $rows lines: " . nopaste(
                join qq{\n} =>
                map {
                    _line($_->moment, $_->nick, $_->message)
                } reverse @messages
            );
        });
};

__PACKAGE__->meta->make_immutable;
no Moose;

1;

