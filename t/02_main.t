#!/usr/bin/perl -w

# Main testing for Perl::MinimumVersion

use strict;
use lib ();
use File::Spec::Functions ':ALL';
BEGIN {
	$| = 1;
	unless ( $ENV{HARNESS_ACTIVE} ) {
		require FindBin;
		$FindBin::Bin = $FindBin::Bin; # Avoid a warning
		chdir catdir( $FindBin::Bin, updir() );
		lib->import(
			catdir('blib', 'arch'),
			catdir('blib', 'lib' ),
			catdir('lib'),
			);
	}
}

use Test::More tests => 46;
use version;
use PPI;
use Perl::MinimumVersion 'PMV';

sub version_is {
	my $Document = PPI::Document->new( \$_[0] );
	isa_ok( $Document, 'PPI::Document' );
	my $Version = Perl::MinimumVersion->new( $Document );
	isa_ok( $Version, 'Perl::MinimumVersion' );
	is( $Version->minimum_version, $_[1], $_[2] || 'Version matches expected' );
	$Version;
}





#####################################################################
# Basic Testing

# Test support function _max
is( PMV, 'Perl::MinimumVersion', 'PMV constant exports correctly' );

# Check the _max support function (bad)
is( Perl::MinimumVersion::_max(),      '', '_max() returns false'      );
is( Perl::MinimumVersion::_max(undef), '', '_max(undef) returns false' );
is( Perl::MinimumVersion::_max(''),    '', '_max(undef) returns false' );

# Check the _max support function (good)
is_deeply( Perl::MinimumVersion::_max(version->new(5.004)),
	version->new(5.004),
	'_max(one) returns the same valud' );

is_deeply( Perl::MinimumVersion::_max(version->new(5.004), undef),
	version->new(5.004),
	'_max(one, bad) returns the good version' );

is_deeply( Perl::MinimumVersion::_max(version->new(5.004), version->new(5.006)),
	version->new(5.006),
	'_max(two) returns the higher version' );

is_deeply( Perl::MinimumVersion::_max(version->new(5.006), version->new(5.004)),
	version->new(5.006),
	'_max(two) returns the higher version' );

is_deeply( Perl::MinimumVersion::_max(version->new(5.006), version->new(5.004), version->new(5.5.3)),
	version->new(5.006),
	'_max(three) returns the higher version' );

is_deeply( Perl::MinimumVersion::_max(version->new(5.006), version->new(5.8.4), undef, version->new(5.004), '', version->new(5.5.3)),
	version->new(5.8.4),
	'_max(three) returns the higher version' );

# Check the _max support function (bad)
is( PMV->_max(),      '', '_max() returns false (as method)'      );
is( PMV->_max(undef), '', '_max(undef) returns false (as method)' );
is( PMV->_max(''),    '', '_max(undef) returns false (as method)' );

# Check the _max support function (good)
is_deeply( PMV->_max(version->new(5.004)),
	version->new(5.004),
	'_max(one) returns the same value (as method)' );

is_deeply( PMV->_max(version->new(5.004), undef),
	version->new(5.004),
	'_max(one, bad) returns the good version (as method)' );

is_deeply( PMV->_max(version->new(5.004), version->new(5.006)),
	version->new(5.006),
	'_max(two) returns the higher version (as method)' );

is_deeply( PMV->_max(version->new(5.006), version->new(5.004)),
	version->new(5.006),
	'_max(two) returns the higher version (as method)' );

is_deeply( PMV->_max(version->new(5.006), version->new(5.004), version->new(5.5.3)),
	version->new(5.006),
	'_max(three) returns the higher version (as method)' );

is_deeply( PMV->_max(version->new(5.006), version->new(5.8.4), undef, version->new(5.004), '', version->new(5.5.3)),
	version->new(5.8.4),
	'_max(three) returns the higher version (as method)' );

# Constructor testing
{
	my $Version = Perl::MinimumVersion->new( \'print "Hello World!\n";' );
	isa_ok( $Version, 'Perl::MinimumVersion' );
	$Version = Perl::MinimumVersion->new( catfile( 't', '02_main.t' ) );
	# version_is tests the final method

	# Bad things
	foreach ( [], {}, sub { 1 } ) { # Add undef as well after PPI 0.906
		is( Perl::MinimumVersion->new( $_ ), undef, '->new(evil) returns undef' );
	}
}

{
my $Version = version_is( <<'END_PERL', '5.004', 'Hello World matches expected version' );
print "Hello World!\n";
END_PERL
is( $Version->_any_our_variables, '', '->_any_our_variables returns false' );

# This first time, lets double check some assumptions
isa_ok( $Version->Document, 'PPI::Document'  );
isa_ok( $Version->minimum_version, 'version' );
}

# Try one with an 'our' in it
{
my $Version = version_is( <<'END_PERL', '5.006', '"our" matches expected version' );
our $foo = 'bar';
END_PERL
is( $Version->_any_our_variables, 1, '->_any_our_variables returns true' );
}

# Try with attributes
{
my $Version = version_is( <<'END_PERL', '5.006', '"attributes" matches expected version' );
sub foo : attribute { 1 };
END_PERL
is( $Version->_any_attributes, 1, '->_any_attributes returns true' );
}

# Check with a complex explicit
{
my $Version = version_is( <<'END_PERL', '5.008', 'explicit versions are detected' );
sub foo : attribute { 1 };
require 5.006;
use 5.008;
END_PERL
}

# Check with syntax higher than explicit
{
my $Version = version_is( <<'END_PERL', '5.006', 'Used syntax higher than low explicit' );
sub foo : attribute { 1 };
require 5.005;
END_PERL
}

# Regression bug: utf8 mispelled
{
my $Version = version_is( <<'END_PERL', '5.008', 'utf8 module makes the version 5.008' );
use utf8;
1;
END_PERL
}

1;
