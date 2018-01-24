#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 4;

BEGIN {
    use_ok( 'FB3' ) || print "Bail out!\n";
    use_ok( 'FB3::Validator' ) || print "Bail out!\n";
    use_ok( 'FB3::Convert' ) || print "Bail out!\n";
    use_ok( 'FB3::Convert::Epub' ) || print "Bail out!\n";
}

diag( "Testing FB3 $FB3::VERSION, Perl $], $^X" );
