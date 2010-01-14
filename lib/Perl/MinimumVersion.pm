package Perl::MinimumVersion;

=pod

=head1 NAME

Perl::MinimumVersion - Find a minimum required version of perl for Perl code

=head1 SYNOPSIS

  # Create the version checking object
  $object = Perl::MinimumVersion->new( $filename );
  $object = Perl::MinimumVersion->new( \$source  );
  $object = Perl::MinimumVersion->new( $ppi_document );

  # Find the minimum version
  $version = $object->minimum_version;

=head1 DESCRIPTION

C<Perl::MinimumVersion> takes Perl source code and calculates the minimum
version of perl required to be able to run it. Because it is based on
L<PPI>, it can do this without having to actually load the code.

Currently it tests both the syntax of your code, and the use of explicit
version dependencies such as C<require 5.005>.

Future plans are to also add support for tracing module dependencies.

Using C<Perl::MinimumVersion> is dead simple, the synopsis pretty much
covers it.

=head1 METHODS

=cut

use 5.006;
use strict;
use version      ();
use Carp         ();
use Exporter     ();
use List::Util   ();
use Params::Util ('_INSTANCE', '_CLASS');
use PPI::Util    ('_Document');
use PPI          ();
use Perl::Critic::Utils 1.104 qw{
	:characters
	:severities
	:data_conversion
	:classification
	:ppi
};

use Perl::MinimumVersion::Reason ();

use vars qw{$VERSION @ISA @EXPORT_OK %CHECKS %MATCHES};
BEGIN {
	$VERSION = '1.23_01';

	# Only needed for dev releases, comment out otherwise
	$VERSION = eval $VERSION;

	# Export the PMV convenience constant
	@ISA       = 'Exporter';
	@EXPORT_OK = 'PMV';

	# The primary list of version checks
	%CHECKS = (
		_perl_5010_pragmas      => version->new('5.010'),
		_perl_5010_operators    => version->new('5.010'),
		_perl_5010_magic        => version->new('5.010'),

		# Various small things
		_bugfix_magic_errno     => version->new('5.008.003'),
		_unquoted_versions      => version->new('5.008.001'),
		_perl_5008_pragmas      => version->new('5.008'),
		_constant_hash          => version->new('5.008'),
		_use_base_exporter      => version->new('5.008'),
		_local_soft_reference   => version->new('5.008'),
		_use_carp_version       => version->new('5.008'),

		# Included in 5.6. Broken until 5.8
		_pragma_utf8            => version->new('5.008'),

		_perl_5006_pragmas      => version->new('5.006'),
		_any_our_variables      => version->new('5.006'),
		_any_binary_literals    => version->new('5.006'),
		_any_version_literals   => version->new('5.006'), #v-string
		_magic_version          => version->new('5.006'),
		_any_attributes         => version->new('5.006'),
		_any_CHECK_blocks       => version->new('5.006'),
		_three_argument_open    => version->new('5.006'),
		_weaken                 => version->new('5.006'),
		_mkdir_1_arg            => version->new('5.006'),

		_any_qr_tokens          => version->new('5.005.03'),
		_perl_5005_pragmas      => version->new('5.005'),
		_perl_5005_modules      => version->new('5.005'),
		_any_tied_arrays        => version->new('5.005'),
		_any_quotelike_regexp   => version->new('5.005'),
		_any_INIT_blocks        => version->new('5.005'),
		_substr_4_arg           => version->new('5.005'),
		_splice_negative_length => version->new('5.005'),

		_postfix_foreach        => version->new('5.004.05'),
	);

	# Predefine some indexes needed by various check methods
	%MATCHES = (
		_perl_5010_pragmas => {
			mro     => 1,
			feature => 1,
		},
		_perl_5010_operators => {
			'//'  => 1,
			'//=' => 1,
			'~~'  => 1,
		},
		_perl_5010_magic => {
			'%+' => 1,
			'%-' => 1,
		},
		_perl_5008_pragmas => {
			threads           => 1,
			'threads::shared' => 1,
			sort              => 1,
		},
		_perl_5006_pragmas => {
			warnings             => 1, #may be ported into older version
			'warnings::register' => 1,
			attributes           => 1,
			open                 => 1,
			filetest             => 1,
			charnames            => 1,
			bytes                => 1,
		},
		_perl_5005_pragmas => {
			re     => 1,
			fields => 1, # can be installed from CPAN, with base.pm
			attr   => 1,
		},
	);
}

