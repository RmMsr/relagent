# Tasks: Refactor Settings Page

## 1. Create Base Widget Components
- [ ] 1.1 Create `lib/widgets/settings/` directory structure
- [ ] 1.2 Create `SettingsTile` - base list tile showing label, value, tap handler
- [ ] 1.3 Create `SettingsSection` - header with grouped tiles
- [ ] 1.4 Create `TextEditDialog` - modal for editing text values
- [ ] 1.5 Create `UrlEditDialog` - modal with URL validation
- [ ] 1.6 Create `SliderEditDialog` - modal for numeric slider values
- [ ] 1.7 Create `SelectDialog` - modal for enum/dropdown selection

## 2. Extract Section Widgets
- [ ] 2.1 Create `BackendSelectionSection` - segmented button for backend choice
- [ ] 2.2 Create `AuthenticationSection` - reusable auth type, username, password
- [ ] 2.3 Create `OpenAiSettingsSection` - URL, model, prime message, auth
- [ ] 2.4 Create `EngineSettingsSection` - URL, auth
- [ ] 2.5 Create `VoiceSettingsSection` - TTS speaker, speed, background duration

## 3. Refactor Settings Page
- [ ] 3.1 Replace form fields with section widget composition
- [ ] 3.2 Remove TextEditingController management (handled by dialogs)
- [ ] 3.3 Simplify state to just what's needed for UI (loading, expanded states)
- [ ] 3.4 Update save flow to use provider directly (no local form state)

## 4. Health Check Integration
- [ ] 4.1 Move health check logic to settings provider or dedicated service
- [ ] 4.2 Add inline health status indicator to backend sections
- [ ] 4.3 Trigger health check on URL/auth changes

## 5. Polish & Accessibility
- [ ] 5.1 Ensure keyboard navigation works (Tab, Enter, Escape)
- [ ] 5.2 Add semantic labels for screen readers
- [ ] 5.3 Test touch targets meet 48dp minimum
- [ ] 5.4 Add haptic feedback on tile tap (mobile)

## 6. Cleanup
- [ ] 6.1 Remove unused code from old implementation
- [ ] 6.2 Run flutter analyze and fix issues
- [ ] 6.3 Test all settings flows work correctly
- [ ] 6.4 Update AGENTS.md if patterns changed
