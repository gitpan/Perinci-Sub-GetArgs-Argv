package Perinci::Sub::GetArgs::Argv;

use 5.010001;
use strict;
use warnings;
#use Log::Any '$log';

use Data::Sah::Normalize qw(normalize_schema);
use Getopt::Long::Util qw(parse_getopt_long_opt_spec);
use Perinci::Sub::GetArgs::Array qw(get_args_from_array);
use Perinci::Sub::Util qw(err);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       gen_getopt_long_spec_from_meta
                       get_args_from_argv
               );

our $DATE = '2014-09-03'; # DATE
our $VERSION = '0.51'; # VERSION

our %SPEC;

my $re_simple_scalar = qr/^(str|num|int|float|bool)$/;

# retun ($success?, $errmsg, $res)
sub _parse_json {
    my $str = shift;

    state $json = do {
        require JSON;
        JSON->new->allow_nonref;
    };

    # to rid of those JSON::XS::Boolean objects which currently choke
    # Data::Sah-generated validator code. in the future Data::Sah can be
    # modified to handle those, or we use a fork of JSON::XS which doesn't
    # produce those in the first place (probably only when performance is
    # critical).
    state $cleanser = do {
        require Data::Clean::FromJSON;
        Data::Clean::FromJSON->get_cleanser;
    };

    my $res;
    eval { $res = $json->decode($str); $cleanser->clean_in_place($res) };
    my $e = $@;
    return (!$e, $e, $res);
}

sub _parse_yaml {
    require YAML::Syck;

    my $str = shift;

    local $YAML::Syck::ImplicitTyping = 1;
    my $res;
    eval { $res = YAML::Syck::Load($str) };
    my $e = $@;
    return (!$e, $e, $res);
}

sub _arg2opt {
    my $opt = shift;
    $opt =~ s/[^A-Za-z0-9-]+/-/g; # foo.bar_baz becomes --foo-bar-baz
    $opt;
}

sub _opt2ospec {
    my ($opt, $schema) = @_;
    my $type = $schema->[0];
    my $cs   = $schema->[1];
    my $is_array_of_simple_scalar = $type eq 'array' &&
        $cs->{of} && $cs->{of}[0] =~ $re_simple_scalar;
    if ($type eq 'bool') {
        if (length($opt) == 1 || $cs->{is}) {
            # single-letter option like -b doesn't get --nob.
            # [bool=>{is=>1}] also means it's a flag and should not get
            # --nofoo.
            return $opt;
        } else {
            return "$opt!";
        }
    } else {
        return "$opt=" . ($type eq 'int' ? 'i' : $type eq 'float' ? 'f' :
                              $is_array_of_simple_scalar ? 's@' : 's');
    }
}