sub PMV () { 'Perl::MinimumVersion' }





#####################################################################
# Constructor

=pod

=head2 new

  # Create the version checking object
  $object = Perl::MinimumVersion->new( $filename );
  $object = Perl::MinimumVersion->new( \$source  );
  $object = Perl::MinimumVersion->new( $ppi_document );

The C<new> constructor creates a new version checking object for a
L<PPI::Document>. You can also provide the document to be read as a
file name, or as a C<SCALAR> reference containing the code.

Returns a new C<Perl::MinimumVersion> object, or C<undef> on error.

=cut

sub new {
	my $class    = ref $_[0] ? ref shift : shift;
	my $Document = _Document(shift) or return undef;
	my $default  = _INSTANCE(shift, 'version') || version->new('5.004');

	# Create the object
	my $self = bless {
		Document => $Document,

		# Checking limit and default minimum version.
		# Explicitly don't check below this version.
		default  => $default,

		# Caches for resolved versions
		explicit => undef,
		syntax   => undef,
		external => undef,
	}, $class;

	$self;
}

=pod

=head2 Document

The C<Document> accessor can be used to get the L<PPI::Document> object
back out of the version checker.

=cut

sub Document {
	$_[0]->{Document}
}





#####################################################################
# Main Methods

=pod

=head2 minimum_version

The C<minimum_version> method is the primary method for finding the
minimum perl version required based on C<all> factors in the document.

At the present time, this is just syntax and explicit version checks,
as L<Perl::Depends> is not yet completed.

Returns a L<version> object, or C<undef> on error.

=cut

sub minimum_version {
	my $self    = _SELF(\@_) or return undef;
	my $minimum = $self->{default}; # Sensible default

	# Is the explicit version greater?
	my $explicit = $self->minimum_explicit_version;
	return undef unless defined $explicit;
	if ( $explicit and $explicit > $minimum ) {
		$minimum = $explicit;
	}

	# Is the syntax version greater?
	# Since this is the most expensive operation (for this file),
	# we need to be careful we don't run things we don't need to.
	my $syntax = $self->minimum_syntax_version;
	return undef unless defined $syntax;
	if ( $syntax and $syntax > $minimum ) {
		$minimum = $syntax;
	}

	### FIXME - Disabled until minimum_external_version completed
	# Is the external version greater?
	#my $external = $self->minimum_external_version;
	#return undef unless defined $external;
	#if ( $external and $external > $minimum ) {
	#	$minimum = $external;
	#}

	$minimum;
}

sub minimum_reason {
	my $self    = _SELF(\@_) or return undef;
	my $minimum = $self->default_reason; # Sensible default

	# Is the explicit version greater?
	my $explicit = $self->minimum_explicit_version;
	return undef unless defined $explicit;
	if ( $explicit and $explicit > $minimum ) {
		$minimum = $explicit;
	}

}

sub default_reason {
	Perl::MinimumVersion->new(
		rule    => 'default',
		version => $_[0]->{default},
		element => undef,
	);
}

=pod

=head2 minimum_explicit_version

The C<minimum_explicit_version> method checks through Perl code for the
use of explicit version dependencies such as.

  use 5.006;
  require 5.005_03;

Although there is almost always only one of these in a file, if more than
one are found, the highest version dependency will be returned.

Returns a L<version> object, false if no dependencies could be found,
or C<undef> on error.

=cut

sub minimum_explicit_version {
	my $self   = _SELF(\@_) or return undef;
	my $reason = $self->minimum_explicit_reason(@_);
	return $reason ? $reason->version : $reason;
}

sub minimum_explicit_reason {
	my $self = _SELF(\@_) or return undef;
	unless ( defined $self->{explicit} ) {
		$self->{explicit} = $self->_minimum_explicit_version;
	}
	return $self->{explicit};
}

