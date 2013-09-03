#!/usr/local/bin/perl

use Net::Jabber qw(Client);
use vars qw($jabberbot $eventlooptimeout $clnt);
use POSIX qw(strftime);
use constant {
    HILFE => 'aktuelle Sendung mit !jetzt anfragen',
};

$SIG{HUP} = \&Stop;$SIG{KILL} = \&Stop;$SIG{TERM} = \&Stop;$SIG{INT} = \&Stop;

my $server = "server";
my $port = "5222";
my $username = "user";
my $password = "passwort";
my $resource = "name";
$jabberbot = 1;
$eventlooptimeout = 1;

my $clnt = new Net::Jabber::Client;

if($jabberbot) {
    print "Init\n";
    $clnt->SetCallBacks("message" => \&InMessage,
                       #"presence" => \&InPresence,
                       #"iq" => \&InIQ
                       );
    my $status = $clnt->Connect(hostname=>$server, port=>$port);

    if (!defined($status)) {
        die "Jabber connect error ($!)\n";
    }
    
    my @result = $clnt->AuthSend(username=>$username,
        password=>$password,
        resource=>$resource);
    
    if ($result[0] ne "ok") {
        die "Jabber auth error: @result\n";
    }
    
    $clnt->MUCJoin(
        room=>'dvb-t',
        server=>'conference.fem-net.de',
        nick=>'lena'
    );
    $clnt->PresenceSend();
    $clnt->MUCJoin(
        room=>'gelaber',
        server=>'conference.fem-net.de',
        nick=>'lena'
    );
    $clnt->PresenceSend();
}

while(!($jabberbot) || defined($clnt->Process($eventlooptimeout))) {
}

sub InMessage {
    shift;
    my $message = shift;
    #print "Got: " . $message->GetXML() . "\n";
    my $type = $message->GetType();
    my $from = $message->GetFrom();
    my $resource = "";
    ($from,$resource) = split('/',$from);
    my $subject = $message->GetSubject();
    my $body = $message->GetBody();
    my @delay = $message->GetX("jabber:x:delay");
    return if($#delay > -1);
    my @confX = $message->GetX("jabber:x:conference");
    my $xjid = ""; my $xconf = "";
    if($#confX > -1) {
      $xjid = $confX[0]->GetJID() if $confX[0]->DefinedJID();
      eval {
        $xconf = $confX[0]->GetConference();
      };
      warn $! if $!;
    }
    #print 'ja nachricht';
    if ($body eq 'hallo') {
        sendmessage('Hallo ' . $resource, $from);
    }
    if ($body eq 'moin') {
        sendmessage('moin ' . $resource, $from);
    }
    if ($body =~ /^!/) {
        if ($body eq '!jetzt') {
            sendungsmessage($from);
            logs($message->GetXML());
        } elsif ($body eq '!temp') {
            tempmessage($from);
            logs($message->GetXML());
        } elsif ($body eq '!help') {
            sendmessage(HILFE,$from);
            logs($message->GetXML());
        } elsif ($body eq '!bla') {
            sendmessage('bla',$from);
            logs($message->GetXML());
        } elsif ($body ne '!') {
            #sendmessage('nö',$from);
        } elsif ($body =~ '!\'rm -rf /') {
            sendmessage('Der Befehl »rm« wurde nicht gefunden, meinten Sie vielleicht:',$from);
            logs($message->GetXML());
        } elsif ($body =~ '!\'kill 0\'') {
            sendmessage('Der Befehl »kill« wurde nicht gefunden, meinten Sie vielleicht:',$from);
            logs($message->GetXML());
        }
    }
    if ($body eq 'danke lena') {
        sendmessage('bitte ' . $resource,$from);
        logs($message->GetXML());
    }
}

sub sendmessage {
    my ($nachricht,$chat) = @_;
    print $chat;
    print "sendmessage\n";
    my $msg = Net::Jabber::Message->new();
    $msg->SetMessage(
        type => 'groupchat',
        to => $chat,
        body => $nachricht,
    );
    $clnt->Send($msg);
}

sub sendungsmessage {
    open(IN,'/tmp/sendung.txt');
    @liste = <IN>;
    sendmessage(@liste[0],$_[0]);
    close(IN);
}

sub tempmessage {
    open(IN,'/tmp/temperatur.txt');
    @liste = <IN>;
    sendmessage(@liste[0],$_[0]);
    close(IN);
}

sub Stop {
    print "Exiting...\n";
    sendmessage('tschüss','dvb-t@conference.fem-net.de');
    $clnt->Disconnect() if $jabberbot;
    exit(0);
}

sub logs {
    my $zeit = strftime "%Y-%m-%d %H:%M:%S", localtime;
    open(OUT, ">>/home/fem/jabber_log.txt");
    print OUT $zeit . ' ' . $_[0] . "\n";
    close(OUT);
}
