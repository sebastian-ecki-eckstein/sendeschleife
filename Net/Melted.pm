#!/usr/bin/perl

package Net::Melted;

# Command reference:
# http://www.mltframework.org/bin/view/MLT/MVCP

=head1 NAME

Net::Melted - Control a melted server via network (telnet)

=head1 VERSION

$Revision: 194 $

=head1 SYNOPSIS

C<Net::Melted> provides a Perl object to ease the control of a
melted server. It was developed for FeM-CI, the Fricklig-eklig
Media Content Infrastructure of FeM e.V.

=cut

use strict;
use warnings;

use Carp;
use Net::Telnet;
use POSIX qw(strftime);
use Try::Tiny;

=head1 USAGE

=head2 new()

Create a new Net::Melted object. You may pass options for three
different types of settings:

=over

=item Melted server specific settings

  host  - host of melted server to connect to (default: localhost)
  port  - port to connect to                  (default: 5250)
  unit  - unit to use                         (default: u0)

=cut

use constant {
    MELTED_HOST       => 'localhost',
    MELTED_PORT       => 5250,
    MELTED_UNIT       => 'u0',
};

=item Logging

  log     - log playlist to given file name (default: ~/sendeschleife.log)
  jabber  - log currently played file name  (default: ~/jabber.txt)

=cut

use constant {
    FILE_LOG          => $ENV{HOME} .'/sendeschleife.log',
    FILE_JABBER       => $ENV{HOME} .'/jabber.txt',
};

=item Internal timings

  autowipe  - wipe playlist (before current item) every <n> seconds
              (default: 6 hours, 0 - no wiping)
  status    - cache status for at max. <n> seconds (default: 5 seconds)
=back

=cut

use constant {
    INTERVAL_AUTOWIPE => 3600*6,
    INTERVAL_STATUS   => 5,
};

sub new {
    my $class = shift;
    my %parms = @_; # {{{

    my $self = {
        # load parameters/default values into internal hash
        NM_HOST   => $parms{host}     ? $parms{host}     : MELTED_HOST,
        NM_PORT   => $parms{port}     ? $parms{port}     : MELTED_PORT,
        NM_UNIT   => $parms{unit}     ? $parms{unit}     : MELTED_UNIT,
        NM_JABBER => $parms{jabber}   ? $parms{jabber}   : FILE_JABBER,
        NM_LOG    => $parms{log}      ? $parms{log}      : FILE_LOG,
        NM_WIPE   => $parms{autowipe} ? $parms{autowipe} : INTERVAL_AUTOWIPE,
        NM_STATUS => $parms{status}   ? $parms{status}   : INTERVAL_STATUS,

        # force first update
        NM_LAST_STATE_UPDATE => 0,
        NM_LAST_STATE => {
            # dummy value to avoid warning
            filename => '',
        },

        # last autowipe
        NM_LAST_WIPE => time(),
    };
    croak 'status needs to be at least 1' unless $self->{NM_STATUS} >= 1;

    bless ($self, $class);
    return $self;
}
# }}}

# private functions

# get current telnet connection or create one
sub _connection {
    my ($self) = @_; # {{{

    # connection still okay, return it
    return $self->{NM_TELNET} if $self->{NM_TELNET};

    # build new connection
    my $telnet = Net::Telnet->new(Telnetmode => 0);
    $telnet->open(
        Host => $self->{NM_HOST},
        Port => $self->{NM_PORT},
    );

    # read greeting
    my $line = $telnet->getline;
    croak 'Parse error: ', $line unless $line =~ m{100 VTR Ready}o;

    # okay, store connection and return it
    $self->{NM_TELNET} = $telnet;
    return $telnet;
}
# }}}

# do jabber logging
sub _log_jabber {
    my ($self) = @_; # {{{

    open(my $out, '>', $self->{NM_JABBER}) or
        croak 'Cannot replace jabber file', $self->{NM_JABBER};
    printf $out "%s %s (noch %d Minuten)\n",
        $self->{NM_LAST_STATE}{status},
        $self->{NM_LAST_STATE}{filename},
        $self->{NM_LAST_STATE}{remain_secs} / 60;
    close($out);
}
# }}}

