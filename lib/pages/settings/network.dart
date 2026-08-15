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
    var res = '';
    if (proxyUsername.isNotEmpty) {
      res += proxyUsername;
      if (proxyPassword.isNotEmpty) res += ':$proxyPassword';
      res += '@';
    }
    res += proxyHost;
    if (proxyPort.isNotEmpty) res += ':$proxyPort';
    return res;
  }

  void _parseProxy(String proxy) {
    if (proxy == 'direct') { proxyType = 'direct'; return; }
    if (proxy == 'system') { proxyType = 'system'; return; }
    proxyType = 'manual';
    var parts = proxy.split('@');
    if (parts.length == 2) {
      var auth = parts[0].split(':');
      if (auth.length == 2) { proxyUsername = auth[0]; proxyPassword = auth[1]; }
      parts = parts[1].split(':');
      if (parts.length == 2) { proxyHost = parts[0]; proxyPort = parts[1]; }
    } else {
      parts = proxy.split(':');
      if (parts.length == 2) { proxyHost = parts[0]; proxyPort = parts[1]; }
    }
  }

  void _saveProxy() {
    appdata.settings['proxy'] = _toProxyStr();
    appdata.saveData();
  }

  // DNS overrides
  final _dnsOverrides = <(TextEditingController, TextEditingController)>[];

  // 代理配置输入框 controller（缓存 + dispose，避免 rebuild 丢输入/内存泄漏）
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    _parseProxy(appdata.settings['proxy']);
    _hostController = TextEditingController(text: proxyHost);
    _portController = TextEditingController(text: proxyPort);
    _usernameController = TextEditingController(text: proxyUsername);
    _passwordController = TextEditingController(text: proxyPassword);
    for (var entry in (appdata.settings['dnsOverrides'] as Map).entries) {
      if (entry.key is String && entry.value is String) {
        _dnsOverrides.add((
          TextEditingController(text: entry.key),
          TextEditingController(text: entry.value)
        ));
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    var map = <String, String>{};
    for (var entry in _dnsOverrides) {
      map[entry.$1.text] = entry.$2.text;
    }
    appdata.settings['dnsOverrides'] = map;
    appdata.saveData();
    JsEngine().resetDio();
    for (var entry in _dnsOverrides) {
      entry.$1.dispose();
      entry.$2.dispose();
    }
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                title: Text("Direct".tl),
                value: 'direct',
              ),
              RadioListTile<String>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                title: Text("System".tl),
                value: 'system',
              ),
              RadioListTile<String>(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  title: TextField(
                    decoration: InputDecoration(labelText: "Host".tl),
                    controller: _hostController,
                    onChanged: (v) => proxyHost = v,
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  title: TextField(
                    decoration: InputDecoration(labelText: "Port".tl),
                    controller: _portController,
                    onChanged: (v) => proxyPort = v,
                    keyboardType: TextInputType.number,
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  title: TextField(
                    decoration: InputDecoration(labelText: "Username".tl),
                    controller: _usernameController,
                    onChanged: (v) => proxyUsername = v,
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  title: TextField(
                    decoration: InputDecoration(labelText: "Password".tl),
                    controller: _passwordController,
                    onChanged: (v) => proxyPassword = v,
                    obscureText: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.icon(
                    onPressed: () { _saveProxy(); context.showMessage(message: "Saved".tl); },
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedSave, size: 18),
                    label: Text("Save".tl),
                  ),
                ),
              ],
            ),
          ).toSliver(),
        _SettingPartTitle(
          title: "DNS Overrides".tl,
          icon: HugeIcon(icon: HugeIcons.strokeRoundedGlobe02, size: 18),
        ),
        _SwitchSetting(
          title: "Enable DNS Overrides".tl,
          settingKey: "enableDnsOverrides",
        ).toSliver(),
        _SwitchSetting(
          title: "Server Name Indication".tl,
          settingKey: "sni",
        ).toSliver(),
        if (_dnsOverrides.isNotEmpty)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: context.colorScheme.outlineVariant,
          ).toSliver(),
        for (var i = 0; i < _dnsOverrides.length; i++) _buildDnsRow(i).toSliver(),
        TextButton.icon(
          onPressed: () {
            setState(() => _dnsOverrides.add((TextEditingController(), TextEditingController())));
          },
          icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
          label: Text("Add".tl),
        ).paddingHorizontal(16).toSliver(),
      ],
    );
  }

  Widget _buildDnsRow(int index) {
    var entry = _dnsOverrides[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Domain".tl,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              controller: entry.$1,
            ),
          ),
          SizedBox(
            height: 32,
            child: VerticalDivider(width: 1, color: context.colorScheme.outlineVariant),
          ),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "IP".tl,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              controller: entry.$2,
            ),
          ),
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
            onPressed: () => setState(() => _dnsOverrides.removeAt(index)),
          ),
        ],
      ),
    );
  }
}

class _DNSOverrides extends StatefulWidget {
  const _DNSOverrides();

  @override
  State<_DNSOverrides> createState() => __DNSOverridesState();
}

class __DNSOverridesState extends State<_DNSOverrides> {
  var overrides = <(TextEditingController, TextEditingController)>[];

  @override
  void initState() {
    for (var entry in (appdata.settings['dnsOverrides'] as Map).entries) {
      if (entry.key is String && entry.value is String) {
        overrides.add((
          TextEditingController(text: entry.key),
          TextEditingController(text: entry.value)
        ));
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    var map = <String, String>{};
    for (var entry in overrides) {
      map[entry.$1.text] = entry.$2.text;
      entry.$1.dispose();
      entry.$2.dispose();
    }
    appdata.settings['dnsOverrides'] = map;
    appdata.saveData();
    JsEngine().resetDio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "DNS Overrides".tl,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _SwitchSetting(
              title: "Enable DNS Overrides".tl,
              settingKey: "enableDnsOverrides",
            ),
            _SwitchSetting(
              title: "Server Name Indication".tl,
              settingKey: "sni",
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: 8),
              color: context.colorScheme.outlineVariant,
            ),
            for (var i = 0; i < overrides.length; i++) buildOverride(i),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  overrides
                      .add((TextEditingController(), TextEditingController()));
                });
              },
              icon: HugeIcon(icon: HugeIcons.strokeRoundedAddCircle, size: 18),
              label: Text("Add".tl),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildOverride(int index) {
    var entry = overrides[index];
    return Container(
      key: ValueKey(index),
      height: 48,
      margin: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colorScheme.outlineVariant,
          ),
          left: BorderSide(
            color: context.colorScheme.outlineVariant,
          ),
          right: BorderSide(
            color: context.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Domain".tl,
              ),
              controller: entry.$1,
            ).paddingHorizontal(8),
          ),
          Container(
            width: 1,
            color: context.colorScheme.outlineVariant,
          ),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "IP".tl,
              ),
              controller: entry.$2,
            ).paddingHorizontal(8),
          ),
          Container(
            width: 1,
            color: context.colorScheme.outlineVariant,
          ),
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18),
            onPressed: () {
              setState(() {
                overrides.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }
}
