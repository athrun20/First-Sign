import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/lead_models.dart';
import '../services/lead_store.dart';
import '../theme/app_lux.dart';
import 'branding_screen.dart';
import 'lead_detail_screen.dart';
import 'manage_contractors_screen.dart';

/// Contractor luxury tokens — aliases of [AppLux].
abstract final class _ProLux {
  static const bg = AppLux.bg;
  static const surface = AppLux.surface;
  static const border = AppLux.border;
  static const borderSoft = AppLux.borderSoft;
  static const charcoal = AppLux.charcoal;
  static const body = AppLux.body;
  static const muted = AppLux.muted;
  static const icon = AppLux.icon;
  static const teal = AppLux.teal;
  static const tealMist = AppLux.tealMist;
  static const gold = AppLux.gold;
  static const goldSoft = AppLux.goldSoft;

  static List<BoxShadow> cardShadow({double intensity = 1}) =>
      AppLux.cardShadow(intensity: intensity);

  static BoxDecoration card({double radius = AppLux.radius3xl}) =>
      AppLux.card(radius: radius);
}

/// Local contractor pipeline: list leads, filter by status, open detail.
class ContractorDashboardScreen extends StatefulWidget {
  const ContractorDashboardScreen({super.key});

  @override
  State<ContractorDashboardScreen> createState() =>
      _ContractorDashboardScreenState();
}

class _ContractorDashboardScreenState extends State<ContractorDashboardScreen> {
  String _status = 'All';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    LeadStore.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    LeadStore.instance.addListener(_onStore);
  }

  @override
  void dispose() {
    LeadStore.instance.removeListener(_onStore);
    _search.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  List<QuoteLead> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return LeadStore.instance.leads.where((l) {
      if (_status != 'All' && l.status != _status) return false;
      if (q.isEmpty) return true;
      final blob =
          '${l.name} ${l.phone} ${l.email} ${l.address} ${l.homeownerNotes} ${l.contractorNotes}'
              .toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  void _openBranding() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BrandingScreen()));
  }

  void _openManageContractors() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ManageContractorsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = LeadStore.instance;
    final leads = store.leads;
    final filtered = _filtered;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _ProLux.bg,
      appBar: AppBar(
        backgroundColor: _ProLux.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _ProLux.charcoal,
        title: Text(
          'Pro tools',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 19,
            letterSpacing: -0.4,
            color: _ProLux.charcoal,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Invitee contractors',
            onPressed: _openManageContractors,
            style: IconButton.styleFrom(
              foregroundColor: _ProLux.charcoal,
              backgroundColor: _ProLux.surface,
              side: const BorderSide(color: _ProLux.border, width: 0.75),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.groups_outlined, size: 20),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'PDF branding',
              onPressed: _openBranding,
              style: IconButton.styleFrom(
                foregroundColor: _ProLux.charcoal,
                backgroundColor: _ProLux.surface,
                side: const BorderSide(color: _ProLux.border, width: 0.75),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.palette_outlined, size: 20),
            ),
          ),
        ],
      ),
      body: store.isLoading && !store.isLoaded
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: _ProLux.teal,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      // Header + tools
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Leads & branding for contractor follow-up. '
                                'Everything stays on this device.',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  height: 1.6,
                                  color: _ProLux.body,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.05,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _BrandingAccessCard(onTap: _openBranding),
                              const SizedBox(height: 32),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Quote leads',
                                      style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: _ProLux.charcoal,
                                        letterSpacing: -0.4,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    leads.isEmpty
                                        ? 'None yet'
                                        : '${leads.length} total · ${filtered.length} shown',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _ProLux.muted,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _SearchField(
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 14),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final s in ['All', ...LeadStatus.all])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: _StatusChip(
                                          label: s == 'All'
                                              ? 'All (${store.countForStatus('All')})'
                                              : '$s (${store.countForStatus(s)})',
                                          selected: _status == s,
                                          onTap: () =>
                                              setState(() => _status = s),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),

                      // Empty or lead list
                      if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
                            child: _EmptyState(hasAnyLeads: leads.isNotEmpty),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(24, 0, 24, 28 + bottom),
                          sliver: SliverList.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final lead = filtered[i];
                              return _LeadCard(
                                lead: lead,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          LeadDetailScreen(leadId: lead.id),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Branding access ─────────────────────────────────────────────────────────

class _BrandingAccessCard extends StatelessWidget {
  const _BrandingAccessCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: _ProLux.teal.withValues(alpha: 0.06),
        highlightColor: _ProLux.teal.withValues(alpha: 0.03),
        child: Ink(
          decoration: _ProLux.card(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _ProLux.tealMist,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _ProLux.teal.withValues(alpha: 0.12),
                      width: 0.75,
                    ),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 22,
                    color: _ProLux.teal,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PDF branding',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _ProLux.charcoal,
                          letterSpacing: -0.25,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Logo & company name on report exports',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: _ProLux.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: _ProLux.icon.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Search ──────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      cursorColor: _ProLux.teal,
      cursorWidth: 1.4,
      style: GoogleFonts.inter(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: _ProLux.charcoal,
        letterSpacing: -0.1,
      ),
      decoration: InputDecoration(
        hintText: 'Search name, address, or notes…',
        hintStyle: GoogleFonts.inter(
          color: _ProLux.muted.withValues(alpha: 0.9),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: _ProLux.icon,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 50,
        ),
        filled: true,
        fillColor: _ProLux.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: _ProLux.borderSoft, width: 0.7),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: _ProLux.border, width: 0.7),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: _ProLux.teal.withValues(alpha: 0.72),
            width: 1.35,
          ),
        ),
      ),
    );
  }
}

