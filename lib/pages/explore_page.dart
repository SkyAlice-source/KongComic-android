import 'package:flutter/material.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/scroll_top_fab.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/global_state.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/pages/comic_source_page.dart';
import 'package:kong_comic/pages/settings/settings_page.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/translations.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin<ExplorePage> {
  late TabController controller;

  final showFB = ValueNotifier<bool>(true);

  double location = 0;

  late List<String> pages;

  void onSettingsChanged() {
    var explorePages = List<String>.from(appdata.settings["explore_pages"] ?? []);
    var all = ComicSource.enabled()
        .map((e) => e.explorePages)
        .expand((e) => e.map((e) => e.title))
        .toList();
    explorePages = explorePages.where((e) => all.contains(e)).toList();
    _sortBySourceOrder(explorePages);
    if (!pages.isEqualTo(explorePages)) {
      setState(() {
        pages = explorePages;
        controller = TabController(
          length: pages.length,
          vsync: this,
        );
      });
    }
  }

  /// Sorts explore-page titles by their owning source's position in
  /// [sourceOrder], preserving relative order within the same source.
  void _sortBySourceOrder(List<String> list) {
    final order = appdata.settings['sourceOrder'];
    int orderOf(String title) {
      for (var s in ComicSource.enabled()) {
        if (s.explorePages.any((e) => e.title == title)) {
          if (order is List) {
            final i = order.indexOf(s.key);
            if (i != -1) return i;
          }
          return 1 << 30;
        }
      }
      return 1 << 30;
    }

    list.sort((a, b) => orderOf(a).compareTo(orderOf(b)));
  }

  void onNaviItemTapped(int index) {
    if (index == 2) {
      int page = controller.index;
      String currentPageId = pages[page];
      GlobalState.find<_SingleExplorePageState>(currentPageId).toTop();
    }
  }

  void addPage() {
    showPopUpWidget(App.rootContext, setExplorePagesWidget());
  }

  NaviPaneState? naviPane;

  @override
  void initState() {
    pages = List<String>.from(appdata.settings["explore_pages"]);
    var all = ComicSource.enabled()
        .map((e) => e.explorePages)
        .expand((e) => e.map((e) => e.title))
        .toList();
    pages = pages.where((e) => all.contains(e)).toList();
    _sortBySourceOrder(pages);
    controller = TabController(
      length: pages.length,
      vsync: this,
    );
    appdata.settings.addListener(onSettingsChanged);
    NaviPane.of(context).addNaviItemTapListener(onNaviItemTapped);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    naviPane = NaviPane.of(context);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    controller.dispose();
    showFB.dispose();
    appdata.settings.removeListener(onSettingsChanged);
    naviPane?.removeNaviItemTapListener(onNaviItemTapped);
    super.dispose();
  }

  void refresh() {
    int page = controller.index;
    String currentPageId = pages[page];
    GlobalState.find<_SingleExplorePageState>(currentPageId).refresh();
  }

  Widget buildFAB() => ScrollTopFab(
        avoidNavBar: true,
        heroTag: 'exploreScrollTopFab',
        onPressed: () {
          String currentPageId = pages[controller.index];
          GlobalState.find<_SingleExplorePageState>(currentPageId).toTop();
        },
      );

  Tab buildTab(String i) {
    var comicSource = ComicSource.enabled()
        .firstWhere((e) => e.explorePages.any((e) => e.title == i));
    return Tab(text: i.ts(comicSource.key), key: Key(i));
  }

  Widget buildBody(String i) => Material(
        child: _SingleExplorePage(i, key: PageStorageKey(i)),
      );

  Widget buildEmpty() {
    if (ComicSource.isEmpty) {
      return EmptyState(
        icon: HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 18),
        title: "No Explore Pages".tl,
        subtitle: "Please add some comic sources first".tl,
        actionLabel: "Manage".tl,
        onAction: () => context.to(() => const ComicSourcePage()),
      );
    }
    return EmptyState(
      icon: HugeIcon(icon: HugeIcons.strokeRoundedInbox, size: 18),
      title: "No Explore Pages".tl,
      subtitle: "Please check your source settings".tl,
      actionLabel: "Manage".tl,
      onAction: addPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (pages.isEmpty) {
      return buildEmpty();
    }

    Widget tabBar = Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: AppTabBar(
        key: PageStorageKey(pages.toString()),
        tabs: pages.map((e) => buildTab(e)).toList(),
        controller: controller,
        actionButton: TabActionButton(
          icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
          text: "Add".tl,
          onPressed: () => context.to(() => const ComicSourcePage()),
        ),
      ),
    ).paddingTop(context.padding.top);

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              tabBar,
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notifications) {
                    if (notifications.metrics.axis == Axis.horizontal) {
                      if (!showFB.value) {
                        showFB.value = true;
                      }
                      return true;
                    }

                    var current = notifications.metrics.pixels;
                    var overflow = notifications.metrics.outOfRange;
                    if (current > location && current != 0 && showFB.value) {
                      showFB.value = false;
                    } else if ((current < location - 50 || current == 0) &&
                        !showFB.value) {
                      showFB.value = true;
                    }
                    if ((current > location || current < location - 50) &&
                        !overflow) {
                      location = current;
                    }
                    return false;
                  },
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: TabBarView(
                      controller: controller,
                      children: pages.map((e) => buildBody(e)).toList(),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
        Positioned(
          right: 16,
          // 与历史页对齐：ScrollTopFab(avoidNavBar:true) 已在内部加 bottomBarHeight
          // 抬升，这里只留 endFloat 默认的 16 边距。原 90 会导致发现页 FAB 比
          // 历史页高出一大截（90 + bottomBarHeight vs 16 + bottomBarHeight）。
          bottom: 16,
          child: ValueListenableBuilder<bool>(
            valueListenable: showFB,
            builder: (context, visible, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              reverseDuration: const Duration(milliseconds: 150),
              child: visible ? buildFAB() : const SizedBox(),
              transitionBuilder: (widget, animation) {
                var tween = Tween<Offset>(
                    begin: const Offset(0, 1), end: const Offset(0, 0));
                return SlideTransition(
                  position: tween.animate(animation),
                  child: widget,
                );
              },
            ),
          ),
        )
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _SingleExplorePage extends StatefulWidget {
  const _SingleExplorePage(this.title, {super.key});

  final String title;

  @override
  State<_SingleExplorePage> createState() => _SingleExplorePageState();
}

class _SingleExplorePageState extends AutomaticGlobalState<_SingleExplorePage>
    with AutomaticKeepAliveClientMixin<_SingleExplorePage> {
  late final ExplorePageData data;

  late final String comicSourceKey;

  bool _notFound = false;

  bool _wantKeepAlive = true;

  var scrollController = ScrollController();

  VoidCallback? refreshHandler;

  void onSettingsChanged() {
    var explorePages = appdata.settings["explore_pages"];
    if (!explorePages.contains(widget.title)) {
      _wantKeepAlive = false;
      updateKeepAlive();
    }
  }

  @override
  void initState() {
    super.initState();
    for (var source in ComicSource.enabled()) {
      for (var d in source.explorePages) {
        if (d.title == widget.title) {
          data = d;
          comicSourceKey = source.key;
          appdata.settings.addListener(onSettingsChanged);
          return;
        }
      }
    }
    appdata.settings.addListener(onSettingsChanged);
    // 源已被移除：标记为未找到，build 显示空状态而不是 throw 崩溃
    _notFound = true;
  }

  @override
  void dispose() {
    scrollController.dispose();
    appdata.settings.removeListener(onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_notFound) {
      return EmptyState(
        icon: const Icon(Icons.explore_outlined),
        title: "Explore Page Not Found".tl,
        subtitle: "The comic source may have been removed.".tl,
      );
    }
    if (data.loadMultiPart != null) {
      return _MultiPartExplorePage(
        key: const PageStorageKey("comic_list"),
        data: data,
        controller: scrollController,
        comicSourceKey: comicSourceKey,
        refreshHandlerCallback: (c) {
          refreshHandler = c;
        },
      );
    } else if (data.loadPage != null || data.loadNext != null) {
      return ComicList(
        enablePageStorage: true,
        loadPage: data.loadPage,
        loadNext: data.loadNext,
        key: const PageStorageKey("comic_list"),
        controller: scrollController,
        showSourceOnCover: false,
        refreshHandlerCallback: (c) {
          refreshHandler = c;
        },
      );
    } else if (data.loadMixed != null) {
      return _MixedExplorePage(
        data,
        comicSourceKey,
        key: const PageStorageKey("comic_list"),
        controller: scrollController,
        refreshHandlerCallback: (c) {
          refreshHandler = c;
        },
      );
    } else {
      return Center(
        child: Text("Empty Page".tl),
      );
    }
  }

  @override
  Object? get key => widget.title;

  @override
  void refresh() {
    refreshHandler?.call();
  }

  @override
  bool get wantKeepAlive => _wantKeepAlive;

  void toTop() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }
}

