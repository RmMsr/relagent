## Purpose

Let users quick-switch which downloaded ASR model is actively loaded for recognition, via the same mic long-press gesture already used to pick an input device — labeled by each model's language coverage so the user can judge which one to use, without implying the app can force a model to recognize one specific language.

## Non-Goals

Controlling *which* language a multi-language ASR model recognizes. Nothing in this app's ASR pipeline can bias a model's decoder toward a specific language — a downloaded model recognizes whatever it hears, across its entire declared language set. Earlier drafts of this capability modeled ASR the same way as TTS (a `language → model` routing table, with a "recognition language" the user could pick). That was a mistake: TTS genuinely produces audio in the language its model was built for, so routing by language controls a real outcome; ASR does not have an equivalent lever. This capability is scoped to model selection only.

## ADDED Requirements

### Requirement: ASR Quick-Pick Model Set
Users SHALL be able to mark a downloaded/available ASR model as a mic long-press quick-pick candidate, independent of how many languages it declares — enabling a model makes its entire declared language set available at once, not one language at a time. This set is persisted per-device.

#### Scenario: Enabling a model adds it to the quick-pick set
- **WHEN** the user enables the quick-pick toggle on a downloaded ASR model's card
- **THEN** that model SHALL be added to the quick-pick set
- **AND** it SHALL survive an app restart

#### Scenario: A multi-language model is enabled as a single unit
- **GIVEN** a downloaded ASR model declares several languages (e.g. 25)
- **WHEN** the user enables its quick-pick toggle
- **THEN** the model SHALL be added to the quick-pick set as one entry
- **AND** the app SHALL NOT require the user to enable each of its languages individually

#### Scenario: Disabling a model removes it from the quick-pick set
- **WHEN** the user disables the quick-pick toggle on a model already in the set
- **THEN** that model SHALL be removed from the quick-pick set
- **AND** if it was this session's active quick-picked model, that selection SHALL clear (falling back to the device default)

### Requirement: ASR Model Card Default Control
Each downloaded/available ASR model card SHALL provide a wildcard (default) control, the same widget TTS cards use, marking it the persisted device default ASR model — the model used whenever no quick-pick override is active. TTS's default means "play this when no language-specific model is assigned"; ASR's means "recognize with this when nothing more specific overrides it." The quick-pick toggle and the default control are independent — a card can be in the quick-pick set, marked default, both, or neither.

#### Scenario: Marking a model as default
- **WHEN** the user activates the default control on a downloaded ASR model card
- **THEN** that model SHALL become the persisted device default ASR model
- **AND** any previously marked default card's control SHALL reflect it is no longer the default
- **AND** the choice SHALL survive an app restart

#### Scenario: Default and quick-pick are independent
- **GIVEN** a model is marked default
- **WHEN** the user also enables its quick-pick toggle (or vice versa)
- **THEN** both states SHALL be reflected independently — one does not imply or exclude the other

### Requirement: Mic Long-Press Offers a Session-Only Recognition-Model Override
Long-pressing the mic button SHALL open a picker offering, in addition to the existing input-device choice, a section to quick-switch the active ASR model for the remainder of the current app session — shown only when at least two models are in the quick-pick set. Each entry is labeled by the model's name and its declared language coverage (e.g. "Parakeet TDT — 25 languages" or "Zipformer — German"), never by a single language in isolation. This selection is **not persisted**: it exists only for the running app session and reverts to the device default the next time the app launches.

#### Scenario: Model section shown with multiple quick-pick models
- **GIVEN** two or more downloaded ASR models are in the quick-pick set
- **WHEN** the user long-presses the mic button
- **THEN** the picker SHALL include a model section listing each quick-pick model with its language coverage
- **AND** the currently active model for this session (if any) SHALL be indicated in that list

#### Scenario: Model section hidden with fewer than two quick-pick models
- **GIVEN** zero or one model is in the quick-pick set
- **WHEN** the user long-presses the mic button (if the picker opens at all)
- **THEN** the picker SHALL NOT show a model section

#### Scenario: Picking a model sets it active for this session
- **GIVEN** the model section is shown
- **WHEN** the user selects a model from it
- **THEN** that model SHALL become the active ASR model for recognition, overriding the device default until changed, cleared, or the app restarts

#### Scenario: Picking the already-active model clears the override
- **GIVEN** a quick-pick model is the active session override
- **WHEN** the user selects that same model again from the picker
- **THEN** the session override SHALL clear, reverting resolution to the device default

