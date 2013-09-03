#!/usr/bin/perl

package CTCC::Client;

#http://wiki.fem.tu-ilmenau.de/broadcast/projekte/sendeabwicklung/ctcc/protokoll
=head1 NAME

CTCC::Client - Client for CTCC Message Hub

=head1 VERSION

$Revision: $

=head1 SYNOPSIS

C<CTCC::Client> implements a client for the central message hub using
the CTCC protocol. It was developed for FeM-CI, the Fricklig-eklig
Media Content Infrastructure of the FeM e.V.

=cut

use strict;
use warnings;

use Carp;
use CTCC::Client::Subscription;
use Net::Telnet;

=head1 USAGE

=head2 new($host, [$port])

Create a new CTCC::Client object. You need to pass the hostname or
address of the message hub. You may add a port number (default:
12345).

=cut

use constant {
    DEBUG    => 1,
    HUB_PORT => 12345,
};

sub new {
    my $class = shift;
    my ($host, $port) = @_; # {{{

    croak 'No message hub hostname/address!' unless $host;

    my $self = {
        # load parameters/default values into internal hash
        CC_HOST  => $host,
        CC_PORT  => $port ? $port : HUB_PORT,
        CC_STATE => {},
    };

    bless ($self, $class);
    return $self;
}
# }}}

# private functions

# get current telnet connection or create one
sub _connection {
    my ($self) = @_; # {{{

    # connection still okay, return it
    return $self->{CC_TELNET} if $self->{CC_TELNET};

    # build new connection
    my $telnet = Net::Telnet->new(Telnetmode => 0);
    $telnet->open(
        Host       => $self->{CC_HOST},
        Port       => $self->{CC_PORT},
    );
    $telnet->input_log('-')  if DEBUG;
    $telnet->output_log('-') if DEBUG;

    # try to read (not yet implemented) greeting
    my $line = $telnet->getline(
        Errmode => 'return',
        Timeout => 2,
    );

    # restore subscriptions
    foreach my $obj (@{$self->{CC_SUB_LIST}}) {
        $obj->subscribe($telnet);
    }

    # okay, store connection and return it
    $self->{CC_TELNET} = $telnet;
    return $telnet;
}
# }}}

# public interface

=head2 get($channel, $slot)

'get' asks the message hub for cached messages in the specified slot
on the channel.

Returns nothing.

=cut

sub get {
    my ($self, $channel, $slot) = @_; # {{{

    # sanity checks
    croak 'Channel not specified'   unless $channel;
    croak 'Slot not numeric or "*"' unless $slot =~ m{^(\d+|\*)$}o;

    my $telnet = $self->_connection;
    $telnet->print('GET '. $channel .' '. $slot);

    return;
}
# }}}

=head2 subscribe($channel, {[slot => $slot], [callback => &callback]})

Subscribe a channel, optionally limited to the specified slot. You may
either add a callback function to process received data, or poll data
via the poll() method.

Returns nothing.

=cut

sub subscribe {
    my ($self, $channel, %opts) = @_;

    # set defaults
    $channel    = '*' unless $channel;
    $opts{slot} = '*' unless defined $opts{slot};

    my $telnet = $self->_connection;
    my $subscr = CTCC::Client::Subscription->new($telnet, $channel, %opts);

    # create internal management structure
    push @{$self->{CC_SUB_LIST}}, $subscr;
    $self->{CC_SUB_TREE}{$channel}{$opts{slot}} = $subscr;

    return;
}

=head2 publish($channel, $slot, $data)

Publish data on the selected channel into the specified slot.

Returns nothing.

=cut

sub publish {
    my ($self, $channel, $slot, $data) = @_; # {{{

    # sanity checks
    croak 'Channel not specified' unless $channel;
    croak 'Slot not numeric'      unless $slot =~ m{^\d+$}o;
    croak 'Data b0rked'
        # ASCII without CR/LF
        unless $data =~ m{^[\x{00}-\x{09}\x{11}\x{12}\x{14}-\x{7f}]+$}o;

    my $telnet = $self->_connection;
    $telnet->print('PUBLISH '. $channel .' '. $slot .' '. $data);

    return;
}
# }}}

=head2 poll($channel, [$slot])

If no callback is set, you need to poll the selected channel for
data. If $slot is given, only returns data for that slot.

Returns array of published lines.  May be empty.

=cut

sub poll {
    my ($self, $channel, $slot) = @_;

    # sanity checks
    croak 'Channel not specified'   unless $channel;

    #use Data::Dumper;
    #print Dumper($self->{CC_SUB_TREE});

    if (defined $slot) {
        croak 'Slot not numeric or "*"' unless $slot =~ m{^(\d+|\*)$}o;

        if (my $obj = $self->{CC_SUB_TREE}{$channel}{$slot}) {
            return $obj->poll if $obj->pollable;
        }

    } else { # all slots
        my @collect = ();
        foreach my $slot (keys %{$self->{CC_SUB_TREE}{$channel}}) {
            if (my $obj = $self->{CC_SUB_TREE}{$channel}{$slot}) {
                push @collect, $obj->poll if $obj->pollable;
            }
        }
        return @collect;
    }

    return ();
}

=head2 loop([$maxwait])

As CTCC::Client is not threaded, you have to call the loop method from
time to time to allow the client to gather published messages and run
callbacks or cache them.

The loop method will wait for $maxwait seconds for publications.

Returns nothing.

=cut

sub loop {
    my ($self, $maxwait) = @_;

    # default wait
    $maxwait = 10 unless defined $maxwait;

    my $telnet = $self->_connection;
    foreach ($telnet->getlines(
            All     => 0,
            Errmode => 'return',
            Timeout => $maxwait,
    )) {
        warn '***', $_ if DEBUG;
        my ($channel, $slot, $msg) = m{^PUBLISH\s+(\S+)\s(\S+)\s(.*)}smo;

        my $obj = $self->{CC_SUB_TREE}{$channel}{$slot};
        $obj->_process($msg) if $obj;
    }

    return;
}

1;
__END__

=head1 COPYRIGHT

Copyright (c) 2012 Christoph Weber <mehdorn@fem.tu-ilmenau.de>

=cut
