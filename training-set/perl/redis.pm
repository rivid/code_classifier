package Redis;

# ABSTRACT: Perl binding for Redis database
# VERSION
# AUTHORITY

use warnings;
use strict;

use IO::Socket::INET;
use IO::Socket::UNIX;
use IO::Socket::Timeout;
use IO::Select;
use IO::Handle;
use Fcntl qw( O_NONBLOCK F_SETFL );
use Errno ();
use Data::Dumper;
use Carp;
use Try::Tiny;
use Scalar::Util ();

use Redis::Sentinel;

use constant WIN32       => $^O =~ /mswin32/i;
use constant EWOULDBLOCK => eval {Errno::EWOULDBLOCK} || -1E9;
use constant EAGAIN      => eval {Errno::EAGAIN} || -1E9;
use constant EINTR       => eval {Errno::EINTR} || -1E9;
use constant BUFSIZE     => 4096;

sub _maybe_enable_timeouts {
    my ($self, $socket) = @_;
    $socket or return;
    exists $self->{read_timeout} || exists $self->{write_timeout}
      or return $socket;
    IO::Socket::Timeout->enable_timeouts_on($socket);
    defined $self->{read_timeout}
      and $socket->read_timeout($self->{read_timeout});
    defined $self->{write_timeout}
      and $socket->write_timeout($self->{write_timeout});
    $socket;
}

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  $self->{__buf} = '';
  $self->{debug} = $args{debug} || $ENV{REDIS_DEBUG};

  ## Deal with REDIS_SERVER ENV
  if ($ENV{REDIS_SERVER} && ! exists $args{sock} && ! exists $args{server} && ! exists $args{sentinel}) {
    if ($ENV{REDIS_SERVER} =~ m!^/!) {
      $args{sock} = $ENV{REDIS_SERVER};
    }
    elsif ($ENV{REDIS_SERVER} =~ m!^unix:(.+)!) {
      $args{sock} = $1;
    }
    elsif ($ENV{REDIS_SERVER} =~ m!^(?:tcp:)?(.+)!) {
      $args{server} = $1;
    }
  }

  defined $args{$_}
    and $self->{$_} = $args{$_} for 
      qw(password on_connect name no_auto_connect_on_new cnx_timeout
         write_timeout read_timeout sentinels_cnx_timeout sentinels_write_timeout
         sentinels_read_timeout no_sentinels_list_update);

  $self->{reconnect}     = $args{reconnect} || 0;
  $self->{conservative_reconnect} = $args{conservative_reconnect} || 0;
  $self->{every}         = $args{every} || 1000;

  if (exists $args{sock}) {
    $self->{server} = $args{sock};
    $self->{builder} = sub {
        my ($self) = @_;
        $self->_maybe_enable_timeouts(
            IO::Socket::UNIX->new(
                Peer => $self->{server},
                ( $self->{cnx_timeout} ? ( Timeout => $self->{cnx_timeout} ): () ),
            )
        );
    };
  } elsif ($args{sentinels}) {
      $self->{sentinels} = $args{sentinels};

      ref $self->{sentinels} eq 'ARRAY'
        or croak("'sentinels' param must be an ArrayRef");

      defined($self->{service} = $args{service})
        or croak("Need 'service' name when using 'sentinels'!");

      $self->{builder} = sub {
          my ($self) = @_;
          # try to connect to a sentinel
          my $status;
          foreach my $sentinel_address (@{$self->{sentinels}}) {
              my $sentinel = eval {
                  Redis::Sentinel->new(
                      server => $sentinel_address,
                      cnx_timeout   => (   exists $self->{sentinels_cnx_timeout}
                                         ? $self->{sentinels_cnx_timeout}   : 0.1),
                      read_timeout  => (   exists $self->{sentinels_read_timeout}
                                         ? $self->{sentinels_read_timeout}  : 1  ),
                      write_timeout => (   exists $self->{sentinels_write_timeout}
                                         ? $self->{sentinels_write_timeout} : 1  ),
                  )
              } or next;
              my $server_address = $sentinel->get_service_address($self->{service});
              defined $server_address
                or $status ||= "Sentinels don't know this service",
                   next;
              $server_address eq 'IDONTKNOW'
                and $status = "service is configured in one Sentinel, but was never reached",
                    next;

              # we found the service, set the server
              $self->{server} = $server_address;

              if (! $self->{no_sentinels_list_update} ) {
                  # move the elected sentinel at the front of the list and add
                  # additional sentinels
                  my $idx = 2;
                  my %h = ( ( map { $_ => $idx++ } @{$self->{sentinels}}),
                            $sentinel_address => 1,
                          );
                  $self->{sentinels} = [
                      ( sort { $h{$a} <=> $h{$b} } keys %h ), # sorted existing sentinels,
                      grep { ! $h{$_}; }                      # list of unknown
                      map { +{ @$_ }->{name}; }               # names of
                      $sentinel->sentinel(                    # sentinels 
                        sentinels => $self->{service}         # for this service
                      )
                  ];
              }
              
              return $self->_maybe_enable_timeouts(
                  IO::Socket::INET->new(
                      PeerAddr => $server_address,
                      Proto    => 'tcp',
                      ( $self->{cnx_timeout} ? ( Timeout => $self->{cnx_timeout} ) : () ),
                  )
              );
          }
          croak($status || "failed to connect to any of the sentinels");
      };
  } else {
    $self->{server} = exists $args{server} ? $args{server} : '127.0.0.1:6379';
    $self->{builder} = sub {
        my ($self) = @_;
        $self->_maybe_enable_timeouts(
            IO::Socket::INET->new(
                PeerAddr => $self->{server},
                Proto    => 'tcp',
                ( $self->{cnx_timeout} ? ( Timeout => $self->{cnx_timeout} ) : () ),
            )
        );
    };
  }

  $self->{is_subscriber} = 0;
  $self->{subscribers}   = {};

  $self->connect unless $args{no_auto_connect_on_new};

  return $self;
}

