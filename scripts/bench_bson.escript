#!/usr/bin/env escript
%%! -noshell

main(Args) ->
    ok = load_code_paths(),
    #{iterations := Iterations} = parse_args(Args),
    Scenarios = scenarios(),
    Results = [run_scenario(Scenario, Iterations) || Scenario <- Scenarios],
    print_results(Results, Iterations).

parse_args(Args) ->
    parse_args(Args, #{iterations => 100000}).

parse_args([], Config) ->
    Config;
parse_args(["--iterations", Value | Rest], Config) ->
    parse_args(Rest, Config#{iterations => list_to_integer(Value)});
parse_args(["-n", Value | Rest], Config) ->
    parse_args(Rest, Config#{iterations => list_to_integer(Value)});
parse_args(["--help" | _], _Config) ->
    usage();
parse_args([Unknown | _], _Config) ->
    io:format(standard_error, "Unknown argument: ~s~n", [Unknown]),
    usage().

usage() ->
    io:format("Usage: ./scripts/bench_bson.escript [--iterations N]~n", []),
    halt(1).

load_code_paths() ->
    ScriptDir = filename:dirname(escript:script_name()),
    RootDir = filename:dirname(ScriptDir),
    Candidates =
        [
            filename:join([RootDir, "_build", "default", "lib", "bson", "ebin"]),
            RootDir
        ],
    lists:foreach(
        fun(Path) ->
            case filelib:is_dir(Path) of
                true -> code:add_patha(Path);
                false -> ok
            end
        end,
        Candidates
    ),
    ensure_loaded(bson),
    ensure_loaded(bson_binary).

ensure_loaded(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} -> ok;
        {error, Reason} ->
            io:format(
                standard_error,
                "Failed to load ~p: ~p. Run `rebar3 compile` first.~n",
                [Module, Reason]
            ),
            halt(1)
    end.

scenarios() ->
    CommandDoc =
        bson:document(
            [
                {<<"find">>, <<"events">>},
                {<<"filter">>,
                    bson:document(
                        [
                            {<<"tenant_id">>, <<"tenant-42">>},
                            {<<"status">>, <<"active">>},
                            {<<"kind">>, <<"metric">>}
                        ]
                    )},
                {<<"projection">>, bson:document([{<<"_id">>, 0}, {<<"payload">>, 1}])},
                {<<"limit">>, 100},
                {<<"singleBatch">>, true},
                {<<"$db">>, <<"analytics">>}
            ]
        ),
    BatchInsertDocs = sample_documents(64),
    BatchInsertCommand =
        bson:document(
            [
                {<<"insert">>, <<"events">>},
                {<<"documents">>, BatchInsertDocs},
                {<<"ordered">>, true},
                {<<"writeConcern">>, #{<<"w">> => 1}},
                {<<"$db">>, <<"analytics">>}
            ]
        ),
    ReplyDoc =
        #{
            <<"ok">> => 1.0,
            <<"cursor">> =>
                #{
                    <<"firstBatch">> => sample_documents(64),
                    <<"id">> => 0,
                    <<"ns">> => <<"analytics.events">>
                }
        },
    ReplyBin = bson_binary:put_document(ReplyDoc),
    [
        {
            encode_command_tuple,
            byte_size(bson_binary:put_document(CommandDoc)),
            fun(Sink) ->
                Encoded = bson_binary:put_document(CommandDoc),
                Sink bxor byte_size(Encoded)
            end
        },
        {
            encode_insert_batch,
            byte_size(bson_binary:put_document(BatchInsertCommand)),
            fun(Sink) ->
                Encoded = bson_binary:put_document(BatchInsertCommand),
                Sink bxor byte_size(Encoded)
            end
        },
        {
            decode_reply_map,
            byte_size(ReplyBin),
            fun(Sink) ->
                {Decoded, <<>>} = bson_binary:get_map(ReplyBin),
                Sink bxor map_size(Decoded)
            end
        },
        {
            append_single_field,
            undefined,
            fun(Sink) ->
                Updated = bson:append(CommandDoc, {<<"comment">>, <<"otp27-bench">>}),
                Sink bxor tuple_size(Updated)
            end
        }
    ].

sample_documents(Count) ->
    [sample_document(N) || N <- lists:seq(1, Count)].

sample_document(N) ->
    #{
        <<"_id">> => {<<N:32/big, 16#010203:24/big, 16#0405:16/big, N:24/big>>},
        <<"tenant_id">> => <<"tenant-42">>,
        <<"status">> => <<"active">>,
        <<"seq">> => N,
        <<"payload">> =>
            #{
                <<"source">> => <<"ingest">>,
                <<"size">> => N rem 17,
                <<"ok">> => true
            },
        <<"tags">> => [<<"alpha">>, <<"beta">>, <<"gamma">>]
    }.

run_scenario({Name, Bytes, Fun}, Iterations) ->
    WarmupIterations = min(1000, max(1, Iterations div 10)),
    _ = run_iterations(WarmupIterations, Fun, 0),
    erlang:garbage_collect(),
    {reductions, ReductionsStart} = process_info(self(), reductions),
    StartTime = erlang:monotonic_time(microsecond),
    Checksum = run_iterations(Iterations, Fun, 0),
    ElapsedUs = erlang:monotonic_time(microsecond) - StartTime,
    {reductions, ReductionsEnd} = process_info(self(), reductions),
    #{
        name => Name,
        iterations => Iterations,
        bytes => Bytes,
        checksum => Checksum,
        elapsed_us => ElapsedUs,
        reductions => ReductionsEnd - ReductionsStart
    }.

