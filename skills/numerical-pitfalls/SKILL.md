---
name: numerical-pitfalls
description: >
  Floating-point gotchas and determinism for game and simulation code — IEEE 754
  compliance gaps, fixed-point arithmetic, large-world precision, physics stability,
  hashing/equality, angle representations, and RNG for games. Load when the user
  mentions "floating point", "float precision", "determinism", "fixed point",
  "large world", "origin rebasing", "physics stability", "epsilon comparison",
  "PRNG", "numerical precision", "cross-platform lockstep", or "FMA variance".
  Triggers: floating point, float precision, determinism, fixed point arithmetic, large world, origin rebasing, physics stability, epsilon comparison, PRNG, numerical precision.
---

# Numerical Pitfalls

## Floating-Point Determinism

IEEE 754 guarantees bit-exact results for `+`, `-`, `*`, `/`, and `sqrt` — **if** both sides use the same rounding mode and precision. In practice, that guarantee breaks constantly.

### Where IEEE 754 Compliance Gaps Appear

| Source | What Goes Wrong | Impact |
|--------|----------------|--------|
| FMA (fused multiply-add) | `a * b + c` computed as one op with single rounding vs two ops with two roundings | 1 ULP difference per operation; accumulates fast |
| x87 FPU (legacy x86) | 80-bit extended precision intermediate values | Different results from SSE2 (64-bit); spilling to memory truncates |
| Compiler reordering | `(a + b) + c` rewritten as `a + (b + c)` — not equivalent in float | Non-deterministic across optimization levels |
| `-ffast-math` / `/fp:fast` | Enables reassociation, reciprocal approximation, NaN assumption removal | Completely breaks determinism; never use for lockstep |
| Denormals | Some hardware flushes denormals to zero (DAZ/FTZ flags) | Different results near zero on different CPUs |
| Math library (`sin`, `cos`, `exp`) | Not required to be correctly rounded by IEEE 754; implementations vary | `sinf(x)` can differ by 1-3 ULP across platforms |

### FMA Variance in Detail

FMA is the single largest source of cross-platform float divergence:

```c
// These are NOT equivalent in IEEE 754:
float result_fma = fma(a, b, c);        // One rounding: round(a*b + c)
float result_sep = (a * b) + c;          // Two roundings: round(round(a*b) + c)
```

ARM64 has hardware FMA and compilers use it aggressively. x86-64 has FMA3 (Haswell+) but older CPUs do not. When one player runs ARM and another runs x86-without-FMA3, lockstep desynchronizes within seconds.

**Mitigation strategies:**

| Strategy | Portability | Performance Cost | Determinism |
|----------|------------|-----------------|-------------|
| Force FMA everywhere (`-mfma`) | Requires FMA hardware on all targets | None (faster) | Cross-platform if all have FMA |
| Disable FMA (`-ffp-contract=off`) | Universal | 5-15% in math-heavy code | Deterministic across FMA/non-FMA |
| Software FMA emulation | Universal | Severe (10-50x for FMA-heavy code) | Bit-exact everywhere |
| Use fixed-point for deterministic paths | Universal | Moderate | Bit-exact by construction |

**Recommendation for cross-platform lockstep:** Use `-ffp-contract=off` (Clang/GCC) or `/fp:precise` (MSVC). Accept the performance cost on FMA-capable hardware. Reserve FMA for non-deterministic paths (rendering, audio).

### `-ffast-math` Pitfalls

`-ffast-math` (GCC/Clang) is shorthand for a bundle of flags:

| Sub-flag | What It Allows | What It Breaks |
|----------|---------------|----------------|
| `-ffinite-math-only` | Assumes no NaN/Inf | `isnan()` returns false always; NaN propagation disappears |
| `-fno-signed-zeros` | Treats -0.0 as +0.0 | Breaks `atan2`, edge cases in physics reflection |
| `-freciprocal-math` | Replaces `a / b` with `a * (1/b)` | Changes results by several ULP |
| `-fassociative-math` | Reorders float operations | `(a+b)+c != a+(b+c)` in float; reorder changes result |
| `-fno-trapping-math` | Removes exception traps | Cannot detect overflow/invalid at runtime |
| `-funsafe-math-optimizations` | All of the above | Everything above combined |

