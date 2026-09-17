import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import 'claim_stage.dart';

/// A horizontal progress rail for one claim, in the shape people already know
/// from parcel tracking: filled nodes behind, a ringed node for where the
/// delivery is now, hollow nodes ahead.
class DeliveryTracker extends StatelessWidget {
  const DeliveryTracker({
    required this.current,
    required this.timestamps,
    super.key,
  });

  final ClaimStage current;

  /// Stage -> when it was reached. Missing entries render without a time,
  /// which is what a skipped stage looks like.
  final Map<ClaimStage, DateTime?> timestamps;

  @override
  Widget build(BuildContext context) {
    final steps = context.tokens.pipelineSteps(ClaimStage.values.length);
    final compact = context.isCompact;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stage in ClaimStage.values) ...[
          if (!stage.isFirst)
            Expanded(
              child: Padding(
                // Sits on the centreline of the nodes beside it.
                padding: const EdgeInsets.only(top: 12, left: 2, right: 2),
                child: _Connector(filled: stage.index <= current.index),
              ),
            ),
          _Node(
            stage: stage,
            current: current,
            color: steps[stage.index],
            at: timestamps[stage],
            compact: compact,
          ),
        ],
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: filled ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Stack(
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: context.tokens.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            FractionallySizedBox(
              widthFactor: value,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      );
}

class _Node extends StatelessWidget {
  const _Node({
    required this.stage,
    required this.current,
    required this.color,
    required this.at,
    required this.compact,
  });

  final ClaimStage stage, current;
  final Color color;
  final DateTime? at;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final done = stage.index < current.index;
    final active = stage == current;
    final reached = done || active;
    final tokens = context.tokens;

    return SizedBox(
      width: compact ? 68 : 96,
      child: Column(
        children: [
          Semantics(
            label: '${stage.label}: '
                '${active ? 'current step' : done ? 'done' : 'not started'}',
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: reached ? color : tokens.raised,
                shape: BoxShape.circle,
                border: Border.all(
                  color: reached ? color : tokens.hairline,
                  width: 2,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                done ? Icons.check_rounded : stage.icon,
                size: 14,
                color: reached ? Colors.white : tokens.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            compact ? stage.short : stage.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: reached ? tokens.ink : tokens.inkSoft,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          SizedBox(
            height: 26,
            child: at == null || !reached
                ? null
                : Text(
                    // Date over time: one line of "MMM d, h:mm a" does not fit
                    // a 68px node and was truncating to "Sep 17 11:3…".
                    '${DateFormat.MMMd().format(at!)}\n'
                    '${DateFormat.jm().format(at!)}',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall
                        ?.copyWith(fontSize: 10, height: 1.25),
                  ),
          ),
        ],
      ),
    );
  }
}
