{
  package SimplePoCo;

  use strict;
  use base qw(POE::Component::Pluggable);
  use POE;
  use POE::Component::Pluggable::Constants qw(:ALL);

  sub spawn {
    my $package = shift;
    my %opts = @_;
    $opts{lc $_} = delete $opts{$_} for keys %opts;
    my $self = bless \%opts, $package;
    $self->_pluggable_init( prefix => 'simplepoco_' );
    $self->{session_id} = POE::Session->create(
	object_states => [
		$self => { shutdown => '_shutdown' },
		$self => [qw(_send_ping _start register unregister __send_event)],
	],
	heap => $self,
    )->ID();
    return $self;
  }

  sub shutdown {
    my $self = shift;
    $poe_kernel->post( $self->{session_id}, 'shutdown' );
  }

  sub _pluggable_event {
    my $self = shift;
    $poe_kernel->post( $self->{session_id}, '__send_event', @_ );
  }

  sub _start {
    my ($kernel,$self) = @_[KERNEL,OBJECT];
    $self->{session_id} = $_[SESSION]->ID();
    if ( $self->{alias} ) {
	$kernel->alias_set( $self->{alias} );
    }
    else {
	$kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
    }
    $kernel->delay( '_send_ping', $self->{time} || 300 );
    return;
  }

  sub _shutdown {
    my ($kernel,$self) = @_[KERNEL,OBJECT];
    $self->_pluggable_destroy();
    $kernel->alarm_remove_all();
    $self->alias_remove($_) for $kernel->alias_list();
    $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ ) unless $self->{alias};
    $kernel->refcount_decrement( $_, __PACKAGE__ ) for keys %{ $self->{sessions} };
    return;
  }

  sub register {
    my ($kernel,$sender,$self) = @_[KERNEL,SENDER,OBJECT];
    my $sender_id = $sender->ID();
    $self->{sessions}->{ $sender_id }++;
    if ( $self->{sessions}->{ $sender_id } == 1 ) { 
      $kernel->refcount_increment( $sender_id, __PACKAGE__ );
      $kernel->yield( __send_event => $self->{_pluggable_prefix} . 'registered', $sender_id );
    }
    return;
  }

  sub unregister {
    my ($kernel,$sender,$self) = @_[KERNEL,SENDER,OBJECT];
    my $sender_id = $sender->ID();
    my $record = delete $self->{sessions}->{ $sender_id };
    if ( $record ) {
      $kernel->refcount_decrement( $sender_id, __PACKAGE__ );
      $kernel->yield( __send_event => $self->{_pluggable_prefix} . 'unregistered', $sender_id );
    }
    return;
  }

  sub __send_event {
    my ($kernel,$self,$event,@args) = @_[KERNEL,OBJECT,ARG0,ARG1..$#_];

    return 1 if $self->_pluggable_process( 'PING', $event, \( @args ) ) == PLUGIN_EAT_ALL;

    $kernel->post( $_, $event, @args ) for keys %{ $self->{sessions} };
  }

  sub _send_ping {
    my ($kernel,$self) = @_[KERNEL,OBJECT];
    my $event = $self->{_pluggable_prefix} . 'ping';
    my @args = ('Wake up sleepy');
    $kernel->yield( '__send_event', $event, @args );
    $kernel->delay( '_send_ping', $self->{time} || 300 );
    return;
  }
}

use POE;

my $pluggable = SimplePoCo->spawn( alias => 'pluggable', time => 30 );

POE::Session->create(
	package_states => [
		'main' => [qw(_start simplepoco_registered simplepoco_ping)],
	],
);

$poe_kernel->run();
exit 0;

sub _start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $kernel->post( 'pluggable', 'register' );
  return;
}

sub simplepoco_registered {
  print "Yay, we registered\n";
  return;
}

sub simplepoco_ping {
  my ($sender,$text) = @_[SENDER,ARG0];
  print "Got '$text' from ", $sender->ID, "\n";
  return;
}