**Never use `-ffast-math` in game simulation code.** It is acceptable for shaders (GPU already non-deterministic), audio DSP (perceptual tolerance), and offline tools.

### Cross-Platform Lockstep Checklist

1. **Compiler flags**: `-ffp-contract=off -fno-fast-math` (or MSVC `/fp:precise`)
2. **FPU control word**: Set SSE2 mode on x86, disable x87 extended precision
3. **Denormal handling**: Explicitly set DAZ+FTZ or explicitly leave them off — same on all platforms
4. **Math functions**: Use a deterministic math library (e.g., libfixmath, or hand-rolled polynomial approximations)
5. **Operation order**: Avoid compiler reordering by using volatile intermediates or explicit parenthesization
6. **Validation**: Run the same simulation on all target platforms and compare state hashes every frame

```c
// Example: setting consistent FPU state on x86-64
#include <xmmintrin.h>
#include <pmmintrin.h>

void set_deterministic_fpu_state(void) {
    // Flush denormals to zero — must match on all platforms
    _mm_setcsr(_mm_getcsr() | _MM_FLUSH_ZERO_ON | _MM_DENORMALS_ZERO_ON);
    // Round to nearest, ties to even (IEEE default)
    _mm_setcsr((_mm_getcsr() & ~_MM_ROUND_MASK) | _MM_ROUND_NEAREST);
}
```

## Fixed-Point Arithmetic

When floating-point determinism is too expensive or fragile, fixed-point gives you bit-exact cross-platform math by construction. The tradeoff is reduced range and more careful overflow management.

### When to Use Fixed-Point

| Use Case | Use Fixed-Point? | Reason |
|----------|-----------------|--------|
| Lockstep multiplayer simulation | Yes | Bit-exact across all platforms without compiler flag gymnastics |
| Financial/currency systems | Yes | Exact decimal representation; no 0.1 + 0.2 surprises |
| Embedded/no-FPU targets | Yes | No hardware float support |
| Physics with known bounds | Often | Predictable precision within the bounded range |
| Rendering / shaders | No | GPU is natively float; fixed-point is slower and less precise |
| Audio DSP | Rarely | Float gives better dynamic range for signal processing |
| General gameplay logic | Depends | If precision bugs cause desyncs, yes; otherwise float is simpler |

### Q-Format Notation

Fixed-point numbers are described using Q-format: `Qm.n` where `m` is integer bits and `n` is fractional bits. The total storage is `m + n + 1` bits (the +1 is the sign bit for signed types).

| Format | Storage | Integer Range | Fractional Resolution | Example Use |
|--------|---------|--------------|----------------------|-------------|
| Q16.16 | 32-bit | -32768 to 32767 | 1/65536 ~= 0.000015 | Position in a bounded world |
| Q8.24 | 32-bit | -128 to 127 | 1/16777216 ~= 0.00000006 | Normalized values, interpolation |
| Q32.32 | 64-bit | -2B to 2B | 1/4294967296 | Large-world position with sub-millimeter precision |
| Q1.15 | 16-bit | -1 to ~1 | 1/32768 | Audio samples, unit vectors |
| Q0.32 | 32-bit | 0 to ~1 (unsigned) | 1/4294967296 | Probability, blend weights |

### Implementation Patterns

