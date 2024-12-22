import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:edge_alerts/edge_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/error_handler.dart';
import 'services/sqlite_service.dart';

enum BestTutorSite { male, female, all }

// We'll store these locally once we get them from sendAllCandidatesToServer()
int number = 0;
int savedNumber = 0;

class SortPage extends StatefulWidget {
  const SortPage({Key? key}) : super(key: key);

  @override
  State<SortPage> createState() => _State();
}

class _State extends State<SortPage> {
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  final ScrollController controllerScroll = ScrollController();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<TextEditingController> _controllers = [];

  late SqliteService _sqliteService;
  List<Candidate> _candidates = [];
  @override
  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized();

    _sqliteService = SqliteService();
    _sqliteService.initializeDB();

    initConnectivity();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    // Step 1: fetch from server => populate DB => load from DB => setState
    _fetchAndPopulateCandidates();
  }

  // ---------------------------------------------------------------------------
  // 1) Fetch from server (select_electors.php),
  // 2) populateCandidatesTable(...),
  // 3) read all candidates from local DB,
  // 4) setState => update the UI
  // ---------------------------------------------------------------------------
  Future<void> _fetchAndPopulateCandidates() async {
    try {
      // 1) Call the server to get raw JSON
      final jsonResponse = await _callSelectElectorsApi();
      // 2) Populate local DB
      await _sqliteService.populateCandidatesTable(jsonResponse);
      // 3) Read all from DB
      List<Candidate> dbCandidates = await _sqliteService.getAllCandidates();
      // 4) Update UI
      setState(() {
        _candidates = dbCandidates;
        for (var e in dbCandidates) {
          _controllers.add(TextEditingController(text: e.votes.toString()));
          if (e.type == 1) {
            number += e.votes;
            savedNumber = number;
          }
        }
      });
    } catch (e, stack) {
      ErrorHandler.logError("_fetchAndPopulateCandidates", e, stack);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ErrorHandler.showUserErrorMessage(
            context, "تعذر تحميل المرشحين. يرجى المحاولة لاحقاً.");
      });
    }
  }

  // Helper function to call the server's select_electors.php
  // and return the raw body (which is presumably a JSON array).
  Future<String> _callSelectElectorsApi() async {
    // Get domain from DB
    var domainRows = await _sqliteService.getDomainLogged();
    if (domainRows.isEmpty) {
      throw Exception("No domain found in DB");
    }
    String domain = domainRows[0]["domain"]?.toString() ?? "";

    // 2) Retrieve area_id from SharedPreferences (or DB)
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int areaID = prefs.getInt("observer_area_id") ?? 0;

    // 3) Construct the request body with area_id
    Map<String, dynamic> requestBody = {
      "area_id": areaID,
    };
    final response = await http.post(
      Uri.parse("$domain/APIS/select_electors.php"),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      if (response.body.isNotEmpty) {
        return response
            .body; // We'll decode it later in populateCandidatesTable
      } else {
        throw Exception('Failed to load data: Empty response body');
      }
    } else {
      throw Exception('Failed to load data: ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // Called when user taps "+" or "-"
  // We do an async DB call to update candidate votes, then setState
  // ---------------------------------------------------------------------------
  Future<void> _adjustCandidateVotes(int index, int delta) async {
    try {
      int candidateId = _candidates[index].id;
      final newVal = await _sqliteService.updateCandidateVotes(candidateId, delta);
      if (newVal >= 0) {
        setState(() {
          _candidates[index].votes = newVal;
        });
      } else {
        ErrorHandler.showUserErrorMessage(context, "خطأ في تحديث الأصوات");
      }
    } catch (e, stack) {
      ErrorHandler.logError("_adjustCandidateVotes", e, stack);
      ErrorHandler.showUserErrorMessage(context, "تعذر تحديث الأصوات");
    }
  }

  Future<void> _changeCandidateVotes(int index, int delta) async {
    try {
      int candidateId = _candidates[index].id;
      final newVal = await _sqliteService.changeCandidateVotes(candidateId, delta);
      if (newVal >= 0) {
        setState(() {
          _candidates[index].votes = newVal;
        });
      } else {
        ErrorHandler.showUserErrorMessage(context, "خطأ في تحديث الأصوات");
      }
    } catch (e, stack) {
      ErrorHandler.logError("_adjustCandidateVotes", e, stack);
      ErrorHandler.showUserErrorMessage(context, "تعذر تحديث الأصوات");
    }
  }

  // ---------------------------------------------------------------------------
  // Called when user taps "تسجيل البيانات"
  // 1) sendAllCandidatesToServer() => returns { valid: X, invalid: Y }
  // 2) We display them in bottomNavigationBar
  // ---------------------------------------------------------------------------
  Future<void> _sendCandidates() async {
    final result = await _sqliteService.sendAllCandidatesToServer();
    setState(() {
      savedNumber = result["votes"] ?? 0;
    });
    // You could show a message if needed:
    if (number == 0) {
      ErrorHandler.showUserErrorMessage(
          context, "فشل إرسال البيانات أو لا توجد بيانات");
    } else {
      edgeAlert(
        context,
        title: 'تم تسجيل البيانات',
        backgroundColor: Colors.black,
        gravity: Gravity.bottom,
        icon: Icons.check_circle_rounded,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Returns a list of widgets for each candidate
  // ---------------------------------------------------------------------------
  List<Widget> publicElections() {
    List<Widget> elections = [];
    for (int i = 0; i < _candidates.length; i++) {
      elections.add(
        Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
          decoration: ShapeDecoration(
            color: const Color(0xFFF6FBFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.295,
            height: 188,
            decoration: ShapeDecoration(
              color: const Color(0xFFEDF7FE),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            child: Column(
              children: [
                // Top image region
                Container(
                  width: MediaQuery.of(context).size.width * 0.295,
                  height: 100,
                  decoration: const ShapeDecoration(
                    color: Color(0xFFEDF7FE),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(5),
                        topRight: Radius.circular(5),
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.295,
                          height: 100,
                          decoration: const ShapeDecoration(
                            color: Color(0xFFD9D9D9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(5),
                                topRight: Radius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 231,
                        height: 346,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: NetworkImage(_candidates[i].image),
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Candidate name
                Container(
                  width: double.infinity,
                  color: const Color(0xFF002938),
                  child: Text(
                    _candidates[i].name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFEDF7FE),
                      fontSize: 13,
                      fontFamily: 'Baloo Bhaijaan 2',
                      fontWeight: FontWeight.w600,
                      height: 0,
                    ),
                  ),
                ),
                // Votes count
                Container(
                  width: double.infinity,
                  height: 24,
                  color: const Color(0xFF7B8F97),
                  child: TextField(
                    cursorColor: const Color(0xFF002938),
                    controller: _controllers[i], // Set initial value from _candidates
                    keyboardType: TextInputType.number,  // Set keyboard type to number
                    textAlign: TextAlign.center,  // Center align text
                    style: const TextStyle(
                      color: Color(0xFFEDF7FE),
                      fontSize: 12,
                      fontFamily: 'Baloo Bhaijaan 2',
                      fontWeight: FontWeight.w600,
                      height: 4.8,
                    ),
                    onChanged: (value) async {
                      setState(() {
                        number = 0;
                        _candidates[i].votes = int.tryParse(value) ?? 0;
                        for (var e in _candidates) {
                          if (e.type == 1) {
                            number += e.votes;
                          }
                        }
                      });
                      await _changeCandidateVotes(i, _candidates[i].votes); // Update in DB
                    },
                  ),
                ),
                // +/- buttons
                SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // "-" button
                      SizedBox(
                        height: 24,
                        width: MediaQuery.of(context).size.width * 0.11,
                        child: ElevatedButton(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all(
                                const Color(0xFFDF0202)),
                            alignment: Alignment.center,
                            // Ensures content is centered
                            padding: WidgetStateProperty.all(EdgeInsets.zero),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          child: const Icon(Icons.remove,
                              color: Colors.white, size: 16),
                          onPressed: () async {
                            // Decrement in DB and update UI
                            if (_candidates[i].votes > 0) {
                              await _adjustCandidateVotes(i, -1);
                              number--;
                            } else {
                              ErrorHandler.showUserErrorMessage(
                                  context, "لا يمكن أن يكون التصويت سلبياً");
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // "+" button
                      SizedBox(
                        height: 24,
                        width: MediaQuery.of(context).size.width * 0.11,
                        child: ElevatedButton(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all(
                                const Color(0xFF2196F3)),
                            alignment: Alignment.center,
                            // Ensures content is centered
                            padding: WidgetStateProperty.all(EdgeInsets.zero),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 16),
                          onPressed: () async {
                            // Increment in DB and update UI
                            number++;
                            await _adjustCandidateVotes(i, 1);
                          },
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return [
      Wrap(
        spacing: 10,
        runSpacing: 0,
        alignment: WrapAlignment.center,
        children: elections,
      )
    ];
  }

  // ---------------------------------------------------------------------------
  // Connectivity
  // ---------------------------------------------------------------------------
  Future<void> initConnectivity() async {
    late ConnectivityResult result;
    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      developer.log("Couldn't check connectivity status", error: e);
      return;
    }

    if (!mounted) {
      return Future.value(null);
    }
    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    if (mounted) {
      setState(() {
        _connectionStatus = result;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        key: scaffoldKey,
        appBar: AppBar(
          backgroundColor: const Color(0xFF2196F3),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logoq8votes_appbar.png',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // Top bar: "اعادة الفرز" / "فرز المرشحين"
            Container(
              color: const Color(0xFFFFFFFF),
              constraints: const BoxConstraints(minHeight: 60, maxHeight: 60),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(5, 5, 10, 5),
                child: Row(
                  children: [
                    // "اعادة الفرز" => reset all votes to 0 in memory + DB
                    // Container(
                    //   height: 45,
                    //   padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                    //   child: ElevatedButton(
                    //     style: ButtonStyle(
                    //       backgroundColor: WidgetStateProperty.all(const Color(0xFFDF0202)),
                    //       shape: WidgetStateProperty.all(
                    //         RoundedRectangleBorder(
                    //           borderRadius: BorderRadius.circular(10),
                    //         ),
                    //       ),
                    //     ),
                    //     child: const Row(
                    //       children: [
                    //         Text(
                    //           'اعادة الفرز',
                    //           textAlign: TextAlign.center,
                    //           style: TextStyle(
                    //             color: Colors.white,
                    //             fontSize: 12,
                    //             fontFamily: 'Baloo Bhaijaan 2',
                    //             fontWeight: FontWeight.w500,
                    //           ),
                    //         ),
                    //         SizedBox(width: 4),
                    //         Icon(Icons.refresh, color: Colors.white, size: 16),
                    //       ],
                    //     ),
                    //     onPressed: () async {
                    //       // Reset votes to 0 in DB + UI
                    //       for (int i = 0; i < _candidates.length; i++) {
                    //         final candidateId = _candidates[i].id;
                    //         await _sqliteService.updateCandidateVotes(candidateId, -_candidates[i].votes);
                    //       }
                    //       // Then reload from DB
                    //       final fresh = await _sqliteService.getAllCandidates();
                    //       setState(() {
                    //         _candidates = fresh;
                    //       });
                    //       edgeAlert(
                    //         context,
                    //         title: 'تم اعادة الفرز بنجاح',
                    //         backgroundColor: Colors.black,
                    //         gravity: Gravity.bottom,
                    //         icon: Icons.check_circle_rounded,
                    //       );
                    //     },
                    //   ),
                    // ),
                    SizedBox(width: 40),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(
                          'فرز المرشحين',
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            color: Color(0xFF002938),
                            fontSize: 20,
                            fontFamily: 'Baloo Bhaijaan 2',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Middle: list of candidates
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.88,
                  alignment: Alignment.center,
                  color: const Color(0xFFFFFFFF),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 0, 9, 0),
                    child: ListView(
                      controller: controllerScroll,
                      children: <Widget>[
                        Column(children: publicElections()),
                        const SizedBox(height: 150),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            number != savedNumber
                ? Container(
                    height: 49,
                    decoration: const BoxDecoration(color: Color(0xFFDF0303)),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '“عدد المصوتين علي الهاتف مختلف عن عدد المصوتين على السيرفر” ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontFamily: 'Baloo Bhaijaan 2',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'يرجى الضغط على تسجيل البيانات لرفع الاصوات على السيرفر',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Baloo Bhaijaan 2',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.warning_amber_sharp,
                                color: Colors.white, size: 16),
                          ],
                        ),
                      ],
                    ),
                  )
                : Container(),
          ],
        ), // Bottom bar: total valid / invalid, plus "تسجيل البيانات"
        bottomNavigationBar: Container(
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'إجمالي الأصوات: $number',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF002938),
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    fontFamily: 'Baloo Bhaijaan 2',
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'الاصوات المسجلة: $savedNumber',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF002938),
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    fontFamily: 'Baloo Bhaijaan 2',
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.fromLTRB(5, 0, 10, 5),
                  child: ElevatedButton(
                    style: ButtonStyle(
                      backgroundColor: _connectionStatus != ConnectivityResult.none ? WidgetStateProperty.all(const Color(0xFF2196F3)) : WidgetStateProperty.all(const Color(0xFFB0C0C6)),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    onPressed: _connectionStatus != ConnectivityResult.none ? () {
                      setState(() {
                        _sendCandidates();
                      });
                    } : null,
                    child: const Text(
                      'تسجيل البيانات',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Baloo Bhaijaan 2',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// NOTE: The old "Candidate" class in this file is no longer used
// because we're using the one in sqlite_service.dart now.
