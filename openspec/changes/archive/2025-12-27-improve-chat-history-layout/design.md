# Design: Improve Chat History Layout

## Context

The current chat history layout uses excessive vertical spacing, with timestamps on separate centered lines and large gaps between messages. This results in poor space utilization - only 3-4 messages visible on a typical mobile screen - making it difficult to scan conversation context.

### Background

- Current layout inherited from initial prototype, not optimized for production use
- Centered timestamp headers take up ~30-40% of vertical space
- Action buttons positioned outside bubbles add horizontal clutter
- No visual grouping for consecutive messages from same sender

### Constraints

- Must maintain all existing functionality (TTS, retry, markdown rendering)
- Must work on all screen sizes (mobile, tablet, desktop)
- Must preserve accessibility (touch targets, contrast, screen readers)
- Cannot break existing message data structure

### Stakeholders

- End users: Need efficient conversation overview, especially for hands-free/voice usage
- Developers: Need maintainable widget structure and clear grouping logic

## Goals / Non-Goals

### Goals

- Increase message density by 2-3x (show 5-8 messages instead of 3-4)
- Create clear visual flow through message grouping
- Integrate action buttons into bubbles to reduce clutter
- Maintain full functionality and accessibility
- Align with modern chat UI patterns (WhatsApp, Telegram style)

### Non-Goals

- Not changing message data structure or storage
- Not implementing swipe gestures or advanced interactions
- Not adding new features (reactions, editing, etc.)
- Not redesigning the entire chat page (just message display)

## Decisions

### Decision 1: Inline timestamp with bullet separator

**What:** Change timestamp format from separate line "user @ 18:46:21" to inline "user • 18:46:21"

**Why:**
- Eliminates entire line of vertical space per message
- Bullet "•" is more modern and visually lighter than "@"
- Single line is easier to scan than centered header
- Aligns with common chat UI patterns

**Alternatives considered:**
- Relative timestamps ("2m ago"): Requires updating logic, not always clearer
- No timestamps: Too extreme, users want temporal reference
- Timestamp at end of message: Awkward with right-aligned user messages

**Implementation:**
```dart
// Old (separate Container):
Container(
  alignment: Alignment.bottomCenter,
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: Text('${message.role.name} @ $time', ...),
),

// New (inline in bubble header):
Row(
  children: [
    Text('${message.role.name} • $time',
      style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
    ),
  ],
)
```

### Decision 2: Message grouping with 5-minute time threshold

**What:** Group consecutive messages from same sender, show timestamp only for first message in group. Break groups when sender changes or time gap exceeds 5 minutes.

**Why:**
- Reduces timestamp redundancy (every message currently shows timestamp)
- Creates visual coherence for related messages
- 5-minute threshold balances grouping with temporal clarity
- Matches user mental model of conversation "chunks"

**Alternatives considered:**
- No grouping: Misses opportunity to reduce redundancy
- Always group same sender: Confusing when large time gaps (hours)
- Shorter threshold (2 min): Too aggressive, breaks natural pauses
- Longer threshold (10 min): Groups unrelated exchanges

**Grouping logic:**
```dart
class MessageGroup {
  final ChatRole sender;
  final List<ChatMessage> messages;
  final DateTime firstMessageTime;

  bool shouldBreakGroup(ChatMessage nextMessage) {
    // Break if sender changes
    if (nextMessage.role != sender) return true;

    // Break if time gap > 5 minutes
    final lastMessageTime = messages.last.timestamp;
    final timeDiff = nextMessage.timestamp.difference(lastMessageTime);
    return timeDiff.inMinutes > 5;
  }
}

List<MessageGroup> groupMessages(List<ChatMessage> messages) {
  final groups = <MessageGroup>[];
  MessageGroup? currentGroup;

  for (final message in messages) {
    if (currentGroup == null || currentGroup.shouldBreakGroup(message)) {
      // Start new group
      currentGroup = MessageGroup(
        sender: message.role,
        messages: [message],
        firstMessageTime: message.timestamp,
      );
      groups.add(currentGroup);
    } else {
      // Add to existing group
      currentGroup.messages.add(message);
    }
  }

  return groups;
}
```

### Decision 3: Action buttons in bubble footer with outline style

