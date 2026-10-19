import 'package:flutter/widgets.dart';
import 'package:nest_fe/core/design/app_top_bar.dart';
import 'package:nest_fe/features/notification/data/notification_api.dart';
import 'package:nest_fe/features/notification/presentation/notification_bell.dart';

/// The theme switch and the bell, as the trailing actions of a pushed student screen's [AppTopBar].
const List<Widget> kStudentTopBarActions = [
  ThemeModeButton(),
  NotificationBell(module: NotificationModule.erp, tile: true),
];