class _MixedExplorePage extends StatefulWidget {
  const _MixedExplorePage(this.data, this.sourceKey,
      {super.key, this.controller, required this.refreshHandlerCallback});

  final ExplorePageData data;

  final String sourceKey;

  final ScrollController? controller;

  final void Function(VoidCallback c) refreshHandlerCallback;

  @override
  State<_MixedExplorePage> createState() => _MixedExplorePageState();
}

class _MixedExplorePageState
    extends MultiPageLoadingState<_MixedExplorePage, Object> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.refreshHandlerCallback(refresh);
  }

  void refresh() {
    reset();
  }

  Iterable<Widget> buildSlivers(BuildContext context, List<Object> data) sync* {
    List<Comic> cache = [];
    for (var part in data) {
      if (part is ExplorePagePart) {
        if (cache.isNotEmpty) {
          yield SliverGridComics(
            comics: (cache),
            showSourceOnCover: false,
          );
          yield const SliverToBoxAdapter(child: Divider());
          cache.clear();
        }
        yield* _buildExplorePagePart(part, widget.sourceKey);
        yield const SliverToBoxAdapter(child: Divider());
      } else {
        cache.addAll(part as List<Comic>);
      }
    }
    if (cache.isNotEmpty) {
      yield SliverGridComics(
        comics: (cache),
        showSourceOnCover: false,
      );
    }
  }

  @override
  Widget buildContent(BuildContext context, List<Object> data) {
    return SmoothCustomScrollView(
      controller: widget.controller,
      slivers: [
        ...buildSlivers(context, data),
        const SliverListLoadingIndicator(),
      ],
    );
  }

  @override
  Future<Res<List<Object>>> loadData(int page) async {
    var res = await widget.data.loadMixed!(page);
    if (res.error) {
      return res;
    }
    for (var element in res.data) {
      if (element is! ExplorePagePart && element is! List<Comic>) {
        return const Res.error("function loadMixed return invalid data");
      }
    }
    return res;
  }
}

