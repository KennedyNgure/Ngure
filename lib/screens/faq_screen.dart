import 'package:flutter/material.dart';

class FAQScreen extends StatefulWidget {
  FAQScreen({Key? key}) : super(key: key);

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, String>> allFAQs = [
    {
      "q": "How do I log in as a fire station?",
      "a":
      "Only authorized fire stations are allowed to log in to this system.To access your account, simply enter: Station Name and Password.Ensure your credentials are correct before proceeding."
    },
{
"q": "What if I forget my login credentials?",
"a": "Only authorized fire stations can access the forgot password feature.\n\nIf you have forgotten your password:\n\n1. Click on \"Forgot Password\"\n2. Enter your Station Name\n3. You will receive a temporary password\n4. Use the temporary password to log in\n5. After logging in, go to your Profile and set a new password\n\nMake sure to update your password immediately after logging in for security purposes."
},
{
      "q": "How does the app send alerts?",
      "a":
      "The app uses Firebase real-time updates to instantly notify stations."
    },
    {
      "q": "Can multiple stations respond to the same alert?",
      "a":
      "Yes, multiple stations can coordinate depending on the severity."
    },
    {
      "q": "Is internet connection required?",
      "a":
      "Yes, an active internet connection is required for real-time alerts."
    },
  ];

  List<Map<String, String>> filteredFAQs = [];

  @override
  void initState() {
    super.initState();
    filteredFAQs = allFAQs;
  }

  void _filterFAQs(String query) {
    final results = allFAQs.where((faq) {
      final question = faq["q"]!.toLowerCase();
      final answer = faq["a"]!.toLowerCase();
      final input = query.toLowerCase();

      return question.contains(input) || answer.contains(input);
    }).toList();

    setState(() {
      filteredFAQs = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("FAQs"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 🔍 SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _filterFAQs,
              decoration: InputDecoration(
                hintText: "Search FAQs...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterFAQs("");
                  },
                )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // 📋 FAQ LIST
          Expanded(
            child: filteredFAQs.isEmpty
                ? const Center(child: Text("No results found"))
                : ListView.builder(
              itemCount: filteredFAQs.length,
              itemBuilder: (context, index) {
                final faq = filteredFAQs[index];
                return FAQItem(
                  question: faq["q"]!,
                  answer: faq["a"]!,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FAQItem extends StatelessWidget {
  final String question;
  final String answer;

  const FAQItem({
    Key? key,
    required this.question,
    required this.answer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(answer),
          ),
        ],
      ),
    );
  }
}