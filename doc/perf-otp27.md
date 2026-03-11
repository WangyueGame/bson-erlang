# BSON OTP 27 Performance Workflow

This repository keeps BSON performance work intentionally narrow: each optimization
must preserve the external API and come with a repeatable benchmark run.

## Benchmark entrypoint

From the repository root:

```sh
make bench
```

The default run count is `100000`. To override it explicitly:

```sh
make bench BENCH_ITERATIONS=100000
```

The benchmark covers four scenarios that reflect `mongodb-erlang` usage:

1. Encoding a small ordered command document.
2. Encoding an insert command with a document array payload.
3. Decoding a cursor reply into maps.
4. Appending a single field onto an existing BSON tuple document.

The report prints:

- iterations
- microseconds per operation
- reductions per operation
- bytes per operation when the scenario moves BSON binaries
- throughput in MiB/s when byte counts are available

Each scenario runs the full requested iteration count. There is no per-scenario
downscaling.

## Before and after comparison

Capture a baseline before an optimization:

```sh
make bench BENCH_ITERATIONS=100000 | tee /tmp/bson-bench-before.txt
```

Apply the optimization, then rerun:

```sh
make bench BENCH_ITERATIONS=100000 | tee /tmp/bson-bench-after.txt
```

Compare the two reports directly. For each performance change, keep the functional
tests green and mention the benchmark delta in the commit or review notes.

## Validation expectations

Performance changes should always include:

1. Existing `eunit` coverage passing.
2. A benchmark run before and after the change.
3. At least one regression test when the optimized code changes control flow or
   special-case behavior.

## Recorded Results

Machine-local serial benchmark runs, `BENCH_ITERATIONS=100000`.

### Summary

| Commit | Description | encode_command_tuple us/op | encode_insert_batch us/op | decode_reply_map us/op | append_single_field us/op |
| --- | --- | ---: | ---: | ---: | ---: |
| `ae4dbc8` | Optimization baseline | 2.83 | 296.83 | 260.14 | 0.13 |
| `ef68629` | Final optimized state, includes changes 1/2/3 | 2.28 | 266.68 | 232.26 | 0.04 |

Relative to baseline `ae4dbc8`, final optimized commit `ef68629`:

- `encode_command_tuple`: `-19.43%`
- `encode_insert_batch`: `-10.16%`
- `decode_reply_map`: `-10.72%`
- `append_single_field`: `-69.23%`

`append_single_field` has a very small absolute runtime and is more sensitive to
normal benchmark noise than the encode/decode cases. For append-specific changes,
it is still better to pair this report with a focused micro-benchmark.

### Baseline `ae4dbc8`

```text
BSON OTP 27 benchmark
Requested iterations: 100000

Scenario                        iters            us/op    reductions/op     bytes/op      MiB/s
------------------------ ------------ ---------------- ---------------- ------------ ----------
encode_command_tuple           100000             2.83           105.08          179      60.26
encode_insert_batch            100000           296.83         11197.31        11349      36.46
decode_reply_map               100000           260.14          9200.94        11334      41.55
append_single_field            100000             0.13             9.11            -          -
```

### Optimized `ef68629`

```text
BSON OTP 27 benchmark
Requested iterations: 100000

Scenario                        iters            us/op    reductions/op     bytes/op      MiB/s
------------------------ ------------ ---------------- ---------------- ------------ ----------
encode_command_tuple           100000             2.28           120.38          179      74.92
encode_insert_batch            100000           266.68         11278.57        11349      40.58
decode_reply_map               100000           232.26          9200.95        11334      46.54
append_single_field            100000             0.04             7.03            -          -
```
