// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'error_handler.dart';
import 'dart:async';


class ApiService {
  Future<dynamic> postRequest(String url, Map<String, dynamic> body, {String contextName = "API call"}) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(body),
      );


      // Decode the response body as UTF-8 before jsonDecode
      String decodedBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        if (decodedBody.isEmpty) {
          throw Exception('Empty response body');
        }
        return jsonDecode(decodedBody);
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } catch (e, stack) {

      ErrorHandler.logError(contextName, e, stack);
      rethrow;
    }
  }

  Future<dynamic> postRequestNoBody(String url, {String contextName = "API call"}) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json; charset=UTF-8'},
      );

      // Decode the response body as UTF-8
      String decodedBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        if (decodedBody.isEmpty) {
          throw Exception('Empty response body');
        }
        return jsonDecode(decodedBody);
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } catch (e, stack) {
      ErrorHandler.logError(contextName, e, stack);
      rethrow;
    }
  }
}