**What:** Move speaker (assistant) and retry (user) buttons from external positioning into message bubble footers using outline/ghost button style.

**Why:**
- Eliminates horizontal space waste (buttons currently outside bubbles)
- Reduces visual clutter (outline style is lighter than filled icons)
- Keeps actions contextually close to message content
- Footer position doesn't interfere with message readability

**Alternatives considered:**
- Hide buttons, show on hover: Doesn't work well for mobile/touch
- Toolbar above/below message: Takes up even more space
- Keep external but closer: Still wastes horizontal space

**Button styling:**
```dart
// Outline style for reduced visual weight
IconButton.outlined(
  icon: Icon(ttsIcon, size: 18),
  iconSize: 18,
  padding: const EdgeInsets.all(8),
  color: theme.colorScheme.primary.withAlpha(180), // Subtle color
  onPressed: () => onSpeak!(message.text, messageId),
)
```

**Footer layout:**
```dart
// Assistant message: speaker button on left
Row(
  mainAxisAlignment: MainAxisAlignment.start,
  children: [
    IconButton.outlined(...), // Speaker button
  ],
)

// User message: retry button on right
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    IconButton.outlined(...), // Retry button
  ],
)
```

### Decision 4: Assistant messages without background bubble

**What:** Remove background color/bubble from assistant messages, let them blend with app background. Keep distinct background for user messages.

**Why:**
- User's preference: "assistant is part of the app"
- Reduces visual weight (less colored rectangles on screen)
- Left-aligned text on plain background is clean and readable
- User messages remain clearly distinguished by background + right alignment

**Alternatives considered:**
- Both with bubbles: Too much visual weight, symmetric but cluttered
- Neither with bubbles: User messages not distinguished enough
- Subtle border for assistant: Adds line clutter, not needed with alignment

**Message styling:**
```dart
// Assistant message: no background, left-aligned
Container(
  alignment: Alignment.centerLeft,
  padding: const EdgeInsets.all(10),
  margin: const EdgeInsets.only(left: 10, right: 10),
  // No background decoration
  child: SelectableRegion(
    child: GptMarkdown(message.text, ...),
  ),
)

// User message: background bubble, right-aligned
Container(
  alignment: Alignment.centerRight,
  padding: const EdgeInsets.all(10),
  margin: const EdgeInsets.only(left: 10, right: 10),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(8),
    color: theme.colorScheme.onInverseSurface.withValues(alpha: 0.6),
  ),
  child: Text(message.text, ...),
)
```

### Decision 5: Spacing system based on grouping

**What:** Define two spacing levels:
- **Within-group**: 8 points (tight, messages visually connected)
- **Between-group**: 20 points (moderate, clear sender transition)

**Why:**
- 8pt within-group: Tight enough to show grouping, loose enough to distinguish messages
- 20pt between-group: Clear visual break without excessive gap
- Reduces spacing from current ~40-60pt (timestamp line + margins)
- Tested values that balance density with readability

**Alternatives considered:**
- Uniform spacing: Loses grouping benefit
- Even tighter (4pt): Too cramped on mobile
- Larger between-group (30pt+): Defeats space-saving purpose

**Spacing implementation:**
```dart
Widget build(BuildContext context) {
  final groups = groupMessages(messages);
  final widgets = <Widget>[];

  for (int i = 0; i < groups.length; i++) {
    final group = groups[i];

    // First message in group: show timestamp + role
    widgets.add(MessageBubble(
      message: group.messages.first,
      showHeader: true,
      ...
    ));

    // Subsequent messages in group: no timestamp
    for (int j = 1; j < group.messages.length; j++) {
      widgets.add(SizedBox(height: 8)); // Within-group spacing
      widgets.add(MessageBubble(
        message: group.messages[j],
        showHeader: false,
        ...
      ));
    }

    // Between-group spacing (if not last group)
    if (i < groups.length - 1) {
      widgets.add(SizedBox(height: 20));
    }
  }

  return Column(children: widgets);
}
```

## Risks / Trade-offs

### Risk: Timestamp visibility reduction

**Risk:** Showing timestamps only for first message in group may make it harder to determine exact timing of individual messages.

