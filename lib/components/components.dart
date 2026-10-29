import 'dart:async';
export 'package:hugeicons/hugeicons.dart';
import 'badge.dart';
export 'badge.dart';
export 'list_tile.dart';
export 'pill_chip.dart';
export 'hero_blocks.dart';
export 'card.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:syntax_highlight/syntax_highlight.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kong_comic/foundation/app.dart';
import 'package:kong_comic/foundation/app_page_route.dart';
import 'package:kong_comic/foundation/appdata.dart';
import 'package:kong_comic/foundation/comic_source/comic_source.dart';
import 'package:kong_comic/foundation/comic_type.dart';
import 'package:kong_comic/foundation/consts.dart';
import 'package:kong_comic/foundation/custom_cover.dart';
import 'package:kong_comic/foundation/favorites.dart';
import 'package:kong_comic/foundation/history.dart';
import 'package:kong_comic/foundation/image_provider/cached_image.dart';
import 'package:kong_comic/foundation/image_provider/history_image_provider.dart';
import 'package:kong_comic/foundation/image_provider/local_comic_image.dart';
import 'package:kong_comic/foundation/local.dart';
import 'package:kong_comic/foundation/log.dart';
import 'package:kong_comic/foundation/listen_mixin.dart';
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/cloudflare.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/favorites/favorites_page.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/utils/image_save.dart';
import 'package:kong_comic/design_tokens.dart';
export 'package:kong_comic/design_tokens.dart';

part 'glass_container.dart';
part 'image.dart';
part 'cover.dart';
part 'appbar.dart';
part 'button.dart';
part 'consts.dart';
part 'tools_pill.dart';
part 'flyout.dart';
part 'layout.dart';
part 'loading.dart';
part 'chibi.dart';
part 'menu.dart';
part 'message.dart';
part 'navigation_bar.dart';
part 'pop_up_widget.dart';
part 'scroll.dart';
part 'select.dart';
part 'switch.dart';
part 'side_bar.dart';
part 'comic.dart';
part 'effects.dart';
part 'gesture.dart';
part 'code.dart';

/// 统一的友好空状态组件 —— 用于各 tab 的"无数据"展示。
/// 与 NetworkError（红色错误图标）区分：本组件传达"这里还没有内容"而非"出错了"。
///
/// 默认插画是 [KcChibiIdle]：空状态和加载态共用同一只角色，形成「在爬 = 正在
/// 载入、停着 = 没有内容」的一套语言。个别场景（塞在卡片里的窄条空态）可以
/// 用 [illustration] 换更小的画，或用 [icon] 退回单个图标。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.illustration,
    this.illustrationWidth = 144,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  }) : assert(
         icon == null || illustration == null,
         'icon 与 illustration 只能二选一',
       );

  /// 单个图标的退路。不传 [illustration] 也不传它时用默认角色插画。
  final Widget? icon;

  /// 自定义插画（整块 Widget，尺寸由调用方自己决定）。
  final Widget? illustration;

  /// 默认角色插画的宽度。矮屏 / 窄卡片里可以调小到 88–96。
  final double illustrationWidth;

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 次要动作（文字按钮）。用于「主 CTA 之外还有一个轻量入口」的场景，
  /// 例如收藏总览空态：主按钮去发现页，次按钮新建文件夹。
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget graphic;
    if (illustration != null) {
      graphic = illustration!;
    } else if (icon != null) {
      graphic = IconTheme(
        data: IconThemeData(
          size: 56,
          color: cs.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        child: icon!,
      );
    } else {
      // 默认角色插画。标题已经说明了「这里是什么都没有」，插画不需要再被
      // 读屏念一次。
      graphic = ExcludeSemantics(
        child: KcChibiIdle(width: illustrationWidth),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            graphic,
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: kcSubtitle,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: kcBody,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              Button.filled(
                onPressed: () => onAction?.call(),
                child: Text(actionLabel!),
              ),
            ],
            // 次要动作：不抢主 CTA 的视觉权重，用文字按钮排在下面。
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 4),
              Button.text(
                onPressed: () => onSecondary?.call(),
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
