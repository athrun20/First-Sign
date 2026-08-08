import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/lead_models.dart';
import '../services/lead_store.dart';
import '../theme/app_lux.dart';
import 'branding_screen.dart';
import 'lead_detail_screen.dart';
import 'manage_contractors_screen.dart';

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
    unawaited(
      LeadStore.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
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
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BrandingScreen()),
      ),
    );
  }

  void _openInviteNetwork() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ManageContractorsScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = LeadStore.instance;
    final leads = store.leads;
    final filtered = _filtered;
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
          'Pro tools',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 19,
            letterSpacing: -0.4,
            color: AppLux.charcoal,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'PDF branding',
              onPressed: _openBranding,
              style: IconButton.styleFrom(
                foregroundColor: AppLux.charcoal,
                backgroundColor: AppLux.surface,
                side: const BorderSide(color: AppLux.border, width: 0.75),
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
          ? Center(child: AppLux.loadingCard(label: 'Loading leads…'))
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
                                'FirstSign pro tools for contractor follow-up. '
                                'Leads and branding stay on this device.',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  height: 1.55,
                                  color: AppLux.body,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.05,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _BrandingAccessCard(onTap: _openBranding),
                              const SizedBox(height: 12),
                              _InviteNetworkAccessCard(
                                onTap: _openInviteNetwork,
                              ),
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
                                        color: AppLux.charcoal,
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
                                      color: AppLux.muted,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                              if (leads.isNotEmpty) ...[
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
                                      for (final s in [
                                        'All',
                                        ...LeadStatus.all,
                                      ])
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
                              ],
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),

                      // Empty or lead list
                      if (leads.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              0,
                              24,
                              32 + bottom,
                            ),
                            child: _ZeroLeadsState(
                              onOpenBranding: _openBranding,
                              onBackHome: () => Navigator.of(
                                context,
                              ).popUntil((r) => r.isFirst),
                            ),
                          ),
                        )
                      else if (filtered.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(24, 0, 24, 40),
                            child: _NoMatchState(),
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
                                  unawaited(
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            LeadDetailScreen(leadId: lead.id),
                                      ),
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
    return _ProToolAccessCard(
      onTap: onTap,
      icon: Icons.picture_as_pdf_outlined,
      title: 'PDF branding',
      subtitle: 'Logo & company name on report exports',
    );
  }
}

// ── Invite network (owner) ──────────────────────────────────────────────────

class _InviteNetworkAccessCard extends StatelessWidget {
  const _InviteNetworkAccessCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ProToolAccessCard(
      onTap: onTap,
      icon: Icons.groups_2_outlined,
      title: 'Invite network',
      subtitle: 'Add & manage contractors for future matching',
    );
  }
}

class _ProToolAccessCard extends StatelessWidget {
  const _ProToolAccessCard({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: AppLux.teal.withValues(alpha: 0.06),
        highlightColor: AppLux.teal.withValues(alpha: 0.03),
        child: Ink(
          decoration: AppLux.card(radius: 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppLux.tealMist,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppLux.teal.withValues(alpha: 0.12),
                      width: 0.75,
                    ),
                  ),
                  child: Icon(icon, size: 22, color: AppLux.teal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppLux.charcoal,
                          letterSpacing: -0.25,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: AppLux.muted,
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
                  color: AppLux.icon.withValues(alpha: 0.85),
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
      cursorColor: AppLux.teal,
      cursorWidth: 1.4,
      style: GoogleFonts.inter(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: AppLux.charcoal,
        letterSpacing: -0.1,
      ),
      decoration: InputDecoration(
        hintText: 'Search name, address, or notes…',
        hintStyle: GoogleFonts.inter(
          color: AppLux.muted.withValues(alpha: 0.9),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: AppLux.icon,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 50,
        ),
        filled: true,
        fillColor: AppLux.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
                      color: AppLux.teal.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : AppLux.cardShadow(intensity: 0.5),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05,
              color: selected ? Colors.white : AppLux.body,
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
        return AppLux.teal;
      case LeadStatus.quoted:
        return AppLux.gold;
      case LeadStatus.contacted:
        return const Color(0xFF0369A1);
      default:
        return AppLux.charcoal;
    }
  }

  Color get _statusBg {
    switch (lead.status) {
      case LeadStatus.won:
        return AppLux.tealMist;
      case LeadStatus.quoted:
        return AppLux.goldSoft;
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
        splashColor: AppLux.teal.withValues(alpha: 0.05),
        highlightColor: AppLux.teal.withValues(alpha: 0.02),
        child: Ink(
          decoration: AppLux.card(radius: 20),
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
                          color: AppLux.charcoal,
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
                    color: AppLux.body,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$phone · ${lead.relativeDateLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppLux.muted,
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
                    color: AppLux.bg.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppLux.border.withValues(alpha: 0.7),
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
                            color: AppLux.teal,
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
        Icon(icon, size: 14, color: AppLux.icon),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppLux.charcoal,
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
          color: AppLux.muted.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Empty states ────────────────────────────────────────────────────────────

/// Calm, intentional empty when no quote leads exist yet.
class _ZeroLeadsState extends StatelessWidget {
  const _ZeroLeadsState({
    required this.onOpenBranding,
    required this.onBackHome,
  });

  final VoidCallback onOpenBranding;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppLux.emptyState(
          icon: Icons.inbox_outlined,
          title: 'No leads yet',
          body:
              'When a homeowner finishes an assessment and requests a quote, '
              'their contact details and report summary land here — on this device only.',
          action: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onBackHome,
              style: AppLux.secondaryButton(minHeight: 48),
              child: Text(
                'Back to home',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: AppLux.card(radius: AppLux.radius3xl),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How leads arrive',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppLux.charcoal,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 14),
              const _HowLeadStep(
                number: '1',
                title: 'Assessment',
                body: 'Homeowner runs Full Assessment or Quick Scan.',
              ),
              const SizedBox(height: 12),
              const _HowLeadStep(
                number: '2',
                title: 'Request a quote',
                body: 'They share contact details from the report.',
              ),
              const SizedBox(height: 12),
              const _HowLeadStep(
                number: '3',
                title: 'Follow up here',
                body: 'Open the lead, add notes, and track status.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenBranding,
            borderRadius: BorderRadius.circular(AppLux.radius2xl),
            child: Ink(
              decoration: AppLux.goldNote(radius: AppLux.radius2xl),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.palette_outlined,
                      size: 20,
                      color: AppLux.gold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'While you wait',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppLux.disclaimerInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Add PDF branding so exports look professional.',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppLux.disclaimerInk.withValues(
                                alpha: 0.9,
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppLux.gold.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HowLeadStep extends StatelessWidget {
  const _HowLeadStep({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppLux.tealMist,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppLux.teal.withValues(alpha: 0.14),
              width: 0.75,
            ),
          ),
          child: Text(
            number,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppLux.teal,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppLux.charcoal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: AppLux.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    return AppLux.emptyState(
      icon: Icons.filter_list_off_rounded,
      title: 'No matches',
      body: 'Try another status filter or clear the search to see all leads.',
    );
  }
}