**Mitigation:**
- 5-minute threshold ensures temporal clarity (groups don't span long periods)
- Users can still see approximate timing from group's first message
- If needed, add tap-to-reveal timestamp on individual messages (future enhancement)
- Most chat apps use similar grouping without user complaints

### Risk: Increased cognitive load from tighter spacing

**Risk:** Tighter spacing may make messages harder to read or cause user fatigue.

**Mitigation:**
- 8pt and 20pt spacings are tested values, still comfortable
- Grouping actually reduces cognitive load by showing related messages together
- Clear sender distinction (alignment + background) aids scanning
- User testing will validate readability before finalizing

### Trade-off: Outline buttons vs. filled buttons

**Trade-off:** Outline buttons are less visually prominent, may be harder to notice.

**Decision:**
- Prioritize reduced clutter over maximum button prominence
- Action buttons are secondary UI (users don't click them every message)
- Icon shapes (speaker, retry) are recognizable enough
- Touch targets remain full size (44x44pt) even with outline style

### Risk: Breaking existing visual expectations

**Risk:** Users accustomed to current layout may find new design disorienting.

**Mitigation:**
- New design follows established chat UI patterns (familiar from other apps)
- Gradual rollout option: add setting to toggle old/new layout temporarily
- Improved usability will quickly become preferred
- Document change in release notes

## Migration Plan

### Implementation Steps

1. **Phase 1: Message grouping logic** (no UI changes yet)
   - Implement message grouping algorithm
   - Add unit tests for grouping edge cases
   - Prepare MessageBubble to accept `showHeader` parameter

2. **Phase 2: Update timestamp display** (isolated change)
   - Change format from "user @ HH:MM:SS" to "user • HH:MM:SS"
   - Move timestamp inline (remove separate Container)
   - Test timestamp readability

3. **Phase 3: Implement spacing system**
   - Apply within-group and between-group spacing
   - Remove old excessive spacing
   - Verify message density improvement

4. **Phase 4: Redesign message bubbles**
   - Remove background from assistant messages
   - Move action buttons to bubble footers
   - Apply outline button style
   - Test button functionality

5. **Phase 5: Integration and refinement**
   - Wire grouping logic into ChatHistory widget
   - Test with various message types (short, long, code, tables, errors)
   - Adjust spacing/styling based on testing
   - Verify accessibility compliance

6. **Phase 6: Testing and documentation**
   - Full manual testing on all platforms
   - Accessibility audit (contrast, touch targets, screen readers)
   - Update screenshots and documentation
   - Prepare release notes

### Rollback Plan

- If users report readability issues: Revert spacing to larger values
- If grouping causes confusion: Disable grouping, keep other improvements
- If button integration problematic: Move buttons back outside bubbles
- Full rollback: All changes are UI-only, no data migration needed

### Testing Strategy

**Visual regression tests:**
- Capture screenshots of chat history with different message configurations
- Compare before/after layouts for message density
- Verify grouping visual appearance

**Functional tests:**
- Message display with grouping
- Timestamp showing/hiding based on grouping
- Action button functionality (speaker, retry)
- Markdown rendering in new layout
- Error message display
- Pending message placeholder

**Accessibility tests:**
- Touch target sizes (min 44x44pt)
- Color contrast ratios (WCAG AA)
- Screen reader announcements
- Keyboard navigation

**Performance tests:**
- Scrolling smoothness with tighter spacing
- Layout rebuild performance with grouping logic
- Memory usage with message history

## Open Questions

1. **Should we add visual indicators for time gaps within groups?**
   - If 2 messages in same group are 4 minutes apart, show subtle timestamp?
   - Decision: Defer to user feedback, start without sub-group timestamps

2. **Should error messages get special grouping treatment?**
   - Always break group before/after error messages?
   - Decision: Treat errors as regular messages for now, they're rare

3. **Should we animate transitions between spacing states?**
   - When new message arrives and creates new group, animate spacing change?
   - Decision: No, adds complexity without clear UX benefit

4. **Should outline button borders match message styling?**
   - Use theme colors or fixed gray?
   - Decision: Use theme.colorScheme.primary with transparency for consistency

5. **Should we support long-press timestamp reveal?**
   - Allow users to see exact timestamp for any message by long-pressing?
   - Decision: Nice-to-have, defer to future iteration if users request it
