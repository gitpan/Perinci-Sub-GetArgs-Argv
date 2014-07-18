#!perl

use 5.010;
use strict;
use warnings;
#use Log::Any '$log';

use Data::Clean::JSON;
use Perinci::Sub::GetArgs::Argv qw(
                                      gen_getopt_long_spec_from_meta
                              );
use Test::More 0.98;

my $meta = {
    v => 1.1,
    args => {
        str_arg1   => {schema=>'str'},
        'ary.arg1' => {schema=>[array => of => 'str']},
        float1     => {schema=>'float'},
        int1       => {schema=>'int'},
        bool1      => {schema=>'bool'},
        help       => {schema=>['bool', is=>1]},
    },
};

# TODO: test per_arg_json=0
# TODO: test per_arg_yaml=0
# TODO: test conflicts

my $res = gen_getopt_long_spec_from_meta(
    meta=>$meta,
    per_arg_json=>1,
    per_arg_yaml=>1,
    common_opts=>{
        'help|h|?'  => sub {},
        'version|v' => sub {},
        'verbose!' => sub {},
        'format=s'  => sub {},
        'format-options=s' => sub {},
    },
);

my $cleanser = Data::Clean::JSON->get_cleanser;
$cleanser->clean_in_place($res);

my $expected_res = [
    200, "OK",
    {
        'h|help|?' => 'CODE',
        'v|version' => 'CODE',
        'verbose!' => 'CODE',
        'format=s' => 'CODE',
        'format-options=s' => 'CODE',
        'str-arg1=s' => 'CODE',
        'ary-arg1=s' => 'CODE',
        'ary-arg1-json=s' => 'CODE',
        'ary-arg1-yaml=s' => 'CODE',
        'float1=f' => 'CODE',
        'int1=i' => 'CODE',
        'bool1!' => 'CODE',
        'help-arg' => 'CODE',
    },
    {
        'func.specmeta' => {
            'h|help|?' => {arg=>undef, orig_spec=>'help|h|?'},
            'v|version' => {arg=>undef, orig_spec=>'version|v'},
            'verbose!' => {arg=>undef, orig_spec=>'verbose!'},
            'format=s' => {arg=>undef, orig_spec=>'format=s'},
            'format-options=s' => {arg=>undef, orig_spec=>'format-options=s'},
            'str-arg1=s' => {arg=>'str_arg1',},
            'ary-arg1=s' => {arg=>'ary.arg1',},
            'ary-arg1-json=s' => {arg=>'ary.arg1', is_json=>1},
            'ary-arg1-yaml=s' => {arg=>'ary.arg1', is_yaml=>1},
            'float1=f' => {arg=>'float1',},
            'int1=i' => {arg=>'int1',},
            'bool1!' => {arg=>'bool1',},
            'help-arg' => {arg=>'help',},
        },
        'func.opts' => [
            '?',
            'ary-arg1',
            'ary-arg1-json',
            'ary-arg1-yaml',
            'bool1',
            'float1',
            'format',
            'format-options',
            'h',
            'help',
            'help-arg',
            'int1',
            'no-bool1',
            'no-verbose',
            'nobool1',
            'noverbose',
            'str-arg1',
            'v',
            'verbose',
            'version',
        ],
    },
];

is_deeply($res, $expected_res)
    or diag explain $res;

DONE_TESTING:
done_testing;
