import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_model.dart';
import 'services/ads/google_ads.dart';
import 'services/analytics.dart';
import 'services/feedback.dart';
import 'services/purchases.dart';
import 'services/save_store.dart';
import 'ui/menu_screen.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A rendering or async error in an optional subsystem must not take the game down.
  FlutterError.onError = (details) => debugPrint('flutter error: ${details.exceptionAsString()}');
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('uncaught: $error');
    return true;
  };
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  const Analytics analytics = kDebugMode ? DebugAnalytics() : NoAnalytics();
  final model = AppModel(
    store: FileSaveStore(),
    audio: FlameAudioService(),
    haptics: Haptics(),
    ads: GoogleAdManager(analytics: analytics),
    analytics: analytics,
    purchases: StorePurchases(),
  );
  runApp(NovalithApp(model: model));
}

class NovalithApp extends StatefulWidget {
  const NovalithApp({super.key, required this.model, this.startServices = true});
  final AppModel model;

  /// Tests switch this off: no audio, ad or store plugins exist there.
  final bool startServices;

  @override
  State<NovalithApp> createState() => _NovalithAppState();
}

class _NovalithAppState extends State<NovalithApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    final model = widget.model;
    final locale = ui.PlatformDispatcher.instance.locale.languageCode;
    await model.load(locale);
    if (!widget.startServices) return;
    // Optional subsystems start in the background; the menu is already usable.
    unawaited(model.audio.init().then((_) => model.audio.setMusic(model.profile.music)).catchError((_) {}));
    unawaited(model.ads.init().catchError((_) {}));
    unawaited(model.purchases.init().catchError((_) {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final model = widget.model;
    if (state == AppLifecycleState.resumed) {
      model.audio.resumeAll();
    } else {
      model.audio.pauseAll();
      if (model.loaded) unawaited(model.save());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      model: widget.model,
      child: Builder(
        builder: (context) {
          final model = AppScope.of(context);
          return MaterialApp(
            title: 'Novalith',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: Palette.ink,
              fontFamily: 'Exo2',
              colorScheme: const ColorScheme.dark(
                primary: Palette.cyan,
                secondary: Palette.violet,
                surface: Palette.ink,
              ),
              splashFactory: NoSplash.splashFactory,
            ),
            builder: (context, child) => Directionality(
              textDirection: model.rtl ? TextDirection.rtl : TextDirection.ltr,
              // The layout is designed for the default text size up to a moderate enlargement.
              child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.25, child: child ?? const SizedBox()),
            ),
            home: model.loaded ? const MenuScreen() : const _Splash(),
          );
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Palette.ink,
      child: Center(child: Image(image: AssetImage('assets/brand/logo.png'), width: 180, height: 180)),
    );
  }
}