```c
// Q16.16 fixed-point type
typedef int32_t fixed_t;
#define FIXED_SHIFT 16
#define FIXED_ONE   (1 << FIXED_SHIFT)      // 65536
#define FIXED_HALF  (1 << (FIXED_SHIFT - 1)) // 32768

// Conversion
#define INT_TO_FIXED(x)   ((fixed_t)(x) << FIXED_SHIFT)
#define FLOAT_TO_FIXED(x) ((fixed_t)((x) * FIXED_ONE + ((x) >= 0 ? 0.5f : -0.5f)))
#define FIXED_TO_FLOAT(x) ((float)(x) / FIXED_ONE)
#define FIXED_TO_INT(x)   ((x) >> FIXED_SHIFT)  // Truncates toward negative infinity

// Arithmetic
#define FIXED_ADD(a, b) ((a) + (b))  // Watch for overflow
#define FIXED_SUB(a, b) ((a) - (b))
#define FIXED_MUL(a, b) ((fixed_t)(((int64_t)(a) * (b)) >> FIXED_SHIFT))
#define FIXED_DIV(a, b) ((fixed_t)(((int64_t)(a) << FIXED_SHIFT) / (b)))

// Overflow-safe multiply with saturation
static inline fixed_t fixed_mul_sat(fixed_t a, fixed_t b) {
    int64_t result = ((int64_t)a * b) >> FIXED_SHIFT;
    if (result > INT32_MAX) return INT32_MAX;
    if (result < INT32_MIN) return INT32_MIN;
    return (fixed_t)result;
}
```

```gdscript
# GDScript fixed-point helper (for deterministic Godot multiplayer)
const FIXED_SHIFT := 16
const FIXED_ONE := 1 << FIXED_SHIFT

static func to_fixed(f: float) -> int:
    return roundi(f * FIXED_ONE)

static func to_float(fx: int) -> float:
    return float(fx) / FIXED_ONE

static func fixed_mul(a: int, b: int) -> int:
    return (a * b) >> FIXED_SHIFT

static func fixed_div(a: int, b: int) -> int:
    return (a << FIXED_SHIFT) / b
```

### Performance Trade-Offs

| Operation | Float (x86 SSE) | Fixed Q16.16 | Notes |
|-----------|-----------------|-------------|-------|
| Add/Sub | 1 cycle | 1 cycle | Same — both are integer ops internally on modern CPUs |
| Multiply | 1 cycle (mul) | 2 cycles (imul + shift) | Widen to 64-bit then shift back |
| Divide | 10-15 cycles | 20-30 cycles | 64-bit shift then idiv; significantly slower |
| Sqrt | 10-15 cycles | 40-100 cycles | No hardware support; iterative (Newton-Raphson) |
| Sin/Cos | 50-100 cycles (libm) | 10-30 cycles (lookup table) | Fixed-point wins with lookup tables + interpolation |
| SIMD width | 4x float32 / 8x float32 | 4x int32 / 8x int32 | Same throughput but float SIMD has richer instruction set |

## Large-World Precision

Standard `float32` gives ~7 decimal digits of precision. At 10 km from origin, you lose sub-millimeter precision. At 100 km, you lose centimeter precision. This is called "large-world jitter" and it manifests as:

- Mesh vertices snapping to a visible grid
- Physics objects vibrating or drifting
- Camera stuttering at large coordinates
- Particle systems misaligning

### Precision Loss by Distance from Origin

| Distance from Origin | float32 Precision | Visible Effect |
|---------------------|-------------------|----------------|
| 0-100 m | ~0.001 mm | None |
| 1 km | ~0.06 mm | None |
| 10 km | ~1 mm | Subtle mesh shimmer |
| 100 km | ~8 mm | Visible vertex snapping, physics jitter |
| 1,000 km | ~64 mm | Severe jitter, unusable physics |
| 10,000 km | ~1 m | Completely broken |
| Earth radius (6,371 km) | ~0.5 m | Terrain cannot represent features < 0.5 m |

### Decision Table by World Size

