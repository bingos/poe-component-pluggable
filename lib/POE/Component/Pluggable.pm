package POE::Component::Pluggable;

use strict;
use warnings;
use POE::Component::Pluggable::Pipeline;
use POE::Component::Pluggable::Constants qw(:ALL);
use vars qw($VERSION);

$VERSION='1.04';

sub _pluggable_init {
  my $self = shift;
  my %opts = @_;
  $self->{'_pluggable_' . lc $_} = delete $opts{$_} for keys %opts;
  $self->{_pluggable_prefix} = 'pluggable_' unless $self->{_pluggable_prefix};
  $self->{_pluggable_types} = [] unless $self->{_pluggable_types} and ref $self->{_pluggable_types} eq 'ARRAY';
  return 1;
}

sub _pluggable_destroy {
  my $self = shift;
  $self->plugin_del( $_ ) for keys %{ $self->plugin_list() };
}

sub _pluggable_event {
  return;
}

sub _pluggable_process {
  my ($self, $type, $event, @args) = @_;
  my $pipeline = $self->pipeline;
  my $prefix = $self->{_pluggable_prefix};
  $event =~ s/^\Q$prefix\E//;
  my $sub = join '_', $type, $event;
  my $return = PLUGIN_EAT_NONE;
  my $self_ret = $return;

  if ( $self->can($sub) ) {
    eval { $self_ret = $self->$sub( $self, @args ) };
    warn "$@" if $@;
  }

  return $return if $self_ret == PLUGIN_EAT_PLUGIN;
  $return = PLUGIN_EAT_ALL if $self_ret == PLUGIN_EAT_CLIENT;
  return PLUGIN_EAT_ALL if $self_ret == PLUGIN_EAT_ALL;

  for my $plugin (@{ $pipeline->{PIPELINE} }) {
    next if $self eq $plugin;
    next
      unless $pipeline->{HANDLES}{$plugin}{$type}{$event}
      or $pipeline->{HANDLES}{$plugin}{$type}{all};

    my $ret = PLUGIN_EAT_NONE;

    if ( $plugin->can($sub) ) {
      eval { $ret = $plugin->$sub($self,@args) };
      warn "$sub call failed with $@\n" if $@ and $self->{_pluggable_debug};
    } elsif ( $plugin->can('_default') ) {
      eval { $ret = $plugin->_default($self,$sub,@args) };
      warn "_default call failed with $@\n" if $@ and $self->{_pluggable_debug};
    }

    return $return if $ret == PLUGIN_EAT_PLUGIN;
    $return = PLUGIN_EAT_ALL if $ret == PLUGIN_EAT_CLIENT;
    return PLUGIN_EAT_ALL if $ret == PLUGIN_EAT_ALL;
  }

  return $return;
}

# accesses the plugin pipeline
sub pipeline {
  my ($self) = @_;
  $self->{_PLUGINS} = POE::Component::Pluggable::Pipeline->new($self)
    unless UNIVERSAL::isa($self->{_PLUGINS}, 'POE::Component::Pluggable::Pipeline');
  return $self->{_PLUGINS};
}

# Adds a new plugin object
sub plugin_add {
  my ($self, $name, $plugin) = @_;
  my $pipeline = $self->pipeline;

  unless (defined $name and defined $plugin) {
    warn 'Please supply a name and the plugin object to be added!';
    return;
  }

  return $pipeline->push($name => $plugin);
}

# Removes a plugin object
sub plugin_del {
  my ($self, $name) = @_;

  unless (defined $name) {
    warn 'Please supply a name/object for the plugin to be removed!';
    return;
  }

  my $return = scalar $self->pipeline->remove($name);
  warn "$@\n" if $@;
  return $return;
}

# Gets the plugin object
sub plugin_get {
  my ($self, $name) = @_;  

  unless (defined $name) {
    warn 'Please supply a name/object for the plugin to be removed!';
    return;
  }

  return scalar $self->pipeline->get($name);
}

# Lists loaded plugins
sub plugin_list {
  my ($self) = @_;
  my $pipeline = $self->pipeline;
  my %return;

  for (@{ $pipeline->{PIPELINE} }) {
    $return{ $pipeline->{PLUGS}{$_} } = $_;
  }

  return \%return;
}

