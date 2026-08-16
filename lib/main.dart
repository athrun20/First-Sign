import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'models/capture_models.dart';
import 'models/saved_report.dart';
import 'screens/analysis_report_screen.dart';
import 'screens/contractor_dashboard_screen.dart';
import 'screens/demo_mode_screen.dart';
import 'screens/guided_capture_screen.dart';
import 'screens/home_screen.dart';
import 'screens/photo_review_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/report_history_screen.dart';
import 'services/branding_store.dart';
import 'widgets/brand_mark.dart';
import 'services/capture_draft_store.dart';
import 'services/finding_feedback_store.dart';
import 'services/lead_store.dart';
import 'services/local_blob_store.dart';
import 'services/onboarding_store.dart';
import 'services/profile_store.dart';
import 'services/report_store.dart';
import 'legal/product_copy.dart';
import 'theme/app_lux.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Native splash is Android/iOS only (pubspec: flutter_native_splash.web: false).
  // Web uses the HTML loading shell in web/index.html instead.
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  // Orientation lock is not supported on web; guard it.
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  // Binary photo store first (Hive / IndexedDB) — keeps prefs free of base64.
  await LocalBlobStore.instance.init();
  // Local-first stores (survive restarts).
  await Future.wait([
    LeadStore.instance.ensureLoaded(),
    ReportStore.instance.ensureLoaded(),
    BrandingStore.instance.ensureLoaded(),
    ProfileStore.instance.ensureLoaded(),
    CaptureDraftStore.instance.ensureLoaded(),
    OnboardingStore.instance.ensureLoaded(),
    FindingFeedbackStore.instance.ensureLoaded(),
  ]);
  runApp(const FirstSignApp());
}