| World Radius | Recommended Strategy | Complexity | Engine Support |
|-------------|---------------------|-----------|----------------|
| < 5 km | No action needed | None | All engines |
| 5-50 km | Floating origin | Low | Godot: manual; Unity: built-in; Unreal: World Partition |
| 50-500 km | Origin rebasing + chunked streaming | Medium | Unreal World Partition; Godot: manual |
| 500 km - planet | Double-precision + relative coords | High | Custom / Unreal LWC (Large World Coordinates) |
| Multi-planet / space | Nested coordinate frames | Very high | Custom engine (Space Engineers, KSP approach) |

### Origin Rebasing (Floating Origin Pattern)

The simplest large-world fix: when the camera moves far from origin, teleport everything back to re-center the camera near (0, 0, 0).

```gdscript
# Godot 4 floating origin implementation
extends Node3D

const REBASE_THRESHOLD := 4096.0  # Rebase when camera exceeds this distance from origin

@onready var camera: Camera3D = $Camera3D

func _physics_process(_delta: float) -> void:
    var cam_pos := camera.global_position
    if cam_pos.length() > REBASE_THRESHOLD:
        _rebase_world(cam_pos)

func _rebase_world(offset: Vector3) -> void:
    # Shift all top-level nodes
    for child in get_children():
        if child is Node3D:
            child.global_position -= offset

    # If using physics, wake sleeping bodies after rebase
    for body in get_tree().get_nodes_in_group("physics_bodies"):
        if body is RigidBody3D:
            body.sleeping = false

    # Update any world-space tracking (minimap coords, etc.)
    world_offset += offset  # Accumulate total offset for absolute positioning
```

### Relative Coordinates

For physics and rendering, compute everything relative to a local reference frame rather than absolute world coordinates.

```c
// Instead of: position_world = entity.position
// Compute:    position_relative = entity.position - reference.position

typedef struct {
    int64_t x, y, z;      // Absolute position in fixed-point (large range)
} world_pos_t;

typedef struct {
    float x, y, z;         // Relative position in float (high local precision)
} local_pos_t;

local_pos_t world_to_local(world_pos_t entity, world_pos_t reference) {
    // Subtraction in integer space (exact), then convert to float
    local_pos_t local;
    local.x = (float)(entity.x - reference.x) / FIXED_SCALE;
    local.y = (float)(entity.y - reference.y) / FIXED_SCALE;
    local.z = (float)(entity.z - reference.z) / FIXED_SCALE;
    return local;
}
```

### Double-Precision Fallback

Use `float64` for position storage and simulation, `float32` for rendering. This gives sub-millimeter precision out to ~1 million km.

```gdscript
# Godot: store canonical positions as Vector2/Vector3 won't help (they're float32)
# Use a custom double-precision position class
class_name PrecisePosition

var x: float  # Godot float is 64-bit in GDScript
var y: float
var z: float

# Convert to engine Vector3 relative to camera for rendering
func to_render_position(camera_precise: PrecisePosition) -> Vector3:
    return Vector3(
        x - camera_precise.x,
        y - camera_precise.y,
        z - camera_precise.z
    )
```

**Note:** GDScript `float` is 64-bit (double), but Godot's `Vector3` uses 32-bit floats internally. Store precise positions as individual floats, convert to Vector3 only for rendering.

## Physics Accumulation

Numerical integration of physics equations accumulates error every frame. The choice of integrator determines how fast errors grow and whether they cause energy gain (explosion) or energy loss (damping).

### Euler vs Verlet vs RK4

| Integrator | Order | Energy Conservation | Stability | Cost per Step | Best For |
|-----------|-------|-------------------|-----------|--------------|---------|
| Explicit Euler | 1st | Gains energy over time | Poor — explodes at high dt | 1 force eval | Never (except prototypes) |
| Semi-implicit Euler (Symplectic) | 1st | Bounded error, no drift | Good for fixed dt | 1 force eval | Most game physics |
| Verlet (position) | 2nd | Excellent (symplectic) | Very good | 1 force eval | Particle systems, cloth |
| Velocity Verlet (Stormer-Verlet) | 2nd | Excellent (symplectic) | Very good | 2 force evals | Rigid body, molecular dynamics |
| RK4 (Runge-Kutta 4th order) | 4th | Good but not symplectic | Excellent for smooth forces | 4 force evals | Orbital mechanics, high-accuracy |

