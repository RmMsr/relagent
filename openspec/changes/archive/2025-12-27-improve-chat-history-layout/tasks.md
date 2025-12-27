## 1. Implementation

- [x] 1.1 Update timestamp display format
  - [x] 1.1.1 Change timestamp format from "user @ HH:MM:SS" to "user • HH:MM:SS"
  - [x] 1.1.2 Move timestamp to inline position with role (single line)
  - [x] 1.1.3 Reduce font size and use subtle color for timestamp
  - [x] 1.1.4 Update DateFormat usage to show only time (HH:MM:SS)

- [x] 1.2 Implement message grouping logic
  - [x] 1.2.1 Create logic to detect consecutive messages from same sender
  - [x] 1.2.2 Add grouping metadata to message display (first, middle, last in group)
  - [x] 1.2.3 Show timestamp only for first message in each group
  - [x] 1.2.4 Define group break conditions (different sender, time gap > 5 minutes)

- [x] 1.3 Redesign ChatMessageBubble widget
  - [x] 1.3.1 Remove separate timestamp container (currently centered above message)
  - [x] 1.3.2 Integrate timestamp inline with role at top of bubble
  - [x] 1.3.3 Move action buttons (speaker, retry) to bubble footer
  - [x] 1.3.4 Change action buttons to outline/ghost style (reduce visual weight)
  - [x] 1.3.5 Adjust padding and margins for tighter layout

- [x] 1.4 Update assistant message styling
  - [x] 1.4.1 Remove special background for assistant messages (blend with app background)
  - [x] 1.4.2 Keep left alignment for assistant messages
  - [x] 1.4.3 Ensure readability without background bubble (subtle border or just text)
  - [x] 1.4.4 Maintain selectability and markdown rendering

- [x] 1.5 Refine user message styling
  - [x] 1.5.1 Maintain distinct background color for user messages
  - [x] 1.5.2 Keep right alignment
  - [x] 1.5.3 Ensure consistent padding with new button positioning
  - [x] 1.5.4 Add rounded corners on left side only for "reaching in" effect
  - [x] 1.5.5 Add subtle shadow for depth
  - [x] 1.5.6 Remove right padding from container, add internal right padding

- [x] 1.6 Implement message spacing system
  - [x] 1.6.1 Define tight spacing for consecutive messages (same sender) - 8pt
  - [x] 1.6.2 Define larger spacing for sender transitions - 20pt
  - [x] 1.6.3 Apply spacing based on grouping metadata
  - [x] 1.6.4 Remove excessive vertical spacing from current layout

- [x] 1.7 Update ChatHistory widget
  - [x] 1.7.1 Modify message iteration to include grouping logic
  - [x] 1.7.2 Pass grouping context to ChatMessageBubble widgets
  - [x] 1.7.3 Adjust Column spacing parameters
  - [x] 1.7.4 Ensure empty state remains unchanged

- [x] 1.8 Handle edge cases
  - [x] 1.8.1 Single message display (no grouping)
  - [x] 1.8.2 Long time gaps between messages (show timestamp for clarity)
  - [x] 1.8.3 Error messages styling (maintain visibility)
  - [x] 1.8.4 Pending assistant message placeholder

- [x] 1.9 Testing
  - [x] 1.9.1 Test with various message lengths (short, long, code blocks, tables)
  - [x] 1.9.2 Test with consecutive messages from same sender
  - [x] 1.9.3 Test timestamp visibility and readability
  - [x] 1.9.4 Test action button functionality (speaker play/pause, retry)
  - [x] 1.9.5 Verify improved message density (count messages visible on screen)
  - [x] 1.9.6 Test on different screen sizes (phone, tablet, desktop)
  - [x] 1.9.7 Verify accessibility (touch targets, contrast ratios)
  - [x] 1.9.8 Fix TTS button size consistency (hourglass indicator)

- [x] 1.10 Documentation
  - [x] 1.10.1 Update UI screenshots in documentation (if any)
  - [x] 1.10.2 Document message grouping logic and spacing values
  - [x] 1.10.3 Note any breaking changes to chat widget API
