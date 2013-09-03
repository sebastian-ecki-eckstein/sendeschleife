#!/usr/bin/perl

use strict;
use warnings;

require SPU;

use constant {
    COM_PRIV      => 'private',
    COM_PUB       => 'public',
    HOST          => '10.42.60.3',
};

my $spu = SPU->new(HOST, COM_PUB, COM_PRIV);

sub show {
    for my $logo (1 .. 2) {
        my ($id, $enabled) = $spu->logo_get($logo);
        print $logo, ': ', $enabled ? 'on' : 'off', ' ID: ', $id, "\n";
    }
}

print "init\n";
show;

print "disable 2\n";
$spu->logo_disable(2);
show;

print "set 2 to 4 and enable\n";
$spu->logo_set(2, 4);
$spu->logo_enable(2);
show;

print "set 2 to 3\n";
$spu->logo_set(2, 3);
show;

print "logo id out of range\n";
eval {
    $spu->logo_get(0);
};
print $@;
eval {
    $spu->logo_get(3);
};
print $@;

print "logo value out of range\n";
eval {
    $spu->logo_set(2, 0);
};
print $@;
eval {
    $spu->logo_set(2, 257);
};
print $@;
