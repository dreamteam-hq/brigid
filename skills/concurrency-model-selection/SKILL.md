---
name: concurrency-model-selection
description: "Concurrency model decision framework — CSP vs actors vs async/await vs structured concurrency, by problem characteristics and language"
triggers:
  - concurrency model
  - CSP vs actors
  - async await
  - structured concurrency
  - data parallelism
  - message passing
  - shared state concurrency
  - concurrent programming
  - goroutines
  - channels
version: "1.0.0"
---

# Concurrency Model Selection

This skill provides a decision framework for choosing the right concurrency model given problem characteristics, language constraints, and operational requirements. It is not an encyclopedia — it focuses on the decision boundaries where picking the wrong model causes real pain.

## The Five Models

### CSP (Communicating Sequential Processes)

Sequential processes that communicate exclusively through typed channels. No shared memory. Composition through channel wiring.

**Core primitives**: channels (buffered/unbuffered), select/alt, goroutines or similar lightweight processes.

**Strengths**:
- Pipeline and fan-out/fan-in patterns fall out naturally
- Bounded work distribution without explicit queues
- Deadlock-freedom is structurally achievable (no locks to get wrong)
- Back-pressure via bounded channels is trivial

**Weaknesses**:
- Fine-grained shared state (e.g., concurrent map updates) is awkward — you end up serializing through a single goroutine
- Channel debugging is harder than lock debugging: deadlocks manifest as goroutine leaks rather than thread hangs
- Overhead per-channel is low but not zero; microbenchmarks against atomics will lose

**Where it lives**: Go (native), Clojure core.async, Crystal, Kotlin channels, Rust crossbeam-channel.

### Actor Model

Isolated processes with private state, communicating through asynchronous message passing. Each actor processes one message at a time.

**Core primitives**: actors/processes, mailboxes, supervision trees, location transparency.

**Strengths**:
- Fault isolation is built in — a crashing actor does not corrupt neighbors
- Supervision trees provide self-healing architecture
- Location transparency enables distribution without code changes
- Natural fit for entities with identity and lifecycle (users, sessions, devices)

**Weaknesses**:
- Single-mailbox bottleneck: a hot actor serializes all its callers
- Message ordering guarantees vary by implementation — causal ordering is not free
- Request/response (ask) patterns add latency and timeout complexity
- Refactoring actor boundaries is expensive once message protocols are established

**Where it lives**: Erlang/OTP (native), Akka (JVM), Microsoft Orleans (.NET), Elixir, Pony.

### Async/Await (Cooperative Scheduling)

Suspendable computations managed by an event loop or executor. The programmer writes sequential-looking code that yields at I/O boundaries.

**Core primitives**: futures/promises, async functions, executors/runtimes, cancellation tokens.

**Strengths**:
- Minimal overhead per task compared to OS threads (thousands to millions of tasks)
- Sequential-looking code for I/O-heavy workloads
- Cancellation propagation through structured APIs
- Ecosystem integration: HTTP frameworks, database drivers, etc.

**Weaknesses**:
- Function coloring problem: async infects call chains; mixing sync and async code is friction-heavy
- Cooperative scheduling means one CPU-bound task blocks the executor unless explicitly yielded
- Debugging is harder — stack traces are fragmented across suspension points
- Pinning and lifetime issues (Rust `Pin<Box<dyn Future>>`) add complexity in systems languages

**Where it lives**: JavaScript/TypeScript (native), Python asyncio, C# Task/ValueTask, Rust async (tokio/async-std), Kotlin coroutines, Swift concurrency.

### Structured Concurrency

Child tasks are scope-bound to their parent. When a scope exits, all child tasks are joined or cancelled. No fire-and-forget.

**Core primitives**: task groups, nurseries/scopes, cancellation scopes, error propagation.

**Strengths**:
- Eliminates orphaned tasks — resource leaks from forgotten fire-and-forget are impossible
- Error propagation is deterministic: parent sees all child failures
- Reasoning about lifetimes is local, not global
- Composes well with async/await as an additional structural constraint

**Weaknesses**:
- Long-lived background tasks need explicit patterns (daemon tasks, detached scopes)
- Not all runtimes support it — retrofitting onto existing async code is invasive
- Can feel restrictive for event-driven architectures where tasks legitimately outlive their creators

**Where it lives**: Java 21+ (virtual threads + StructuredTaskScope), Kotlin coroutineScope, Swift TaskGroup, Python trio/anyio, Rust async (emerging patterns).

### Data Parallelism

