#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 2;

BEGIN {
    use_ok( 'FB3::Convert' ) || print "Bail out!\n";
    use_ok( 'FB3::Convert::Epub' ) || print "Bail out!\n";
}

diag( "Testing FB3::Convert $FB3::Convert::VERSION, Perl $], $^X" );
