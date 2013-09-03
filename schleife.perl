#!/usr/bin/perl

use strict;
use warnings;
#use File::Find;
use POSIX qw(strftime);
use Try::Tiny;

use constant {
    FILE_LOG      => '/home/fem/dvbt_log.txt',
    FILE_ERROR    => '/home/fem/dvbt_error.txt',
    LOOP_SLEEP    => 2,
    TRACE         => 1,
    VIDEO_IMPRINT => 'impressum_2013.avi',
    VIDEO_SPI     => 'News/spi-latest.mp4',
    VIDEO_31_A    => 'Unterhaltung/Dinner_For_One_DV.avi',
    VIDEO_31_B    => 'Unterhaltung/2012-12-31_Broadcast_Silvester_Countdow_Final.avi',
};

# Pfad zu Net::Melted in @INC schubsen
# (entfaellt, wenn es spaeter mal im Standardpfad liegt)
my $libdir;
BEGIN {
    use File::Spec::Functions qw(rel2abs);
    use File::Basename qw(dirname);
    my $path = rel2abs($0);
    $libdir  = dirname($path);
}
use lib $libdir;

# Module einbinden
require CTCC::Client;
require Net::Melted;

sub trace { # {{{
    print timestamp(), ' ', @_, "\n" if TRACE;
}
# }}}

sub get_playlist {
    my ($filename) = @_; # {{{
    open(my $list, '<', $filename) or
        die 'Cannot read ', $filename, ': ', $!;
    my @playlist = <$list>;
    close($list);
    chomp @playlist;

    return @playlist;
}
# }}}

sub random_video {
    my ($list, $last_video) = @_; # {{{

    # empty list, nothing to do
    return '' unless @$list;

    # if there is only one video in the list, we won't have much choice
    return $list->[0] if @$list == 1;

    # do not complain if parameter is not given
    $last_video ||= '';

    my $crowbar = 0;
    my $next_video = $list->[rand @$list];
    PICK: while ($last_video eq $next_video) {
        $next_video = $list->[rand @$list];

        # bad random number generator? give up after some time
        $crowbar++;
        last PICK if $crowbar > 100;
    }

    return $next_video;
}
# }}}

# Objekt erzeugen
my $client = CTCC::Client->new('localhost') or
    die 'Cannot connect: ', $!;

sub timestamp {
    # {{{
    return strftime "%Y-%m-%d %H:%M:%S", localtime;
}
# }}}

sub logs {
    my ($title, $frame) = @_; # {{{

    # default: begin with frame 0
    $frame ||= 0;

    open(my $log, '>>', FILE_LOG) or
        die 'Cannot write to ', FILE_LOG, ': ', $!;
    print $log timestamp(), ' ', $title, ' Frame: ', $frame, "\n";
    close($log);
    $client->publish(
        "CLIP", "1",
        "{\"type\":\"change\",\"mode\":\"bridge\",\"clip\":\"{".$title."}\"}"
    );
}
# }}}

sub play {
    my ($melted, $video, $trenner, $opts) = @_; # {{{

    try {
        if ($opts->{append}) {
            $melted->append($video);
        } else {
            $melted->load($video, $opts->{frame});
        }
        $melted->append($trenner);
    } catch {
        open(my $err, '>>', FILE_ERROR) or
            die 'Cannot write to ', FILE_ERROR, ': ', $!;
        chomp $_;
        print $err timestamp(), ' ', $_, ' (', $video, '; ', $trenner, ")\n";
        close $err;
    };
}
# }}}

sub logo_sende {
    $client->publish('LOGO', '1', '3');
}

sub logo_himmel {
    $client->publish('LOGO', '1', '8');
}

# Objekt erzeugen
my $melted = Net::Melted->new(
    autowipe => 0,
    host     => 'localhost',
) or die "I'm melting";

my @fruehs;
my @vormittags;
my @nachmittags;
my @abends;
my @nachts;
my @trenner;
my @himmelbalu;
my @himmeltrenner;
my @ankuendigung;

sub do_announcements {
    # takes no parameters # {{{
    my $annoucement = random_video(\@ankuendigung);

    # list currently empty?
    return unless $annoucement;

    # FIXME: avoid this special case in future
    return if $annoucement eq 'ignore_me';

    play($melted, $annoucement, random_video(\@trenner), {append => 1});
}
# }}}

# convenience
$| = 1;
my $last_video = '';
my $merke = '';
my $merkeframe = 0;
my $reload_playlists = 1;
my $result;
my $unterbrechung = 0;
trace 'Starting';

