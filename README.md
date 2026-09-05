# Roshanfer TLA+ model — EuroSys 2027

TLA+ specification of the Request Limit Protocol from §5 of **Roshanfer: Achieving Performance Resilience in Cloud Microservices** (EuroSys 2027, paper #1195). This directory is the spec the paper points to in Supplementary Materials.

## Files

| File | Role |
| --- | --- |
| `Roshanfer.tla` | Protocol (Ingress, Agent, Server). Derived constant tables (`Reach`, path limits, weights, downstreams) are computed once in `Init` with `TLCSet` / `TLCGet` so TLC workers do not recompute them on every state. |
| `RoshanferTest.tla` | One finite configuration |
| `RoshanferTest.cfg` | TLC configuration (invariants `Conservation`, `ABound`, `NsBound`; liveness `AllProcessed`) |
| `Utils.tla` | Sequence and set helpers |
| `run-tlc.sh` | Downloads tla2tools if needed and runs exhaustive TLC with all cores, off-heap fingerprints, and `time -v` |

## Properties

TLC exhaustively checks these on the bundled configuration:

- **Request Bound.** Active requests at an endpoint stay within that endpoint’s local limit plus the bounds of its immediate downstream endpoints. There is no unbounded queueing inside the service.
- **Deadlock Freedom.** Every request admitted at Ingress receives a response, assuming processing inside the microservices terminates.
- **Work Conservation.** Credit requests queue at a microservice only if that microservice, or some downstream of it, has sufficient active requests to exhaust its local limit. The protocol does not stall upstream microservices when there exists no downstream microservice that is at its processing capacity.

## Checked topology and bounds

The finite model is the configuration in `RoshanferTest.tla` / `RoshanferTest.cfg`.

- **Microservices:** 5 (frontend S1 plus S2–S5). Ingress is the external client of S1.
- **APIs:** 2, corresponding to S1’s two endpoints.
- **EndpointLimits:** 1 on every endpoint.
- **GlobalLimits:** −1 on non-leaves (S1, S2, S3; no global cap); 1 on leaves S4 and S5.
- **EndpointWeights:** 2:1 on S4; 1 elsewhere (weighted credit scheduling).
- **Call graph** (`ServerDownstreams`), including dynamic (set-valued) branches:
  - S1.E1 (API 1): one stage, dynamic choice {S2.E1, S5.E1}
  - S1.E2 (API 2): one stage, {S3.E2}
  - S2.E1: sequential stages {S4.E1} then {S3.E1}
  - S3.E2: one stage, dynamic choice {S4.E2, S2.E2}
  - S2.E2, S3.E1, S4.E1, S4.E2, S5.E1: leaves
- **Admitted messages** (`NumberOfMessages` = `TotalEndpointPathLimit` at the frontend): 5 on API 1, 4 on API 2.
- **Checked properties:** invariants `Conservation`, `ABound`, `NsBound`; liveness `AllProcessed`.

This covers sequential stages, fan-in/fan-out, dynamic downstream choice, leaf global limits, and multiple concurrent APIs, with all per-endpoint limits set to 1.

## Run

Java 17+ and `/usr/bin/time` (GNU time). The script fetches [tla2tools.jar v1.7.4](https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar) if it is missing.

```bash
./run-tlc.sh
```

On a 24-core server with ~125 GiB RAM (the defaults above), expect on the order of **~14 hours**.

This uses all CPU cores (`-workers auto`), checks liveness once at the end (`-lncheck final`), disables checkpoints, and enables TLC’s off-heap fingerprint set and `BAQueue`. Optional overrides: `HEAP` (default `32G`), `DIRECT_MEM` (default `64G`), `FPMEM` (default `0.5`), `WORKERS` (default `auto`).

Outputs go under `results/` (created by the script, not checked in):

| File | Contents |
| --- | --- |
| `results/tlc-output.txt` | Full TLC transcript |
| `results/tlc-command.txt` | Exact argv, host, Java version |
| `results/tlc-time.txt` | GNU `time -v` (wall clock, Max RSS) |
| `results/summary.txt` | Parsed topology and statistics |

Changing constants in `RoshanferTest.tla` checks other configurations.

## TLC statistics

Exhaustive BFS of the bundled configuration (`./run-tlc.sh` on octopus1, 24 cores, OpenJDK 17.0.20, TLC 2.19 / tla2tools v1.7.4). **No error was found.**

| | |
| --- | --- |
| States generated | 2,025,770,223 |
| Distinct states | 289,350,580 |
| States left on queue | 0 |
| Search depth (diameter) | 119 |
| Average outdegree | 1 (min 0, max 9, 95th percentile 3) |
| Memory | Max RSS 95.37 GiB (100,007,668 kB); TLC heap 29,127 MB, 65,536 MB off-heap |
| Result | `Model checking completed. No error has been found.` |

TLC’s fingerprint-collision estimates after the run: optimistic 0.027; based on the actual fingerprints 0.1.

Exact command (written to `results/tlc-command.txt`):

```bash
java -XX:+UseParallelGC -Xmx32G -XX:MaxDirectMemorySize=64G \
  -Dtlc2.tool.fp.FPSet.impl=tlc2.tool.fp.OffHeapDiskFPSet \
  -Dtlc2.tool.ModelChecker.BAQueue=true \
  -jar tla2tools.jar \
  -workers auto -lncheck final -checkpoint 0 -cleanup -fpmem 0.5 \
  -metadir .states \
  -config RoshanferTest.cfg RoshanferTest.tla
```

TLC footer from `results/tlc-output.txt`:

```
Model checking completed. No error has been found.
  Estimates of the probability that TLC did not check all reachable states
  because two distinct states had the same fingerprint:
  calculated (optimistic):  val = .027
  based on the actual fingerprints:  val = .1
2025770223 states generated, 289350580 distinct states found, 0 states left on queue.
The depth of the complete state graph search is 119.
The average outdegree of the complete state graph is 1 (minimum is 0, the maximum 9 and the 95th percentile is 3).
```

## Contact
- Farzad Mohammadi, [f.mohammadi24@imperial.ac.uk](mailto:f.mohammadi24@imperial.ac.uk)
- Theo Akande, [theoakande1@gmail.com](mailto:theoakande1@gmail.com)

## License

MIT ([LICENSE](LICENSE)).
