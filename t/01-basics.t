#!perl

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use Test::More 0.96;

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

# XXX check bool arg

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

test_getargs(meta=>$meta, argv=>['--arg1', '{foo: false}',
                               '--arg2', '',
                               '--arg5', '{foo: false}'],
           args=>{arg1=>'{foo: false}', arg2=>'', arg5=>{foo=>""}},
           name=>"yaml parsing, done on nonscalars");
test_getargs(meta=>$meta, argv=>['--arg1', '{foo: false}',
                               '--arg2', '',
                               '--arg5', '{foo: false'],
           error=>1,
           name=>"yaml syntax error");

{
    my $extra = 0;
    test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2 --extra/],
                 extra_getopts=>{extra=>sub{$extra=5}},
                 args=>{arg1=>1, arg2=>2},
                 posttest=>sub {
                     is($extra, 5, "extra getopt is executed");
                 },
                 name=>"opt: extra_getopts",
             );
    $extra = 0;
    test_getargs(meta=>$meta, argv=>[qw/--arg1 1 --arg2 2/],
                 extra_getopts=>{"arg1=s"=>sub{$extra=1},
                                 "--arg2=s"=>sub{$extra=2}},
                 args=>{arg1=>1, arg2=>2},
                 posttest=>sub {
                     is($extra, 0, "clashing extra getopt is ignored");
                 },
                 name=>"opt: extra_getopts (2)",
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
    v => 1.1,
    args => {
        foo_bar_baz => {schema=>'int'},
    },
};
test_getargs(name=>"dash alias for underscore (1)",
             meta=>$meta, argv=>[qw/--foo_bar_baz 2/],
             args=>{foo_bar_baz=>2},
       );
test_getargs(name=>"dash alias for underscore (2)",
             meta=>$meta, argv=>[qw/--foo-bar-baz 2/],
             args=>{foo_bar_baz=>2},
       );
test_getargs(name=>"dash alias for underscore (3)",
             meta=>$meta, argv=>[qw/--foo-bar_baz 2/],
             error=>1,
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

{
    local @ARGV = (qw/--foo 2/);
    test_getargs(meta=>$meta,
                 args=>{foo=>2},
                 name=>"argv defaults to \@ARGV");
}

DONE_TESTING:
done_testing();

sub test_getargs {
    my (%args) = @_;

    subtest $args{name} => sub {
        my $argv = clone($args{argv});
        my $res;
        my %input_args = (argv=>$argv, meta=>$args{meta});
        for (qw/strict extra_getopts per_arg_yaml/) {
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
            $args{posttest}->();
        }

        done_testing();
    };
}

