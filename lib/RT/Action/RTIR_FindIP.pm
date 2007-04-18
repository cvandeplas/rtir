package RT::Action::RTIR_FindIP;

use strict;
use warnings;

use base qw(RT::Action::RTIR);

use Regexp::Common qw(net);
use Regexp::Common::net::CIDR ();
use Net::CIDR ();

=head2 Prepare

Always run this.

=cut

sub Prepare { return 1 }

=head2 Commit

Search for IP addresses in the transaction's content.

=cut

sub Commit {
    my $self = shift;
    my $ticket = $self->TicketObj;

    my $cf = $ticket->LoadCustomFieldByIdentifier('_RTIR_IP');
    return 1 unless $cf && $cf->id;

    my $attach = $self->TransactionObj->ContentObj;
    return 1 unless $attach && $attach->id;

    my %existing;
    for( @{$cf->ValuesForObject( $ticket )->ItemsArrayRef} ) {
        $existing{ $_->Content } =  1;
    }

    my @IPs = ( $attach->Content =~ /(?<!\d)($RE{net}{IPv4})(?!\d)(?!\/(3[0-2]|[1-2]?[0-9]))/go );
    $self->AddIP(
        IP          => $_,
        CustomField => $cf,
        Skip        => \%existing,
    ) foreach @IPs;

    my @CIDRs = ( $attach->Content =~ /$RE{net}{CIDR}{IPv4}{-keep}/go );
    while ( my ($addr, $bits) = splice @CIDRs, 0, 2 ) {
        my $cidr = join( '.', map $_||0, (split /\./, $addr)[0..3] ) ."/$bits";
        my $range = (Net::CIDR::cidr2range( $cidr ))[0] or next;
        $self->AddIP( IP => $range, CustomField => $cf, Skip => \%existing );
    }

    return 1;
}

sub AddIP {
    my $self = shift;
    my %arg = ( CustomField => undef, IP => undef, Skip => {}, @_ );
    return if !$arg{'IP'} || $arg{'Skip'}->{ $arg{'IP'} }++
        || $arg{'Skip'}->{ $arg{'IP'} .'-'. $arg{'IP'} }++;

    my ($status, $msg) = $self->TicketObj->AddCustomFieldValue(
        Value => $arg{'IP'},
        Field => $arg{'CustomField'},
    );
    $RT::Logger->error("Couldn't add IP address: $msg") unless $status;

    return;
}

1;