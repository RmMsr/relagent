## 1. Analysis

- [x] Analyze the race condition between input clearing and speech recognition updates
- [x] Identify the exact timing issue in RecorderButton listener

## 2. Design Solution

- [x] Add submission state tracking to ChatInput widget
- [x] Implement cooldown period after submission to block voice input updates
- [x] Modify RecorderButton to respect submission state

## 3. Implement Fix

- [x] Update ChatInput to track when submission is in progress
- [x] Modify RecorderButton voice input listener to check submission state
- [x] Add brief cooldown (500ms) after submission

## 4. Test Fix

- [x] Manually test voice input in continuous modes
- [x] Verify input clears properly after voice submission
- [x] Ensure no regression in text input behavior