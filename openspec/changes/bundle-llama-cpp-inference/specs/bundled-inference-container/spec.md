## ADDED Requirements

### Requirement: Bundled Inference Container Image

The project SHALL provide a `bundled` container image target that ships a
CPU-based `llama.cpp` inference server together with the engine, so that
Relagent can answer conversations with no externally configured inference
provider.

The default engine image (the `slim` target) SHALL remain provider-less and
SHALL continue to require an externally configured OpenAI-compatible endpoint.

#### Scenario: Bundled target builds a self-contained image

- **WHEN** the container images are built
- **THEN** a `bundled` target SHALL be produced in addition to the default engine image
- **AND** the bundled image SHALL contain a `llama.cpp` server and the engine
- **AND** the bundled image tag SHALL be distinguished by a `-bundled` suffix

#### Scenario: Default image stays provider-less

- **WHEN** the default (non-bundled) engine image is run
- **THEN** it SHALL NOT include an inference server
- **AND** it SHALL require an externally configured `PROVIDER_API_BASE`

### Requirement: Bundled Provider Is For Demo And First-Try Use Only

The bundled inference container SHALL be positioned for demonstration,
showcasing, and first-try / evaluation use. It SHALL NOT be presented as a
productive or permanent deployment option.

User-facing documentation SHALL state that the bundled inference server offers
only limited performance and SHALL point productive deployments at a dedicated
external inference provider.

#### Scenario: Documentation frames the bundled image as a trial option

- **WHEN** installation documentation describes the bundled image
- **THEN** it SHALL describe the bundled image as the easiest way to try Relagent out
- **AND** it SHALL state that the bundled provider gives only limited performance
- **AND** it SHALL recommend an external inference provider for productive or permanent installations

#### Scenario: Performance expectations are set up front

- **WHEN** a user runs the bundled image for the first time
- **THEN** the documentation SHALL have told them a model is downloaded on first start
- **AND** SHALL have told them to expect multi-second response times on CPU

### Requirement: Bundled Server Lifecycle

When the bundled image runs (`PROVIDER_BUNDLED=true`), the entrypoint SHALL start
the bundled inference server and point the engine's `PROVIDER_API_BASE` at it
before launching the engine. The bundled server SHALL be bound to loopback and
SHALL be configured for modest, single-user CPU inference.

#### Scenario: Entrypoint starts the bundled server and wires the engine to it

- **GIVEN** the container runs with `PROVIDER_BUNDLED=true`
- **WHEN** the entrypoint executes
- **THEN** it SHALL start the bundled `llama.cpp` server on a loopback address
- **AND** SHALL set `PROVIDER_API_BASE` to that server before starting the engine
- **AND** SHALL apply a default model when none is configured

#### Scenario: Engine is reachable before the model is ready

- **GIVEN** the bundled image is starting for the first time
- **WHEN** the engine API is already accepting requests but the model is still loading or downloading
- **THEN** an inference request SHALL fail in a recoverable way
- **AND** the failure SHALL be reported per the `engine-error-reporting` capability (retryable, descriptive)
