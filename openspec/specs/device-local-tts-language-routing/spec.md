# device-local-tts-language-routing Specification

## Purpose
Let each device maintain its own mapping from response language to TTS model, independent of any other device, so playback can use the right voice per language without backend coordination.
## Requirements
### Requirement: Per-Language TTS Model Assignment
The app SHALL let the user assign a downloaded TTS model to a language code, and SHALL persist that assignment locally on the device.

#### Scenario: Assign a model to a language
- **WHEN** the user assigns a downloaded TTS model to a language code
- **THEN** the assignment SHALL be stored in local device preferences
- **AND** SHALL survive an app restart

#### Scenario: Remove a language assignment
- **WHEN** the user removes a model's assignment to a language
- **THEN** the stored preference for that language SHALL be deleted
- **AND** future responses in that language SHALL fall back per the fallback chain

#### Scenario: Reassign a language to a different model
- **WHEN** the user assigns a new model to a language that already has an assigned model
- **THEN** the previous assignment SHALL be replaced by the new one

### Requirement: Default TTS Model
The app SHALL let the user designate one downloaded TTS model as the device default, used when no language-specific assignment exists.

#### Scenario: Set default model
- **WHEN** the user marks a downloaded TTS model as the default
- **THEN** it SHALL be persisted as the device default
- **AND** any previously designated default SHALL be unmarked

#### Scenario: Clear default model
- **WHEN** the user unmarks the current default model
- **THEN** the device SHALL have no default TTS model until one is set again

### Requirement: No Cross-Device Sync
Language-to-model assignments and the default model designation SHALL be stored per-device only, with no backend synchronization.

#### Scenario: Assignments differ across devices
- **GIVEN** a user has different assignments on two devices
- **WHEN** either device selects a TTS model for playback
- **THEN** it SHALL use only its own local assignments
- **AND** SHALL NOT be affected by the other device's assignments