while (sleep(LOOP_SLEEP)) {
    if ($reload_playlists) { # {{{
        $reload_playlists = 0;
        trace 'Reloading playlists ...';
        @himmeltrenner = get_playlist('/home/fem/himmelbalu_trenner.txt');
        @himmelbalu = get_playlist('/home/fem/himmelbalu.txt');
        @ankuendigung = get_playlist('/home/fem/ankuendigungen.txt');
        @fruehs = get_playlist('/home/fem/fruehs.txt');
        @vormittags = get_playlist('/home/fem/vormittags.txt');
        @nachmittags = get_playlist('/home/fem/nachmittags.txt');
        @abends = get_playlist('/home/fem/abends.txt');
        @nachts = get_playlist('/home/fem/nachts.txt');
        @trenner = get_playlist('/home/fem/trenner.txt');
        trace 'Reloading playlists done';
    }
    # }}}

    $result = $melted->get();
    my $zeit = strftime "%H:", localtime;

    if ($result->{status} ne 'playing') {
        unless ($unterbrechung) {
            if (($zeit =~ /05:/)||($zeit =~ /06:/)||($zeit =~ /07:/)||($zeit =~ /08:/)) {
                $last_video = random_video(\@fruehs, $last_video);
                trace 'Fruehs: ', $last_video;
                if ($last_video) {
                    logs($last_video);
                    play($melted, $last_video, random_video(\@trenner));
                }

                do_announcements;
                sleep 10;
            }
            elsif (($zeit =~ /09:/)||($zeit =~ /10:/)||($zeit =~ /11:/)||($zeit =~ /12:/)) {
                $last_video = random_video(\@vormittags, $last_video);
                trace 'Vormittags: ', $last_video;
                if ($last_video) {
                    logs($last_video);
                    play($melted, $last_video, random_video(\@trenner));
                }

                do_announcements;
                sleep 10;
            }
            elsif (($zeit =~ /13:/)||($zeit =~ /14:/)||($zeit =~ /15:/)||($zeit =~ /16:/)||($zeit =~ /17:/)||($zeit =~ /18:/)||($zeit =~ /19:/)) {
                $last_video = random_video(\@nachmittags, $last_video);
                trace 'Nachmittags: ', $last_video;
                if ($last_video) {
                    logs($last_video);
                    play($melted, $last_video, random_video(\@trenner));
                }

                do_announcements;
                sleep 10;
            }
            elsif (($zeit =~ /20:/)||($zeit =~ /21:/)||($zeit =~ /22:/)) {
                $last_video = random_video(\@abends, $last_video);
                trace 'Abends: ', $last_video;
                if ($last_video) {
                    logs($last_video);
                    play($melted, $last_video, random_video(\@trenner));
                }

                do_announcements;
                sleep 10;
            }
            elsif (($zeit =~ /23:/)||($zeit =~ /00:/)||($zeit =~ /01:/)||($zeit =~ /02:/)||($zeit =~ /03:/)||($zeit =~ /04:/)) {
                $last_video = random_video(\@nachts, $last_video);
                trace 'Nachts: ', $last_video;
                if ($last_video) {
                    logs($last_video);
                    play($melted, $last_video, random_video(\@trenner));
                }

                do_announcements;
                sleep 10;
            }
        }
        else { # Unterbrechung beendet
            sleep 8;
            $result = $melted->get();
            if ($result->{status} ne 'playing') {
                $unterbrechung = 0;
                logo_sende;
                logs($merke, $merkeframe);
                play(
                    $melted, $merke, random_video(\@trenner),
                    {frame => $merkeframe}
                );

                do_announcements;
                sleep 10;
            }
        }
    }
    else {
        # playing
    }

    # Unterbrechungen einleiten
    $zeit = strftime "%H:%M:%S", localtime;
    if (($zeit =~ /12:00:/) || ($zeit =~ /20:00:/)) { # sPi-TV und Ankuendigung
        $unterbrechung = 1;
        $melted->pause();
        sleep 6;
        $result = $melted->get();
        $merke = $result->{filename};
        $merkeframe = $result->{cur_frame} - 50;
        logs('sPi-News');
        trace 'News: ', VIDEO_SPI;
        play($melted, random_video(\@trenner), VIDEO_SPI);

        do_announcements;
        sleep 60;
    }
    elsif (($zeit =~ /10:00:/) || ($zeit =~ /18:00:/)) { # Himmelbalu
        $unterbrechung = 1;
        $melted->pause();
        logo_himmel();
        sleep 6;
        $result = $melted->get();
        $merke = $result->{filename};
        $merkeframe = $result->{cur_frame} - 50;

        my $append = 0;
        trace 'Himmelbalu ...';
        foreach my $video (@himmelbalu) {
            logs("himmelbalu: ". $video);
            trace 'Himmelbalu: ', $video;
            play(
                $melted, $video, random_video(\@himmeltrenner),
                {append => $append}
            );
            $append = 1;
        }
        sleep 90;
        trace 'Himmelbalu done';
    }
    elsif ($zeit =~ /23:28:/) { # Dinner for one
        my $month = strftime "%b", localtime;
        my $day = strftime "%e", localtime;
        if (($day eq "31")&&($month eq "Dec")) {
            $unterbrechung = 1;
            $melted->pause();
            sleep 6;
            $result = $melted->get();
            $merke = $result->{filename};
            $merkeframe = $result->{cur_frame} - 50;
            logs(VIDEO_31_A);
            trace 'Silvester: ', VIDEO_31_A;
            play($melted, VIDEO_31_A, random_video(\@trenner));
        }
        sleep 90;
    }
    elsif ($zeit =~ /23:50:/) { # Silvester-Countdown
        my $month = strftime "%b", localtime;
        my $day = strftime "%e", localtime;
        if (($day eq "31")&&($month eq "Dec")) {
            $unterbrechung = 1;
            $result = $melted->get();
            $merke = $result->{filename};
            $merkeframe = $result->{cur_frame} - 50;
            logs(VIDEO_31_B);
            trace 'Silvester: '. VIDEO_31_B;
            play($melted, VIDEO_31_B, random_video(\@trenner));
        }
        sleep 90;
    }
    elsif ((($zeit =~ /23:55:/) || ($zeit =~ /03:55:/)) && !($unterbrechung)) { # Ilmpressum
        $unterbrechung = 1;
        $melted->pause();
        sleep 6;
        $result = $melted->get();
        $merke = $result->{filename};
        $merkeframe = $result->{cur_frame} - 50;
        logs("impressum");
        trace 'Impressum';
        play($melted, random_video(\@trenner), VIDEO_IMPRINT);
        sleep 280;
        $reload_playlists = 1;
    }
}

# never reached
exit;

# vim: nowrap
