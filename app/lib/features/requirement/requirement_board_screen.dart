// app/lib/features/requirement/requirement_board_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/signed_photo.dart';
import 'models/requirement.dart';
import 'requirement_formatting.dart';
import 'requirement_providers.dart';

/// Browse all open requirements across negotiators -- same shape as
/// MarketplaceScreen, but for requirement criteria instead of listings.
class RequirementBoardScreen extends ConsumerStatefulWidget {
  const RequirementBoardScreen({super.key});

  @override
  ConsumerState<RequirementBoardScreen> createState() => _RequirementBoardScreenState();
}

class _RequirementBoardScreenState extends ConsumerState<RequirementBoardScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Requirement> _filter(List<Requirement> requirements) {
    if (_query.trim().isEmpty) return requirements;
    final q = _query.toLowerCase();
    return requirements
        .where((r) => r.area.toLowerCase().contains(q) || r.state.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final requirementsAsync = ref.watch(boardRequirementsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('requirement_board_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'requirement_board_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: requirementsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
              data: (requirements) {
                final filtered = _filter(requirements);
                if (filtered.isEmpty) {
                  return Center(child: Text('requirement_board_empty'.tr()));
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(boardRequirementsProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final requirement = filtered[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (requirement.photoUrls.isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: SignedPhoto(
                                        path: requirement.photoUrls.first,
                                        signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        RequirementFormatting.formatBudgetRange(
                                          requirement.budgetMin,
                                          requirement.budgetMax,
                                          requirement.transactionType,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: AppColors.ink),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                                        '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (requirement.bedrooms != null) ...[
                                            const Icon(Icons.bed, size: 16),
                                            const SizedBox(width: 4),
                                            Text('${requirement.bedrooms}'),
                                            const SizedBox(width: 12),
                                          ],
                                          Flexible(
                                            child: Text(
                                              requirement.area,
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Builder(builder: (context) {
                                        final ownerAsync =
                                            ref.watch(requirementOwnerProvider(requirement.negotiatorId));
                                        return ownerAsync.when(
                                          loading: () => const SizedBox.shrink(),
                                          error: (error, stack) => const SizedBox.shrink(),
                                          data: (owner) => Text(
                                            '${owner.fullName} (REN: ${owner.renNumber})',
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
