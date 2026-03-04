## ADDED Requirements

### Requirement: Streaming TTS Gate on RTF Benchmark
The TTS pipeline SHALL consult the stored benchmark for the active model and disable streaming synthesis when the model is measured to be too slow for real-time delivery.

#### Scenario: Streaming disabled when RTF exceeds threshold
- **GIVEN** the active TTS model has a stored benchmark with RTF greater than 1.10
- **WHEN** the TTS service initializes for that model
- **THEN** streaming synthesis SHALL be disabled for that session
- **AND** the pipeline SHALL fall back to full-buffer synthesis regardless of any streaming setting

#### Scenario: Streaming allowed when RTF is within threshold
- **GIVEN** the active TTS model has a stored benchmark with RTF of 1.10 or below
- **WHEN** the TTS service initializes for that model
- **THEN** the streaming setting SHALL determine whether streaming synthesis is used

#### Scenario: Streaming mode unchanged when no benchmark exists
- **GIVEN** the active TTS model has no stored benchmark
- **WHEN** the TTS service initializes
- **THEN** the streaming gate SHALL NOT suppress streaming based on absence of data
- **AND** the streaming setting SHALL determine the synthesis mode as normal