#### Scenario: The session override does not survive a restart
- **GIVEN** the user picked a quick-pick model as this session's active override
- **WHEN** the app is relaunched
- **THEN** resolution SHALL use the persisted device default (or its own fallback), not the override from the previous session

#### Scenario: Device section still gated on having options
- **GIVEN** the platform can enumerate input devices
- **AND** at least one device is available
- **WHEN** the user long-presses the mic button
- **THEN** the picker SHALL include the existing device section, unchanged from today

#### Scenario: Neither section has options
- **GIVEN** no input devices are enumerable
- **AND** fewer than two models are in the quick-pick set
- **WHEN** the user attempts to long-press the mic button
- **THEN** no picker SHALL open, consistent with today's behavior when device selection is unavailable

### Requirement: Mic Button Badges Indicate Available Quick-Picks
The mic button SHALL show a small badge icon for each picker section that currently has options, so the hidden long-press menu's contents are discoverable without opening it.

#### Scenario: Device badge shown as today
- **GIVEN** the active input device has a distinguishable category (Bluetooth, wired, USB)
- **WHEN** the mic button is displayed
- **THEN** it SHALL show the existing device-category badge, unchanged

#### Scenario: Model badge shown when a model quick-pick is available
- **GIVEN** two or more models are in the ASR quick-pick set
- **WHEN** the mic button is displayed
- **THEN** it SHALL show a small badge (a translate icon) indicating a recognition-model choice exists, distinct in position from the device badge

#### Scenario: Both badges can appear together
- **GIVEN** both a distinguishable input device and two or more quick-pick models exist
- **WHEN** the mic button is displayed
- **THEN** both badges SHALL be shown simultaneously, each in its own position

#### Scenario: No model badge with fewer than two quick-pick models
- **GIVEN** fewer than two models are in the ASR quick-pick set
- **WHEN** the mic button is displayed
- **THEN** no model badge SHALL be shown

### Requirement: ASR Model Resolution Chain
Recognition SHALL resolve which ASR model to use via, in order: (1) this session's active quick-pick override, if set and usable; (2) the persisted device default, if set and usable; (3) the first downloaded ASR model, if any; (4) none.

#### Scenario: Session override takes priority
- **GIVEN** a session override is active
- **AND** it differs from the device default
- **WHEN** recognition starts
- **THEN** the session override SHALL be used

#### Scenario: No override falls back to the default
- **GIVEN** no session override is active
- **AND** a device default is set
- **WHEN** recognition starts
- **THEN** the device default SHALL be used

#### Scenario: No override and no default falls back to any downloaded model
- **GIVEN** no session override is active
- **AND** no device default is set
- **AND** at least one ASR model is downloaded
- **WHEN** recognition starts
- **THEN** the first downloaded ASR model SHALL be used, with no prior configuration required

#### Scenario: Nothing available
- **GIVEN** no session override, no device default, and no downloaded ASR model
- **WHEN** recognition starts
- **THEN** no ASR model SHALL be used

### Requirement: Active Recording Restarts When the Resolved Model Changes
When recording is currently active and the model resolution chain's result changes — the persisted device default changes, the session override is set or cleared, or a just-selected model finishes downloading — the app SHALL stop and restart recording so the new model takes effect immediately, rather than continuing on the previously-loaded model until some unrelated stop/start.

#### Scenario: Changing the default while recording restarts it
- **GIVEN** recording is currently active using one ASR model
- **WHEN** the user changes the persisted device default to a different downloaded model
- **THEN** recording SHALL stop and restart using the newly-resolved model

#### Scenario: Picking a session override while recording restarts it
- **GIVEN** recording is currently active using one ASR model
- **WHEN** the user picks a different model via the mic long-press quick-pick
- **THEN** recording SHALL stop and restart using the newly-resolved model

#### Scenario: Clearing a session override while recording restarts it
- **GIVEN** recording is currently active using a session-overridden model
- **WHEN** the user clears the override (picking it again, or it becomes invalid)
- **THEN** recording SHALL stop and restart using the device default (or further fallback)

#### Scenario: No restart when not recording
- **GIVEN** recording is not currently active
- **WHEN** the resolved model changes
- **THEN** no stop/restart SHALL occur — the new model simply takes effect the next time recording starts

#### Scenario: No restart when the resolved model is unchanged
- **GIVEN** recording is currently active
- **WHEN** a settings change occurs that does not alter which model the resolution chain selects
- **THEN** recording SHALL NOT be stopped or restarted
