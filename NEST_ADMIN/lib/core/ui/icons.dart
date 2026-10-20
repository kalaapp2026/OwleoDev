import 'package:flutter/material.dart';

/// The prototype draws its icons from a lucide-style SVG set and refers to them by short names
/// (`ic('wallet')`). Screens here keep those same names so a prototype line can be ported
/// directly, and this table maps each name to the closest Material icon.
const Map<String, IconData> _icons = {
  'dash': Icons.dashboard_outlined,
  'bld': Icons.apartment_outlined,
  'trend': Icons.trending_up_rounded,
  'rupee': Icons.currency_rupee_rounded,
  'rocket': Icons.rocket_launch_outlined,
  'users': Icons.group_outlined,
  'cap': Icons.school_outlined,
  'plus': Icons.add_rounded,
  'search': Icons.search_rounded,
  'bell': Icons.notifications_none_rounded,
  'x': Icons.close_rounded,
  'chev': Icons.chevron_right_rounded,
  'left': Icons.chevron_left_rounded,
  'up': Icons.north_east_rounded,
  'down': Icons.south_east_rounded,
  'warn': Icons.warning_amber_rounded,
  'check': Icons.check_rounded,
  'layers': Icons.layers_outlined,
  'pulse': Icons.monitor_heart_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'target': Icons.track_changes_rounded,
  'book': Icons.menu_book_outlined,
  'pin': Icons.place_outlined,
  'grid': Icons.grid_view_rounded,
  'imgplus': Icons.add_photo_alternate_outlined,
  'cal': Icons.calendar_month_outlined,
  'user': Icons.account_circle_outlined,
  'heart': Icons.favorite_border_rounded,
  'msg': Icons.chat_bubble_outline_rounded,
  'flag': Icons.flag_outlined,
  'eye': Icons.visibility_outlined,
  'send': Icons.send_rounded,
  'phone': Icons.phone_outlined,
  'mail': Icons.mail_outline_rounded,
  'lock': Icons.lock_outline_rounded,
  'shield': Icons.verified_user_outlined,
  'mega': Icons.campaign_outlined,
  'spark': Icons.auto_awesome_outlined,
  'clock': Icons.schedule_rounded,
  'gear': Icons.settings_outlined,
  'flow': Icons.account_tree_outlined,
  'exit': Icons.logout_rounded,
  'file': Icons.description_outlined,
  'edit': Icons.edit_outlined,
  'home': Icons.home_outlined,
  'dl': Icons.file_download_outlined,
  'ul': Icons.file_upload_outlined,
  'filter': Icons.filter_alt_outlined,
  'db': Icons.storage_outlined,
  'undo': Icons.undo_rounded,
  'bank': Icons.account_balance_outlined,
  'camera': Icons.photo_camera_outlined,
  'chevd': Icons.keyboard_arrow_down_rounded,
  'trash': Icons.delete_outline_rounded,
  'back': Icons.arrow_back_rounded,
  'star': Icons.star_rounded,
  'reply': Icons.reply_rounded,
  'swap': Icons.swap_horiz_rounded,
};

IconData iconOf(String name) {
  final i = _icons[name];
  assert(i != null, 'Unknown HQ icon "$name"');
  return i ?? Icons.circle_outlined;
}

/// `ic('wallet', 16, color)` - same call shape as the prototype's helper.
Widget ic(String name, [double size = 16, Color? color]) => Icon(iconOf(name), size: size, color: color);
