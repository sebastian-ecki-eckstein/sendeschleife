#!/usr/bin/perl
use strict;                 # use all three strictures
$|++;                       # set command buffering
    
use Data::Dumper;
use XML::Simple;
use POSIX qw(strftime);

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

# Module einbinden
#require CTCC::Client;
require "/home/ecki/Projekte/software/sendeschleife/CTCC/Client.pm";
#require Net::Melted;
require "/home/ecki/Projekte/software/sendeschleife/Net/Melted.pm";

my $einstellungen = XMLin("demo-schleife/einstellungen.xml");
my $logo = $einstellungen->{logo};
my $aktuell_logo = "";

# Objekt erzeugen
my $client = CTCC::Client->new('localhost') or
    die 'Cannot connect: ', $!;

# Objekt erzeugen
my $melted = Net::Melted->new(
    autowipe => 0,
    host     => 'localhost',
) or die "I'm melting";

sub get_playlist {
    my ($filename) = @_; # {{{
    open(my $list, '<', $filename) or
        die 'Cannot read ', $filename, ': ', $!;
    my @playlist = <$list>;
    close($list);
    chomp @playlist;

    return @playlist;
}

sub lese_tag {
  my $dateiname = strftime "%Y-%m-%d_tag.xml", localtime;
  if(-e $dateiname){
    print "datei da";
  }
  else {
    $dateiname = strftime "%Y-%m_tag.xml", localtime;
    if(-e $dateiname){
      print "datei da";
    } else {
      $dateiname = "tag.xml";
    }
  }
  my $tag = XMLin($dateiname);
  return $tag;
}

sub zusatzinfo{
  my ($datei) = @_;
  $datei = $datei + ".meta.txt";
  #read datei
  #auswertung aspect
}

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
  my ($video, $opts) = @_; # {{{
  zusatzinfo($video);
  #
  try {
        if ($opts->{append}) {
            logs($video);
            $melted->append($video);
        } else {
            logs($video,$opts->{frame});
            $melted->load($video, $opts->{frame});
        }
        #$melted->append($trenner);
    } catch {
        open(my $err, '>>', FILE_ERROR) or
            die 'Cannot write to ', FILE_ERROR, ': ', $!;
        chomp $_;
        #print $err timestamp(), ' ', $_, ' (', $video, '; ', $trenner, ")\n";
        close $err;
    };
}

sub get_datei_liste{
  my ($tag,$uhrzeit) = @_;
  my $uhr;
  for my $sendung (@{$tag->{sendung}}){
    if(ref($sendung->{uhrzeit}) eq'ARRAY'){
      $uhr = $sendung->{uhrzeit}->{content};
    } else {
      $uhr = $sendung->{uhrzeit};
    }
    if ($uhr == $uhrzeit){
      return $sendung->{datei};
    }
  }
}

sub get_logo{
  my ($tag,$uhrzeit) = @_;
  my $uhr;
  for my $sendung (@{$tag->{sendung}}){
    if(ref($sendung->{uhrzeit}) eq'ARRAY'){
      $uhr = $sendung->{uhrzeit}->{content};
    } else {
      $uhr = $sendung->{uhrzeit};
    }
    if ($uhr == $uhrzeit){
      return $sendung->{logo};
    }
  }
}

sub get_trenner{
  my ($tag,$uhrzeit) = @_;
  my $uhr;
  for my $sendung (@{$tag->{sendung}}){
    if(ref($sendung->{uhrzeit}) eq'ARRAY'){
      $uhr = $sendung->{uhrzeit}->{content};
    } else {
      $uhr = $sendung->{uhrzeit};
    }
    if ($uhr == $uhrzeit){
      if(!($sendung->{trenner})){
        return $einstellungen->{trenner};
      } else {
        return $sendung->{trenner};
      }
    }
  }
}

sub get_ankuend{
  my ($tag,$uhrzeit) = @_;
  my $uhr;
  for my $sendung (@{$tag->{sendung}}){
    if(ref($sendung->{uhrzeit}) eq'ARRAY'){
      $uhr = $sendung->{uhrzeit}->{content};
    } else {
      $uhr = $sendung->{uhrzeit};
    }
    if ($uhr == $uhrzeit){
      if(!($sendung->{ankuendigung})){
        return 0;
      } else {
        #$sendung->{freq}?
        return $sendung->{ankuendigung};
      }
    }
  }
}

sub einzel{
  my ($sendung) = @_;
  logo($sendung->{logo});
  play($sendung->{datei});
}

