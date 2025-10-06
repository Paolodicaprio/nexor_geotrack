import 'dart:io';
import 'package:http/http.dart' as http;

/// Classe utilitaire pour encapsuler les appels HTTP avec gestion centralisée des erreurs.
class SafeHttp {
  static Future<http.Response> request(
      Future<http.Response> Function() requestFn) async {
    try {
      // Exécution de la requête
      return await requestFn();
    } on HandshakeException catch (e) {
      print('SSL Handshake error: $e');
      throw Exception(
          'SSL Error: The server certificate is invalid. Please check the API URL.');
    } on SocketException catch (e) {
      print('No Internet connection: $e');
      throw Exception(
          'Unable to connect to the server. Check your Internet connection.');
    } on HttpException catch (e) {
      print('HTTP error: $e');
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e) {
      print('Bad response format: $e');
      throw Exception('Invalid server response.');
    } catch (e) {
      print('Unexpected error: $e');
      throw Exception('Unexpected error: $e');
    }
  }
}