### Why Symplectic Integrators Matter for Games

A symplectic integrator preserves the phase-space volume of the system — in practical terms, total energy oscillates around the true value but never drifts. Explicit Euler is **not** symplectic and will visibly pump energy into springs, pendulums, and orbits.

```c
// WRONG: Explicit Euler — energy increases every frame
void euler_step(float *pos, float *vel, float accel, float dt) {
    *pos += *vel * dt;      // Uses old velocity
    *vel += accel * dt;
}

// RIGHT: Semi-implicit (Symplectic) Euler — bounded energy error
void symplectic_euler_step(float *pos, float *vel, float accel, float dt) {
    *vel += accel * dt;     // Update velocity FIRST
    *pos += *vel * dt;      // Use NEW velocity
}

// BETTER: Velocity Verlet — second-order, symplectic
void verlet_step(float *pos, float *vel, float accel_old, float dt,
                 float (*compute_accel)(float pos)) {
    *pos += *vel * dt + 0.5f * accel_old * dt * dt;
    float accel_new = compute_accel(*pos);
    *vel += 0.5f * (accel_old + accel_new) * dt;
}
```

### Sub-Step Strategies

When the physics timestep is too large, splitting it into sub-steps improves stability without changing the integrator.

| Strategy | How It Works | When to Use |
|----------|-------------|-------------|
| Fixed sub-stepping | Run N smaller steps per frame | Known stiff systems (springs, joints) |
| Adaptive sub-stepping | Estimate error, subdivide if too large | Variable stiffness; orbital mechanics |
| Interpolated rendering | Physics at fixed rate, render interpolates between states | Decoupling physics from frame rate (the standard approach) |

```gdscript
# Godot: fixed physics with interpolated rendering
# In Project Settings: Physics > Common > Physics Ticks Per Second = 60
# Enable Physics > Common > Physics Interpolation = true

# For custom sub-stepping:
const SUB_STEPS := 4

func _physics_process(delta: float) -> void:
    var sub_dt := delta / SUB_STEPS
    for i in SUB_STEPS:
        _simulate_step(sub_dt)
```

### Common Accumulation Bugs

| Bug | Symptom | Root Cause | Fix |
|-----|---------|-----------|-----|
| Spring explosion | Objects fly to infinity | dt too large for spring constant; Euler integration | Use symplectic Euler + sub-steps; clamp velocity |
| Energy drift in orbits | Orbits spiral inward or outward | Non-symplectic integrator (Euler/RK4) over long time | Use Verlet; or apply energy correction |
| Frame-rate dependent physics | Physics runs faster/slower on different machines | Using frame delta for physics instead of fixed timestep | Fixed timestep with accumulator pattern |
| Velocity clamping artifacts | Objects "stick" to surfaces or jitter | Max velocity clamp prevents proper restitution | Clamp energy, not velocity; or clamp after integration only |

## Hashing and Equality

Floating-point equality is broken by design. `0.1 + 0.2 != 0.3` in IEEE 754. This affects hash maps, deduplication, spatial hashing, and any code that uses floats as keys or comparisons.

### Epsilon Comparison Patterns

