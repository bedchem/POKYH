import '../services/api_client.dart';

String simplifyErrorMessage(Object? error) {
  if (error == null) return 'Unbekannter Fehler';

  if (error is ApiException) {
    switch (error.statusCode) {
      case 401:
        return 'Session abgelaufen. Bitte neu anmelden.';
      case 403:
        return 'Kein Zugriff (${error.message})';
      case 404:
        return 'Nicht gefunden (${error.message})';
      case 429:
        return 'Zu viele Anfragen. Bitte kurz warten.';
      case 500:
      case 502:
      case 503:
        return 'Server-Fehler. Bitte später erneut versuchen.';
      default:
        return error.message.isNotEmpty ? error.message : 'API-Fehler ${error.statusCode}';
    }
  }

  var message = error is Error || error is Exception
      ? error.toString()
      : '$error';
  message = message.replaceAll('Exception: ', '').trim();

  if (message.contains('TimeoutException') || message.contains('timed out')) {
    return 'Verbindung zum Server zu langsam. Bitte prüfe deine Internetverbindung.';
  }
  if (message.contains('SocketException') || message.contains('Failed host lookup') || message.contains('Network is unreachable')) {
    return 'Kein Internet. Bitte prüfe deine Verbindung.';
  }
  if (message.contains('Connection refused') || message.contains('Connection timed out')) {
    return 'Server nicht erreichbar. Bitte später erneut versuchen.';
  }

  final hostIndex = message.indexOf('Failed host lookup');
  if (hostIndex >= 0) {
    return 'Kein Internet. Bitte prüfe deine Verbindung.';
  }

  final newlineIndex = message.indexOf('\n');
  if (newlineIndex >= 0) {
    message = message.substring(0, newlineIndex);
  }

  return message.trim();
}
