import 'package:flutter_riverpod/legacy.dart';

/// Which mode the auth screen should open in — set by whichever entry point
/// sent the user there (the landing page's "Get started" vs "Sign in"
/// buttons) so a "Sign in" tap doesn't land on the sign-up form. Defaults to
/// sign-up, matching the auth screen's original default before this existed.
final authInitialModeProvider = StateProvider<bool>((ref) => true);