sub _minimum_explicit_version {
	my $self     = shift or return undef;
	my $explicit = $self->Document->find( sub {
		$_[1]->isa('PPI::Statement::Include') or return '';
		$_[1]->version                        or return '';
		1;
	} );
	return $explicit unless $explicit;

	# Find the highest version
	my $max     = undef;
	my $element = undef;
	foreach my $include ( @$explicit ) {
		my $version = version->new($include->version);
		if ( $version > $max or not $element ) {
			$max     = $version;
			$element = $include;
		}
	}

	return Perl::MinimumVersion::Reason->new(
		rule    => 'explicit',
		version => $max,
		element => $element,
	);
}

=pod

=head2 minimum_syntax_version $limit

The C<minimum_syntax_version> method will explicitly test only the
Document's syntax to determine it's minimum version, to the extent
that this is possible.

It takes an optional parameter of a L<version> object defining the
the lowest known current value. For example, if it is already known
that it must be 5.006 or higher, then you can provide a param of
qv(5.006) and the method will not run any of the tests below this
version. This should provide dramatic speed improvements for
large and/or complex documents.

The limitations of parsing Perl mean that this method may provide
artifically low results, but should not artificially high results.

For example, if C<minimum_syntax_version> returned 5.006, you can be
confident it will not run on anything lower, although there is a chance
that during actual execution it may use some untestable feature that
creates a dependency on a higher version.

Returns a L<version> object, false if no dependencies could be found,
or C<undef> on error.

=cut

sub minimum_syntax_version {
	my $self   = _SELF(\@_) or return undef;
	my $reason = $self->minimum_syntax_reason(@_);
	return $reason ? $reason->version : $reason;
}

sub minimum_syntax_reason {
	my $self  = _SELF(\@_) or return undef;
	my $limit = shift;
	if ( defined $limit and not _INSTANCE($limit, 'version') ) {
		$limit = version->new("$limit");
	}
	if ( defined $self->{syntax} ) {
		if ( $self->{syntax} >= $limit ) {
			# Previously discovered minimum is what they want
			return $self->{syntax};
		}

		# Rather than return a value BELOW their filter,
		# which they would not be expecting, return false.
		return '';
	}

	# Look for the value
	my $syntax = $self->_minimum_syntax_version( $limit );

	# If we found a value, it will be stable, cache it.
	# If we did NOT, don't cache as subsequent runs without
	# the filter may find a version.
	if ( $syntax ) {
		$self->{syntax} = $syntax;
		return $self->{syntax};
	}

	return '';
}

sub _minimum_syntax_version {
	my $self   = shift;
	my $filter = shift || $self->{default};

	# Always check in descending version order.
	# By doing it this way, the version of the first check that matches
	# is also the version of the document as a whole.
	my @rules = sort {
		$CHECKS{$b} <=> $CHECKS{$a}
	} grep {
		$CHECKS{$_} > $filter
	} keys %CHECKS;

	foreach my $rule ( @rules ) {
		my $result = $self->$rule() or next;

		# Create the result object
		return Perl::MinimumVersion::Reason->new(
			rule    => $rule,
			version => $CHECKS{$rule},
			element => _INSTANCE($result, 'PPI::Element'),
		);
	}

	# Found nothing of interest
	return '';
}

=pod

=head2 minimum_external_version

B<WARNING: This method has not been implemented. Any attempted use will throw
an exception>

The C<minimum_external_version> examines code for dependencies on other
external files, and recursively traverses the dependency tree applying the
same tests to those files as it does to the original.

Returns a C<version> object, false if no dependencies could be found, or
C<undef> on error.

=cut

sub minimum_external_version {
	my $self   = _SELF(\@_) or return undef;
	my $reason = $self->minimum_explicit_reason(@_);
	return $reason ? $reason->version : $reason;
}

sub minimum_external_reason {
	my $self = _SELF(\@_) or return undef;
	unless ( defined $self->{external} ) {
		$self->{external} = $self->_minimum_external_version;
	}
	$self->{external};
}

sub _minimum_external_version {
	Carp::croak("Perl::MinimumVersion::minimum_external_version is not implemented");
}

=pod

