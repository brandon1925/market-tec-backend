import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/notificaciones_service.dart';
import 'side_drawer.dart';
import 'top_nav_bar.dart';

/// Estructura común de las pantallas internas:
/// Scaffold + TopNavBar + SideDrawer (solo en móvil) + detección de móvil.
///
/// ```dart
/// MainLayout(
///   activeRoute: 'Inicio',
///   builder: (context, isMobile) => ...,
/// )
/// ```
class MainLayout extends StatefulWidget {
  final String activeRoute;
  final Widget Function(BuildContext context, bool isMobile) builder;
  final Color backgroundColor;
  final Widget? floatingActionButton;

  /// Se llama cuando el TopNavBar avisa que cambió algo (por ejemplo el rol).
  /// Si es null, solo se reconstruye el layout.
  final VoidCallback? onStateChanged;

  const MainLayout({
    super.key,
    required this.activeRoute,
    required this.builder,
    this.backgroundColor = AppColors.background,
    this.floatingActionButton,
    this.onStateChanged,
  });

  static bool isMobileOf(BuildContext context) =>
      MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Cada cambio de pantalla revisa avisos nuevos y si la cuenta sigue
    // activa (si un admin la suspendió, aquí se cierra la sesión).
    NotificacionesService.instance.sincronizar();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MainLayout.isMobileOf(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: widget.backgroundColor,
      endDrawer: isMobile
          ? SideDrawer(
              activeRoute: widget.activeRoute,
              onStateChanged: widget.onStateChanged ?? () => setState(() {}),
            )
          : null,
      body: Column(
        children: [
          TopNavBar(
            activeRoute: widget.activeRoute,
            scaffoldKey: _scaffoldKey,
            isMobile: isMobile,
            onStateChanged: widget.onStateChanged ?? () => setState(() {}),
          ),
          Expanded(child: widget.builder(context, isMobile)),
        ],
      ),
      floatingActionButton: widget.floatingActionButton,
    );
  }
}

/// Contenido desplazable con el padding horizontal estándar (20 móvil / 60 escritorio).
class PageScroll extends StatelessWidget {
  final bool isMobile;
  final double verticalPadding;
  final Widget child;

  const PageScroll({
    super.key,
    required this.isMobile,
    required this.child,
    this.verticalPadding = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20.0 : 60.0,
          vertical: verticalPadding,
        ),
        child: child,
      ),
    );
  }
}

/// Dos paneles lado a lado en escritorio (con proporción flex) y apilados en móvil.
class ResponsiveSplit extends StatelessWidget {
  final bool isMobile;
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double spacing;
  final double? mobileSpacing;
  final CrossAxisAlignment mobileCrossAxisAlignment;

  const ResponsiveSplit({
    super.key,
    required this.isMobile,
    required this.left,
    required this.right,
    this.leftFlex = 7,
    this.rightFlex = 4,
    this.spacing = 32,
    this.mobileSpacing,
    this.mobileCrossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: mobileCrossAxisAlignment,
        children: [
          left,
          SizedBox(height: mobileSpacing ?? spacing),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        SizedBox(width: spacing),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }
}
