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

our $VERSION = '0.20'; # VERSION

our %SPEC;

$SPEC{get_args_from_argv} = {
    v => 1.1,
    summary => 'Get subroutine arguments (%args) from command-line arguments '.
        '(@ARGV)',
    description => <<'_',

Using information in function metadata's 'args' property, parse command line
arguments '@argv' into hash '%args', suitable for passing into subs.

Currently uses Getopt::Long's GetOptions to do the parsing.

As with GetOptions, this function modifies its 'argv' argument.

Why would one use this function instead of using Getopt::Long directly? Among
other reasons, we want to be able to parse complex types.

This function exists mostly to support command-line options parsing for
Perinci::CmdLine. See its documentation, on the section of command-line
options/argument parsing.

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
        check_required_args => {
            schema => ['bool'=>{default=>1}],
            summary => 'Whether to check required arguments',
            description => <<'_',

If set to true, will check that required arguments (those with req=>1) have been
specified. Normally you want this, but Perinci::CmdLine turns this off so users
can run --help even when arguments are incomplete.

_
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

See also: per_arg_json. You should enable just one instead of turning on both.

_
        },
        per_arg_json => {
            schema => ['bool' => {default=>0}],
            summary => 'Whether to recognize --ARGNAME-json',
            description => <<'_',

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

    % script.pl --name-json 'null'

But every other string will need to be quoted:

    % script.pl --name-json '"foo"'

See also: per_arg_yaml. You should enable just one instead of turning on both.

_
        },
        extra_getopts_before => {
            schema => ['array' => {}],
            summary => 'Specify extra Getopt::Long specification',
            description => <<'_',

If specified, insert extra Getopt::Long specification. This is used, for
example, by Perinci::CmdLine::run() to add general options --help, --version,
--list, etc so it can mixed with spec arg options, for convenience.

Since the extra specification is put at the front (before function arguments
specification), the extra options will not be able to override function
arguments (this is how Getopt::Long works). For example, if extra specification
contains --help, and one of function arguments happens to be 'help', the extra
specification won't have any effect.

_
        },
        extra_getopts_after => {
            schema => ['array' => {}],
            summary => 'Specify extra Getopt::Long specification',
            description => <<'_',

Just like *extra_getopts_before*, but the extra specification is put _after_
function arguments specification so extra options can override function
arguments.

_
        },
        allow_extra_elems => {
            schema => ['bool' => {default=>0}],
            summary => 'Allow extra/unassigned elements in argv',
            description => <<'_',

If set to 1, then if there are array elements unassigned to one of the
arguments, instead of generating an error, the function will just ignore them.

This option will be passed to Perinci::Sub::GetArgs::Array's allow_extra_elems.

_
        },
        on_missing_required_args => {
            schema => 'code',
            summary => 'Execute code when there is missing required args',
            description => <<'_',

This can be used to give a chance to supply argument value from other sources if
not specified by command-line options. Perinci::CmdLine, for example, uses this
hook to supply value from STDIN or file contents (if argument has `cmdline_src`
specification key set).

This hook will be called for each missing argument. It will be supplied hash
arguments: (arg => $the_missing_argument_name, args =>
$the_resulting_args_so_far, spec => $the_arg_spec).

_
        },
    },
};

my $re_simple_scalar = qr/^(str|num|int|float|bool)$/;

