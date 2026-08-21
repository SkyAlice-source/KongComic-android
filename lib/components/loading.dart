part of 'components.dart';

/// 判断错误是否由「未登录 / 未授权」引起。
///
/// 用于把漫画源返回的英文错误（如 "Not logged in" / "unauthorized" /
/// HTTP 401）替换为本地化的「需登录」提示，并在存在漫画源上下文时
/// 提供「去登录」入口。
bool isAuthError(String message) {
  final m = message.toLowerCase();
  return m.contains('not logged') ||
      m.contains('please log in') ||
      m.contains('please login') ||
      m.contains('login required') ||
      m.contains('log in required') ||
      m.contains('sign in') ||
      m.contains('signin') ||
      m.contains('unauthorized') ||
      m.contains('not authorized') ||
      m.contains('authorization failed') ||
      m.contains('auth failed') ||
      m.contains('login failed') ||
      m.contains('log in failed') ||
      m.contains('login error') ||
      m.contains('access denied') ||
      m.contains('access_denied') ||
      m.contains('forbidden') ||
      m.contains('token expired') ||
      m.contains('session expired') ||
      m.contains('login expired') ||
      m.contains('invalid token') ||
      m.contains('invalid credentials') ||
      m.contains('logged out') ||
      m.contains('401') ||
      m.contains('403') ||
      m.contains('未登录') ||
      m.contains('请登录') ||
      m.contains('需要登录') ||
      m.contains('需登录') ||
      m.contains('登陆') ||
      m.contains('登录已过期') ||
      m.contains('登录失效') ||
      m.contains('会话过期') ||
      m.contains('登录');
}

String _prettifyErrorMessage(String raw) {
  var msg = raw.replaceFirst(RegExp(r'^DioException\s*\[[^\]]+\]:\s*'), '');
  msg = msg.replaceFirst(RegExp(r'^Error:\s*SocketException:\s*'), '');

  if (isAuthError(msg)) {
    return "Login required".tl;
  }

  // 统一处理 "Invalid Status Code: 410" / "Invalid status code: 410"
  final invalidStatusMatch =
      RegExp(r'Invalid\s+[Ss]tatus\s+[Cc]ode:\s*(\d{3})').firstMatch(msg);
  if (invalidStatusMatch != null) {
    final code = int.tryParse(invalidStatusMatch.group(1)!);
    return _friendlyHttpStatus(code);
  }

  if (msg.contains('Connection reset by peer') ||
      msg.contains('连接被重置') ||
      msg.contains('Connection reset')) {
    return "Connection reset".tl;
  }
  if (msg.contains('timed out') ||
      msg.contains('Timeout') ||
      msg.contains('超时')) {
    return "Connection timed out".tl;
  }
  if (msg.contains('Connection terminated during handshake') ||
      msg.contains('handshake')) {
    return "Connection handshake failed".tl;
  }
  if (msg.contains('No route to host') ||
      msg.contains('No address associated with hostname') ||
      msg.contains('Bad address')) {
    return "Unable to connect server".tl;
  }
  if (msg.contains('Connection refused')) {
    return "Connection refused".tl;
  }
  if (msg.contains('Failed to fetch') ||
      msg.contains('NetworkError') ||
      msg.contains('Network Error')) {
    return "Network Error".tl;
  }
  if (msg.contains('HTTP')) {
    final status = RegExp(r'HTTP[^\s]*\s+(\d+)').firstMatch(msg);
    if (status != null) {
      final code = int.tryParse(status.group(1)!);
      return _friendlyHttpStatus(code);
    }
  }
  // 源解析返回空对象导致的 JS 属性访问错误（如 CopyManga loadInfo null）
  if (msg.contains("cannot read property") ||
      msg.contains("Cannot read properties") ||
      msg.contains("undefined is not an object") ||
      msg.contains("null is not an object") ||
      msg.contains("TypeError")) {
    final sourceMatch = RegExp(r'\(([^:]+):\d+:\d+\)').firstMatch(msg);
    final sourceName = sourceMatch?.group(1) ?? "Source";
    return "@source: Source returned empty data, the comic may have been removed or the source is temporarily unavailable."
        .tlParams({"source": sourceName});
  }
  // 服务器错误（5xx）兜底：源 JS 抛出的错误未必带 "HTTP" 字样，
  // 用 word-boundary 匹配裸状态码，避免误伤漫画名/章节里的数字。
  final low = msg.toLowerCase();
  final serverError = RegExp(r'\b(?:500|502|503|504)\b').firstMatch(low);
  if (serverError != null ||
      low.contains('bad gateway') ||
      low.contains('service unavailable') ||
      low.contains('internal server error') ||
      low.contains('server error')) {
    return "This is server-side error, please try again later. Do not report this issue."
        .tl;
  }
  if (low.contains('failed to fetch') ||
      low.contains('xmlhttprequest') ||
      low.contains('http request failed') ||
      low.contains('failed to load resource')) {
    return "Network Error".tl;
  }
  if (low.contains('unable to resolve host') ||
      low.contains('name or service not known') ||
      low.contains('no such host') ||
      low.contains('dns')) {
    return "Unable to connect server".tl;
  }
  if (low.contains('certificate') ||
      low.contains('ssl') ||
      low.contains('tls')) {
    return "SSL connection error".tl;
  }
  return msg;
}

