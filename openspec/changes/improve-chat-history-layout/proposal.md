# Change: Improve Chat History Layout

## Why

The current chat history layout wastes significant vertical space and makes it difficult to quickly scan conversation flow. Key issues:

- **Excessive vertical spacing**: Timestamps on separate centered lines above each message create large gaps
- **Poor space utilization**: Only 3-4 messages visible on screen due to spacing
- **Inconsistent visual hierarchy**: Centered timestamps don't align with left/right message alignment
- **Disrupted reading flow**: Large gaps between consecutive messages from the same sender break conversation continuity
- **Cluttered action buttons**: Speaker and retry icons positioned outside bubbles add visual noise

Improving the layout will:
- Increase message density, allowing users to see more conversation context at once
- Create clearer visual flow for hands-free usage (important for voice-first UX)
- Reduce visual clutter by integrating action buttons into message bubbles
- Improve readability by grouping consecutive messages from the same sender
- Align with modern chat UI best practices (WhatsApp, Telegram, iMessage style)

## What Changes

- **Compact timestamp display**: Move timestamps inline with role on a single line (e.g., "user • 18:46:21" instead of separate line with "user @ 18:46:21")

- **Message grouping**: Implement chat bubble style where consecutive messages from the same sender are visually grouped:
  - Minimal spacing between consecutive messages from same sender
  - Single timestamp shown once per message group (not for every message)
  - Clear visual break between different senders

- **Integrated action buttons**: Move speaker and retry icons into message bubble footers:
  - Position at bottom of message bubble
  - Use outline/ghost button style to reduce visual weight
  - Maintain same functionality (play/pause/retry)

- **Refined visual identity**:
  - Assistant messages blend with app background (no special bubble style)
  - User messages maintain distinct background and right alignment
  - Cleaner visual separation between user input and assistant responses

- **Reduced vertical spacing**: Significantly tighten spacing between all UI elements while maintaining readability

## Impact

- Affected specs: `chat-history` (new capability)
- Affected code:
  - `apps/lib/chat/widgets.dart` (ChatHistory and ChatMessageBubble widgets)
  - `apps/lib/chat/models.dart` (may need message grouping logic)
  - UI theme/styling (message bubble appearance)
- Improved UX: 2-3x more messages visible on screen at once
- Better hands-free usage: Easier to glance at recent conversation flow