class FirstSignApp extends StatelessWidget {
  const FirstSignApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppLux.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppLux.teal,
        primary: AppLux.charcoal,
        secondary: AppLux.teal,
        surface: AppLux.surface,
        brightness: Brightness.light,
      ),
    );

    final inter = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: AppLux.body, displayColor: AppLux.charcoal);

    return MaterialApp(
      title: ProductCopy.displayName,
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: inter,
        primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
        dividerColor: AppLux.border,
        cardColor: AppLux.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: AppLux.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            color: AppLux.charcoal,
            fontSize: AppLux.titleMd,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          iconTheme: const IconThemeData(color: AppLux.charcoal),
          actionsIconTheme: const IconThemeData(color: AppLux.charcoalMid),
        ),
        filledButtonTheme: FilledButtonThemeData(style: AppLux.primaryButton()),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppLux.teal,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppLux.teal.withValues(alpha: 0.45),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppLux.radiusXl),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: AppLux.secondaryButton(),
        ),
        textButtonTheme: TextButtonThemeData(style: AppLux.ghostButton()),
        chipTheme: ChipThemeData(
          backgroundColor: AppLux.bg,
          selectedColor: AppLux.tealMist,
          disabledColor: AppLux.borderSoft,
          labelStyle: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppLux.charcoal,
          ),
          secondaryLabelStyle: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppLux.teal,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLux.radiusLg),
            side: const BorderSide(
              color: AppLux.border,
              width: AppLux.borderWidth,
            ),
          ),
          side: const BorderSide(
            color: AppLux.border,
            width: AppLux.borderWidth,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppLux.charcoal,
          contentTextStyle: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 13.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLux.radiusLg),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppLux.teal,
          linearTrackColor: AppLux.border,
          circularTrackColor: AppLux.borderSoft,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppLux.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppLux.radius2xl),
            borderSide: const BorderSide(
              color: AppLux.border,
              width: AppLux.borderWidth,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppLux.radius2xl),
            borderSide: const BorderSide(
              color: AppLux.border,
              width: AppLux.borderWidth,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppLux.radius2xl),
            borderSide: const BorderSide(color: AppLux.teal, width: 1.2),
          ),
          hintStyle: GoogleFonts.inter(color: AppLux.muted, fontSize: 14),
          labelStyle: GoogleFonts.inter(color: AppLux.body, fontSize: 14),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppLux.teal,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/guided-capture':
            final args = settings.arguments;
            List<CapturePhoto> seed = const [];
            CaptureShotId? focus;
            var retakeMode = false;
            var singlePhotoMode = false;
            String? retakeTitle;
            if (args is Map) {
              final s = args['seed'];
              if (s is List<CapturePhoto>) seed = s;
              final f = args['focus'];
              if (f is CaptureShotId) focus = f;
              retakeMode = args['retakeMode'] == true;
              singlePhotoMode =
                  args['singlePhotoMode'] == true || args['quickScan'] == true;
              final t = args['findingTitle'];
              if (t is String && t.trim().isNotEmpty) retakeTitle = t.trim();
            }
            return MaterialPageRoute<List<CapturePhoto>?>(
              builder: (_) => GuidedCaptureScreen(
                seedPhotos: seed,
                focusSlot: focus,
                retakeMode: retakeMode,
                retakeFindingTitle: retakeTitle,
                singlePhotoMode: singlePhotoMode,
              ),
              settings: settings,
            );
          case '/photo-review':
            final args = settings.arguments;
            final photos = <CapturePhoto>[];
            var lowDetailHint = false;
            Object? photoArgs = args;
            if (args is Map) {
              photoArgs = args['photos'];
              lowDetailHint = args['lowDetailHint'] == true;
            }
            if (photoArgs is List<CapturePhoto>) {
              photos.addAll(photoArgs);
            } else if (photoArgs is List<XFile>) {
              photos.addAll(CapturePhoto.fromXFiles(photoArgs));
            } else if (photoArgs is List) {
              for (final item in photoArgs) {
                if (item is CapturePhoto) {
                  photos.add(item);
                } else if (item is XFile) {
                  photos.add(
                    CapturePhoto(
                      file: item,
                      label: 'Photo ${photos.length + 1}',
                      index: photos.length,
                    ),
                  );
                }
              }
            }
            return MaterialPageRoute<void>(
              builder: (_) => PhotoReviewScreen(
                photos: photos,
                lowDetailHint: lowDetailHint,
              ),
              settings: settings,
            );
          case '/saved-report':
            final saved = settings.arguments;
            if (saved is! SavedReport) return null;
            return MaterialPageRoute<void>(
              builder: (_) => AnalysisReportScreen(
                photos: saved.toCapturePhotos(),
                report: saved.report,
                savedReportId: saved.id,
              ),
              settings: settings,
            );
          case '/report-history':
            return MaterialPageRoute<void>(
              builder: (_) => const ReportHistoryScreen(),
              settings: settings,
            );
          case '/profile':
            return MaterialPageRoute<void>(
              builder: (_) => const ProfileScreen(),
              settings: settings,
            );
          case '/privacy':
            return MaterialPageRoute<void>(
              builder: (_) => const PrivacyScreen(),
              settings: settings,
            );
          case '/contractors':
            return MaterialPageRoute<void>(
              builder: (_) => const ContractorDashboardScreen(),
              settings: settings,
            );
          case '/demo':
            return MaterialPageRoute<void>(
              builder: (_) => const DemoModeScreen(),
              settings: settings,
            );
          default:
            return null;
        }
      },
    );
  }
}

/// Brief launch screen: app logo only on navy, then home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const assetPath = BrandMark.assetPath;
  static const backgroundColor = BrandMark.navy;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1200);
  static const _fadeDuration = Duration(milliseconds: 400);

  late final AnimationController _fadeController;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: _fadeDuration);
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    // Drop native splash once this frame is ready (logo on same navy).
    // Skip on web — removeSplashFromWeb is not generated when web: false.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        FlutterNativeSplash.remove();
      }
    });
    unawaited(_runSplash());
  }

  Future<void> _runSplash() async {
    await Future<void>.delayed(_holdDuration);
    if (!mounted) return;
    await _fadeController.forward();
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) {
            return const HomeScreen();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: SplashScreen.backgroundColor,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: SplashScreen.backgroundColor,
        body: AnimatedBuilder(
          animation: _fadeController,
          builder: (context, child) {
            return Opacity(opacity: _opacity.value, child: child);
          },
          child: const ColoredBox(
            color: SplashScreen.backgroundColor,
            child: Center(
              child: BrandMark(size: 128, radius: 28),
            ),
          ),
        ),
      ),
    );
  }
}