sub _log_file {
    my ($self) = @_; # {{{

    open(my $out, '>>', $self->{NM_LOG}) or
        croak 'Cannot append to log file', $self->{NM_LOG};
    printf $out "%s %s (Position: %ds; %s)\n",
        strftime("%Y-%m-%d %H:%M:%S", localtime),
        $self->{NM_LAST_STATE}{filename},
        $self->{NM_LAST_STATE}{cur_secs},
        $self->{NM_LAST_STATE}{status};
    close($out);
}
# }}}

# public interface

=head2 get()

Get current status of melted server. The status will be cached at max.
"status" seconds (see new()).

Returns hash with the following information:

=over

=item status

String; "playing" or "pause" etc. (directly copied from melted server)

=item filename

String; current or last played filename (depending on status)

=item cur_frame

Int; current frame position

=item cur_secs

Int; current position in seconds (frames devided by rate)

=item remain_frame

Int; remaining frames in the current file

=item cur_secs

Int; remaining seconds in the current file

=cut

sub get {
    my ($self) = @_; # {{{

    if ($self->{NM_LAST_STATE_UPDATE} + $self->{NM_STATUS} <= time()) {
        # cache too old, get new data
        my $telnet = $self->_connection;

        $telnet->print('usta '. $self->{NM_UNIT});
        # status code (normally "202 OK")
        my $line = $telnet->getline;
        chomp $line;
        croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

        # space-separated status message like:
        # empty:
        # 0 not_loaded "" 0 0 0.00 0 0 0 "" 0 0 0 0 0 0 0
        # already played something:
        # 0 paused "/foo.avi" 2205 0 25.00 0 2205 2206 "/foo.avi"
        # 2205 0 2205 2206 1 6 1
        $line = $telnet->getline;
        my (
            $unit, $status, $filename, $cur_frame, $speed, $framerate,
            $start_frame, $end_frame
        ) = $line =~ m{
            # unit number: U0, U1, U2, or U3 without the "U" prefix
            ^(\d)\s
            # mode:
            (offline|not_loaded|playing|stopped|paused|disconnected|unknown)\s
            # current clip name: filename
            "(.*?)"\s
            # current position: in absolute frame number units
            (\d+)\s
            # speed: playback rate in (percent * 10)
            (\d+)\s
            # fps: frames-per-second of loaded clip
            (\d+[.,]\d+)\s
            # current in-point: starting frame number
            (\d+)\s
            # current out-point: ending frame number
            (\d+)\s
            # length of the clip
            #(\d+)\s".*?"\s(\d+)\s(\d+)\s(\d+)\s(\d+)\s([01])\s(\d+)\s(\d+)$
            # buffer tail clip name: filename
            # buffer tail position: in absolute frame number units
            # buffer tail in-point: starting frame number
            # buffer tail out-point: ending frame number
            # buffer tail length: length of clip in buffer tail
            # seekable flag: indicates if the current clip is seekable
            # playlist generation number
            # current clip index (relates to head)
        }smogx;

        # fix up framerate
        $framerate =~ s{,}{.}smog;
        $framerate = 1 if $framerate <= 0;

        # calculate some times
        my $cur_secs     = $cur_frame / $framerate;
        my $remain_frame = $end_frame - $cur_frame;
        my $remain_secs  = $remain_frame / $framerate;

        # store for change detection
        my $name_changed =
            $filename eq $self->{NM_LAST_STATE}{filename} ? 0 : 1;

        # update state information
        $self->{NM_LAST_STATE} = {
            cur_frame    => $cur_frame,
            cur_secs     => $cur_secs,
            filename     => $filename ? $filename : '',
            remain_frame => $remain_frame,
            remain_secs  => $remain_secs,
            status       => $status,
        };
        $self->{NM_LAST_STATE_UPDATE} = time();

        # logging, Jabber
        try {
            $self->_log_jabber();
        };
        try {
            # only log when name changed
            $self->_log_file() if $name_changed;
        };
    }

    if ($self->{NM_LAST_WIPE} + $self->{NM_WIPE} <= time()) {
        try {
            $self->wipe();
        };
    }

    # return current state
    return $self->{NM_LAST_STATE};
}
# }}}

=head2 pause()

Pause playback of the unit.

Returns same status hash as get() on success.

=cut

