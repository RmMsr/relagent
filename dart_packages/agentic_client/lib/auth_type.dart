enum AuthType {
  none, // No authentication required
  basic, // HTTP Basic authentication
  apiKey, // API key required (detection signal only, not persisted as auth type)
}
