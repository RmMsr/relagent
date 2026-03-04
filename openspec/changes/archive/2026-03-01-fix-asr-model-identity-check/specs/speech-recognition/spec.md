## MODIFIED Requirements

### Requirement: ASR Model Identity Comparison
The system SHALL compare ASR model identity by model ID string, not by object reference. The sherpa-onnx recognizer SHALL be reused across recordings when the selected model has not changed, and recreated only when the model ID actually differs.

#### Scenario: Recognizer reused on second recording start
- **GIVEN** a recording session has completed with model "model-a"
- **WHEN** a new recording starts with the same model "model-a"
- **THEN** the existing sherpa-onnx recognizer SHALL be reused
- **AND** recording SHALL start immediately without model reload

#### Scenario: Recognizer recreated when model changes
- **GIVEN** a recording session has completed with model "model-a"
- **WHEN** a new recording starts with model "model-b"
- **THEN** the previous recognizer SHALL be disposed
- **AND** a new recognizer SHALL be initialized with model "model-b"
- **AND** recording SHALL start after model initialization completes
