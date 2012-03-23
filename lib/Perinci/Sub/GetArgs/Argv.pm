package Perinci::Sub::GetArgs::Argv;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Data::Clone;
use Data::Sah;
use Perinci::Sub::GetArgs::Array qw(get_args_from_array);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_args_from_argv);

our $VERSION = '0.14'; # VERSION

our %SPEC;

$SPEC{get_args_from_argv} = {
    v => 1.1,
    summary => 'Get subroutine arguments (%args) from command-line arguments '.
        '(@ARGV)',
    description => <<'_',

Using information in function metadata's 'args' property, parse command line
arguments '@argv' into hash '%args', suitable for passing into subs.

Uses Getopt::Long's GetOptions to parse the result.

As with GetOptions, this function modifies its 'argv' argument.

Why would one use this function instead of using Getopt::Long directly? Among
other reasons, we want YAML parsing (ability to pass data structures via command
line) and parsing of pos and greedy.

* How this routine uses the 'args' property

Bool types can be specified using:

    --ARGNAME

or

    --noARGNAME

All the other types can be specified using:

    --ARGNAME VALUE

or

    --ARGNAME=VALUE

VALUE will be parsed as YAML for nonscalar types (hash, array). If you want to
force YAML parsing for scalar types (e.g. when you want to specify undef, '~' in
YAML) you can use:

    --ARGNAME-yaml=VALUE

but you need to set 'per_arg_yaml' to true.

This function also (using Perinci::Sub::GetArgs::Array) groks 'pos' and 'greedy'
argument specification, for example:

    $SPEC{multiply2} = {
        v => 1.1,
        summary => 'Multiply 2 numbers (a & b)',
        args => {
            a => ['num*' => {pos=>0}],
            b => ['num*' => {pos=>1}],
        }
    }

then on the command-line any of below is valid:

    % multiply2 --a 2 --b 3
    % multiply2 2 --b 3; # first non-option argument is fed into a (pos=0)
    % multiply2 2 3;     # first argument is fed into a, second into b (pos=1)

_
    args => {
        argv => {
            schema => ['array*' => {
                of => 'str*',
            }],
            req => 1,
            description => 'If not specified, defaults to @ARGV',
        },
        meta => {
            schema => ['hash*' => {}],
            req => 1,
        },
        strict => {
            schema => ['bool' => {default=>1}],
            summary => 'Strict mode',
            description => <<'_',

If set to 0, will still return parsed argv even if there are parsing errors. If
set to 1 (the default), will die upon error.

Normally you would want to use strict mode, for more error checking. Setting off
strict is used by, for example, Perinci::BashComplete.

_
        },
        per_arg_yaml => {
            schema => ['bool' => {default=>0}],
            summary => 'Whether to recognize --ARGNAME-yaml',
            description => <<'_',

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

    % script.pl --name-yaml '~'

_
        },
        extra_getopts => {
            schema => ['hash' => {}],
            summary => 'Specify extra Getopt::Long specification',
            description => <<'_',

If specified, add extra Getopt::Long specification (as long as it doesn't clash
with spec arg). This is used, for example, by Perinci::CmdLine::run() to add
general options --help, --version, --list, etc so it can mixed with spec arg
options, for convenience.

_
        }
    },
};

# this is an internal flag used by Perinci::CmdLine to bypass checking required
# args
our $_pa_skip_check_required_args;