// ── Status filter chips ─────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _ProLux.teal : _ProLux.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? _ProLux.teal.withValues(alpha: 0.9)
                  : _ProLux.border,
              width: 0.75,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _ProLux.teal.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : _ProLux.cardShadow(intensity: 0.5),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05,
              color: selected ? Colors.white : _ProLux.body,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Lead card ───────────────────────────────────────────────────────────────

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, required this.onTap});

  final QuoteLead lead;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (lead.status) {
      case LeadStatus.won:
        return _ProLux.teal;
      case LeadStatus.quoted:
        return _ProLux.gold;
      case LeadStatus.contacted:
        return const Color(0xFF0369A1);
      default:
        return _ProLux.charcoal;
    }
  }

  Color get _statusBg {
    switch (lead.status) {
      case LeadStatus.won:
        return _ProLux.tealMist;
      case LeadStatus.quoted:
        return _ProLux.goldSoft;
      case LeadStatus.contacted:
        return const Color(0xFFF0F9FF);
      default:
        return const Color(0xFFF5F5F4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = lead.name.isEmpty ? 'Unnamed lead' : lead.name;
    final address = lead.address.isEmpty ? 'No address' : lead.address;
    final phone = lead.phone.isEmpty ? 'No phone' : lead.phone;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: _ProLux.teal.withValues(alpha: 0.05),
        highlightColor: _ProLux.teal.withValues(alpha: 0.02),
        child: Ink(
          decoration: _ProLux.card(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: -0.3,
                          color: _ProLux.charcoal,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _statusColor.withValues(alpha: 0.14),
                          width: 0.75,
                        ),
                      ),
                      child: Text(
                        lead.status,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.15,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  address,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.4,
                    color: _ProLux.body,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$phone · ${lead.relativeDateLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.35,
                    color: _ProLux.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _ProLux.bg.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _ProLux.border.withValues(alpha: 0.7),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    children: [
                      _MetricPill(
                        icon: Icons.speed_rounded,
                        label: 'Score ${lead.overallScore}',
                      ),
                      _MetricDot(),
                      _MetricPill(
                        icon: Icons.list_alt_rounded,
                        label:
                            '${lead.findingsCount} finding${lead.findingsCount == 1 ? '' : 's'}',
                      ),
                      _MetricDot(),
                      Flexible(
                        child: Text(
                          lead.severitySummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _ProLux.teal,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _ProLux.icon),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _ProLux.charcoal,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _MetricDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: _ProLux.muted.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAnyLeads});

  final bool hasAnyLeads;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        decoration: _ProLux.card(radius: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _ProLux.tealMist,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                hasAnyLeads
                    ? Icons.filter_list_off_rounded
                    : Icons.inbox_outlined,
                size: 26,
                color: _ProLux.teal,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasAnyLeads ? 'No matches' : 'No leads yet',
              style: GoogleFonts.inter(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: _ProLux.charcoal,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasAnyLeads
                  ? 'Try another status filter or clear the search.'
                  : 'When homeowners request a quote, leads appear here for follow-up.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.55,
                color: _ProLux.body,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
