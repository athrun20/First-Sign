import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/branding_store.dart';
import '../services/storage_exception.dart';
import '../theme/app_lux.dart';

/// Branding settings: company name + logo for PDF report headers.
///
/// 1. Pick logo from gallery
/// 2. Preview it
/// 3. Save branding
/// 4. Logo appears in PDF export header
class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key});

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _logoBytes;
  bool _picking = false;
  bool _dirty = false;

  bool get _hasLogo => _logoBytes != null && _logoBytes!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
    unawaited(_loadBranding());
  }

  Future<void> _loadBranding() async {
    await BrandingStore.instance.ensureLoaded();
    if (!mounted) return;
    final store = BrandingStore.instance;
    setState(() {
      _nameController.text = store.companyName;
      _logoBytes = store.logoBytes;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: kIsWeb ? null : 1024,
        maxHeight: kIsWeb ? null : 1024,
        imageQuality: kIsWeb ? null : 90,
        requestFullMetadata: false,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        _toast('Could not read that image. Try a PNG or JPG.');
        return;
      }

      setState(() {
        _logoBytes = bytes;
        _dirty = true;
      });
      _toast('Logo ready — preview below. Tap Save branding to apply.');
    } catch (e) {
      if (mounted) _toast('Could not pick image: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeLogo() {
    setState(() {
      _logoBytes = null;
      _dirty = true;
    });
    // Persist removal only after Save; mark dirty so user confirms.
  }

  Future<void> _save() async {
    try {
      await BrandingStore.instance.save(
        companyName: _nameController.text,
        logoBytes: _logoBytes,
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      _toast(
        BrandingStore.instance.hasLogo
            ? 'Saved — logo will show in the PDF report header.'
            : 'Saved company name for PDF reports.',
        color: AppLux.teal,
      );
    } on StorageFullException catch (e) {
      if (!mounted) return;
      _toast(e.userMessage, color: Colors.orange.shade800);
    }
  }

  void _toast(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewName = _nameController.text.trim().isEmpty
        ? 'Your Company'
        : _nameController.text.trim();
    final bottom = MediaQuery.paddingOf(context).bottom;
    final radius = BorderRadius.circular(AppLux.radius2xl);

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: AppLux.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppLux.charcoal,
        title: Text(
          'PDF branding',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 19,
            letterSpacing: -0.4,
            color: AppLux.charcoal,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text(
                  'Logo and company name appear on PDF report headers — '
                  'calm, professional exports for homeowners and crews.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.6,
                    color: AppLux.body,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.05,
                  ),
                ),
                const SizedBox(height: 28),

                // 1) Logo
                Text(
                  'Company logo',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppLux.charcoal,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'PNG or JPG works best. Square logos look cleanest in the header.',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppLux.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _picking ? null : _pickLogo,
                    borderRadius: BorderRadius.circular(20),
                    splashColor: AppLux.teal.withValues(alpha: 0.06),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: AppLux.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _hasLogo
                              ? AppLux.teal.withValues(alpha: 0.35)
                              : AppLux.border,
                          width: _hasLogo ? 1.1 : 0.75,
                        ),
                        boxShadow: AppLux.cardShadow(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 32,
                          horizontal: 22,
                        ),
                        child: Column(
                          children: [
                            if (_hasLogo)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.memory(
                                  _logoBytes!,
                                  key: ValueKey(_logoBytes.hashCode),
                                  height: 120,
                                  fit: BoxFit.contain,
                                ),
                              )
                            else
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppLux.tealMist,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  _picking
                                      ? Icons.hourglass_top_rounded
                                      : Icons.add_photo_alternate_outlined,
                                  size: 26,
                                  color: AppLux.teal,
                                ),
                              ),
                            const SizedBox(height: 14),
                            Text(
                              _picking
                                  ? 'Opening gallery…'
                                  : _hasLogo
                                  ? 'Tap to change logo'
                                  : 'Tap to pick from gallery',
                              style: GoogleFonts.inter(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppLux.charcoal,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Shown in PDF report headers',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppLux.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _OutlineAction(
                        onPressed: _picking ? null : _pickLogo,
                        icon: Icons.photo_library_outlined,
                        label: _hasLogo ? 'Change logo' : 'Upload logo',
                      ),
                    ),
                    if (_hasLogo) ...[
                      const SizedBox(width: 10),
                      _OutlineAction(
                        onPressed: _removeLogo,
                        icon: Icons.close_rounded,
                        label: 'Remove',
                        destructive: true,
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 36),

                // 2) Company name
                Text(
                  'Company name',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppLux.charcoal,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Appears next to your logo on exported reports.',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppLux.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  cursorColor: AppLux.teal,
                  cursorWidth: 1.4,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppLux.charcoal,
                    letterSpacing: -0.1,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Atlanta Construction Pros',
                    hintStyle: GoogleFonts.inter(
                      color: AppLux.muted.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: AppLux.surface,
                    prefixIcon: const Icon(
                      Icons.business_rounded,
                      size: 20,
                      color: AppLux.icon,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 52,
                      minHeight: 56,
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(4, 20, 18, 20),
                    border: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: const BorderSide(
                        color: AppLux.borderSoft,
                        width: 0.7,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: const BorderSide(
                        color: AppLux.border,
                        width: 0.7,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: BorderSide(
                        color: AppLux.teal.withValues(alpha: 0.72),
                        width: 1.35,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // 3) PDF preview
                Text(
                  'Header preview',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppLux.charcoal,
                    letterSpacing: -0.4,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'How your brand will read at the top of a PDF export.',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppLux.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AppLux.card(radius: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppLux.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppLux.border,
                            width: 0.75,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _hasLogo
                            ? Image.memory(
                                _logoBytes!,
                                key: ValueKey('prev_${_logoBytes.hashCode}'),
                                fit: BoxFit.contain,
                              )
                            : const Icon(
                                Icons.image_outlined,
                                color: AppLux.icon,
                                size: 22,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              previewName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppLux.charcoal,
                                letterSpacing: -0.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _hasLogo
                                  ? 'Logo will appear in PDF header'
                                  : 'No logo yet — upload one above',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppLux.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppLux.tealMist,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppLux.teal.withValues(alpha: 0.14),
                            width: 0.75,
                          ),
                        ),
                        child: Text(
                          'PDF',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: AppLux.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sticky save
          Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottom),
            decoration: BoxDecoration(
              color: AppLux.surface.withValues(alpha: 0.97),
              border: Border(
                top: BorderSide(
                  color: AppLux.border.withValues(alpha: 0.75),
                  width: 0.55,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppLux.charcoal.withValues(alpha: 0.035),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: _SaveBrandingButton(dirty: _dirty, onPressed: _save),
          ),
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFB91C1C) : AppLux.charcoal;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: AppLux.surface,
        side: BorderSide(
          color: destructive ? color.withValues(alpha: 0.28) : AppLux.border,
          width: 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _SaveBrandingButton extends StatefulWidget {
  const _SaveBrandingButton({required this.dirty, required this.onPressed});

  final bool dirty;
  final VoidCallback onPressed;

  @override
  State<_SaveBrandingButton> createState() => _SaveBrandingButtonState();
}

class _SaveBrandingButtonState extends State<_SaveBrandingButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.dirty;

    return AnimatedScale(
      scale: _pressed && enabled ? 0.982 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: enabled
                ? [
                    Color.lerp(AppLux.teal, AppLux.tealBright, 0.28)!,
                    AppLux.teal,
                    Color.lerp(AppLux.teal, const Color(0xFF0A5C56), 0.25)!,
                  ]
                : [
                    AppLux.teal.withValues(alpha: 0.38),
                    AppLux.teal.withValues(alpha: 0.34),
                    AppLux.teal.withValues(alpha: 0.32),
                  ],
            stops: const [0.0, 0.55, 1.0],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppLux.teal.withValues(
                      alpha: _pressed ? 0.14 : 0.22,
                    ),
                    blurRadius: _pressed ? 16 : 28,
                    offset: Offset(0, _pressed ? 6 : 12),
                  ),
                  BoxShadow(
                    color: AppLux.charcoal.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white.withValues(alpha: 0.10),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: SizedBox(
              height: 56,
              width: double.infinity,
              child: Center(
                child: Text(
                  widget.dirty ? 'Save branding' : 'Saved',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: enabled ? 1 : 0.85),
                    letterSpacing: 0.2,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
