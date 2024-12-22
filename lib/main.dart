import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'secondPage.dart';
import 'services/api_service.dart';
import 'services/custom_animation.dart';
import 'services/error_handler.dart';
import 'services/sqlite_service.dart';

// =========================================== main() =========================================== //
//The main() function is the entry point of the application.
// After setting up the database environment, it runs the Flutter app starting with MyLoading() widget.
// Initialize FFI for sqflite on desktop (Windows)
//sqfliteFfiInit() sets up the environment so that sqflite can run using native code on non-mobile platforms.
// databaseFactory = databaseFactoryFfi; redirects all SQLite operations to the FFI-based implementation.
void main() {
  runApp(const MyLoading());
}

// =========================================== End of main() =========================================== //
//
//
//
// =========================================== MyLoading =========================================== //
// EasyLoading.instance... sets how the loading indicators look.
// MaterialApp(home: const MyApp()) launches the actual login interface (MyApp) after the loading configuration.
class MyLoading extends StatelessWidget {
  const MyLoading({super.key});

  @override
  Widget build(BuildContext context) {
    EasyLoading.instance
      ..displayDuration = const Duration(milliseconds: 2000)
      ..indicatorType = EasyLoadingIndicatorType.fadingCircle
      ..loadingStyle = EasyLoadingStyle.dark
      ..indicatorSize = 100.0
      ..radius = 10.0
      ..progressColor = Colors.yellow
      ..backgroundColor = Colors.green
      ..indicatorColor = Colors.yellow
      ..textColor = Colors.yellow
      ..maskColor = Colors.blue.withOpacity(0.5)
      ..userInteractions = true
      ..dismissOnTap = false
      ..customAnimation = CustomAnimation();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const MyApp(),
      builder: EasyLoading.init(),
    );
  }
}

// =========================================== End of MyLoading =========================================== //
//
//
//
// =========================================== Domain =========================================== //
// Domain is a simple model representing a domain option fetched from the server.
// key is presumably a label (in Arabic) for a particular election circle or domain.
// value is the actual base URL used for that domain.
// table_number might represent some table or code related to that domain.
// fromJson() allows easy creation of Domain objects from JSON maps (like those fetched from HTTP).
class Domain {
  final String key; // Arabic place name
  final String table_number;
  final String value; // URL

  const Domain(
      {required this.key, required this.value, required this.table_number});

  factory Domain.fromJson(Map<String, dynamic> json) {
    return Domain(
      key: json['key'],
      value: json['value'],
      table_number: json['table_number'],
    );
  }
}

// =========================================== End of Domain =========================================== //
//
//
//
// =========================================== MyApp =========================================== //
//MyApp is a stateful widget that represents the login screen.
// When it is initialized, it fetches a list of domains from a remote server and displays them in a dropdown.
// The user must choose a domain, enter their phone number and password, and then log in.
class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}
// =========================================== End of MyApp =========================================== //

class _MyAppState extends State<MyApp> {
  final SqliteService _sqliteService = SqliteService();
  final ApiService _apiService = ApiService();
  bool loadingDomains = true;
  List<Domain> domainList = [];
  TextEditingController nameController =
      TextEditingController(); // phone number
  TextEditingController passwordController = TextEditingController();
  bool validate = false;
  Domain? selectedDomain;
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();

  Future<void> initConnectivity() async {
    late ConnectivityResult result;

    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      developer.log('Couldn\'t check connectivity status', error: e);
      return;
    }

