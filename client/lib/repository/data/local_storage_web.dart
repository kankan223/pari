// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'local_storage.dart';

/// Web implementation backed by `window.localStorage`.
///
/// SECURITY CHECKPOINT: only opaque, non-PII entity data should be stored.
/// localStorage contents are visible to any JS on the same origin.
class WebLocalStorage implements LocalStorage {
  @override
  String? getItem(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  @override
  void setItem(String key, String value) {
    try {
      html.window.localStorage[key] = value;
    } catch (_) {
      // Quota exceeded or unavailable — swallow.
    }
  }

  @override
  void removeItem(String key) {
    try {
      html.window.localStorage.remove(key);
    } catch (_) {
      // Ignore.
    }
  }
}

LocalStorage createLocalStorage() => WebLocalStorage();
