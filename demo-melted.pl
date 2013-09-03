#!/usr/bin/perl

use strict;
use warnings;
use Try::Tiny;
use Data::Dumper;

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

# Modul einbinden
require Net::Melted;

# Objekt erzeugen
my $melted = Net::Melted->new(
    autowipe => 0,
    host     => 'localhost',
) or die "I'm melting";

# convenience
$| = 1;
my $result;

print "pause ";
$melted->pause() and print "okay\n";

print "append ";
try {
    $melted->append('test.avi') and print "okay\n";
} catch {
    warn "failed ($_)\n";
};

print "play ";
$melted->play() and print "okay\n";

print "goto ";
$melted->goto(10) and print "okay\n";

print "goto (no value) ";
try {
    $melted->goto() and warn "failed\n";
} catch {
    if (m{^Frame must be an integer}smog) {
        print "okay\n";
    } else {
        warn "failed ($_)\n";
    }
};

print "goto (broken value) ";
try {
    $melted->goto('foo') and warn "failed\n";
} catch {
    if (m{^Frame not a positive integer}smog) {
        print "okay\n";
    } else {
        warn "failed ($_)\n";
    }
};

print "wipe ";
$melted->wipe() and print "okay\n";

print "get ";
$result = $melted->get() and print "okay\n";
print 'File:   ', $result->{filename} ? $result->{filename} : 'undef', "\n";
print 'Status: ', $result->{status} ? $result->{status} : 'undef', "\n";

print "load ";
try {
    $melted->load('test.avi') and print "okay\n";
} catch {
    warn "failed ($_)\n";
};

print "get ";
$result = $melted->get() and print "okay\n";
print 'File:   ', $result->{filename} ? $result->{filename} : 'undef', "\n";

sleep 5;
$result = $melted->get() and print "okay\n";
print 'Status: ', $result->{status} ? $result->{status} : 'undef', "\n";
print Dumper($result);
