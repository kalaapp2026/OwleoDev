import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nest_fe/features/academy/data/academy_profile.dart';
import 'package:nest_fe/features/academy/presentation/academy_profile_shared.dart';

AcademyProfile _profile({String? logoUrl, Set<String> hidden = const {}, String? coverStyle}) => AcademyProfile.fromJson({
      'id': 'a1',
      'name': 'Owleo Academy',
      'tagline': 'Where every art form finds its stage',
      'logoUrl': logoUrl,
      'address': '24 Residency Road',
      'city': 'Bengaluru',
      'state': 'Karnataka',
      'pinCode': '560038',
      'contactNumber': '9845011223',
      'instagramUrl': 'instagram.com/owleo',
      'coverStyle': coverStyle,
      'hiddenLinks': hidden.toList(),
      'featuredTrainers': [
        {'id': 'f1', 'trainerMembershipId': 'm1', 'fullName': 'Meera Krishnan', 'designation': 'Head of Dance'},
      ],
    });

void main() {
  group('ProfileDraft', () {
    test('a fresh draft is not dirty, even with unset presets', () {
      final published = _profile();
      expect(ProfileDraft.from(published).isDirtyAgainst(published), isFalse);
    });

    test('editing any field, a designation, or the trainer list makes it dirty', () {
      final published = _profile();
      expect((ProfileDraft.from(published)..tagline = 'New').isDirtyAgainst(published), isTrue);
      expect((ProfileDraft.from(published)..featured.first.designation = 'Founder').isDirtyAgainst(published), isTrue);
      expect((ProfileDraft.from(published)..featured.clear()).isDirtyAgainst(published), isTrue);
      expect((ProfileDraft.from(published)..newCoverBytes = Uint8List(1)).isDirtyAgainst(published), isTrue);
    });

    test('hiding a link keeps its URL and sends it as hidden', () {
      final published = _profile();
      final draft = ProfileDraft.from(published)..hiddenLinks.add('instagram');
      final body = draft.toBody(published: published);
      expect(body['instagramUrl'], 'instagram.com/owleo');
      expect(body['hiddenLinks'], ['instagram']);
      expect(draft.linkVisible('instagram'), isFalse);
    });

    test('removing a published logo is sent as removeLogo, but not when a new one replaces it', () {
      final published = _profile(logoUrl: '/files/logo.png');
      final removed = ProfileDraft.from(published)..logoUrl = null;
      expect(removed.toBody(published: published)['removeLogo'], isTrue);
      expect(removed.isDirtyAgainst(published), isTrue);

      final replaced = ProfileDraft.from(published)
        ..logoUrl = null
        ..newLogoBytes = Uint8List(1);
      expect(replaced.toBody(published: published)['removeLogo'], isFalse);
    });

    test('featured trainers are sent in order with their designation', () {
      final published = _profile();
      final draft = ProfileDraft.from(published)..featured.add(DraftTrainer(membershipId: 'm2', fullName: 'Arjun Nair'));
      expect(draft.toBody(published: published)['featuredTrainers'], [
        {'trainerMembershipId': 'm1', 'designation': 'Head of Dance'},
        {'trainerMembershipId': 'm2', 'designation': null},
      ]);
    });

    test('validation blocks a missing name, a bad pin code and a short phone', () {
      final published = _profile();
      expect(ProfileDraft.from(published).validationError(), isNull);
      expect((ProfileDraft.from(published)..name = ' ').validationError(), isNotNull);
      expect((ProfileDraft.from(published)..pinCode = '5600').validationError(), isNotNull);
      expect((ProfileDraft.from(published)..contactNumber = '98450').validationError(), isNotNull);
    });

    test('an unknown cover style falls back to the first preset', () {
      expect(ProfileDraft.from(_profile(coverStyle: 'nonsense')).coverStyle, coverPresets.first.key);
    });
  });

  test('a bare 10-digit number dials and chats as Indian', () {
    expect(telUri('98450 11223').toString(), 'tel:+919845011223');
    expect(whatsappUri('9845011223').toString(), 'https://wa.me/919845011223');
    expect(webUri('instagram.com/owleo').toString(), 'https://instagram.com/owleo');
  });
}
