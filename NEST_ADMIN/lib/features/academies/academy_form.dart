import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/json.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/sections.dart';
import 'academy_meta.dart';

final _email = RegExp(r'^\S+@\S+\.\S+$');
final _mobile = RegExp(r'^[6-9]\d{9}$');

/// The details of an academy that both "Add academy" and "Edit academy" collect: who it is, where
/// it is, and who owns it. One object holds the controllers and the validation, so the two screens
/// can never disagree about what a valid academy looks like.
class AcademyFormData extends ChangeNotifier {
  AcademyFormData({Map<String, dynamic>? from}) {
    if (from != null) {
      name.text = from.str('name');
      type = from.strOrNull('type') ?? 'Dance';
      owner.text = from.str('owner');
      for (final e in {
        'aemail': aemail, 'aphone': aphone, 'a1': a1, 'a2': a2, 'landmark': landmark, 'city': city,
        'district': district, 'state': state, 'country': country, 'pin': pin, 'ophone': ophone, 'oemail': oemail,
      }.entries) {
        e.value.text = from.str(e.key);
      }
    }
    if (country.text.isEmpty) country.text = 'India';
    for (final c in all) {
      c.addListener(notifyListeners);
    }
  }

  final name = TextEditingController();
  final aemail = TextEditingController();
  final aphone = TextEditingController();
  final a1 = TextEditingController();
  final a2 = TextEditingController();
  final landmark = TextEditingController();
  final city = TextEditingController();
  final district = TextEditingController();
  final state = TextEditingController();
  final country = TextEditingController();
  final pin = TextEditingController();
  final owner = TextEditingController();
  final ophone = TextEditingController();
  final oemail = TextEditingController();
  String type = 'Dance';

  List<TextEditingController> get all =>
      [name, aemail, aphone, a1, a2, landmark, city, district, state, country, pin, owner, ophone, oemail];

  void setType(String t) {
    type = t;
    notifyListeners();
  }

  /// Every problem, as (section, message), in the order the sections appear.
  ///
  /// A [preLead] is an academy HQ has only heard of: just its own details, no owner. It needs a name, a
  /// city and state and one way to reach it; the rest of the address is optional, but must be right when
  /// given. The server applies the same rules (PreLeadRules).
  List<(String, String)> issues({bool preLead = false}) {
    final out = <(String, String)>[];
    if (preLead) {
      final email = aemail.text.trim(), phone = aphone.text.trim(), line1 = a1.text.trim(), code = pin.text.trim();
      if (name.text.trim().length < 3) out.add(('details', 'Enter the academy name.'));
      if (email.isEmpty && phone.isEmpty) out.add(('details', "Add the academy's phone or email so the team can reach them."));
      if (email.isNotEmpty && !_email.hasMatch(email)) out.add(('details', 'Enter a valid academy email address.'));
      if (phone.isNotEmpty && !_mobile.hasMatch(phone)) out.add(('details', 'Enter the academy phone as a 10-digit mobile number.'));
      if (line1.isNotEmpty && line1.length < 3) out.add(('address', 'Address line 1 needs a house number and street, or leave it empty.'));
      if (city.text.trim().length < 2) out.add(('address', 'Enter the city.'));
      if (state.text.trim().length < 2) out.add(('address', 'Enter the state.'));
      if (code.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(code)) out.add(('address', 'Enter a 6-digit PIN code, or leave it empty.'));
      return out;
    }
    if (name.text.trim().length < 3) out.add(('details', 'Enter the academy name.'));
    if (!_email.hasMatch(aemail.text.trim())) out.add(('details', 'Enter a valid academy email address.'));
    if (!_mobile.hasMatch(aphone.text.trim())) out.add(('details', 'Enter the academy phone as a 10-digit mobile number.'));
    if (a1.text.trim().length < 3) out.add(('address', 'Enter address line 1: house number and street.'));
    if (city.text.trim().length < 2) out.add(('address', 'Enter the city.'));
    if (state.text.trim().length < 2) out.add(('address', 'Enter the state.'));
    if (!RegExp(r'^\d{6}$').hasMatch(pin.text.trim())) out.add(('address', 'Enter a 6-digit PIN code.'));
    if (owner.text.trim().length < 2) out.add(('owner', 'Enter the owner\'s name.'));
    if (!_mobile.hasMatch(ophone.text.trim())) out.add(('owner', 'Enter the owner\'s 10-digit mobile number.'));
    if (!_email.hasMatch(oemail.text.trim())) out.add(('owner', 'Enter a valid owner email address.'));
    return out;
  }

