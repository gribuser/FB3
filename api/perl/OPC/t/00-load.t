#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 5;

BEGIN {
    use_ok( 'OPC' ) || print "Bail out!\n";
    use_ok( 'OPC::Node' ) || print "Bail out!\n";
    use_ok( 'OPC::Part' ) || print "Bail out!\n";
    use_ok( 'OPC::Root' ) || print "Bail out!\n";
    use_ok( 'OPC::Validator' ) || print "Bail out!\n";
}

diag( "Testing OPC $OPC::VERSION, Perl $], $^X" );
