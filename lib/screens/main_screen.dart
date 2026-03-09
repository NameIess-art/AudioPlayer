import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/app_language_provider.dart';
import '../providers/audio_provider.dart';
import 'library_tab.dart';
import 'playlist_tab.dart';
import 'settings_tab.dart';
import 'timer_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const Duration _pageTransitionDuration = Duration(milliseconds: 220);
  static const Curve _pageTransitionCurve = Curves.easeOutCubic;
  static const double _desktopBreakpoint = 980;

  int _currentIndex = 0;
  int? _previousIndex;
  int _transitionToken = 0;

  final List<Widget> _pages = const [
    LibraryTab(),
    PlaylistTab(),
    SettingsTab(),
  ];

  static const List<_MainDestination> _destinations = [
    _MainDestination(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
      labelKey: 'nav_library',
    ),
    _MainDestination(
      icon: Icons.graphic_eq_outlined,
      selectedIcon: Icons.graphic_eq_rounded,
      labelKey: 'nav_sessions',
    ),
    _MainDestination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      labelKey: 'nav_settings',
    ),
  ];

  void _switchPage(int index) {
    if (index == _currentIndex) return;
    final token = ++_transitionToken;
    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = index;
    });
    Future<void>.delayed(_pageTransitionDuration, () {
      if (!mounted || token != _transitionToken) return;
      setState(() {
        _previousIndex = null;
      });
    });
  }

  Widget _buildAnimatedBody({required bool isDesktop}) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(isDesktop ? 28 : 24);

    return Stack(
      fit: StackFit.expand,
      children: List.generate(_pages.length, (index) {
        final isCurrent = index == _currentIndex;
        final isPrevious = index == _previousIndex;
        final shouldShow = isCurrent || isPrevious;

        return Offstage(
          offstage: !shouldShow,
          child: TickerMode(
            enabled: shouldShow,
            child: IgnorePointer(
              ignoring: !isCurrent,
              child: AnimatedOpacity(
                opacity: isCurrent ? 1 : 0,
                duration: _pageTransitionDuration,
                curve: _pageTransitionCurve,
                child: AnimatedSlide(
                  offset: isCurrent ? Offset.zero : const Offset(-0.015, 0),
                  duration: _pageTransitionDuration,
                  curve: _pageTransitionCurve,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: isDesktop
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 980),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                22,
                                24,
                                22,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.9),
                                  borderRadius: radius,
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.08),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: radius,
                                  child: _pages[index],
                                ),
                              ),
                            ),
                          )
                        : _pages[index],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _openTimerSettingsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          body: const TimerTab(showHeader: true),
          floatingActionButton: _BottomRightCloseButton(
            onPressed: () => Navigator.of(pageContext).maybePop(),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        ),
      ),
    );
  }

  String _fmtDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }

  String _timerFabLabel(AudioProvider provider, AppLanguageProvider i18n) {
    final configured = provider.timerDuration != null;
    if (!configured) return i18n.tr('timer');

    final remaining = provider.timerRemaining ?? provider.timerDuration!;
    if (provider.timerActive) {
      return _fmtDuration(remaining);
    }
    if (remaining <= Duration.zero) {
      return i18n.tr('done');
    }
    if (provider.timerMode == TimerMode.trigger) {
      return i18n.tr('timer_play_plus', {'time': _fmtDuration(remaining)});
    }
    return _fmtDuration(remaining);
  }

  Widget? _buildFloatingActionButton(
    BuildContext context,
    AudioProvider audioProvider,
    AppLanguageProvider i18n,
  ) {
    if (_currentIndex == 1) {
      return Semantics(
        button: true,
        label: i18n.tr('open_timer_settings'),
        child: _GlassFloatingButton(
          icon: Icons.timer_rounded,
          label: _timerFabLabel(audioProvider, i18n),
          onPressed: () => _openTimerSettingsPage(context),
        ),
      );
    }

    return null;
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = context.watch<AppLanguageProvider>();
    final items = _destinations.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final selected = index == _currentIndex;
      final label = i18n.tr(item.labelKey);

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _switchPage(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: selected
                        ? cs.surface.withValues(alpha: 0.28)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? cs.outlineVariant.withValues(alpha: 0.45)
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected ? item.selectedIcon : item.icon,
                        size: 28,
                        color: selected ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: selected ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.surface.withValues(alpha: 0.34),
                        cs.surfaceContainerHighest.withValues(alpha: 0.16),
                      ],
                    ),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.2),
                        blurRadius: 34,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                    child: Row(children: items),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavigation(
    BuildContext context,
    AudioProvider audioProvider,
    AppLanguageProvider i18n,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 292,
      margin: const EdgeInsets.fromLTRB(16, 18, 8, 18),
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    i18n.tr('asmr_player'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: _currentIndex,
              onDestinationSelected: _switchPage,
              extended: true,
              minExtendedWidth: 256,
              useIndicator: true,
              groupAlignment: -0.86,
              destinations: _destinations
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(i18n.tr(item.labelKey)),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: _DesktopQuickAction(
              icon: Icons.timer_rounded,
              title: _timerFabLabel(audioProvider, i18n),
              subtitle: i18n.tr('timer'),
              onTap: () => _openTimerSettingsPage(context),
            ),
          ),
        ],
      ),
    );
  }

  double _mobileTimerButtonBottom(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return safeBottom + 90;
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final i18n = context.watch<AppLanguageProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= _desktopBreakpoint;
    final mobileFab = isDesktop
        ? null
        : _buildFloatingActionButton(context, audioProvider, i18n);

    return Scaffold(
      extendBody: !isDesktop,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AmbientBackground(),
          if (isDesktop)
            Row(
              children: [
                _buildDesktopNavigation(context, audioProvider, i18n),
                Expanded(child: _buildAnimatedBody(isDesktop: true)),
              ],
            )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                _buildAnimatedBody(isDesktop: false),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildBottomBar(context),
                ),
                if (mobileFab != null)
                  Positioned(
                    right: 16,
                    bottom: _mobileTimerButtonBottom(context),
                    child: mobileFab,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            cs.surfaceContainerHigh.withValues(alpha: 0.94),
            cs.surface,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -96,
            top: -64,
            child: _GlowOrb(
              color: cs.primary.withValues(alpha: 0.12),
              size: 260,
            ),
          ),
          Positioned(
            right: -72,
            bottom: -86,
            child: _GlowOrb(
              color: cs.tertiary.withValues(alpha: 0.1),
              size: 232,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}

class _DesktopQuickAction extends StatelessWidget {
  const _DesktopQuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHigh.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: cs.onSecondaryContainer, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainDestination {
  const _MainDestination({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
}

class _BottomRightCloseButton extends StatelessWidget {
  const _BottomRightCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<AppLanguageProvider>();
    return Semantics(
      button: true,
      label: i18n.tr('close'),
      child: FloatingActionButton.small(
        heroTag: null,
        onPressed: onPressed,
        child: const Icon(Icons.close_rounded),
      ),
    );
  }
}

class _GlassFloatingButton extends StatelessWidget {
  const _GlassFloatingButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surface.withValues(alpha: 0.46),
                cs.surfaceContainerHighest.withValues(alpha: 0.22),
              ],
            ),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.42),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
