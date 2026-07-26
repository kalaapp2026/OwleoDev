import 'package:nest_fe/core/auth/feature_keys.dart';
import 'package:nest_fe/core/auth/user_profile.dart';

/// Mirrors PostService.resolveAuthorOrThrow exactly (PRD 3.13 "who can post"): Super Admin and
/// Artist always; Academy Admin always; a Trainer only with ARTIST_STYLE_POSTING; Student and
/// Guest never. Used purely to decide whether to SHOW the compose/upload button - the backend is
/// still the real gate, this is just so the button doesn't appear for someone who'd be rejected.
bool userCanPost(UserProfile? user) {
  if (user == null) return false;
  if (user.isSuperAdmin || user.isArtist) return true;
  final membership = user.activeMembership;
  if (membership == null) return false;
  if (membership.isAcademyAdmin) return true;
  return membership.roleType == 'TRAINER' && membership.hasFeature(FeatureKeys.artistStylePosting);
}
