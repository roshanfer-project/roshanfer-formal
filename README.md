# Roshanfer TLA+ model — EuroSys 2027

TLA+ specification of the Request Limit Protocol from §5 of **Roshanfer: Achieving Performance Resilience in Cloud Microservices** (EuroSys 2027, paper #1195). This directory is the spec the paper points to in Supplementary Materials.

## Files

| File | Role |
| --- | --- |
| `Roshanfer.tla` | Protocol (Ingress, Agent, Server) |
| `RoshanferTest.tla` | One finite configuration |
| `RoshanferTest.cfg` | TLC configuration |
| `Utils.tla` | Sequence and set helpers |

## Properties

TLC exhaustively checks these on the bundled configuration:

- **Request Bound.** Active requests at an endpoint stay within that endpoint’s local limit plus the bounds of its immediate downstream endpoints. There is no unbounded queueing inside the service.
- **Deadlock Freedom.** Every request admitted at Ingress receives a response, assuming processing inside the microservices terminates.
- **Work Conservation.** Credit requests queue at a microservice only if that microservice, or some downstream of it, has sufficient active requests to exhaust its local limit. The protocol does not stall upstream microservices when there exists no downstream microservice that is at its processing capacity.

## Run

**Where:** laptop. Java 11+. TLC from [tla2tools.jar v1.7.4](https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar).

**What:**

```bash
curl -L -o tla2tools.jar \
  https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar
java -XX:+UseParallelGC -jar tla2tools.jar \
  -config RoshanferTest.cfg RoshanferTest.tla
```

**Expected:** `Model checking completed. No error has been found.`

Changing constants in `RoshanferTest.tla` checks other configurations.

## Contact
- Farzad Mohammadi, [f.mohammadi24@imperial.ac.uk](mailto:f.mohammadi24@imperial.ac.uk)
- Theo Akande, [theoakande1@gmail.com](mailto:theoakande1@gmail.com)

## License

MIT ([LICENSE](LICENSE)). 



