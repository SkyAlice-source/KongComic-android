import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/cache_manager.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/js_engine.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/network/app_dio.dart';
import 'package:kong_comic/utils/data.dart';
import 'package:kong_comic/utils/data_sync.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:yaml/yaml.dart';
import 'package:kong_comic/utils/import_comic.dart';

part 'reader.dart';
part 'explore_settings.dart';
part 'setting_components.dart';
part 'appearance.dart';
part 'local_favorites.dart';
part 'app.dart';
part 'about.dart';
part 'network.dart';
part 'download.dart';
part 'import_settings.dart';
part 'debug.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage = -1, super.key});

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int currentPage = -1;

  ColorScheme get colors => Theme.of(context).colorScheme;

  bool get enableTwoViews => context.width > 720;

  final categories = <String>[
    "Explore",
    "Reading",
    "Appearance",
    "Local Favorites",
    "APP",
    "Download",
    "Import",
    "Network",
    "About"
  ];

  final icons = <IconData>[
    FluentIcons.compass_northwest_24_regular,
    FluentIcons.book_24_regular,
    FluentIcons.color_24_regular,
    FluentIcons.bookmark_multiple_24_regular,
    FluentIcons.apps_24_regular,
    Icons.file_download,
    FluentIcons.arrow_import_24_regular,
    FluentIcons.globe_24_regular,
    FluentIcons.info_24_regular,
  ];

  @override
  void initState() {
    currentPage = widget.initialPage;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: buildBody(),
    );
  }

  Widget buildBody() {
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(
            width: 280,
            height: double.infinity,
            child: buildLeft(),
          ),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return LayoutBuilder(
                  builder: (context, constrains) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        var width = constrains.maxWidth;
                        var value = animation.isForwardOrCompleted
                            ? 1 - animation.value
                            : 1;
                        var left = width * value;
                        return Stack(
                          children: [
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: width,
                              child: child,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              child: buildRight(),
            ),
          )
        ],
      );
    } else {
      return buildLeft();
    }
  }

  Widget buildLeft() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).padding.top,
          ),
          SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(
                width: 8,
              ),
              Tooltip(
                message: "Back",
                child: IconButton(
                  icon: const Icon(FluentIcons.arrow_left_24_regular),
                  onPressed: context.pop,
                ),
              ),
              const SizedBox(
                width: 24,
              ),
              Text(
                "Settings".tl,
                style: ts.s20,
              )
            ]),
          ),
          const SizedBox(
            height: 4,
          ),
          Expanded(
            child: buildCategories(),
          )
        ],
      ),
    );
  }

  Widget buildCategories() {
    Widget buildItem(String name, int id) {
      final bool selected = id == currentPage;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      Widget content = Container(
        height: 58,
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: Row(children: [
          Icon(icons[id], color: isDark
              ? (selected ? const Color(0xFF0EA5E9) : Colors.white.withValues(alpha: 0.7))
              : const Color(0xFF0EA5E9), size: 22),
          const SizedBox(width: 14),
          Text(
            name,
            style: ts.s16.copyWith(
              color: selected
                  ? (isDark ? Colors.white : const Color(0xFF1A365D))
                  : (isDark ? Colors.white.withValues(alpha: 0.7) : null),
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
          const Spacer(),
          if (selected) const Icon(FluentIcons.chevron_right_24_regular, color: Color(0xFF0EA5E9))
        ]),
      );

      if (selected) {
        content = Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(14),
          ),
          height: 58,
          child: content,
        );
      } else {
        content = Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A1E).withValues(alpha: 0.5) : const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(14),
          ),
          height: 58,
          child: content,
        );
      }

      return Padding(
        padding: enableTwoViews
            ? const EdgeInsets.fromLTRB(8, 0, 8, 0)
            : EdgeInsets.zero,
        child: InkWell(
          splashColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(() => _SettingsDetailPage(pageIndex: id));
            }
          },
          child: content,
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: categories.length,
      itemBuilder: (context, index) => buildItem(categories[index].tl, index),
    );
  }

  Widget buildRight() {
    if (currentPage == -1) {
      return const SizedBox();
    }
    return Navigator(
      onGenerateRoute: (settings) {
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return _buildSettingsContent(currentPage);
          },
          transitionDuration: Duration.zero,
        );
      },
    );
  }

  Widget _buildSettingsContent(int pageIndex) {
    return switch (pageIndex) {
      0 => const ExploreSettings(),
      1 => const ReaderSettings(),
      2 => const AppearanceSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const AppSettings(),
      5 => const DownloadSettings(),
      6 => const ImportSettings(),
      7 => const NetworkSettings(),
      8 => const AboutSettings(),
      _ => throw UnimplementedError()
    };
  }

}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: _buildPage(),
    );
  }

  Widget _buildPage() {
    return switch (pageIndex) {
      0 => const ExploreSettings(),
      1 => const ReaderSettings(),
      2 => const AppearanceSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const AppSettings(),
      5 => const DownloadSettings(),
      6 => const ImportSettings(),
      7 => const NetworkSettings(),
      8 => const AboutSettings(),
      _ => throw UnimplementedError()
    };
  }
}