sub get_args_from_argv {
    # we are trying to shave off startup overhead, so only load modules when
    # about to be used
    require Getopt::Long;
    require YAML::Syck; $YAML::Syck::ImplicitTyping = 1;

    my %input_args = @_;
    my $argv       = $input_args{argv} // \@ARGV;
    my $meta       = $input_args{meta} or return [400, "Please specify meta"];
    my $v = $meta->{v} // 1.0;
    return [412, "Only metadata version 1.1 is supported, given $v"]
        unless $v == 1.1;
    my $args_p     = clone($meta->{args} // {});
    my $strict     = $input_args{strict} // 1;
    my $extra_go   = $input_args{extra_getopts} // {};
    my $per_arg_yaml = $input_args{per_arg_yaml} // 0;
    $log->tracef("-> get_args_from_argv(), argv=%s", $argv);

    # the resulting args
    my $args = {};

    my %go_spec;

    $_pa_skip_check_required_args = 0;

    # 1. first we form Getopt::Long spec

    while (my ($a, $as) = each %$args_p) {
        $as->{schema} = Data::Sah::normalize_schema($as->{schema} // 'any');
        my $go_opt;
        $a =~ s/_/-/g; # arg_with_underscore becomes --arg-with-underscore
        my @name = ($a);
        my $name2go_opt = sub {
            my ($name, $schema) = @_;
            if ($schema->[0] eq 'bool') {
                if (length($name) == 1 || $schema->[1]{is}) {
                    # single-letter option like -b doesn't get --nob.
                    # [bool=>{is=>1}] also means it's a flag and should not get
                    # --nofoo.
                    return $name;
                } else {
                    return "$name!";
                }
            } else {
                return "$name=s";
            }
        };
        my $arg_key;
        for my $name (@name) {
            unless (defined $arg_key) { $arg_key = $name; $arg_key =~ s/-/_/g }
            $name =~ s/\./-/g;
            $go_opt = $name2go_opt->($name, $as->{schema});
            # why we use coderefs here? due to getopt::long's behavior. when
            # @ARGV=qw() and go_spec is ('foo=s' => \$opts{foo}) then %opts will
            # become (foo=>undef). but if go_spec is ('foo=s' => sub {
            # $opts{foo} = $_[1] }) then %opts will become (), which is what we
            # prefer, so we can later differentiate "unspecified"
            # (exists($opts{foo}) == false) and "specified as undef"
            # (exists($opts{foo}) == true but defined($opts{foo}) == false).
            $go_spec{$go_opt} = sub { $args->{$arg_key} = $_[1] };
            if ($per_arg_yaml && $as->{schema}[0] ne 'bool') {
                $go_spec{"$name-yaml=s"} = sub {
                    my $decoded;
                    eval { $decoded = YAML::Syck::Load($_[1]) };
                    my $eval_err = $@;
                    return [500, "Invalid YAML in option --$name-yaml: ".
                                "$_[1]: $eval_err"]
                        if $eval_err;
                    $args->{$arg_key} = $decoded;
                };
            }

            # parse argv_aliases
            if ($as->{cmdline_aliases}) {
                while (my ($al, $alspec) = each %{$as->{cmdline_aliases}}) {
                    $go_opt = $name2go_opt->(
                        $al, $alspec->{schema} // $as->{schema});
                    if ($alspec->{code}) {
                        $go_spec{$go_opt} = sub { $alspec->{code}->($args) };
                    } else {
                        $go_spec{$go_opt} = sub { $args->{$arg_key} = $_[1] };
                    }
                }
            }
        }
    }

    # while we already handle arg/--arg and arg=s/arg! variation, we still
    # haven't covered 'arg|alias' case
    while (my ($k0, $v) = each %$extra_go) {
        my $k  = $k0; $k  =~ s/(.+)(?:=.+|!)/$1/; $k =~ s/^-+//;
        my $k_ = $k ; $k_ =~ s/-/_/g;
        if ($args_p->{$k_} ||
                grep {/^(?:--)?\Q$k\E(?:=|!|\z)/} keys %go_spec) {
            $log->warnf("Extra getopt option %s (%s) clashes with ".
                            "argument from metadata, ignored", $k0, $k_);
            next;
        }
        $go_spec{$k} = $v;
    }

    # 2. then we run GetOptions to fill $args from command-line opts

    $log->tracef("GetOptions spec: %s", \%go_spec);
    my $old_go_opts = Getopt::Long::Configure(
        $strict ? "no_pass_through" : "pass_through",
        "no_ignore_case", "permute");
    my $result = Getopt::Long::GetOptionsFromArray($argv, %go_spec);
    Getopt::Long::Configure($old_go_opts);
    unless ($result) {
        return [500, "GetOptions failed"] if $strict;
    }

    # 3. then we try to fill $args from remaining command-line arguments (for
    # args which have 'pos' spec specified)

    if (@$argv) {
        my $res = get_args_from_array(
            array=>$argv, _args_p=>$args_p,
        );
        if ($res->[0] != 200 && $strict) {
            return [500, "Get args from array failed: $res->[0] - $res->[1]"];
        } elsif ($res->[0] == 200) {
            my $pos_args = $res->[2];
            for my $name (keys %$pos_args) {
                if (exists $args->{$name}) {
                    return [400, "You specified option --$name but also ".
                                "argument #".$args_p->{$name}{pos}] if $strict;
                }
                $args->{$name} = $pos_args->{$name};
            }
        }
    }

    # 4. check required args & parse yaml/etc

    unless ($_pa_skip_check_required_args) {
        while (my ($a, $as) = each %$args_p) {
            if ($as->{req} &&
                    !exists($args->{$a})) {
                return [400, "Missing required argument: $a"] if $strict;
            }
            my $parse_yaml;
            my $type = $as->{schema}[0];
            # XXX more proper checking, e.g. check any/all recursively for
            # nonscalar types. check base type.
            $log->tracef("name=%s, arg=%s, parse_yaml=%s",
                         $a, $args->{$a}, $parse_yaml);
            $parse_yaml++ unless $type =~ /^(str|num|int|float|bool)$/;
            if ($parse_yaml && defined($args->{$a})) {
                if (ref($args->{$a}) eq 'ARRAY') {
                    # XXX check whether each element needs to be YAML or not
                    eval {
                        $args->{$a} = [
                            map { YAML::Syck::Load($_) } @{$args->{$a}}
                        ];
                    };
                    return [500, "Invalid YAML in arg '$a': $@"] if $@;
                } elsif (!ref($args->{$a})) {
                    eval { $args->{$a} = YAML::Syck::Load($args->{$a}) };
                    return [500, "Invalid YAML in arg '$a': $@"] if $@;
                } else {
                    return [500, "BUG: Why is \$args->{$a} ".
                                ref($args->{$a})."?"];
                }
            }

            # XXX special parsing of type = date
        }
    }

    $log->tracef("<- get_args_from_argv(), args=%s, remaining argv=%s",
                 $args, $argv);
    [200, "OK", $args];
}

1;
#ABSTRACT: Get subroutine arguments from command line arguments (@ARGV)


=pod

=head1 NAME

Perinci::Sub::GetArgs::Argv - Get subroutine arguments from command line arguments (@ARGV)

=head1 VERSION

version 0.14

=head1 SYNOPSIS

 use Perinci::Sub::GetArgs::Argv;

 my $res = get_args_from_argv(argv=>\@ARGV, meta=>$meta, ...);

=head1 DESCRIPTION

This module provides C<get_args_from_argv()>, which parses command line
arguments (C<@ARGV>) into subroutine arguments (C<%args>). This module is used
by L<Perinci::CmdLine>.

This module uses L<Log::Any> for logging framework.

This module has L<Rinci> metadata.

=head1 FAQ

=head1 SEE ALSO

L<Perinci>

=head1 FUNCTIONS


=head2 get_args_from_argv(%args) -> [status, msg, result, meta]

Get subroutine arguments (%args) from command-line arguments (@ARGV).

Using information in function metadata's 'args' property, parse command line
arguments '@argv' into hash '%args', suitable for passing into subs.

Uses Getopt::Long's GetOptions to parse the result.

As with GetOptions, this function modifies its 'argv' argument.

Why would one use this function instead of using Getopt::Long directly? Among
other reasons, we want YAML parsing (ability to pass data structures via command
line) and parsing of pos and greedy.

=over

=item *

How this routine uses the 'args' property


=back

Bool types can be specified using:

    --ARGNAME

or

    --noARGNAME

All the other types can be specified using:

    --ARGNAME VALUE

or

    --ARGNAME=VALUE

VALUE will be parsed as YAML for nonscalar types (hash, array). If you want to
force YAML parsing for scalar types (e.g. when you want to specify undef, '~' in
YAML) you can use:

    --ARGNAME-yaml=VALUE

but you need to set 'perB<arg>yaml' to true.

This function also (using Perinci::Sub::GetArgs::Array) groks 'pos' and 'greedy'
argument specification, for example:

    $SPEC{multiply2} = {
        v => 1.1,
        summary => 'Multiply 2 numbers (a & b)',
        args => {
            a => ['num*' => {pos=>0}],
            b => ['num*' => {pos=>1}],
        }
    }

then on the command-line any of below is valid:

    % multiply2 --a 2 --b 3
    % multiply2 2 --b 3; # first non-option argument is fed into a (pos=0)
    % multiply2 2 3;     # first argument is fed into a, second into b (pos=1)

Arguments ('*' denotes required arguments):

=over 4

=item * B<argv>* => I<array>

If not specified, defaults to @ARGV

=item * B<extra_getopts> => I<hash>

Specify extra Getopt::Long specification.

If specified, add extra Getopt::Long specification (as long as it doesn't clash
with spec arg). This is used, for example, by Perinci::CmdLine::run() to add
general options --help, --version, --list, etc so it can mixed with spec arg
options, for convenience.

=item * B<meta>* => I<hash>

=item * B<per_arg_yaml> => I<bool> (default: 0)

Whether to recognize --ARGNAME-yaml.

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

    % script.pl --name-yaml '~'

=item * B<strict> => I<bool> (default: 1)

Strict mode.

If set to 0, will still return parsed argv even if there are parsing errors. If
set to 1 (the default), will die upon error.

Normally you would want to use strict mode, for more error checking. Setting off
strict is used by, for example, Perinci::BashComplete.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

