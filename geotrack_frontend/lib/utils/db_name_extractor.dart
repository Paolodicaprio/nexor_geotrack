String? extractDatabaseName(String apiUrl) {
  try {
    final uri = Uri.parse(apiUrl);
    final host = uri.host; // ex: nexor-dev-2124.dev.odoo.com

    // Si le domaine contient ".dev.odoo.com"
    if (host.contains(".dev.odoo.com")) {
      return host.split(".dev.odoo.com").first;
    }

    // Sinon, on peut juste prendre le premier segment avant le premier "."
    return host.split(".").first;
  } catch (e) {
    return null; // apiUrl invalide
  }
}