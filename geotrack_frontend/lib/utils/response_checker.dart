import 'package:http/http.dart' as http;

/// Détecte si la session Odoo est invalide en analysant le contenu du body.
bool isSessionInvalid(http.Response response) {
  // Check for ALL redirect status codes (3xx) that might indicate session expiry
  // Including permanent redirects which Odoo might use for expired sessions
  if (response.statusCode >= 300 && response.statusCode < 400) {
    print('⚠️ Detected redirect (${response.statusCode}) - possible session expiry');
    return true;
  }
  
  // Check for authentication/authorization errors
  // 401: Unauthorized (missing/invalid credentials)
  // 403: Forbidden (might indicate expired session with valid-looking token)
  // 419: Session Expired (used by some frameworks)
  // 440: Login Timeout (IIS extended code)
  // 511: Network Authentication Required
  if (response.statusCode == 401 || 
      response.statusCode == 403 ||
      response.statusCode == 419 ||
      response.statusCode == 440 ||
      response.statusCode == 511) {
    print('⚠️ Detected auth error (${response.statusCode}) - session likely expired');
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

