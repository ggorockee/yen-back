import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/calculator/calculator_screen.dart';
import 'ui/dashboard/dashboard_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/shops/shops_screen.dart';

class YenBackApp extends ConsumerWidget {
  const YenBackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardingDoneProvider);
    return MaterialApp(
      title: '돌려받엔',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: onboarded ? const HomeShell() : const OnboardingScreen(),
    );
  }

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD7263D), brightness: b),
    useMaterial3: true,
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pages = [CalculatorScreen(), ShopsScreen(), DashboardScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _tab, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: '계산기'),
        NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: '매장'),
        NavigationDestination(
          icon: Icon(Icons.flight_takeoff_outlined),
          selectedIcon: Icon(Icons.flight_takeoff),
          label: '내 여행',
        ),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '설정'),
      ],
    ),
  );
}
