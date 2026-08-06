import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
import 'package:kong_comic/utils/data.dart';
import 'package:kong_comic/utils/data_sync.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/utils/import_comic.dart';
import 'package:kong_comic/utils/app_update.dart';

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

  List<String> _categories() => [
    "Reader Settings".tl,
    "Appearance".tl,
    "Explore".tl,
    "Local Favorites".tl,
    "Network".tl,
    "Download".tl,
    "Import".tl,
    "APP".tl,
    "About".tl
  ];

  final icons = <Widget>[
    HugeIcon(icon: HugeIcons.strokeRoundedBook01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedColorPicker, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedCompass01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedBookmark01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedDownload04, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedUpload01, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedAppStore, size: 24),
    HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 24),
  ];

  List<String> _subtitles() => [
    "Reading mode, page turning, zoom".tl,
    "Theme, language".tl,
    "Comic display, search sources, home".tl,
    "Local favorites management".tl,
    "Proxy, DNS".tl,
    "Download tasks, CBZ packaging".tl,
    "Comic import".tl,
    "Data sync, auth, cache, storage".tl,
    "Version, update, GitHub".tl,
  ];
  @override
  void initState() {
    currentPage = widget.initialPage;
    appdata.settings.addListener(_onSettingsChange);
    super.initState();
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_onSettingsChange);
    super.dispose();
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
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
                message: "Back".tl,
                child: IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, size: 22),
                  onPressed: context.pop,
                ),
              ),
              const SizedBox(
                width: 24,
              ),
              Text(
                "Settings".tl,
                style: ts.s20,
              ),
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
    Widget buildItem(String name, String subtitle, int id) {
      final bool selected = id == currentPage;
      final cs = Theme.of(context).colorScheme;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(kcCardRadius),
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(() => _SettingsDetailPage(pageIndex: id));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kcCardRadius),
              border: Border.all(
                color: selected ? cs.primary.withValues(alpha: 0.3) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                HugeIcon(icon: (icons[id] as HugeIcon).icon, color: selected ? cs.primary : cs.onSurfaceVariant, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: kcSubtitle,
                          fontWeight: FontWeight.w600,
                          color: selected ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: kcCaption,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: selected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.4),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: MediaQuery.of(context).padding.bottom + 16),
      itemCount: _categories().length,
      itemBuilder: (context, index) => buildItem(_categories()[index], _subtitles()[index], index),
    );
  }

  Widget buildRight() {
    if (currentPage == -1) {
      return const SizedBox();
    }
    // Render the selected settings page directly. Sub-pages reach a 2nd/3rd
    // level via `context.to`, which now resolves to the main (per-tab)
    // navigator — keeping the back stack symmetric with the narrow-screen
    // flow and the rest of the app.
    //
    // A separate nested Navigator used to live here. Because it was a
    // different navigator from the per-tab one, the outer PopScope in
    // navigation_bar.dart intercepted the system / predictive back gesture and
    // popped the whole SettingsPage off the per-tab stack, skipping the
    // in-page level. Returning from a 2nd/3rd-level settings page therefore
    // required multiple back presses (the same class of bug as the earlier
    // comments-page fix).
    return _buildSettingsContent(currentPage);
  }

  Widget _buildSettingsContent(int pageIndex) {
    return switch (pageIndex) {
      0 => const ReaderSettings(),
      1 => const AppearanceSettings(),
      2 => const ExploreSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const NetworkSettings(),
      5 => const DownloadSettings(),
      6 => const ImportSettings(),
      7 => const AppSettings(),
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
      0 => const ReaderSettings(),
      1 => const AppearanceSettings(),
      2 => const ExploreSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const NetworkSettings(),
      5 => const DownloadSettings(),
      6 => const ImportSettings(),
      7 => const AppSettings(),
      8 => const AboutSettings(),
      _ => throw UnimplementedError()
    };
  }
}