  Map<String, dynamic> toJson() => {
        'name': name.text.trim(),
        'type': type,
        'owner': owner.text.trim(),
        'aemail': aemail.text.trim(),
        'aphone': aphone.text.trim(),
        'a1': a1.text.trim(),
        'a2': a2.text.trim(),
        'landmark': landmark.text.trim(),
        'city': city.text.trim(),
        'district': district.text.trim(),
        'state': state.text.trim(),
        'country': country.text.trim(),
        'pin': pin.text.trim(),
        'ophone': ophone.text.trim(),
        'oemail': oemail.text.trim(),
      };

  String get addressLine => [a1, a2, landmark, city, district, state, pin].map((c) => c.text.trim()).where((s) => s.isNotEmpty).join(', ');

  @override
  void dispose() {
    for (final c in all) {
      c.dispose();
    }
    super.dispose();
  }
}

final _digits10 = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)];

/// The Details, Address and Owner sections. [open] says which are unfolded; [onToggle] flips one.
///
/// With [preLead] only the academy's own details and address are shown: there is no owner yet, and the
/// address is optional apart from the city and state.
class AcademyFormSections extends StatelessWidget {
  const AcademyFormSections({super.key, required this.data, required this.open, required this.onToggle, this.preLead = false});

  final AcademyFormData data;
  final Set<String> open;
  final ValueChanged<String> onToggle;
  final bool preLead;

  @override
  Widget build(BuildContext context) {
    final issues = data.issues(preLead: preLead);
    bool ok(String s) => !issues.any((i) => i.$1 == s);
    String? b(String s) => ok(s) ? 'Done' : 'Incomplete';
    Tone tn(String s) => ok(s) ? Tone.green : Tone.gold;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CollapsibleSection(
        icon: 'bld',
        title: 'Academy details',
        summary: data.name.text.trim().isEmpty ? 'Name, type, academy email' : data.name.text.trim(),
        open: open.contains('details'),
        onToggle: () => onToggle('details'),
        badge: b('details'),
        badgeTone: tn('details'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HqField(label: 'Academy name', controller: data.name, hint: 'e.g. Nrityanjali Dance Academy'),
          HqSelect<String>(
            label: 'Academy type',
            value: data.type,
            searchable: false,
            options: [for (final t in AcademyMeta.academyTypes) SelectOption(t, t)],
            onChanged: data.setType,
          ),
          HqField(label: preLead ? 'Academy email (phone or email)' : 'Academy email', controller: data.aemail, hint: 'academy@yourname.in', keyboard: TextInputType.emailAddress),
          HqField(label: preLead ? 'Academy phone (phone or email)' : 'Academy phone', controller: data.aphone, hint: '10-digit mobile', keyboard: TextInputType.phone, formatters: _digits10),
        ]),
      ),
      CollapsibleSection(
        icon: 'home',
        title: 'Address',
        summary: data.addressLine.isEmpty ? (preLead ? 'City and state' : 'Required') : data.addressLine,
        open: open.contains('address'),
        onToggle: () => onToggle('address'),
        badge: b('address'),
        badgeTone: tn('address'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HqField(label: preLead ? 'Address line 1' : 'Address line 1 *', controller: data.a1, hint: 'House no., street'),
          HqField(label: 'Address line 2', controller: data.a2, hint: 'Area, apartment (optional)'),
          HqField(label: 'Landmark', controller: data.landmark, hint: 'Optional'),
          FieldRow([
            HqField(label: 'City *', controller: data.city, hint: 'City'),
            HqField(label: 'District', controller: data.district, hint: 'District'),
          ]),
          FieldRow([
            HqField(label: 'State *', controller: data.state, hint: 'State'),
            HqField(label: 'Country', controller: data.country, hint: 'Country'),
          ]),
          HqField(label: preLead ? 'PIN code' : 'PIN code *', controller: data.pin, hint: '6-digit PIN code', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]),
        ]),
      ),
      if (!preLead)
      CollapsibleSection(
        icon: 'user',
        title: 'Owner',
        summary: data.owner.text.trim().isEmpty ? 'Who runs the academy and gets the login invite' : data.owner.text.trim(),
        open: open.contains('owner'),
        onToggle: () => onToggle('owner'),
        badge: b('owner'),
        badgeTone: tn('owner'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HqField(label: 'Owner name', controller: data.owner, hint: 'Full name'),
          FieldRow([
            HqField(label: 'Owner phone', controller: data.ophone, hint: '10-digit mobile', keyboard: TextInputType.phone, formatters: _digits10),
            HqField(label: 'Owner email', controller: data.oemail, hint: 'owner@academy.in', keyboard: TextInputType.emailAddress),
          ]),
        ]),
      ),
    ]);
  }
}
