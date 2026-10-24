import 'package:flutter_test/flutter_test.dart';
import 'package:owleo_hq/features/academies/academy_form.dart';

AcademyFormData form({
  String name = 'Nrityanjali Dance Academy',
  String city = 'Mysuru',
  String state = 'Karnataka',
  String phone = '9876543210',
  String email = '',
}) {
  final d = AcademyFormData();
  d.name.text = name;
  d.city.text = city;
  d.state.text = state;
  d.aphone.text = phone;
  d.aemail.text = email;
  return d;
}

void main() {
  group('pre-lead: the academy\'s own details only', () {
    test('a name, city, state and one way to reach them is enough', () {
      expect(form().issues(preLead: true), isEmpty);
    });

    test('no owner, address line or PIN is needed', () {
      final d = form();
      expect(d.owner.text, isEmpty);
      expect(d.ophone.text, isEmpty);
      expect(d.oemail.text, isEmpty);
      expect(d.a1.text, isEmpty);
      expect(d.pin.text, isEmpty);
      expect(d.issues(preLead: true), isEmpty);
    });

    test('an email alone will do', () {
      expect(form(phone: '', email: 'hello@nrityanjali.in').issues(preLead: true), isEmpty);
    });

    test('with neither phone nor email the team cannot reach them', () {
      final issues = form(phone: '').issues(preLead: true);
      expect(issues.map((i) => i.$2), contains("Add the academy's phone or email so the team can reach them."));
    });

    test('the basics are required', () {
      expect(form(name: 'Ab').issues(preLead: true).map((i) => i.$2), contains('Enter the academy name.'));
      expect(form(city: '').issues(preLead: true).map((i) => i.$2), contains('Enter the city.'));
      expect(form(state: '').issues(preLead: true).map((i) => i.$2), contains('Enter the state.'));
    });

    test('anything that is given must still be right', () {
      expect(form(phone: '12345').issues(preLead: true).map((i) => i.$2), contains('Enter the academy phone as a 10-digit mobile number.'));
      expect(form(email: 'nope').issues(preLead: true).map((i) => i.$2), contains('Enter a valid academy email address.'));
      final d = form()..pin.text = '123';
      expect(d.issues(preLead: true).map((i) => i.$2), contains('Enter a 6-digit PIN code, or leave it empty.'));
      final e = form()..a1.text = 'No';
      expect(e.issues(preLead: true).map((i) => i.$2), contains('Address line 1 needs a house number and street, or leave it empty.'));
    });
  });

  group('a lead still needs the whole account', () {
    test('the same details that pass as a pre-lead fail as a lead until the owner is added', () {
      final d = form(email: 'hello@nrityanjali.in');
      expect(d.issues(preLead: true), isEmpty);
      final lead = d.issues().map((i) => i.$1).toSet();
      expect(lead, containsAll(['address', 'owner']));

      d
        ..a1.text = '12 MG Road'
        ..pin.text = '570001'
        ..owner.text = 'Anjali Rao'
        ..ophone.text = '9876543211'
        ..oemail.text = 'anjali@example.com';
      expect(d.issues(), isEmpty);
    });
  });
}
