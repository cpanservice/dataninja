#!/usr/bin/env perl
use strict;
use warnings;
use Net::Hiveminder;
package Dataninja::Bot::Command::Task;
use base 'Dataninja::Bot::Command';
=head1 DESCRIPTION

Reminds a user to blah blah TODO

=cut

sub pattern { qr/^#task\s+(.+)/ }

sub run {
    my $args = shift;
    my $hm = Net::Hiveminder->new(use_config => 1);

    (my $task = $1) =~ s/\[.+?\]//g;
    my $priorities_munged = 0;

    warn "TASK: $task";
    $priorities_munged = 1 if $task =~ /!/ || $task =~ /^[+-]/;
    $task =~ y/!//d;
    $task =~ s/^[+-]*//g;
    my $warnings = "";
    $warnings = " (warning: priority modification detected and stripped)"
	if $priorities_munged;
    return "task: " . $hm->create_task("$task [irc_dataninja]")->{record_locator}
	. $warnings;
    
}

1;
