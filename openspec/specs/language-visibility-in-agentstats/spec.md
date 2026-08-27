# language-visibility-in-agentstats Specification

## Purpose
Show users which language a response was detected in, as part of message agentstats — including for the app's default (e.g. English) language, since the LLM now signals its language choice on every response, not only when it deviates from the default.
## Requirements
### Requirement: Detected Language Shown In Agentstats
When an assistant message has a detected language code, the chat UI SHALL show it inside the message's agentstats detail panel, exposed via the same "Show stats" interaction already used for other per-message statistics. This applies regardless of which language was detected, including the app's default language — the indicator is not limited to non-default/non-English responses.

#### Scenario: Language code present
- **GIVEN** an assistant message has a language code
- **WHEN** the user expands the message's stats panel
- **THEN** the detected language SHALL be shown in the panel

#### Scenario: Default-language response still shows its language
- **GIVEN** an assistant message has a language code equal to the app's default/expected language
- **WHEN** the user expands the message's stats panel
- **THEN** the detected language SHALL be shown the same as it would be for any other language — it SHALL NOT be hidden just because it matches the default

#### Scenario: Stats panel reachable even without other stats data
- **GIVEN** an assistant message has a language code but no other agentstats data
- **WHEN** the message is displayed
- **THEN** the "Show stats" control SHALL still be available so the language can be viewed

#### Scenario: No language code detected
- **GIVEN** an assistant message has no language code
- **WHEN** the user expands the message's stats panel (if available for other reasons)
- **THEN** no language indicator SHALL be shown for it

### Requirement: No TTS Model Attribution Shown
The language indicator SHALL NOT report which TTS model played (or would play) the response. Which model plays a given language is a matter of local, per-device settings (`device-local-tts-language-routing`), not a fact about the message itself, and SHALL NOT be surfaced in the chat UI.

#### Scenario: Played-model text absent
- **GIVEN** an assistant message has a language code and was played back via TTS
- **WHEN** the message's stats panel is displayed
- **THEN** no "played as" or similar model-attribution text SHALL appear next to the language indicator

