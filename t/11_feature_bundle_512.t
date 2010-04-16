#!/usr/bin/perl -w

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More;

#use version;
use Perl::MinimumVersion;
my @examples_not=(
    q{use feature ':5.8'},
    q{use feature ':5.10'},
    q{use feature},
    q{use feature 'say', ':5.10';},
);
my @examples_yes=(
    q{use feature ':5.8', ':5.12'},
    q{use feature ':5.12'},
    q{use feature ':5.12', "say"},
    q{use feature ':5.12';},
);
plan tests =>(@examples_not+@examples_yes);
foreach my $example (@examples_not) {
	my $p = Perl::MinimumVersion->new(\$example);
	is( $p->_feature_bundle_5_12, '', $example )
	  or do { diag "\$\@: $@" if $@ };
}
foreach my $example (@examples_yes) {
	my $p = Perl::MinimumVersion->new(\$example);
	ok( $p->_feature_bundle_5_12, $example )
	  or do { diag "\$\@: $@" if $@ };
}

