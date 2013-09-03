#!/usr/bin/perl

use strict;
use warnings;

use Net::Twitter;
require CTCC::Client;

use constant FILE_CFG => $ENV{HOME} .'/sendetwitter.cfg';

# read config file
open(my $cfgfile, '<', FILE_CFG) or
    die 'Cannot read ', FILE_CFG, ': ', $!;
my %cfg = map{ m{([^:]*)\s*:\s*(.*?)\r?\n?$}smo } <$cfgfile>;
close $cfgfile;

# Objekt erzeugen
my $client = CTCC::Client->new('localhost') or
    die 'Cannot connect', $!;

# convenience
$| = 1;

print 'subscribe ';
$client->subscribe('CLIP', slot => 1);
print "okay\n";

while (sleep(2)) {
    my $nt = Net::Twitter->new(
        traits => [qw/API::REST OAuth/],
        (
            consumer_key    => $cfg{consumer_key},
            consumer_secret => $cfg{consumer_secret},
        )
    );

    $nt->access_token($cfg{access_token});
    $nt->access_token_secret($cfg{access_token_secret});

    my $test = "nein";
    while (sleep(2) && ($test eq "nein")) {
        my @sendung;
        while (!@sendung) {
            #print 'loop ';
            $client->loop(2);
            #print "okay\n";

            #print "poll ";
            @sendung = $client->poll('CLIP', 1);
            #print " ok\n";
            if (@sendung) {
                my @a = split(/{/, $sendung[0]);
                my @b = split(/}/, $a[2]);
                my $string = 'Ab jetzt zeigen wir '.$b[0];
                if (length($string)>139) {
                    $string = substring($string, 0, 138);
                }
                print $string."\n";
                $nt->update($string) or $test = "ja";
                print $test."\n";
            }
        }
    }

    $nt->end_session();
}

exit;
