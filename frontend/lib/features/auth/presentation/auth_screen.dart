import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/responsive.dart';
import '../../../core/theme.dart';
import '../../../shared/location_picker.dart';
import '../../../shared/widgets.dart';
import '../auth_controller.dart';

/// One page of the registration wizard.
enum SignUpStep {
  account(
    title: 'Your account',
    label: 'Account',
    blurb: 'How you sign in, and which side of the handover you are on.',
    icon: Icons.person_outline_rounded,
    fields: {'role', 'name', 'email', 'password'},
  ),
  organization(
    title: 'Your organization',
    label: 'Organization',
    blurb: 'What partners see when your listings reach them.',
    icon: Icons.storefront_outlined,
    fields: {'organization', 'phone', 'address'},
  ),
  location(
    title: 'Your location',
    label: 'Location',
    blurb: 'Where pickups happen, so partners can be ranked by distance.',
    icon: Icons.place_outlined,
    fields: {'latitude', 'longitude', 'location'},
  );

  const SignUpStep({
    required this.title,
    required this.label,
    required this.blurb,
    required this.icon,
    required this.fields,
  });

  final String title, label, blurb;
  final IconData icon;

  /// Server-side error keys owned by this step, so a rejected field sends the
  /// user back to the page that holds it.
  final Set<String> fields;

  bool get isLast => index == SignUpStep.values.length - 1;
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({this.initialError, super.key});
  final String? initialError;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  // A form per page: "Continue" must validate only what is on screen, and
  // FormState.validate() has no way to check a subset.
  final _signIn = GlobalKey<FormState>();
  final _stepForms = {
    for (final step in SignUpStep.values) step: GlobalKey<FormState>(),
  };

  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final organization = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final latitude = TextEditingController();
  final longitude = TextEditingController();

  bool isRegistering = false;
  bool isSubmitting = false;
  bool hidePassword = true;
  String role = 'kitchen';
  String? formError;
  Map<String, String> fieldErrors = {};

  SignUpStep step = SignUpStep.account;

  /// Pages stay mounted once reached so going back does not lose their state
  /// or their [FormState].
  SignUpStep reached = SignUpStep.account;

  @override
  void initState() {
    super.initState();
    password.addListener(() {
      if (isRegistering) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      email,
      password,
      organization,
      phone,
      address,
      latitude,
      longitude
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- validation

  String? validateField(String field, String? localError) =>
      localError ?? fieldErrors[field];

  String? validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Enter a valid email address';
    }
    return fieldErrors['email'];
  }

  String? validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Password is required';
    if (!isRegistering) return fieldErrors['password'];
    if (text.length < 10 || text.length > 72) return 'Use 10 to 72 characters';
    if (!RegExp(r'[a-z]').hasMatch(text) ||
        !RegExp(r'[A-Z]').hasMatch(text) ||
        !RegExp(r'[0-9]').hasMatch(text)) {
      return 'Include uppercase, lowercase, and a number';
    }
    return fieldErrors['password'];
  }

  String? validateCoordinate(
      String field, String? value, double min, double max) {
    final text = value?.trim() ?? '';
    final other =
        field == 'latitude' ? longitude.text.trim() : latitude.text.trim();
    if (text.isEmpty && other.isEmpty) return fieldErrors[field];
    if (text.isEmpty) return 'Provide both coordinates';
    final number = double.tryParse(text);
    if (number == null || number < min || number > max) {
      return 'Enter a value from $min to $max';
    }
    return fieldErrors[field] ?? fieldErrors['location'];
  }

  // ------------------------------------------------------------------ actions

  void _goTo(SignUpStep target) {
    setState(() {
      step = target;
      if (target.index > reached.index) reached = target;
    });
  }

  void _continue() {
    setState(() => formError = null);
    if (_stepForms[step]!.currentState?.validate() != true) return;
    if (step.isLast) {
      submit();
      return;
    }
    _goTo(SignUpStep.values[step.index + 1]);
  }

  void _back() {
    if (step.index == 0) return;
    _goTo(SignUpStep.values[step.index - 1]);
  }

  void _toggleMode() => setState(() {
        isRegistering = !isRegistering;
        step = SignUpStep.account;
        reached = SignUpStep.account;
        fieldErrors = {};
        formError = null;
      });

  /// Sends the user to the page that owns a rejected field, so a server error
  /// is never reported on a page they cannot see.
  void _revealFirstError() {
    for (final candidate in SignUpStep.values) {
      if (candidate.fields.any(fieldErrors.containsKey)) {
        _goTo(candidate);
        _stepForms[candidate]!.currentState?.validate();
        return;
      }
    }
  }