The same operation applied to many data elements simultaneously. Exploits hardware parallelism (SIMD, GPU, multi-core) with minimal coordination.

**Core primitives**: parallel iterators, SIMD intrinsics, GPU kernels, vectorized operations.

**Strengths**:
- Scales linearly with hardware for embarrassingly parallel workloads
- No shared mutable state — each element is independent
- Hardware acceleration (GPU, SIMD) provides orders-of-magnitude speedups
- Often expressible as map/filter/reduce without explicit thread management

**Weaknesses**:
- Only applicable when the problem decomposes into independent elements
- Data transfer overhead (CPU-GPU, NUMA) can dominate for small datasets
- Debugging parallel iterators is harder than sequential equivalents
- Irregular parallelism (graph traversal, tree search) is a poor fit

**Where it lives**: Rust Rayon, Java parallel streams, .NET PLINQ, Python multiprocessing/NumPy, CUDA/Vulkan compute, Go errgroup (coarse-grained).

---

## Decision Table: Choosing by Problem Characteristics

| Problem Characteristic | Best Fit | Avoid |
|---|---|---|
| **I/O-bound, many connections** (HTTP servers, proxies) | Async/await | Data parallelism |
| **CPU-bound, independent chunks** (image processing, batch transforms) | Data parallelism | Actors (overhead) |
| **Stateful entities with identity** (user sessions, game entities, IoT devices) | Actors | CSP (no natural entity mapping) |
| **Pipeline with stages** (ETL, stream processing) | CSP | Actors (over-engineered) |
| **Fault tolerance is primary concern** (telecom, payment processing) | Actors (with supervision) | Raw async/await |
| **Short-lived concurrent subtasks** (parallel API calls, scatter-gather) | Structured concurrency | Actors (lifecycle overhead) |
| **Mixed I/O and CPU** (web app with compute-heavy endpoints) | Async/await + data parallelism hybrid | Single model forced everywhere |
| **Shared mutable state, high contention** (concurrent caches, counters) | Locks/atomics directly | CSP (serialization bottleneck) |
| **Request/response with timeouts** (microservice calls) | Async/await + structured concurrency | Actors (ask pattern complexity) |
| **Long-running background workflows** (batch jobs, cron-like) | CSP or actors | Structured concurrency (scope mismatch) |

### Hybrid patterns that work

- **Async/await + structured concurrency**: The dominant modern pattern. Use async for I/O, structured scoping for task lifecycle.
- **Async/await + data parallelism**: Offload CPU work to a thread pool from within an async context. Common in web services that occasionally do heavy computation.
- **CSP + actors**: Use channels for pipeline plumbing, actors for stateful entities within pipeline stages. Erlang and Go codebases often blend these.
- **Actors + structured concurrency**: Actor message handlers spawn scoped subtask groups for parallel processing within a single message.

### Anti-patterns

- **Actors for stateless request handling**: Actors add overhead (mailbox, scheduling) that buys nothing when there is no state to protect. Use async/await.
- **CSP for entity management**: Modeling 100k user sessions as goroutine-per-session with channels works but is harder to reason about than actors with explicit identity.
- **Data parallelism for I/O**: Parallel iterators over network calls waste threads waiting on I/O. Use async instead.
- **Raw threads everywhere**: If you are managing threads directly in 2025+, you are likely re-inventing a worse version of one of these models.
- **Mixing models without boundaries**: Pick one primary model per architectural layer. Mixing CSP and actors in the same module creates confusion about which communication style governs.

---

## Language-Specific Recommendations

### Go

**Primary model**: CSP (goroutines + channels). It is the language's native concurrency model and the ecosystem is built around it.

**When to reach beyond CSP**:
- High-contention shared state: use `sync.Mutex`, `sync.Map`, or `atomic` directly rather than serializing through a channel.
- Data parallelism: `errgroup` for coarse-grained; for fine-grained, consider calling into C/Rust via CGo or using specialized libraries.
- Structured concurrency: `errgroup.Group` with context cancellation provides scope-bound task management.

### Rust

**Primary model**: Async/await (tokio) for I/O-heavy; Rayon for CPU-heavy. The ownership system makes shared-state concurrency safer than in other languages.

