import 'dart:async';
export 'package:hugeicons/hugeicons.dart';
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
import 'package:kong_comic/foundation/res.dart';
import 'package:kong_comic/network/cloudflare.dart';
import 'package:kong_comic/utils/ext.dart';
import 'package:kong_comic/utils/io.dart';
import 'package:kong_comic/utils/tags_translation.dart';
import 'package:kong_comic/pages/comic_details_page/comic_page.dart';
import 'package:kong_comic/pages/favorites/favorites_page.dart';
import 'package:kong_comic/utils/translations.dart';

part 'glass_container.dart';
part 'image.dart';
part 'appbar.dart';
part 'button.dart';
part 'consts.dart';
part 'flyout.dart';
part 'layout.dart';
part 'loading.dart';
part 'menu.dart';
part 'message.dart';
part 'navigation_bar.dart';
part 'pop_up_widget.dart';
part 'scroll.dart';
part 'select.dart';
part 'side_bar.dart';
part 'comic.dart';
part 'effects.dart';
part 'gesture.dart';
part 'code.dart';

/// 统一的友好空状态组件 —— 用于各 tab 的"无数据"展示。
/// 与 NetworkError（红色错误图标）区分：本组件传达"这里还没有内容"而非"出错了"。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
              child: icon,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
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
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