sub is_subscriber { $_[0]{is_subscriber} }

sub select {
  my $self = shift;
  my $database = shift;
  my $ret = $self->__std_cmd('select', $database, @_);
  $self->{current_database} = $database;
  $ret;
}

### we don't want DESTROY to fallback into AUTOLOAD
sub DESTROY { }


### Deal with common, general case, Redis commands
our $AUTOLOAD;

sub AUTOLOAD {
  my $command = $AUTOLOAD;
  $command =~ s/.*://;

  my $method = sub { shift->__std_cmd($command, @_) };

  # Save this method for future calls
  no strict 'refs';
  *$AUTOLOAD = $method;

  goto $method;
}

sub __std_cmd {
  my $self    = shift;
  my $command = shift;

  $self->__is_valid_command($command);

  my $cb = @_ && ref $_[-1] eq 'CODE' ? pop : undef;

  # If this is an EXEC command, in pipelined mode, and one of the commands
  # executed in the transaction yields an error, we must collect all errors
  # from that command, rather than throwing an exception immediately.
  my $uc_command = uc($command);
  my $collect_errors = $cb && $uc_command eq 'EXEC';

  if ($uc_command eq 'MULTI') {
      $self->{__inside_transaction} = 1;
  } elsif ($uc_command eq 'EXEC' || $uc_command eq 'DISCARD') {
      delete $self->{__inside_transaction};
      delete $self->{__inside_watch};
  } elsif ($uc_command eq 'WATCH') {
      $self->{__inside_watch} = 1;
  } elsif ($uc_command eq 'UNWATCH') {
      delete $self->{__inside_watch};
  }

  ## Fast path, no reconnect;
  $self->{reconnect}
    or return $self->__run_cmd($command, $collect_errors, undef, $cb, @_);

  my @cmd_args = @_;
  $self->__with_reconnect(
    sub {
      $self->__run_cmd($command, $collect_errors, undef, $cb, @cmd_args);
    }
  );
}

sub __with_reconnect {
  my ($self, $cb) = @_;

  ## Fast path, no reconnect
  $self->{reconnect}
    or return $cb->();

  return &try(
    $cb,
    catch {
      ref($_) eq 'Redis::X::Reconnect'
        or die $_;

      $self->{__inside_transaction} || $self->{__inside_watch}
        and croak("reconnect disabled inside transaction or watch");

      scalar @{$self->{queue} || []} && $self->{conservative_reconnect}
        and croak("reconnect disabled while responses are pending and conservative reconnect mode enabled");

      $self->connect;
      $cb->();
    }
  );
}

