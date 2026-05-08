import 'package:flutter/material.dart';

import '/agentic/models.dart';

// -- Approval Card --

class ApprovalCard extends StatefulWidget {
  final ApprovalData approval;
  final SensitivityLevel sessionSensitivity;
  final bool isActionable;
  final ValueChanged<SensitivityLevel>? onChangeSensitivity;
  final void Function(ApprovalData, GrantRequest, bool isGlobal)? onGrant;
  final ValueChanged<String>? onDecline;

  const ApprovalCard({
    super.key,
    required this.approval,
    required this.sessionSensitivity,
    this.isActionable = true,
    this.onChangeSensitivity,
    this.onGrant,
    this.onDecline,
  });

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  bool _isGlobal = false;
  Duration? _selectedExpiry;
  Set<String> _wildcardParams = {};
  final Set<String> _expandedParams = {};
  bool _isExpanded = false;
  bool _isPurposeExpanded = false;

  static const _expiryOptions = [
    null,
    Duration(days: 2),
    Duration(days: 1),
    Duration(hours: 2),
    Duration(hours: 1),
    Duration(minutes: 15),
  ];

  String _formatExpiryDuration(Duration? d) {
    if (d == null) return 'Never';
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}min';
  }

  String _formatExpiryAbsolute(DateTime? expiresAt) {
    if (expiresAt == null) return 'Never';
    final local = expiresAt.toLocal();
    final now = DateTime.now();
    final diff = local.difference(now);
    if (diff.isNegative) return 'Expired';
    // Same day: show time only
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approval = widget.approval;
    final isResolved = approval.resolution != ApprovalResolution.pending;
    final isStale = approval.resolution == ApprovalResolution.stale;
    final hasMismatch =
        approval.sensitivity.value > widget.sessionSensitivity.value;
    final borderSide =
        BorderSide(color: theme.colorScheme.outlineVariant, width: 1);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: isStale
          ? theme.colorScheme.surfaceContainerHighest.withAlpha(128)
          : isResolved
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isStale
              ? theme.colorScheme.outlineVariant
              : approval.sensitivity.color.withAlpha(isResolved ? 128 : 255),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section 1 — Header
          _buildHeader(theme, isResolved, isStale, borderSide),

          // Detail sections — shown when pending+actionable, or when resolved+expanded
          if ((!isResolved && !isStale && widget.isActionable) ||
              (isResolved && _isExpanded)) ...[
            // Section 2 — Sensitivity row
            _buildSensitivityRow(theme, borderSide),

            // Section 3 — Parameters table
            if (approval.allowedParameters.isNotEmpty)
              _buildParamsTable(theme, borderSide, readOnly: isResolved),

            // Section 4 — Scope selector
            if (!isResolved)
              _buildScopeSelector(theme, borderSide)
            else
              _buildReadOnlyRow(
                theme,
                borderSide,
                label: 'Scope',
                value: _isGlobal ? 'Any session' : 'This session',
              ),

            // Section 5 — Expiry selector
            if (!isResolved)
              _buildExpirySelector(theme, borderSide)
            else
              _buildReadOnlyRow(
                theme,
                borderSide,
                label: 'Expires',
                value: _formatExpiryAbsolute(approval.expiresAt),
              ),

            // Sensitivity mismatch banner
            if (!isResolved && hasMismatch) _buildMismatchBanner(theme, borderSide),

            // Section 6 — Action buttons
            if (!isResolved) _buildActionButtons(theme, borderSide),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    bool isResolved,
    bool isStale,
    BorderSide borderSide,
  ) {
    final approval = widget.approval;
    final typeStr =
        'type:${approval.type.value}, component: ${approval.component ?? 'none'}';
    final IconData headerIcon;
    final Color headerIconColor;
    if (isStale) {
      headerIcon = Icons.help_outline;
      headerIconColor = theme.colorScheme.onSurfaceVariant;
    } else if (approval.resolution == ApprovalResolution.granted) {
      headerIcon = Icons.check_circle_outline;
      headerIconColor = theme.colorScheme.primary;
    } else if (approval.resolution == ApprovalResolution.declined) {
      headerIcon = Icons.cancel_outlined;
      headerIconColor = theme.colorScheme.onSurfaceVariant;
    } else {
      headerIcon = Icons.help_outline;
      headerIconColor = theme.colorScheme.onSurface;
    }
    final iconColor = headerIconColor;
    final header = Container(
      decoration: BoxDecoration(
        border: ((!isResolved && !isStale) || (isResolved && _isExpanded))
            ? Border(bottom: borderSide)
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Icon(headerIcon, size: 28, color: headerIconColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Approval: ',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: iconColor,
                              ),
                            ),
                            TextSpan(
                              text: typeStr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: iconColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isResolved)
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => setState(() => _isPurposeExpanded = !_isPurposeExpanded),
                  child: Text(
                    approval.purpose,
                    maxLines: _isPurposeExpanded ? null : 1,
                    overflow: _isPurposeExpanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isResolved) {
      return InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: header,
      );
    }
    return header;
  }


  Widget _buildSensitivityRow(ThemeData theme, BorderSide borderSide) {
    final approval = widget.approval;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Current Sensitivity: ',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: approval.sensitivity.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: approval.sensitivity.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamsTable(ThemeData theme, BorderSide borderSide, {bool readOnly = false}) {
    final params = widget.approval.allowedParameters;
    final keys = params.keys.toList();
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cellStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
    );

    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table header
          Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                Colors.amber.withAlpha(25),
                theme.colorScheme.surfaceContainer,
              ),
              border: Border(bottom: borderSide),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('Parameter', style: headerStyle)),
                Expanded(flex: 5, child: Text('Value', style: headerStyle)),
                SizedBox(
                  width: 72,
                  child: Text(
                    'Any value',
                    style: headerStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          // Table rows
          ...keys.map((key) {
            final value = params[key];
            final isWildcard = _wildcardParams.contains(key);
            return Container(
              decoration: key != keys.last
                  ? BoxDecoration(border: Border(bottom: borderSide))
                  : null,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(key, style: cellStyle),
                  ),
                  Expanded(
                    flex: 5,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        if (_expandedParams.contains(key)) {
                          _expandedParams.remove(key);
                        } else {
                          _expandedParams.add(key);
                        }
                      }),
                      child: Text(
                        value.toString(),
                        maxLines: _expandedParams.contains(key) ? null : 2,
                        overflow: _expandedParams.contains(key)
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: cellStyle?.copyWith(
                          color: isWildcard
                              ? theme.colorScheme.onSurfaceVariant.withAlpha(100)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Center(
                      child: readOnly
                          ? Icon(
                              isWildcard
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                if (isWildcard) {
                                  _wildcardParams.remove(key);
                                } else {
                                  // Only one wildcard at a time
                                  _wildcardParams = {key};
                                }
                              }),
                              child: Icon(
                                isWildcard
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: isWildcard
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildReadOnlyRow(
    ThemeData theme,
    BorderSide borderSide, {
    required String label,
    required String value,
  }) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeSelector(ThemeData theme, BorderSide borderSide) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('This session')),
          ButtonSegment(value: true, label: Text('Any session')),
        ],
        selected: {_isGlobal},
        onSelectionChanged: (s) => setState(() => _isGlobal = s.first),
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: theme.textTheme.labelSmall,
        ),
      ),
    );
  }

  Widget _buildExpirySelector(ThemeData theme, BorderSide borderSide) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Text('Expires:', style: theme.textTheme.labelSmall),
          ..._expiryOptions.map((d) {
          return ChoiceChip(
            label: Text(_formatExpiryDuration(d)),
            selected: _selectedExpiry == d,
            onSelected: (_) => setState(() => _selectedExpiry = d),
            visualDensity: VisualDensity.compact,
            labelStyle: theme.textTheme.labelSmall,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          );
        }),
        ],
      ),
    );
  }

  Widget _buildMismatchBanner(ThemeData theme, BorderSide borderSide) {
    final targetLevel = widget.approval.sensitivity;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.amber.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber, width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: Colors.amber,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Session sensitivity is lower than required',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () =>
                  widget.onChangeSensitivity?.call(targetLevel),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Change to ${targetLevel.label}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, BorderSide borderSide) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => widget.onDecline?.call(widget.approval.id),
                style: TextButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Continue without'),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  final wildcardKey = _wildcardParams.isEmpty
                      ? null
                      : _wildcardParams.first;
                  final grant = GrantRequest.fromApproval(
                    widget.approval,
                    maxSensitivity: widget.approval.sensitivity,
                    wildcardParameter: wildcardKey,
                    expiresAt: _selectedExpiry != null
                        ? DateTime.now().add(_selectedExpiry!)
                        : null,
                  );
                  widget.onGrant?.call(widget.approval, grant, _isGlobal);
                },
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Approve'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Approval Group --

