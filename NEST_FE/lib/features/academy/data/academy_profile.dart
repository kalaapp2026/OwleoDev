/// A trainer (or Academy Admin, who can also teach) shown on a highlight card and its detail
/// view.
class HighlightTrainer {
  final String membershipId;
  final String fullName;
  final String? profileImageUrl;

  const HighlightTrainer({required this.membershipId, required this.fullName, required this.profileImageUrl});

  factory HighlightTrainer.fromJson(Map<String, dynamic> json) => HighlightTrainer(
        membershipId: json['membershipId'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

/// A "what we teach" block - a photo carousel (can be several images), a description, and the
/// trainer(s) who teach it. Tapping the card opens the full detail.
class AcademyHighlight {
  final String id;
  final String title;
  final String? description;
  final List<String> imageUrls;
  final List<HighlightTrainer> trainers;

  const AcademyHighlight({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrls,
    required this.trainers,
  });

  factory AcademyHighlight.fromJson(Map<String, dynamic> json) => AcademyHighlight(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        imageUrls: List<String>.from(json['imageUrls'] as List? ?? const []),
        trainers: (json['trainers'] as List? ?? []).map((e) => HighlightTrainer.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class FeaturedTrainer {
  final String id;
  final String trainerMembershipId;
  final String fullName;
  final String? profileImageUrl;

  const FeaturedTrainer({required this.id, required this.trainerMembershipId, required this.fullName, required this.profileImageUrl});

  factory FeaturedTrainer.fromJson(Map<String, dynamic> json) => FeaturedTrainer(
        id: json['id'] as String,
        trainerMembershipId: json['trainerMembershipId'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

class AcademyBranchInfo {
  final String id;
  final String name;
  final String? address;

  const AcademyBranchInfo({required this.id, required this.name, required this.address});

  factory AcademyBranchInfo.fromJson(Map<String, dynamic> json) => AcademyBranchInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
      );
}

/// The academy's public About-Us page - a singleton per academy. Every field the Admin never
/// filled in comes back null; the read view simply doesn't render that row.
class AcademyProfile {
  final String id;
  final String name;
  final String? tagline;
  final String? logoUrl;
  final String? description;
  final String? establishedBy;
  final String? ownerName;
  final String? additionalInfo;
  final String? address;
  final String? city;
  final String? state;
  final String? contactNumber;
  final String? email;
  final String? instagramUrl;
  final String? xUrl;
  final String? facebookUrl;
  final String? youtubeUrl;
  final List<AcademyHighlight> highlights;
  final List<FeaturedTrainer> featuredTrainers;
  final List<AcademyBranchInfo> branches;

  const AcademyProfile({
    required this.id,
    required this.name,
    required this.tagline,
    required this.logoUrl,
    required this.description,
    required this.establishedBy,
    required this.ownerName,
    required this.additionalInfo,
    required this.address,
    required this.city,
    required this.state,
    required this.contactNumber,
    required this.email,
    required this.instagramUrl,
    required this.xUrl,
    required this.facebookUrl,
    required this.youtubeUrl,
    required this.highlights,
    required this.featuredTrainers,
    required this.branches,
  });

  factory AcademyProfile.fromJson(Map<String, dynamic> json) => AcademyProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        tagline: json['tagline'] as String?,
        logoUrl: json['logoUrl'] as String?,
        description: json['description'] as String?,
        establishedBy: json['establishedBy'] as String?,
        ownerName: json['ownerName'] as String?,
        additionalInfo: json['additionalInfo'] as String?,
        address: json['address'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        contactNumber: json['contactNumber'] as String?,
        email: json['email'] as String?,
        instagramUrl: json['instagramUrl'] as String?,
        xUrl: json['xUrl'] as String?,
        facebookUrl: json['facebookUrl'] as String?,
        youtubeUrl: json['youtubeUrl'] as String?,
        highlights: (json['highlights'] as List? ?? []).map((e) => AcademyHighlight.fromJson(e as Map<String, dynamic>)).toList(),
        featuredTrainers: (json['featuredTrainers'] as List? ?? []).map((e) => FeaturedTrainer.fromJson(e as Map<String, dynamic>)).toList(),
        branches: (json['branches'] as List? ?? []).map((e) => AcademyBranchInfo.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// The Admin's "pick a trainer to feature" source.
class TrainerCandidate {
  final String membershipId;
  final String fullName;
  final String? profileImageUrl;

  const TrainerCandidate({required this.membershipId, required this.fullName, required this.profileImageUrl});

  factory TrainerCandidate.fromJson(Map<String, dynamic> json) => TrainerCandidate(
        membershipId: json['membershipId'] as String,
        fullName: json['fullName'] as String,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}
