import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/audio_provider.dart';
import 'library_tab.dart';
import 'playlist_tab.dart';
import 'settings_tab.dart';
import 'timer_tab.dart';
import 'video_converter_tab.dart';

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
      label: 'Library',
    ),
    _MainDestination(
      icon: Icons.graphic_eq_outlined,
      selectedIcon: Icons.graphic_eq_rounded,
      label: 'Sessions',
    ),
    _MainDestination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      label: 'Settings',
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
    final radius = BorderRadius.circular(isDesktop ? 28 : 0);

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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isDesktop ? 980 : double.infinity,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 24 : 0,
                          isDesktop ? 22 : 0,
                          isDesktop ? 24 : 0,
                          isDesktop ? 22 : 0,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(
                              alpha: isDesktop ? 0.9 : 1,
                            ),
                            borderRadius: radius,
                            border: isDesktop
                                ? Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.75,
                                    ),
                                  )
                                : null,
                            boxShadow: isDesktop
                                ? [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.08),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : null,
                          ),
                          child: isDesktop
                              ? ClipRRect(
                                  borderRadius: radius,
                                  child: _pages[index],
                                )
                              : _pages[index],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _openVideoConverterFloating(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final dialogWidth = size.width > 700 ? 620.0 : size.width - 20;
        final dialogHeight = size.height - 32;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 16,
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Stack(
              children: [
                const Positioned.fill(child: VideoConverterTab()),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _BottomRightCloseButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  String _timerFabLabel(AudioProvider provider) {
    final configured = provider.timerDuration != null;
    if (!configured) return 'Timer';

    final remaining = provider.timerRemaining ?? provider.timerDuration!;
    if (provider.timerActive) {
      return _fmtDuration(remaining);
    }
    if (remaining <= Duration.zero) {
      return 'Done';
    }
    if (provider.timerMode == TimerMode.trigger) {
      return 'Play + ${_fmtDuration(remaining)}';
    }
    return _fmtDuration(remaining);
  }

  Widget? _buildFloatingActionButton(
    BuildContext context,
    AudioProvider audioProvider,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Open timer settings',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: FloatingActionButton.extended(
              onPressed: () => _openTimerSettingsPage(context),
              backgroundColor: Colors.transparent,
              elevation: 0,
              highlightElevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              foregroundColor: cs.onPrimaryContainer,
              icon: const Icon(Icons.timer_rounded),
              label: Text(_timerFabLabel(audioProvider)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const capsuleRadius = 30.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 10 + bottomInset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(capsuleRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(capsuleRadius),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  height: 62,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  indicatorColor: cs.primary.withValues(alpha: 0.2),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final weight = states.contains(WidgetState.selected)
                        ? FontWeight.w700
                        : FontWeight.w600;
                    final color = states.contains(WidgetState.selected)
                        ? cs.onSurface
                        : cs.onSurfaceVariant;
                    return TextStyle(
                      color: color,
                      fontWeight: weight,
                      fontSize: states.contains(WidgetState.selected) ? 11 : 10,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final color = states.contains(WidgetState.selected)
                        ? cs.onSurface
                        : cs.onSurfaceVariant;
                    return IconThemeData(color: color);
                  }),
                ),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  child: NavigationBar(
                    selectedIndex: _currentIndex,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    onDestinationSelected: _switchPage,
                    destinations: _destinations
                        .map(
                          (item) => NavigationDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: item.label,
                          ),
                        )
                        .toList(),
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
                    'ASMR Player',
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
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            child: _DesktopQuickAction(
              icon: Icons.timer_rounded,
              title: _timerFabLabel(audioProvider),
              subtitle: 'Timer',
              onTap: () => _openTimerSettingsPage(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: _DesktopQuickAction(
              icon: Icons.video_library_rounded,
              title: 'Converter',
              subtitle: 'Extract audio',
              onTap: () => _openVideoConverterFloating(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= _desktopBreakpoint;
    final mobileFab = isDesktop
        ? null
        : _buildFloatingActionButton(context, audioProvider);
    final mobileBottomInset = MediaQuery.paddingOf(context).bottom;

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
                _buildDesktopNavigation(context, audioProvider),
                Expanded(child: _buildAnimatedBody(isDesktop: true)),
              ],
            )
          else
            _buildAnimatedBody(isDesktop: false),
          if (!isDesktop) _buildBottomBar(context),
        ],
      ),
      floatingActionButton: mobileFab == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: 68 + mobileBottomInset),
              child: mobileFab,
            ),
      bottomNavigationBar: null,
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
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _BottomRightCloseButton extends StatelessWidget {
  const _BottomRightCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: FloatingActionButton.small(
        heroTag: null,
        onPressed: onPressed,
        child: const Icon(Icons.close_rounded),
      ),
    );
  }
}
