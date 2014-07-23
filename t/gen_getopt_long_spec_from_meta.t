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
        float1     => {schema=>'float', cmdline_aliases=>{f=>{}}},
        int1       => {schema=>'int', cmdline_aliases=>{set_zero=>{schema=>'bool', code=>sub{}}}},
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
        help    => {getopt=>'help|h|?' , handler=>sub {}},
        version => {getopt=>'version|v', handler=>sub {}},
        verbose => {getopt=>'verbose!' , handler=>sub {}},
        format  => {getopt=>'format=s' , handler=>sub {}},
        fmtopts => {getopt=>'format-options=s', handler=>sub {}},
    },
);

my $cleanser = Data::Clean::JSON->get_cleanser;
$cleanser->clean_in_place($res);

# strip parsed to keep things short
{
    my $sms = $res->[3]{'func.specmeta'};
    for (keys %$sms) {
        $sms->{$_}{parsed} = 'PARSED' if $sms->{$_}{parsed};
    }
}

# due to random hash ordering, sometimes 'f=f' is processed first (and thus
# 'float1=f' becomes CIRCULAR) and sometimes it's the other way around. so we
# just change 'CIRCULAR' to 'CODE' here.
{
    my $res = $res->[2];
    for (keys %$res) {
        $res->{$_} = 'CODE' if $res->{$_} eq 'CIRCULAR';
    }
}

my $expected_res = [
    200, "OK",
    {
        'help|h|?' => 'CODE',
        'version|v' => 'CODE',
        'verbose!' => 'CODE',
        'format=s' => 'CODE',
        'format-options=s' => 'CODE',
        'str-arg1=s' => 'CODE',
        'ary-arg1=s' => 'CODE',
        'ary-arg1-json=s' => 'CODE',
        'ary-arg1-yaml=s' => 'CODE',
        'f=f' => 'CODE',
        'float1=f' => 'CODE',
        'int1=i' => 'CODE',
        'bool1!' => 'CODE',
        'set-zero' => 'CODE', # XXX should be 'set-zero'
        'help-arg' => 'CODE',
    },
    {
        'func.specmeta' => {
            'help|h|?' => {arg=>undef, orig_spec=>'help|h|?', parsed=>'PARSED',},
            'version|v' => {arg=>undef, orig_spec=>'version|v', parsed=>'PARSED',},
            'verbose!' => {arg=>undef, orig_spec=>'verbose!', parsed=>'PARSED',},
            'format=s' => {arg=>undef, orig_spec=>'format=s', parsed=>'PARSED',},
            'format-options=s' => {arg=>undef, orig_spec=>'format-options=s', parsed=>'PARSED',},
            'str-arg1=s' => {arg=>'str_arg1', parsed=>'PARSED',},
            'ary-arg1=s' => {arg=>'ary.arg1', parsed=>'PARSED',},
            'ary-arg1-json=s' => {arg=>'ary.arg1', is_json=>1, parsed=>'PARSED',},
            'ary-arg1-yaml=s' => {arg=>'ary.arg1', is_yaml=>1, parsed=>'PARSED',},
            'float1=f' => {arg=>'float1', parsed=>'PARSED', noncode_aliases=>['f=f'],},
            'f=f' => {is_alias=>1, alias=>'f', alias_for=>'float1=f', is_code=>0, arg=>'float1', parsed=>'PARSED',},
            'int1=i' => {arg=>'int1', parsed=>'PARSED', code_aliases=>['set-zero'],},
            'set-zero' => {is_alias=>1, alias=>'set_zero', alias_for=>'int1=i', is_code=>1, arg=>'int1', parsed=>'PARSED',},
            'bool1!' => {arg=>'bool1', parsed=>'PARSED',},
            'help-arg' => {arg=>'help', parsed=>'PARSED',},
        },
        'func.opts' => [
            '--ary-arg1',
            '--ary-arg1-json',
            '--ary-arg1-yaml',
            '--bool1',
            '--float1',
            '--format',
            '--format-options',
            '--help',
            '--help-arg',
            '--int1',
            '--no-bool1',
            '--no-verbose',
            '--nobool1',
            '--noverbose',
            '--set-zero',
            '--str-arg1',
            '--verbose',
            '--version',
            '-?',
            '-f',
            '-h',
            '-v',
        ],
        'func.common_opts' => [
            '--format',
            '--format-options',
            '--help',
            '--no-verbose',
            '--noverbose',
            '--verbose',
            '--version',
            '-?',
            '-h',
            '-v',
        ],
        'func.func_opts' => [
            '--ary-arg1',
            '--ary-arg1-json',
            '--ary-arg1-yaml',
            '--bool1',
            '--float1',
            '--help-arg',
            '--int1',
            '--no-bool1',
            '--nobool1',
            '--set-zero',
            '--str-arg1',
            '-f',
        ],
        'func.opts_by_arg' => {
            'ary.arg1' => [
                '--ary-arg1',
                '--ary-arg1-json',
                '--ary-arg1-yaml',
            ],
            'bool1' => [
                '--bool1',
                '--no-bool1',
                '--nobool1',
            ],
            'float1' => [
                '--float1',
                '-f',
            ],
            'help' => [
                '--help-arg',
            ],
            'int1' => [
                '--int1',
                '--set-zero',
            ],
            'str_arg1' => [
                '--str-arg1',
            ]
        },
        'func.opts_by_common' => {
            'format-options=s' => [
                '--format-options',
            ],
            'format=s' => [
                '--format',
            ],
            'help|h|?' => [
                '--help',
                '-?',
                '-h',
            ],
            'verbose!' => [
                '--no-verbose',
                '--noverbose',
                '--verbose',
            ],
            'version|v' => [
                '--version',
                '-v',
            ]
        },
    },
];

is_deeply($res, $expected_res)
    or diag explain $res;

DONE_TESTING:
done_testing;
