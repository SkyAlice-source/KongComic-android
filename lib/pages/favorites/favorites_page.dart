import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/bookshelf_layout.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/download.dart';
import 'package:kong_comic/network/cache.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/reader/reader.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/opencc.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/utils/translations.dart';

part 'favorite_actions.dart';
part 'side_bar.dart';
part 'local_favorites_page.dart';
part 'network_favorites_page.dart';

const _kLeftBarWidth = 256.0;

const _kTwoPanelChangeWidth = 720.0;

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String? folder;

  bool isNetwork = false;

  FolderList? folderList;

  // 收藏页整体回顶按钮：复用与发现/历史页一致的 ScrollTopFab
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showFab = ValueNotifier(true);
  double _scrollPos = 0;

  void setFolder(bool isNetwork, String? folder) {
    setState(() {
      this.isNetwork = isNetwork;
      this.folder = folder;
    });
    _showFab.value = true; // 切到别的文件夹后回到顶部，回顶按钮重新出现
    folderList?.update();
    appdata.implicitData['favoriteFolder'] = {
      'name': folder,
      'isNetwork': isNetwork,
    };
    appdata.writeImplicitData();
  }

  @override
  void initState() {
    var data = appdata.implicitData['favoriteFolder'];
    if (data != null) {
      folder = data['name'];
      isNetwork = data['isNetwork'] ?? false;
    }
    if (folder != null &&
        !isNetwork &&
        !LocalFavoritesManager().existsFolder(folder!)) {
      folder = null;
    }
    // 默认显示"全部"文件夹
    folder ??= _localAllFolderLabel;
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showFab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedPositioned(
          left: context.width <= _kTwoPanelChangeWidth ? -_kLeftBarWidth : 0,
          top: 0,
          bottom: 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: _kLeftBarWidth,
            color: Theme.of(context).colorScheme.surface,
            child: const _LeftBar(),
          ),
        ),
        Positioned(
          top: 0,
          left: context.width <= _kTwoPanelChangeWidth ? 0 : _kLeftBarWidth,
          right: 0,
          bottom: 0,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: buildBody(),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showFab,
            builder: (context, visible, _) => AnimatedSwitcher(
              duration: kcReduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              reverseDuration: kcReduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: (visible && folder != null)
                  ? _buildScrollTopFab()
                  : const SizedBox(),
              transitionBuilder: (widget, animation) {
                final tween = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: const Offset(0, 0),
                );
                return SlideTransition(
                  position: tween.animate(animation),
                  child: widget,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final current = n.metrics.pixels;
    if (current > _scrollPos && current != 0 && _showFab.value) {
      _showFab.value = false;
    } else if ((current < _scrollPos - 50 || current == 0) && !_showFab.value) {
      _showFab.value = true;
    }
    if (current > _scrollPos || current < _scrollPos - 50) {
      _scrollPos = current;
    }
    return false;
  }

  Widget _buildScrollTopFab() {
    return ScrollTopFab(
      avoidNavBar: true,
      heroTag: 'favoritesScrollTopFab',
      onPressed: () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
    );
  }

  void showFolderSelector() {
    // 用 showGeneralDialog 统一动画：遮罩与卡片同步淡入 + 轻微缩放。
    // 系统默认 DialogRoute 只淡入卡片，遮罩首帧就已铺满，慢设备上会先闪一屏灰。
    final reduceMotion = kcReduceMotion(context);
    showGeneralDialog(
      context: App.mainNavigatorKey?.currentContext ?? context,
      barrierDismissible: true,
      barrierLabel: 'Folders'.tl,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) =>
          _FolderSelectorDialog(favPage: this),
      transitionBuilder: (context, animation, _, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// 计算本地 / 网络 两组的漫画数量，用于未选中落地态的概览卡。
  Map<String, int> _favoritesGroupCounts() {
    final net = _computeNetworkFolders();
    var local = 0;
    var network = 0;
    for (final f in LocalFavoritesManager().folderNames) {
      if (f == kReadLaterFolder) continue;
      final c = LocalFavoritesManager().count(f);
      if (net.contains(f)) {
        network += c;
      } else {
        local += c;
      }
    }
    return {'local': local, 'network': network};
  }

  /// 复刻 _LeftBarState.findNetworkFolders：从已启用源的 favoriteData 键与
  /// settings['favorites'] 求交集，得到网络分组文件夹列表。
  List<String> _computeNetworkFolders() {
    final all = ComicSource.enabled()
        .where((e) => e.favoriteData != null)
        .map((e) => e.favoriteData!.key)
        .toList();
    final settings = appdata.settings['favorites'];
    final net = <String>[];
    if (settings is List) {
      for (var p in settings) {
        if (p is String && all.contains(p) && !net.contains(p)) {
          net.add(p);
        }
      }
    }
    return net;
  }

  /// 未选中落地态的分组概览卡：图标 + 标签 + 数量 + 箭头，点进去进对应列表。
  Widget _overviewCard(
    Widget icon,
    String label,
    int count,
    VoidCallback? onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kcCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(kcCardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: kcSubtitle,
                    fontWeight: FontWeight.w600,
                    color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: kcSubtitle,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 收藏页右上角工具胶囊条 —— 唯一实现见 `components/tools_pill.dart`
  /// 的 [ToolsPill]（历史页等列表页共用同一套外观，别再复制一份）。
  Widget _favToolsPill(BuildContext context, List<Widget> children) {
    return ToolsPill(children: children);
  }

  /// 工具胶囊条内的单个图标按钮 —— 见 [ToolsPillButton]。
  Widget _toolIconButton(
    BuildContext context, {
    required dynamic icon,
    bool active = false,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return ToolsPillButton(
      icon: icon,
      active: active,
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }

  /// 工具胶囊条内的「更多」按钮 —— 见 [ToolsPillMoreButton]。
  ///
  /// 定位坑已收进组件内部：必须用按钮自身 context 取 RenderBox，
  /// 否则菜单会弹到屏幕左上角（点右边弹左边）。
  Widget _toolMoreButton(BuildContext context, List<MenuEntry> entries) {
    return ToolsPillMoreButton(entries: entries);
  }

  Widget buildBody() {
    if (folder == null) {
      final counts = _favoritesGroupCounts();
      final net = _computeNetworkFolders();
      return CustomScrollView(
        slivers: [
          SliverAppbar(
            leading: Tooltip(
              message: "Folders".tl,
              child: context.width <= _kTwoPanelChangeWidth
                  ? IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedMenu02,
                        size: 18,
                      ),
                      color: kcBrandAdaptive(context),
                      onPressed: showFolderSelector,
                    )
                  : null,
            ),
            title: GestureDetector(
              onTap: context.width < _kTwoPanelChangeWidth
                  ? showFolderSelector
                  : null,
              child: Text(
                "Favorites".tl,
                style: const TextStyle(
                  fontSize: kcSectionTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 未选中落地态：用三张分组概览卡替代空标题，带数量、点进去进对应列表。
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(kcSpaceLg),
              child: Column(
                children: [
                  _overviewCard(
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                      size: 22,
                      color: kcAccentColor(context),
                    ),
                    "Local".tl,
                    counts['local']!,
                    () => setFolder(false, _localAllFolderLabel),
                  ),
                  const SizedBox(height: kcSpaceSm),
                  _overviewCard(
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedGlobe02,
                      size: 22,
                      color: net.isEmpty
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : kcAccentColor(context),
                    ),
                    "Network".tl,
                    counts['network']!,
                    net.isEmpty ? null : () => setFolder(true, net.first),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (!isNetwork) {
      return _LocalFavoritesPage(
        folder: folder!,
        controller: _scrollController,
        key: PageStorageKey("local_$folder"),
      );
    } else {
      var favoriteData = getFavoriteDataOrNull(folder!);
      if (favoriteData == null) {
        folder = null;
        return buildBody();
      } else {
        return NetworkFavoritePage(
          favoriteData,
          controller: _scrollController,
          key: PageStorageKey("network_$folder"),
        );
      }
    }
  }
}

abstract interface class FolderList {
  void update();

  void updateFolders();
}
