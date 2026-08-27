## Context

The app already has a TTS isolate-based pipeline (`TtsIsolateWorker`) that plays audio for assistant messages. Currently, all playback uses a single active TTS model, with no awareness of message language. The backend `AssistantMessage` model has no language field, so language information is lost after generation.

Users in multilingual contexts want responses in topic-appropriate languages and the ability to request translations. The LLM can already reason about language, but there's no plumbing to signal it or act on it client-side.

Key existing components reused by this change:
- `AssistantMessage` in `engine/domain/models.py` — will gain the `language_code` field.
- `TtsNotifier` and `TtsService` — TTS playback orchestration; will consult language preferences.
- Model cards in `_ModelEntryCard` — will gain language selection UI.
- `Settings` / `SettingsProvider` — Map-based persistence pattern already used for `engineUrlHistory` and `history`.

## Goals / Non-Goals

**Goals:**
- LLM includes language code when responding in a language other than English.
- Backend stores and delivers language code to the client via `AssistantMessage.language_code`.
- App displays which language and TTS model played the response (in agentstats).
- Users can assign TTS models to languages via model card UI (checkbox + wildcard).
- TTS playback respects language-to-model assignments or falls back gracefully.

**Non-Goals:**
- Backend-driven TTS model catalog or language validation.
- Cross-device sync of language preferences (per-device only).
- Automatic language detection from user input — LLM decides based on context.
- Explicit "respond in language X" UI button — relies on LLM understanding requests.
- Language-specific prompt tuning.

## Decisions

### D1 — LLM Chooses Language; Backend Extracts and Stores

The system prompt instructs the LLM to determine the most appropriate language for each response (based on topic or explicit request) and include the language code in its output. The backend parser extracts the code (looking for JSON `"language_code": "xx"` or a structured marker) and populates `AssistantMessage.language_code`. If extraction fails or the response is in English, the field remains `None`.

This approach is simple and flexible: the LLM already understands language context; we just need to ask it to signal its choice. If the signal is missing or unrecognized, the client defaults gracefully.

Alternative considered: backend logic to detect language post-generation (e.g., `langdetect` library). Rejected because it adds dependency complexity and the LLM is a better source of truth about its intent.

### D2 — Device-Local Language Preferences, Not Backend-Synced

Each device maintains its own `language_code → modelId` mapping in SharedPreferences. No backend involvement. This reflects the reality of heterogeneous device setups: users may have different models downloaded on phone vs. desktop, different hardware capabilities, and strong preferences for local control.

A future iteration can add backend sync if the UX calls for it; starting local-only keeps this iteration focused and limits scope.

### D3 — Simple Checkbox + Wildcard UI on Model Cards

Instead of a separate "TTS Languages" settings section, we enhance the existing model card UI:
- Checkbox: assign this model to its language.
- Wildcard (⭐) button: mark it as the device default.
- Filter dropdown: "All" / "Selected" / "Downloaded" to browse and manage assignments.

This reuses the model management flow users already know and avoids UI fragmentation.

### D4 — One Language Per TTS Model

We assume each TTS model represents one language (e.g., "Kokoro EN" is for English, "Kokoro FR" is for French). This eliminates per-language checkboxes on a single card and simplifies the data model.

If a multi-language model ever becomes relevant, the checkbox pattern can be added later without breaking existing UI.

### D5 — Graceful Fallback Chain

If no TTS model is configured for a response language:
1. Use the `defaultTtsModelId`.
2. If default is unavailable, use the first available model.
3. If no models are available, skip TTS (text-only).

This ensures a response always reaches the user, even if the audio isn't perfect.

### D6 — Language Visibility in Agentstats, Not Chat UI

The response language is shown only in message agentstats (when the user opens details), not as a badge on the chat message itself. This keeps the chat UI clean and puts language context where it's needed (when users wonder why the accent doesn't match the expected language).

Display format: `[Human Language Name] LanguageCode/Unknown (played as PlayedLanguageCode)` (e.g., "German de (played as de)" or "French fr/Unknown (played as en)").

