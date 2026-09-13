import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'home_screen.dart';
import 'build_screen.dart';
import 'history_screen.dart';
import 'me_screen.dart';
import 'top_screen.dart';

/// 🏠 Shell utama — NavigationBar NATIVE (Material 3). 4 tab utama + layar
/// leaderboard dibuka dari Home/Profil. IndexedStack = state tiap tab aman.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _idx = 0;
  // globalkey biar layar lain bisa loncat ke tab Home (mis. abis submit build)
  final _homeKey = GlobalKey<HomeScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _idx,
        children: [
          HomeScreen(key: _homeKey, onOpenTop: _openTop),
          BuildScreen(onSubmitted: _goHome),
          const HistoryScreen(),
          const MeScreen(),
        ],
      ),
      floatingActionButton: _idx == 0 ? FloatingActionButton(
        backgroundColor: DzrTheme.seed,
        onPressed: () => _openTop(context),
        child: const Icon(Icons.emoji_events_rounded, color: Colors.white),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.build_rounded), selectedIcon: Icon(Icons.build_rounded), label: 'Build'),
          NavigationDestination(icon: Icon(Icons.history_rounded), selectedIcon: Icon(Icons.history_rounded), label: 'Riwayat'),
          NavigationDestination(icon: Icon(Icons.person_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Saya'),
        ],
      ),
    );
  }

  void _goHome() {
    setState(() => _idx = 0);
    _homeKey.currentState?.refresh();
  }

  void _openTop(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TopScreen()),
    );
  }
}
