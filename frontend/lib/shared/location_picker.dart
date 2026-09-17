import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/geocoding.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Picks a latitude/longitude on an OpenStreetMap canvas.
///
/// The pin is fixed to the centre of the viewport and the map moves underneath
/// it. That beats dropping a marker on tap: the target stays a full-screen
/// gesture instead of a finger-sized icon, and the pin can never land under
/// the thumb that placed it.
///
/// [latitude] and [longitude] stay the source of truth so the surrounding
/// [Form] keeps validating them and server-side field errors still surface.
/// Manual entry remains available for keyboard and screen-reader users, and
/// for anyone who already has exact coordinates.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    required this.latitude,
    required this.longitude,
    required this.addressOf,
    this.latitudeValidator,
    this.longitudeValidator,
    this.onChanged,
    this.framed = true,
    super.key,
  });

  final TextEditingController latitude, longitude;

  /// Reads the address field, so "Find my address" can geocode what the user
  /// has already typed instead of asking for it twice.
  final String Function() addressOf;

  final FormFieldValidator<String>? latitudeValidator, longitudeValidator;
  final VoidCallback? onChanged;

  /// Draws its own card. Set false when the picker already sits inside one, so
  /// the two borders do not nest.
  final bool framed;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  static const _fallback = LatLng(28.6139, 77.2090);

  final _controller = MapController();
  late LatLng _center = _parsed() ?? _fallback;
  bool _placed = false;
  bool _manual = false;
  bool _searching = false;
  String? _searchError;
  String? _searchResult;

  @override
  void initState() {
    super.initState();
    _placed = _parsed() != null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  LatLng? _parsed() {
    final latitude = double.tryParse(widget.latitude.text.trim());
    final longitude = double.tryParse(widget.longitude.text.trim());
    if (latitude == null || longitude == null) return null;
    if (latitude < -90 || latitude > 90) return null;
    if (longitude < -180 || longitude > 180) return null;
    return LatLng(latitude, longitude);
  }

  /// Writes the picked point back into the form fields.
  void _commit(LatLng point) {
    widget.latitude.text = point.latitude.toStringAsFixed(6);
    widget.longitude.text = point.longitude.toStringAsFixed(6);
    if (!_placed) setState(() => _placed = true);
    widget.onChanged?.call();
  }

  void _clear() {
    widget.latitude.clear();
    widget.longitude.clear();
    setState(() {
      _placed = false;
      _searchResult = null;
      _searchError = null;
    });
    widget.onChanged?.call();
  }

  Future<void> _findAddress() async {
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResult = null;
    });
    try {
      final result = await const Geocoder().search(widget.addressOf());
      if (!mounted) return;
      _controller.move(result.point, 16);
      setState(() {
        _center = result.point;
        _searchResult = result.displayName;
      });
      _commit(result.point);
    } on GeocodingException catch (error) {
      if (mounted) setState(() => _searchError = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = context.colors;

    final inset = widget.framed ? 18.0 : 0.0;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, widget.framed ? 16 : 0, inset, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your location on the map',
                          style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        _placed
                            ? 'Drag the map to fine-tune the pin.'
                            : 'Drag the map so the pin sits on your door.',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_placed)
                  IconButton(
                    tooltip: 'Clear location',
                    onPressed: _clear,
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                  ),
              ],
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.framed ? 0 : 12),
              // Unframed, the map needs its own edge: there is no card border
              // around it to supply one.
              border: widget.framed
                  ? null
                  : Border.all(color: context.tokens.hairline),
            ),
            child: SizedBox(
            height: context.isCompact ? 240 : 280,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: _placed ? 16 : 11,
                    minZoom: 2,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    // Tapping is kept for mouse users, who aim precisely and
                    // have no thumb in the way.
                    onTap: (_, point) {
                      _controller.move(point, _controller.camera.zoom);
                      setState(() => _center = point);
                      _commit(point);
                    },
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) setState(() => _center = camera.center);
                    },
                    onMapEvent: (event) {
                      // Commit once the gesture settles, not on every frame of
                      // the pan.
                      if (event is MapEventMoveEnd ||
                          event is MapEventFlingAnimationEnd ||
                          event is MapEventDoubleTapZoomEnd) {
                        _commit(event.camera.center);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'org.soulserve.app',
                    ),
                  ],
                ),
                // The pin is chrome, not a map layer: it must not pan with the
                // tiles, and it must not swallow the drag.
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      // Lifts the point of the pin onto the exact centre.
                      padding: const EdgeInsets.only(bottom: 34),
                      child: _Pin(placed: _placed),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  right: 10,
                  child: _Readout(
                    point: _center,
                    placed: _placed,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: tokens.raised.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '© OpenStreetMap',
                      style: context.text.labelSmall?.copyWith(fontSize: 10),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ZoomButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Zoom in',
                        onPressed: () => _controller.move(
                          _controller.camera.center,
                          (_controller.camera.zoom + 1).clamp(2, 18),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _ZoomButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Zoom out',
                        onPressed: () => _controller.move(
                          _controller.camera.center,
                          (_controller.camera.zoom - 1).clamp(2, 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 14, inset, widget.framed ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _searching ? null : _findAddress,
                      icon: _searching
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore_rounded, size: 18),
                      label: Text(_searching
                          ? 'Searching…'
                          : 'Find my address on the map'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _manual = !_manual),
                      icon: Icon(
                        _manual
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                      ),
                      label: const Text('Enter coordinates'),
                    ),
                  ],
                ),
                if (_searchError != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 16, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _searchError!,
                          style: context.text.bodySmall
                              ?.copyWith(color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_searchResult != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 16, color: tokens.positive),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Matched ${_searchResult!}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                // Always mounted so the form can validate and focus the fields
                // even while the section is collapsed.
                Offstage(
                  offstage: !_manual,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: widget.latitude,
                            validator: widget.latitudeValidator,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true, signed: true),
                            decoration:
                                const InputDecoration(labelText: 'Latitude'),
                            onChanged: (_) => _syncFromFields(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: widget.longitude,
                            validator: widget.longitudeValidator,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true, signed: true),
                            decoration:
                                const InputDecoration(labelText: 'Longitude'),
                            onChanged: (_) => _syncFromFields(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return widget.framed
        ? AppCard(padding: EdgeInsets.zero, child: body)
        : body;
  }

  /// Typed coordinates move the map, so the two inputs never disagree.
  void _syncFromFields() {
    final point = _parsed();
    if (point == null) {
      if (_placed) setState(() => _placed = false);
      return;
    }
    _controller.move(point, _controller.camera.zoom);
    setState(() {
      _center = point;
      _placed = true;
    });
    widget.onChanged?.call();
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.placed});
  final bool placed;

  @override
  Widget build(BuildContext context) {
    final color =
        placed ? context.colors.primary : context.tokens.inkSoft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.storefront_rounded,
              size: 16, color: Colors.white),
        ),
        // A stem down to the exact point the coordinates refer to.
        Container(width: 2, height: 14, color: Colors.white),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.point, required this.placed});
  final LatLng point;
  final bool placed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.raised.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              placed ? Icons.place_rounded : Icons.touch_app_rounded,
              size: 14,
              color: placed ? context.colors.primary : tokens.inkSoft,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                placed
                    ? '${point.latitude.toStringAsFixed(5)}, '
                        '${point.longitude.toStringAsFixed(5)}'
                    : 'Drag to place the pin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: tokens.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: context.tokens.raised.withValues(alpha: 0.93),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: context.tokens.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(icon, size: 18, color: context.tokens.ink),
            ),
          ),
        ),
      );
}
