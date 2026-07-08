import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:kong_comic/utils/translations.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.onSuccessfulAuth});

  final void Function()? onSuccessfulAuth;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(SchedulerBinding.instance.lifecycleState != AppLifecycleState.paused) {
        auth();
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          SystemNavigator.pop();
        }
      },
      child: Material(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedSecurityLock, size: 36),
              const SizedBox(height: 16),
              Text("Authentication Required".tl),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: auth,
                child: Text("Continue".tl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void auth() async {
    var localAuth = LocalAuthentication();
    var canCheckBiometrics = await localAuth.canCheckBiometrics;
    if (!canCheckBiometrics && !await localAuth.isDeviceSupported()) {
      widget.onSuccessfulAuth?.call();
      return;
    }
    var isAuthorized = await localAuth.authenticate(
      localizedReason: "Please authenticate to continue".tl,
      authMessages: [
        AndroidAuthMessages(
          signInTitle: "需要身份验证",
          signInHint: "请验证身份",
          cancelButton: "取消",
        ),
        IOSAuthMessages(
          cancelButton: "取消",
          localizedFallbackTitle: "使用密码",
        ),
      ],
    );
    if (isAuthorized) {
      widget.onSuccessfulAuth?.call();
    }
  }
}
