import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';
import 'requirement_status_filter.dart';

/// Ports the my_inventory shape for requirements -- open/fulfilled/withdrawn
/// tabs instead of active/sold/withdrawn.
class MyRequirementsScreen extends ConsumerStatefulWidget {
  const MyRequirementsScreen({super.key});

  @override
  ConsumerState<MyRequirementsScreen> createState() => _MyRequirementsScreenState();
}

class _MyRequirementsScreenState extends ConsumerState<MyRequirementsScreen> {
  String _selectedStatus = 'open';

  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('requirement_my_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'open', label: Text('requirement_tab_open'.tr())),
                ButtonSegment(value: 'fulfilled', label: Text('requirement_tab_fulfilled'.tr())),
                ButtonSegment(value: 'withdrawn', label: Text('inventory_tab_withdrawn'.tr())),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (selection) => setState(() => _selectedStatus = selection.first),
            ),
          ),
          Expanded(
            // A null negotiatorId here is a brief startup race (the auth
            // redirect already guarantees a session reaches this route),
            // so it reads as "still loading", not as an error state.
            child: negotiatorId == null
                ? const Center(child: CircularProgressIndicator())
                : Consumer(
                    builder: (context, ref, _) {
                      final requirementsAsync = ref.watch(myRequirementsProvider(negotiatorId));
                      return requirementsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
                        data: (requirements) {
                          final filtered = RequirementStatusFilter.byStatus(requirements, _selectedStatus);
                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/illustrations/my_requirements_empty.png',
                                    height: 160,
                                    errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('requirement_my_empty'.tr()),
                                ],
                              ),
                            );
                          }
                          return RefreshIndicator(
                            onRefresh: () async =>
                                ref.invalidate(myRequirementsProvider(negotiatorId)),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final requirement = filtered[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                                      borderRadius: BorderRadius.circular(12),
                                      child: BrutalistCard(
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            RequirementFormatting.formatBudgetRange(
                                              requirement.budgetMin,
                                              requirement.budgetMax,
                                              requirement.transactionType,
                                            ),
                                          ),
                                          subtitle: Text('${requirement.area}, ${requirement.state}'),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: BrutalistButton(
              label: 'requirement_post_new'.tr(),
              onPressed: () => context.push('/post-requirement'),
            ),
          ),
        ],
      ),
    );
  }
}
