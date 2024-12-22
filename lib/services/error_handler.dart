// lib_improved/services/error_handler.dart
import 'package:flutter/material.dart';
import 'dart:developer' as developer;

class ErrorHandler {
  /// Logs a detailed error message for developers.
  static void logError(String context, dynamic error, [StackTrace? stackTrace]) {
    developer.log('Error in $context: $error', stackTrace: stackTrace);
  }

  /// Shows a user-friendly error message to the user.
  /// Call this method from within a widget's context.
  static void showUserErrorMessage(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('خطأ'),
          content: Text(message,
              style: const TextStyle(fontSize: 16, color: Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );
  }
}