  Future<void> submit() async {
    setState(() {
      fieldErrors = {};
      formError = null;
    });
    if (!isRegistering && _signIn.currentState?.validate() != true) return;
    setState(() => isSubmitting = true);
    try {
      final auth = ref.read(authProvider.notifier);
      if (isRegistering) {
        await auth.register({
          'name': name.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          'role': role,
          'organization': organization.text.trim(),
          'phone': phone.text.trim(),
          'address': address.text.trim(),
          'latitude': double.tryParse(latitude.text.trim()),
          'longitude': double.tryParse(longitude.text.trim()),
        });
      } else {
        await auth.login(email.text.trim(), password.text);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        fieldErrors = error.fieldErrors;
        formError = error.message;
      });
      if (isRegistering) {
        _revealFirstError();
      } else {
        _signIn.currentState?.validate();
      }
    } catch (_) {
      if (mounted) {
        setState(() => formError = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final wide = context.screenWidth >= 900;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: MaxWidth(
                  width: 1080,
                  child: Padding(
                    padding: context.pagePadding,
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 5, child: _aside(context)),
                              const SizedBox(width: 48),
                              Expanded(flex: 4, child: _card(context)),
                            ],
                          )
                        : Column(
                            children: [
                              _aside(context),
                              const SizedBox(height: 24),
                              _card(context),
                              const SizedBox(height: 24),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Left column: the pitch when signing in, the progress map when registering.
  Widget _aside(BuildContext context) {
    final wide = context.screenWidth >= 900;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Brand(),
        SizedBox(height: context.isCompact ? 24 : 36),
        if (isRegistering) ...[
          Text('Create your account',
              style: context.isCompact
                  ? context.text.headlineMedium
                  : context.text.displaySmall),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Three short steps. You can go back and change anything before '
              'the account is created.',
              style: context.text.bodyLarge
                  ?.copyWith(color: context.tokens.inkSoft),
            ),
          ),
          const SizedBox(height: 24),
          if (wide)
            _StepList(
              current: step,
              reached: reached,
              onSelect: _goTo,
            )
          else
            _StepBar(current: step),
        ] else ...[
          Text(
            'Good food belongs\non a plate.',
            style: context.isCompact
                ? context.text.headlineLarge
                : context.text.displaySmall,
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Soul Serve moves surplus from kitchens to the community '
              'organizations nearest them, before it spoils.',
              style: context.text.bodyLarge
                  ?.copyWith(color: context.tokens.inkSoft),
            ),
          ),
          const SizedBox(height: 28),
          const _Highlight(
            icon: Icons.bolt_rounded,
            title: 'Publish in under a minute',
            body: 'Pick a food type, weigh it, confirm it is safe.',
          ),
          const _Highlight(
            icon: Icons.local_shipping_rounded,
            title: 'Tracked to the doorstep',
            body: 'Reserved, picked up, out for delivery, delivered.',
          ),
          const _Highlight(
            icon: Icons.phonelink_lock_rounded,
            title: 'Recognition stays on device',
            body: 'Photos are labelled locally and never uploaded.',
          ),
        ],
      ],
    );
  }

  Widget _card(BuildContext context) => AppCard(
        padding: EdgeInsets.all(context.isCompact ? 18 : 26),
        child: isRegistering ? _signUpCard(context) : _signInCard(context),
      );

  Widget _signInCard(BuildContext context) => Form(
        key: _signIn,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome back', style: context.text.headlineSmall),
            const SizedBox(height: 6),
            Text('Sign in to continue your food rescue work.',
                style: context.text.bodySmall),
            const SizedBox(height: 22),
            _emailField(),
            const SizedBox(height: 12),
            _passwordField(),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: isSubmitting ? null : submit,
              child: isSubmitting
                  ? const _ButtonSpinner()
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: isSubmitting ? null : _toggleMode,
              child: const Text('New to Soul Serve? Create an account'),
            ),
            _errorBanner(context),
          ],
        ),
      );

  Widget _signUpCard(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(step.title, style: context.text.titleLarge),
          const SizedBox(height: 2),
          Text(step.blurb, style: context.text.bodySmall),
          const SizedBox(height: 20),
          // Every reached page stays in the tree: Offstage keeps its state and
          // its FormState alive while taking no space.
          for (final page in SignUpStep.values)
            if (page.index <= reached.index)
              Offstage(
                offstage: page != step,
                child: Form(
                  key: _stepForms[page],
                  child: switch (page) {
                    SignUpStep.account => _accountFields(context),
                    SignUpStep.organization => _organizationFields(context),
                    SignUpStep.location => _locationFields(context),
                  },
                ),
              ),
          const SizedBox(height: 22),
          Row(
            children: [
              if (step.index > 0) ...[
                OutlinedButton.icon(
                  onPressed: isSubmitting ? null : _back,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back'),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSubmitting ? null : _continue,
                  icon: isSubmitting
                      ? const _ButtonSpinner()
                      : Icon(
                          step.isLast
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                  label: Text(step.isLast ? 'Create account' : 'Continue'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: isSubmitting ? null : _toggleMode,
            child: const Text('Already registered? Sign in'),
          ),
          _errorBanner(context),
        ],
      );

  // -------------------------------------------------------------------- steps

  Widget _accountFields(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('I am a', style: context.text.labelMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 'kitchen',
                icon: const Icon(Icons.restaurant_rounded, size: 18),
                label: Text(context.isCompact ? 'Provider' : 'Food provider'),
              ),
              const ButtonSegment(
                value: 'ngo',
                icon: Icon(Icons.volunteer_activism_rounded, size: 18),
                label: Text('NGO'),
              ),
            ],
            selected: {role},
            onSelectionChanged: (selection) =>
                setState(() => role = selection.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: name,
            validator: (value) => validateField(
              'name',
              (value?.trim().length ?? 0) < 2
                  ? 'Enter at least 2 characters'
                  : null,
            ),
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          _emailField(),
          const SizedBox(height: 12),
          _passwordField(),
          const SizedBox(height: 10),
          _PasswordRequirements(value: password.text),
        ],
      );

  Widget _organizationFields(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: organization,
            validator: (value) => validateField(
              'organization',
              (value?.trim().length ?? 0) < 2
                  ? 'Organization is required'
                  : null,
            ),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Organization',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: phone,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return fieldErrors['phone'];
              final digits = text.replaceAll(RegExp(r'\D'), '');
              return validateField(
                'phone',
                digits.length < 7 || digits.length > 15
                    ? 'Enter 7 to 15 digits'
                    : null,
              );
            },
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              labelText: 'Phone',
              prefixIcon: Icon(Icons.call_outlined),
              helperText: 'Optional, but it speeds up pickup coordination.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: address,
            validator: (value) => validateField(
              'address',
              (value?.trim().length ?? 0) < 5
                  ? 'Enter a complete address'
                  : null,
            ),
            textCapitalization: TextCapitalization.sentences,
            autofillHints: const [AutofillHints.fullStreetAddress],
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Address',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
        ],
      );

  Widget _locationFields(BuildContext context) => LocationPicker(
        framed: false,
        latitude: latitude,
        longitude: longitude,
        addressOf: () => address.text,
        latitudeValidator: (value) =>
            validateCoordinate('latitude', value, -90, 90),
        longitudeValidator: (value) =>
            validateCoordinate('longitude', value, -180, 180),
        onChanged: () => setState(() {}),
      );

  // ------------------------------------------------------------ shared pieces

  Widget _emailField() => TextFormField(
        controller: email,
        validator: validateEmail,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Email',
          prefixIcon: Icon(Icons.alternate_email_rounded),
        ),
      );

  Widget _passwordField() => TextFormField(
        controller: password,
        validator: validatePassword,
        obscureText: hidePassword,
        autofillHints: [
          isRegistering ? AutofillHints.newPassword : AutofillHints.password
        ],
        onFieldSubmitted: (_) {
          if (isSubmitting) return;
          isRegistering ? _continue() : submit();
        },
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: hidePassword ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => hidePassword = !hidePassword),
            icon: Icon(hidePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
          ),
        ),
      );

  Widget _errorBanner(BuildContext context) {
    final message = formError ?? widget.initialError;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.errorContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 18, color: context.colors.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: context.text.bodySmall
                      ?.copyWith(color: context.colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

/// Vertical progress for wide screens. Visited steps are tappable so a
/// correction never costs a lap through the whole wizard.
class _StepList extends StatelessWidget {
  const _StepList({
    required this.current,
    required this.reached,
    required this.onSelect,
  });
  final SignUpStep current, reached;
  final ValueChanged<SignUpStep> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in SignUpStep.values)
          () {
            final done = step.index < current.index;
            final active = step == current;
            final visited = step.index <= reached.index;
            final color = active || done
                ? context.colors.primary
                : tokens.inkSoft;
            return InkWell(
              onTap: visited && !active ? () => onSelect(step) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active || done
                            ? context.colors.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active || done
                              ? context.colors.primary
                              : tokens.hairline,
                          width: 2,
                        ),
                      ),
                      child: done
                          ? Icon(Icons.check_rounded,
                              size: 15, color: context.colors.onPrimary)
                          : Text(
                              '${step.index + 1}',
                              style: context.text.labelSmall?.copyWith(
                                color: active
                                    ? context.colors.onPrimary
                                    : tokens.inkSoft,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      step.label,
                      style: context.text.titleSmall?.copyWith(
                        color: active ? tokens.ink : color,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// Compact progress: a labelled bar rather than three stacked rows.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.current});
  final SignUpStep current;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final step in SignUpStep.values) ...[
                if (step.index > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: step.index <= current.index
                          ? context.colors.primary
                          : context.tokens.hairline,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${current.index + 1} of ${SignUpStep.values.length} · '
            '${current.label}',
            style: context.text.labelSmall,
          ),
        ],
      );
}

class _PasswordRequirements extends StatelessWidget {
  const _PasswordRequirements({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('10+ characters', value.length >= 10),
      (
        'Upper and lowercase',
        RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value)
      ),
      ('A number', RegExp(r'[0-9]').hasMatch(value)),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (label, met) in rules)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                met ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 14,
                color: met ? context.tokens.positive : context.tokens.inkSoft,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.text.bodySmall?.copyWith(
                  color: met ? context.tokens.positive : context.tokens.inkSoft,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: context.colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  Text(body, style: context.text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
}
