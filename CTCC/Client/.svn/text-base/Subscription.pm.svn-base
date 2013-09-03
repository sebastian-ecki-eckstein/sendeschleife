#!/usr/bin/perl

package CTCC::Client::Subscription;

#http://wiki.fem.tu-ilmenau.de/broadcast/projekte/sendeabwicklung/ctcc/protokoll
=head1 NAME

CTCC::Client::Subscription - Single subscription to the CTCC Message
Hub

=head1 VERSION

$Revision: $

=head1 SYNOPSIS

C<CTCC::Client::Subscription> implements a subscription (channel and
slot) to the CTCC message hub.

=cut

use strict;
use warnings;

use Carp;

=head1 USAGE

=head2 new($connection, [$channel, {[slot => $slot], [callback => &callback]}])

Create a new CTCC::Client::Subscription object. When no channel is
given, it will subscribe '*' (all channels).  The same logic applies
for the slot.  If no callback is given, you'll need to poll the data.

=cut

sub new {
    my $class = shift;
    my ($connection, $channel, %opts) = @_; # {{{

    if (defined $opts{slot}) {
        croak 'Slot not numeric or "*"' unless $opts{slot} =~ m{^(\d+|\*)$}o;
    } else {
        $opts{slot} = '*';
    }

    # prepare state
    my $self = {
        CC_CHANNEL => $channel ? $channel : '*',
        CC_SLOT    => $opts{slot},
    };

    # do we use a callback or need a message cache for polling?
    if ($opts{callback}) {
        $self->{CC_CALLBACK} = $opts{callback};
    } else {
        $self->{CC_CACHE} = [];
    }

    bless ($self, $class);

    $self->subscribe($connection);

    return $self;
}
# }}}

# public interface

=head2 subscribe([$connection])

(Re-)subscribe the subscription object.  You may replace the existing
connection with a new one.

=cut

sub subscribe {
    my ($self, $connection) = @_; # {{{

    $self->{CC_CONNECTION} = $connection if $connection;
    my $telnet = $self->{CC_CONNECTION};
    croak 'Subscribe failed, no connection' unless $telnet;

    $telnet->print('SUBSCRIBE '. $self->{CC_CHANNEL} .' '. $self->{CC_SLOT});

    return;
}
# }}}

=head2 identify

Returns the channel name and slot as list.

=cut

sub identify {
    my ($self) = @_; # {{{

    return ($self->{CC_CHANNEL}, $self->{CC_SLOT});
}
# }}}

=head2 pollable

Returns true if the subscription is pollable (has no callback)

=cut

sub pollable {
    my ($self) = @_; # {{{

    return 0 if $self->{CC_CALLBACK};

    return 1;
}
# }}}

=head2 poll

If no callback is set, you need to poll the selected channel for
data.

Returns array of published lines (oldest first).  May be empty if
nothing was received.

=cut

sub poll {
    my ($self) = @_; # {{{

    # sanity checks
    croak 'Not a polling channel' if $self->{CC_CALLBACK};

    # empty cache, return content
    my @cache = @{$self->{CC_CACHE}};
    $self->{CC_CACHE} = [];

    return @cache;
}
# }}}

# private interface

=head2 _process($message)

Process a message (run callback or append to the polling cache).

Returns nothing.

=cut

sub _process {
    my ($self, $message) = @_; # {{{

    # sanity checks
    croak 'No message' unless $message;
    if ($self->{CC_CALLBACK}) {
        # run callback on message
        &{$self->{CC_CALLBACK}}($message);

    } else {
        # store in message cache
        push @{$self->{CC_CACHE}}, $message;
    }

    return;
}
# }}}

1;
__END__

=head1 COPYRIGHT

Copyright (c) 2012 Christoph Weber <mehdorn@fem.tu-ilmenau.de>

=cut