sub pause {
    my ($self) = @_;

    my $telnet = $self->_connection;
    # pause playback
    $telnet->print('pause '. $self->{NM_UNIT});

    # status code (normally "202 OK")
    my $line = $telnet->getline;
    chomp $line;
    croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

    foreach my $i (
        1 .. 2*($self->{NM_STATUS} ? $self->{NM_STATUS} : INTERVAL_STATUS)
    ) {
        try {
            $self->get();
        };
        return $self->{NM_LAST_STATE}
            if
                $self->{NM_LAST_STATE}{status} eq 'paused' or
                # special case on startup
                $self->{NM_LAST_STATE}{status} eq 'not_loaded';
        sleep 1;
    }
    croak 'Pause failed';
}

=head2 play()

FIXME:

=cut

sub play {
    my ($self) = @_;

    my $telnet = $self->_connection;
    # Playlist fortsetzen
    $telnet->print('play '. $self->{NM_UNIT});

    # status code (normally "2xx OK")
    my $line = $telnet->getline;
    chomp $line;
    croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

    #foreach my $i (
    #    1 .. ($self->{NM_STATUS} ? $self->{NM_STATUS} : INTERVAL_STATUS)
    #) {
    #    try {
    #        $self->get();
    #    };
    #    return $self->{NM_LAST_STATE}
    #        if $self->{NM_LAST_STATE}{status} eq 'playing';
    #    sleep 1;
    #}
    #croak 'Play failed';

    return 1;
}

=head2 append()

FIXME:

=cut

# Wenn Playlist durch, bleibt es bei letzten Frame in "paused"
# -> append u0 mit nutzerdefinierter Datei

sub append {
    my ($self, $file) = @_;

    # basic checks
    croak 'File name missing or empty' unless $file;

    # übergebenes Video an Playlist anhängen
    # Wiedergabe ggf. starten
    my $telnet = $self->_connection;
    $telnet->print('apnd '. $self->{NM_UNIT} .' '. $file);

    # status code (normally "2xx OK")
    my $line = $telnet->getline;
    chomp $line;
    croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

    return $self->play;
}

=head2 load()

FIXME:

=cut

sub load {
    my ($self, $file, $frame) = @_;

    # set default value
    $frame = 0 unless $frame;

    # basic checks
    croak 'File name missing or empty'   unless $file;
    croak 'Frame not a number: ', $frame unless $frame =~ m{^\d+$}smog;

    # übergebenes Video per Load holen (ersetzt Playlist)
    my $telnet = $self->_connection;
    $telnet->print('load '. $self->{NM_UNIT} .' '. $file);

    # status code (normally "2xx OK")
    my $line = $telnet->getline;
    chomp $line;
    croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

    $self->goto($frame);

    return $self->play;
}

=head2 goto($frame)

Skip to the given frame in the current clip (Int)

Returns true on success.

=cut

sub goto {
    my ($self, $frame) = @_;

    # basic checks
    croak 'Frame must be an integer' unless defined $frame;
    $frame = scalar $frame;
    croak 'Frame not a positive integer: ', $frame
        unless $frame =~ m{^-?\d+$}smog;

    my $telnet = $self->_connection;
    # jump to frame
    $telnet->print('goto '. $self->{NM_UNIT} .' '. $frame);

    # status code (normally "2xx OK")
    my $line = $telnet->getline;
    chomp $line;
    croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

    return 1;
}

=head2 wipe()

Clear playlist before the current clip.

Returns true on success.

=cut

sub wipe {
    my ($self) = @_;

    my $telnet = $self->_connection;
    # wipe everything before current clip away from playlist
    $telnet->print('wipe '. $self->{NM_UNIT});

    # status code (normally "2xx OK")
    my $line = $telnet->getline;
    chomp $line;
    croak 'Bad status: ', $line unless $line =~ m{^2\d\d }smog;

    $self->{NM_LAST_WIPE} = time();

    return 1;
}

=pod
sub get_filelist {
    $t->print("list u0");
    my @lines = $t->get(Timeout => "10");
    return @lines;
}

=cut

1;
__END__

=head1 ACKNOWLEDGEMENTS

Idea and first code examples by Sebastian Eckstein.

=head1 COPYRIGHT

Copyright (c) 2012 Christoph Weber <mehdorn@fem.tu-ilmenau.de>

=cut
