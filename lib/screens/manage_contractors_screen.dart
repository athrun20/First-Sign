import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/contractor_models.dart';
import '../services/contractor_store.dart';
import '../theme/app_lux.dart';

/// Owner-only invitee directory — add / edit local contractors.
///
/// Not homeowner-facing. Not wired into quote email routing yet.
class ManageContractorsScreen extends StatefulWidget {
  const ManageContractorsScreen({super.key});

  @override
  State<ManageContractorsScreen> createState() =>
      _ManageContractorsScreenState();
}

class _ManageContractorsScreenState extends State<ManageContractorsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ContractorStore.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
    ContractorStore.instance.addListener(_onStore);
  }

  @override
  void dispose() {
    ContractorStore.instance.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor({Contractor? contractor}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ContractorEditorScreen(contractor: contractor),
      ),
    );
    if (!mounted || saved != true) return;
    _toast(
      contractor == null ? 'Contractor saved' : 'Changes saved',
      color: AppLux.teal,
    );
  }

  Future<void> _toggleActive(Contractor c) async {
    final store = ContractorStore.instance;
    if (c.isActive) {
      await store.deactivate(c.id);
      if (!mounted) return;
      _toast('${c.displayName} deactivated');
    } else {
      await store.reactivate(c.id);
      if (!mounted) return;
      _toast('${c.displayName} reactivated', color: AppLux.teal);
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
    final store = ContractorStore.instance;
    final list = store.contractors;
    final activeCount = store.activeContractors.length;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppLux.bg,
      appBar: AppBar(
        backgroundColor: AppLux.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppLux.charcoal,
        title: Text(
          'Invite network',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 19,
            letterSpacing: -0.4,
            color: AppLux.charcoal,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        backgroundColor: AppLux.teal,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: Text(
          'Add contractor',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            letterSpacing: -0.1,
          ),
        ),
      ),
      body: store.isLoading && !store.isLoaded
          ? Center(child: AppLux.loadingCard(label: 'Loading contractors…'))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Owner tools — invite-only contractors stored on this '
                          'device. Matching is ready; quote routing is not wired yet.',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            height: 1.55,
                            color: AppLux.body,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.05,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                'Contractors',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppLux.charcoal,
                                  letterSpacing: -0.4,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            Text(
                              list.isEmpty
                                  ? 'None yet'
                                  : '$activeCount active · ${list.length} total',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppLux.muted,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (list.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 100 + bottom),
                      child: AppLux.emptyState(
                        icon: Icons.groups_2_outlined,
                        title: 'No contractors yet',
                        body:
                            'Add invite-only pros with trades and service areas. '
                            'They stay local until quote routing is enabled.',
                        action: FilledButton.icon(
                          onPressed: _openEditor,
                          style: AppLux.primaryButton(minHeight: 48),
                          icon: const Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 18,
                          ),
                          label: const Text('Add first contractor'),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 100 + bottom),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final c = list[i];
                        return Dismissible(
                          key: ValueKey('contractor_${c.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) async {
                            await _toggleActive(c);
                            // Never remove from list via dismiss — toggle only.
                            return false;
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 22),
                            decoration: BoxDecoration(
                              color: c.isActive
                                  ? AppLux.goldSoft
                                  : AppLux.tealMist,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              c.isActive ? 'Deactivate' : 'Reactivate',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: c.isActive ? AppLux.gold : AppLux.teal,
                              ),
                            ),
                          ),
                          child: _ContractorCard(
                            contractor: c,
                            onTap: () => _openEditor(contractor: c),
                            onToggleActive: () => _toggleActive(c),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── List card ───────────────────────────────────────────────────────────────

class _ContractorCard extends StatelessWidget {
  const _ContractorCard({
    required this.contractor,
    required this.onTap,
    required this.onToggleActive,
  });

  final Contractor contractor;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final c = contractor;
    final company = c.companyName?.trim() ?? '';
    final areas = c.isOpenServiceArea
        ? 'National / open'
        : c.serviceAreas.join(' · ');
    final trades = c.trades.isEmpty
        ? 'No trades'
        : c.trades.map(_tradeLabel).join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: AppLux.teal.withValues(alpha: 0.05),
        highlightColor: AppLux.teal.withValues(alpha: 0.02),
        child: Ink(
          decoration: AppLux.card(
            radius: 20,
          ).copyWith(color: c.isActive ? AppLux.surface : AppLux.cardFill),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              c.name.trim().isEmpty ? 'Unnamed' : c.name.trim(),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: -0.3,
                                color: AppLux.charcoal,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActiveBadge(active: c.isActive),
                        ],
                      ),
                      if (company.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          company,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppLux.body,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        trades,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppLux.tealDeep,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        areas,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppLux.muted,
                          height: 1.35,
                        ),
                      ),
                      if (c.phone.isNotEmpty || c.email.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (c.phone.isNotEmpty) c.phone,
                            if (c.email.isNotEmpty) c.email,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppLux.body,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  children: [
                    IconButton(
                      tooltip: c.isActive ? 'Deactivate' : 'Reactivate',
                      onPressed: onToggleActive,
                      style: IconButton.styleFrom(
                        foregroundColor: c.isActive
                            ? AppLux.muted
                            : AppLux.teal,
                      ),
                      icon: Icon(
                        c.isActive
                            ? Icons.toggle_on_rounded
                            : Icons.toggle_off_outlined,
                        size: 28,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: AppLux.icon.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppLux.tealMist : const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? AppLux.teal.withValues(alpha: 0.22) : AppLux.border,
          width: 0.75,
        ),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: active ? AppLux.teal : AppLux.muted,
        ),
      ),
    );
  }
}