### D7 — Fallback "Played As" Transparency

The agentstats also shows which TTS model actually played (or which default was used). This is crucial for transparency: if a user gets a French response but English audio plays, they immediately see why. Example: "French fr/Unknown (played as en)" signals that no French model was available, so English was used instead.

### D8 — Small LRU Pool of Native TTS Engines, Not a Single Swapped Engine

Implementation revealed a gap this design didn't originally address: `NativeVoiceService` holds exactly one `TtsIsolateWorker` (one native `sherpa_onnx.OfflineTts` loaded in a dedicated Dart isolate) at a time. Switching models means disposing that isolate and spawning/loading a new one — the same operation the SIGABRT crash-guard in `TtsNotifier` exists to protect, previously triggered only by a deliberate Settings change. Naively resolving a model per message would fire that dispose/reload cycle every time consecutive messages land in different languages.

Since each `TtsIsolateWorker` is independently spawned (not a process-wide native singleton), `NativeVoiceService` keeps a small LRU-bounded pool of them (max 3), keyed by resolved model ID, instead of a single swapped worker:

- `VoiceService.generateSpeech` takes the `ResolvedTtsModel` to speak with on every call (rather than relying on a prior `initializeTts` call's implicit state), so concurrent generation for two in-flight messages in different languages (the existing chunk-prefetch pipeline already runs concurrently) can each target the right pooled worker without racing.
- A pool hit (recently-used language) is instant; a pool miss spawns a new isolate and evicts the least-recently-used entry once the pool is full.
- `initializeTts` becomes a pre-warm hint: called at startup with the initially-selected model, and after an explicit Settings change, so the first message doesn't pay the pool-miss cost.
- `disposeTts` tears down every pooled worker.

Trade-off: up to 3 TTS models resident in memory at once (tens of MB each) instead of 1. Accepted — bounded and small relative to switching cost, and the existing crash-guard/robustness handling in `TtsService`/`TtsNotifier` did not need to change, only what triggers a reload.

## Data Structures

### Backend

```python
class AssistantMessage(BaseModel):
    message_id: UUID
    role: Literal["assistant"]
    timestamp: datetime
    content: str
    language_code: str | None = Field(
        default=None,
        description="ISO 639-1 language code (e.g., 'en', 'fr', 'de') chosen by the LLM. None if English or language was not determined."
    )
    stats: AgentStats | None = None
    final: bool = True
```

### Frontend (Dart/Flutter)

```dart
// Preference model
class TtsLanguagePreference {
  final String languageCode;  // 'en', 'fr', 'es', etc.
  final String modelId;        // e.g., 'kokoro-en', 'kokoro-fr'
}

// Settings (persisted)
class Settings {
  // ... existing fields
  Map<String, String> ttsLanguagePreferences = {};  // languageCode -> modelId
  String? defaultTtsModelId;  // Fallback if no language match
  // ... existing fields
}

// Usage in TtsNotifier
class TtsNotifier {
  String? _getModelIdForLanguage(String? languageCode) {
    if (languageCode == null) return settings.defaultTtsModelId;
    return settings.ttsLanguagePreferences[languageCode] ?? settings.defaultTtsModelId;
  }
}
```

## Error Handling & Fallback

| Scenario | Behavior |
|----------|----------|
| Response has `language_code='fr'`, user has `fr→kokoro-fr`, model available | Use Kokoro FR |
| Response has `language_code='de'`, no `de` mapping, default is `kokoro-en` | Use Kokoro EN (default) |
| Response has `language_code='es'`, no mapping, no default, models available | Use first available model |
| Response has `language_code='pt'`, no mapping, no default, no models | Skip TTS (text-only) |
| Response missing `language_code` (English or extraction failed) | Use `defaultTtsModelId` |
| User unchecks a model (removes language assignment) | Preference deleted; future responses in that language fall back to default |

## Testing Strategy

### Unit Tests
- **Language code extraction:** Mock LLM responses with language codes in various formats (JSON field, marker text, mixed). Verify parsing into `language_code` field.
- **Model lookup logic:** Preferences with various states (empty, partial, complete); verify correct fallback to default, then first available.

### Integration Tests
- Message arrives with `language_code='fr'`, preferences has `fr→kokoro-fr` → TTS uses Kokoro FR.
- Message arrives with `language_code='de'`, preferences empty, default is `kokoro-en` → TTS uses Kokoro EN.
- Message arrives with `language_code='es'`, no models available → TTS skipped, message text displays.
- Message arrives without `language_code` (None) → TTS uses default.
- User unchecks a model → preference removed, future requests fall back.

### Widget Tests
- Checkbox state: check/uncheck, persists to SharedPreferences.
- Wildcard button: tapping sets model as default, icon changes.
- Filter dropdown: "All" / "Selected" / "Downloaded" shows correct model sets.
- Preferences persist across app restart.

### Manual / E2E Tests
- Send a message asking for a translation (e.g., "What is hello in French?").
- Receive a French response (`language_code='fr'`).
- Trigger TTS → correct model plays (if assigned) or default plays (if not).
- Open agentstats → language and "played as" info visible.
- Change model assignment in settings → next TTS uses new model.

## Risks / Trade-offs

- [Risk] LLM may fail to include language code or include it in an unrecognized format. → Mitigation: parser is lenient; missing code is treated as English (None). Document the expected format in the system prompt and the backend implementation.
- [Risk] Users may not understand the checkbox/wildcard UI at first. → Mitigation: brief tooltip on each button; model cards already have interactive elements, so the pattern is familiar.
- [Risk] Running TTS in a language the model doesn't support (e.g., playing French audio with an English model) produces strange results. → Mitigation: unavoidable without a TTS model catalog; the "played as" agentstats gives transparency. Users will quickly learn to assign models correctly.
- [Risk] No per-language TTS model validation backend-side means misconfigured preferences can silently produce wrong audio. → Accepted trade-off: device-local simplicity wins over centralized validation. The "played as" transparency helps users notice and correct.

### D9 — Language Marker Sent for Every Response, Not Just Non-English

Second-round user review: the language indicator should be visible for *every* message, including ones in the app's default language (English), not only when the LLM deviates from it. Originally (D6/D1) the instructions told the LLM to omit the marker entirely for English, so `language_code` was `None` for the common case and nothing could be shown.

The `discussion_agent` instructions now ask for the marker on every response, English included. The parser (`extract_language_code`) is unchanged — it already just looks for the marker line and returns `None` if absent, which remains the correct fallback for a malformed or missing marker rather than a signal of "it was English."

### D10 — Language Indicator Moves Back Into Agentstats

D6 originally put the language indicator inside the collapsible "Show stats" panel; the first UI-review round (§8.1) moved it out to an always-visible badge next to the message actions. Second-round review reversed that: the language indicator belongs back inside the stats panel — it's detail-level information, not something that needs to compete for attention on every message row now that it appears on *every* message (per D9).

The "Show stats" toggle becomes available whenever there is a language code *or* stats data (previously gated on stats data alone), so a message with a language code but no `AgentStats` still exposes the language via the toggle.

### D11 — Language-Assignment Controls Generalized to ASR, With Multi-Language-Per-Model Support *(ASR portion superseded by D15)*

**Note:** the TTS half of this decision (multi-language chip toggles) stands, refined by D14. The ASR half — assigning specific languages to an ASR model — was based on a false premise; see D15.

D4 assumed one language per TTS model and let the model-card checkbox always assign "the model's first listed language." That assumption doesn't hold for ASR: multi-lingual ASR models (e.g. a Whisper variant covering several languages) are common, and the user now wants ASR models assignable to specific recognition languages the same way TTS models are assignable to playback languages — reusing the exact same UI mechanism for both.

Revised rule, applied to both ASR and TTS cards uniformly:
- A model whose `languages` list has exactly one concrete entry keeps the current single-checkbox control (unchanged mechanism, now shared code, now also available on ASR cards).
- A model whose `languages` list has more than one concrete entry shows one small toggle per language (a `Wrap` of compact chips below the model's language text) instead of a single checkbox — the user explicitly picks which of the model's languages to associate it with, rather than the app guessing "the first one."
- A model whose only language entry is the `multi` sentinel (unenumerable, e.g. Omnilingual ASR's ~1600 languages) shows no language-assignment controls at all — there is nothing meaningful to enumerate, and such a model already matches every requested language in resolution logic.
- Assigned languages render in a visually highlighted (filled/tinted) state, not just a checked checkbox — this satisfies "the active language per model card has to be highlighted" and keeps ASR and TTS visually consistent per the existing "Consistent Selected-State Visuals" requirement.
- The TTS wildcard (default) button is unaffected and stays TTS-only; ASR has no equivalent "default" concept — its fallback is the existing single active model (`selectedAsrModelId`, the "Select" control), unchanged.

This is implemented as one shared widget (replacing `_TtsLanguageControls`) parameterized by which settings map/notifier methods to call, so ASR and TTS keep pixel-identical behavior for the shared part.

### D12 — Mic Long-Press Gains a Second, Independently-Gated Section *(section content corrected by D15)*

The mic button's long-press already opens a device picker (`MicPickerSheet`). It now also offers a second, independent section in the same sheet for quick-switching ASR-related state.

**Correction (D15):** the section quick-switches the active ASR *model*, not a "recognition language" — the app has no way to target a language (see D15). The gating shape below is otherwise unchanged.

Each section is shown only when it has real options:
- The device section shows only when there is at least one enumerated input device (today it's gated only on platform capability; this tightens it to also require a non-empty device list, since "Automatic" alone isn't a real choice).
- The model section shows only when two or more downloaded/available ASR models are in the quick-pick set (`Settings.asrQuickPickModelIds`, filtered to models that are currently usable). With zero or one quick-pick model there's nothing to switch between.

The long-press gesture itself, and the corresponding badge icon on the mic button, are active only when at least one section has options — consistent with today's behavior where the whole picker is suppressed when the platform can't enumerate devices.

Badge icons on the mic symbol indicate *which* hidden sections exist, reusing the existing `MicDeviceBadge` positioning pattern for the device category and adding a second small `Icons.translate` badge (opposite corner) when the language section has options. Two badges can be present simultaneously.

### D13 — ASR Recognition Language Is a Selectable Overlay, Not a Model Switch *(superseded by D15)*

**Superseded:** this decision assumed the app could target a specific recognition language, which it can't (see D15). Kept for history; `Settings.activeAsrLanguage`/`asrLanguagePreferences` described below do not exist in the corrected design — use `Settings.activeAsrModelId`/`asrQuickPickModelIds` instead.

Picking a language from the mic quick-pick sets a new `Settings.activeAsrLanguage` (the currently targeted recognition language), rather than mutating `selectedAsrModelId` directly. ASR model resolution becomes language-aware, mirroring the TTS pattern from D1–D5 but with a shorter fallback chain (no "device default" concept for ASR, no "first available" scan — those exist for TTS because *any* downloaded TTS model can produce *some* audio, whereas an ASR model not configured for the requested language would silently mis-transcribe, which is worse than falling back to the existing single active model):

1. If `activeAsrLanguage` is set and `asrLanguagePreferences` has an assignment for it, use that model.
2. Otherwise, use `selectedAsrModelId` (today's behavior, unchanged when the feature isn't used).

`activeAsrLanguage` is persisted like other settings so the choice survives app restarts, but it is a thin overlay: clearing an assignment or leaving `activeAsrLanguage` unset reproduces exactly today's single-active-model behavior.

### D14 — One Language-Assignment Mechanism Regardless of Language Count (TTS); Both Types Gain a Default

Third-round user review simplified D11 further, for TTS: the single-checkbox-vs-chips split (one language → checkbox, several → chips) was itself inconsistent — "it should behave identical on 1 or multiple languages." The checkbox is dropped for TTS; a model's language-assignment control is now always the chip row from D11, whether it lists one language or several. The card's background/elevation highlight (already established for "assigned or default") is the visual signal that something is assigned — a checkbox next to a single chip would be redundant with both the chip's own selected style and the card highlight.

**This decision covers TTS only.** The same review round initially proposed giving ASR the identical chip mechanism plus a `defaultAsrModelId`. Neither the chip/language-assignment part nor (per D16) the separate-default part held up for ASR — see D15 and D16, which correct course before any of it was implemented. What still stands from this round, TTS-side:
- ASR's separate "Select"/checkmark single-active-model control, and its whole-card tap-to-select action, are removed — but see D16 for what replaces it (not a default-star mirroring TTS's, as first proposed here).
- TTS keeps `Settings.defaultTtsModelId` and the card-highlight definition ("assigned to a language, or default") exactly as D3/D5 already had it.

### D15 — ASR Has No Language Control: Quick-Pick a Model, Not a Language

Immediately after D14 was drafted (before any of its ASR portion was implemented), a logic error surfaced: **nothing in this app's ASR pipeline can bias a model's decoder toward one language.** A downloaded ASR model — single-language or multi-language — recognizes whatever it hears across its full declared language set; there's no "target language" input to give it. D11–D14 modeled ASR the same way as TTS (a `language → model` routing table, an "active recognition language" the user picks), which implicitly claimed a control that doesn't exist. Worse, it also implied per-language exclusivity: assigning one of a 25-language model's languages to it, one checkbox/chip at a time, when the model already recognizes all 25 the moment it's loaded — there's no reason to make the user tick 25 boxes to get behavior the model provides for free.

This supersedes the ASR-specific parts of D11, D13, and D14's initial draft. The corrected model (fallback chain and card control further simplified by D16 — read that too):
- Drop `Settings.asrLanguagePreferences` (language → model) and `Settings.activeAsrLanguage` entirely — replaced by `Settings.asrQuickPickModelIds` (a set of model ids) and `Settings.activeAsrModelId`.
- ASR model cards get one toggle — "include in quick-pick" — per model, never per language, regardless of how many languages the model declares. Enabling a multi-language model makes its whole declared set available at once, framed as *set membership*, not per-language exclusivity.
- The mic long-press's second section becomes a **model** picker, not a language picker: each row is a quick-pick-enabled model, labeled by name and its full language coverage (e.g. "Parakeet TDT — 25 languages"), never a bare language code standing in for a model choice. Picking a row sets `activeAsrModelId`.
- The mic badge icon, its gating (section shown only with ≥2 quick-pick candidates), and the device section's independent gating are unchanged in spirit from D12 — only what the second section *contains* changes.

### D16 — No Separate ASR Default: One Field, the Quick-Pick Set Supplies Its Own Fallback *(superseded by D17)*

**Superseded:** the very next message reversed this — the default comes back, persisted, via the shared star widget. What's still correct here: dropping `defaultAsrModelId` as *initially proposed in D14* (routing-table-style, mirroring TTS's "assigned or default" too literally) was the right instinct to question, even though the final answer (D17) keeps a default after all, just drawn along a different line (persisted vs. session-only, not "real vs. decorative"). Kept for the reasoning trail.

D15's fallback chain (`activeAsrModelId ?? defaultAsrModelId`) and D14's "ASR gains the same wildcard control TTS has" turned out to reintroduce the exact three-control sprawl this whole review thread has been trying to shed — worse, the star ended up doing *more* real work than the quick-pick toggle: with fewer than two quick-pick models, the mic picker's model section doesn't show at all (D15), so a user with exactly one ASR model had no way to make it active *except* through the default star. The star wasn't decorative, but it also wasn't earning a separate concept — TTS's default genuinely answers a question ("what plays when no language matches"); ASR's "default" was just "the active model, when nothing more specific was picked," which is what `activeAsrModelId` already means.

**`Settings.defaultAsrModelId` is dropped entirely.** ASR model cards get exactly one control: the quick-pick toggle. No star, no default, no "which type does the shared wildcard widget belong to today" question — that widget stays TTS-only.

Resolution becomes a three-step chain, computed on demand (nothing beyond `activeAsrModelId` is persisted):
1. `activeAsrModelId`, if set and still usable (its model still downloaded/available, still in `asrQuickPickModelIds` — see below for what invalidates it).
2. Otherwise, the first usable model in `asrQuickPickModelIds` (insertion order — whichever the user enabled first). This is what makes a *single* quick-pick model work without ever touching `activeAsrModelId`: enabling it is enough.
3. Otherwise, the first downloaded ASR model, full stop — no quick-pick configuration at all is a valid, common state (a user with exactly one downloaded ASR model shouldn't have to configure anything), and unlike D13's original TTS-style reasoning, there's no "wrong language" risk to guard against here any more (D15 already established recognition isn't language-targeted) — any downloaded model is an equally reasonable last resort.

Consequences:
- `Settings.selectedAsrModelId` is renamed directly to `Settings.activeAsrModelId` (skipping the `defaultAsrModelId` intermediate D15 proposed) — same JSON-migration approach (read the legacy key when the new one is absent).
- `activeAsrModelId` is set only by explicitly picking a model from the mic long-press list (step 1 above); toggling a card's quick-pick checkbox never writes it. Picking the *already-active* model again clears it (a toggle, mirroring how TTS's wildcard un-defaults), reverting to step 2/3.
- Disabling a model's quick-pick toggle, or deleting a model, clears `activeAsrModelId` if it pointed there (same `clearModelSelection` cleanup pattern already used for TTS).
- Card highlight and the catalog's "Selected" filter, for ASR, mean "in the quick-pick set" — full stop, no "or default" clause, since there's no longer a separate default to OR in.
- The settings-page ASR summary lists quick-pick models (name + language coverage), marking whichever is currently *active* per the resolution chain above (which may be the auto-selected first quick-pick entry, not something the user explicitly picked) — no separate "default" row. When the quick-pick set is empty, the summary falls back to the single-model display `_modelSubtitle` already provides, showing whatever the chain's step-3 fallback resolves to (or "None" if nothing is downloaded).

