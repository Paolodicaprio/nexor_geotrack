import 'package:http/http.dart' as http;

/// Détecte si la session Odoo est invalide en analysant le contenu du body.
bool isSessionInvalid(http.Response response) {
  // Check for redirect status codes (3xx) that indicate session expiry in Odoo
  // Exclude 304 (Not Modified) as it's a caching response, not an auth issue
  if (response.statusCode >= 300 && response.statusCode < 400 && response.statusCode != 304) {
    print('⚠️ Detected redirect (${response.statusCode}) - session likely expired, will auto-reconnect');
    return true;
  }
  
  // Check for authentication/authorization errors
  // 401: Unauthorized (missing/invalid credentials)
  // 403: Forbidden (might indicate expired session with valid-looking token)
  // 419: Session Expired (used by some frameworks)
  // 440: Login Timeout (IIS extended code)
  // Note: 511 (Network Auth Required) is for captive portals, handled separately
  if (response.statusCode == 401 || 
      response.statusCode == 403 ||
      response.statusCode == 419 ||
      response.statusCode == 440) {
    print('⚠️ Detected auth error (${response.statusCode}) - session likely expired, will auto-reconnect');
    return true;
  }
  
  final lowerBody = response.body.toLowerCase();

  // Cas typiques observés dans Odoo quand le cookie est expiré :
  // - du HTML complet (avec <html> ou <script>…)
  // - la présence de `odoo.__session_info__`
  // - la variable `is_public` = true
  // - parfois un formulaire de login ou la balise <title>Login</title>
  return lowerBody.contains('<html') ||
      lowerBody.contains('odoo.__session_info__') ||
      lowerBody.contains('"is_public": true') ||
      lowerBody.contains('<title>login</title>');
}

/// Check if response has empty body (e.g., 204 No Content)
bool hasEmptyBody(http.Response response) {
  return response.body.isEmpty || response.statusCode == 204;
}

/// Check if response indicates captive portal / network authentication required
bool isCaptivePortal(http.Response response) {
  return response.statusCode == 511;
}

/// Check if response is a successful response (2xx)
bool isSuccessResponse(http.Response response) {
  return response.statusCode >= 200 && response.statusCode < 300;
}
