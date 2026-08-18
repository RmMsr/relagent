## MODIFIED Requirements

### Requirement: Architecture Auto-Detection
The system SHALL inspect the file names within a selected archive and attempt to determine the model architecture before presenting the metadata form.

#### Scenario: Transducer detected
- **WHEN** the archive contains files matching `encoder*.onnx`, `decoder*.onnx`, and `joiner*.onnx`
- **THEN** the detected architecture SHALL be `transducer`
- **AND** the architecture field in the metadata form SHALL be pre-filled with this value

#### Scenario: NeMo CTC streaming detected
- **WHEN** the archive contains a single model `.onnx` file and `tokens.txt`, and any entry path contains "nemo"
- **THEN** the detected architecture SHALL be `onlineNemoCtc`

#### Scenario: CTC detected
- **WHEN** the archive contains a single model `.onnx` file and `tokens.txt` with no "nemo" indicator
- **THEN** the detected architecture SHALL be `ctc`

#### Scenario: Piper VITS detected
- **WHEN** the archive contains a model `.onnx` file and an `espeak-ng-data/` directory entry
- **THEN** the detected architecture SHALL be `vitsPiper`

#### Scenario: Kokoro detected
- **WHEN** the archive contains `voices.bin`
- **THEN** the detected architecture SHALL be `kokoro`

#### Scenario: Whisper detected
- **WHEN** the archive contains exactly one encoder `.onnx` file and exactly one decoder `.onnx` file sharing a common filename prefix, no joiner file, and a tokens file matching `<prefix>tokens.txt` (the naming sherpa-onnx's own whisper export script produces, e.g. `nb-whisper-base-encoder.onnx` / `nb-whisper-base-decoder.onnx` / `nb-whisper-base-tokens.txt`)
- **THEN** the detected architecture SHALL be `whisper`
- **AND** this detection SHALL NOT require the tokens file to be named exactly `tokens.txt`

#### Scenario: Detection fails
- **WHEN** no known file pattern is matched
- **THEN** the architecture field SHALL be left blank and marked as required in the metadata form
