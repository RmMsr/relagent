## ADDED Requirements

### Requirement: API Key Storage for Relagent Engine

The system SHALL store and retrieve API keys for the Relagent Engine in platform secure storage, scoped to the engine URL, using the same security guarantees as password storage.

#### Scenario: Store engine API key securely
- **GIVEN** the user has entered an API key for an engine URL
- **WHEN** the key is saved via the credential storage service
- **THEN** the key SHALL be stored using platform-specific secure storage (iOS Keychain, Android Keystore, Linux Secret Service)
- **AND** the key SHALL NOT be accessible to other applications
- **AND** the storage key SHALL be distinct from the password key for the same URL

#### Scenario: Retrieve stored engine API key
- **GIVEN** an API key has been stored for an engine URL
- **WHEN** the credential storage service retrieves the API key for that URL
- **THEN** the service SHALL return the stored key value

#### Scenario: Engine API key not returned for different URL
- **GIVEN** an API key is stored for engine URL "http://server-a:8000"
- **WHEN** the credential storage service is queried for URL "http://server-b:8000"
- **THEN** the retrieval SHALL return null

#### Scenario: Clear engine API key
- **GIVEN** an API key is stored for an engine URL
- **WHEN** `clearEngineApiKey` is called for that URL
- **THEN** the key SHALL be removed from secure storage
- **AND** subsequent retrieval attempts SHALL return null

### Requirement: API Key Storage for OpenAI-Compatible Backend

The system SHALL store and retrieve API keys for the OpenAI-compatible backend in platform secure storage, scoped to the simple chat base URL.

#### Scenario: Store simple chat API key securely
- **GIVEN** the user has entered an API key for a simple chat URL
- **WHEN** the key is saved via the credential storage service
- **THEN** the key SHALL be stored using platform-specific secure storage
- **AND** the key SHALL be scoped to the simple chat URL namespace (distinct from engine keys)

#### Scenario: Retrieve stored simple chat API key
- **GIVEN** an API key has been stored for a simple chat URL
- **WHEN** the credential storage service retrieves the API key for that URL
- **THEN** the service SHALL return the stored key value

#### Scenario: Clear simple chat API key
- **GIVEN** an API key is stored for a simple chat URL
- **WHEN** `clearChatApiKey` is called for that URL
- **THEN** the key SHALL be removed from secure storage
- **AND** subsequent retrieval attempts SHALL return null

### Requirement: API Key Not Logged

The system SHALL never write API key values to application logs.

#### Scenario: No API key value in logs
- **GIVEN** an API key is stored, retrieved, or injected into a request header
- **WHEN** debug logging is enabled
- **THEN** the actual API key value SHALL NOT appear in log output
- **AND** only generic messages such as "API key present" SHALL be logged
