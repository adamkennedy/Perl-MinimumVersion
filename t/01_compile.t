#!/usr/bin/perl

# Load test the Perl::MinimumVersion module

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More 'tests' => 3;
use Test::Script;

ok( $] >= 5.005, 'Your perl is new enough' );

use_ok('Perl::MinimumVersion' );

script_compiles_ok( 'script/perlver', 'perver compiles ok' );