class ApprovalGroup extends StatelessWidget {
  final AgenticMessage message;
  final SensitivityLevel sessionSensitivity;
  final bool isActionable;
  /// True while a /continue is in flight; suppresses the recovery Continue button.
  final bool isAgentRunInFlight;
  final ValueChanged<SensitivityLevel>? onChangeSensitivity;
  final void Function(ApprovalData, GrantRequest, bool isGlobal)? onGrant;
  final ValueChanged<String>? onDecline;
  final VoidCallback? onContinue;
  final VoidCallback? onStop;

  const ApprovalGroup({
    super.key,
    required this.message,
    required this.sessionSensitivity,
    this.isActionable = true,
    this.isAgentRunInFlight = false,
    this.onChangeSensitivity,
    this.onGrant,
    this.onDecline,
    this.onContinue,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approvals = message.approvals ?? [];
    final isStale = message.isStale;
    // Hide Stop once any approval is decided — the auto-continue has fired.
    final allPending = approvals.every(
      (a) => a.resolution == ApprovalResolution.pending,
    );
    // Stuck cycle (in-flight, all decided, no run): offer Continue.
    final allDecided = approvals.isNotEmpty &&
        approvals.every((a) => a.resolution != ApprovalResolution.pending);
    final showContinueButton = isActionable &&
        !isStale &&
        !message.isFinal &&
        onContinue != null &&
        allDecided &&
        !isAgentRunInFlight;
    final showStopBar = isActionable &&
        !isStale &&
        !message.isFinal &&
        onStop != null &&
        allPending;

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.notification != null) ...[
            SystemNoteBubble(text: message.notification!),
            const SizedBox(height: 4),
          ],
          for (final approval in approvals)
            ApprovalCard(
              approval: approval,
              sessionSensitivity: sessionSensitivity,
              isActionable: isActionable && !isStale,
              onChangeSensitivity: onChangeSensitivity,
              onGrant: onGrant,
              onDecline: onDecline,
            ),
          if (isStale) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: const Text('Continue at new sensitivity'),
                ),
              ),
            ),
          ],
          if (showContinueButton)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('approval-group-continue-button'),
                  onPressed: onContinue,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Continue'),
                ),
              ),
            ),
          if (showStopBar)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('approval-group-stop-bar'),
                  onPressed: onStop,
                  icon: Icon(
                    Icons.cancel_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    'Stop and ask something else',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Referenced by ApprovalGroup — imported from widgets.dart
// ignore: avoid_classes_with_only_static_members
class SystemNoteBubble extends StatelessWidget {
  final String text;

  const SystemNoteBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
