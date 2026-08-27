## Why

Users want responses in languages that match the topic being discussed, even within a single conversation session. They should also be able to request explicit translations ("what is X in language Y?") and have both the response and audio playback reflect the appropriate language. Currently, Relagent has no way to signal or act on multilingual responses — all output defaults to English.

## What Changes

- The LLM includes a language code with each response, signaling the language in which it chose to respond (based on topic or explicit user request).
- The engine stores the language code in `AssistantMessage` for visibility and client-side decision making.
- The app shows which TTS model played the response (or which default was used) in the message agentstats.
- The app maintains per-device, per-language TTS model assignments (e.g., "French → Kokoro FR", "Spanish → Default").
- TTS playback uses the app's assigned model for the response language, or falls back gracefully if no model is available for that language.

## Capabilities

### New Capabilities

- `dynamic-response-languages`: LLM chooses response language based on topic/context; language code included in every message (not just non-English ones — see design D9).
- `device-local-tts-language-routing`: App maps language codes to TTS models (per-device, user-configurable).
- `language-aware-tts-playback`: TTS playback respects language-to-model mapping or falls back to default.
- `language-visibility-in-agentstats`: Message agentstats show which language was detected, for every message.
- `asr-language-selection`: Users can mark downloaded ASR models for a mic long-press quick-pick (a multi-language model's whole declared set becomes available at once, not one language at a time) and quick-switch the active ASR model, alongside the existing input-device picker. Unlike TTS, this does not route by language — nothing can direct an ASR model to recognize one specific language (see design D15).

### Modified Capabilities

- `model-catalog`: TTS model cards gain a per-language chip control (one chip per declared language, always — no separate single-language checkbox). ASR model cards gain a single quick-pick toggle, independent of how many languages the model declares. Both types gain a wildcard button (device-default marker) using the same widget. The filter control gains a "Selected" option (assigned/enabled-or-default, per type). Neither type keeps a "Select"/checkmark single-active-model control or a whole-card tap-to-select action.
- `agentic-chat`: TTS playback consults `AssistantMessage.language_code` and routes to the assigned model, falling back gracefully when none is assigned.

## Impact

**Backend:**
- **engine/domain/models.py** — Add `language_code: str | None` field to `AssistantMessage`.
- **engine system prompt** — Updated to instruct the LLM to determine response language and include it.

**Frontend:**
- **apps/lib/widgets/model_management_section.dart** — Model cards gain checkbox and wildcard button for language assignment.
- **apps/lib/providers/voice_service_provider.dart** — TTS service lookup logic consults language code and user preferences.
- **apps/lib/models/settings.dart** / **apps/lib/providers/settings_provider.dart** — New `ttsLanguagePreferences: Map<String, String>` and `defaultTtsModelId: String` persisted to SharedPreferences.
- **apps/lib/widgets/chat/message_details.dart** / **apps/lib/agentic/widgets.dart** — Agentstats display shows the detected language for every message.
- **apps/lib/models/settings.dart** / **apps/lib/providers/settings_provider.dart** — `defaultAsrModelId: String?` (renamed from `selectedAsrModelId`, with a JSON migration), plus new `asrQuickPickModelIds: List<String>` and `activeAsrModelId: String?`. Not a `language → model` map — see design D15.
- **apps/lib/voice/model_resolver.dart** — Language-aware ASR model resolution (`selectAsrModelIdForLanguage`), mirroring the TTS resolver.
- **apps/lib/speech_recognition/mic_selection_widgets.dart** / **apps/lib/speech_recognition/widgets.dart** — Mic picker sheet gains an independently-gated language section; mic button gains a second badge icon.
- **apps/lib/widgets/model_management_section.dart** — Language-assignment controls generalized to a shared widget used by both ASR and TTS cards, with per-language toggles for multi-language models.

**No new pub dependencies required.**

## Constraints & Scope

**Per-Device Only:** Language-to-model preferences are stored locally on each device. No backend sync. This acknowledges that TTS model availability and user preferences vary widely across devices.

**Assumptions:**
- Most TTS and ASR models support one language; multi-language models (inherent to the model metadata) require the user to explicitly pick which of their languages to assign, rather than the app guessing.
- LLM reliably includes language code in every response (parser handles extraction; a missing/malformed marker degrades to no language shown, not an error).
- Language codes are ISO 639-1 (2-letter: 'en', 'fr', 'de', etc.).
- ASR has no lever to target a specific recognition language — the quick-pick selects a *model*, not a language, and is an overlay on top of the device default: with no quick-pick model active, behavior falls back to the default (renamed from today's single active model, same fallback role).