String _friendlyHttpStatus(int? code) {
  if (code == null) return "Network Error".tl;
  if (code >= 500) {
    return "This is server-side error, please try again later. Do not report this issue."
        .tl;
  }
  final messages = <int, String>{
    400: "The Request is invalid.".tl,
    401: "The Request is unauthorized.".tl,
    402: "Payment required.".tl,
    403: "No permission to access the resource. Check your account or network.".tl,
    404: "Not found.".tl,
    405: "Method not allowed.".tl,
    406: "Not acceptable.".tl,
    408: "Request timeout.".tl,
    409: "Conflict.".tl,
    410: "The resource has been removed.".tl,
    429: "Too many requests. Please try again later.".tl,
  };
  return messages[code] ??
      "Server returned @code".tlParams({"code": code.toString()});
}

/// 统一加载指示器 —— 应用默认加载态的唯一实现。
///
/// 集中约定尺寸与线宽，替代各处 strokeWidth 不一（1.4/1.8/2/默认）的裸
/// [CircularProgressIndicator]。新加载态请优先使用本组件，保持全局一致。
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.size = 32, this.strokeWidth = 2});

  final double size;

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: strokeWidth),
      ),
    );
  }
}

class NetworkError extends StatelessWidget {
  const NetworkError({
    super.key,
    required this.message,
    this.retry,
    this.withAppbar = true,
    this.buttonText,
    this.action,
  });

  final String message;

  final void Function()? retry;

  final bool withAppbar;

  final String? buttonText;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    var cfe = CloudflareException.fromString(message);
    final cs = context.colorScheme;
    final displayMessage = _prettifyErrorMessage(
      cfe == null ? message : "Cloudflare verification required".tl,
    );
    Widget body = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAlertCircle,
              size: 44,
              color: cs.error,
            ),
            const SizedBox(height: 16),
            Text(
              "Error".tl,
              style: TextStyle(
                fontSize: kcSubtitle,
                fontWeight: FontWeight.w600,
                color: cs.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: kcBody,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            if (retry != null)
              if (cfe != null)
                FilledButton(
                  onPressed: () => passCloudflare(
                    CloudflareException.fromString(message)!,
                    retry!,
                  ),
                  child: Text('Verify'.tl),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (action != null)
                      action!.paddingRight(8),
                    FilledButton.tonal(
                      onPressed: retry,
                      child: Text(buttonText ?? 'Retry'.tl),
                    ),
                  ],
                ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                saveFile(
                  data: utf8.encode(Log().toString()),
                  filename: 'log.txt',
                );
              },
              child: Text("Export logs".tl),
            ),
          ],
        ),
      ),
    );
    if (withAppbar) {
      body = Column(
        children: [
          const Appbar(title: Text("")),
          Expanded(child: body),
        ],
      );
    }
    return Material(child: body);
  }
}

class ListLoadingIndicator extends StatelessWidget {
  const ListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 80,
      child: Center(child: FiveDotLoadingAnimation()),
    );
  }
}

class SliverListLoadingIndicator extends StatelessWidget {
  const SliverListLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // SliverToBoxAdapter can not been lazy loaded.
    // Use SliverList to make sure the animation can be lazy loaded.
    return SliverList.list(
      children: const [SizedBox(), ListLoadingIndicator()],
    );
  }
}

