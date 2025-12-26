## 1. Implementation

- [ ] 1.1 Update timestamp display format
  - [ ] 1.1.1 Change timestamp format from "user @ HH:MM:SS" to "user • HH:MM:SS"
  - [ ] 1.1.2 Move timestamp to inline position with role (single line)
  - [ ] 1.1.3 Reduce font size and use subtle color for timestamp
  - [ ] 1.1.4 Update DateFormat usage to show only time (HH:MM:SS)

- [ ] 1.2 Implement message grouping logic
  - [ ] 1.2.1 Create logic to detect consecutive messages from same sender
  - [ ] 1.2.2 Add grouping metadata to message display (first, middle, last in group)
  - [ ] 1.2.3 Show timestamp only for first message in each group
  - [ ] 1.2.4 Define group break conditions (different sender, time gap > X minutes)

- [ ] 1.3 Redesign ChatMessageBubble widget
  - [ ] 1.3.1 Remove separate timestamp container (currently centered above message)
  - [ ] 1.3.2 Integrate timestamp inline with role at top of bubble
  - [ ] 1.3.3 Move action buttons (speaker, retry) to bubble footer
  - [ ] 1.3.4 Change action buttons to outline/ghost style (reduce visual weight)
  - [ ] 1.3.5 Adjust padding and margins for tighter layout

- [ ] 1.4 Update assistant message styling
  - [ ] 1.4.1 Remove special background for assistant messages (blend with app background)
  - [ ] 1.4.2 Keep left alignment for assistant messages
  - [ ] 1.4.3 Ensure readability without background bubble (subtle border or just text)
  - [ ] 1.4.4 Maintain selectability and markdown rendering

- [ ] 1.5 Refine user message styling
  - [ ] 1.5.1 Maintain distinct background color for user messages
  - [ ] 1.5.2 Keep right alignment
  - [ ] 1.5.3 Ensure consistent padding with new button positioning

- [ ] 1.6 Implement message spacing system
  - [ ] 1.6.1 Define tight spacing for consecutive messages (same sender)
  - [ ] 1.6.2 Define larger spacing for sender transitions
  - [ ] 1.6.3 Apply spacing based on grouping metadata
  - [ ] 1.6.4 Remove excessive vertical spacing from current layout

- [ ] 1.7 Update ChatHistory widget
  - [ ] 1.7.1 Modify message iteration to include grouping logic
  - [ ] 1.7.2 Pass grouping context to ChatMessageBubble widgets
  - [ ] 1.7.3 Adjust Column spacing parameters
  - [ ] 1.7.4 Ensure empty state remains unchanged

- [ ] 1.8 Handle edge cases
  - [ ] 1.8.1 Single message display (no grouping)
  - [ ] 1.8.2 Long time gaps between messages (show timestamp for clarity)
  - [ ] 1.8.3 Error messages styling (maintain visibility)
  - [ ] 1.8.4 Pending assistant message placeholder

- [ ] 1.9 Testing
  - [ ] 1.9.1 Test with various message lengths (short, long, code blocks, tables)
  - [ ] 1.9.2 Test with consecutive messages from same sender
  - [ ] 1.9.3 Test timestamp visibility and readability
  - [ ] 1.9.4 Test action button functionality (speaker play/pause, retry)
  - [ ] 1.9.5 Verify improved message density (count messages visible on screen)
  - [ ] 1.9.6 Test on different screen sizes (phone, tablet, desktop)
  - [ ] 1.9.7 Verify accessibility (touch targets, contrast ratios)

- [ ] 1.10 Documentation
  - [ ] 1.10.1 Update UI screenshots in documentation (if any)
  - [ ] 1.10.2 Document message grouping logic and spacing values
  - [ ] 1.10.3 Note any breaking changes to chat widget API
