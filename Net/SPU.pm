#!/usr/bin/perl

package SPU;

=head1 NAME

SPU - Change values of the Signal Processing Unit (via SNMP)

=head1 VERSION

$Revision: $

=head1 SYNOPSIS

C<SPU> provides a Perl object to ease the control of the signal
processing unit.  You can use it to enable, change or disable the
logo.  It was developed for FeM-CI, the Fricklig-eklig Media Content
Infrastructure of FeM e.V.

=cut

use strict;
use warnings;
use Carp;
use Net::SNMP;

use constant {
    # see: http://www.for-a.com/products/fa9500/FA9500-E-E8.pdf
    OID_LOGO_BASE => '1.3.6.1.4.1.20175.1.301.2.10',
};

### public methods

=head1 USAGE

=head2 Regular public methods

=head3 new($host, $read, $write)

Create a new SPU object. Parameters:

=over

=item $host

Hostname to connect to.

=item $read

SNMP community to read settings from the SPU. Will be used for all read
operations.

=item $read

SNMP community to write settings to the SPU. Will be used only when a
write operation is necessary.

=back

=cut

sub new {
    my ($class, $host, $community_read, $community_write) = @_; # {{{

    my $self = {};
    bless ($self, $class);

    $self->{SPU_READ}  = $self->_snmp_session($host, $community_read);
    $self->{SPU_WRITE} = $self->_snmp_session($host, $community_write);

    return $self;
}
# }}}


=head3 logo_get($id)

Get status of a logo. Use the numeric identifier $id to specify the
logo of interest.

In scalar context, it will return just the current numeric value of
the logo.  In list context, it will additionally return the status
(enabled or disabled) of the logo.

=cut

sub logo_get {
    my ($self, $id) = @_; # {{{

    # basic checks
    $self->_check_logo_id($id);

    my $value = $self->get($self->_oid_logo_id($id));
    return $value unless wantarray;

    # array requested, add "enabled/disabled" status
    my $enabled = $self->get($self->_oid_logo_enab($id));

    return ($value, $enabled);
}
# }}}


=head3 logo_set($id, $value)

Set logo specified by $id to the given value.

Returns 1 on success.

=cut

sub logo_set {
    my ($self, $id, $value) = @_; # {{{

    # basic checks
    $self->_check_logo_id($id);
    $self->_check_logo_value($value);

    return $self->set($self->_oid_logo_id($id), $value);
}
# }}}


=head3 logo_enable($id)

Enable logo specified by $id.

Returns 1 on success.

=cut

sub logo_enable {
    my ($self, $id) = @_; # {{{

    # basic checks
    $self->_check_logo_id($id);

    return $self->logo_disable($id, 1);
}
# }}}


=head3 logo_disable($id, [$enable])

Disable logo specified by $id.  $enable is used internally to enable
logos.  You may not want to use this option.

Returns 1 on success.

=cut

sub logo_disable {
    my ($self, $id, $enable) = @_; # {{{

    # basic checks
    $self->_check_logo_id($id);

    return $self->set($self->_oid_logo_enab($id), ($enable ? 1 : 0));
}
# }}}


=head2 Internal public methods (usually not called directly)

=head3 get($oid)

Get the value of the specified SNMP OID in $oid.

Returns the value on success.

=cut

sub get {
    my ($self, $oid) = @_; # {{{

    my $result = $self->{SPU_READ}->get_request(
        -varbindlist => [$oid],
    ) or croak 'Error: ', $self->{SPU_READ}->error;

    return $result->{$oid};
}
# }}}

=head3 set($oid, $value, $type)

Set the value of the SNMP OID $oid to $value.  The data type in $type
is optional and defaults to INTEGER.

Returns 1 on success.

=cut

sub set {
    my ($self, $oid, $value, $type) = @_; # {{{

    $type ||= INTEGER;

    my $result = $self->{SPU_WRITE}->set_request(
        -varbindlist => [$oid, $type, $value],
    ) or croak 'Error: ', $$self->{SPU_WRITE}->error;

    return 1;
}
# }}}

sub DESTROY {
    my ($self) = @_; # {{{

    # close open SNMP session
    $self->{SPU_READ}->close  if $self->{SPU_READ};
    $self->{SPU_WRITE}->close if $self->{SPU_WRITE};
}
# }}}


### private methods

# create new SNMP session
sub _snmp_session {
    my ($self, $host, $community) = @_; # {{{

    my ($session, $error) = Net::SNMP->session(
        -community => $community,
        -hostname  => $host,
        -version   => 'snmpv2c',
    );
    croak 'Cannot create SNMP session: ', $error unless $session;

    return $session;
}
# }}}

# make sure logo_id is numeric and in (1 .. 2)
# returns logo_id on success
sub _check_logo_id {
    my ($self, $logo) = @_; # {{{

    croak 'Logo ID not numeric' unless $logo =~ m{^\d+$};
    croak 'Logo ID out of range' if $logo < 1 or $logo > 2;

    return $logo;
}
# }}}

# make sure logo_value is numeric and in (1 .. 256)
# returns logo_value on success
sub _check_logo_value {
    my ($self, $value) = @_; # {{{

    croak 'Logo value not numeric' unless $value =~ m{^\d+$};
    croak 'Logo value out of range' if $value < 1 or $value > 256;

    return $value;
}
# }}}

# return "id" oid for $logo
sub _oid_logo_id {
    my ($self, $logo) = @_; # {{{

    return OID_LOGO_BASE .'.'. (2*$logo-1) .'.0';
}
# }}}

# return "enabled" oid for $logo
sub _oid_logo_enab {
    my ($self, $logo) = @_; # {{{

    return OID_LOGO_BASE .'.'. (2*$logo) .'.0';
}
# }}}

1;
__END__

#=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT

Copyright (c) 2013 Christoph Weber <mehdorn@fem.tu-ilmenau.de>

=cut
