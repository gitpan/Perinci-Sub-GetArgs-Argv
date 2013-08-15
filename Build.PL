
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Get subroutine arguments from command line arguments (\@ARGV)",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "Perinci-Sub-GetArgs-Argv",
  "dist_version" => "0.23",
  "license" => "perl",
  "module_name" => "Perinci::Sub::GetArgs::Argv",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Data::Sah" => "0.02",
    "JSON" => 0,
    "Log::Any" => 0,
    "Perinci::Sub::GetArgs::Array" => "0.09",
    "Perinci::Sub::Util" => 0,
    "Rinci" => "v1.1.10",
    "YAML::Syck" => 0,
    "perl" => "5.010001"
  },
  "script_files" => [],
  "test_requires" => {
    "Data::Clone" => 0,
    "Test::More" => "0.98"
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
