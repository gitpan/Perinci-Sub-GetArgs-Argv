
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Get subroutine arguments from command line arguments (\@ARGV)",
  "AUTHOR" => "Steven Haryanto <stevenharyanto\@gmail.com>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Perinci-Sub-GetArgs-Argv",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Perinci::Sub::GetArgs::Argv",
  "PREREQ_PM" => {
    "Data::Clean::FromJSON" => "0.11",
    "Data::Sah" => "0.02",
    "JSON" => 0,
    "Log::Any" => 0,
    "Perinci::Sub::GetArgs::Array" => "0.11",
    "Perinci::Sub::Util" => 0,
    "Rinci" => "v1.1.40",
    "YAML::Syck" => 0
  },
  "TEST_REQUIRES" => {
    "Data::Clone" => 0,
    "File::Spec" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Test::More" => "0.98"
  },
  "VERSION" => "0.29",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Data::Clean::FromJSON" => "0.11",
  "Data::Clone" => 0,
  "Data::Sah" => "0.02",
  "File::Spec" => 0,
  "IO::Handle" => 0,
  "IPC::Open3" => 0,
  "JSON" => 0,
  "Log::Any" => 0,
  "Perinci::Sub::GetArgs::Array" => "0.11",
  "Perinci::Sub::Util" => 0,
  "Rinci" => "v1.1.40",
  "Test::More" => "0.98",
  "YAML::Syck" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



