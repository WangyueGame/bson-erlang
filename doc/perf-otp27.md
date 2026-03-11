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
| `f5a8c703` | Pre-optimization baseline | 2.64 | 269.94 | 273.41 | 0.17 |
| `793a940` | Current optimized state with unordered map encoding | 2.32 | 255.30 | 274.40 | 0.05 |

Relative to baseline `f5a8c703`, current optimized commit `793a940`:

- `encode_command_tuple`: `-12.12%`
- `encode_insert_batch`: `-5.42%`
- `decode_reply_map`: `+0.36%`
- `append_single_field`: `-70.59%`

`append_single_field` has a very small absolute runtime and is more sensitive to
normal benchmark noise than the encode/decode cases. The decode delta is within
normal single-run noise and should not be read as a meaningful regression on its own.

### Baseline `f5a8c703`

```text
BSON OTP 27 benchmark
Requested iterations: 100000

Scenario                        iters            us/op    reductions/op     bytes/op      MiB/s
------------------------ ------------ ---------------- ---------------- ------------ ----------
encode_command_tuple           100000             2.64           105.08          179      64.65
encode_insert_batch            100000           269.94         11377.78        11349      40.09
decode_reply_map               100000           273.41          9200.95        11334      39.53
append_single_field            100000             0.17             9.11            -          -
```

### Optimized `793a940`

```text
BSON OTP 27 benchmark
Requested iterations: 100000

Scenario                        iters            us/op    reductions/op     bytes/op      MiB/s
------------------------ ------------ ---------------- ---------------- ------------ ----------
encode_command_tuple           100000             2.32           120.38          179      73.54
encode_insert_batch            100000           255.30         11423.22        11349      42.39
decode_reply_map               100000           274.40          9200.95        11334      39.39
append_single_field            100000             0.05             7.03            -          -
```
