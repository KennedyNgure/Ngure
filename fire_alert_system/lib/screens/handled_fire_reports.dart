import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// PDF Packages
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class HandledFireReportsScreen extends StatefulWidget {
  final String? stationName;

  const HandledFireReportsScreen({super.key, required this.stationName});

  @override
  State<HandledFireReportsScreen> createState() => _HandledFireReportsScreenState();
}

class _HandledFireReportsScreenState extends State<HandledFireReportsScreen> {
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  bool _isGeneratingPdf = false;

  /// 🛡️ Simplifies text and removes characters that crash PDF engines
  String _cleanText(dynamic text) {
    if (text == null) return "N/A";
    String s = text.toString();
    // Keep only basic keyboard characters
    return s.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  /// Format date for display and PDF
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "N/A";
    try {
      if (timestamp is Timestamp) {
        return DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate());
      }
      return timestamp.toString();
    } catch (e) {
      return "N/A";
    }
  }

  /// 📄 SIMPLIFIED PDF GENERATOR
  Future<void> _generateSimplePdf(List<Map<String, dynamic>> reports) async {
    setState(() => _isGeneratingPdf = true);

    try {
      final pdf = pw.Document();

      // Define the table data beforehand to catch errors early
      final List<List<String>> tableData = [
        ['Date/Time', 'Description', 'Location'] // Header row
      ];

      for (var r in reports) {
        tableData.add([
          _cleanText(_formatDate(r['timestamp'])),
          _cleanText(r['description'] ?? 'No Description'),
          _cleanText("${r['ward'] ?? ''}, ${r['subcounty'] ?? ''}"),
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => [
            pw.Text("Handled Fire Reports: ${widget.stationName ?? 'All'}",
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text("Total Records: ${reports.length} | Exported: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}"),
            pw.SizedBox(height: 15),

            // The simplest possible table layout
            pw.TableHelper.fromTextArray(
              context: context,
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
              },
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Fire_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      debugPrint("PDF Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not generate PDF: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Handled Reports", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal[700],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("reports")
            .where("status", isEqualTo: "handled")
            .where("handledBy", isEqualTo: widget.stationName)
            .orderBy("timestamp", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error loading data"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // Search filtering logic
          final filteredDocs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final searchBase = "${data['description']} ${data['ward']} ${data['subcounty']}".toLowerCase();
            return searchBase.contains(searchQuery.toLowerCase());
          }).toList();

          return Column(
            children: [
              // Search Bar & Download Button
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.teal[700],
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => searchQuery = val),
                        decoration: InputDecoration(
                          hintText: "Search reports...",
                          fillColor: Colors.white,
                          filled: true,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: _isGeneratingPdf
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.picture_as_pdf, color: Colors.white, size: 30),
                      onPressed: (_isGeneratingPdf || filteredDocs.isEmpty)
                          ? null
                          : () {
                        final dataList = filteredDocs.map((d) => d.data() as Map<String, dynamic>).toList();
                        _generateSimplePdf(dataList);
                      },
                    )
                  ],
                ),
              ),

              // List of Results
              Expanded(
                child: filteredDocs.isEmpty
                    ? const Center(child: Text("No results found"))
                    : ListView.builder(
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final report = filteredDocs[index].data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(report['description'] ?? "No Description"),
                        subtitle: Text("${report['ward']} • ${_formatDate(report['timestamp'])}"),
                        leading: const Icon(Icons.assignment_turned_in, color: Colors.teal),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}