sub __run_cmd {
  my ($self, $command, $collect_errors, $custom_decode, $cb, @args) = @_;

  my $ret;
  my $wrapper = $cb && $custom_decode
    ? sub {
      my ($reply, $error) = @_;
      $cb->(scalar $custom_decode->($reply), $error);
    }
    : $cb || sub {
      my ($reply, $error) = @_;
      croak "[$command] $error, " if defined $error;
      $ret = $reply;
    };

  $self->__send_command($command, @args);
  push @{ $self->{queue} }, [$command, $wrapper, $collect_errors];

  return 1 if $cb;

  $self->wait_all_responses;
  return
      $custom_decode ? $custom_decode->($ret, !wantarray)
    : wantarray && ref $ret eq 'ARRAY' ? @$ret
    :                                    $ret;
}

sub wait_all_responses {
  my ($self) = @_;

  my $queue = $self->{queue};
  $self->wait_one_response while @$queue;

  return;
}

sub wait_one_response {
  my ($self) = @_;

  my $handler = shift @{ $self->{queue} };
  return unless $handler;

  my ($command, $cb, $collect_errors) = @$handler;
  $cb->($self->__read_response($command, $collect_errors));

  return;
}


### Commands with extra logic
sub quit {
  my ($self) = @_;
  return unless $self->{sock};

  croak "[quit] only works in synchronous mode, "
    if @_ && ref $_[-1] eq 'CODE';

  try {
    $self->wait_all_responses;
    $self->__send_command('QUIT');
  };

  $self->__close_sock() if $self->{sock};

  return 1;
}

sub shutdown {
  my ($self) = @_;
  $self->__is_valid_command('SHUTDOWN');

  croak "[shutdown] only works in synchronous mode, "
    if @_ && ref $_[-1] eq 'CODE';

  return unless $self->{sock};

  $self->wait_all_responses;
  $self->__send_command('SHUTDOWN');
  $self->__close_sock() || croak("Can't close socket: $!");

  return 1;
}

sub ping {
  my $self = shift;
  $self->__is_valid_command('PING');

  croak "[ping] only works in synchronous mode, "
    if @_ && ref $_[-1] eq 'CODE';

  return unless exists $self->{sock};

  $self->wait_all_responses;
  return scalar try {
    $self->__std_cmd('PING');
  }
  catch {
    $self->__close_sock();
    return;
  };
}

