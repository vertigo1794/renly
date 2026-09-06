// app/lib/features/listing/listing_drafts_provider.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/listing_draft.dart';

/// Locally-saved in-progress Post Listing forms -- mirrors
/// conversation_list_screen.dart's _ArchivedConversations StateNotifier
/// pattern exactly (SharedPreferences-backed, loaded async at
/// construction). A draft never becomes a real Listing row until the
/// resumed form is actually submitted.
class ListingDraftsNotifier extends StateNotifier<List<ListingDraft>> {
  ListingDraftsNotifier() : super(const []) {
    _load();
  }

  static const _prefsKey = 'listing_drafts';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    state = raw.map((s) => ListingDraft.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  Future<void> add(ListingDraft draft) async {
    state = [...state, draft];
    await _persist();
  }

  Future<void> remove(String draftId) async {
    state = state.where((d) => d.draftId != draftId).toList();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.map((d) => jsonEncode(d.toJson())).toList());
  }
}

final listingDraftsProvider = StateNotifierProvider<ListingDraftsNotifier, List<ListingDraft>>((ref) {
  return ListingDraftsNotifier();
});