### D17 — Default Restored (Persisted), Active Quick-Pick Is Session-Only *(supersedes D16)*

Immediately after D16 was drafted (before implementation), a further correction: the star should come back after all, but the two ASR concepts split along a different axis than before — **persistence**, not "which one is real."

- `Settings.defaultAsrModelId` returns as a genuinely persisted field, set via the same wildcard widget TTS uses (shared control, per D14's original framing — that part was right). It's the model used whenever nothing more specific overrides it, surviving app restarts, exactly like `defaultTtsModelId`.
- `Settings.asrQuickPickModelIds` stays persisted too — it's curation ("which models are worth offering in the mic long-press menu"), set up once, not something to redo every session.
- What does **not** persist: which quick-pick model is currently active. That selection lives only for the current app session — in an ephemeral Riverpod provider, not in `Settings`/`SharedPreferences` — and resets to "unset" on every app launch. Long-pressing the mic and picking a model is a *this-session-only* override; it never touches the default.

This makes D16's "single quick-pick model becomes active on its own" auto-selection step unnecessary — with the default back, that gap it was patching no longer exists — and drops D16's fallback chain in favor of one that mirrors TTS almost exactly:

1. The session's active quick-pick override, if any is set and still usable.
2. Otherwise, `defaultAsrModelId`, if set and still usable.
3. Otherwise, the first downloaded ASR model (same "any downloaded model is an equally reasonable last resort" reasoning D16 gave — still holds, since recognition still isn't language-targeted).
4. Otherwise, none.

Concretely:
- `Settings.selectedAsrModelId` is renamed to `Settings.defaultAsrModelId` (not `activeAsrModelId` as D16 proposed) — same JSON-migration approach, reading the legacy key when the new one is absent.
- No `activeAsrModelId` field exists in `Settings` at all. The session-only override lives in its own provider (e.g. `activeAsrModelOverrideProvider`, a plain in-memory `StateProvider<String?>` or `Notifier`), read by ASR resolution alongside `Settings` but never serialized. Toggling a card's quick-pick checkbox never touches it, same as D16 established; picking the already-active model again in the mic picker clears it (toggle behavior), reverting to step 2/3.
- Disabling a model's quick-pick toggle, or deleting a model, clears the session override if it pointed there, and clears `defaultAsrModelId` if that pointed there too (the existing `clearModelSelection` cleanup pattern, extended).
- Card highlight and the catalog's "Selected" filter, for ASR: "in the quick-pick set, or is the default" — restored to the same shape TTS uses (D14's "assigned-or-default" condition), just swapping "assigned to a language" for "in the quick-pick set."
- The settings-page ASR summary lists quick-pick models plus a default row (mirroring `_ttsMappingSubtitle`'s structure exactly, per D14's original framing), additionally marking the session's active override on whichever row it points to, if any.

Net effect for the user: the star is back to meaning what it obviously looked like it should mean — "the ASR model I want by default" — and the mic long-press remains a lightweight, non-committal way to try a different model for the rest of this session without disturbing that default.

Practical effect for the user: enabling "Parakeet TDT" once in the model browser makes it available in the mic quick-pick as a single entry covering all 25 of its languages, instead of 25 individual per-language toggles that never actually constrained what the model would recognize anyway.

`Settings.selectedTtsModelId` is unrelated to this change and is left alone — it drives TTS isolate pre-warm/crash-guard lifecycle in `TtsNotifier`, not the language-routing fallback chain (`defaultTtsModelId` does that). ASR has no equivalent lifecycle field to preserve; `selectedAsrModelId` had no callers outside the routing fallback and card/settings display, so renaming it in place is a clean rename, not a parallel addition.

### D18 — TTS Drops Its Per-Language Chips Too: One Shared Checkbox Widget for Both Types *(supersedes D14's chip mechanism)*

D14 moved TTS to "always chips, one per declared language, never a checkbox" specifically to unify the single- and multi-language cases. Fourth-round review reversed that: with ASR's own control settling on a single quick-pick checkbox regardless of language count (D15), TTS's chip row became the odd one out rather than the unified case — two different-looking controls for two conceptually parallel actions ("mark this model relevant to how I use this type"). The chips were also solving a problem the actual catalog doesn't have: every TTS model in the catalog and every imported TTS model declares exactly one language in practice (D4's original assumption), so the multi-language chip path was speculative machinery for a case that doesn't occur.