sub info {
  my $self = shift;
  $self->__is_valid_command('INFO');

  my $custom_decode = sub {
    my ($reply) = @_;
    return $reply if !defined $reply || ref $reply;
    return { map { split(/:/, $_, 2) } grep {/^[^#]/} split(/\r\n/, $reply) };
  };

  my $cb = @_ && ref $_[-1] eq 'CODE' ? pop : undef;

  ## Fast path, no reconnect
  return $self->__run_cmd('INFO', 0, $custom_decode, $cb, @_)
    unless $self->{reconnect};

  my @cmd_args = @_;
  $self->__with_reconnect(
    sub {
      $self->__run_cmd('INFO', 0, $custom_decode, $cb, @cmd_args);
    }
  );
}

sub keys {
  my $self = shift;
  $self->__is_valid_command('KEYS');

  my $custom_decode = sub {
    my ($reply, $synchronous_scalar) = @_;

    ## Support redis <= 1.2.6
    $reply = [split(/\s/, $reply)] if defined $reply && !ref $reply;

    return ref $reply && ($synchronous_scalar || wantarray) ? @$reply : $reply;
  };

  my $cb = @_ && ref $_[-1] eq 'CODE' ? pop : undef;

  ## Fast path, no reconnect
  return $self->__run_cmd('KEYS', 0, $custom_decode, $cb, @_)
    unless $self->{reconnect};

  my @cmd_args = @_;
  $self->__with_reconnect(
    sub {
      $self->__run_cmd('KEYS', 0, $custom_decode, $cb, @cmd_args);
    }
  );
}


### PubSub
sub wait_for_messages {
  my ($self, $timeout) = @_;

  my $s = IO::Select->new;

  my $count = 0;


  my $e;

  try {
    $self->__with_reconnect( sub {

      # the socket can be changed due to reconnection, so get it each time
      my $sock = $self->{sock};
      $s->remove($s->handles);
      $s->add($sock);

      while ($s->can_read($timeout)) {      
        my $has_stuff = $self->__try_read_sock($sock);
        # If the socket is ready to read but there is nothing to read, ( so
        # it's an EOF ), try to reconnect.
        defined $has_stuff
          or $self->__throw_reconnect('EOF from server');

        do {
          my ($reply, $error) = $self->__read_response('WAIT_FOR_MESSAGES');
          croak "[WAIT_FOR_MESSAGES] $error, " if defined $error;
          $self->__process_pubsub_msg($reply);
          $count++;

          # if __try_read_sock() return 0 (no data)
          # or undef ( socket became EOF), back to select until timeout
        } while ($self->{__buf} || $self->__try_read_sock($sock));
      }
    
    });

  } catch {
    $e = $_;
};

# if We had an error and it was not an EOF, die
defined $e && $e ne 'EOF from server'
  and die $e;

  return $count;
}

sub __subscription_cmd {
  my $self    = shift;
  my $pr      = shift;
  my $unsub   = shift;
  my $command = shift;
  my $cb      = pop;

  croak("Missing required callback in call to $command(), ")
    unless ref($cb) eq 'CODE';

  $self->wait_all_responses;

  my @subs = @_;
  $self->__with_reconnect(
    sub {
      $self->__throw_reconnect('Not connected to any server')
        unless $self->{sock};

      @subs = $self->__process_unsubscribe_requests($cb, $pr, @subs)
        if $unsub;
      return unless @subs;

      $self->__send_command($command, @subs);

      my %cbs = map { ("${pr}message:$_" => $cb) } @subs;
      return $self->__process_subscription_changes($command, \%cbs);
    }
  );
}

sub subscribe    { shift->__subscription_cmd('',  0, subscribe    => @_) }
sub psubscribe   { shift->__subscription_cmd('p', 0, psubscribe   => @_) }
sub unsubscribe  { shift->__subscription_cmd('',  1, unsubscribe  => @_) }
sub punsubscribe { shift->__subscription_cmd('p', 1, punsubscribe => @_) }

sub __process_unsubscribe_requests {
  my ($self, $cb, $pr, @unsubs) = @_;
  my $subs = $self->{subscribers};

  my @subs_to_unsubscribe;
  for my $sub (@unsubs) {
    my $key = "${pr}message:$sub";
    my $cbs = $subs->{$key} = [grep { $_ ne $cb } @{ $subs->{$key} }];
    next if @$cbs;

    delete $subs->{$key};
    push @subs_to_unsubscribe, $sub;
  }

  return @subs_to_unsubscribe;
}

sub __process_subscription_changes {
  my ($self, $cmd, $expected) = @_;
  my $subs = $self->{subscribers};

  while (%$expected) {
    my ($m, $error) = $self->__read_response($cmd);
    croak "[$cmd] $error, " if defined $error;

    ## Deal with pending PUBLISH'ed messages
    if ($m->[0] =~ /^p?message$/) {
      $self->__process_pubsub_msg($m);
      next;
    }

    my ($key, $unsub) = $m->[0] =~ m/^(p)?(un)?subscribe$/;
    $key .= "message:$m->[1]";
    my $cb = delete $expected->{$key};

    push @{ $subs->{$key} }, $cb unless $unsub;

    $self->{is_subscriber} = $m->[2];
  }
}

sub __process_pubsub_msg {
  my ($self, $m) = @_;
  my $subs = $self->{subscribers};

  my $sub   = $m->[1];
  my $cbid  = "$m->[0]:$sub";
  my $data  = pop @$m;
  my $topic = defined $m->[2] ? $m->[2] : $sub;

  if (!exists $subs->{$cbid}) {
    warn "Message for topic '$topic' ($cbid) without expected callback, ";
    return;
  }

  $_->($data, $topic, $sub) for @{ $subs->{$cbid} };

  return 1;

}


### Mode validation
sub __is_valid_command {
  my ($self, $cmd) = @_;

  croak("Cannot use command '$cmd' while in SUBSCRIBE mode, ")
    if $self->{is_subscriber};
}


### Socket operations
sub connect {
  my ($self) = @_;
  delete $self->{sock};
  delete $self->{__inside_watch};
  delete $self->{__inside_transaction};

  # Suppose we have at least one command response pending, but we're about
  # to reconnect.  The new connection will never get a response to any of
  # the pending commands, so delete all those pending responses now.
  $self->{queue} = [];
  $self->{pid}   = $$;

  ## Fast path, no reconnect
  return $self->__build_sock() unless $self->{reconnect};

  ## Use precise timers on reconnections
  require Time::HiRes;
  my $t0 = [Time::HiRes::gettimeofday()];

  ## Reconnect...
  while (1) {
    eval { $self->__build_sock };

    last unless $@;    ## Connected!
    die if Time::HiRes::tv_interval($t0) > $self->{reconnect};    ## Timeout
    Time::HiRes::usleep($self->{every});                          ## Retry in...
  }

  return;
}

sub __build_sock {
  my ($self) = @_;

  $self->{sock} = $self->{builder}->($self)
    || croak("Could not connect to Redis server at $self->{server}: $!");

  $self->{__buf} = '';

  if (exists $self->{password}) {
    try { $self->auth($self->{password}) }
    catch {
      $self->{reconnect} = 0;
      croak("Redis server refused password");
    };
  }

  $self->__on_connection;

  return;
}

sub __close_sock {
  my ($self) = @_;
  $self->{__buf} = '';
  delete $self->{__inside_watch};
  delete $self->{__inside_transaction};
  return close(delete $self->{sock});
}

sub __on_connection {

    my ($self) = @_;

    # If we are in PubSub mode we shouldn't perform any command besides
    # (p)(un)subscribe
    if (! $self->{is_subscriber}) {
      defined $self->{name}
        and try {
            my $n = $self->{name};
            $n = $n->($self) if ref($n) eq 'CODE';
            $self->client_setname($n) if defined $n;
        };
  
      defined $self->{current_database}
        and $self->select($self->{current_database});
    }

    foreach my $topic (CORE::keys(%{$self->{subscribers}})) {
      if ($topic =~ /(p?message):(.*)$/ ) {
        my ($key, $channel) = ($1, $2);
        if ($key eq 'message') {
            $self->__send_command('subscribe', $channel);
            my (undef, $error) = $self->__read_response('subscribe');
            defined $error
              and croak "[subscribe] $error";
        } else {
            $self->__send_command('psubscribe', $channel);
            my (undef, $error) = $self->__read_response('psubscribe');
            defined $error
              and croak "[psubscribe] $error";
        }
      }
    }

    defined $self->{on_connect}
      and $self->{on_connect}->($self);

}


sub __send_command {
  my $self = shift;
  my $cmd  = uc(shift);
  my $deb  = $self->{debug};

  # if already connected but after a fork, reconnect
  if ($self->{sock} && ($self->{pid} // 0) != $$) {
    $self->connect;
  }

  my $sock = $self->{sock}
    || $self->__throw_reconnect('Not connected to any server');

  warn "[SEND] $cmd ", Dumper([@_]) if $deb;

  ## Encode command using multi-bulk format
  my @cmd     = split /_/, $cmd;
  my $n_elems = scalar(@_) + scalar(@cmd);
  my $buf     = "\*$n_elems\r\n";
  for my $bin (@cmd, @_) {
    utf8::downgrade($bin, 1)
      or croak "command sent is not an octet sequence in the native encoding (Latin-1). Consider using debug mode to see the command itself.";
    $buf .= defined($bin) ? '$' . length($bin) . "\r\n$bin\r\n" : "\$-1\r\n";
  }

  ## Check to see if socket was closed: reconnect on EOF
  my $status = $self->__try_read_sock($sock);
  $self->__throw_reconnect('Not connected to any server')
    unless defined $status;

  ## Send command, take care for partial writes
  warn "[SEND RAW] $buf" if $deb;
  while ($buf) {
    my $len = syswrite $sock, $buf, length $buf;
    $self->__throw_reconnect("Could not write to Redis server: $!")
      unless defined $len;
    substr $buf, 0, $len, "";
  }

  return;
}

sub __read_response {
  my ($self, $cmd, $collect_errors) = @_;

  croak("Not connected to any server") unless $self->{sock};

  local $/ = "\r\n";

  ## no debug => fast path
  return $self->__read_response_r($cmd, $collect_errors) unless $self->{debug};

  my ($result, $error) = $self->__read_response_r($cmd, $collect_errors);
  warn "[RECV] $cmd ", Dumper($result, $error);
  return $result, $error;
}

sub __read_response_r {
  my ($self, $command, $collect_errors) = @_;

  my ($type, $result) = $self->__read_line;

  if ($type eq '-') {
    return undef, $result;
  }
  elsif ($type eq '+' || $type eq ':') {
    return $result, undef;
  }
  elsif ($type eq '$') {
    return undef, undef if $result < 0;
    return $self->__read_len($result + 2), undef;
  }
  elsif ($type eq '*') {
    return undef, undef if $result < 0;

    my @list;
    while ($result--) {
      my @nested = $self->__read_response_r($command, $collect_errors);
      if ($collect_errors) {
        push @list, \@nested;
      }
      else {
        croak "[$command] $nested[1], " if defined $nested[1];
        push @list, $nested[0];
      }
    }
    return \@list, undef;
  }
  else {
    croak "unknown answer type: $type ($result), ";
  }
}

sub __read_line {
  my $self = $_[0];
  my $sock = $self->{sock};

  my $data = $self->__read_line_raw;
  croak("Error while reading from Redis server: $!")
    unless defined $data;

  chomp $data;
  warn "[RECV RAW] '$data'" if $self->{debug};

  my $type = substr($data, 0, 1, '');
  return ($type, $data);
}

sub __read_line_raw {
  my $self = $_[0];
  my $sock = $self->{sock};
  my $buf = \$self->{__buf};

  if (length $$buf) {
    my $idx = index($$buf, "\r\n");
    $idx >= 0 and return substr($$buf, 0, $idx + 2, '');
  }

  while (1) {
    my $bytes = sysread($sock, $$buf, BUFSIZE, length($$buf));
    next if !defined $bytes && $! == EINTR;
    return unless defined $bytes && $bytes;

    # start looking for \r\n where we stopped last time
    # extracting one is required to handle corner case
    # where \r\n are split and therefore read by two conseqent sysreads
    my $idx = index($$buf, "\r\n", length($$buf) - $bytes - 1);
    $idx >= 0 and return substr($$buf, 0, $idx + 2, '');
  }
}

sub __read_len {
  my ($self, $len) = @_;
  my $buf = \$self->{__buf};
  my $buflen = length($$buf);

  if ($buflen < $len) {
    my $to_read = $len - $buflen;
    while ($to_read > 0) {
      my $bytes = sysread($self->{sock}, $$buf, BUFSIZE, length($$buf));
      next if !defined $bytes && $! == EINTR;
      croak("Error while reading from Redis server: $!") unless defined $bytes;
      croak("Redis server closed connection") unless $bytes;
      $to_read -= $bytes;
    }
  }

  my $data = substr($$buf, 0, $len, '');
  chomp $data;
  warn "[RECV RAW] '$data'" if $self->{debug};

  return $data;
}

sub __try_read_sock {
  my ($self, $sock) = @_;
  my $data = '';

  while (1) {
      # WIN32 doesn't support MSG_DONTWAIT,
      # need to swith fh to nonblockng mode manually.
      # For Unix still use MSG_DONTWAIT because of fewer syscalls
      my ($res, $err);
      if (WIN32) {
          __fh_nonblocking_win32($sock, 1);
          $res = recv($sock, $data, BUFSIZE, 0);
          $err = 0 + $!;
          __fh_nonblocking_win32($sock, 0);
      } else {
          $res = recv($sock, $data, BUFSIZE, MSG_DONTWAIT);
          $err = 0 + $!;
      }

      if (defined $res) {
        ## have read some data
        if (length($data)) {
            $self->{__buf} .= $data;
            return 1;
        }

        ## no data but also no error means EOF
        return;
      }

      next if $err && $err == EINTR;

      ## Keep going if nothing there, but socket is alive
      return 0 if $err and ($err == EWOULDBLOCK or $err == EAGAIN);

      ## result is undef but err is 0? should never happen
      return if $err == 0;

      ## For everything else, there is Mastercard...
      croak("Unexpected error condition $err/$^O, please report this as a bug");
  }
}

## Copied from AnyEvent::Util
sub __fh_nonblocking_win32 {
    ioctl $_[0], 0x8004667e, pack "L", $_[1];
}

##########################
# I take exception to that

sub __throw_reconnect {
  my ($self, $m) = @_;
  die bless(\$m, 'Redis::X::Reconnect') if $self->{reconnect};
  die $m;
}


1;    # End of Redis.pm

__END__