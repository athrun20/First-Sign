import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../legal/privacy_copy.dart';
import '../services/local_data_reset.dart';
import '../services/profile_store.dart';
import '../theme/app_lux.dart';
import '../widgets/onboarding_sheet.dart';

/// Homeowner profile for quote autofill — calm luxury, local-only.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  bool _dirty = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await ProfileStore.instance.ensureLoaded();
    final p = ProfileStore.instance;
    _name.text = p.name;
    _phone.text = p.phone;
    _email.text = p.email;
    _address.text = p.address;
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ProfileStore.instance.save(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      address: _address.text,
    );
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppLux.charcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppLux.radiusMd),
        ),
        content: Text(
          'Profile saved — used to autofill quote requests.',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _confirmWipeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete all First Sign data?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes reports, photos, leads, drafts, branding logo, '
          'finding feedback, and contact fields saved on this device. '
          'This cannot be undone.',
          style: GoogleFonts.inter(height: 1.45, color: AppLux.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppLux.danger),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await LocalDataReset.wipeAllOnDevice();
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _dirty = false);
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppLux.charcoal,
        content: Text(
          'All local First Sign data deleted on this device.',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (!_ready) {
      return Scaffold(
        backgroundColor: AppLux.bg,
        appBar: AppBar(
          backgroundColor: AppLux.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: AppLux.charcoal,
          title: Text(
            'Profile',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: AppLux.titleMd,
              letterSpacing: -0.2,
              color: AppLux.charcoal,
            ),
          ),
        ),
        body: Center(child: AppLux.loadingCard(label: 'Loading profile…')),
      );
    }

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: AppLux.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppLux.charcoal,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: AppLux.titleMd,
            letterSpacing: -0.2,
            color: AppLux.charcoal,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppLux.pagePaddingH,
                8,
                AppLux.pagePaddingH,
                28,
              ),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                Text(
                  PrivacyCopy.profileIntro,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.55,
                    color: AppLux.body,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.05,
                  ),
                ),
                const SizedBox(height: 20),

                // Privacy + tips as calm link cards
                _LinkCard(
                  icon: Icons.shield_outlined,
                  title: PrivacyCopy.title,
                  subtitle: PrivacyCopy.shortLine,
                  mist: true,
                  onTap: () => Navigator.of(context).pushNamed('/privacy'),
                ),
                const SizedBox(height: 12),
                _LinkCard(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'How First Sign works',
                  subtitle: 'Full Assessment vs Quick Scan — reopen anytime.',
                  mist: false,
                  onTap: () => showFirstSignOnboarding(context),
                ),

                const SizedBox(height: 28),
                AppLux.sectionHeader('Contact details'),
                const SizedBox(height: 6),
                Text(
                  'Saved only on this device. Autofills quote requests in First Sign.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.45,
                    color: AppLux.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  decoration: AppLux.card(radius: AppLux.radius3xl),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Column(
                    children: [
                      _ProfileField(
                        label: 'Full name',
                        controller: _name,
                        icon: Icons.person_outline_rounded,
                        onChanged: _markDirty,
                      ),
                      const _FieldDivider(),
                      _ProfileField(
                        label: 'Phone',
                        controller: _phone,
                        icon: Icons.phone_outlined,
                        keyboard: TextInputType.phone,
                        onChanged: _markDirty,
                      ),
                      const _FieldDivider(),
                      _ProfileField(
                        label: 'Email',
                        controller: _email,
                        icon: Icons.email_outlined,
                        keyboard: TextInputType.emailAddress,
                        onChanged: _markDirty,
                      ),
                      const _FieldDivider(),
                      _ProfileField(
                        label: 'Property address',
                        controller: _address,
                        icon: Icons.home_outlined,
                        maxLines: 2,
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: AppLux.goldNote(radius: AppLux.radiusXl),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: AppLux.gold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No account required. Clear these fields anytime — '
                          'nothing is uploaded until you request a quote.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: AppLux.disclaimerInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                AppLux.sectionHeader('Privacy'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _confirmWipeAll,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete all data on this device'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppLux.danger,
                    side: BorderSide(
                      color: AppLux.danger.withValues(alpha: 0.35),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppLux.radiusXl),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Removes reports, photos, leads, drafts, and feedback stored here. '
                  'Shared PDFs already sent cannot be recalled.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppLux.muted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              AppLux.pagePaddingH,
              14,
              AppLux.pagePaddingH,
              12 + bottom,
            ),
            decoration: BoxDecoration(
              color: AppLux.surface,
              border: Border(
                top: BorderSide(
                  color: AppLux.border.withValues(alpha: 0.95),
                  width: AppLux.borderWidth,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppLux.charcoal.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: FilledButton(
              onPressed: _dirty ? _save : null,
              style: AppLux.primaryButton(minHeight: 52),
              child: Text(
                _dirty ? 'Save profile' : 'Saved',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.mist,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool mist;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppLux.radius2xl),
        splashColor: AppLux.teal.withValues(alpha: 0.05),
        highlightColor: AppLux.teal.withValues(alpha: 0.02),
        child: Ink(
          decoration: mist
              ? AppLux.mistCard(radius: AppLux.radius2xl)
              : AppLux.card(radius: AppLux.radius2xl),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: mist
                        ? AppLux.surface.withValues(alpha: 0.7)
                        : AppLux.tealMist,
                    borderRadius: BorderRadius.circular(AppLux.radiusMd),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.14),
                      width: AppLux.borderWidth,
                    ),
                  ),
                  child: Icon(icon, size: 20, color: AppLux.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppLux.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppLux.icon.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: AppLux.borderWidth,
      color: AppLux.border.withValues(alpha: 0.9),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.onChanged,
    this.keyboard,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final VoidCallback onChanged;
  final TextInputType? keyboard;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppLux.muted,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            maxLines: maxLines,
            onChanged: (_) => onChanged(),
            cursorColor: AppLux.teal,
            cursorWidth: 1.4,
            style: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: AppLux.charcoal,
              height: 1.35,
              letterSpacing: -0.1,
            ),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(icon, size: 20, color: AppLux.icon),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              filled: true,
              fillColor: AppLux.cardFill,
              contentPadding: const EdgeInsets.fromLTRB(4, 14, 12, 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLux.radiusLg),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLux.radiusLg),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLux.radiusLg),
                borderSide: BorderSide(
                  color: AppLux.teal.withValues(alpha: 0.45),
                  width: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
