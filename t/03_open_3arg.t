#!/usr/bin/perl -w

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More;

BEGIN {
        plan skip_all => "not yet implemented";
}
#use version;
use Perl::MinimumVersion;
my @examples_not3arg=(
    q{close $x;},
    q{open A,'test.txt'},
    q{open INFO,   "<  datafile"  or print "can't open datafile: ",$!;},
    q{open(INFO,      "datafile") || die("can't open datafile: $!");},
);
my @examples_3arg=(
    q{open A,'<','test.txt';},
    q{open( INFO, ">", $datafile ) || die "Can't create $datafile: $!";},
);
plan tests =>(@examples_3arg+@examples_not3arg);
foreach my $example (@examples_not3arg) {
        my $p = Perl::MinimumVersion->new(\$example);
        is($p->_three_argument_open,'');
}
foreach my $example (@examples_3arg) {
        my $p = Perl::MinimumVersion->new(\$example);
        is($p->_three_argument_open,1);
}
