import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:edge_alerts/edge_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';
import 'services/error_handler.dart';
import 'services/sqlite_service.dart';
import 'sortingPage.dart'; // Make sure sortingPage.dart defines 'SortPage' widget

enum BestTutorSite { male, female, all }

int number = 0;
String savedNumber = "0";

class SecondPage extends StatefulWidget {
  const SecondPage({Key? key}) : super(key: key);

  @override
  State<SecondPage> createState() => _State();
}

class _State extends State<SecondPage> {
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  TextEditingController nameController = TextEditingController();
  TextEditingController numberController = TextEditingController();
  TextEditingController familyController = TextEditingController();

  final ScrollController controllerScroll = ScrollController();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  BestTutorSite? site = BestTutorSite.all;
  late SharedPreferences prefs;
  late SqliteService _sqliteService;
  late List<Map<String, dynamic>> observer = [
    {"search_field": ""}
  ];
  List<User> _users = [];

  bool isLoading = false; // loading indicator if needed

  @override
  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized();

    _sqliteService = SqliteService();
    _sqliteService.initializeDB();

    initConnectivity();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    voteUsers();
    getUserNumber();
    // controllerScroll.addListener(() {});
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> initConnectivity() async {
    late ConnectivityResult result;
    try {
      result = await _connectivity.checkConnectivity();
      observer = await _sqliteService.getUserLogged();
    } on PlatformException {
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

  Future<void> getUserNumber() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      savedNumber = prefs.getString("saved_number") ?? "0";
    });
  }

  Future<void> voteUsers() async {
    try {
      final data = await _sqliteService.votedNumber();
      setState(() {
        number = int.parse(data[0]['count(id)'].toString());
      });
    } catch (e) {
      ErrorHandler.logError("voteUsers", e);
    }
  }

  void searchUser(
      String name, String registration, String family, int offset) async {
    setState(() {
      isLoading = true;
      _users.clear();
    });

    try {
      final data =
          await _sqliteService.searchUsers(name, registration, family, offset);
      setState(() {
        _users = data;
      });
    } catch (e) {
      ErrorHandler.logError("searchUser", e);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ErrorHandler.showUserErrorMessage(
            context, "حدث خطأ أثناء البحث. يرجى المحاولة لاحقاً.");
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> getUserVoted(String reference, int vote) async {
    try {
      await _sqliteService.updateUser(reference, vote);
    } catch (e) {
      ErrorHandler.logError("getUserVoted", e);
    }
  }

  Future<void> _updateVote(User user, bool val) async {
    try {
      bool success =
          await _sqliteService.updateUser(user.reference, val ? 1 : 0);
      if (success) {
        setState(() {
          user.vote = val ? 1 : 0;
        });
        voteUsers();
      } else {
        ErrorHandler.showUserErrorMessage(
            context, "تعذر تحديث حالة التصويت. حاول مرة أخرى.");
      }
    } catch (e) {
      ErrorHandler.logError("updateVote", e);
      ErrorHandler.showUserErrorMessage(
          context, "حدث خطأ أثناء تحديث حالة التصويت.");
    }
  }

  Future<void> _sendDataToServer() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? domain = prefs.getString('domain');
      if (domain == null) throw Exception("Domain not found in preferences");

      final data = await _sqliteService.votedUsers();
      if (observer.isEmpty) throw Exception("No user logged in");

      final ApiService apiService = ApiService();

      var requestBody = {
        "data": data
            .map((e) => {"reference": e["reference"], "vote": e["vote"]})
            .toList(),
        "observer": observer[0]["username"]
      };

      developer.log("sendDataToServer: Request Body = $requestBody");
      final response = await apiService.postRequest(
        "$domain/APIS/update_api.php",
        requestBody,
        contextName: "Update Votes",
      );

      developer.log("sendDataToServer: raw response = $response");

      if (response is Map &&
          response.containsKey('data') &&
          response['data'] is Map) {
        final dataMap = response['data'];
        if (dataMap.containsKey('result_number')) {
          int resultNumber = dataMap['result_number'];
          prefs.setString('saved_number', resultNumber.toString());

          setState(() {
            savedNumber = resultNumber.toString();
          });
        } else {
          ErrorHandler.showUserErrorMessage(
              context, "No result_number in response data.");
        }
      } else {
        ErrorHandler.showUserErrorMessage(
            context, "Unexpected response format from server.");
      }

      if (response is Map &&
          response.containsKey('message') &&
          response['message'] != "0") {
        edgeAlert(
          context,
          title: 'تم تسجيل البيانات',
          backgroundColor: Colors.black,
          gravity: Gravity.bottom,
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e, stackTrace) {
      developer.log("Error in sendDataToServer: $e");
      developer.log("$stackTrace");
      ErrorHandler.logError("sendDataToServer", e, stackTrace);
      ErrorHandler.showUserErrorMessage(
          context, "تعذر تسجيل البيانات. يرجى المحاولة لاحقاً.");
    }
  }

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
            Container(
              color: const Color(0xFFFFFFFF),
              constraints: const BoxConstraints(
                minHeight: 275,
                maxHeight: 275,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 15, 15, 5),
                child: Container(
                  alignment: Alignment.center,
                  color: Colors.white,
                  child: ListView(
                    children: <Widget>[
                      Row(
                        children: [
                          Container(
                              height: 45,
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                              child: ElevatedButton(
                                style: ButtonStyle(
                                  backgroundColor: WidgetStateProperty.all(
                                      const Color(0xFFDF0202)),
                                  shape: WidgetStateProperty.all(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'انهاء التصويت',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontFamily: 'Baloo Bhaijaan 2',
                                    fontWeight: FontWeight.w500,
                                    height: 0.08,
                                  ),
                                ),
                                onPressed: () async {
                                  bool? confirmEnd = await showDialog<bool>(
                                    context: context,
                                    builder: (BuildContext dialogContext) {
                                      return AlertDialog(
                                        title: const Text(
                                          'تأكيد',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: Color(0xFF002938),
                                            fontSize: 20,
                                            fontFamily: 'Baloo Bhaijaan 2',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        content: const Text(
                                          'هل أنت متأكد من إنهاء التصويت؟',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: Color(0xFF002938),
                                            fontSize: 14,
                                            fontFamily: 'Baloo Bhaijaan 2',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            child: const Text(
                                              "لا",
                                              style: TextStyle(
                                                color: Color(0xFF2196F3),
                                                fontSize: 17,
                                                fontFamily: 'Baloo Bhaijaan 2',
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.of(dialogContext)
                                                  .pop(false);
                                            },
                                          ),
                                          TextButton(
                                            style: ButtonStyle(
                                              backgroundColor:
                                                  WidgetStateProperty.all(
                                                      const Color(0xFF2196F3)),
                                              shape: WidgetStateProperty.all(
                                                RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                            child: const Text(
                                              "نعم",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 17,
                                                fontFamily: 'Baloo Bhaijaan 2',
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.of(dialogContext)
                                                  .pop(true);
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  );

                                  if (confirmEnd == true) {
                                    SharedPreferences prefs = await SharedPreferences.getInstance();
                                    await prefs.setBool('election_ended', true);

                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const SortPage()),
                                    );
                                  }
                                },
                              )),
                          const SizedBox(width: 20),
                          const Expanded(
                            child: Directionality(
                              textDirection: TextDirection.rtl,
                              child: Text(
                                'تصويت الناخبين',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF002938),
                                  fontSize: 20,
                                  fontFamily: 'Baloo Bhaijaan 2',
                                  fontWeight: FontWeight.w600,
                                  height: 0.08,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                              child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: TextField(
                                  cursorColor: const Color(0xFF002938),
                                  controller: nameController,
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Color(0xFFF6FBFF),
                                    border: InputBorder.none,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      borderSide: BorderSide(
                                        style: BorderStyle.none,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      borderSide: BorderSide(
                                        color: Color(0xFF2196F3),
                                        width: 2.0,
                                      ),
                                    ),
                                    labelText: 'الإسم بالكامل',
                                    labelStyle: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Baloo Bhaijaan 2',
                                      fontSize: 16,
                                      color: Color(0xFFB0C0C6),
                                    ),
                                    floatingLabelStyle: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Baloo Bhaijaan 2',
                                      fontSize: 16,
                                      color: Color(0xFF2196F3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                              child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: TextField(
                                  cursorColor: const Color(0xFF002938),
                                  controller: familyController,
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Color(0xFFF6FBFF),
                                    border: InputBorder.none,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      borderSide: BorderSide(
                                        style: BorderStyle.none,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      borderSide: BorderSide(
                                        color: Color(0xFF2196F3),
                                        width: 2.0,
                                      ),
                                    ),
                                    labelText: 'اسم العائلة',
                                    labelStyle: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Baloo Bhaijaan 2',
                                      fontSize: 16,
                                      color: Color(0xFFB0C0C6),
                                    ),
                                    floatingLabelStyle: TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Baloo Bhaijaan 2',
                                      fontSize: 16,
                                      color: Color(0xFF2196F3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                              child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: TextField(
                                  cursorColor: const Color(0xFF002938),
                                  controller: numberController,
                                  textAlign: TextAlign.right,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFFF6FBFF),
                                    border: InputBorder.none,
                                    enabledBorder: const OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      borderSide: BorderSide(
                                        style: BorderStyle.none,
                                      ),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(10)),
                                      borderSide: BorderSide(
                                        color: Color(0xFF2196F3),
                                        width: 2.0,
                                      ),
                                    ),
                                    labelText: observer[0]["search_field"] ??
                                        'رقم القيد',
                                    labelStyle: const TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Baloo Bhaijaan 2',
                                      fontSize: 16,
                                      color: Color(0xFFB0C0C6),
                                    ),
                                    floatingLabelStyle: const TextStyle(
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Baloo Bhaijaan 2',
                                      fontSize: 16,
                                      color: Color(0xFF2196F3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                          height: 56,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                          child: ElevatedButton(
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(
                                  const Color(0xFF2196F3)),
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            child: const Text(
                              'بحث',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontFamily: 'Baloo Bhaijaan 2',
                                fontWeight: FontWeight.w500,
                                height: 0.08,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                controllerScroll.animateTo(0,
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.fastOutSlowIn);
                                searchUser(
                                    nameController.text,
                                    numberController.text,
                                    familyController.text,
                                    0);
                              });
                            },
                          )),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.58,
                  alignment: Alignment.center,
                  color: const Color(0xFFFFFFFF),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(25, 0, 25, 0),
                    child: ListView(
                      controller: controllerScroll,
                      children: <Widget>[
                        Container(
                            height: 56,
                            margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                            decoration: ShapeDecoration(
                              color: const Color(0xFFF6FBFF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              '(${_users.length}) النتائج',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF2196F3),
                                fontSize: 18,
                                fontFamily: 'Baloo Bhaijaan 2',
                                fontWeight: FontWeight.w500,
                                height: 3.3,
                              ),
                            )),
                        Column(
                          children: publicElections(),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            number.toString() != savedNumber
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
        ),
        bottomNavigationBar: Container(
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'عدد المصوتين: $number',
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
                  'المصوتين المسجلين: $savedNumber',
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
                        _sendDataToServer();
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
                    )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Container> publicElections() {
    List<Container> elections = [];

    for (var i = 0; i < _users.length; i++) {
      elections.add(
        Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
          decoration: ShapeDecoration(
            color: const Color(0xFFF6FBFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 15),
                child: Column(
                  children: [
                    Text(
                      _users[i].normalized_fullname,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Color(0xFF002938),
                        fontWeight: FontWeight.w400,
                        fontSize: 22,
                        fontFamily: 'Baloo Bhaijaan 2',
                      ),
                    ),
                    const Divider(
                      indent: 0,
                      endIndent: 0,
                      color: Color(0xFFE9F0F8),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                'رقم الصندوق: ${_users[i].registeration_number}',
                                style: const TextStyle(
                                  color: Color(0xFF002938),
                                  fontWeight: FontWeight.w400,
                                  fontSize: 16,
                                  fontFamily: 'Baloo Bhaijaan 2',
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.table_chart,
                                  size: 16, color: Color(0xFF2196F3)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'رقم الجدول: ${_users[i].table_number}',
                                style: const TextStyle(
                                  color: Color(0xFF002938),
                                  fontWeight: FontWeight.w400,
                                  fontSize: 16,
                                  fontFamily: 'Baloo Bhaijaan 2',
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.pivot_table_chart,
                                  size: 16, color: Color(0xFF2196F3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'تاريخ الميلاد: ${_users[i].dob}',
                          style: const TextStyle(
                            color: Color(0xFF002938),
                            fontWeight: FontWeight.w400,
                            fontSize: 16,
                            fontFamily: 'Baloo Bhaijaan 2',
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.date_range,
                            size: 16, color: Color(0xFF2196F3)),
                      ],
                    ),
                    const Divider(
                      indent: 0,
                      endIndent: 0,
                      color: Color(0xFFE9F0F8),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _users[i].vote == 1 ? 'تم التصويت' : 'لم يتم التصويت',
                          style: const TextStyle(
                            color: Color(0xFF002938),
                            fontWeight: FontWeight.w400,
                            fontSize: 16,
                            fontFamily: 'Baloo Bhaijaan 2',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FlutterSwitch(
                          activeColor: const Color(0xFF2196F3),
                          value: _users[i].vote == 1 ? true : false,
                          valueFontSize: 10.0,
                          width: 56,
                          height: 30,
                          borderRadius: 30.0,
                          showOnOff: false,
                          onToggle: (val) {
                            showAlertDialog(BuildContext context) {
                              Widget cancelButton = TextButton(
                                child: const Text(
                                  "الغاء",
                                  style: TextStyle(
                                    color: Color(0xFF2196F3),
                                    fontSize: 17,
                                    fontFamily: 'Baloo Bhaijaan 2',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                },
                              );
                              Widget continueButton = TextButton(
                                style: ButtonStyle(
                                  backgroundColor: WidgetStateProperty.all(
                                      const Color(0xFF2196F3)),
                                  shape: WidgetStateProperty.all(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  "تأكيد",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontFamily: 'Baloo Bhaijaan 2',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _updateVote(_users[i], val);
                                  });
                                  Navigator.of(context, rootNavigator: true)
                                      .pop();
                                },
                              );

                              AlertDialog alert = AlertDialog(
                                title: Text(
                                  _users[i].normalized_fullname,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Color(0xFF002938),
                                    fontSize: 20,
                                    fontFamily: 'Baloo Bhaijaan 2',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                content: const Text(
                                  "هل أنت متأكد أن هذا الناخب قد قام بالتصويت؟",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Color(0xFF002938),
                                    fontSize: 14,
                                    fontFamily: 'Baloo Bhaijaan 2',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                actions: [
                                  cancelButton,
                                  continueButton,
                                ],
                              );

                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return alert;
                                },
                              );
                            }

                            showAlertDialog(context);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return elections;
  }
}
