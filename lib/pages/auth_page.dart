import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:kong_comic/utils/translations.dart';
import 'package:kong_comic/components/components.dart';
import 'package:kong_comic/foundation/context.dart';
import 'package:kong_comic/foundation/log.dart';

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
      if (SchedulerBinding.instance.lifecycleState !=
          AppLifecycleState.paused) {
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
              Button.filled(onPressed: auth, child: Text("Continue".tl)),
            ],
          ),
        ),
      ),
    );
  }

  void auth() async {
    var localAuth = LocalAuthentication();
    // 能力查询本身也会抛（没有生物识别硬件、ROM 的 BiometricManager 报错）。
    // 这一步失败时宁可放行：这是 App 内的一道软锁，把用户永久锁在外面比
    // 少一次校验糟糕得多。
    bool canAuthenticate;
    try {
      canAuthenticate =
          await localAuth.canCheckBiometrics ||
          await localAuth.isDeviceSupported();
    } catch (e, s) {
      Log.error("Auth", "Failed to query biometric capability: $e", s);
      widget.onSuccessfulAuth?.call();
      return;
    }
    if (!canAuthenticate) {
      widget.onSuccessfulAuth?.call();
      return;
    }
    // 生物识别不是「调用必然成功」的 API：没有录入指纹、系统临时锁死
    // （连续失败）、厂商 ROM 的 BiometricPrompt 异常都会从这里抛
    // PlatformException。以前完全不接，异常被 runZonedGuarded 吞掉，界面
    // 表现是「点了继续没有任何反应」，用户被留在锁屏页出不去。
    bool isAuthorized;
    try {
      isAuthorized = await localAuth.authenticate(
        localizedReason: "Please authenticate to continue".tl,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: "Sign in".tl,
            signInHint: "Verify your identity".tl,
            cancelButton: "Cancel".tl,
          ),
          IOSAuthMessages(
            cancelButton: "Cancel".tl,
            localizedFallbackTitle: "Use password".tl,
          ),
        ],
      );
    } catch (e, s) {
      Log.error("Auth", "Failed to authenticate: $e", s);
      if (mounted) {
        context.showMessage(
          message: "Authentication failed. Please try again.".tl,
        );
      }
      return;
    }
    if (isAuthorized) {
      widget.onSuccessfulAuth?.call();
    }
  }
}
