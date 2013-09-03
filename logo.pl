#!/usr/bin/perl

use strict;
use warnings;

require Net::SPU;
require CTCC::Client;

use constant FILE_CFG => $ENV{HOME} .'/logo.cfg';

# read config file
open(my $cfgfile, '<', FILE_CFG) or
    die 'Cannot read ', FILE_CFG, ': ', $!;
my %cfg = map{ m{([^:]*)\s*:\s*(.*?)\r?\n?$}smo } <$cfgfile>;
close $cfgfile;

# show current logo status
sub show {
    my ($spu) = @_; # {{{

    for my $logo (1 .. 2) {
        my ($id, $enabled) = $spu->logo_get($logo);
        print $logo, ': ', $enabled ? 'on' : 'off', ' ID: ', $id, "\n";
    }
}
# }}}

# Objekte erzeugen
my $spu = SPU->new(
    $cfg{spu_host},
    $cfg{spu_community_public},
    $cfg{spu_community_private},
);
my $client = CTCC::Client->new('localhost') or
    die 'Cannot connect', $!;

# convenience
$| = 1;

print 'subscribe ';
$client->subscribe('LOGO', slot => 1);
print "okay\n";

my $test="nein";
while (sleep(2) && ($test eq "nein")) {
    my @logo;
    while (!@logo) {
        #print 'loop ';
        $client->loop(2);
        #print "okay\n";

        #print "poll ";
        @logo = $client->poll('LOGO',1);
        #print " ok\n";
        if (@logo) {
            $spu->logo_disable(1);
            $spu->logo_disable(2);
            $spu->logo_set(1, $logo[0]);
            $spu->logo_set(2, $logo[0]);
            $spu->logo_enable(1);
            $spu->logo_enable(2);
            show($spu);
            #print $logo[0];
        }
    }
}

exit;
