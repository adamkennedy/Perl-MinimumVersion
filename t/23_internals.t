#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Perl::MinimumVersion;
my %examples=(
    q{Internals::SvREADONLY($scalar, 1);} => '5.8.0',
    q{Internals::SvREADONLY($scalar, 0);} => '5.8.0',
    q{Internals::SvREADONLY(%hash, 1);}   => '5.8.0',
    q{Internals::SvREADONLY(%hash, 0);}   => '5.8.0',
    q{Internals::SvREADONLY(@array, 1);}  => '5.8.0',
    q{Internals::SvREADONLY(@array, 0);}  => '5.8.0',
);
plan tests => scalar(keys %examples);
foreach my $example (sort keys %examples) {
	my $p = Perl::MinimumVersion->new(\$example);
    my $v = $p->minimum_version;
	is( $v, $examples{$example}, $example )
	  or do { diag "\$\@: $@" if $@ };
}
