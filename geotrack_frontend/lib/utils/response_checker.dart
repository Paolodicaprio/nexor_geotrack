import 'package:http/http.dart' as http;

/// Détecte si la session Odoo est invalide en analysant le contenu du body.
bool isSessionInvalid(http.Response response) {
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