sub listezufall{
  my ($tag,$uhrzeit) = @_;
  my $last_video = '';
  my $uhr;
  my $dateiliste = get_datei_liste($tag,$uhrzeit);
  my $logosendung = get_logo($tag,$uhrzeit);
  my $trennersendung = get_trenner($tag,$uhrzeit);
  #my $ankuendigung = ???
  my $zeit = strftime "%H:%M", localtime;
  while (sleep(LOOP_SLEEP)) {
    $zeit = strftime "%H:%M", localtime;
    for my $sendung (@{$tag->{sendung}}){
      if(ref($sendung->{uhrzeit}) eq'ARRAY'){
        $uhr = $sendung->{uhrzeit}->{content};
      } else {
        $uhr = $sendung->{uhrzeit};
      }
    }
    if(($zeit eq $uhr)and($zeit ne $$uhrzeit)){
      return;
    }
    my $result = $melted->get();
    if ($result->{status} ne 'playing'){
      $last_video = random_video(\@$dateiliste, $last_video);
      if ($last_video) {
         logo($logosendung);
         play($last_video);
         play(random_video(\@$trennersendung,{append => 1}));
         #zufall 0-100
         #if(zufall < freq){
         #  play(random_video(\@$ankuendigung,{append => 1}));
         #}
      }
    }
  }
}

sub listefest{
  my ($tag,$uhrzeit) = @_;
  my $dateiliste = get_datei_liste($tag,$uhrzeit);
  my $logosendung = get_logo($tag,$uhrzeit);
  my $trennersendung = get_trenner($tag,$uhrzeit);
  #my $ankuendigung = ???
  my $zeit = strftime "%H:%M", localtime;
  my $uhr = "";
  my $i = 0;
  while (sleep(LOOP_SLEEP)) {
    $zeit = strftime "%H:%M", localtime;
    for my $sendung (@{$tag->{sendung}}){
      if(ref($sendung->{uhrzeit}) eq'ARRAY'){
        $uhr = $sendung->{uhrzeit}->{content};
      } else {
        $uhr = $sendung->{uhrzeit};
      }
    }
    if(($zeit eq $uhr)and($zeit ne $$uhrzeit)){
      return;
    }
    my $result = $melted->get();
    if ($result->{status} ne 'playing'){
      logo($logosendung);
      play(@$dateiliste[$i]);
      play(random_video(\@$trennersendung,{append => 1}));
      #zufall 0-100
      #if(zufall < freq){
      #  play(random_video(\@$ankuendigung,{append => 1}));
      #}
      $i++;
      if($i>@$dateiliste){
         $i=0;
      }
    }
  }
}

sub live{
  print "hier koennte ihre werbung stehen"
}

sub logo{
  my ($was) = @_;
  $aktuell_logo = $was;
  $client->publish('LOGO', '1', $logo->$was)
}

my @merke = [];
my @merkeframe = [];
my @merkelogo = [];
my $merkeliste = "";
my $uhr = "";
my $fallback = "";
my $fallbackwas = "";
my $unterbrechung = "";
my @tag = lese_tag();

while (sleep(LOOP_SLEEP)) {
  my $zeit = strftime "%H:", localtime;
  if($zeit =~ /23:/){
    #read tag
    @tag=lese_tag();
    #read einstellungen?
  }
  $zeit = strftime "%H:%M", localtime;
  my $result = $melted->get();
  for my $sendung (${@tag->{sendung}}){
    if(ref($sendung->{uhrzeit}) eq'ARRAY'){
      $uhr = $sendung->{uhrzeit}->{content};
      if($sendung->{uhrzeit}->{fallback} eq '1'){
        $fallback = $uhr;
        $fallbackwas = $sendung->{was};
        $unterbrechung = '0';
      }
    } else {
      $uhr = $sendung->{uhrzeit};
      $unterbrechung = '1';
    }
    if($zeit eq $uhr){
      #do something
      if($unterbrechung eq '1'){
        $melted->pause();
        push(@merke, $result->{filename});
        push(@merkeframe, $result->{cur_frame} - 25);
        push(@merkelogo, $aktuell_logo);
        $unterbrechung = '0';
        if($sendung->{was} eq 'listezufall'){
          listezufall(@tag,$uhr);
        }
        elsif($sendung->{was} eq 'listefest'){
          listefest(@tag,$uhr);
        }
        elsif($sendung->{was} eq 'einzel'){
          einzel($sendung);
        }
        elsif($sendung->{was} eq 'live'){
          #noch nicht vorhanden
        }
      }
      else{
        if($result->{status} ne 'playing'){
          if(!@merke) {
            logo(pop(@merkelogo));
            play(pop(@merke),{frame => pop(@merkeframe)});
          } else {
             if($sendung->{was} eq 'listezufall'){
                listezufall(@tag,$uhr);
             }
             elsif($sendung->{was} eq 'listefest'){
               listefest(@tag,$uhr);
             }
             elsif($sendung->{was} eq 'einzel'){
               einzel($sendung);
             }
             elsif($sendung->{was} eq 'live'){
               #noch nicht vorhanden
             }
          }
        }
      }
    }
    else{
      if($result->{status} ne 'playing'){
        if(!@merke){
          logo(pop(@merkelogo));
          play(pop(@merke),{frame => pop(@merkeframe)});
        }
        else{
          if($fallbackwas eq 'listezufall'){
            listezufall(@tag,$fallback);
          }
          elsif ($fallbackwas eq 'listefest'){
            listefest(@tag,$fallback);
          }
        }
      }
    }
  }
}

exit;
