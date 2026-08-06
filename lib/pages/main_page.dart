import 'package:flutter/material.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/pages/categories_page.dart';
import 'package:kong_comic/pages/history_page.dart';
import 'package:kong_comic/pages/search_page.dart';
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
    // MainPage 挂在主干 Navigator 路由里，App.forceRebuild()（作用于 MyApp）
    // 不会重建本 State，导致顶栏 paneActions 缓存的布局切换图标不刷新。
    // 改为直接监听 settings，任何 comicDisplayMode 变化都让本页重建并刷新图标/文案。
    appdata.settings.addListener(_onSettingsChanged);
    super.initState();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_onSettingsChanged);
    super.dispose();
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
    const HistoryPage(
      key: PageStorageKey('history'),
    ),
  ];

  var index = 2; // Home tab (index 2)

  /// 列表/网格切换按钮仅在「收藏(1)/发现(3)/历史(4)」显示，
  /// 这三个页面都用 comicDisplayMode 渲染漫画。
  bool get _showLayoutToggle => index == 1 || index == 3 || index == 4;

  /// 当前是否为详细列表模式（detailed）。否则为简洁网格（brief）。
  bool get _isDetailedLayout => appdata.settings['comicDisplayMode'] != 'brief';

  @override
  Widget build(BuildContext context) {
    return NaviPane(
      initialPage: index,
      observer: _observer,
      navigatorKey: _navigatorKey!,
      paneItems: [
        PaneItemEntry(
          label: 'Categories'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedDashboardCircle, size: 22),
          activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedDashboardCircle, size: 22),
        ),
        PaneItemEntry(
          label: 'Favorites'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 22),
          activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 22),
        ),
        PaneItemEntry(
          label: 'Home'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedHome02, size: 22),
          activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedHome02, size: 22),
        ),
        PaneItemEntry(
          label: 'Explore'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 22),
          activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 22),
        ),
        PaneItemEntry(
          label: 'History'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 22),
          activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 22),
        ),
      ],
      onPageChanged: (i) {
        setState(() {
          index = i;
        });
      },
      paneActions: [
        if (_showLayoutToggle)
          PaneActionEntry(
            icon: HugeIcon(
              icon: _isDetailedLayout
                  ? HugeIcons.strokeRoundedGridView
                  : HugeIcons.strokeRoundedListView,
              size: 22,
            ),
            label: _isDetailedLayout
                ? "Switch to grid view".tl
                : "Switch to list view".tl,
            onTap: () {
              appdata.settings['comicDisplayMode'] =
                  _isDetailedLayout ? 'brief' : 'detailed';
              appdata.saveData();
            },
          ),
        PaneActionEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch02, size: 22),
          label: "Search".tl,
          onTap: () {
            to(() => const SearchPage(), preventDuplicate: true);
          },
        ),
        PaneActionEntry(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 22),
          label: "Settings".tl,
          onTap: () {
            to(() => const SettingsPage(), preventDuplicate: true);
          },
        )
      ],
      pageBuilder: (index) {
        return _pages[index];
      },
      // 收藏页(1)与历史页(4)均显示全局粗体标题（"收藏"/"历史"），
      // 操作按钮各自承载在页面内部 SliverAppbar，故无需隐藏任何全局标题。
      topBarTitleHiddenPages: const [],
    );
  }
}
