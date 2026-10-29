part of 'components.dart';

/// 封面占位层：没有可画的东西时也把版面占住，用「书名首字 + 中性底」
/// 代替纯空白。
///
/// 为什么不用灰块：断网时一屏十几张灰块看起来像界面坏了；而「首字」既宣告
/// 这里是一张封面，又保留了「这是哪本书」的信息，成本和灰块一样低。
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    this.label,
    this.icon,
    this.iconSize = 26,
    this.fontSize = 40,
    this.showIcon = true,
  });

  /// 书名。取首字作为占位文字；为空时退化为图标。
  final String? label;

  /// 自定义图标（默认用图片图标）。HugeIcons 的图标常量是嵌套 List，不是 IconData。
  final List<List<dynamic>>? icon;

  final double iconSize;

  /// 首字字号。大卡（主页英雄卡）给小卡的值会让首字小得看不见。
  final double fontSize;

  final bool showIcon;

  String? get _initial {
    final text = label?.trim();
    if (text == null || text.isEmpty) return null;
    // runes 取首个码点：中文、日文、emoji 都不会被截成半个字符。
    return String.fromCharCode(text.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = _initial;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        // 极弱的对角高光，避免一整块死灰；暗色下几乎不可见，只是让边缘有层次。
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.onSurface.withValues(alpha: 0.03),
            cs.onSurface.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Center(
        child: initial != null
            ? Text(
                initial,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              )
            : (showIcon
                ? HugeIcon(
                    icon: icon ?? HugeIcons.strokeRoundedImage01,
                    size: iconSize,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                  )
                : const SizedBox()),
      ),
    );
  }
}

/// 统一的封面容器：占位 → 淡入 → 失败可重试。
///
/// 之前各页面各写一套 `CachedNetworkImage` + `FileImage`，占位普遍是
/// `SizedBox()`，断网时就是「白卡片」。这里把三件事收口：
/// 1. 加载中永远有一张 [CoverPlaceholder] 顶着，不会白；
/// 2. 失败时在封面右下角给「重试」，点一下 evict 掉失败缓存重新拉；
/// 3. 成功走 [AnimatedImage] 的 200ms 淡入，和列表卡片观感一致。
class CoverBox extends StatefulWidget {
  const CoverBox({
    super.key,
    required this.image,
    this.label,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.retryable = true,
    this.failed = false,
    this.onFailed,
    this.showIcon = true,
    this.initialFontSize = 40,
    this.cacheWidth,
    this.cacheHeight,
  });

  /// 为 null 时只渲染占位（例如本地漫画记录丢失）。
  final ImageProvider? image;

  /// 占位用的文字来源（书名）。
  final String? label;

  final BoxFit fit;
  final FilterQuality filterQuality;

  /// 是否显示重试入口。列表里的小缩略图不需要（重试命中率低且太小），
  /// 大卡片才给。
  final bool retryable;

  /// 外部已知该封面加载失败（例如轮播每次切页都会重建整棵子树，
  /// 失败信息必须由调用方记住，否则会一遍遍从「加载中」重新开始）。
  final bool failed;

  /// 首次失败时回调，供调用方把「已失败」记在更长寿的 State 里。
  final VoidCallback? onFailed;

  /// 占位里是否画那颗图片图标。纯装饰背景（如主页轮播的堆叠卡）
  /// 传 false，只留一块底色。
  final bool showIcon;

  final double initialFontSize;

  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<CoverBox> createState() => _CoverBoxState();
}

class _CoverBoxState extends State<CoverBox> {
  /// 重试计数：换掉 [AnimatedImage] 的 key，逼它重新 resolve 一次。
  int _attempt = 0;
  late bool _failed = widget.failed;

  @override
  void didUpdateWidget(CoverBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _failed = widget.failed;
      _attempt = 0;
    } else if (widget.failed != oldWidget.failed) {
      _failed = widget.failed;
    }
  }

  void _retry() {
    // evict 只清内存缓存，App 自己的磁盘缩略图缓存保留 —— 磁盘有图时
    // 重试是一瞬间的事；真的没网，也只是再失败一次，不会更糟。
    widget.image?.evict();
    setState(() {
      _failed = false;
      _attempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final placeholder = CoverPlaceholder(
      label: widget.label,
      fontSize: widget.initialFontSize,
      showIcon: widget.showIcon,
    );

    if (image == null) return placeholder;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        placeholder,
        AnimatedImage(
          key: ValueKey('cover_${image.hashCode}_$_attempt'),
          image: image,
          fit: widget.fit,
          filterQuality: widget.filterQuality,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          // 占位由外层 Stack 提供；这里透明，避免把首字盖住。
          placeholder: const SizedBox.shrink(),
          errorWidget: const SizedBox.shrink(),
          onError: (_, __) {
            widget.onFailed?.call();
            if (!_failed && mounted) setState(() => _failed = true);
          },
        ),
        if (_failed && widget.retryable)
          Positioned(
            right: 8,
            bottom: 8,
            child: _CoverRetryButton(onTap: _retry),
          ),
      ],
    );
  }
}

class _CoverRetryButton extends StatelessWidget {
  const _CoverRetryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          // 半透明面板：不管封面是深是浅，按钮都能读出来。
          color: cs.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(kcRadius22),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              size: 13,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              'Retry'.tl,
              style: TextStyle(fontSize: kcFont11, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
