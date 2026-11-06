part of 'settings_page.dart';

class NetworkSettings extends StatefulWidget {
  const NetworkSettings({super.key});

  @override
  State<NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends State<NetworkSettings> {
  String proxyType = '';
  String proxyHost = '';
  String proxyPort = '';
  String proxyUsername = '';
  String proxyPassword = '';
  final _proxyFormKey = GlobalKey<FormState>();

  String _toProxyStr() {
    if (proxyType == 'direct') return 'direct';
    if (proxyType == 'system') return 'system';
    // Read directly from the controllers so the default values shown in the
    // fields (e.g. 127.0.0.1 / 7890) are persisted even when the user does
    // not edit them before pressing Save.
    final user = _usernameController.text;
    final pass = _passwordController.text;
    final host = _hostController.text;
    final port = _portController.text;
    var res = '';
    if (user.isNotEmpty) {
      res += user;
      if (pass.isNotEmpty) res += ':$pass';
      res += '@';
    }
    res += host;
    if (port.isNotEmpty) res += ':$port';
    return res;
  }

  void _parseProxy(String proxy) {
    if (proxy == 'direct') {
      proxyType = 'direct';
      return;
    }
    if (proxy == 'system') {
      proxyType = 'system';
      return;
    }
    proxyType = 'manual';
    var parts = proxy.split('@');
    if (parts.length == 2) {
      var auth = parts[0].split(':');
      if (auth.length == 2) {
        proxyUsername = auth[0];
        proxyPassword = auth[1];
      }
      parts = parts[1].split(':');
      if (parts.length == 2) {
        proxyHost = parts[0];
        proxyPort = parts[1];
      }
    } else {
      parts = proxy.split(':');
      if (parts.length == 2) {
        proxyHost = parts[0];
        proxyPort = parts[1];
      }
    }
  }

  void _saveProxy() {
    appdata.settings['proxy'] = _toProxyStr();
    appdata.saveData();
  }

  // 代理配置输入框 controller（缓存 + dispose，避免 rebuild 丢输入/内存泄漏）
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    _parseProxy(appdata.settings['proxy']);
    // 默认值：首次切到「手动」时填上最常见的本地代理（Clash 默认 HTTP 端口 7890），
    // 已保存过其它值则保留。
    _hostController = TextEditingController(
      text: proxyHost.isNotEmpty ? proxyHost : "127.0.0.1",
    );
    _portController = TextEditingController(
      text: proxyPort.isNotEmpty ? proxyPort : "7890",
    );
    _usernameController = TextEditingController(text: proxyUsername);
    _passwordController = TextEditingController(text: proxyPassword);
    super.initState();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Network".tl)),
        _SettingPartTitle(
          title: "Proxy".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedForward01, size: 18),
        ),
        RadioGroup<String>(
          groupValue: proxyType,
          onChanged: (v) {
            setState(() => proxyType = v ?? proxyType);
            if (proxyType != 'manual') _saveProxy();
          },
          child: Column(
            children: [
              RadioListTile<String>(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                title: Text("Direct".tl),
                value: 'direct',
              ),
              RadioListTile<String>(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                title: Text("System".tl),
                value: 'system',
              ),
              RadioListTile<String>(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                title: Text("Manual".tl),
                value: 'manual',
              ),
            ],
          ),
        ).toSliver(),
        if (proxyType == 'manual')
          Form(
            key: _proxyFormKey,
            child: Column(
              children: [
                KcListTile(
                  title: TextField(
                    decoration: InputDecoration(
                      labelText: "Host".tl,
                      // M3 TextField 默认带 InputBorder.underline，会和这一行的
                      // KcRowDivider 发丝线叠成「深一条浅一条」的双线。去掉自带
                      // 下划线，只保留列表的分隔线。
                      border: InputBorder.none,
                    ),
                    controller: _hostController,
                    onChanged: (v) => proxyHost = v,
                  ),
                ),
                KcListTile(
                  title: TextField(
                    decoration: InputDecoration(
                      labelText: "Port".tl,
                      border: InputBorder.none,
                    ),
                    controller: _portController,
                    onChanged: (v) => proxyPort = v,
                    keyboardType: TextInputType.number,
                  ),
                ),
                KcListTile(
                  title: TextField(
                    decoration: InputDecoration(
                      labelText: "Username".tl,
                      border: InputBorder.none,
                    ),
                    controller: _usernameController,
                    onChanged: (v) => proxyUsername = v,
                  ),
                ),
                KcListTile(
                  title: TextField(
                    decoration: InputDecoration(
                      labelText: "Password".tl,
                      border: InputBorder.none,
                    ),
                    controller: _passwordController,
                    onChanged: (v) => proxyPassword = v,
                    obscureText: true,
                  ),
                  // 下一项是「保存」按钮，不是又一行，末行不画线。
                  showDivider: false,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(kcSpaceLg, kcSpaceSm, kcSpaceLg, kcSpaceSm),
                  child: Button.filled(
                    onPressed: () {
                      _saveProxy();
                      context.showMessage(message: "Saved".tl);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedSave, size: 18),
                        const SizedBox(width: 6),
                        Text("Save".tl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).toSliver(),
      ],
    );
  }
}
