#!perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Test::More 0.98;

use Data::Clone qw(clone);
use Perinci::Sub::GetArgs::Argv qw(get_args_from_argv);

my $meta = {
    v => 1.1,
    args => {
        arg1 => {schema=>'str', req=>1, pos=>0},
        arg2 => {schema=>['str'=>{}], req=>1, pos=>1},
        arg3 => {schema=>'str'},
        arg4 => {schema=>'array'},
        arg5 => {schema=>'hash'},
    },
};

test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"optional missing = ok");
test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2 --arg3 3/],
           args=>{arg1=>1, arg2=>2, arg3=>3},
           name=>"optional given = ok");
test_getargs(meta=>$meta, argv=>[qw/1 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"arg_pos");
test_getargs(meta=>$meta, argv=>[qw/1 2 --arg3 3/],
           args=>{arg1=>1, arg2=>2, arg3=>3},
           name=>"mixed arg_pos with opts (1)");
test_getargs(meta=>$meta, argv=>[qw/1 --arg2 2/],
           args=>{arg1=>1, arg2=>2},
           name=>"mixed arg_pos with opts (2)");
test_getargs(meta=>$meta, argv=>[qw/--arg1 1 2/], error=>1,
           name=>"mixed arg_pos with opts (clash)");
test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2 3/], error=>1,
           name=>"extra args given = fails (1)");
test_getargs(meta=>$meta, argv=>[qw/1 2 3/], error=>1,
           name=>"extra args given = fails (2)");

test_getargs(meta=>$meta, argv=>[qw//], error=>1,
           name=>"required missing = fails");
test_getargs(meta=>$meta, argv=>[qw/--foo bar/], error=>1,
           name=>"unknown args given = fails");

test_getargs(meta=>$meta, argv=>['--arg1', '{"foo":0}',
                               '--arg2', '',
                               '--arg5', '{"foo":0}'],
           args=>{arg1=>'{"foo":0}', arg2=>'', arg5=>{foo=>0}},
           name=>"json parsing, done on nonscalars");
test_getargs(meta=>$meta,
             argv=>[
                 '--arg1', 's', '--arg2', 's',
                 '--arg5', '{"true":true,"false":false}',
             ],
             args=>{arg1=>"s", arg2=>"s", arg5=>{true=>1, false=>0}},
             name=>"json true/false");
test_getargs(meta=>$meta, argv=>['--arg1', '{foo: false}',
                               '--arg2', '',
                               '--arg5', '{foo: false}'],
           args=>{arg1=>'{foo: false}', arg2=>'', arg5=>{foo=>""}},
           name=>"yaml parsing, done on nonscalars");
test_getargs(meta=>$meta, argv=>['--arg1', '{"foo": false}',
                               '--arg2', '',
                               '--arg5', '{foo: false'],
           error=>1,
           name=>"yaml+json syntax error");

{
    my $meta = {
        v => 1.1,
        args => {
            arg1 => {schema=>'hash', req=>1, pos=>0},
        },
    };
    test_getargs(meta=>$meta, argv=>['[foo]'],
                 args=>{arg1=>['foo']},
                 name=>"nonscalar argv, yaml/json parsing");

    $meta = {
        v => 1.1,
        args => {
            arg1 => {schema=>'array', req=>1, pos=>0, greedy=>1},
        },
    };
    test_getargs(meta=>$meta, argv=>['[foo]'],
                 args=>{arg1=>[['foo']]},
                 name=>"nonscalar argv, yaml/json parsing, greedy");
}

{
    my $extra  = 0;
    my $extra2 = 0;
    test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2 --extra --extra2 6/],
                 extra_getopts_before=>[extra=>sub{$extra=5},
                                        "extra2=s"=>sub{$extra2=$_[1]}],
                 args=>{arg1=>1, arg2=>2},
                 posttest=>sub {
                     is($extra , 5, "extra getopt is parsed 1");
                     is($extra2, 6, "extra getopt is parsed 2");
                 },
                 name=>"opt: extra_getopts_before",
             );
    $extra = 0;
    test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2/],
                 extra_getopts=>["arg1=s"=>sub{$extra=1},
                                 "--arg2=s"=>sub{$extra=2}],
                 args=>{arg1=>1, arg2=>2},
                 posttest=>sub {
                     is($extra, 0, "clashing extra getopt is ignored");
                 },
                 name=>"opt: extra_getopts_before (clash)",
             );
}

