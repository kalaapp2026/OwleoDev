/// Which kind of person a Users screen is dealing with.
///
/// It lives here rather than on either screen because both the roster and the form need it, and
/// having one import the other for it made them mutually dependent - which the compiler resolves
/// by merging the two into a single module.
///
/// This is more than a filter: it decides the accent colour, the add button's label, which
/// registration endpoint is called, and whether the form is one page or two.
enum UserTab {
  student('Students', 'student'),
  trainer('Trainers', 'trainer');

  const UserTab(this.label, this.noun);

  /// Plural, for the tab itself.
  final String label;

  /// Singular, for sentences: "Add trainer", "Edit student".
  final String noun;
}