# Lists loaded plugins in order!
sub plugin_order {
  my ($self) = @_;
  return $self->pipeline->{PIPELINE};
}

sub plugin_register {
  my ($self, $plugin, $type, @events) = @_;
  my $pipeline = $self->pipeline;

  unless ( grep { $_ eq $type } @{ $self->{_pluggable_types} } ) {
    warn "That type: '$type', is not supported!";
    return;
  }

  unless (defined $plugin) {
    warn 'Please supply the plugin object to register!';
    return;
  }

  unless (@events) {
    warn 'Please supply at least one event to register!';
    return;
  }

  for my $ev (@events) {
    if (ref($ev) and ref($ev) eq "ARRAY") {
      @{ $pipeline->{HANDLES}{$plugin}{$type} }{ map lc, @$ev } = (1) x @$ev;
    }
    else {
      $pipeline->{HANDLES}{$plugin}{$type}{lc $ev} = 1;
    }
  }

  return 1;
}

sub plugin_unregister {
  my ($self, $plugin, $type, @events) = @_;
  my $pipeline = $self->pipeline;

  unless ( grep { $_ eq $type } @{ $self->{_pluggable_types} } ) {
    warn "That type: '$type', is not supported!";
    return;
  }

  unless (defined $plugin) {
    warn 'Please supply the plugin object to register!';
    return;
  }

  unless (@events) {
    warn 'Please supply at least one event to unregister!';
    return;
  }

  for my $ev (@events) {
    if (ref($ev) and ref($ev) eq "ARRAY") {
      for my $e (map lc, @$ev) {
        unless (delete $pipeline->{HANDLES}{$plugin}{$type}{$e}) {
          warn "The event '$e' does not exist!";
          next;
        }
      }
    }
    else {
      $ev = lc $ev;
      unless (delete $pipeline->{HANDLES}{$plugin}{$type}{$ev}) {
        warn "The event '$ev' does not exist!";
        next;
      }
    }
  }

  return 1;
}

1;
__END__

=head1 NAME

POE::Component::Pluggable - A base class for creating plugin enabled POE Components.

=head1 SYNOPSIS

  # A simple POE Component that sends ping events to registered sessions
  # every 30 seconds. A rather convoluted example to be honest.

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

=head1 DESCRIPTION

POE::Component::Pluggable is a base class for creating plugin enabled POE Components. It is a
generic port of L<POE::Component::IRC>'s plugin system.

If your component dispatches events to registered POE sessions then POE::Component::Pluggable may
be a good fit for you.

Basic use would involve subclassing POE::Component::Pluggable, then overriding _pluggable_event()
and inserting _pluggable_process() wherever you dispatch events from.

Users of your component can then load plugins using the plugin methods provided to handle events
generated by the component.

You may also use plugin style handlers within your component as _pluggable_process() will attempt to
process any events with local method calls first. The return value of these handlers has the same 
significance as the return value of 'normal' plugin handlers.

=head1 PRIVATE METHODS

Subclassing POE::Component::Pluggable gives your object the following 'private' methods:

=over

=item _pluggable_init

This should be called on your object after initialisation, but before you want to start processing plugins.
It accepts a number of argument/value pairs:

  'prefix', the prefix for your events;
  'types', an arrayref of the types of event that your poco will support;

Notes: 'prefix' should probably end with a '_'. The types specify the prefixes for plugin handlers. You can specify as many different types as you require. 

=item _pluggable_destroy

This should be called from any shutdown handler that your poco has. The method unloads any loaded plugins.

=item _pluggable_process

This should be called before events are dispatched to interested sessions. This gives pluggable a chance to
discard events if requested to by a plugin.

The first argument is a type, as specified to _pluggable_init().

  sub _dispatch {
    # stuff
    
    return 1 if $self->_pluggable_process( $type, $event, \( @args ) ) == PLUGIN_EAT_ALL;

    # dispatch event to interested sessions.
  }

This example demonstrates event arguments being passed as scalar refs to the plugin system. This 
enables plugins to mangle the arguments if necessary. 

=item _pluggable_event

This method should be overridden in your class so that pipeline can dispatch events through your event
dispatcher. Pipeline sends a prefixed 'plugin_add' and 'plugin_del' event whenever plugins are added or
removed, respectively.

  sub _pluggable_event {
     my $self = shift;
     $poe_kernel->post( $self->{session_id}, '__send_event', @_ );
  }

