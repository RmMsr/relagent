/// Default engine base URL for native (non-web) Dart targets. This package
/// is never built for web, so there is no platform-aware default to
/// resolve here — Flutter's web-aware default lives in the app itself.
const String defaultEngineBaseUrl = 'http://localhost:8000';