**When to reach beyond async/await**:
- CPU-bound work: Rayon parallel iterators, not `tokio::spawn_blocking` (which wastes the async runtime's blocking pool).
- Actors: `actix` exists but the actor pattern is less natural in Rust due to ownership constraints on message types. Consider channels (crossbeam, tokio::mpsc) instead.
- Structured concurrency: `tokio::JoinSet` provides scope-bound task management.

### C# / .NET

**Primary model**: Async/await with `Task`/`ValueTask`. The runtime, frameworks, and ecosystem assume this model.

**When to reach beyond async/await**:
- Data parallelism: `Parallel.ForEachAsync`, PLINQ, or `System.Numerics.Vector<T>` for SIMD.
- Actors: Orleans for virtual actors (grains) when you need stateful distributed entities.
- Structured concurrency: Not natively supported; approximate with `Task.WhenAll` + `CancellationTokenSource` linking.

### Python

**Primary model**: `asyncio` for I/O-bound; `multiprocessing` for CPU-bound (GIL bypass). The GIL means threading is not useful for CPU parallelism.

**When to reach beyond asyncio**:
- CPU parallelism: `multiprocessing`, `concurrent.futures.ProcessPoolExecutor`, or NumPy/Pandas vectorized operations.
- Structured concurrency: `trio` or `anyio` for scope-bound task management. Prefer these over raw `asyncio.gather`.
- Actors: Not common in Python; Ray provides actor semantics for distributed workloads.

### TypeScript / JavaScript

**Primary model**: Async/await with Promises. Single-threaded event loop; concurrency is cooperative by design.

**When to reach beyond async/await**:
- CPU parallelism: Web Workers (browser) or Worker Threads (Node.js). Heavy computation blocks the event loop otherwise.
- Structured concurrency: `Promise.allSettled` + `AbortController` provides partial structured semantics. No native scope-bound tasks.
- Streaming: Node.js streams or Web Streams API for backpressure-aware pipelines.

### Java

**Primary model**: Virtual threads (Loom) + structured concurrency for new code. Thread-per-request is viable again with virtual threads.

**When to reach beyond virtual threads**:
- Data parallelism: parallel streams, `ForkJoinPool` for recursive decomposition.
- Actors: Akka when you need supervision trees and distribution. Overkill for single-JVM concurrency.
- Reactive: Project Reactor / RxJava only when backpressure on streaming data is the primary concern. Do not use reactive for ordinary request/response.

### GDScript (Godot)

**Primary model**: Cooperative multitasking via signals and `await`. Godot's scene tree is single-threaded by default.

**When to reach beyond signals/await**:
- CPU-bound: `WorkerThreadPool` for physics, pathfinding, terrain generation. Keep rendering on the main thread.
- Data parallelism: GDExtension (C++/Rust) for SIMD or GPU compute via Vulkan compute shaders.
- Avoid: Threading the scene tree. Godot nodes are not thread-safe. Isolate threaded work from scene state.

---

## Correctness Considerations

### Common failure modes by model

| Model | Typical Bug | Mitigation |
|---|---|---|
| CSP | Goroutine leak (blocked on channel nobody reads) | Context cancellation, bounded channels, leak detectors (goleak) |
| Actors | Mailbox overflow under load | Back-pressure protocols, bounded mailboxes, load shedding |
| Async/await | Executor starvation from blocking call | Dedicated blocking thread pool, lint rules against sync I/O in async |
| Structured concurrency | Scope too narrow (task cancelled prematurely) | Design scopes around logical operations, not syntactic blocks |
| Data parallelism | False sharing on cache lines | Padding, per-thread accumulators, reduction patterns |

### When to use locks and atomics directly

The five models above are not exhaustive. Sometimes the right answer is a mutex, a read-write lock, or an atomic counter:

- **Low-contention shared state**: A `Mutex<HashMap>` in Rust or `sync.RWMutex` in Go is simpler and faster than a channel or actor for a config cache read 1000x per second and written once per minute.
- **Counters and flags**: Atomics (`AtomicU64`, `atomic.Int64`) for metrics, feature flags, reference counts. No model overhead needed.
- **Lock-free structures**: When profiling shows contention on a specific data structure, consider lock-free alternatives (crossbeam SkipMap, Java ConcurrentHashMap). But measure first — lock-free is not always faster.

---

## Cross-References

- **Language-specific deep dives**: Load the relevant language skill (e.g., `cross-language-interop`, `roslyn-analyzers` for .NET, `rust-project-patterns`) for implementation details beyond concurrency.
- **Distributed systems**: Concurrency models operate within a single process. For cross-process coordination (consensus, distributed transactions, CRDTs), the problem is fundamentally different — network partitions and partial failure change the rules.
- **Performance profiling**: The choice of concurrency model affects profiling strategy. Async stack traces differ from thread stack traces. Actor mailbox depth is a key metric. Channel utilization reveals pipeline bottlenecks.
