import 'package:flutter/material.dart';
import 'package:nest_fe/app/theme/app_tokens.dart';
import 'package:nest_fe/app/theme/app_typography.dart';
import 'package:nest_fe/core/validation/countries.dart';

/// A searchable list of every country and its calling code, for choosing the code of a phone
/// number. Returns the chosen [Country], or null if dismissed.
///
/// Searching matches the name, the two-letter code and the calling code, with or without the plus:
/// "ind", "IN", "91" and "+91" all find India. With nothing typed, the countries this app's users
/// are most often in come first, then everything A to Z.
Future<Country?> showCountryPicker({
  required BuildContext context,
  Country? selected,
  String title = 'Country code',
}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8040710),
    builder: (sheetContext) => _CountrySheet(title: title, selected: selected),
  );
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.title, required this.selected});

  final String title;
  final Country? selected;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Country> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return Country.all;
    final digits = q.replaceAll('+', '');
    return Country.all.where((c) {
      if (c.searchText.contains(q)) return true;
      // "91" and "+91" find India; "+1" finds all of North America.
      return digits.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(digits) && c.dialDigits.startsWith(digits);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final matches = _matches;
    final popularCount = _query.trim().isEmpty ? Country.popular.length : 0;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.sheetTop,
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xl),
              decoration: BoxDecoration(color: palette.border, borderRadius: AppRadii.all(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title.toUpperCase(), style: AppType.sectionLabel(palette.textMuted))),
                  Text('${Country.all.length} countries',
                      style: TextStyle(fontSize: AppType.smd, color: palette.textFaint)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
              child: TextField(
                controller: _search,
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: AppType.xl, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search country or code',
                  hintStyle: TextStyle(fontSize: AppType.lg, color: palette.textFaint),
                  prefixIcon: Icon(Icons.search, size: 18, color: palette.textFaint),
                  filled: true,
                  fillColor: palette.surfaceRaised,
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
                  border: OutlineInputBorder(
                    borderRadius: AppRadii.all(AppRadii.xl),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadii.all(AppRadii.xl),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadii.all(AppRadii.xl),
                    borderSide: BorderSide(color: palette.primary),
                  ),
                ),
              ),
            ),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.x4l),
                      child: Text('No country matches "$_query".',
                          style: TextStyle(fontSize: AppType.lg, color: palette.textMuted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      // A header row before the popular block and another before the rest.
                      itemCount: matches.length + (popularCount > 0 ? 2 : 0),
                      itemBuilder: (context, i) {
                        if (popularCount > 0) {
                          if (i == 0) return _header('Popular');
                          if (i == popularCount + 1) return _header('All countries');
                          final index = i < popularCount + 1 ? i - 1 : i - 2;
                          return _row(matches[index]);
                        }
                        return _row(matches[i]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xs),
      child: Text(text.toUpperCase(), style: AppType.sectionLabel(palette.textFaint)),
    );
  }

  Widget _row(Country country) {
    final palette = context.palette;
    final isSelected = widget.selected?.iso == country.iso;
    return InkWell(
      onTap: () => Navigator.of(context).pop(country),
      borderRadius: AppRadii.all(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 11),
        child: Row(
          children: [
            SizedBox(width: 30, child: Text(country.flag, style: const TextStyle(fontSize: 20))),
            Expanded(
              child: Text(
                country.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.xl,
                  fontWeight: isSelected ? AppType.bold : AppType.regular,
                  color: isSelected ? palette.primary : palette.text,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              country.dial,
              style: TextStyle(
                fontSize: AppType.lg,
                fontWeight: AppType.bold,
                color: isSelected ? palette.primary : palette.textMuted,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.check, size: 16, color: palette.primary),
            ],
          ],
        ),
      ),
    );
  }
}
