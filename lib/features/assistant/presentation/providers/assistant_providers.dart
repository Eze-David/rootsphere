import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/assistant_service.dart';

/// AI Assistant client (Supabase Edge Function `assistant`).
final assistantServiceProvider = Provider<AssistantService>((ref) => AssistantService());
