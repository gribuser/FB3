#!/usr/local/bin/perl
use strict;
use utf8;
use open qw(:std :utf8);
use Getopt::Long;
use FB3::Validator;
use File::ShareDir qw/dist_dir/;

my ($Help, $Verbose, $XsdDir, $File);
GetOptions(
	'help|h'											=>	\$Help,
	'verbose|v'										=>	\$Verbose,
	'xsd=s'												=>	\$XsdDir,
	'fb3=s'												=>	\$File,
) or usage ("Incorrect usage!");

$XsdDir ||= FB3::SchemasDirPath();

usage() if (defined $Help);
usage(qq{File $File doesn't exist or empty!}) unless ( -e $File );
usage(qq{--xsd option is required!}) unless $XsdDir;

sub usage {
  my $message = $_[0];
  if (defined $message && length $message) {
    $message .= "\n" unless $message =~ /\n$/;
  }

  my $command = $0;
  $command =~ s#^.*/##;

  print STDERR (
    $message,
    qq{usage: $command 
       --help -h                    => this help
       --verbose -v                 => debug messages
       --fb3="path"                 => path to FB3 file
       --xsd="path"                 => path to directory with FB3 xsd files
                                       if omitted, internal schemes will be used
                                       (convenient in most cases)}
  );

  die("\n")
}

my $Validator = FB3::Validator->new( $XsdDir );
my $ValidationError = $Validator->Validate( $File );
if ($ValidationError) {
	print "File $File is not valid: $ValidationError";
} else {
	print "File $File is valid FB3 file\n";
}

	