$SPEC{gen_getopt_long_spec_from_meta} = {
    v           => 1.1,
    summary     => 'Generate Getopt::Long spec from Rinci function metadata',
    description => <<'_',

Function arguments will be mapped to command-line options with the same name,
with non-alphanumeric characters changed to `-` (`-` is preferred over `_`
because it lets user avoid pressing Shift on popular keyboards). For example:
`file_size` becomes `file-size`, `file_size.max` becomes `file-size-max`. If
function argument option name clashes with command-line option or another
existing option, it will be renamed to `NAME-arg` (or `NAME-arg2` and so on).
For example: `help` will become `help-arg` (if `common_opts` contains `help`,
that is).

Each command-line alias (`cmdline_aliases` property) in the argument
specification will also be added as command-line option, except if it clashes
with an existing option, in which case this function will warn and skip adding
the alias. For more information about `cmdline_aliases`, see `Rinci::function`.

For arguments with type of `bool`, Getopt::Long will by default also
automatically recognize `--noNAME` or `--no-NAME` in addition to `--name`. So
this function will also check those names for clashes.

For arguments with type array of simple scalar, `--NAME` can be specified more
than once to append to the array.

If `per_arg_json` setting is active, and argument's schema is not a "required
simple scalar" (e.g. an array, or a nullable string), then `--NAME-json` will
also be added to let users input undef (through `--NAME-json null`) or a
non-scalar value (e.g. `--NAME-json '[1,2,3]'`). If this name conflicts with
another existing option, a warning will be displayed and the option will not be
added.

If `per_arg_yaml` setting is active, and argument's schema is not a "required
simple scalar" (e.g. an array, or a nullable string), then `--NAME-yaml` will
also be added to let users input undef (through `--NAME-yaml '~'`) or a
non-scalar value (e.g. `--NAME-yaml '[foo, bar]'`). If this name conflicts with
another existing option, a warning will be displayed and the option will not be
added. YAML can express a larger set of values, e.g. binary data, circular
references, etc.

Will produce a hash (Getopt::Long spec), with `func.specmeta`, `func.opts`,
`func.common_opts`, `func.func_opts` that contain extra information
(`func.specmeta` is a hash of getopt spec name and a hash of extra information
while `func.*opts` lists all used option names).

_
    args => {
        meta => {
            summary => 'Rinci function metadata',
            schema  => 'hash*',
            req     => 1,
        },
        args => {
            summary => 'Reference to hash which will store the result',
            schema  => 'hash*',
        },
        common_opts => {
            summary => 'Common options',
            description => <<'_',

A hash where the values are hashes containing these keys: `getopt` (Getopt::Long
option specification), `handler` (Getopt::Long handler). Will be passed to
`get_args_from_argv()`. Example:

    {
        help => {
            getopt  => 'help|h|?',
            handler => sub { ... },
            summary => 'Display help and exit',
        },
        version => {
            getopt  => 'version|v',
            handler => sub { ... },
            summary => 'Display version and exit',
        },
    }

_
            schema => ['hash*'],
        },
        per_arg_json => {
            summary => 'Whether to add --NAME-json for non-simple arguments',
            schema  => 'bool',
            default => 0,
            description => <<'_',

Will also interpret command-line arguments as JSON if assigned to function
arguments, if arguments' schema is not simple scalar.

_
        },
        per_arg_yaml => {
            summary => 'Whether to add --NAME-yaml for non-simple arguments',
            schema  => 'bool',
            default => 0,
            description => <<'_',

Will also interpret command-line arguments as YAML if assigned to function
arguments, if arguments' schema is not simple scalar.

_
        },
        ignore_converted_code => {
            summary => 'Whether to ignore coderefs converted to string',
            schema => 'bool',
            default => 0,
            description => <<'_',

Across network through JSON encoding, coderef in metadata (e.g. in
`cmdline_aliases` property) usually gets converted to string `CODE`. In some
cases, like for tab completion, this is harmless so you can turn this option on.

_
        },
    },
};
sub gen_getopt_long_spec_from_meta {
    my %fargs = @_;

    my $meta       = $fargs{meta} or return [400, "Please specify meta"];
    unless ($fargs{meta_is_normalized}) {
        require Perinci::Sub::Normalize;
        $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
    }
    my $co           = $fargs{common_opts} // {};
    my $per_arg_yaml = $fargs{per_arg_yaml} // 0;
    my $per_arg_json = $fargs{per_arg_json} // 0;
    my $ignore_converted_code = $fargs{ignore_converted_code};
    my $rargs        = $fargs{args} // {};

    my %go_spec;
    my %specmeta; # key = option spec, val = hash of extra info
    my %seen_opts;
    my %seen_common_opts;
    my %seen_func_opts;

    for my $k (keys %$co) {
        my $v = $co->{$k};
        my $ospec   = $v->{getopt};
        my $handler = $v->{handler};
        my $res = parse_getopt_long_opt_spec($ospec)
            or return [400, "Can't parse common opt spec '$ospec'"];
        $go_spec{$ospec} = $handler;
        $specmeta{$ospec} = {arg=>undef, parsed=>$res};
        for (@{ $res->{opts} }) {
            return [412, "Clash of common opt '$_'"] if $seen_opts{$_};
            $seen_opts{$_}++; $seen_common_opts{$_} = $ospec;
            if ($res->{is_neg}) {
                $seen_opts{"no$_"}++; $seen_common_opts{"no$_"} = $ospec;
                $seen_opts{"no-$_"}++; $seen_common_opts{"no-$_"} = $ospec;
            }
        }
    }

    my $args_p = $meta->{args} // {};
    for my $arg (keys %$args_p) {
        my $as    = $args_p->{$arg};
        my $sch   = $as->{schema} // ['any', {}];
        my $type  = $sch->[0] // '';
        my $cs    = $sch->[1] // {};

        # XXX normalization of 'of' clause should've been handled by sah itself
        if ($type eq 'array' && $cs->{of}) {
            $cs->{of} = normalize_schema($cs->{of});
        }
        my $opt = _arg2opt($arg);
        if ($seen_opts{$opt}) {
            my $i = 1;
            my $opt2;
            while (1) {
                $opt2 = "$opt-arg" . ($i > 1 ? $i : '');
                last unless $seen_opts{$opt2};
                $i++;
            }
            $opt = $opt2;
        }

        my $ospec = _opt2ospec($opt, $sch);
        my $parsed = parse_getopt_long_opt_spec($ospec);
        my $is_simple_scalar = $type =~ $re_simple_scalar;
        my $is_array_of_simple_scalar = $type eq 'array' &&
            $cs->{of} && $cs->{of}[0] =~ $re_simple_scalar;

        # why we use coderefs here? due to Getopt::Long's behavior. when
        # @ARGV=qw() and go_spec is ('foo=s' => \$opts{foo}) then %opts will
        # become (foo=>undef). but if go_spec is ('foo=s' => sub { $opts{foo} =
        # $_[1] }) then %opts will become (), which is what we prefer, so we can
        # later differentiate "unspecified" (exists($opts{foo}) == false) and
        # "specified as undef" (exists($opts{foo}) == true but
        # defined($opts{foo}) == false).

        my $handler = sub {
            my ($val, $val_set);
            if ($is_array_of_simple_scalar) {
                $rargs->{$arg} //= [];
                $val_set = 1; $val = $_[1];
                push @{ $rargs->{$arg} }, $val;
            } elsif ($is_simple_scalar) {
                $val_set = 1; $val = $_[1];
                $rargs->{$arg} = $val;
            } else {
                {
                    my ($success, $e, $decoded);
                    ($success, $e, $decoded) = _parse_json($_[1]);
                    if ($success) {
                        $val_set = 1; $val = $decoded;
                        $rargs->{$arg} = $val;
                        last;
                    }
                    ($success, $e, $decoded) = _parse_yaml($_[1]);
                    if ($success) {
                        $val_set = 1; $val = $decoded;
                        $rargs->{$arg} = $val;
                        last;
                    }
                    die "Invalid YAML/JSON in arg '$arg'";
                }
            }
            if ($val_set && $as->{cmdline_on_getopt}) {
                $as->{cmdline_on_getopt}->(
                    arg=>$arg, value=>$val, args=>$rargs,
                    opt=>$opt,
                );
            }
        }; # handler
        $go_spec{$ospec} = $handler;
        $specmeta{$ospec} = {arg=>$arg, parsed=>$parsed};
        $seen_opts{$opt}++; $seen_func_opts{$opt} = $arg;
        if ($parsed->{is_neg}) {
            $seen_opts{"no$opt"}++; $seen_func_opts{"no$opt"} = $arg;
            $seen_opts{"no-$opt"}++; $seen_func_opts{"no-$opt"} = $arg;
        }

        if ($per_arg_json && $type !~ $re_simple_scalar) {
            my $jopt = "$opt-json";
            if ($seen_opts{$jopt}) {
                warn "Clash of option: $jopt, not added";
            } else {
                my $jospec = "$jopt=s";
                $go_spec{$jospec} = sub {
                    my ($success, $e, $decoded);
                    ($success, $e, $decoded) = _parse_json($_[1]);
                    if ($success) {
                        $rargs->{$arg} = $decoded;
                    } else {
                        die "Invalid JSON in option --$jopt: $_[1]: $e";
                    }
                };
                my $parsed = parse_getopt_long_opt_spec($jospec);
                $specmeta{$jospec} = {arg=>$arg, is_json=>1,  parsed=>$parsed};
                $seen_opts{$jopt}++; $seen_func_opts{$jopt} = $arg;
            }
        }
        if ($per_arg_yaml && $type !~ $re_simple_scalar) {
            my $yopt = "$opt-yaml";
            if ($seen_opts{$yopt}) {
                warn "Clash of option: $yopt, not added";
            } else {
                my $yospec = "$yopt=s";
                $go_spec{$yospec} = sub {
                    my ($success, $e, $decoded);
                    ($success, $e, $decoded) = _parse_yaml($_[1]);
                    if ($success) {
                        $rargs->{$arg} = $decoded;
                    } else {
                        die "Invalid YAML in option --$yopt: $_[1]: $e";
                    }
                };
                my $parsed = parse_getopt_long_opt_spec($yospec);
                $specmeta{$yospec} = {arg=>$arg, is_yaml=>1, parsed=>$parsed};
                $seen_opts{$yopt}++; $seen_func_opts{$yopt} = $arg;
            }
        }

        # parse argv_aliases
        if ($as->{cmdline_aliases}) {
            for my $al (keys %{$as->{cmdline_aliases}}) {
                my $alopt = _arg2opt($al);
                if ($seen_opts{$alopt}) {
                    warn "Clash of cmdline_alias option $al";
                    next;
                }
                my $alspec = $as->{cmdline_aliases}{$al};
                my $alsch = $alspec->{schema} // $sch;
                my $alcode = $alspec->{code};
                my $alospec;
                if ($alcode && $alsch->[0] eq 'bool') {
                    # bool --alias doesn't get --noalias if has code
                    $alospec = $alopt; # instead of "$alopt!"
                } else {
                    $alospec = _opt2ospec($alopt, $alsch);
                }

                if ($alcode) {
                    if ($alcode eq 'CODE') {
                        if ($ignore_converted_code) {
                            $alcode = sub {};
                        } else {
                            return [
                                502,
                                join("",
                                     "Code in cmdline_aliases for arg $arg ",
                                     "got converted into string, probably ",
                                     "because of JSON/YAML transport"),
                            ];
                        }
                    }
                    $go_spec{$alospec} = sub {$alcode->($rargs, $_[1])};
                } else {
                    $go_spec{$alospec} = $handler;
                }
                my $parsed = parse_getopt_long_opt_spec($alospec);
                $specmeta{$alospec} = {
                    alias     => $al,
                    is_alias  => 1,
                    alias_for => $ospec,
                    arg       => $arg,
                    is_code   => $alcode ? 1:0,
                    parsed    => $parsed,
                };
                push @{$specmeta{$ospec}{($alcode ? '':'non').'code_aliases'}},
                    $alospec;
                $seen_opts{$alopt}++; $seen_func_opts{$alopt} = $arg;
                if ($parsed->{is_neg}) {
                    $seen_opts{"no$alopt"}++; $seen_func_opts{"no$alopt"} = $arg;
                    $seen_opts{"no-$alopt"}++; $seen_func_opts{"no-$alopt"} = $arg;
                }
            }
        }

    } # for arg

    my $opts        = [sort(map {length($_)>1 ? "--$_":"-$_"} keys %seen_opts)];
    my $common_opts = [sort(map {length($_)>1 ? "--$_":"-$_"} keys %seen_common_opts)];
    my $func_opts   = [sort(map {length($_)>1 ? "--$_":"-$_"} keys %seen_func_opts)];
    my $opts_by_common = {};
    for my $k (keys %$co) {
        my $v = $co->{$k};
        my $ospec = $v->{getopt};
        my @opts;
        for (keys %seen_common_opts) {
            next unless $seen_common_opts{$_} eq $ospec;
            push @opts, (length($_)>1 ? "--$_":"-$_");
        }
        $opts_by_common->{$ospec} = [sort @opts];
    }
    my $opts_by_arg = {};
    for my $arg (keys %$args_p) {
        my @opts;
        for (keys %seen_func_opts) {
            next unless $seen_func_opts{$_} eq $arg;
            push @opts, (length($_)>1 ? "--$_":"-$_");
        }
        $opts_by_arg->{$arg} = [sort @opts];
    }

    [200, "OK", \%go_spec,
     {
         "func.specmeta"       => \%specmeta,
         "func.opts"           => $opts,
         "func.common_opts"    => $common_opts,
         "func.func_opts"      => $func_opts,
         "func.opts_by_arg"    => $opts_by_arg,
         "func.opts_by_common" => $opts_by_common,
     }];
}

