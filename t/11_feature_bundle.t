#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

#use version;
use Perl::MinimumVersion;
my %examples=(
    q{use feature ':5.8'} => '5.8.0',
    q{use feature} => undef,
    q{use feature 'say', ':5.10';} => '5.10.0',
    q{use feature ':5.10';use feature ':5.12';} => '5.12.0',
    q{use feature ':5.14';use feature ':5.12';} => '5.14.0',
    q{use feature 'array_base';} => '5.16.0',
);
plan tests => scalar(keys %examples);
foreach my $example (sort keys %examples) {
	my $p = Perl::MinimumVersion->new(\$example);
	my ($v, $obj) = $p->_feature_bundle;
	is( $v, $examples{$example}, $example )
	  or do { diag "\$\@: $@" if $@ };
}