    if (!mounted) {
      return Future.value(null);
    }

    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    setState(() {
      _connectionStatus = result;
    });
  }

  // =========================================== initState() =========================================== //
  // Ensures Flutter bindings are initialized (usually needed before calling some platform methods).
  // Calls WakelockPlus.enable() to prevent the screen from sleeping.
  // Calls _fetchDomains() to load the domain data from the remote server.
  @override
  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized();
    WakelockPlus.enable();

    _sqliteService.initializeDB();

    initConnectivity();
    // runApp(MaterialApp(home: status.isEmpty ? const MyLoading() : const SecondPage()));

    _fetchDomains();
  }

  // =========================================== End of initState() =========================================== //
  //
  //
  //
  // =========================================== _fetchDomains() =========================================== //
  // Makes a network request via _apiService.postRequestNoBody() to fetch a list of domains.
  // If successful and data is a list, converts it into a list of Domain objects and updates the UI accordingly.
  // If there's an error, logs it and shows a user error message.
  Future<void> _fetchDomains() async {
    try {
      final response = await _apiService.postRequestNoBody(
          "https://q8votes.com/select_elections/select_election.php",
          contextName: "Fetch Domains");
      if (response is List) {
        setState(() {
          domainList = response.map((x) => Domain.fromJson(x)).toList();
          loadingDomains = false;
        });
      } else {
        throw Exception("Unexpected data format for domains");
      }
    } catch (e) {
      ErrorHandler.logError("fetchDomains", e);
      setState(() {
        loadingDomains = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ErrorHandler.showUserErrorMessage(
            context, "فشل تحميل البيانات، يرجى التحقق من اتصال الانترنت.");
      });
    }
  }

  // =========================================== End of _fetchDomains() =========================================== //
  //
  //
  //
  // =========================================== _login() =========================================== //
  // Ensures that a domain is selected and both phone and password fields are filled. If not, shows an error message.
  // Uses EasyLoading.show() to show a loading indicator while logging in.
  // Saves the selected domain’s URL in SharedPreferences.
  // Constructs the login API endpoint from the selected domain’s URL.
  // Calls the API with the phone and password, waits for a response:
  // If response == false, it means incorrect credentials; sets validate = true and shows an error.
  // If response is List, it means the server returned a list of users. Calls _insertUsersInBatches() to store them locally, sets loggedIn = true in prefs, and navigates to SecondPage.
  // If response is Map and has a msg key, shows that message to the user.
  // Otherwise, throws an exception.
  // On any exception, prints and logs the error, shows a user-friendly error message.
  // Finally, dismisses the loading indicator.
  Future<void> _login() async {
    if (selectedDomain == null ||
        nameController.text.isEmpty ||
        passwordController.text.isEmpty) {
      ErrorHandler.showUserErrorMessage(
          context, "الرجاء ادخال جميع البيانات واختيار الدائرة.");
      return;
    }

    EasyLoading.show(status: 'جاري تحميل البيانات...');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('domain', selectedDomain!.value);
    prefs.setString("observer_password", passwordController.text);

    try {
      String url = selectedDomain!.value.endsWith('/')
          ? "${selectedDomain!.value}APIS/select_api.php"
          : "${selectedDomain!.value}/APIS/select_api.php";

      final response = await _apiService.postRequest(
          url,
          {
            "number": nameController.text,
            "password": passwordController.text,
          },
          contextName: "Login API");

      if (response == false) {
        setState(() {
          validate = true;
        });
        ErrorHandler.showUserErrorMessage(
            context, "اسم المستخدم او كلمة المرور غير صحيحة.");
      } else if (response is Map &&
          response.containsKey("area_id") &&
          response.containsKey("data")) {
        int areaId = int.tryParse(response["area_id"].toString()) ?? 0;
        String search = response.containsKey("search_field")
            ? response["search_field"].toString()
            : "رقم القيد";
        int result = await _sqliteService.userLogged(
            nameController.text, selectedDomain!.value, areaId, search);
        var check = await _sqliteService.getUserLogged();

        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setInt("observer_area_id", areaId);
        var userData = response["data"];
        if (userData is List) {
          await _insertUsersInBatches(userData);
        }
        prefs.setBool('loggedIn', true);
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (ctx) => const SecondPage()));
      } else if (response is List) {
        await _insertUsersInBatches(response);
        prefs.setBool('loggedIn', true);
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (ctx) => const SecondPage()));
      } else if (response is Map) {
        if (response.containsKey('msg')) {
          ErrorHandler.showUserErrorMessage(
              context, response['msg'].toString());
        } else {
          ErrorHandler.showUserErrorMessage(
              context, "استجابة غير متوقعة من الخادم.");
        }
      } else {
        throw Exception("Unexpected response format during login");
      }
    } catch (e) {
      ErrorHandler.showUserErrorMessage(
          context, "حدث خطأ أثناء تسجيل الدخول. يرجى المحاولة مرة أخرى.");
    } finally {
      EasyLoading.dismiss();
    }
  }

  // =========================================== End of _login() =========================================== //
  //
  //
  //
  // =========================================== _insertUsersInBatches() =========================================== //
  // Loops through each user entry from the server’s response.
  // Converts them into User objects and inserts them into the local database using createUser().
  // After insertion, queries the database to count how many users have been stored and prints that result.
  Future<void> _insertUsersInBatches(List usersData) async {
    for (var userMap in usersData) {
      int parsedId = 0;
      int parsedVote = 0;
      int parsedRegisterNumber = 1;

      if (userMap['id'] != null) {
        parsedId = int.tryParse(userMap['id'].toString()) ?? 0;
      }

      if (userMap['vote'] != null) {
        parsedVote = int.tryParse(userMap['vote'].toString()) ?? 0;
      }

      if (userMap['registeration_number'] != null) {
        parsedRegisterNumber =
            int.tryParse(userMap['registeration_number'].toString()) ?? 1;
      }

      String reference = userMap['internal_reference']?.toString() ?? "";
      String normalizedFamilyname =
          userMap['normalized_familyname']?.toString() ?? "";
      String dob = userMap['dob']?.toString() ?? "";
      String votedAt = userMap['voted_at']?.toString() ?? "";
      String normalizedFullname =
          userMap['normalized_fullname']?.toString() ?? "";
      String address = userMap['address']?.toString() ?? "";
      String tableNumber = userMap['table_number']?.toString() ?? "";

      User user = User(
        id: parsedId,
        reference: reference,
        normalized_familyname: normalizedFamilyname,
        dob: dob,
        vote: parsedVote,
        voted_at: votedAt,
        normalized_fullname: normalizedFullname,
        address: address,
        table_number: tableNumber,
        registeration_number: parsedRegisterNumber,
      );
      await _sqliteService.createUser(user);
    }

    // After insertion, count how many users in the database and print it
    final db = await _sqliteService.initializeDB();
    final countResult = await db.rawQuery('SELECT count(id) as cnt FROM User');
  }

  // =========================================== End of _insertUsersInBatches() =========================================== //
  //
  //
  //
  // =========================================== build() =========================================== //
  // If loadingDomains is true, shows a loading screen with a CircularProgressIndicator.
  // Otherwise, builds the login form:
  // Shows a dropdown for selecting the domain (if domainList.isNotEmpty).
  // TextFields for phone number and password.
  // A login button that calls _login() when pressed.
  // All UI strings and field labels are in Arabic.
  @override
  Widget build(BuildContext context) {
    if (loadingDomains) {
      return Scaffold(
        appBar: AppBar(title: const Text("تحميل البيانات")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
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
      body: Container(
        color: const Color(0xFFFFFFFF),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Container(
            margin: const EdgeInsets.fromLTRB(0, 10, 0, 0),
            alignment: Alignment.center,
            color: const Color(0xFFFFFFFF),
            child: ListView(
              children: <Widget>[
                Image.asset(
                  'assets/images/logoq8votes_title.png',
                  fit: BoxFit.contain,
                  height: 32,
                ),
                Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                  padding: const EdgeInsets.all(10),
                  child: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF002938),
                        fontFamily: 'Baloo Bhaijaan 2'),
                  ),
                ),
                domainList.isNotEmpty
                    ? Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(10),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton2(
                            isExpanded: true,
                            hint: const Row(
                              children: [
                                Icon(
                                  Icons.arrow_drop_down_sharp,
                                  size: 16,
                                  color: Colors.black,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'اختر الدائرة',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF002938),
                                      fontFamily: 'Baloo Bhaijaan 2',
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            items: domainList.map((item) {
                              return DropdownMenuItem<Domain>(
                                alignment: Alignment.centerRight,
                                value: item,
                                child: Text(
                                  item.key,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              );
                            }).toList(),
                            value: selectedDomain,
                            onChanged: (value) {
                              setState(() {
                                selectedDomain = value as Domain;
                              });
                            },
                            buttonStyleData: ButtonStyleData(
                              height: 56,
                              padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: const Color(0xFFF6FBFF),
                              ),
                              elevation: 0,
                            ),
                            iconStyleData: const IconStyleData(
                              icon: Icon(
                                Icons.arrow_forward_ios_outlined,
                              ),
                              iconSize: 0,
                            ),
                            dropdownStyleData: DropdownStyleData(
                              padding: null,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white,
                              ),
                              elevation: 8,
                              scrollbarTheme: const ScrollbarThemeData(
                                radius: Radius.circular(40),
                              ),
                            ),
                            menuItemStyleData: const MenuItemStyleData(
                              height: 56,
                              padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                            ),
                          ),
                        ),
                      )
                    : Container(),
                const SizedBox(height: 6),
                Container(
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
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(
                            style: BorderStyle.none,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(
                            color: Color(0xFF2196F3),
                            width: 2.0,
                          ),
                        ),
                        labelText: 'رقم الهاتف',
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
                const SizedBox(height: 16),
                Container(
                  height: 56,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: TextField(
                      obscureText: true,
                      cursorColor: const Color(0xFF002938),
                      controller: passwordController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color(0xFFF6FBFF),
                        border: InputBorder.none,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(style: BorderStyle.none),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          borderSide: BorderSide(
                            color: Color(0xFF2196F3),
                            width: 2.0,
                          ),
                        ),
                        labelText: 'كلمة السر',
                        labelStyle: TextStyle(
                          fontSize: 16,
                          color: Color(0xFFB0C0C6),
                          fontWeight: FontWeight.w400,
                          fontFamily: 'Baloo Bhaijaan 2',
                        ),
                        floatingLabelStyle: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF2196F3),
                          fontWeight: FontWeight.w400,
                          fontFamily: 'Baloo Bhaijaan 2',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                validate
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(0, 0, 20, 0),
                        child: Text(
                          "يرجى التحقق من البيانات الخاصة بك",
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              fontFamily: 'Baloo Bhaijaan 2',
                              color: Colors.red,
                              fontWeight: FontWeight.w400,
                              fontSize: 16),
                        ),
                      )
                    : const SizedBox(),
                const SizedBox(height: 20),
                domainList.isNotEmpty
                    ? Container(
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
                          onPressed: _login,
                          child: const Text(
                            'تسجيل الدخول',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontFamily: 'Baloo Bhaijaan 2',
                              fontWeight: FontWeight.w500,
                              height: 0.08,
                            ),
                          ),
                        ),
                      )
                    : Container(),
              ],
            ),
          ),
        ),
      ),
    );
  }
// =========================================== End of build() =========================================== //
}