=head2 version_markers

This method returns a list of pairs in the form:

  ($version, \@markers)

Each pair represents all the markers that could be found indicating that the
version was the minimum needed version.  C<@markers> is an array of strings.
Currently, these strings are not as clear as they might be, but this may be
changed in the future.  In other words: don't rely on them as specific
identifiers.

=cut

sub version_markers {
	my $self = _SELF(\@_) or return undef;

	my %markers;

	if ( my $explicit = $self->minimum_explicit_version ) {
		$markers{ $explicit } = [ 'explicit' ];
	}

	foreach my $check ( keys %CHECKS ) {
		next unless $self->$check();
		my $markers = $markers{ $CHECKS{$check} } ||= [];
		push @$markers, $check;
	}

	my @rv;
	my %marker_ver = map { $_ => version->new($_) } keys %markers;

	foreach my $ver ( sort { $marker_ver{$b} <=> $marker_ver{$a} } keys %markers ) {
		push @rv, $marker_ver{$ver} => $markers{$ver};
	}

	return @rv;
}





#####################################################################
# Version Check Methods

sub _perl_5010_pragmas {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$MATCHES{_perl_5010_pragmas}->{$_[1]->pragma}
	} );
}

sub _perl_5010_operators {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Token::Magic')
		and
		$MATCHES{_perl_5010_operators}->{$_[1]->content}
	} );
}

sub _perl_5010_magic {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Token::Operator')
		and
		$MATCHES{_perl_5010_magic}->{$_[1]->content}
	} );
}

sub _perl_5008_pragmas {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$MATCHES{_perl_5008_pragmas}->{$_[1]->pragma}
	} );
}

# FIXME: Needs to be upgraded to return something
sub _bugfix_magic_errno {
	my $Document = shift->Document;
	$Document->find_any( sub {
		$_[1]->isa('PPI::Token::Magic')
		and
		$_[1]->content eq '$^E'
	} )
	and
	$Document->find_any( sub {
		$_[1]->isa('PPI::Token::Magic')
		and
		$_[1]->content eq '$!'
	} );
}

# version->new(5.005.004);
sub _unquoted_versions {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Token::Number')       or return '';
		$_[1]->{_subtype}                      or return '';
		$_[1]->{_subtype} eq 'base256'         or return '';
		my $stmt   = $_[1]->parent             or return '';
		my $braces = $stmt->parent             or return '';
		$braces->isa('PPI::Structure')         or return '';
		$braces->braces eq '()'                or return '';
		my $new = $braces->previous_sibling    or return '';
		$new->isa('PPI::Token::Word')          or return '';
		$new->content eq 'new'                 or return '';
		my $method = $new->previous_sibling    or return '';
		$method->isa('PPI::Token::Operator')   or return '';
		$method->content eq '->'               or return '';
		my $_class = $method->previous_sibling or return '';
		$_class->isa('PPI::Token::Word')       or return '';
		$_class->content eq 'version'          or return '';
		1;
	} );
}

sub _pragma_utf8 {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		(
			($_[1]->module and $_[1]->module eq 'utf8')
			or
			($_[1]->pragma and $_[1]->pragma eq 'utf8')
		)
		# This used to be just pragma(), but that was buggy in PPI v1.118
	} );
}

# Check for the use of 'use constant { ... }'
sub _constant_hash {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$_[1]->type
		and
		$_[1]->type eq 'use'
		and
		$_[1]->module eq 'constant'
		and
		$_[1]->schild(2)->isa('PPI::Structure')
	} );
}

sub _perl_5006_pragmas {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$MATCHES{_perl_5006_pragmas}->{$_[1]->pragma}
	} );
}

sub _any_our_variables {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Variable')
		and
		$_[1]->type eq 'our'
	} );
}

sub _any_binary_literals {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Token::Number')
		and
		$_[1]->{_subtype}
		and
		$_[1]->{_subtype} eq 'binary'
	} );	
}

sub _any_version_literals {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Token::Number::Version')
	} );	
}


sub _magic_version {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Token::Magic')
		and
		$_[1]->content eq '$^V'
	} );
}

sub _any_attributes {
	shift->Document->find_first( 'Token::Attribute' );
}