$SPEC{get_args_from_argv} = {
    v => 1.1,
    summary => 'Get subroutine arguments (%args) from command-line arguments '.
        '(@ARGV)',
    description => <<'_',

Using information in Rinci function metadata's `args` property, parse command
line arguments `@argv` into hash `%args`, suitable for passing into subroutines.

Currently uses Getopt::Long's GetOptions to do the parsing.

As with GetOptions, this function modifies its `argv` argument, so you might
want to copy the original `argv` first (or pass a copy instead) if you want to
preserve the original.

See also: gen_getopt_long_spec_from_meta() which is the routine that generates
the specification.

_
    args => {
        argv => {
            schema => ['array*' => {
                of => 'str*',
            }],
            description => 'If not specified, defaults to @ARGV',
        },
        args => {
            summary => 'Specify input args, with some arguments preset',
            schema  => ['hash'],
        },
        meta => {
            schema => ['hash*' => {}],
            req => 1,
        },
        meta_is_normalized => {
            summary => 'Can be set to 1 if your metadata is normalized, '.
                'to avoid duplicate effort',
            schema => 'bool',
            default => 0,
        },
        strict => {
            schema => ['bool' => {default=>1}],
            summary => 'Strict mode',
            description => <<'_',

If set to 0, will still return parsed argv even if there are parsing errors
(reported by Getopt::Long). If set to 1 (the default), will die upon error.

Normally you would want to use strict mode, for more error checking. Setting off
strict is used by, for example, Perinci::Sub::Complete.

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
        common_opts => {
            summary => 'Common options',
            description => <<'_',

A hash where the values are hashes containing these keys: `getopt` (Getopt::Long
option specification), `handler` (Getopt::Long handler). Will be passed to
`get_args_from_argv()`. Example:

    {
        help => {
            getopt  => 'help|h|?',
            handler => sub { ... },
            summary => 'Display help and exit',
        },
        version => {
            getopt  => 'version|v',
            handler => sub { ... },
            summary => 'Display version and exit',
        },
    }

_
            schema => ['hash*'],
        },
        allow_extra_elems => {
            schema => ['bool' => {default=>0}],
            summary => 'Allow extra/unassigned elements in argv',
            description => <<'_',

If set to 1, then if there are array elements unassigned to one of the
arguments, instead of generating an error, this function will just ignore them.

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

The hook can return true if it succeeds in making the missing situation
resolved. In this case, this function will not report the argument as missing.

_
        },
        ignore_converted_code => {
            summary => 'Whether to ignore coderefs converted to string',
            schema => 'bool',
            default => 0,
            description => <<'_',

Across network through JSON encoding, coderef in metadata (e.g. in
`cmdline_aliases` property) usually gets converted to string `CODE`. In some
cases, like for tab completion, this is harmless so you can turn this option on.

_
        },
    },
    result => {
        description => <<'_',

Error codes:

* 400 - Error in Getopt::Long option specification, e.g. in common_opts.

* 500 - failure in GetOptions, meaning argv is not valid according to metadata
  specification (only if 'strict' mode is enabled).

* 502 - coderef in cmdline_aliases got converted into a string, probably because
  the metadata was transported (e.g. through Riap::HTTP/Riap::Simple).

_
    },
};
sub get_args_from_argv {
    require Getopt::Long;

    my %fargs = @_;
    my $argv       = $fargs{argv} // \@ARGV;
    my $meta       = $fargs{meta} or return [400, "Please specify meta"];
    unless ($fargs{meta_is_normalized}) {
        require Perinci::Sub::Normalize;
        $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
    }
    my $strict            = $fargs{strict} // 1;
    my $common_opts       = $fargs{common_opts} // {};
    my $per_arg_yaml      = $fargs{per_arg_yaml} // 0;
    my $per_arg_json      = $fargs{per_arg_json} // 0;
    my $allow_extra_elems = $fargs{allow_extra_elems} // 0;
    my $on_missing        = $fargs{on_missing_required_args};
    my $ignore_converted_code = $fargs{ignore_converted_code};
    #$log->tracef("-> get_args_from_argv(), argv=%s", $argv);

    # to store the resulting args
    my $rargs = $fargs{args} // {};

    # 1. first we generate Getopt::Long spec
    my $genres = gen_getopt_long_spec_from_meta(
        meta => $meta, meta_is_normalized => 1,
        args => $rargs,
        common_opts  => $common_opts,
        per_arg_json => $per_arg_json,
        per_arg_yaml => $per_arg_yaml,
        ignore_converted_code => $ignore_converted_code,
    );
    return err($genres->[0], "Can't generate Getopt::Long spec", $genres)
        if $genres->[0] != 200;
    my $go_spec = $genres->[2];

    # 2. then we run GetOptions to fill $rargs from command-line opts
    #$log->tracef("GetOptions spec: %s", \@go_spec);
    {
        my $old_go_conf = Getopt::Long::Configure(
            $strict ? "no_pass_through" : "pass_through",
            "no_ignore_case", "permute", "bundling", "no_getopt_compat");
        my $res = Getopt::Long::GetOptionsFromArray($argv, %$go_spec);
        Getopt::Long::Configure($old_go_conf);
        unless ($res) {
            return [500, "GetOptions failed"] if $strict;
        }
    }

    # 3. then we try to fill $rargs from remaining command-line arguments (for
    # args which have 'pos' spec specified)

    my $args_p = $meta->{args};

    if (@$argv) {
        my $res = get_args_from_array(
            array=>$argv, meta => $meta,
            meta_is_normalized => 1,
            allow_extra_elems => $allow_extra_elems,
        );
        if ($res->[0] != 200 && $strict) {
            return err(500, "Get args from array failed", $res);
        } elsif ($strict && $res->[0] != 200) {
            return err("Can't get args from argv", $res);
        } elsif ($res->[0] == 200) {
            my $pos_args = $res->[2];
            for my $name (keys %$pos_args) {
                my $as  = $args_p->{$name};
                my $val = $pos_args->{$name};
                if (exists $rargs->{$name}) {
                    return [400, "You specified option --$name but also ".
                                "argument #".$as->{pos}] if $strict;
                }
                my $type = $as->{schema}[0];
                my $cs   = $as->{schema}[1];
                my $is_simple_scalar = $type =~ $re_simple_scalar;
                my $is_array_of_simple_scalar = $type eq 'array' &&
                    $cs->{of} && $cs->{of}[0] =~ $re_simple_scalar;

                if ($as->{greedy} && ref($val) eq 'ARRAY' &&
                        !$is_array_of_simple_scalar) {
                    my $i = 0;
                    for (@$val) {
                      TRY_PARSING_AS_JSON_YAML:
                        {
                            my ($success, $e, $decoded);
                            if ($per_arg_json) {
                                ($success, $e, $decoded) = _parse_json($_);
                                if ($success) {
                                    $_ = $decoded;
                                    last TRY_PARSING_AS_JSON_YAML;
                                } else {
                                    warn "Failed trying to parse argv #$i as JSON: $e";
                                }
                            }
                            if ($per_arg_yaml) {
                                ($success, $e, $decoded) = _parse_yaml($_);
                                if ($success) {
                                    $_ = $decoded;
                                    last TRY_PARSING_AS_JSON_YAML;
                                } else {
                                    warn "Failed trying to parse argv #$i as YAML: $e";
                                }
                            }
                        }
                        $i++;
                    }
                }
                if (!$as->{greedy} && !$is_simple_scalar) {
                  TRY_PARSING_AS_JSON_YAML:
                    {
                        my ($success, $e, $decoded);
                        if ($per_arg_json) {
                            ($success, $e, $decoded) = _parse_json($val);
                            if ($success) {
                                $val = $decoded;
                                last TRY_PARSING_AS_JSON_YAML;
                            } else {
                                warn "Failed trying to parse argv #$as->{pos} as JSON: $e";
                            }
                        }
                        if ($per_arg_yaml) {
                            ($success, $e, $decoded) = _parse_yaml($val);
                            if ($success) {
                                $val = $decoded;
                                last TRY_PARSING_AS_JSON_YAML;
                            } else {
                                warn "Failed trying to parse argv #$as->{pos} as YAML: $e";
                            }
                        }
                    }
                }
                $rargs->{$name} = $val;
                # we still call cmdline_on_getopt for this
                if ($as->{cmdline_on_getopt}) {
                    if ($as->{greedy}) {
                        $as->{cmdline_on_getopt}->(
                            arg=>$name, value=>$_, args=>$rargs,
                            opt=>undef, # this marks that value is retrieved from cmdline arg
                        ) for @$val;
                    } else {
                        $as->{cmdline_on_getopt}->(
                            arg=>$name, value=>$val, args=>$rargs,
                            opt=>undef, # this marks that value is retrieved from cmdline arg
                        );
                    }
                }
            }
        }
    }

    # 4. check missing required args

    my %missing_args;
    for my $a (keys %$args_p) {
        my $as = $args_p->{$a};
        if (!exists($rargs->{$a})) {
            next unless $as->{req};
            # give a chance to hook to set missing arg
            if ($on_missing) {
                next if $on_missing->(arg=>$a, args=>$rargs, spec=>$as);
            }
            next if exists $rargs->{$a};
            $missing_args{$a} = 1;
        }
    }

    #$log->tracef("<- get_args_from_argv(), args=%s, remaining argv=%s",
    #             $rargs, $argv);
    [200, "OK", $rargs, {
        "func.missing_args" => [sort keys %missing_args],
        "func.gen_getopt_long_spec_result" => $genres,
    }];
}

1;
#ABSTRACT: Get subroutine arguments from command line arguments (@ARGV)

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::Sub::GetArgs::Argv - Get subroutine arguments from command line arguments (@ARGV)

=head1 VERSION

This document describes version 0.51 of Perinci::Sub::GetArgs::Argv (from Perl distribution Perinci-Sub-GetArgs-Argv), released on 2014-09-03.

=head1 SYNOPSIS

 use Perinci::Sub::GetArgs::Argv;

 my $res = get_args_from_argv(argv=>\@ARGV, meta=>$meta, ...);

=head1 DESCRIPTION

This module provides C<get_args_from_argv()>, which parses command line
arguments (C<@ARGV>) into subroutine arguments (C<%args>). This module is used
by L<Perinci::CmdLine>. For explanation on how command-line options are
processed, see Perinci::CmdLine's documentation.

This module uses L<Log::Any> for logging framework.

This module has L<Rinci> metadata.

=head1 FUNCTIONS


=head2 gen_getopt_long_spec_from_meta(%args) -> [status, msg, result, meta]

Generate Getopt::Long spec from Rinci function metadata.

Function arguments will be mapped to command-line options with the same name,
with non-alphanumeric characters changed to C<-> (C<-> is preferred over C<_>
because it lets user avoid pressing Shift on popular keyboards). For example:
C<file_size> becomes C<file-size>, C<file_size.max> becomes C<file-size-max>. If
function argument option name clashes with command-line option or another
existing option, it will be renamed to C<NAME-arg> (or C<NAME-arg2> and so on).
For example: C<help> will become C<help-arg> (if C<common_opts> contains C<help>,
that is).

Each command-line alias (C<cmdline_aliases> property) in the argument
specification will also be added as command-line option, except if it clashes
with an existing option, in which case this function will warn and skip adding
the alias. For more information about C<cmdline_aliases>, see C<Rinci::function>.

For arguments with type of C<bool>, Getopt::Long will by default also
automatically recognize C<--noNAME> or C<--no-NAME> in addition to C<--name>. So
this function will also check those names for clashes.

For arguments with type array of simple scalar, C<--NAME> can be specified more
than once to append to the array.

If C<per_arg_json> setting is active, and argument's schema is not a "required
simple scalar" (e.g. an array, or a nullable string), then C<--NAME-json> will
also be added to let users input undef (through C<--NAME-json null>) or a
non-scalar value (e.g. C<--NAME-json '[1,2,3]'>). If this name conflicts with
another existing option, a warning will be displayed and the option will not be
added.

If C<per_arg_yaml> setting is active, and argument's schema is not a "required
simple scalar" (e.g. an array, or a nullable string), then C<--NAME-yaml> will
also be added to let users input undef (through C<--NAME-yaml '~'>) or a
non-scalar value (e.g. C<--NAME-yaml '[foo, bar]'>). If this name conflicts with
another existing option, a warning will be displayed and the option will not be
added. YAML can express a larger set of values, e.g. binary data, circular
references, etc.

Will produce a hash (Getopt::Long spec), with C<func.specmeta>, C<func.opts>,
C<func.common_opts>, C<func.func_opts> that contain extra information
(C<func.specmeta> is a hash of getopt spec name and a hash of extra information
while C<func.*opts> lists all used option names).

Arguments ('*' denotes required arguments):

=over 4

=item * B<args> => I<hash>

Reference to hash which will store the result.

=item * B<common_opts> => I<hash>

Common options.

A hash where the values are hashes containing these keys: C<getopt> (Getopt::Long
option specification), C<handler> (Getopt::Long handler). Will be passed to
C<get_args_from_argv()>. Example:

 {
     help =E<gt> {
         getopt  =E<gt> 'help|h|?',
         handler =E<gt> sub { ... },
         summary =E<gt> 'Display help and exit',
     },
     version =E<gt> {
         getopt  =E<gt> 'version|v',
         handler =E<gt> sub { ... },
         summary =E<gt> 'Display version and exit',
     },
 }

=item * B<ignore_converted_code> => I<bool> (default: 0)

Whether to ignore coderefs converted to string.

Across network through JSON encoding, coderef in metadata (e.g. in
C<cmdline_aliases> property) usually gets converted to string C<CODE>. In some
cases, like for tab completion, this is harmless so you can turn this option on.

=item * B<meta>* => I<hash>

Rinci function metadata.

=item * B<per_arg_json> => I<bool> (default: 0)

Whether to add --NAME-json for non-simple arguments.

Will also interpret command-line arguments as JSON if assigned to function
arguments, if arguments' schema is not simple scalar.

=item * B<per_arg_yaml> => I<bool> (default: 0)

Whether to add --NAME-yaml for non-simple arguments.

Will also interpret command-line arguments as YAML if assigned to function
arguments, if arguments' schema is not simple scalar.

=back

Return value:

Returns an enveloped result (an array).

First element (status) is an integer containing HTTP status code
(200 means OK, 4xx caller error, 5xx function error). Second element
(msg) is a string containing error message, or 'OK' if status is
200. Third element (result) is optional, the actual result. Fourth
element (meta) is called result metadata and is optional, a hash
that contains extra information.

 (any)


=head2 get_args_from_argv(%args) -> [status, msg, result, meta]

Get subroutine arguments (%args) from command-line arguments (@ARGV).

Using information in Rinci function metadata's C<args> property, parse command
line arguments C<@argv> into hash C<%args>, suitable for passing into subroutines.

Currently uses Getopt::Long's GetOptions to do the parsing.

As with GetOptions, this function modifies its C<argv> argument, so you might
want to copy the original C<argv> first (or pass a copy instead) if you want to
preserve the original.

See also: gen_getopt_long_spec_from_meta() which is the routine that generates
the specification.

Arguments ('*' denotes required arguments):

=over 4

=item * B<allow_extra_elems> => I<bool> (default: 0)

Allow extra/unassigned elements in argv.

If set to 1, then if there are array elements unassigned to one of the
arguments, instead of generating an error, this function will just ignore them.

This option will be passed to Perinci::Sub::GetArgs::Array's allow_extra_elems.

=item * B<args> => I<hash>

Specify input args, with some arguments preset.

=item * B<argv> => I<array>

If not specified, defaults to @ARGV

=item * B<common_opts> => I<hash>

Common options.

A hash where the values are hashes containing these keys: C<getopt> (Getopt::Long
option specification), C<handler> (Getopt::Long handler). Will be passed to
C<get_args_from_argv()>. Example:

 {
     help =E<gt> {
         getopt  =E<gt> 'help|h|?',
         handler =E<gt> sub { ... },
         summary =E<gt> 'Display help and exit',
     },
     version =E<gt> {
         getopt  =E<gt> 'version|v',
         handler =E<gt> sub { ... },
         summary =E<gt> 'Display version and exit',
     },
 }

=item * B<ignore_converted_code> => I<bool> (default: 0)

Whether to ignore coderefs converted to string.

Across network through JSON encoding, coderef in metadata (e.g. in
C<cmdline_aliases> property) usually gets converted to string C<CODE>. In some
cases, like for tab completion, this is harmless so you can turn this option on.

=item * B<meta>* => I<hash>

=item * B<meta_is_normalized> => I<bool> (default: 0)

Can be set to 1 if your metadata is normalized, to avoid duplicate effort.

=item * B<on_missing_required_args> => I<code>

Execute code when there is missing required args.

This can be used to give a chance to supply argument value from other sources if
not specified by command-line options. Perinci::CmdLine, for example, uses this
hook to supply value from STDIN or file contents (if argument has C<cmdline_src>
specification key set).

This hook will be called for each missing argument. It will be supplied hash
arguments: (arg => $the_missing_argument_name, args =>
$the_resulting_args_so_far, spec => $the_arg_spec).

The hook can return true if it succeeds in making the missing situation
resolved. In this case, this function will not report the argument as missing.

=item * B<per_arg_json> => I<bool> (default: 0)

Whether to recognize --ARGNAME-json.

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

 % script.pl --name-json 'null'

But every other string will need to be quoted:

 % script.pl --name-json '"foo"'

See also: per_arg_yaml. You should enable just one instead of turning on both.

=item * B<per_arg_yaml> => I<bool> (default: 0)

Whether to recognize --ARGNAME-yaml.

This is useful for example if you want to specify a value which is not
expressible from the command-line, like 'undef'.

 % script.pl --name-yaml '~'

See also: per_arg_json. You should enable just one instead of turning on both.

=item * B<strict> => I<bool> (default: 1)

Strict mode.

If set to 0, will still return parsed argv even if there are parsing errors
(reported by Getopt::Long). If set to 1 (the default), will die upon error.

Normally you would want to use strict mode, for more error checking. Setting off
strict is used by, for example, Perinci::Sub::Complete.

=back

Return value:

Returns an enveloped result (an array).

First element (status) is an integer containing HTTP status code
(200 means OK, 4xx caller error, 5xx function error). Second element
(msg) is a string containing error message, or 'OK' if status is
200. Third element (result) is optional, the actual result. Fourth
element (meta) is called result metadata and is optional, a hash
that contains extra information.

 (any)

Error codes:

* 400 - Error in Getopt::Long option specification, e.g. in common_opts.

* 500 - failure in GetOptions, meaning argv is not valid according to metadata
  specification (only if 'strict' mode is enabled).

* 502 - coderef in cmdline_aliases got converted into a string, probably because
  the metadata was transported (e.g. through Riap::HTTP/Riap::Simple).

=head1 FAQ

=head1 TODO

Option to enable json/yaml for nullable simple scalar (to enable C<--str-json
'~'>).

=head1 SEE ALSO

L<Perinci>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Perinci-Sub-GetArgs-Argv>.

=head1 SOURCE

Source repository is at L<https://github.com/perlancar/perl-Perinci-Sub-GetArgs-Argv>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Perinci-Sub-GetArgs-Argv>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