Iterable<Widget> _buildExplorePagePart(
    ExplorePagePart part, String sourceKey) sync* {
  Widget buildTitle(ExplorePagePart part) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 5, 10),
          child: Row(
            children: [
              Text(
                part.title,
                style:
                    const TextStyle(fontSize: kcTitleLarge, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (part.viewMore != null)
                TextButton(
                  onPressed: () {
                    var context = App.mainNavigatorKey!.currentContext!;
                    part.viewMore!.jump(context);
                  },
                  child: Text("View more".tl),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget buildComics(ExplorePagePart part) {
    return SliverGridComics(
      comics: part.comics,
      showSourceOnCover: false,
    );
  }

  yield buildTitle(part);
  yield buildComics(part);
}

class _MultiPartExplorePage extends StatefulWidget {
  const _MultiPartExplorePage({
    super.key,
    required this.data,
    required this.controller,
    required this.comicSourceKey,
    required this.refreshHandlerCallback,
  });

  final ExplorePageData data;

  final ScrollController controller;

  final String comicSourceKey;

  final void Function(VoidCallback c) refreshHandlerCallback;

  @override
  State<_MultiPartExplorePage> createState() => _MultiPartExplorePageState();
}

class _MultiPartExplorePageState extends State<_MultiPartExplorePage> {
  late final ExplorePageData data;

  List<ExplorePagePart>? parts;

  bool loading = true;

  String? message;

  Map<String, dynamic> get state => {
        "loading": loading,
        "message": message,
        "parts": parts,
      };

  void restoreState(dynamic state) {
    if (state == null) return;
    loading = state["loading"];
    message = state["message"];
    parts = state["parts"];
  }

  void storeState() {
    PageStorage.of(context).writeState(context, state);
  }

  void refresh() {
    setState(() {
      loading = true;
      message = null;
      parts = null;
    });
    storeState();
  }

  @override
  void initState() {
    super.initState();
    data = widget.data;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    restoreState(PageStorage.of(context).readState(context));
    widget.refreshHandlerCallback(refresh);
  }

  void load() async {
    var res = await data.loadMultiPart!();
    loading = false;
    if (mounted) {
      setState(() {
        if (res.error) {
          message = res.errorMessage;
        } else {
          parts = res.data;
        }
      });
      storeState();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      load();
      return const Center(
        child: CircularProgressIndicator(),
      );
    } else if (message != null) {
      return NetworkError(
        message: message!,
        retry: () {
          setState(() {
            loading = true;
            message = null;
          });
        },
        withAppbar: false,
      );
    } else {
      return buildPage();
    }
  }

  Widget buildPage() {
    return SmoothCustomScrollView(
      key: const PageStorageKey('scroll'),
      controller: widget.controller,
      slivers: _buildPage().toList(),
    );
  }

  Iterable<Widget> _buildPage() sync* {
    for (var part in parts!) {
      yield* _buildExplorePagePart(part, widget.comicSourceKey);
    }
  }
}
