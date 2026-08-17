import 'package:sherpa_voice/model_architecture.dart';

/// Architecture names this app's runtime actually knows how to build.
///
/// Single source of truth: dart_packages/sherpa_voice/lib/model_architecture.dart.
/// Anything else in the catalog is either 'unknown' (no information at all)
/// or a catalog-only descriptive label — a model we know the identity of but
/// can't run yet.
final Set<String> supportedArchitectures =
    ModelArchitecture.values.map((a) => a.name).toSet();