abstract class LoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool isLoading = false;

  S? data;

  String? error;

  Future<Res<S>> loadData();

  Future<Res<S>> loadDataWithRetry() async {
    int retry = 0;
    while (true) {
      var res = await loadData();
      if (res.success) {
        return res;
      } else {
        if (!mounted) return res;
        if (retry >= 3) {
          return res;
        }
        retry++;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  FutureOr<void> onDataLoaded() {}

  Widget buildContent(BuildContext context, S data);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildLoading() {
    return const AppLoadingIndicator();
  }

  void retry() {
    setState(() {
      isLoading = true;
      error = null;
    });
    loadDataWithRetry().then((value) async {
      if (value.success) {
        data = value.data;
        await onDataLoaded();
        setState(() {
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          error = value.errorMessage!;
        });
      }
    });
  }

  Widget buildError() {
    return NetworkError(message: error!, retry: retry);
  }

  @override
  @mustCallSuper
  void initState() {
    isLoading = true;
    Future.microtask(() {
      loadDataWithRetry().then((value) async {
        if (!mounted) return;
        if (value.success) {
          data = value.data;
          await onDataLoaded();
          setState(() {
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
            error = value.errorMessage!;
          });
        }
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (isLoading) {
      child = buildLoading();
    } else if (error != null) {
      child = buildError();
    } else {
      child = buildContent(context, data!);
    }

    return buildFrame(context, child) ?? child;
  }
}

abstract class MultiPageLoadingState<T extends StatefulWidget, S extends Object>
    extends State<T> {
  bool _isFirstLoading = true;

  bool _isLoading = false;

  List<S>? data;

  String? _error;

  int _page = 1;

  int? _maxPage;

  Future<Res<List<S>>> loadData(int page);

  Widget? buildFrame(BuildContext context, Widget child) => null;

  Widget buildContent(BuildContext context, List<S> data);

  bool get isLoading => _isLoading || _isFirstLoading;

  bool get isFirstLoading => _isFirstLoading;

  bool get haveNextPage => _maxPage == null || _page <= _maxPage!;

  void nextPage() {
    if (_maxPage != null && _page > _maxPage!) return;
    if (_isLoading) return;
    _isLoading = true;
    loadData(_page).then((value) {
      _isLoading = false;
      if (mounted) {
        if (value.success) {
          _page++;
          if (value.subData is int) {
            _maxPage = value.subData as int;
          }
          setState(() {
            data!.addAll(value.data);
          });
        } else {
          var message = value.errorMessage ?? "Network Error".tl;
          if (message.length > 20) {
            message = "${message.substring(0, 20)}...";
          }
          context.showMessage(message: message);
        }
      }
    });
  }

  void reset() {
    setState(() {
      _isFirstLoading = true;
      _isLoading = false;
      data = null;
      _error = null;
      _page = 1;
    });
    firstLoad();
  }

  void firstLoad() {
    Future.microtask(() {
      loadData(_page).then((value) {
        if (!mounted) return;
        if (value.success) {
          _page++;
          if (value.subData is int) {
            _maxPage = value.subData as int;
          }
          setState(() {
            _isFirstLoading = false;
            data = value.data;
          });
        } else {
          setState(() {
            _isFirstLoading = false;
            _error = value.errorMessage!;
          });
        }
      });
    });
  }

  @override
  void initState() {
    firstLoad();
    super.initState();
  }

  Widget buildLoading(BuildContext context) {
    return const AppLoadingIndicator();
  }

  Widget buildError(BuildContext context, String error) {
    return NetworkError(withAppbar: false, message: error, retry: reset);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isFirstLoading) {
      child = buildLoading(context);
    } else if (_error != null) {
      child = buildError(context, _error!);
    } else {
      child = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels ==
              notification.metrics.maxScrollExtent) {
            nextPage();
          }
          return false;
        },
        child: buildContent(context, data!),
      );
    }

    return buildFrame(context, child) ?? child;
  }
}

class FiveDotLoadingAnimation extends StatefulWidget {
  const FiveDotLoadingAnimation({super.key});

  @override
  State<FiveDotLoadingAnimation> createState() =>
      _FiveDotLoadingAnimationState();
}

class _FiveDotLoadingAnimationState extends State<FiveDotLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      upperBound: 6,
    )..repeat(min: 0, max: 5.2, period: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow,
    Colors.purple,
  ];

  static const _padding = 12.0;

  static const _dotSize = 12.0;

  static const _height = 24.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: _dotSize * 5 + _padding * 6,
          height: _height,
          child: Stack(children: List.generate(5, (index) => buildDot(index))),
        );
      },
    );
  }

  Widget buildDot(int index) {
    var value = _controller.value;
    var startValue = index * 0.8;
    return Positioned(
      left: index * _dotSize + (index + 1) * _padding,
      bottom:
          (math.sin(math.pi / 2 * (value - startValue).clamp(0, 2))) *
          (_height - _dotSize),
      child: Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(
          color: _colors[index],
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
