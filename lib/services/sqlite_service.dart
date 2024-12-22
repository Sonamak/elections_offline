// lib/services/sqlite_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'error_handler.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

//
// =================================== User Model =================================== //
class User {
  final int id;
  final String reference;
  final String normalized_familyname;
  final String dob;
  int vote;
  String voted_at;
  final String normalized_fullname;
  final String address;
  final String table_number;
  final int registeration_number;

  User({
    required this.id,
    required this.reference,
    required this.normalized_familyname,
    required this.dob,
    required this.vote,
    required this.voted_at,
    required this.normalized_fullname,
    required this.address,
    required this.table_number,
    required this.registeration_number,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic val, {int defaultValue = 0}) {
      if (val == null) return defaultValue;
      if (val is int) return val;
      if (val is String) {
        return int.tryParse(val) ?? defaultValue;
      }
      return defaultValue;
    }

    String parseString(dynamic val, {String defaultValue = ""}) {
      if (val == null) return defaultValue;
      if (val is String) return val;
      return val.toString();
    }

    return User(
      id: parseInt(map["id"], defaultValue: 0),
      reference: parseString(map["reference"]),
      normalized_familyname: parseString(map["normalized_familyname"]),
      dob: parseString(map["dob"]),
      vote: parseInt(map["vote"], defaultValue: 0),
      voted_at: parseString(map["voted_at"]),
      normalized_fullname: parseString(map["normalized_fullname"]),
      address: parseString(map["address"]),
      table_number: parseString(map["table_number"]),
      registeration_number: parseInt(map["registeration_number"], defaultValue: 1),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'reference': reference,
      'normalized_familyname': normalized_familyname,
      'dob': dob,
      'vote': vote,
      'voted_at': voted_at,
      'normalized_fullname': normalized_fullname,
      'address': address,
      'table_number': table_number,
      'registeration_number': registeration_number,
    };
  }
}
//
// =================================== End of User Model =================================== //
//
//
// =================================== Candidate Model =================================== //
class Candidate {
  final int id;       // Unique ID from server
  final String name;
  final String image;
  int votes;          // Current vote count
  final int type;     // 1=valid, 0=invalid (for invalid votes)

  Candidate({
    required this.id,
    required this.name,
    required this.image,
    required this.votes,
    required this.type,
  });

  factory Candidate.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic val, {int defaultValue = 0}) {
      if (val == null) return defaultValue;
      if (val is int) return val;
      if (val is String) {
        return int.tryParse(val) ?? defaultValue;
      }
      return defaultValue;
    }

    return Candidate(
      id: parseInt(map['id']),
      name: (map['name'] ?? "") as String,
      image: (map['image'] ?? "") as String,
      votes: parseInt(map['votes']),
      type: parseInt(map['type']), // default 0 if not found
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'image': image,
      'votes': votes,
      'type': type,
    };
  }
}
//
// =================================== End of Candidate Model =================================== //


