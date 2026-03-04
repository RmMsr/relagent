## ADDED Requirements

### Requirement: TTS Benchmark Persistence
The system SHALL persist per-model RTF benchmark results in user settings so they survive app restarts and are available without re-running previews.

#### Scenario: Benchmark stored after preview
- **WHEN** a TTS model preview completes
- **THEN** the measured RTF SHALL be written to `ttsModelBenchmarks` keyed by model id
- **AND** it SHALL be persisted to SharedPreferences

#### Scenario: Benchmark available on next launch
- **GIVEN** at least one model has a stored RTF benchmark
- **WHEN** the app starts and loads settings
- **THEN** `ttsModelBenchmarks` SHALL contain the previously stored values

#### Scenario: Benchmark absent for unpreviewd models
- **WHEN** settings are loaded for a model that has never been previewed
- **THEN** `ttsModelBenchmarks` SHALL contain no entry for that model id
- **AND** the absence SHALL be treated as "no benchmark" (not as RTF = 0)

#### Scenario: Benchmark updated on re-preview
- **WHEN** the user previews a model that already has a stored benchmark
- **THEN** the new RTF value SHALL replace the old one in `ttsModelBenchmarks`
