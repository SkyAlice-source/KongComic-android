import 'package:flutter/material.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/pages/categories_page.dart';
import 'package:kong_comic/pages/history_page.dart';
import 'package:kong_comic/pages/search_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/utils/translations.dart';

import '../components/components.dart';
import '../foundation/app.dart';
import '../foundation/consts.dart';
import 'explore_page.dart';
import 'favorites/favorites_page.dart';
import 'home_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with AutoListenMixin {
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
    listen(appdata.settings, _onSettingsChanged);
    super.initState();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  final _pages = [
    const CategoriesPage(key: PageStorageKey('categories')),
    const FavoritesPage(key: PageStorageKey('favorites')),
    const HomePage(),
    const ExplorePage(key: PageStorageKey('explore')),
    const HistoryPage(key: PageStorageKey('history')),
  ];

  var index = kHomeTabIndex; // 默认落在主页，页序见 kHomeTabIndex

  /// 列表/网格切换只在真正用漫画网格渲染的根页出现。原先写死 3/4，
  /// 页序一调就会错位；改成按页面类型判断，与页序解耦。
  bool get _showLayoutToggle {
    final page = _pages[index];
    // 历史页已在自己的 ToolsPill 里放了 ToolsPillLayoutButton，
    // 再挂一颗全局裸 IconButton 就是同一功能两个入口。只有发现页
    // 还没有页内胶囊，保留全局项。
    return page is ExplorePage;
  }

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
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedDashboardCircle,
            size: 22,
          ),
          activeIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedDashboardCircle,
            size: 22,
          ),
        ),
        PaneItemEntry(
          label: 'Favorites'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedFavourite, size: 22),
          activeIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedFavourite,
            size: 22,
          ),
        ),
        PaneItemEntry(
          label: 'Home'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedHome02, size: 22),
          activeIcon: HugeIcon(icon: HugeIcons.strokeRoundedHome02, size: 22),
        ),
        PaneItemEntry(
          label: 'Explore'.tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 22),
          activeIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedCompass01,
            size: 22,
          ),
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
            // 与收藏 / 历史页同一颗图标：形状即当前布局，点击淡入切换成另一种。
            // 旧的「换图标」写法只画出目标态，用户看不出现在是什么布局。
            icon: LayoutGlyphIcon(detailed: _isDetailedLayout, size: 22),
            label: _isDetailedLayout
                ? "Switch to grid view".tl
                : "Switch to list view".tl,
            onTap: () {
              appdata.settings['comicDisplayMode'] = _isDetailedLayout
                  ? 'brief'
                  : 'detailed';
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
        ),
      ],
      pageBuilder: (index) {
        return _pages[index];
      },
      // 5 个根 tab 全部走 NaviPane 的共享顶栏：收藏 / 历史通过
      // pageTitle / pageActions / pageHideGlobalActionsNotifier 注入标题与
      // 工具胶囊，不再自绘整条顶栏，因此不需要「隐藏共享顶栏」的页索引名单。
    );
  }
}
