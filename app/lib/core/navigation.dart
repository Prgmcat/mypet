import 'package:flutter/material.dart';

/// Lets notification callbacks navigate without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