**TTS model cards get the exact same checkbox widget ASR cards use** — literally one shared component (`_ModelToggleCheckbox`, parameterized by type), not two similar-looking ones. The underlying action differs by type, same as the shared default-star widget already does:
- TTS: toggling the checkbox assigns/unassigns the model to its first declared language (`ttsLanguagePreferences[language] = modelId` / removed) — reverting to D4's original one-language-per-TTS-model behavior, now via the shared widget rather than a TTS-specific one. `ttsLanguagePreferences` (the `Map<String, String>` routing table) and its resolution chain in `model_resolver.dart` are completely unchanged — this is a UI-layer simplification only.
- ASR: unchanged from D15 — toggling adds/removes the model from `asrQuickPickModelIds`.

A TTS model whose only declared language is the unenumerable `multi` sentinel gets no checkbox (nothing meaningful to assign it to) — same exclusion D11 originally specified, now expressed as "no concrete language available" rather than "language count > 1."

`_LanguageAssignmentChips` (the `FilterChip` row) is deleted entirely, along with the body-row branching between chips and a plain text line — every card, ASR or TTS, now just shows its declared languages as static informational text (`entry.languages.join(', ')`), with the shared checkbox and shared default star in the header being the only interactive controls, identically positioned and identically styled for both types.

## Open Questions

None — design is sufficient to begin implementation. The language code parser format will be finalized during backend implementation.
