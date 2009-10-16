package App::Dataninja::Bot::Plugin::Twitter;
use Moose;
extends 'App::Dataninja::Bot::Plugin';
use Net::Twitter;
use String::Util 'crunch';

=head1 NAME

App::Dataninja::Bot::Plugin::Twitter - get the latest tweet of yourself or someone
else

=head1 COMMANDS

=over

=item * twitter B<[tweeter]>

Get the latest tweet by B<tweeter>. If you don't specify a tweeter, it defaults
to your nick.

=back

=cut

sub get_latest_tweet {
    my $name = shift;
    my $nth_tweet = shift || 0;

    $nth_tweet = 19 if $nth_tweet > 19;

    my $text = eval {
        my $twitter = Net::Twitter->new;
        my $responses = $twitter->user_timeline({id => $name});
        $responses->[$nth_tweet]{text};
    };

    return $@ ? "Unable to get ${name}'s latest status." : $text;
}

around 'command_setup' => sub {
    my $orig = shift;
    my $self = shift;

    $self->command(twitter => sub {
        my $command_args = crunch(shift);
        my $message_data = shift;

        my ($name, $nth_tweet, $tweet_id, $date) =
            $command_args =~ m<
                ^(\w+)? \s*        # username
                (-?\d+)?           # get the Nth tweet (0-indexex)
                (?:
                    (\#\d+) |      # get this particular status id
                    (\#\{[^}]+\})  # get the tweet from this date
                )?
            >x;
        my $name ||= $message_data->nick;

        my $tweet = get_latest_tweet($name, $nth_tweet);
        return "tweet: $tweet" if $tweet;

        # at this point, no tweeple exist by that name
        return "that name is not owned by any tweeple";
    });
};
# }}}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

