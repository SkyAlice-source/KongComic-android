import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/components/quick_search.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/image_provider/image_favorites_provider.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/image_favorites_page/type.dart';
import 'package:kong_comic/pages/reader/reader.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/image_save.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';

part "image_favorites_item.dart";

part "image_favorites_photo_view.dart";

class ImageFavoritesPage extends StatefulWidget {
  const ImageFavoritesPage({super.key, this.initialKeyword});

  final String? initialKeyword;

  @override
  State<ImageFavoritesPage> createState() => _ImageFavoritesPageState();
}

class _ImageFavoritesPageState extends State<ImageFavoritesPage>
    with AutoListenMixin {
  late ImageFavoriteSortType sortType;
  late TimeRange timeFilterSelect;
  late int numFilterSelect;

  // 所有的图片收藏
  List<ImageFavoritesComic> comics = [];

  bool multiSelectMode = false;

  // 多选的时候选中的图片
  Map<ImageFavorite, bool> selectedImageFavorites = {};

  void update() {
    if (mounted) {
      setState(() {});
    }
  }

  void updateImageFavorites() async {
    sortImageFavorites();
    update();
  }

  void sortImageFavorites() {
    // 搜索已统一走速搜浮层（搜到即点进详情），列表本身只负责排序 / 筛选，
    // 不再因为进出搜索态整页重建。
    comics = ImageFavoriteManager().getAll();
    // 筛选到最终列表
    comics = comics.where((ele) {
      bool isFilter = true;
      if (timeFilterSelect != TimeRange.all) {
        isFilter = timeFilterSelect.contains(ele.time);
      }
      if (numFilterSelect != numFilterList[0]) {
        // 必须是 AND，不能直接赋值：直接赋值会把上面时间筛选的结果覆盖掉，
        // 两个条件同时开启时时间过滤形同虚设。
        isFilter = isFilter && ele.images.length > numFilterSelect;
      }
      return isFilter;
    }).toList();
    // 给列表排序
    switch (sortType) {
      case ImageFavoriteSortType.title:
        comics.sort((a, b) => a.title.compareTo(b.title));
      case ImageFavoriteSortType.timeAsc:
        comics.sort((a, b) => a.time.compareTo(b.time));
      case ImageFavoriteSortType.timeDesc:
        comics.sort((a, b) => b.time.compareTo(a.time));
      case ImageFavoriteSortType.maxFavorites:
        comics.sort((a, b) => b.images.length.compareTo(a.images.length));
      case ImageFavoriteSortType.favoritesCompareComicPages:
        comics.sort((a, b) {
          double tempA = a.images.length / a.maxPageFromEp;
          double tempB = b.images.length / b.maxPageFromEp;
          return tempB.compareTo(tempA);
        });
    }
  }

  @override
  void initState() {
    // 外部带关键词进来时直接以同一套速搜浮层打开，并预填关键词，
    // 不再切进内联搜索态把顶栏整个换掉。
    final initialKeyword = widget.initialKeyword;
    if (initialKeyword != null && initialKeyword.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showQuickSearch(
          context,
          scope: QuickSearchScope.imageFavorites,
          initialQuery: initialKeyword,
        );
      });
    }
    sortType =
        ImageFavoriteSortType.values.firstWhereOrNull(
          (e) => e.value == appdata.implicitData["image_favorites_sort"],
        ) ??
        ImageFavoriteSortType.title;
    timeFilterSelect = TimeRange.fromString(
      appdata.implicitData["image_favorites_time_filter"],
    );
    numFilterSelect =
        appdata.implicitData["image_favorites_number_filter"] ??
        numFilterList[0];
    updateImageFavorites();
    listen(ImageFavoriteManager(), updateImageFavorites);
    super.initState();
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  var scrollController = ScrollController();

  void selectAll() {
    for (var c in comics) {
      for (var i in c.images) {
        selectedImageFavorites[i] = true;
      }
    }
    update();
  }

  void deSelect() {
    setState(() {
      selectedImageFavorites.clear();
      // 与 addSelected / Cancel / Delete / PopScope 一致：清空后退出多选态，
      // 否则页面会停在「标题 0、三枚操作常驻、辅助行消失」的残缺状态。
      multiSelectMode = false;
    });
  }

  void addSelected(ImageFavorite i) {
    if (selectedImageFavorites[i] == null) {
      selectedImageFavorites[i] = true;
    } else {
      selectedImageFavorites.remove(i);
    }
    if (selectedImageFavorites.isEmpty) {
      multiSelectMode = false;
    } else {
      multiSelectMode = true;
    }
    update();
  }

  /// 内容区辅助行：左侧结果数，右侧「排序（弹窗内含筛选 tab）」与「多选」
  /// 两枚动作常驻平铺。与收藏 / 历史的 [KcFilterChipRow] 第二行同一套排版；
  /// 图片收藏没有筛选 chip，所以单独画这一行，而不是塞一条空的 chip 行进去。
  Widget _buildActionRow() {
    final cs = Theme.of(context).colorScheme;
    final filterActive =
        timeFilterSelect != TimeRange.all ||
        numFilterSelect != numFilterList[0];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kcSpaceLg,
        vertical: kcSpaceXs,
      ),
      child: LayoutBuilder(
        builder: (context, rowConstraints) => Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: rowConstraints.maxWidth / 2,
              ),
              child: Text(
                "Showing @c items".tlParams({'c': comics.length}),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: kcCaption,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: LayoutBuilder(
                  builder: (ctx, actionConstraints) => KcActionOverflowBar(
                    actions: [
                      KcToolbarAction(
                        icon: HugeIcons.strokeRoundedSortDescending,
                        label: "Sort".tl,
                        color: filterActive ? kcBrandAdaptive(context) : null,
                        onTap: sort,
                      ),
                      KcToolbarAction(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                        label: "Multi-Select".tl,
                        onTap: () => setState(() => multiSelectMode = true),
                      ),
                    ],
                    maxWidth: actionConstraints.maxWidth,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 与收藏总览 / 文件夹内页 / 历史页统一：顶栏只放裸图标，不再套
    // [ToolsPill] 外壳；删除也从 ⋮ 里放出来，位置够就别藏。
    List<Widget> selectActions = [
      ToolsPillButton(
        icon: HugeIcons.strokeRoundedCheckmarkCircle01,
        tooltip: "Select All".tl,
        onPressed: selectAll,
      ),
      ToolsPillButton(
        icon: HugeIcons.strokeRoundedCancel01,
        tooltip: "Deselect".tl,
        onPressed: deSelect,
      ),
      ToolsPillButton(
        icon: HugeIcons.strokeRoundedDelete01,
        tooltip: "Delete".tl,
        color: Theme.of(context).colorScheme.error,
        onPressed: () {
          ImageFavoriteManager().deleteImageFavorite(
            selectedImageFavorites.keys,
          );
          setState(() {
            multiSelectMode = false;
            selectedImageFavorites.clear();
          });
        },
      ),
    ];

    var scrollWidget = SmoothCustomScrollView(
      controller: scrollController,
      slivers: [
        if (!multiSelectMode)
          SliverAppbar(
            title: Text("Image Favorites".tl),
            actions: [
              // 与收藏总览 / 文件夹内页 / 历史页一致：右上角只留一枚裸搜索，
              // 去掉 ToolsPill 的圆角外壳与发丝描边；数据源仍是图片收藏。
              ToolsPillButton(
                icon: HugeIcons.strokeRoundedSearch02,
                tooltip: "Search".tl,
                onPressed: () => showQuickSearch(
                  context,
                  scope: QuickSearchScope.imageFavorites,
                ),
              ),
            ],
          ),
        if (!multiSelectMode)
          // 排序（弹窗内含筛选）/ 多选从右上角挪到「显示 N 项」辅助行平铺，
          // 与收藏 / 历史两页的第二行同一套动作编排。
          SliverToBoxAdapter(child: _buildActionRow()),
        if (multiSelectMode)
          SliverAppbar(
            leading: Tooltip(
              message: "Cancel".tl,
              child: IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                onPressed: () {
                  setState(() {
                    multiSelectMode = false;
                    selectedImageFavorites.clear();
                  });
                },
              ),
            ),
            title: Text(selectedImageFavorites.length.toString()),
            actions: selectActions,
          ),
        if (comics.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: "No image favorites".tl,
              subtitle:
                  'Long-press a comic image to favorite it; images are saved here.'
                      .tl,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final comic = comics[index];
              return _ImageFavoritesItem(
                key: ValueKey('${comic.sourceKey}:${comic.id}'),
                imageFavoritesComic: comic,
                selectedImageFavorites: selectedImageFavorites,
                addSelected: addSelected,
                multiSelectMode: multiSelectMode,
                finalImageFavoritesComicList: comics,
              );
            }, childCount: comics.length),
          ),
        SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
      ],
    );
    Widget body = Scrollbar(
      controller: scrollController,
      thickness: App.isDesktop ? 8 : 12,
      radius: Radius.circular(kcRadius8),
      interactive: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: context.width > changePoint
            ? scrollWidget.paddingHorizontal(8)
            : scrollWidget,
      ),
    );
    return PopScope(
      canPop: !multiSelectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedImageFavorites.clear();
          });
        }
      },
      child: body,
    );
  }

  void sort() {
    showDialog(
      context: context,
      builder: (context) {
        return _ImageFavoritesDialog(
          initSortType: sortType,
          initTimeFilterSelect: timeFilterSelect,
          initNumFilterSelect: numFilterSelect,
          updateConfig: (sortType, timeFilter, numFilter) {
            setState(() {
              this.sortType = sortType;
              timeFilterSelect = timeFilter;
              numFilterSelect = numFilter;
            });
            sortImageFavorites();
          },
        );
      },
    );
  }
}

