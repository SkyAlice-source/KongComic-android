import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
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
    if (folder != null
        && !isNetwork
        && !LocalFavoritesManager().existsFolder(folder!)) {
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
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.primary),
      child: Stack(
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
                      begin: const Offset(0, 1), end: const Offset(0, 0));
                  return SlideTransition(
                      position: tween.animate(animation), child: widget);
                },
              ),
            ),
          ),
        ],
      ),
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
    Navigator.of(App.mainNavigatorKey?.currentContext ?? context).push(PageRouteBuilder(
      barrierDismissible: true,
      fullscreenDialog: true,
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.36),
      pageBuilder: (context, animation, secondary) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            child: SizedBox(
              width: min(300, context.width - 16),
              child: _LeftBar(
                withAppbar: true,
                favPage: this,
                onSelected: () {
                  context.pop();
                },
              ),
            ),
          ),
        );
      },
      transitionsBuilder: (context, animation, secondary, child) {
        var offset =
            Tween<Offset>(begin: const Offset(-1, 0), end: const Offset(0, 0));
        return SlideTransition(
          position: offset.animate(CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
          )),
          child: child,
        );
      },
    ));
  }

  Widget buildBody() {
    if (folder == null) {
      return CustomScrollView(
        slivers: [
          SliverAppbar(
            leading: Tooltip(
              message: "Folders".tl,
              child: context.width <= _kTwoPanelChangeWidth
                  ? IconButton(
                      icon: HugeIcon(icon: HugeIcons.strokeRoundedMenu02, size: 18),
                      color: context.colorScheme.primary,
                      onPressed: showFolderSelector,
                    )
                  : null,
            ),
            title: GestureDetector(
              onTap: context.width < _kTwoPanelChangeWidth
                  ? showFolderSelector
                  : null,
              child: Text("Unselected".tl),
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