```c
// WRONG: absolute epsilon fails for large and small values
bool equal_wrong(float a, float b) {
    return fabsf(a - b) < 0.0001f;  // Too small for large values, too large for small
}

// BETTER: relative epsilon
bool equal_relative(float a, float b, float rel_eps) {
    float diff = fabsf(a - b);
    float largest = fmaxf(fabsf(a), fabsf(b));
    return diff <= largest * rel_eps;
}

// BEST: combined absolute + relative (handles near-zero values)
bool equal_robust(float a, float b, float abs_eps, float rel_eps) {
    float diff = fabsf(a - b);
    if (diff <= abs_eps) return true;           // Catches near-zero
    float largest = fmaxf(fabsf(a), fabsf(b));
    return diff <= largest * rel_eps;           // Relative for larger values
}

// ULP-based comparison (most mathematically sound)
bool equal_ulps(float a, float b, int max_ulps) {
    // Reinterpret as integers; nearby floats have nearby integer representations
    int32_t ia, ib;
    memcpy(&ia, &a, sizeof(float));
    memcpy(&ib, &b, sizeof(float));
    // Handle sign mismatch (except +0 / -0)
    if ((ia < 0) != (ib < 0)) return a == b;
    int32_t ulp_diff = abs(ia - ib);
    return ulp_diff <= max_ulps;
}
```

### Hashable Coordinate Strategies

Floats should never be hash-map keys directly. Strategies:

| Strategy | How | Precision | Use Case |
|----------|-----|-----------|----------|
| Snap to grid | `int key = (int)(x / grid_size)` | Grid-size dependent | Spatial hashing, tile maps |
| Quantize to int | `int key = (int)roundf(x * 1000)` | Fixed (here: 0.001) | Deduplication with known precision |
| Canonical form | Flush denormals, normalize -0 to +0 | Bit-exact | When you need exact float keys (rare) |
| Use integer positions | Store positions as fixed-point ints | Exact | Deterministic multiplayer |

```c
// Spatial hash using grid snapping
typedef struct { int x, y; } grid_key_t;

grid_key_t position_to_grid(float px, float py, float cell_size) {
    return (grid_key_t){
        .x = (int)floorf(px / cell_size),
        .y = (int)floorf(py / cell_size)
    };
}

uint32_t grid_hash(grid_key_t key) {
    // Simple hash combining; use a better hash for production
    return (uint32_t)(key.x * 73856093) ^ (uint32_t)(key.y * 19349663);
}
```

## Angle Representations

The choice of angle representation affects precision, wrapping behavior, and interoperability with math libraries and engines.

### Comparison Table

| Representation | Range | Wrapping | Precision Notes | Typical Use |
|---------------|-------|----------|----------------|-------------|
| Degrees | 0-360 or -180 to 180 | Modulo 360 | Human-readable; `sin(180)` != 0 exactly | UI display, level editors |
| Radians | 0 to 2pi or -pi to pi | Modulo 2pi | `sin`/`cos` expect this; pi is irrational so no float is exact | Math libraries, physics |
| Turns | 0.0 to 1.0 | Modulo 1.0 | Full rotation = 1.0; clean fractions (0.25 = 90 deg exactly) | Shaders, animation blend |
| Fixed-point (brads) | 0 to 65535 (uint16) | Free overflow wrapping | 360/65536 ~= 0.0055 deg resolution; wrapping is automatic via integer overflow | Deterministic multiplayer |

### Wrapping Pitfalls

```c
// WRONG: naive angle difference fails at wraparound
float angle_diff_wrong(float a, float b) {
    return a - b;  // If a=350, b=10, returns 340 instead of -20
}

// RIGHT: shortest-path angle difference in degrees
float angle_diff_degrees(float a, float b) {
    float diff = fmodf(a - b + 540.0f, 360.0f) - 180.0f;
    return diff;
}

// RIGHT: shortest-path angle difference in radians
float angle_diff_radians(float a, float b) {
    float diff = fmodf(a - b + 3.0f * M_PI, 2.0f * M_PI) - M_PI;
    return diff;
}

// BEST: binary angles (brads) — wrapping is free
uint16_t angle_diff_brads(uint16_t a, uint16_t b) {
    return a - b;  // Integer underflow wraps correctly; result is signed via cast to int16_t
}
int16_t signed_angle_diff_brads(uint16_t a, uint16_t b) {
    return (int16_t)(a - b);  // Shortest-path signed difference, automatic wrapping
}
```

### Binary Angles (Brads) for Deterministic Games

