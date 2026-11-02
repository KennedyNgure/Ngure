import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class FireReportsScreen extends StatefulWidget {
  final String filter; // "today", "week", "all"

  const FireReportsScreen({super.key, required this.filter});

  @override
  State<FireReportsScreen> createState() => _FireReportsScreenState();
}

class _FireReportsScreenState extends State<FireReportsScreen> {
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";
  bool _isGenerating = false;

  DateTime getStartOfToday() => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  DateTime getStartOfWeek() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  /// 🛡️ PDF SAFE TEXT: Strips emojis/symbols that crash the PDF engine
  String _sanitize(dynamic text) {
    if (text == null) return "N/A";
    String s = text.toString();
    // Keep only standard characters (letters, numbers, basic punctuation)
    return s.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  /// 🎨 STATUS COLOR MAPPER
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'handled': return Colors.green;
      case 'pending': return Colors.orange;
      case 'dispatched': return Colors.blue;
      default: return Colors.redAccent;
    }
  }

  /// 🔍 SEARCH LOGIC
  bool matchesSearch(Map<String, dynamic> report) {
    if (searchQuery.isEmpty) return true;
    final query = searchQuery.toLowerCase();

    String formattedDate = "";
    if (report["timestamp"] != null) {
      DateTime dt = (report["timestamp"] as Timestamp).toDate();
      formattedDate = DateFormat("dd/MM/yyyy MMMM yyyy").format(dt).toLowerCase();
    }

    final searchString = "${report['reporterName']} ${report['handledBy']} ${report['status']} ${report['ward']} ${report['description']} $formattedDate".toLowerCase();
    return searchString.contains(query);
  }

  /// 📄 SIMPLIFIED PDF GENERATION
  Future<void> downloadPdf(List<Map<String, dynamic>> reports) async {
    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();

      // 1. Prepare Table Data (Headers + Rows)
      final List<List<String>> tableData = [
        ['Date/Time', 'Reporter', 'Station', 'Status', 'Location']
      ];

      for (var r in reports) {
        String ts = "N/A";
        if (r["timestamp"] != null) {
          ts = DateFormat("dd/MM/yy HH:mm").format((r["timestamp"] as Timestamp).toDate());
        }

        tableData.add([
          _sanitize(ts),
          _sanitize(r['reporterName'] ?? 'Unknown'),
          _sanitize(r['handledBy'] ?? 'N/A'),
          _sanitize(r['status']?.toString().toUpperCase() ?? 'N/A'),
          _sanitize("${r['ward'] ?? ''}, ${r['subcounty'] ?? ''}"),
        ]);
      }

      // 2. Add Page to PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => [
            pw.Text("FIRE ALERT SYSTEM - OFFICIAL REPORT",
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
            pw.Text("Filter: ${widget.filter.toUpperCase()} | Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}"),
            pw.SizedBox(height: 10),

            pw.TableHelper.fromTextArray(
              context: context,
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
              cellHeight: 25,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
              },
            ),
          ],
        ),
      );

      // 3. Launch Print/Download Dialog
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Fire_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

    } catch (e) {
      debugPrint("PDF Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to generate PDF: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> deleteReport(String docId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Report?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await FirebaseFirestore.instance.collection("reports").doc(docId).delete();
    }
  }

  void viewReportDetails(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Report Details", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(Icons.description, "Description", report["description"]),
              _detailRow(Icons.person, "Reporter", report["reporterName"]),
              _detailRow(Icons.phone, "Phone", report["reporterPhone"]),
              _detailRow(Icons.local_fire_department, "Station", report["handledBy"]),
              _detailRow(Icons.location_on, "Location", "${report["ward"]}, ${report["subcounty"]}"),
              _detailRow(Icons.access_time, "Time", report["timestamp"] != null ? DateFormat("dd MMM yyyy HH:mm").format(report["timestamp"].toDate()) : "N/A"),
              _detailRow(Icons.info_outline, "Status", report["status"]?.toString().toUpperCase()),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text("$label: ${value ?? 'N/A'}", style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime startOfToday = getStartOfToday();
    DateTime startOfWeek = getStartOfWeek();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.filter == "today" ? "Reports: Today" : widget.filter == "week" ? "Reports: Week" : "All Reports",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("reports").orderBy("timestamp", descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.red));

          var filteredReports = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            if (data["timestamp"] == null) return false;
            DateTime time = (data["timestamp"] as Timestamp).toDate();
            if (widget.filter == "today" && !time.isAfter(startOfToday)) return false;
            if (widget.filter == "week" && !time.isAfter(startOfWeek)) return false;
            return matchesSearch(data);
          }).toList();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(15, 5, 15, 20),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                        child: TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            hintText: "Search reports...",
                            prefixIcon: Icon(Icons.search, color: Colors.red),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 15),
                          ),
                          onChanged: (value) => setState(() => searchQuery = value.trim()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FloatingActionButton.small(
                      heroTag: "fab_download_main",
                      backgroundColor: Colors.white,
                      onPressed: (_isGenerating || filteredReports.isEmpty)
                          ? null
                          : () {
                        final data = filteredReports.map((d) => d.data() as Map<String, dynamic>).toList();
                        downloadPdf(data);
                      },
                      child: _isGenerating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                          : const Icon(Icons.download, color: Colors.red),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filteredReports.isEmpty
                    ? const Center(child: Text("No fire reports found"))
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: filteredReports.length,
                  itemBuilder: (context, index) {
                    var doc = filteredReports[index];
                    var report = doc.data() as Map<String, dynamic>;
                    String status = report["status"] ?? "unknown";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        title: Text(report["reporterName"] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${report['ward']} • ${report['status'].toString().toUpperCase()}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.visibility, color: Colors.blue), onPressed: () => viewReportDetails(report)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteReport(doc.id)),
                          ],
                        ),
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