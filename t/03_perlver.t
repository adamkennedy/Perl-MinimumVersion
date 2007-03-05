#!/usr/bin/perl -w

# Main testing for Perl::MinimumVersion

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More tests => 1;
use Test::Script;

script_compiles_ok( 'bin/perlver', 'bin/perlver compiles ok' );
