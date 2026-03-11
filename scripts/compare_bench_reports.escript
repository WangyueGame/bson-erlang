#!/usr/bin/env escript
%%! -noshell

main(Args) ->
    #{baseline_label := BaselineLabel,
      baseline_report := BaselineReport,
      candidate_label := CandidateLabel,
      candidate_report := CandidateReport} = parse_args(Args),
    Baseline = read_report(BaselineReport),
    Candidate = read_report(CandidateReport),
    print_summary(BaselineLabel, Baseline, CandidateLabel, Candidate).

parse_args(Args) ->
    parse_args(
        Args,
        #{
            baseline_label => undefined,
            baseline_report => undefined,
            candidate_label => undefined,
            candidate_report => undefined
        }
    ).

parse_args([], Config) ->
    validate_args(Config);
parse_args(["--baseline-label", Value | Rest], Config) ->
    parse_args(Rest, Config#{baseline_label => Value});
parse_args(["--baseline-report", Value | Rest], Config) ->
    parse_args(Rest, Config#{baseline_report => Value});
parse_args(["--candidate-label", Value | Rest], Config) ->
    parse_args(Rest, Config#{candidate_label => Value});
parse_args(["--candidate-report", Value | Rest], Config) ->
    parse_args(Rest, Config#{candidate_report => Value});
parse_args(["--help" | _], _Config) ->
    usage();
parse_args([Unknown | _], _Config) ->
    io:format(standard_error, "Unknown argument: ~s~n", [Unknown]),
    usage().

validate_args(#{baseline_label := undefined}) ->
    usage();
validate_args(#{baseline_report := undefined}) ->
    usage();
validate_args(#{candidate_label := undefined}) ->
    usage();
validate_args(#{candidate_report := undefined}) ->
    usage();
validate_args(Config) ->
    Config.

usage() ->
    io:format(
        "Usage: ./scripts/compare_bench_reports.escript "
        "[--baseline-label LABEL] [--baseline-report FILE] "
        "[--candidate-label LABEL] [--candidate-report FILE]~n",
        []
    ),
    halt(1).

read_report(Path) ->
    {ok, Bin} = file:read_file(Path),
    Lines = binary:split(Bin, <<"\n">>, [global]),
    lists:foldl(fun parse_line/2, [], Lines).

parse_line(Line, Acc) ->
    Tokens = re:split(Line, <<"\\s+">>, [{return, binary}, trim]),
    case Tokens of
        [Scenario, Iterations, UsPerOp, _Reductions, _Bytes, _Throughput]
          when Scenario =/= <<"Scenario">>,
               Scenario =/= <<"------------------------">> ->
            case is_integer_token(Iterations) of
                true ->
                    [{binary_to_list(Scenario), parse_float(UsPerOp)} | Acc];
                false ->
                    Acc
            end;
        _ ->
            Acc
    end.

is_integer_token(Bin) ->
    try
        _ = binary_to_integer(Bin),
        true
    catch
        error:badarg -> false
    end.

parse_float(Bin) ->
    list_to_float(binary_to_list(Bin)).

print_summary(BaselineLabel, BaselinePairs, CandidateLabel, CandidatePairs) ->
    Baseline = maps:from_list(BaselinePairs),
    Candidate = maps:from_list(CandidatePairs),
    OrderedScenarios = [Scenario || {Scenario, _} <- lists:reverse(BaselinePairs)],
    io:format("## Benchmark comparison~n~n", []),
    io:format("- baseline: `~s`~n", [BaselineLabel]),
    io:format("- candidate: `~s`~n~n", [CandidateLabel]),
    io:format("| Scenario | Before (us/op) | After (us/op) | Delta |~n", []),
    io:format("| --- | ---: | ---: | ---: |~n", []),
    lists:foreach(
        fun(Scenario) ->
            BaselineUs = maps:get(Scenario, Baseline),
            CandidateUs = maps:get(Scenario, Candidate),
            Delta = ((CandidateUs - BaselineUs) / BaselineUs) * 100,
            io:format(
                "| `~s` | ~.2f | ~.2f | ~s |~n",
                [Scenario, BaselineUs, CandidateUs, format_delta(Delta)]
            )
        end,
        OrderedScenarios
    ).

format_delta(Delta) when Delta >= 0 ->
    lists:flatten(io_lib:format("+~.2f%", [Delta]));
format_delta(Delta) ->
    lists:flatten(io_lib:format("~.2f%", [Delta])).
