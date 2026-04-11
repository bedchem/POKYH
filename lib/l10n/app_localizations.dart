import 'package:flutter/cupertino.dart';

enum AppLanguage {
  de,
  en,
  it;

  String get displayName {
    switch (this) {
      case AppLanguage.de:
        return 'Deutsch';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.it:
        return 'Italiano';
    }
  }

  String get code {
    switch (this) {
      case AppLanguage.de:
        return 'DE';
      case AppLanguage.en:
        return 'EN';
      case AppLanguage.it:
        return 'IT';
    }
  }

  String get flag {
    switch (this) {
      case AppLanguage.de:
        return '\u{1F1E9}\u{1F1EA}';
      case AppLanguage.en:
        return '\u{1F1EC}\u{1F1E7}';
      case AppLanguage.it:
        return '\u{1F1EE}\u{1F1F9}';
    }
  }
}

class AppLocalizations {
  final AppLanguage language;

  const AppLocalizations(this.language);

  String get langCode => language.name; // 'de', 'en', 'it'

  static AppLocalizations of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LocalizationsProvider>()!
        .localizations;
  }

  String get(String key) {
    return _translations[language]?[key] ?? _translations[AppLanguage.de]![key] ?? key;
  }

  String weekdayShort(int weekday) {
    const days = {
      AppLanguage.de: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
      AppLanguage.en: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      AppLanguage.it: ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'],
    };
    return days[language]![weekday - 1];
  }

  String weekdayLong(int weekday) {
    const days = {
      AppLanguage.de: [
        'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
        'Freitag', 'Samstag', 'Sonntag'
      ],
      AppLanguage.en: [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'
      ],
      AppLanguage.it: [
        'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì',
        'Venerdì', 'Sabato', 'Domenica'
      ],
    };
    return days[language]![weekday - 1];
  }

  String monthName(int month) {
    const months = {
      AppLanguage.de: [
        'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
      ],
      AppLanguage.en: [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ],
      AppLanguage.it: [
        'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
        'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'
      ],
    };
    return months[language]![month - 1];
  }

  static const Map<AppLanguage, Map<String, String>> _translations = {
    // ── Deutsch (Muttersprache) ─────────────────────────────────────────
    AppLanguage.de: {
      'menu': 'Speisekarte',
      'calendar': 'Kalender',
      'settings': 'Einstellungen',
      'all': 'Alle',
      'loading': 'Menü wird geladen...',
      'error_loading': 'Speisekarte konnte nicht geladen werden.',
      'retry': 'Erneut versuchen',
      'no_dishes_found': 'Keine Gerichte gefunden',
      'try_other_filters': 'Versuche andere Filter',
      'reset_filters': 'Filter zurücksetzen',
      'description': 'Beschreibung',
      'allergens': 'Allergene',
      'vegetarian': 'Vegetarisch',
      'vegan': 'Vegan',
      'min': 'Min',
      'kcal': 'kcal',
      'eur': 'EUR',
      'fat': 'Fett',
      'protein': 'Protein',
      'week': 'Woche',
      'month': 'Monat',
      'today': 'Heute',
      'no_dish_today': 'Kein Gericht geplant',
      'language': 'Sprache',
      'appearance': 'Erscheinungsbild',
      'about': 'Über die App',
      'app_name': 'ClassByte',
      'app_subtitle': 'Dein Mensaplan',
      'version': 'Version',
      'general': 'Allgemein',
      'no_dishes_this_week': 'Keine Gerichte diese Woche',
      'no_dishes_this_month': 'Keine Gerichte diesen Monat',
      'prep_time': 'Zubereitungszeit',
      'calories_label': 'Kalorien',
      'price_label': 'Preis',
      'this_week': 'Diese Woche',
      'no_dish_planned': 'Kein Gericht geplant',
      'notifications': 'Benachrichtigungen',
      'daily_reminder': 'Tägliche Erinnerung',
      'daily_reminder_desc': 'Erinnere mich ans Mittagessen',
      'new_dish_alert': 'Neue Gerichte',
      'new_dish_alert_desc': 'Benachrichtigung bei neuen Gerichten',
      'display': 'Anzeige',
      'show_calories': 'Kalorien anzeigen',
      'show_allergens': 'Allergene anzeigen',
      'show_prices': 'Preise anzeigen',
      'dietary': 'Ernährung',
      'vegetarian_only': 'Nur vegetarisch',
      'vegan_only': 'Nur vegan',
      'allergen_filter': 'Allergene ausblenden',
      'select_language': 'Sprache wählen',
      'done': 'Fertig',
      'data': 'Daten',
      'clear_cache': 'Cache leeren',
      'clear_cache_desc': 'Gespeicherte Bilder entfernen',
      'cache_cleared': 'Cache wurde geleert',
      'theme_system': 'System',
      'theme_light': 'Hell',
      'theme_dark': 'Dunkel',
      'offline_title': 'Keine Verbindung',
      'offline_message': 'Speisekarte konnte nicht geladen werden. Es werden gespeicherte Daten verwendet.',
    },

    // ── English (B2) ────────────────────────────────────────────────────
    AppLanguage.en: {
      'menu': 'Menu',
      'calendar': 'Calendar',
      'settings': 'Settings',
      'all': 'All',
      'loading': 'Loading menu...',
      'error_loading': 'Could not load the menu.',
      'retry': 'Try again',
      'no_dishes_found': 'No dishes found',
      'try_other_filters': 'Try different filters',
      'reset_filters': 'Reset filters',
      'description': 'Description',
      'allergens': 'Allergens',
      'vegetarian': 'Vegetarian',
      'vegan': 'Vegan',
      'min': 'min',
      'kcal': 'kcal',
      'eur': 'EUR',
      'fat': 'Fat',
      'protein': 'Protein',
      'week': 'Week',
      'month': 'Month',
      'today': 'Today',
      'no_dish_today': 'No dish planned',
      'language': 'Language',
      'appearance': 'Appearance',
      'about': 'About',
      'app_name': 'ClassByte',
      'app_subtitle': 'Your meal planner',
      'version': 'Version',
      'general': 'General',
      'no_dishes_this_week': 'No dishes this week',
      'no_dishes_this_month': 'No dishes this month',
      'prep_time': 'Prep time',
      'calories_label': 'Calories',
      'price_label': 'Price',
      'this_week': 'This Week',
      'no_dish_planned': 'No dish planned',
      'notifications': 'Notifications',
      'daily_reminder': 'Daily reminder',
      'daily_reminder_desc': 'Remind me about lunch',
      'new_dish_alert': 'New dishes',
      'new_dish_alert_desc': 'Notify me about new dishes',
      'display': 'Display',
      'show_calories': 'Show calories',
      'show_allergens': 'Show allergens',
      'show_prices': 'Show prices',
      'dietary': 'Dietary',
      'vegetarian_only': 'Vegetarian only',
      'vegan_only': 'Vegan only',
      'allergen_filter': 'Hide allergens',
      'select_language': 'Select language',
      'done': 'Done',
      'data': 'Data',
      'clear_cache': 'Clear cache',
      'clear_cache_desc': 'Remove saved images',
      'cache_cleared': 'Cache cleared',
      'theme_system': 'System',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'offline_title': 'No Connection',
      'offline_message': 'Menu could not be loaded. Using saved data.',
    },

    // ── Italiano (A2) ───────────────────────────────────────────────────
    AppLanguage.it: {
      'menu': 'Menù',
      'calendar': 'Calendario',
      'settings': 'Impostazioni',
      'all': 'Tutti',
      'loading': 'Caricamento del menù...',
      'error_loading': 'Impossibile caricare il menù.',
      'retry': 'Riprova',
      'no_dishes_found': 'Nessun piatto trovato',
      'try_other_filters': 'Prova altri filtri',
      'reset_filters': 'Reimposta filtri',
      'description': 'Descrizione',
      'allergens': 'Allergeni',
      'vegetarian': 'Vegetariano',
      'vegan': 'Vegano',
      'min': 'min',
      'kcal': 'kcal',
      'eur': 'EUR',
      'fat': 'Grassi',
      'protein': 'Proteine',
      'week': 'Settimana',
      'month': 'Mese',
      'today': 'Oggi',
      'no_dish_today': 'Nessun piatto previsto',
      'language': 'Lingua',
      'appearance': 'Aspetto',
      'about': 'Informazioni',
      'app_name': 'ClassByte',
      'app_subtitle': 'Il tuo piano mensa',
      'version': 'Versione',
      'general': 'Generale',
      'no_dishes_this_week': 'Nessun piatto questa settimana',
      'no_dishes_this_month': 'Nessun piatto questo mese',
      'prep_time': 'Tempo di preparazione',
      'calories_label': 'Calorie',
      'price_label': 'Prezzo',
      'this_week': 'Questa settimana',
      'no_dish_planned': 'Nessun piatto previsto',
      'notifications': 'Notifiche',
      'daily_reminder': 'Promemoria giornaliero',
      'daily_reminder_desc': 'Ricordami del pranzo',
      'new_dish_alert': 'Nuovi piatti',
      'new_dish_alert_desc': 'Avvisami per nuovi piatti',
      'display': 'Visualizzazione',
      'show_calories': 'Mostra calorie',
      'show_allergens': 'Mostra allergeni',
      'show_prices': 'Mostra prezzi',
      'dietary': 'Alimentazione',
      'vegetarian_only': 'Solo vegetariano',
      'vegan_only': 'Solo vegano',
      'allergen_filter': 'Nascondi allergeni',
      'select_language': 'Seleziona lingua',
      'done': 'Fatto',
      'data': 'Dati',
      'clear_cache': 'Svuota cache',
      'clear_cache_desc': 'Rimuovi immagini salvate',
      'cache_cleared': 'Cache svuotata',
      'theme_system': 'Sistema',
      'theme_light': 'Chiaro',
      'theme_dark': 'Scuro',
      'offline_title': 'Nessuna connessione',
      'offline_message': 'Impossibile caricare il menù. Vengono utilizzati i dati salvati.',
    },
  };
}

class LocalizationsProvider extends InheritedWidget {
  final AppLocalizations localizations;

  const LocalizationsProvider({
    super.key,
    required this.localizations,
    required super.child,
  });

  @override
  bool updateShouldNotify(LocalizationsProvider oldWidget) {
    return localizations.language != oldWidget.localizations.language;
  }
}