sub get_args_from_argv {
    # we are trying to shave off startup overhead, so only load modules when
    # about to be used
    require Getopt::Long;

    my %input_args = @_;
    my $argv       = $input_args{argv} // \@ARGV;
    my $meta       = $input_args{meta} or return [400, "Please specify meta"];
    my $v = $meta->{v} // 1.0;
    return [412, "Only metadata version 1.1 is supported, given $v"]
        unless $v == 1.1;
    my $args_p     = clone($meta->{args} // {});
    my $strict     = $input_args{strict} // 1;
    my $extra_go_b = $input_args{extra_getopts_before} // [];
    my $extra_go_a = $input_args{extra_getopts_after} // [];
    my $per_arg_yaml = $input_args{per_arg_yaml} // 0;
    my $per_arg_json = $input_args{per_arg_json} // 0;
    my $allow_extra_elems = $input_args{allow_extra_elems} // 0;
    my $on_missing = $input_args{on_missing_required_args};
    $log->tracef("-> get_args_from_argv(), argv=%s", $argv);

    # the resulting args
    my $args = {};

    my @go_spec;

    # 1. first we form Getopt::Long spec

    while (my ($a, $as) = each %$args_p) {
        $as->{schema} = Data::Sah::normalize_schema($as->{schema} // 'any');
        # XXX normalization of 'of' clause should've been handled by sah itself
        if ($as->{schema}[0] eq 'array' && $as->{schema}[1]{of}) {
            $as->{schema}[1]{of} = Data::Sah::normalize_schema(
                $as->{schema}[1]{of});
        }
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
            my $type = $as->{schema}[0];
            my $cs   = $as->{schema}[1];
            my $is_simple_scalar = $type =~ $re_simple_scalar;
            my $is_array_of_simple_scalar = $type eq 'array' &&
                $cs->{of} && $cs->{of}[0] =~ $re_simple_scalar;
            # why we use coderefs here? due to getopt::long's behavior. when
            # @ARGV=qw() and go_spec is ('foo=s' => \$opts{foo}) then %opts will
            # become (foo=>undef). but if go_spec is ('foo=s' => sub {
            # $opts{foo} = $_[1] }) then %opts will become (), which is what we
            # prefer, so we can later differentiate "unspecified"
            # (exists($opts{foo}) == false) and "specified as undef"
            # (exists($opts{foo}) == true but defined($opts{foo}) == false).
            push @go_spec, $go_opt => sub {
                if ($is_array_of_simple_scalar) {
                    $args->{$arg_key} //= [];
                    push @{ $args->{$arg_key} }, $_[1];
                } elsif ($is_simple_scalar) {
                    $args->{$arg_key} = $_[1];
                } else {
                    require JSON;
                    require YAML::Syck; local $YAML::Syck::ImplicitTyping = 1;
                    state $json = JSON->new->allow_nonref;
                    eval { $args->{$arg_key} = $json->decode($_[1]) };
                    my $ej = $@;
                    eval { $args->{$arg_key} = YAML::Syck::Load($_[1]) };
                    my $ey = $@;
                    die "Invalid YAML/JSON in arg '$arg_key'" if $ej && $ey;
                }
                # XXX special parsing of type = date
            };

            if ($per_arg_json && $as->{schema}[0] ne 'bool') {
                push @go_spec, "$name-json=s" => sub {
                    require JSON;
                    my $decoded;
                    eval { $decoded = JSON->new->allow_nonref->decode($_[1]) };
                    my $e = $@;
                    if ($e) {
                        die "Invalid JSON in option --$name-json: $_[1]: $e";
                        return;
                    }
                    $args->{$arg_key} = $decoded;
                };
            }
            if ($per_arg_yaml && $as->{schema}[0] ne 'bool') {
                push @go_spec, "$name-yaml=s" => sub {
                    require YAML::Syck; local $YAML::Syck::ImplicitTyping = 1;
                    my $decoded;
                    eval { $decoded = YAML::Syck::Load($_[1]) };
                    my $e = $@;
                    if ($e) {
                        die "Invalid YAML in option --$name-yaml: $_[1]: $e";
                        return;
                    }
                    $args->{$arg_key} = $decoded;
                };
            }

            # parse argv_aliases
            if ($as->{cmdline_aliases}) {
                while (my ($al, $alspec) = each %{$as->{cmdline_aliases}}) {
                    $go_opt = $name2go_opt->(
                        $al, $alspec->{schema} // $as->{schema});
                    if ($alspec->{code}) {
                        push @go_spec, $go_opt=>sub {$alspec->{code}->($args)};
                    } else {
                        push @go_spec, $go_opt=>sub {$args->{$arg_key} = $_[1]};
                    }
                }
            }
        }
    }

    # 2. then we run GetOptions to fill $args from command-line opts

    @go_spec = (@$extra_go_b, @go_spec, @$extra_go_a);
    $log->tracef("GetOptions spec: %s", \@go_spec);
    my $old_go_opts = Getopt::Long::Configure(
        $strict ? "no_pass_through" : "pass_through",
        "no_ignore_case", "permute");
    my $result = Getopt::Long::GetOptionsFromArray($argv, @go_spec);
    Getopt::Long::Configure($old_go_opts);
    unless ($result) {
        return [500, "GetOptions failed"] if $strict;
    }

    # 3. then we try to fill $args from remaining command-line arguments (for
    # args which have 'pos' spec specified)

    if (@$argv) {
        my $res = get_args_from_array(
            array=>$argv, _args_p=>$args_p,
            allow_extra_elems => $allow_extra_elems,
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

    # 4. check required args

    if ($input_args{check_required_args} // 1) {
        while (my ($a, $as) = each %$args_p) {
            if (!exists($args->{$a})) {
                # give a chance to hook to set missing arg
                if ($on_missing) {
                    $on_missing->(arg=>$a, args=>$args, spec=>$as);
                }
                if ($as->{req} && !exists($args->{$a})) {
                    return [400, "Missing required argument: $a"] if $strict;
                }
            }
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

version 0.20

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

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head2 get_args_from_argv(%args) -> [status, msg, result, meta]

Get subroutine arguments (%args) from command-line arguments (@ARGV).

Using information in function metadata's 'args' property, parse command line
arguments '@argv' into hash '%args', suitable for passing into subs.

Currently uses Getopt::Long's GetOptions to do the parsing.

As with GetOptions, this function modifies its 'argv' argument.

Why would one use this function instead of using Getopt::Long directly? Among
other reasons, we want to be able to parse complex types.

This function exists mostly to support command-line options parsing for
Perinci::CmdLine. See its documentation, on the section of command-line
options/argument parsing.

Arguments ('*' denotes required arguments):

=over 4

=item * B<allow_extra_elems> => I<bool> (default: 0)

Allow extra/unassigned elements in argv.

If set to 1, then if there are array elements unassigned to one of the
arguments, instead of generating an error, the function will just ignore them.

This option will be passed to Perinci::Sub::GetArgs::Array's allowI<extra>elems.

=item * B<argv>* => I<array>

If not specified, defaults to @ARGV

=item * B<check_required_args> => I<bool> (default: 1)

Whether to check required arguments.

If set to true, will check that required arguments (those with req=>1) have been
specified. Normally you want this, but Perinci::CmdLine turns this off so users
can run --help even when arguments are incomplete.

=item * B<extra_getopts_after> => I<array>

Specify extra Getopt::Long specification.

Just like I<extra_getopts_before>, but the extra specification is put I<after>
function arguments specification so extra options can override function
arguments.

=item * B<extra_getopts_before> => I<array>

Specify extra Getopt::Long specification.

If specified, insert extra Getopt::Long specification. This is used, for
example, by Perinci::CmdLine::run() to add general options --help, --version,
--list, etc so it can mixed with spec arg options, for convenience.

Since the extra specification is put at the front (before function arguments
specification), the extra options will not be able to override function
arguments (this is how Getopt::Long works). For example, if extra specification
contains --help, and one of function arguments happens to be 'help', the extra
specification won't have any effect.

=item * B<meta>* => I<hash>

=item * B<on_missing_required_args> => I<code>

Execute code when there is missing required args.

This can be used to give a chance to supply argument value from other sources if
not specified by command-line options. Perinci::CmdLine, for example, uses this
hook to supply value from STDIN or file contents (if argument has C<cmdline_src>
specification key set).

This hook will be called for each missing argument. It will be supplied hash
arguments: (arg => $theI<missing>argumentI<name, args =>
$the>resultingI<args>soI<far, spec => $the>arg_spec).

=item * B<per_arg_json> => I<bool> (default: 0)

Whether to recognize --ARGNAME-json.

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

    % script.pl --name-json 'null'

But every other string will need to be quoted:

    % script.pl --name-json '"foo"'

See also: perI<arg>yaml. You should enable just one instead of turning on both.

=item * B<per_arg_yaml> => I<bool> (default: 0)

Whether to recognize --ARGNAME-yaml.

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

    % script.pl --name-yaml '~'

See also: perI<arg>json. You should enable just one instead of turning on both.

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