sub _any_CHECK_blocks {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Scheduled')
		and
		$_[1]->type eq 'CHECK'
	} );
}

sub _any_qr_tokens {
	shift->Document->find_first( 'Token::QuoteLike::Regexp' );
}

sub _perl_5005_pragmas {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$MATCHES{_perl_5005_pragmas}->{$_[1]->pragma}
	} );
}

# A number of modules are highly indicative of using techniques
# that are themselves version-dependant.
sub _perl_5005_modules {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$_[1]->module
		and (
			$_[1]->module eq 'Tie::Array'
			or
			($_[1]->module =~ /\bException\b/ and
				$_[1]->module !~ /^(?:CPAN)::/)
			or
			$_[1]->module =~ /\bThread\b/
			or
			$_[1]->module =~ /^Error\b/
			or
			$_[1]->module eq 'base'
			or
			$_[1]->module eq 'Errno'
		)
	} );
}

sub _any_tied_arrays {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Sub')
		and
		$_[1]->name eq 'TIEARRAY'
	} )
}

sub _any_quotelike_regexp {
	shift->Document->find_first( 'Token::QuoteLike::Regexp' );
}

sub _any_INIT_blocks {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Scheduled')
		and
		$_[1]->type eq 'INIT'
	} );
}

# use base 'Exporter' doesn't work reliably everywhere until 5.008
sub _use_base_exporter {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include')
		and
		$_[1]->module eq 'base'
		and
		# Add the "not colon" characters to avoid accidentally
		# colliding with any other Exporter-named modules
		$_[1]->content =~ /[^:]\bExporter\b[^:]/
	} );
}

# You can't localize a soft reference
sub _local_soft_reference {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Variable')  or return '';
		$_[1]->type eq 'local'                  or return '';

		# The second child should be a '$' cast.
		my @child = $_[1]->schildren;
		scalar(@child) >= 2                     or return '';
		$child[1]->isa('PPI::Token::Cast')      or return '';
		$child[1]->content eq '$'               or return '';

		# The third child should be a block
		$child[2]->isa('PPI::Structure::Block') or return '';

		# Inside the block should be a string in a statement
		my $statement = $child[2]->schild(0)    or return '';
		$statement->isa('PPI::Statement')       or return '';
		my $inside = $statement->schild(0)      or return '';
		$inside->isa('PPI::Token::Quote')       or return '';

		# This is indeed a localized soft reference
		return 1;
	} );
}

# Carp.pm did not have a $VERSION in 5.6.2
# Therefore, even "use Carp 0" imposes a 5.8.0 dependency.
sub _use_carp_version {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement::Include') or return '';
		$_[1]->module eq 'Carp'               or return '';

		my $version = $_[1]->module_version;
		return !! ( defined $version and length "$version" );
	} );
}

sub _three_argument_open {
	shift->Document->find_first( sub {
		$_[1]->isa('PPI::Statement')  or return '';
		my @children=$_[1]->children;
		#@children >= 7                or return '';
		my $main_element=$children[0];
		$main_element->isa('PPI::Token::Word') or return '';
		$main_element->content eq 'open'       or return '';
		my @arguments = parse_arg_list($main_element);
		if ( scalar @arguments > 2 ) {
			return 1;
		}
		return '';
	} );
}


sub _substr_4_arg {
	shift->Document->find_first( sub {
		my $main_element=$_[1];
		$main_element->isa('PPI::Token::Word') or return '';
		$main_element->content eq 'substr'       or return '';
		return '' if is_hash_key($main_element);
		return '' if is_method_call($main_element);
		return '' if is_subroutine_name($main_element);
		return '' if is_included_module_name($main_element);
		return '' if is_package_declaration($main_element);
		my @arguments = parse_arg_list($main_element);
		if ( scalar @arguments > 3 ) {
			return 1;
		}
		return '';
	} );
}

