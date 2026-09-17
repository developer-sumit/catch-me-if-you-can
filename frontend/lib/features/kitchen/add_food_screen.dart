import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../camera/camera_screen.dart';

const _foodTypes = [
  'rice',
  'dal',
  'roti',
  'vegetables',
  'curry',
  'biryani',
  'bread',
  'fruits',
  'dairy',
  'other',
];

class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({super.key});

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  final form = GlobalKey<FormState>();
  final quantity = TextEditingController();
  final notes = TextEditingController();
  String food = 'rice';
  bool safeContainer = false;
  bool safeTemperature = false;
  bool submitting = false;
  String? error;
  Map<String, String> fieldErrors = {};

  bool get _safetyConfirmed => safeContainer && safeTemperature;

  @override
  void initState() {
    super.initState();
    quantity.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    quantity.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      error = null;
      fieldErrors = {};
    });
    if (!form.currentState!.validate()) return;
    if (!_safetyConfirmed) {
      setState(() =>
          error = 'Confirm both food-safety checks before publishing.');
      return;
    }
    setState(() => submitting = true);
    try {
      await ref.read(apiProvider).post('/waste/log', {
        'foodType': food,
        'quantity': double.parse(quantity.text.trim()),
        'unit': 'kg',
        'notes': notes.text.trim(),
      });
      if (!mounted) return;
      showSuccess(context, 'Published. Nearby NGOs can claim it now.');
      Navigator.pop(context, true);
    } on ApiException catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.message;
        fieldErrors = exception.fieldErrors;
      });
      form.currentState!.validate();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not publish food. Please try again.');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(quantity.text.trim());
    final ready = parsed != null && parsed > 0 && _safetyConfirmed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log surplus'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            child: MaxWidth(
              width: 760,
              child: Padding(
                padding: context.pagePadding.copyWith(bottom: 40),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('What is available?',
                          style: context.text.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        'Accurate details help a nearby organization decide '
                        'whether they can collect it in time.',
                        style: context.text.bodyMedium
                            ?.copyWith(color: context.tokens.inkSoft),
                      ),
                      const SizedBox(height: 20),
                      _FoodTypePicker(
                        selected: food,
                        onSelected: (value) => setState(() => food = value),
                      ),
                      const SizedBox(height: 12),
                      _QuantityCard(
                        controller: quantity,
                        fieldError: fieldErrors['quantity'],
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: TextFormField(
                          controller: notes,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Pickup and storage notes',
                            hintText:
                                'Packaging, allergens, pickup window, who to '
                                'ask for at the door…',
                            alignLabelWithHint: true,
                          ),
                          validator: (_) => fieldErrors['notes'],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SafetyCard(
                        container: safeContainer,
                        temperature: safeTemperature,
                        onContainer: (value) =>
                            setState(() => safeContainer = value),
                        onTemperature: (value) =>
                            setState(() => safeTemperature = value),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 18, color: context.colors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.colors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _PublishBar(
        enabled: ready,
        submitting: submitting,
        summary: parsed == null || parsed <= 0
            ? 'Add a quantity to continue'
            : _safetyConfirmed
                ? '${_format(parsed)} kg of ${foodLabel(food).toLowerCase()}'
                : 'Confirm the two safety checks',
        onSubmit: submit,
      ),
    );
  }
}

/// Ten food types fit on screen as chips. A dropdown hid them behind a tap and
/// gave no sense of what the options were.
class _FoodTypePicker extends StatelessWidget {
  const _FoodTypePicker({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Food type', style: context.text.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CameraScreen()),
                  ),
                  icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                  label: Text(context.isCompact ? 'Scan' : 'Identify by camera'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in _foodTypes)
                  ChoiceChip(
                    selected: type == selected,
                    onSelected: (_) => onSelected(type),
                    showCheckmark: false,
                    avatar: Text(foodEmoji(type),
                        style: const TextStyle(fontSize: 14)),
                    label: Text(foodLabel(type)),
                    selectedColor: context.colors.primaryContainer,
                    labelStyle: context.text.labelMedium?.copyWith(
                      color: type == selected
                          ? context.colors.onPrimaryContainer
                          : context.tokens.ink,
                    ),
                    side: BorderSide(
                      color: type == selected
                          ? context.colors.primary.withValues(alpha: 0.4)
                          : context.tokens.hairline,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _QuantityCard extends StatelessWidget {
  const _QuantityCard({required this.controller, this.fieldError});
  final TextEditingController controller;
  final String? fieldError;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                suffixText: 'kg',
                prefixIcon: Icon(Icons.scale_outlined),
              ),
              validator: (value) {
                final number = double.tryParse(value?.trim() ?? '');
                if (number == null || number <= 0) {
                  return 'Enter a quantity greater than 0';
                }
                if (number > 10000) return 'Quantity cannot exceed 10,000 kg';
                return fieldError;
              },
            ),
            const SizedBox(height: 12),
            // Most entries are round numbers; presets remove the keyboard step.
            Wrap(
              spacing: 8,
              children: [
                for (final preset in [2, 5, 10, 20, 50])
                  ActionChip(
                    label: Text('$preset kg'),
                    onPressed: () => controller.text = '$preset',
                  ),
              ],
            ),
          ],
        ),
      );
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({
    required this.container,
    required this.temperature,
    required this.onContainer,
    required this.onTemperature,
  });
  final bool container, temperature;
  final ValueChanged<bool> onContainer, onTemperature;

  @override
  Widget build(BuildContext context) {
    final done = container && temperature;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.verified_rounded : Icons.shield_outlined,
                size: 19,
                color: done ? context.tokens.positive : context.tokens.inkSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Food safety', style: context.text.titleMedium),
              ),
              Text(
                '${(container ? 1 : 0) + (temperature ? 1 : 0)} of 2',
                style: context.text.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Both are required before a listing can go live.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: container,
            onChanged: (value) => onContainer(value ?? false),
            title: const Text('Packed in clean, food-grade containers'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: temperature,
            onChanged: (value) => onTemperature(value ?? false),
            title: const Text('Stored at a safe temperature since cooking'),
          ),
        ],
      ),
    );
  }
}

/// A sticky bar that states why the button is disabled, instead of leaving the
/// user to guess which check is missing.
class _PublishBar extends StatelessWidget {
  const _PublishBar({
    required this.enabled,
    required this.submitting,
    required this.summary,
    required this.onSubmit,
  });
  final bool enabled, submitting;
  final String summary;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.tokens.raised,
          border: Border(top: BorderSide(color: context.tokens.hairline)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: !enabled || submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_rounded, size: 18),
                  label: Text(submitting ? 'Publishing…' : 'Publish'),
                ),
              ],
            ),
          ),
        ),
      );
}

String _format(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);
