import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Expense Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ExpenseHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ExpenseHomePage extends StatefulWidget {
  const ExpenseHomePage({super.key});

  @override
  State<ExpenseHomePage> createState() => _ExpenseHomePageState();
}

class _ExpenseHomePageState extends State<ExpenseHomePage> {
  final SmsQuery _query = SmsQuery();
  double _totalSpent = 0.0;
  Map<String, double> _categories = {'Food': 0, 'Transport': 0, 'Shopping': 0, 'Other': 0};
  bool _isLoading = false;

  Future<void> _readSms() async {
    var permission = await Permission.sms.status;
    if (permission.isGranted || await Permission.sms.request().isGranted) {
      setState(() => _isLoading = true);
      
      List<SmsMessage> messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 800, // Scans recent messages
      );

      double total = 0;
      Map<String, double> cats = {'Food': 0, 'Transport': 0, 'Shopping': 0, 'Other': 0};
      final RegExp amountRegex = RegExp(r"(?:rs\.?|inr)\s?(\d+(?:,\d+)?(?:\.\d+)?)", caseSensitive: false);

      for (var msg in messages) {
        String body = msg.body?.toLowerCase() ?? "";
        
        if (body.contains('debited') || body.contains('spent') || body.contains('paid') || body.contains('sent')) {
          var match = amountRegex.firstMatch(body);
          if (match != null) {
            String amountStr = match.group(1)?.replaceAll(',', '') ?? '0';
            double amount = double.tryParse(amountStr) ?? 0;
            total += amount;

            if (body.contains('zomato') || body.contains('swiggy') || body.contains('restaurant')) {
              cats['Food'] = (cats['Food'] ?? 0) + amount;
            } else if (body.contains('uber') || body.contains('ola') || body.contains('irctc') || body.contains('makemytrip')) {
              cats['Transport'] = (cats['Transport'] ?? 0) + amount;
            } else if (body.contains('amazon') || body.contains('flipkart') || body.contains('myntra')) {
              cats['Shopping'] = (cats['Shopping'] ?? 0) + amount;
            } else {
              cats['Other'] = (cats['Other'] ?? 0) + amount;
            }
          }
        }
      }

      setState(() {
        _totalSpent = total;
        _categories = cats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Tracker')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Spent', style: TextStyle(fontSize: 18, color: Colors.grey)),
                Text('₹${_totalSpent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                const Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: _categories.entries.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.key, style: const TextStyle(fontSize: 18)),
                      trailing: Text('₹${e.value.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    )).toList(),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    onPressed: _readSms,
                    child: const Text('Scan SMS for Expenses', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}