There is an example of this in the SYNOPSIS.

=back

=head1 PUBLIC METHODS

Subclassing POE::Component::Pluggable gives your object the following public methods:

=over

=item pipeline

Returns the L<POE::Component::Pluggable::Pipeline> object.

=item plugin_add

Accepts two arguments:

  The alias for the plugin
  The actual plugin object

The alias is there for the user to refer to it, as it is possible to have multiple
plugins of the same kind active in one POE::Component::Pluggable object.

This method goes through the pipeline's push() method.

 This method will call $plugin->plugin_register( $pluggable )

Returns the number of plugins now in the pipeline if plugin was initialized, undef
if not.

=item plugin_del

Accepts one argument:

  The alias for the plugin or the plugin object itself

This method goes through the pipeline's remove() method.

This method will call $plugin->plugin_unregister( $irc )

Returns the plugin object if the plugin was removed, undef if not.

=item plugin_get

Accepts one argument:

  The alias for the plugin

This method goes through the pipeline's get() method.

Returns the plugin object if it was found, undef if not.

=item plugin_list

Has no arguments.

Returns a hashref of plugin objects, keyed on alias, or an empty list if there are no
plugins loaded.

=item plugin_order

Has no arguments.

Returns an arrayref of plugin objects, in the order which they are encountered in the
pipeline.

=item plugin_register

Accepts the following arguments:

  The plugin object
  The type of the hook ( the hook types are specified with _pluggable_init()'s 'types' )
  The event name(s) to watch

The event names can be as many as possible, or an arrayref. They correspond
to the prefixed events and naturally, arbitrary events too.

You do not need to supply events with the prefix in front of them, just the names.

It is possible to register for all events by specifying 'all' as an event.

Returns 1 if everything checked out fine, undef if something's seriously wrong

=item plugin_unregister

Accepts the following arguments:

  The plugin object
  The type of the hook ( the hook types are specified with _pluggable_init()'s 'types' )
  The event name(s) to unwatch

The event names can be as many as possible, or an arrayref. They correspond
to the prefixed events and naturally, arbitrary events too.

You do not need to supply events with the prefix in front of them, just the names.

It is possible to register for all events by specifying 'all' as an event.

Returns 1 if all the event name(s) was unregistered, undef if some was not found.

=back

=head1 PLUGINS

The basic anatomy of a pluggable plugin is:

        # Import the constants, of course you could provide your own 
        # constants as long as they map correctly.
        use POE::Component::Pluggable::Constants qw( :ALL );

        # Our constructor
        sub new {
                ...
        }

        # Required entry point for pluggable plugins
        sub plugin_register {
                my( $self, $pluggable ) = @_;

                # Register events we are interested in
                $pluggable->plugin_register( $self, 'SERVER', qw(something whatever) );

                # Return success
                return 1;
        }

        # Required exit point for pluggable
        sub plugin_unregister {
                my( $self, $pluggable ) = @_;

                # Pluggable will automatically unregister events for the plugin

                # Do some cleanup...

                # Return success
                return 1;
        }

        sub _default {
                my( $self, $pluggable, $event ) = splice @_, 0, 3;

                print "Default called for $event\n";

                # Return an exit code
                return PLUGIN_EAT_NONE;
        }

The constants used can be called anything. You can provide your own even. Check 
L<POE::Component::Pluggable::Constants> for details.

=head1 TODO

Better documentation >:]

=head1 AUTHOR

Chris 'BinGOs' Williams <chris@bingosnet.co.uk>

=head1 LICENSE

Copyright C<(c)> Chris Williams, Apocalypse and Jeff Pinyan

This module may be used, modified, and distributed under the same terms as Perl itself. Please see the license that came with your Perl distribution for details.

=head1 KUDOS

APOCAL for writing the original L<POE::Component::IRC> plugin system.

japhy for writing L<POE::Component::IRC::Pipeline> which improved on it.

All the happy chappies who have contributed to POE::Component::IRC over the 
years ( yes, it has been years ) refining and tweaking the plugin system.

=head1 SEE ALSO

L<POE::Component::IRC>

L<POE::Component::Pluggable::Pipeline>

Both L<POE::Component::Client::NNTP> and L<POE::Component::Server::NNTP> use this module
as a base, examination of their source may yield further understanding.
