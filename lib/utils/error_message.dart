String simplifyErrorMessage(Object? error) {
  if (error == null) return 'Unbekannter Fehler';

  var message = error is Error || error is Exception
      ? error.toString()
      : '$error';
  message = message.replaceAll('Exception: ', '').trim();

  const hostLookup = 'Failed host lookup';
  final hostIndex = message.indexOf(hostLookup);
  if (hostIndex >= 0) {
    return message.substring(0, hostIndex + hostLookup.length).trim();
  }

  final newlineIndex = message.indexOf('\n');
  if (newlineIndex >= 0) {
    message = message.substring(0, newlineIndex);
  }

  return message.trim();
}
