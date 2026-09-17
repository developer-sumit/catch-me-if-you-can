import 'package:flutter/material.dart';

/// The stages a claimed donation moves through, in order. Mirrors
/// `domain.ClaimStages` on the server; the API values must stay in step.
enum ClaimStage {
  claimed(
    api: 'claimed',
    label: 'Reserved',
    short: 'Reserved',
    icon: Icons.bookmark_added_rounded,
    caption: 'Held for you at the kitchen',
  ),
  pickedUp(
    api: 'picked_up',
    label: 'Picked up',
    short: 'Picked up',
    icon: Icons.inventory_2_rounded,
    caption: 'Collected from the kitchen',
    action: 'Mark picked up',
  ),
  outForDelivery(
    api: 'out_for_delivery',
    label: 'Out for delivery',
    short: 'On the way',
    icon: Icons.local_shipping_rounded,
    caption: 'On the way to the community',
    action: 'Start delivery',
  ),
  delivered(
    api: 'completed',
    label: 'Delivered',
    short: 'Delivered',
    icon: Icons.task_alt_rounded,
    caption: 'Handed over and served',
    action: 'Mark delivered',
  );

  const ClaimStage({
    required this.api,
    required this.label,
    required this.short,
    required this.icon,
    required this.caption,
    this.action,
  });

  /// The server's status string.
  final String api;

  /// Full name, used in the badge and the timeline.
  final String label;

  /// Abbreviated name for the narrow tracker on phones.
  final String short;

  final IconData icon;

  /// One line describing what the stage means.
  final String caption;

  /// Label for the button that advances *into* this stage. Null for
  /// [ClaimStage.claimed], which is reached by claiming, not by advancing.
  final String? action;

  bool get isFirst => index == 0;
  bool get isLast => index == ClaimStage.values.length - 1;

  /// The stage this claim moves to next, or null once delivered.
  ClaimStage? get next => isLast ? null : ClaimStage.values[index + 1];

  /// The timestamp field the API returns for this stage.
  String get timestampKey => switch (this) {
        ClaimStage.claimed => 'claimedAt',
        ClaimStage.pickedUp => 'pickedUpAt',
        ClaimStage.outForDelivery => 'outForDeliveryAt',
        ClaimStage.delivered => 'completedAt',
      };

  /// Resolves a server status, or null when the value is not a point on the
  /// progression — a cancelled claim, or a status this build predates.
  static ClaimStage? tryFromApi(Object? value) {
    final text = value?.toString();
    for (final stage in ClaimStage.values) {
      if (stage.api == text) return stage;
    }
    return null;
  }

  /// Resolves a server status, falling back to [ClaimStage.claimed] so a claim
  /// always renders somewhere on the tracker. Check [isCancelled] first: a
  /// cancelled claim is off the progression, not at the start of it.
  static ClaimStage fromApi(Object? value) =>
      tryFromApi(value) ?? ClaimStage.claimed;

  static bool isCancelled(Object? value) => value?.toString() == 'cancelled';

  /// True once a claim needs nothing further from the NGO.
  static bool isSettled(Object? value) {
    if (isCancelled(value)) return true;
    return tryFromApi(value)?.isLast ?? false;
  }
}
