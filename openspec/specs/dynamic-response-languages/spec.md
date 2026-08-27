# dynamic-response-languages Specification

## Purpose
Let the LLM choose the response language per message and make that choice visible to the backend and client so downstream systems can act on it.
## Requirements
### Requirement: LLM Signals Response Language
The system prompt SHALL instruct the LLM to determine the most appropriate language for each response, based on the conversation topic or an explicit user request, and to signal that choice using a structured marker at the start of its output — for every response, including ones in English/the default language. The marker is not reserved for signaling a deviation from a default; it names whichever language the LLM actually used.

#### Scenario: LLM responds in a non-English language
- **WHEN** the LLM determines a response should be in a language other than English
- **THEN** it SHALL prefix its output with a language marker naming the ISO 639-1 code

#### Scenario: LLM responds in English
- **WHEN** the LLM determines a response should be in English
- **THEN** it SHALL still prefix its output with a language marker naming the `en` code, the same as for any other language

### Requirement: Language Code Extraction
The engine SHALL parse the LLM's raw output for a language marker and extract an ISO 639-1 language code from it before constructing the `AssistantMessage`.

#### Scenario: Marker present and well-formed
- **WHEN** the LLM output begins with a well-formed language marker (e.g. `{"language_code": "fr"}`)
- **THEN** the engine SHALL extract the two-letter code
- **AND** normalize it to lowercase

#### Scenario: Marker absent
- **WHEN** the LLM output contains no language marker (the LLM failed to follow the instruction)
- **THEN** the engine SHALL leave the language code unset
- **AND** SHALL NOT infer or assume a language

#### Scenario: Marker malformed
- **WHEN** the LLM output begins with content that cannot be parsed as a valid language marker
- **THEN** the engine SHALL leave the language code unset
- **AND** SHALL NOT fail the response

#### Scenario: Marker content excluded from displayed text
- **WHEN** a language marker is extracted from the LLM output
- **THEN** the marker text SHALL NOT appear in the message content shown to the user

### Requirement: Language Code Stored on Assistant Message
The engine SHALL store the extracted language code on the `AssistantMessage` so clients can act on it.

#### Scenario: Language code delivered to client
- **WHEN** an `AssistantMessage` is returned to the client
- **AND** a language code was extracted
- **THEN** the message SHALL include that ISO 639-1 code

#### Scenario: No language code delivered when unset
- **WHEN** an `AssistantMessage` is returned to the client
- **AND** no language code was extracted (marker absent or unparseable)
- **THEN** the message's language code SHALL be absent/null