run_iterations(0, _Fun, Sink) ->
    ok = consume_sink(Sink),
    Sink;
run_iterations(Iterations, Fun, Sink) ->
    run_iterations(Iterations - 1, Fun, Fun(Sink)).

consume_sink(_Sink) ->
    ok.

print_results(Results, RequestedIterations) ->
    io:format("BSON OTP 27 benchmark~n", []),
    io:format("Requested iterations: ~B~n~n", [RequestedIterations]),
    io:format(
        "~-24s ~12s ~16s ~16s ~12s ~10s~n",
        ["Scenario", "iters", "us/op", "reductions/op", "bytes/op", "MiB/s"]
    ),
    io:format(
        "~-24s ~12s ~16s ~16s ~12s ~10s~n",
        ["------------------------", "------------", "----------------", "----------------", "------------", "----------"]
    ),
    lists:foreach(fun print_result/1, Results).

print_result(#{name := Name, iterations := Iterations, elapsed_us := ElapsedUs, reductions := Reductions, bytes := Bytes}) ->
    UsPerOp = ElapsedUs / Iterations,
    RedsPerOp = Reductions / Iterations,
    Throughput = throughput_mib(Iterations, Bytes, ElapsedUs),
    io:format(
        "~-24s ~12B ~16.2f ~16.2f ~12s ~10s~n",
        [
            atom_to_list(Name),
            Iterations,
            UsPerOp,
            RedsPerOp,
            format_bytes(Bytes),
            format_throughput(Throughput)
        ]
    ).

throughput_mib(_Iterations, undefined, _ElapsedUs) ->
    undefined;
throughput_mib(_Iterations, _Bytes, 0) ->
    undefined;
throughput_mib(Iterations, Bytes, ElapsedUs) ->
    TotalBytes = Iterations * Bytes,
    TotalSeconds = ElapsedUs / 1000000,
    (TotalBytes / 1048576) / TotalSeconds.

format_bytes(undefined) ->
    "-";
format_bytes(Bytes) ->
    integer_to_list(Bytes).

format_throughput(undefined) ->
    "-";
format_throughput(Value) ->
    lists:flatten(io_lib:format("~.2f", [Value])).