Binary angles store angles as unsigned integers where the full range (0 to 2^N-1) maps to one full revolution. Wrapping happens for free via integer overflow.

```c
// Lookup-table sin/cos for brads — bit-exact across all platforms
#define BRAD_TABLE_SIZE 65536
static float sin_table[BRAD_TABLE_SIZE];  // Precomputed at startup

void init_brad_tables(void) {
    for (int i = 0; i < BRAD_TABLE_SIZE; i++) {
        sin_table[i] = sinf((float)i * (2.0f * M_PI / BRAD_TABLE_SIZE));
    }
}

float brad_sin(uint16_t angle) { return sin_table[angle]; }
float brad_cos(uint16_t angle) { return sin_table[(uint16_t)(angle + 16384)]; }
```

## RNG for Games

Games need random numbers for procedural generation, AI decisions, loot drops, particle effects, and multiplayer synchronization. The requirements differ sharply from cryptographic RNG.

### Requirements by Use Case

| Use Case | Deterministic? | Speed | Quality | Distribution |
|----------|---------------|-------|---------|-------------|
| Procedural world gen | Yes — same seed = same world | High | Good uniformity | Varies (Perlin noise, uniform, etc.) |
| Lockstep multiplayer | Yes — all clients must agree | High | Moderate | Uniform, sometimes weighted |
| AI decisions | Usually no | Low-moderate | Low | Weighted/probability |
| Loot / drop tables | Yes (for fairness/replay) | Low | Moderate | Weighted discrete |
| Particle effects | No | Very high | Low | Uniform, Gaussian |
| Shuffle / deck draw | Yes (for replay) | Low | High (no bias) | Permutation |

### PRNG Algorithms for Games

| Algorithm | State Size | Period | Speed | Quality | Notes |
|-----------|-----------|--------|-------|---------|-------|
| PCG32 | 16 bytes | 2^64 | Very fast | Excellent | Best general-purpose choice for games |
| xoshiro256** | 32 bytes | 2^256 - 1 | Very fast | Excellent | Good for parallel streams; jump function |
| xorshift128+ | 16 bytes | 2^128 - 1 | Fastest | Good | Used by V8/SpiderMonkey for Math.random() |
| SplitMix64 | 8 bytes | 2^64 | Very fast | Good | Best for seeding other PRNGs |
| Mersenne Twister | 2.5 KB | 2^19937 - 1 | Fast | Overkill | Too much state for games; slow to seed |
| LCG (minstd) | 4-8 bytes | 2^31 | Fastest | Poor | Low bits have short period; avoid |
| ChaCha8 | 64 bytes | 2^128 | Moderate | Cryptographic | When you need unpredictable RNG (anti-cheat) |

**Recommendation:** Use **PCG32** for most game RNG. Use **xoshiro256**** when you need multiple independent streams (parallel world gen). Use **SplitMix64** to derive seeds from a master seed.

### Seed Synchronization in Multiplayer

In lockstep multiplayer, all clients must produce the same random sequence:

```c
// Shared seed protocol:
// 1. Host generates master seed (from system entropy)
// 2. Host sends master seed to all clients during game setup
// 3. Each system (physics, AI, loot) derives its own stream

typedef struct {
    uint64_t state;
    uint64_t inc;
} pcg32_t;

// Derive per-system RNG from master seed
void init_game_rng(uint64_t master_seed) {
    // SplitMix64 to derive independent seeds
    uint64_t physics_seed = splitmix64(&master_seed);
    uint64_t ai_seed      = splitmix64(&master_seed);
    uint64_t loot_seed    = splitmix64(&master_seed);

    pcg32_init(&physics_rng, physics_seed, 1);
    pcg32_init(&ai_rng,      ai_seed,      3);
    pcg32_init(&loot_rng,    loot_seed,    5);
}

// SplitMix64 — for seeding only
uint64_t splitmix64(uint64_t *state) {
    uint64_t z = (*state += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}
```

