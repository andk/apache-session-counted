#############################################################################
#
# Apache::Session::Tree
# Apache persistent user sessions in the filesystem
# Copyright(c) 1998, 1999 Jeffrey William Baker (jeffrey@kathyandjeffrey.net)
# Distribute under the Artistic License
#
############################################################################

package Apache::Session::Counted;

use strict;
use vars qw(@ISA);

@ISA = qw(Apache::Session);

use Apache::Session;
use File::CounterFile;

{
  package Apache::Session::CountedStore;
  use base 'Apache::Session::TreeStore';
  use Symbol qw(gensym);
#  use vars qw(@ISA);
#  @ISA = qw(Apache::Session::TreeStore);

  sub insert { shift->SUPER::update(@_) };
  sub storefilename {
    my $self    = shift;
    my $session = shift;
    die "The argument 'Directory' for object storage must be passed as an argument"
	unless defined $session->{args}{Directory};
    my $dir = $session->{args}{Directory};
    my $levels = $session->{args}{DirLevels} || 0;
    # here we depart from TreeStore:
    my($file) = $session->{data}{_session_id} =~ /^([\da-f]+)/;
    die "Too short ID part '$file' in session ID'" if length($file)<8;
    while ($levels) {
      $file =~ s|((..){$levels})|$1/|;
      $levels--;
    }
    my $ret = "$dir/$file";
    $ret;
  }
}

sub get_object_store {
  my $self = shift;
  return new Apache::Session::CountedStore $self;
}

sub get_lock_manager {
  die "Should never be reached";
}

sub TIEHASH {
  my $class = shift;

  my $session_id = shift;
  my $args       = shift || {};

  # Make sure that the arguments to tie make sense
  # No. Don't Waste Time.
  # $class->validate_id($session_id);
  # if(ref $args ne "HASH") {
  #   die "Additional arguments should be in the form of a hash reference";
  # }

  #Set-up the data structure and make it an object
  #of our class

  my $self = {
	      args         => $args,

	      # no need to fill in what will be changed anyway:
	      # data         => { _session_id => $session_id },
	      # we always have read and write lock:

	      lock         => Apache::Session::READ_LOCK|Apache::Session::WRITE_LOCK,
	      lock_manager => undef,
	      object_store => undef,
	      status       => 0,
	     };

  bless $self, $class;

  #If a session ID was passed in, this is an old hash.
  #If not, it is a fresh one.

  if (defined $session_id) {
    $self->make_old;
    $self->restore;
    if ($session_id eq $self->{data}->{_session_id}) {
      # Fine. Validated. Kind of authenticated.
      # ready for a new session ID, keeping state otherwise.
      # Nothing to do (?)
    } else {
      # oops, somebody else tried this ID, don't show him data.
      delete $self->{data};
      $self->make_new;
    }
  }
  $self->{data}->{_session_id} = $self->generate_id();

  return $self;
}

sub generate_id {
  my $self = shift;
  # wants counterfile
  my $cf = $self->{args}{CounterFile} or
      die "Argument CounterFile needed in the attribute hash to the tie";
  my $c;
  eval { $c = File::CounterFile->new($cf,"0"); };
  if ($@) {
    warn "CounterFile problem. Retrying after removing $cf.";
    unlink $cf; # May fail. stupid enough that we are here.
    $c = File::CounterFile->new($cf,"0");
  }
  my $rhexid = sprintf "%08x", $c->inc;
  my $hexid = scalar reverse $rhexid; # optimized for treestore. Not
                                      # everything in one directory
  my $password = $self->SUPER::generate_id;
  $hexid . "_" . $password;
}

1;

=head1 NAME

Apache::Session::Counted - Session management via a File::CounterFile

=head1 SYNOPSYS

 tie %s, 'Apache::Session::Counted', $sessionid, {
                                Directory => <root of directory tree>,
                                DirLevels => <number of dirlevels>,
                                CounterFile => <filename for File::CounterFile>
                                                 }

=head1 DESCRIPTION

This session module is based on Apache::Session, but it persues a
different notion of a session, so you probably have to adjust your
expectations a little.

A session in this module only lasts from one request to the next. At
that point a new session starts. Data are not lost though, the only
thing that is lost from one request to the next is the session-ID. So
the only things you have to adjust in your code are those parts that
rely on the session-ID as a fixed token per user. Everything else
remains the same.

What this model buys you, is the following:

=over

=item storing state selectively

You need not store session data for each and every request of a
particular user. There are so many CGI requests that can easily be
handled with two hidden fields and do not need any session support on
the server, and there are others where you definitely want session
support. Both can appear within the same application. Counted allows
you to switch session writing on and off during your application
without much thinking.

=item counter

You get a counter for free which you can control just like
File::CounterFile (because it B<is> File::CounterFile).

=item cleanup

Your data storage area cleans up itself automatically. Whenever you
reset your counter via File::CounterFile, the storage area in use is
being reused. Old files are being overwritten in the same order they
were written.

=item performance

Additionally the notion of daisy-chained sessions simplifies the code
of the session handler itself quite a bit and it is quite likely that
this simplification results in an improved performance. There are less
file stats and less sections that need locking.

=back

As with other modules in the Apache::Session collection, the tied hash
contains a key <_session_id>. You must be aware that the value of this
hash entry is not the same as the one you passed in. So make sure that
you send your user the new session-id in your forms, not the old one.

=head1 PREREQUISITES

Apache::Session::Counted needs Apache::Session,
Apache::Session::TreeStore, and File::CounterFile, all available from the CPAN.

=head1 EXAMPLES

XXX Two examples should show the usage of a date string and the usage
of an external cronjob to influence counter and cleanup.

=head1 AUTHOR

Andreas Koenig <andreas.koenig@anima.de>

=head1 COPYRIGHT

This software is copyright(c) 1999 Andreas Koenig. It is free software
and can be used under the same terms as perl, i.e. either the GNU
Public Licence or the Artistic License.

=cut

