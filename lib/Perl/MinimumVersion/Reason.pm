package Perl::MinimumVersion::Reason;

# Simple abstraction for a syntax limitation.
# It contains the limiting version, the rule responsible, and the
# PPI element responsible for the limitation (if any).

use 5.006;
use strict;
use warnings;

use vars qw{$VERSION};
BEGIN {
	$VERSION = '1.25';

	# Only needed for dev releases, comment out otherwise
	$VERSION = eval $VERSION;
}

sub new {
	my $class = shift;
	return bless { @_ }, $class;
}

sub version {
	$_[0]->{version};
}

sub rule {
	$_[0]->{rule};
}

sub element {
	$_[0]->{element};
}

1;