// ── Add / Edit form ─────────────────────────────────────────────────────────

/// Full-screen add or edit form for a single invitee.
class ContractorEditorScreen extends StatefulWidget {
  const ContractorEditorScreen({super.key, this.contractor});

  /// Null = create new.
  final Contractor? contractor;

  @override
  State<ContractorEditorScreen> createState() => _ContractorEditorScreenState();
}

class _ContractorEditorScreenState extends State<ContractorEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _notes;
  late final TextEditingController _areaInput;

  late Set<String> _trades;
  late List<String> _serviceAreas;
  late bool _isActive;
  late bool _national;
  bool _saving = false;

  bool get _isEdit => widget.contractor != null;

  @override
  void initState() {
    super.initState();
    final c = widget.contractor;
    _name = TextEditingController(text: c?.name ?? '');
    _company = TextEditingController(text: c?.companyName ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _areaInput = TextEditingController();
    _trades = {...?c?.trades.map(ContractorTrade.normalize)};
    _serviceAreas = [...?c?.serviceAreas];
    _isActive = c?.isActive ?? true;
    _national = c?.isOpenServiceArea ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    _areaInput.dispose();
    super.dispose();
  }

  void _toggleTrade(String trade) {
    setState(() {
      if (_trades.contains(trade)) {
        _trades.remove(trade);
      } else {
        _trades.add(trade);
      }
    });
  }

  void _setNational(bool value) {
    setState(() {
      _national = value;
      if (value) _serviceAreas = [];
    });
  }

  void _addAreaFromInput() {
    final raw = _areaInput.text.trim();
    if (raw.isEmpty) return;
    final parts = raw
        .split(RegExp('[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    setState(() {
      _national = false;
      for (final p in parts) {
        final exists = _serviceAreas.any(
          (a) => a.toLowerCase() == p.toLowerCase(),
        );
        if (!exists) _serviceAreas.add(p);
      }
      _areaInput.clear();
    });
  }

  void _removeArea(String area) {
    setState(() {
      _serviceAreas.remove(area);
      if (_serviceAreas.isEmpty) _national = true;
    });
  }

  String? _validate() {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Name is required.';
    if (_trades.isEmpty) return 'Select at least one trade.';
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    if (phone.isEmpty && email.isEmpty) {
      return 'Add a phone number or email.';
    }
    if (email.isNotEmpty && !_looksLikeEmail(email)) {
      return 'Email does not look valid.';
    }
    return null;
  }

  bool _looksLikeEmail(String value) {
    return RegExp('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+\$').hasMatch(value);
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      _toast(err, color: AppLux.danger);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // Empty area list always means national/open in the matching layer.
      final areas = (_national || _serviceAreas.isEmpty)
          ? <String>[]
          : List<String>.from(_serviceAreas);
      final trades = _trades.toList()
        ..sort(
          (a, b) => ContractorTrade.all
              .indexOf(a)
              .compareTo(ContractorTrade.all.indexOf(b)),
        );

      if (_isEdit) {
        final existing = widget.contractor!;
        final updated = existing.copyWith(
          name: _name.text.trim(),
          companyName: _company.text.trim(),
          clearCompanyName: _company.text.trim().isEmpty,
          trades: trades,
          serviceAreas: areas,
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          notes: _notes.text.trim(),
          clearNotes: _notes.text.trim().isEmpty,
          isActive: _isActive,
        );
        await ContractorStore.instance.update(updated);
      } else {
        final created = Contractor.create(
          name: _name.text.trim(),
          companyName: _company.text.trim(),
          trades: trades,
          serviceAreas: areas,
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          notes: _notes.text.trim(),
          isActive: _isActive,
        );
        await ContractorStore.instance.add(created);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      // Toast on parent is fine; also show here briefly if still mounted after pop fails.
    } catch (e) {
      if (mounted) _toast('Could not save: $e', color: AppLux.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
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
          _isEdit ? 'Edit contractor' : 'Add contractor',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 19,
            letterSpacing: -0.4,
            color: AppLux.charcoal,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: AppLux.body,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 32 + bottom),
          children: [
            Text(
              _isEdit
                  ? 'Update this invitee. Changes stay on this device only.'
                  : 'Add an invite-only pro. Required: name, trade(s), and phone or email.',
              style: GoogleFonts.inter(
                fontSize: 15,
                height: 1.55,
                color: AppLux.body,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 28),

            const _FieldLabel('Name', required: true),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              cursorColor: AppLux.teal,
              style: _fieldStyle(),
              decoration: _fieldDecoration(radius, hint: 'Contact name'),
            ),
            const SizedBox(height: 18),

            const _FieldLabel('Company name'),
            const SizedBox(height: 8),
            TextField(
              controller: _company,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              cursorColor: AppLux.teal,
              style: _fieldStyle(),
              decoration: _fieldDecoration(
                radius,
                hint: 'Optional DBA / company',
              ),
            ),
            const SizedBox(height: 24),

            const _FieldLabel('Trades', required: true),
            const SizedBox(height: 6),
            Text(
              'Select every specialty this invitee covers.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppLux.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final trade in ContractorTrade.all)
                  _TradeChip(
                    label: _tradeLabel(trade),
                    selected: _trades.contains(trade),
                    onTap: () => _toggleTrade(trade),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            const _FieldLabel('Service areas'),
            const SizedBox(height: 6),
            Text(
              'Cities, ZIPs, or metros. Leave national for open / fallback coverage.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppLux.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            _NationalToggle(national: _national, onChanged: _setNational),
            if (!_national) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _areaInput,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      cursorColor: AppLux.teal,
                      style: _fieldStyle(),
                      onSubmitted: (_) => _addAreaFromInput(),
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\n')),
                      ],
                      decoration: _fieldDecoration(
                        radius,
                        hint: 'e.g. Atlanta, 30301',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _addAreaFromInput,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppLux.teal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppLux.radiusXl),
                      ),
                    ),
                    child: Text(
                      'Add',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (_serviceAreas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final area in _serviceAreas)
                      InputChip(
                        label: Text(
                          area,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppLux.charcoal,
                          ),
                        ),
                        onDeleted: () => _removeArea(area),
                        deleteIconColor: AppLux.muted,
                        backgroundColor: AppLux.surface,
                        side: const BorderSide(
                          color: AppLux.border,
                          width: 0.75,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 24),

            const _FieldLabel('Phone'),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              cursorColor: AppLux.teal,
              style: _fieldStyle(),
              decoration: _fieldDecoration(radius, hint: 'Mobile or office'),
            ),
            const SizedBox(height: 18),

            const _FieldLabel('Email'),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              cursorColor: AppLux.teal,
              style: _fieldStyle(),
              decoration: _fieldDecoration(radius, hint: 'quotes@company.com'),
            ),
            const SizedBox(height: 6),
            Text(
              'Phone or email is required.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: AppLux.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),

            const _FieldLabel('Notes'),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppLux.teal,
              style: _fieldStyle(),
              decoration: _fieldDecoration(
                radius,
                hint: 'Optional — invite batch, referral source…',
              ),
            ),
            const SizedBox(height: 22),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: AppLux.card(radius: 16),
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Active in network',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppLux.charcoal,
                    ),
                  ),
                  subtitle: Text(
                    _isActive
                        ? 'Eligible for future lead matching'
                        : 'Hidden from matching until reactivated',
                    style: GoogleFonts.inter(fontSize: 13, color: AppLux.muted),
                  ),
                  value: _isActive,
                  activeThumbColor: AppLux.teal,
                  activeTrackColor: AppLux.teal.withValues(alpha: 0.35),
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _saving ? null : _save,
              style: AppLux.primaryButton(minHeight: 54),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isEdit ? 'Save changes' : 'Save contractor',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              style: AppLux.secondaryButton(minHeight: 48),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _fieldStyle() => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppLux.charcoal,
    letterSpacing: -0.1,
  );

  InputDecoration _fieldDecoration(
    BorderRadius radius, {
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: AppLux.muted.withValues(alpha: 0.9),
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: AppLux.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppLux.borderSoft, width: 0.7),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppLux.border, width: 0.7),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: AppLux.teal.withValues(alpha: 0.72),
          width: 1.35,
        ),
      ),
    );
  }
}

