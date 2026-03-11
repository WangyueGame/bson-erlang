# BSON OTP 27 Performance Workflow

This repository keeps BSON performance work intentionally narrow: each optimization
must preserve the external API and come with a repeatable benchmark run.

## Benchmark entrypoint

From the repository root:

```sh
make bench
```

To increase the sample size:

```sh
make bench BENCH_ITERATIONS=50000
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

## Before and after comparison

Capture a baseline before an optimization:

```sh
make bench BENCH_ITERATIONS=50000 | tee /tmp/bson-bench-before.txt
```

Apply the optimization, then rerun:

```sh
make bench BENCH_ITERATIONS=50000 | tee /tmp/bson-bench-after.txt
```

Compare the two reports directly. For each performance change, keep the functional
tests green and mention the benchmark delta in the commit or review notes.

## Validation expectations

Performance changes should always include:

1. Existing `eunit` coverage passing.
2. A benchmark run before and after the change.
3. At least one regression test when the optimized code changes control flow or
   special-case behavior.