class _ImageFavoritesDialog extends StatefulWidget {
  const _ImageFavoritesDialog({
    required this.initSortType,
    required this.initTimeFilterSelect,
    required this.initNumFilterSelect,
    required this.updateConfig,
  });

  final ImageFavoriteSortType initSortType;
  final TimeRange initTimeFilterSelect;
  final int initNumFilterSelect;
  final Function updateConfig;

  @override
  State<_ImageFavoritesDialog> createState() => _ImageFavoritesDialogState();
}

class _ImageFavoritesDialogState extends State<_ImageFavoritesDialog> {
  List<String> optionTypes = ['Sort', 'Filter'];

  /// 当前分页。标题跟着它变，不再把「排序 / 筛选」和 tab 写重复。
  int tabIndex = 0;

  late var sortType = widget.initSortType;
  late var numFilter = widget.initNumFilterSelect;
  late TimeRangeType timeRangeType;
  DateTime? start;
  DateTime? end;

  @override
  void initState() {
    super.initState();
    timeRangeType = switch (widget.initTimeFilterSelect) {
      TimeRange.all => TimeRangeType.all,
      TimeRange.lastWeek => TimeRangeType.lastWeek,
      TimeRange.lastMonth => TimeRangeType.lastMonth,
      TimeRange.lastHalfYear => TimeRangeType.lastHalfYear,
      TimeRange.lastYear => TimeRangeType.lastYear,
      _ => TimeRangeType.custom,
    };
    if (timeRangeType == TimeRangeType.custom) {
      end = widget.initTimeFilterSelect.end;
      // end 为空时不能强解包：任何「end=null 但 duration 非零」的旧数据都会
      // 落到 custom 分支，这里直接崩掉整个筛选弹窗。
      final endValue = end;
      if (endValue != null) {
        start = endValue.subtract(widget.initTimeFilterSelect.duration);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = optionTypes.map((e) => e.tl).toList();
    // 与本地 / 收藏筛选共用参考式样外壳。标题随 tab 变化（不再重复写
    // 「排序 / 筛选」），分段控件等宽，右下角统一为红色胶囊「确认」。
    return KcChoiceDialog(
      title: labels[tabIndex],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KcChoiceTabBar(
            labels: labels,
            index: tabIndex,
            onChanged: (i) => setState(() => tabIndex = i),
          ),
          const SizedBox(height: kcSpaceMd),
          // 只挂当前分页：高度跟着内容走，筛选页不再为了对齐排序页留出
          // 一大片空白；AnimatedSize 让切换时的收缩 / 展开是滑动而非跳一下。
          AnimatedSize(
            duration: kcReduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: tabIndex == 0
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var i = 0;
                        i < ImageFavoriteSortType.values.length;
                        i++
                      ) ...[
                        KcRadioOption<ImageFavoriteSortType>(
                          value: ImageFavoriteSortType.values[i],
                          groupValue: sortType,
                          label: ImageFavoriteSortType.values[i].value.tl,
                          onChanged: (v) => setState(() => sortType = v),
                        ),
                        if (i < ImageFavoriteSortType.values.length - 1)
                          const SizedBox(height: kcDialogRowGap),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      KcListTile(
                        title: Text("Time Filter".tl),
                        showDivider: false,
                        trailing: Select(
                          current: timeRangeType.value.tl,
                          values: TimeRangeType.values
                              .map((e) => e.value.tl)
                              .toList(),
                          minWidth: 64,
                          onTap: (index) {
                            setState(() {
                              timeRangeType = TimeRangeType.values[index];
                            });
                          },
                        ),
                      ),
                      if (timeRangeType == TimeRangeType.custom)
                        Column(
                          children: [
                            KcListTile(
                              title: Text("Start Time".tl),
                              showDivider: false,
                              trailing: Button.text(
                                onPressed: () async {
                                  // showDatePicker 断言 initialDate 落在
                                  // [firstDate, lastDate] 内。先选了「结束时间」
                                  // （过去）再点「开始时间」时，initialDate 是
                                  // 今天 > lastDate，直接断言崩溃。
                                  final first = DateTime(2000);
                                  final last = end ?? DateTime.now();
                                  var initial = start ?? DateTime.now();
                                  if (initial.isBefore(first)) initial = first;
                                  if (initial.isAfter(last)) initial = last;
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: initial,
                                    firstDate: first,
                                    lastDate: last,
                                  );
                                  if (date != null && mounted) {
                                    setState(() {
                                      start = date;
                                    });
                                  }
                                },
                                child: Text(
                                  start == null
                                      ? "Select Date".tl
                                      : DateFormat("yyyy-MM-dd").format(start!),
                                ),
                              ),
                            ),
                            KcListTile(
                              title: Text("End Time".tl),
                              showDivider: false,
                              trailing: Button.text(
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final first = start ?? DateTime(2000);
                                  var initial = end ?? now;
                                  if (initial.isBefore(first)) initial = first;
                                  if (initial.isAfter(now)) initial = now;
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: initial,
                                    firstDate: first,
                                    lastDate: now,
                                  );
                                  if (date != null && mounted) {
                                    setState(() {
                                      end = date;
                                    });
                                  }
                                },
                                child: Text(
                                  end == null
                                      ? "Select Date".tl
                                      : DateFormat("yyyy-MM-dd").format(end!),
                                ),
                              ),
                            ),
                          ],
                        ),
                      KcListTile(
                        title: Text("Image Favorites Greater Than".tl),
                        showDivider: false,
                        trailing: Select(
                          current: numFilter.toString(),
                          values: numFilterList
                              .map((e) => e.toString())
                              .toList(),
                          minWidth: 64,
                          onTap: (index) {
                            setState(() {
                              numFilter = numFilterList[index];
                            });
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      onConfirm: () {
        // In custom mode neither date is pre-filled, and picking only one
        // (or none) would make `end!`/`start!` below throw — the dialog
        // must say what is missing instead of crashing.
        if (timeRangeType == TimeRangeType.custom) {
          final startValue = start;
          final endValue = end;
          if (startValue == null || endValue == null) {
            context.showMessage(
              message: "Please select a start and end time".tl,
            );
            return;
          }
          if (endValue.isBefore(startValue)) {
            context.showMessage(
              message: "The end time must be after the start time".tl,
            );
            return;
          }
        }
        appdata.implicitData["image_favorites_sort"] = sortType.value;
        TimeRange timeRange;
        if (timeRangeType == TimeRangeType.custom) {
          timeRange = TimeRange(end: end, duration: end!.difference(start!));
        } else {
          timeRange = switch (timeRangeType) {
            TimeRangeType.all => TimeRange.all,
            TimeRangeType.lastWeek => TimeRange.lastWeek,
            TimeRangeType.lastMonth => TimeRange.lastMonth,
            TimeRangeType.lastHalfYear => TimeRange.lastHalfYear,
            TimeRangeType.lastYear => TimeRange.lastYear,
            _ => TimeRange.all,
          };
        }
        appdata.implicitData["image_favorites_time_filter"] = timeRange
            .toString();
        appdata.implicitData["image_favorites_number_filter"] = numFilter;
        appdata.writeImplicitData();
        if (mounted) {
          Navigator.pop(context);
          widget.updateConfig(sortType, timeRange, numFilter);
        }
      },
    );
  }
}