$meta = {
    v=>1.1,
    args=>{arg1=>{schema=>'str*'}},
};

test_getargs(meta=>$meta,
             argv=>[qw/--arg1 1 --arg2 2/],
             strict=>1, # the default
             error=>1,
             name=>"opt: strict=1",
         );
test_getargs(meta=>$meta,
             argv=>[qw/--arg1 1 --arg2 2/],
             strict=>0,
             args=>{arg1=>1},
             name=>"opt: strict=0",
       );

$meta = {
    v=>1.1,
    args=>{arg1=>{schema=>'str*', req=>1, pos=>0}},
};

test_getargs(meta=>$meta,
             argv=>[qw//],
             #check_required_args=>1, # the default
             error=>1,
             name=>"opt: check_required_args=1",
         );
test_getargs(meta=>$meta,
             argv=>[qw//],
             check_required_args=>0,
             args=>{},
             name=>"opt: check_required_args=0",
             posttest => sub {
                 my $res = shift;
                 is($res->[3]{'func.missing_arg'}, 'arg1');
             },
         );

$meta = {
    v => 1.1,
    args => {
        foo_bar_baz => {schema=>'int'},
    },
};
test_getargs(name=>"underscore becomes dash (1)",
             meta=>$meta, argv=>[qw/--foo_bar_baz 2/],
             error=>1,
       );
test_getargs(name=>"underscore becomes dash (2)",
             meta=>$meta, argv=>[qw/--foo-bar_baz 2/],
             error=>1,
         );
test_getargs(name=>"underscore becomes dash (3)",
             meta=>$meta, argv=>[qw/--foo-bar-baz 2/],
             args=>{foo_bar_baz=>2},
       );

$meta = {
    v => 1.1,
    args => {
        foo => {schema=>'str'},
    },
};
test_getargs(meta=>$meta, argv=>[qw/--foo-yaml ~/],
             error=>1,
             name=>"per_arg_yaml=0");
test_getargs(meta=>$meta, argv=>[qw/--foo-yaml ~/], per_arg_yaml=>1,
             args=>{foo=>undef},
             name=>"per_arg_yaml=1");
test_getargs(meta=>$meta, argv=>[qw/--foo-json null/],
             error=>1,
             name=>"per_arg_json=0");
test_getargs(meta=>$meta, argv=>[qw/--foo-json null/], per_arg_json=>1,
             args=>{foo=>undef},
             name=>"per_arg_json=1");

{
    local @ARGV = (qw/--foo 2/);
    test_getargs(meta=>$meta,
                 args=>{foo=>2},
                 name=>"argv defaults to \@ARGV");
}

# test bool, one-letter arg, cmdline_aliases

$meta = {
    v => 1.1,
    args => {
        b => {schema=>'bool'},
        b2 => {schema=>'bool'},
        s => {schema=>'str'},
        s2 => {schema=>'str',
               cmdline_aliases=>{
                   S=>{},
                   S_foo=>{schema=>[bool=>{is=>1}],
                           code=>sub{$_[0]{s2} = 'foo'}},
               }
           },
    },
};
test_getargs(meta=>$meta, argv=>[qw/-b -s blah/],
             args=>{b=>1, s=>"blah"},
             name=>"one-letter args get -X as well as --X");
test_getargs(meta=>$meta, argv=>[qw/--nob2/],
             args=>{b2=>0},
             name=>"bool args with length > 1 get --XXX as well as --noXXX");
test_getargs(meta=>$meta, argv=>[qw/-S blah/],
             args=>{s2=>"blah"},
             name=>"cmdline_aliases: S");
test_getargs(meta=>$meta, argv=>[qw/--S_foo/], # XXX S-foo not yet provided?
             args=>{s2=>"foo"},
             name=>"cmdline_aliases: S_foo");

subtest "cmdline_aliases: bool alias with code does not get --noX" => sub {
    my $meta = {
        v => 1.1,
        args => {
            true => {
                schema=>'bool',
                cmdline_aliases => {
                    false => {
                        code => sub { ${$_[0]}{true} = 0 },
                    },
                },
            },
        },
    };
    test_getargs(meta=>$meta, argv=>[qw/--true/]);
    test_getargs(meta=>$meta, argv=>[qw/--notrue/]);
    test_getargs(meta=>$meta, argv=>[qw/--false/]);
    test_getargs(meta=>$meta, argv=>[qw/--nofalse/], error=>1);
};

# test handling of array of scalar, --foo 1 --foo 2

$meta = {
    v => 1.1,
    args => {
        ai => {schema=>[array => {of=>'int'}]},
        as => {schema=>[array => {of=>'str*'}], cmdline_aliases=>{S=>{}}},
    },
};
test_getargs(meta=>$meta, argv=>[qw/--ai 1/],
             args=>{ai=>[1]},
             name=>"array of scalar (int, 1)");
test_getargs(meta=>$meta, argv=>[qw/--ai 1 --ai 1/],
             args=>{ai=>[1, 1]},
             name=>"array of scalar (int, 2)");
test_getargs(meta=>$meta, argv=>[qw/--as x/],
             args=>{as=>['x']},
             name=>"array of scalar (str, 1)");
test_getargs(meta=>$meta, argv=>['--as', '[x]', '--as', '', '--as', '"y"'],
             args=>{as=>['[x]', '', '"y"']},
             name=>"array of scalar (str, 2)");
test_getargs(meta=>$meta, argv=>[qw/-S x/],
             args=>{as=>['x']},
             name=>"array of scalar (str, one-letter alias, 1)");
test_getargs(meta=>$meta, argv=>['-S', '[x]', '-S', '', '-S', '"y"'],
             args=>{as=>['[x]', '', '"y"']},
             name=>"array of scalar (str, one-letter alias, 2)");

# test dot

$meta = {
    v => 1.1,
    args => {
        "foo.bar" => {schema=>'int'},
    },
};
test_getargs(meta=>$meta, argv=>[qw/--foo-bar 2/],
             args=>{'foo.bar' => 2},
             name=>"with.dot accepted via --with-dot");

# test option: allow_extra_elems

my $argv = ['a'];
$meta = {
    v => 1.1,
    args => {
        a => {schema=>'str*'},
    },
};
test_getargs(meta=>$meta, argv=>$argv,
             error=>1,
             name=>"allow_extra_elems=>0");
test_getargs(meta=>$meta, argv=>$argv,
             allow_extra_elems => 1,
             args=>{},
             posttest=>sub{
                 is_deeply($argv,['a'],'argv');
             },
             name=>"allow_extra_elems=>1");

# test option: on_missing_required_args

$meta = {
    v => 1.1,
    args => {
        a => {schema=>'str*', req=>1},
        b => {schema=>'str*', cmdline_src=>'stdin'},
    },
};
test_getargs(meta=>$meta, argv=>[qw//],
             args=>{a=>'v1', b=>'v2'},
             on_missing_required_args => sub {
                 my %args = @_;
                 my $arg  = $args{arg};
                 my $args = $args{args};
                 my $spec = $args{spec};

                 if ($arg eq 'a') {
                     $args->{$arg} = 'v1';
                 } elsif ($spec->{cmdline_src} = 'stdin') {
                     $args->{$arg} = 'v2';
                 }
             },
             name=>"arg values set by on_missing_required_args hook");

# since 0.21+, we enable Go::L configuration: bundling

$meta = {
    v => 1.1,
    args => {
        arg => {schema=>'str', cmdline_aliases=>{X=>{}}},
    },
};
test_getargs(meta=>$meta, argv=>[qw/-X=foo/],
             args=>{arg => '=foo'},
             name=>"Go::L configuration: bundling");

DONE_TESTING:
done_testing();

sub test_getargs {
    my (%args) = @_;

    my $name = $args{name} // "getargs(".join(", ", @{$args{argv}}).")";

    subtest $name => sub {
        my $argv = clone($args{argv});
        my $res;
        my %input_args = (argv=>$argv, meta=>$args{meta});
        for (qw/strict check_required_args
                extra_getopts_before extra_getopts_after
                per_arg_json per_arg_yaml
                allow_extra_elems on_missing_required_args/) {
            $input_args{$_} = $args{$_} if defined $args{$_};
        }
        $res = get_args_from_argv(%input_args);
        if ($args{error}) {
            isnt($res->[0], 200, "error (status != 200)");
        } else {
            is($res->[0], 200, "success (status == 200)")
                or diag explain $res;
        }
        if ($args{args}) {
            is_deeply($res->[2], $args{args}, "result")
                or diag explain $res->[2];
        }

        if ($args{posttest}) {
            $args{posttest}->($res);
        }

        done_testing();
    };
}
