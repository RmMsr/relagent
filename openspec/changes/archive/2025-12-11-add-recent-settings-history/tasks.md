# Implementation Tasks

## 1. Data Model

- [ ] 1.1 Create `SettingsHistoryEntry` model with URL and model fields
- [ ] 1.2 Add JSON serialization for history entries
- [ ] 1.3 Add history list to settings provider state

## 2. History Tracking Logic

- [ ] 2.1 Implement history addition on settings save
- [ ] 2.2 Implement deduplication (move existing entry to top)
- [ ] 2.3 Implement 5-entry limit with oldest entry removal
- [ ] 2.4 Add history persistence to SharedPreferences
- [ ] 2.5 Add history loading on app startup

## 3. UI Implementation

- [ ] 3.1 Add autocomplete widget for base URL field
- [ ] 3.2 Add autocomplete widget for model field
- [ ] 3.3 Display recent entries in dropdown suggestions
- [ ] 3.4 Handle selection of recent entry

## 4. Testing

- [ ] 4.1 Test history tracking with multiple URL/model combinations
- [ ] 4.2 Test deduplication behavior
- [ ] 4.3 Test 5-entry limit enforcement
- [ ] 4.4 Test persistence across app restarts
- [ ] 4.5 Test autocomplete UI interaction