```gdscript
# GDScript: deterministic RNG with Godot's built-in RandomNumberGenerator
var physics_rng := RandomNumberGenerator.new()
var loot_rng := RandomNumberGenerator.new()

func init_from_master_seed(master_seed: int) -> void:
    # Godot's RNG uses PCG internally
    physics_rng.seed = master_seed
    loot_rng.seed = master_seed + 12345  # Offset for independence (simple but effective)

func get_physics_random() -> float:
    return physics_rng.randf()  # Deterministic if seed matches across clients

func roll_loot(weights: PackedFloat32Array) -> int:
    var roll := loot_rng.randf()
    var cumulative := 0.0
    for i in weights.size():
        cumulative += weights[i]
        if roll < cumulative:
            return i
    return weights.size() - 1  # Floating-point safety: catch rounding at the end
```

### Distribution Quality Gotchas

| Pitfall | Example | Fix |
|---------|---------|-----|
| Modulo bias | `rand() % 6` is biased if RAND_MAX is not a multiple of 6 | Rejection sampling: reroll if above largest multiple |
| Float conversion bias | `(float)rand() / RAND_MAX` — boundary values 0.0 and 1.0 are half as likely | Use `(rand() + 0.5) / (RAND_MAX + 1.0)` for open interval |
| Correlated streams | Two PRNGs seeded with sequential seeds | Use SplitMix64 to derive seeds; or use xoshiro jump function |
| Low-bit patterns | LCG low bits cycle with short period | Use upper bits; or switch to PCG/xoshiro |
| Fisher-Yates shuffle bias | Using `rand() % remaining` instead of uniform | Use unbiased bounded random: PCG has `pcg32_boundedrand()` |

## Anti-Patterns Table

| Anti-Pattern | What Goes Wrong | Correct Approach |
|-------------|----------------|-----------------|
| `if (a == b)` on floats | Almost never true after computation | Use epsilon comparison or ULP comparison |
| `-ffast-math` in simulation | Non-deterministic, NaN handling broken | Use `-ffp-contract=off -fno-fast-math` |
| `float` for world positions > 5 km | Sub-centimeter precision lost | Floating origin, double-precision, or fixed-point |
| Explicit Euler for springs | Energy gain, explosion | Symplectic Euler or Verlet |
| `rand() % N` | Modulo bias for non-power-of-2 N | Rejection sampling or bounded random |
| Degrees in math functions | `sin(90)` is not 1.0 (it's in radians) | Always convert: `sin(deg * M_PI / 180.0)` |
| `float` as hash key | Equal values may hash differently | Snap to grid or use integer keys |
| Variable timestep for physics | Frame-rate-dependent behavior | Fixed timestep with accumulator + interpolation |
| Accumulating positions | Error grows O(n) over frames | Accumulate velocity; recompute position from initial + integral |
| Comparing angles by subtraction | Fails at 359-to-1 wraparound | Use shortest-path angle difference or binary angles |
| Using system `sin()`/`cos()` in lockstep | Platform-dependent results | Lookup tables or polynomial approximations, same on all clients |
| Sequential seeds for parallel RNG | Correlated output streams | Derive seeds with SplitMix64 or use PRNG jump functions |
| Storing positions as `float` in save files | Load/save can change precision | Store as fixed-point integers or exact decimal strings |

## Cross-References

- **gamedev-2d-platformer**: Tile-aligned movement benefits from fixed-point or integer coordinates; sub-pixel rendering uses the fractional part
- **gamedev-multiplayer**: Lockstep determinism requires all techniques in the "Floating-Point Determinism" and "RNG for Games" sections; see also rollback netcode interaction with physics sub-stepping
- **gamedev-ecs**: Physics systems in ECS should use Velocity Verlet with fixed timestep; component layout affects whether SIMD-accelerated float ops are viable
- **algorithm-selection-heuristics**: Spatial hashing (in the "Hashing and Equality" section) relates to the spatial data structure decision table