// ── Form bits ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppLux.charcoal,
              letterSpacing: -0.2,
            ),
          ),
          if (required)
            TextSpan(
              text: '  required',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppLux.muted,
                letterSpacing: 0.1,
              ),
            ),
        ],
      ),
    );
  }
}

class _TradeChip extends StatelessWidget {
  const _TradeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppLux.teal : AppLux.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppLux.teal.withValues(alpha: 0.9)
                  : AppLux.border,
              width: 0.75,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppLux.teal.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : AppLux.cardShadow(intensity: 0.4),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppLux.body,
              letterSpacing: 0.05,
            ),
          ),
        ),
      ),
    );
  }
}

class _NationalToggle extends StatelessWidget {
  const _NationalToggle({required this.national, required this.onChanged});

  final bool national;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppLux.card(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _AreaModeRow(
            selected: national,
            title: 'National / open',
            subtitle: 'Empty service areas — matches any property (fallback)',
            onTap: () => onChanged(true),
          ),
          const Divider(height: 1, color: AppLux.borderSoft),
          _AreaModeRow(
            selected: !national,
            title: 'Specific cities / ZIPs',
            subtitle: 'Only match when property address overlaps',
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _AreaModeRow extends StatelessWidget {
  const _AreaModeRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppLux.tealMist.withValues(alpha: 0.55)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 22,
                color: selected ? AppLux.teal : AppLux.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: AppLux.charcoal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppLux.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tradeLabel(String trade) {
  switch (ContractorTrade.normalize(trade)) {
    case ContractorTrade.roofing:
      return 'Roofing';
    case ContractorTrade.siding:
      return 'Siding';
    case ContractorTrade.gutters:
      return 'Gutters';
    case ContractorTrade.foundation:
      return 'Foundation';
    case ContractorTrade.paint:
      return 'Paint';
    case ContractorTrade.windows:
      return 'Windows';
    case ContractorTrade.fascia:
      return 'Fascia / trim';
    case ContractorTrade.general:
      return 'General';
    default:
      if (trade.isEmpty) return trade;
      return trade[0].toUpperCase() + trade.substring(1);
  }
}
