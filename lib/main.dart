import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// 1. THIS FUNCTION RUNS IN THE BACKGROUND AT 11 PM
@pragma('vm:entry-point')
Future<void> backgroundSyncAndNotify() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(const InitializationSettings(android: initSettingsAndroid));

  SmsQuery query = SmsQuery();
  List<SmsMessage> messages = await query.querySms(kinds: [SmsQueryKind.inbox], count: 800);
  final RegExp amountRegex = RegExp(r"(?:rs\.?|inr)\s?(\d+(?:,\d+)?(?:\.\d+)?)", caseSensitive: false);

  DateTime now = DateTime.now();
  String todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  double todayTotal = 0;

  for (var msg in messages) {
    DateTime d = msg.date ?? DateTime.now();
    String msgDayStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    
    if (msgDayStr == todayStr) {
      String body = msg.body?.toLowerCase() ?? "";
      if (body.contains('debited') || body.contains('spent') || body.contains('paid') || body.contains('sent')) {
        var match = amountRegex.firstMatch(body);
        if (match != null) {
          String amountStr = match.group(1)?.replaceAll(',', '') ?? '0';
          double amount = double.tryParse(amountStr) ?? 0;
          bool isInv = (body.contains('zerodha') || body.contains('groww') || body.contains('mutual fund') || body.contains('sip') || body.contains('fd'));
          
          if (!isInv) todayTotal += amount;
        }
      }
    }
  }

  if (todayTotal > 0) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'daily_report', 'Daily Expense Report',
      importance: Importance.max, priority: Priority.high,
    );
    await flutterLocalNotificationsPlugin.show(
      0, 'Daily Expense Report', 'You spent ₹${todayTotal.toStringAsFixed(2)} today.', const NotificationDetails(android: androidDetails),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(const InitializationSettings(android: initSettingsAndroid));
  runApp(const ExpenseTrackerApp());
}

class Expense {
  final int? id;
  final double amount;
  final String date;
  final String month;
  final String body;
  int isInvestment;

  Expense({this.id, required this.amount, required this.date, required this.month, required this.body, this.isInvestment = 0});

  Map<String, dynamic> toMap() => {'id': id, 'amount': amount, 'date': date, 'month': month, 'body': body, 'isInvestment': isInvestment};
}

class DBHelper {
  static Database? _db;
  static Future<Database> get db async {
    if (_db != null) return _db!;
    String path = await getDatabasesPath() + '/expenses.db';
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, amount REAL, date TEXT, month TEXT, body TEXT UNIQUE, isInvestment INTEGER)''');
    });
    return _db!;
  }
  static Future<void> insertExpense(Expense exp) async {
    final dbClient = await db;
    await dbClient.insert('expenses', exp.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  static Future<List<Expense>> getExpenses() async {
    final dbClient = await db;
    final maps = await dbClient.query('expenses', orderBy: 'date DESC, id DESC');
    return List.generate(maps.length, (i) => Expense(id: maps[i]['id'], amount: maps[i]['amount'], date: maps[i]['date'], month: maps[i]['month'], body: maps[i]['body'], isInvestment: maps[i]['isInvestment']));
  }
  static Future<void> toggleInvestment(int id, int currentVal) async {
    final dbClient = await db;
    await dbClient.update('expenses', {'isInvestment': currentVal == 0 ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced Tracker',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _isLoading = false;
  List<Expense> _expenses = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _expenses = await DBHelper.getExpenses();
    setState(() => _isLoading = false);
  }

  // 2. THIS SCHEDULES THE ALARM FROM THE UI
  Future<void> _scheduleDailyReport() async {
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
    
    DateTime now = DateTime.now();
    DateTime scheduledDate = DateTime(now.year, now.month, now.day, 23, 0); // 11 PM
    if (now.isAfter(scheduledDate)) scheduledDate = scheduledDate.add(const Duration(days: 1));

    await AndroidAlarmManager.periodic(
      const Duration(days: 1),
      0,
      backgroundSyncAndNotify,
      startAt: scheduledDate,
      exact: true,
      wakeup: true,
    );
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('11 PM Daily Report Scheduled!')));
  }

  Future<void> _syncSms() async {
    var permission = await Permission.sms.status;
    if (permission.isGranted || await Permission.sms.request().isGranted) {
      setState(() => _isLoading = true);
      List<SmsMessage> messages = await SmsQuery().querySms(kinds: [SmsQueryKind.inbox], count: 2000);
      final RegExp amountRegex = RegExp(r"(?:rs\.?|inr)\s?(\d+(?:,\d+)?(?:\.\d+)?)", caseSensitive: false);

      for (var msg in messages) {
        String body = msg.body?.toLowerCase() ?? "";
        if (body.contains('debited') || body.contains('spent') || body.contains('paid') || body.contains('sent')) {
          var match = amountRegex.firstMatch(body);
          if (match != null) {
            String amountStr = match.group(1)?.replaceAll(',', '') ?? '0';
            double amount = double.tryParse(amountStr) ?? 0;
            DateTime d = msg.date ?? DateTime.now();
            String dayStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
            String monthStr = "${d.year}-${d.month.toString().padLeft(2, '0')}";
            int isInv = (body.contains('zerodha') || body.contains('groww') || body.contains('mutual fund') || body.contains('sip') || body.contains('fd')) ? 1 : 0;
            await DBHelper.insertExpense(Expense(amount: amount, date: dayStr, month: monthStr, body: msg.body ?? "", isInvestment: isInv));
          }
        }
      }
      await _loadData();
    }
  }

  Widget _buildSummary(bool isMonthly) {
    Map<String, double> summary = {};
    Map<String, double> investments = {};
    for (var e in _expenses) {
      String key = isMonthly ? e.month : e.date;
      if (e.isInvestment == 1) {
        investments[key] = (investments[key] ?? 0) + e.amount;
      } else {
        summary[key] = (summary[key] ?? 0) + e.amount;
      }
    }
    List<String> keys = summary.keys.toSet().union(investments.keys.toSet()).toList()..sort((a, b) => b.compareTo(a));

    if (keys.isEmpty) return const Center(child: Text("No expenses recorded."));

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, index) {
        String key = keys[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Spent: ₹${(summary[key] ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                Text('Invested: ₹${(investments[key] ?? 0).toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactions() {
    if (_expenses.isEmpty) return const Center(child: Text("No expenses recorded."));
    return ListView.builder(
      itemCount: _expenses.length,
      itemBuilder: (context, index) {
        var e = _expenses[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            title: Text('₹${e.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${e.date}\n${e.body}', maxLines: 3, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: InkWell(
              onTap: () async {
                await DBHelper.toggleInvestment(e.id!, e.isInvestment);
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: e.isInvestment == 1 ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(e.isInvestment == 1 ? Icons.trending_up : Icons.money_off, color: e.isInvestment == 1 ? Colors.green : Colors.grey, size: 20),
                    const SizedBox(height: 4),
                    Text(e.isInvestment == 1 ? 'Invest' : 'Spend', style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(icon: const Icon(Icons.alarm_on), tooltip: 'Schedule 11 PM Report', onPressed: _scheduleDailyReport),
          IconButton(icon: const Icon(Icons.sync), tooltip: 'Scan SMS Now', onPressed: _syncSms)
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : 
            _currentIndex == 0 ? _buildSummary(false) :
            _currentIndex == 1 ? _buildSummary(true) :
            _buildTransactions(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Daily'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Monthly'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Transactions'),
        ],
      ),
    );
  }
}