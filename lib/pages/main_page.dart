import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/pages/categories_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/translations.dart';

import '../components/components.dart';
import '../foundation/app.dart';
import 'explore_page.dart';
import 'favorites/favorites_page.dart';
import 'home_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final NaviObserver _observer;

  GlobalKey<NavigatorState>? _navigatorKey;

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    _navigatorKey!.currentContext!.to(widget);
  }

  void back() {
    _navigatorKey!.currentContext!.pop();
  }

  @override
  void initState() {
    _observer = NaviObserver();
    _navigatorKey = GlobalKey();
    App.mainNavigatorKey = _navigatorKey;
    index = int.tryParse(appdata.settings['initialPage'].toString()) ?? 0;
    super.initState();
  }

  final _pages = [
    const CategoriesPage(
      key: PageStorageKey('categories'),
    ),
    const FavoritesPage(
      key: PageStorageKey('favorites'),
    ),
    const HomePage(),
    const ExplorePage(
      key: PageStorageKey('explore'),
    ),
  ];

  var index = 2; // Home tab (index 2)

  @override
  Widget build(BuildContext context) {
    return NaviPane(
      initialPage: index,
      observer: _observer,
      navigatorKey: _navigatorKey!,
      paneItems: [
        PaneItemEntry(
          label: 'Categories'.tl,
          icon: FluentIcons.apps_24_regular,
          activeIcon: FluentIcons.apps_24_regular,
        ),
        PaneItemEntry(
          label: 'Favorites'.tl,
          icon: FluentIcons.bookmark_24_regular,
          activeIcon: FluentIcons.bookmark_24_regular,
        ),
        PaneItemEntry(
          label: 'Home'.tl,
          icon: FluentIcons.home_24_regular,
          activeIcon: FluentIcons.home_24_regular,
        ),
        PaneItemEntry(
          label: 'Explore'.tl,
          icon: FluentIcons.book_compass_24_regular,
          activeIcon: FluentIcons.book_compass_24_regular,
        ),
      ],
      onPageChanged: (i) {
        setState(() {
          index = i;
        });
      },
      paneActions: [

        PaneActionEntry(
          icon: FluentIcons.settings_24_regular,
          label: "Settings".tl,
          onTap: () {
            to(() => const SettingsPage(), preventDuplicate: true);
          },
        )
      ],
      pageBuilder: (index) {
        return _pages[index];
      },
    );
  }
}
