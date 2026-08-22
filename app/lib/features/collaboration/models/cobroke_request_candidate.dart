import '../../matching/models/match_candidate.dart';
import 'cobroke_request.dart';

/// A cobroke_request row joined with the MatchCandidate it's for -- reuses
/// the matching feature's view model directly rather than inventing a
/// second representation of "what does this match look like."
class CobrokeRequestCandidate {
  final CobrokeRequest request;
  final MatchCandidate match;

  const CobrokeRequestCandidate({required this.request, required this.match});
}