class SqliteService {
  //
  // ============================ initializeDB() ============================ //
  Future<Database> initializeDB() async {
    String path = await getDatabasesPath();
    return openDatabase(
      join(path, 'database.db'),
      onCreate: (database, version) async {
        // Table #1: User
        await database.execute(
            "CREATE TABLE User ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "reference TEXT, "
                "normalized_familyname TEXT, "
                "dob TEXT, "
                "vote INTEGER, "
                "voted_at TEXT, "
                "normalized_fullname TEXT, "
                "address TEXT, "
                "table_number TEXT, "
                "registeration_number INTEGER)"
        );

        // Table #2: Login
        await database.execute(
            "CREATE TABLE Login ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "username TEXT, "
                "domain TEXT, "
                "status INTEGER,"
                "area_id INTEGER, "
                "search_field TEXT)"
        );

        // Table #3: Candidates
        // Add 'type' so we can differentiate valid vs invalid.
        await database.execute(
            "CREATE TABLE Candidates ("
                "id INTEGER PRIMARY KEY, "
                "name TEXT, "
                "image TEXT, "
                "votes INTEGER, "
                "type INTEGER)"
        );
      },
      version: 5, // Bump version if needed so 'onCreate' is triggered for new installs
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 5) {
          await database.execute(
              "CREATE TABLE IF NOT EXISTS Candidates ("
                  "id INTEGER PRIMARY KEY, "
                  "name TEXT, "
                  "image TEXT, "
                  "votes INTEGER, "
                  "type INTEGER)"
          );
        }
      },
    );
  }
  //
  // ============================ End of initializeDB() ============================ //


  //
  // ============================ userLogged() ============================ //
  Future<int> userLogged(String username, String domain, int areaId, String search) async {
    try {
      var db = await initializeDB();
      int result = await db.insert(
        'Login',
        {"username": username, "domain": domain, "area_id": areaId, "search_field": search},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return result;
    } catch (e, stack) {
      ErrorHandler.logError("userLogged", e, stack);
      return -1;
    }
  }
  //
  // ============================ End of userLogged() ============================ //


  //
  // ============================ getUserLogged() ============================ //
  Future<List<Map<String, Object?>>> getUserLogged() async {
    try {
      final db = await initializeDB();
      return await db.rawQuery('SELECT username, area_id FROM Login');
    } catch (e, stack) {
      ErrorHandler.logError("getUserLogged", e, stack);
      return [];
    }
  }
  //
  // ============================ End of getUserLogged() ============================ //


  //
  // ============================ getDomainLogged() ============================ //
  Future<List<Map<String, Object?>>> getDomainLogged() async {
    try {
      final db = await initializeDB();
      return await db.rawQuery('SELECT domain FROM Login');
    } catch (e, stack) {
      ErrorHandler.logError("getDomainLogged", e, stack);
      return [];
    }
  }
  //
  // ============================ End of getDomainLogged() ============================ //


  //
  // ============================ createUser() ============================ //
  Future<int> createUser(User user) async {
    try {
      var db = await initializeDB();
      return await db.insert(
        'User',
        user.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      ErrorHandler.logError("createUser", e, stack);
      return -1;
    }
  }
  //
  // ============================ End of createUser() ============================ //


  //
  // ============================ getUsers() ============================ //
  Future<List<Map<String, Object?>>> getUsers() async {
    try {
      final db = await initializeDB();
      return await db.rawQuery('SELECT count(id) FROM User');
    } catch (e, stack) {
      ErrorHandler.logError("getUsers", e, stack);
      return [];
    }
  }
  //
  // ============================ End of getUsers() ============================ //


  //
  // ============================ searchUsers() ============================ //
  Future<List<User>> searchUsers(String name, String registration, String family, int offset) async {
    try {
      final db = await initializeDB();

      // Normalize Arabic chars
      List<String> coded = ["ة", "أ", "إ", "آ", "ى", "ئ"];
      List<String> decoded = ["ه", "ا", "ا", "ا", "ي", "ي"];
      final map = Map.fromIterables(coded, decoded);

      // Process name
      final result = map.entries.fold(name, (prev, e) => prev.replaceAll(e.key, e.value));
      String fullname = result.trim().replaceAll(" ", "%");

      // Convert Arabic numerals
      const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
      const farsi = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
      for (int i = 0; i < english.length; i++) {
        registration = registration.replaceAll(farsi[i], english[i]);
      }

      // Process family
      final resultFamily = map.entries.fold(family, (prev, e) => prev.replaceAll(e.key, e.value));
      String familyName = resultFamily.trim().replaceAll(" ", "%");

      final queryResult = await db.rawQuery(
          'SELECT * FROM User '
              'WHERE normalized_fullname LIKE \'%$fullname%\' '
              'AND registeration_number LIKE \'${registration != "" ? int.parse(registration) : "%%"}\' '
              'AND normalized_familyname LIKE \'%$familyName%\' '
              'LIMIT $offset, 500'
      );

      return queryResult.map((e) => User.fromMap(e)).toList();
    } catch (e, stack) {
      ErrorHandler.logError("searchUsers", e, stack);
      return [];
    }
  }
  //
  // ============================ End of searchUsers() ============================ //


  //
  // ============================ votedNumber() ============================ //
  Future<List<Map<String, Object?>>> votedNumber() async {
    try {
      final db = await initializeDB();
      final result = await db.rawQuery('SELECT count(id) FROM User WHERE vote = 1');
      return result;
    } catch (e, stack) {
      ErrorHandler.logError("votedNumber", e, stack);
      return [];
    }
  }
  //
  // ============================ End of votedNumber() ============================ //


  //
  // ============================ votedUsers() ============================ //
  Future<List<Map<String, Object?>>> votedUsers() async {
    try {
      final db = await initializeDB();
      final result = await db.rawQuery('SELECT reference, vote FROM User');
      return result;
    } catch (e, stack) {
      ErrorHandler.logError("votedUsers", e, stack);
      return [];
    }
  }
  //
  // ============================ End of votedUsers() ============================ //


  //
  // ============================ updateUser() ============================ //
  Future<bool> updateUser(String reference, int vote) async {
    try {
      final db = await initializeDB();
      String formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

      await db.rawQuery(
        'UPDATE User SET vote = ?, voted_at = ? WHERE reference = ?',
        [vote, formattedDate, reference],
      );
      return true;
    } catch (e, stack) {
      ErrorHandler.logError("updateUser", e, stack);
      return false;
    }
  }
  //
  // ============================ End of updateUser() ============================ //


  //
  // ============================ sendToServer() ============================ //
  Future<List<Map<String, Object?>>> sendToServer(String reference, int vote) async {
    try {
      final db = await initializeDB();
      return await db.rawQuery('SELECT * FROM User WHERE vote = 1');
    } catch (e, stack) {
      ErrorHandler.logError("sendToServer", e, stack);
      return [];
    }
  }
  //
  // ============================ End of sendToServer() ============================ //


  //////////////////////////////////////////////////////////////////////////////
  //
  //  CANDIDATES LOGIC
  //
  //////////////////////////////////////////////////////////////////////////////


  //
  // ======================= populateCandidatesTable() ======================= //
  // 1) Accepts raw API response from `select_electors.php`.
  // 2) Decodes JSON => inserts or updates rows in 'Candidates'.
  // 3) Returns the list of inserted (or updated) candidates.
  //
  Future<List<Candidate>> populateCandidatesTable(dynamic apiResponse) async {
    try {
      final db = await initializeDB();

      // Decode if it's a JSON string
      Map<String, dynamic> decoded; // The server returns an object, not a top-level array
      if (apiResponse is String) {
        decoded = jsonDecode(apiResponse);
      } else {
        throw Exception("Unsupported format for candidate data (not a string)");
      }

      // Check if decoded['data'] exists and is a list
      if (decoded['data'] == null || decoded['data'] is! List) {
        throw Exception("No 'data' array found in the API response");
      }

      List<dynamic> candidatesJson = decoded['data'];

      List<Candidate> insertedCandidates = [];

      for (var item in candidatesJson) {
        try {
          final idVal = item["id"] ?? 0;
          final typeVal = item["type"] ?? 0;
          final votesVal = item["votes"] ?? 0;

          Candidate c = Candidate(
            id: idVal,
            name: item["name"] ?? "",
            image: item["image"] ?? "",
            votes: votesVal,
            type: typeVal,
          );

          await db.insert(
            'Candidates',
            c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          insertedCandidates.add(c);
        } catch (innerError, innerStack) {
        ErrorHandler.logError("populateCandidatesTable-inner", innerError, innerStack);
        // Optionally keep going or break
        break; // or continue;
      }
      }

      return insertedCandidates;
    } catch (e, stack) {
      ErrorHandler.logError("populateCandidatesTable", e, stack);
      return [];
    }
  }

  //
  // ======================= End of populateCandidatesTable() ======================= //


  //
  // ======================= getAllCandidates() ======================= //
  // Reads all candidates from DB, returns them as a List<Candidate>.
  //
  Future<List<Candidate>> getAllCandidates() async {
    try {
      final db = await initializeDB();
      final result = await db.query('Candidates');
      return result.map((map) => Candidate.fromMap(map)).toList();
    } catch (e, stack) {
      ErrorHandler.logError("getAllCandidates", e, stack);
      return [];
    }
  }
  //
  // ======================= End of getAllCandidates() ======================= //


  //
  // ======================= updateCandidateVotes() ======================= //
  // Applies a delta to the 'votes' column, returns new total votes.
  //
  Future<int> updateCandidateVotes(int candidateId, int delta) async {
    try {
      final db = await initializeDB();

      // Get current votes
      final currentData = await db.query(
        'Candidates',
        columns: ['votes'],
        where: 'id = ?',
        whereArgs: [candidateId],
        limit: 1,
      );

      if (currentData.isEmpty) {
        throw Exception("Candidate with id $candidateId not found");
      }

      int currentVotes = currentData.first['votes'] as int;
      int newVotes = currentVotes + delta;
      if (newVotes < 0) {
        newVotes = 0;  // or throw an exception if negative not allowed
      }

      await db.update(
        'Candidates',
        {'votes': newVotes},
        where: 'id = ?',
        whereArgs: [candidateId],
      );

      return newVotes;
    } catch (e, stack) {
      ErrorHandler.logError("updateCandidateVotes", e, stack);
      return -1; // Indicate error
    }
  }

  Future<int> changeCandidateVotes(int candidateId, int delta) async {
    try {
      final db = await initializeDB();

      // Get current votes
      final currentData = await db.query(
        'Candidates',
        columns: ['votes'],
        where: 'id = ?',
        whereArgs: [candidateId],
        limit: 1,
      );

      if (currentData.isEmpty) {
        throw Exception("Candidate with id $candidateId not found");
      }
      int newVotes = delta;
      if (newVotes < 0) {
        newVotes = 0;  // or throw an exception if negative not allowed
      }

      await db.update(
        'Candidates',
        {'votes': newVotes},
        where: 'id = ?',
        whereArgs: [candidateId],
      );

      return newVotes;
    } catch (e, stack) {
      ErrorHandler.logError("updateCandidateVotes", e, stack);
      return -1; // Indicate error
    }
  }

  //
  // ======================= End of updateCandidateVotes() ======================= //


  //
  // ======================= sendAllCandidatesToServer() ======================= //
  // Now returns a Map with { "valid": X, "invalid": Y }
  // after successfully sending to the server.
  //
  Future<Map<String, int>> sendAllCandidatesToServer() async {
    try {
      final db = await initializeDB();
      // Get all candidates
      final candidatesData = await db.query('Candidates');

      List<Map<String, dynamic>> candidateList = candidatesData.map((c) {
        return {
          "elector_id": c["id"],
          "votes": c["votes"] ?? 0,
        };
      }).toList();

      // Calculate local valid & invalid totals
      int votes = 0;
      for (var row in candidatesData) {
        int t = row["type"] as int? ?? 0;
        int v = row["votes"] as int? ?? 0;
        votes += v;
      }

      // Retrieve domain
      var domainInfo = await getDomainLogged();
      if (domainInfo.isEmpty) {
        throw Exception("No domain found in Login table");
      }
      String domain = domainInfo[0]["domain"]?.toString() ?? "";
      // Retrieve observer phone
      var observerInfo = await getUserLogged();
      if (observerInfo.isEmpty) {
        throw Exception("No observer found in Login table");

      }
      String observerPhone = observerInfo[0]["username"]?.toString() ?? "";
      int areaIdFromDB = observerInfo[0]["area_id"] is int ? observerInfo[0]["area_id"] as int : 0;
      // Retrieve password & area_id from SharedPreferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String password = prefs.getString("observer_password") ?? "unknown_password";
      int areaID = prefs.getInt("observer_area_id") ?? 0;
      Map<String, dynamic> requestBody = {
        "observer": observerPhone,
        "password": password,
        "area_id": areaID,
        "data": candidateList
      };

      final response = await http.post(
        Uri.parse("$domain/APIS/update_area_elector_api.php"),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json'
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {

        // Return local sums to update the UI
        return {
          "votes": votes,
        };
      } else {
        throw Exception("Server returned status code ${response.statusCode}, body=${response.body}");
      }
    } catch (e, stack) {
      ErrorHandler.logError("sendAllCandidatesToServer", e, stack);
      // Return an error-like map or throw
      return {
        "votes": 0,
      };
    }
  }
//
// ======================= End of sendAllCandidatesToServer() ======================= //
}
