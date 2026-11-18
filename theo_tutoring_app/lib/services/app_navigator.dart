import 'package:flutter/material.dart';

/// The app's root navigator (MaterialApp.navigatorKey), so app-wide pieces
/// such as the in-app notification banner can show on top of any page and
/// open pages without a BuildContext of their own.
final appNavigatorKey = GlobalKey<NavigatorState>();