sub _mkdir_1_arg {
	shift->Document->find_first( sub {
		my $main_element=$_[1];
		$main_element->isa('PPI::Token::Word') or return '';
		$main_element->content eq 'mkdir'       or return '';
		return '' if is_hash_key($main_element);
		return '' if is_method_call($main_element);
		return '' if is_subroutine_name($main_element);
		return '' if is_included_module_name($main_element);
		return '' if is_package_declaration($main_element);
		my @arguments = parse_arg_list($main_element);
		if ( scalar @arguments != 2 ) {
			return 1;
		}
		return '';
	} );
}

sub _splice_negative_length {
	shift->Document->find_first( sub {
		my $main_element=$_[1];
		$main_element->isa('PPI::Token::Word') or return '';
		$main_element->content eq 'splice'       or return '';
		return '' if is_hash_key($main_element);
		return '' if is_method_call($main_element);
		return '' if is_subroutine_name($main_element);
		return '' if is_included_module_name($main_element);
		return '' if is_package_declaration($main_element);

		my @arguments = parse_arg_list($main_element);
		if ( scalar @arguments < 3 ) {
			return '';
		}
		my $arg=$arguments[2];
		if (ref($arg) eq 'ARRAY') {
		  $arg=$arg->[0];
		}
		if ($arg->isa('PPI::Token::Number')) {
			if ($arg->literal<0) {
				return 1;
			} else {
				return '';
			}
		}
		return '';
	} );

}

sub _postfix_foreach {
	shift->Document->find_first( sub {
		my $main_element=$_[1];
		$main_element->isa('PPI::Token::Word') or return '';
		$main_element->content eq 'foreach'       or return '';
		return '' if is_hash_key($main_element);
		return '' if is_method_call($main_element);
		return '' if is_subroutine_name($main_element);
		return '' if is_included_module_name($main_element);
		return '' if is_package_declaration($main_element);
		my $stmnt = $main_element->statement();
		return '' if !$stmnt;
		return '' if $stmnt->isa('PPI::Statement::Compound');
		return 1;
	} );
}

# weak references require perl 5.6
# will not work in case of importing several
sub _weaken {
	shift->Document->find_first( sub {
		(
			$_[1]->isa('PPI::Statement::Include')
			and
			$_[1]->module eq 'Scalar::Util'
			and
			$_[1]->content =~ /[^:]\b(?:weaken|isweak)\b[^:]/
		)
		or
		(
			$_[1]->isa('PPI::Token::Word')
			and
			(
				$_[1]->content eq 'Scalar::Util::isweak'
				or
				$_[1]->content eq 'Scalar::Util::weaken'
			)
			#and
			#is_function_call($_[1])
		)
	} );
}





#####################################################################
# Support Functions

# Let sub be a function, object method, and static method
sub _SELF {
	my $param = shift;
	if ( _INSTANCE($param->[0], 'Perl::MinimumVersion') ) {
		return shift @$param;
	}
	if (
		_CLASS($param->[0])
		and
		$param->[0]->isa('Perl::MinimumVersion')
	) {
		my $class   = shift @$param;
		my $options = shift @$param;
		return $class->new($options);
	}
	Perl::MinimumVersion->new(shift @$param);
}

# Find the maximum version, ignoring problems
sub _max {
	defined $_[0] and "$_[0]" eq PMV and shift;
	my @valid = grep { _INSTANCE($_, 'version') } @_;
	my $max   = List::Util::max @valid;
	$max ? $max : '';
}

1;

=pod

=head1 BUGS

B<Perl::MinimumVersion> does a reasonable job of catching the best-known
explicit version dependencies.

B<However> it is exceedingly easy to add a new syntax check, so if you
find something this is missing, copy and paste one of the existing
5 line checking functions, modify it to find what you want, and report it
to rt.cpan.org, along with the version needed.

I don't even need an entire diff... just the function and version.

=head1 TO DO

B<Write lots more version checkers>

- Perl 5.10 operators and language structures

- Three-argument open

B<Write the explicit version checker>

B<Write the recursive module descend stuff>

=head1 SUPPORT

All bugs should be filed via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Perl-MinimumVersion>

For other issues, or commercial enhancement or support, contact the author.

=head1 AUTHORS

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 SEE ALSO

L<http://ali.as/>, L<PPI>, L<version>

=head1 COPYRIGHT

Copyright 2005 - 2009 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
