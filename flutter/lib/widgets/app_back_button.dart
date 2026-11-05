import 'package:flutter/material.dart';

/// A single, consistent back control for every pushed (non-tab) screen: the
/// default `BackButton`, styled by the app theme.
///
/// Always calls `Navigator.maybePop` — a real back navigation (preserving
/// whatever screen, filter, and scroll position was already there), never a
/// hard redirect to a bottom-nav tab.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) => const BackButton();
}
