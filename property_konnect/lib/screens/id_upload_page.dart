import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import 'fingerprint_setup_page.dart';

class IdUploadPage extends StatefulWidget {
  const IdUploadPage({super.key});

  @override
  State<IdUploadPage> createState() => _IdUploadPageState();
}

class _IdUploadPageState extends State<IdUploadPage> {
  static const int _maxFileSize = 10 * 1024 * 1024;

  PlatformFile? _idPdf;
  // Cache the file bytes ONCE when picked — no re-reading on upload.
  Uint8List? _idPdfBytes;

  bool _uploading = false;
  int _progress = 0; // 0-100

  bool get _isDark => AppSettings.of(context).isDark;

  Color get _green => _isDark ? kBrandGreenOnDark : kBrandGreen;

  Color get _background =>
      _isDark ? kPageBackgroundDark : kPageBackgroundLight;

  Color get _text =>
      _isDark ? Colors.grey.shade200 : Colors.grey.shade800;

  Color get _muted =>
      _isDark ? Colors.grey.shade400 : Colors.grey.shade600;

  String _tr(String en, String sw) {
    final code = AppSettings.of(context).languageCode;
    if (code == 'sw') return sw;
    return AppLocalizations.trText(en, code);
  }

  // ============================================================
  // PICK ONE PDF (reads bytes once, validates, caches)
  // ============================================================

  Future<void> _selectPdf() async {
    if (_uploading) return;

    try {
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );

      if (file == null || !mounted) return;

      final String fileName = file.name.trim().toLowerCase();

      if (!fileName.endsWith('.pdf')) {
        throw Exception(
          _tr(
            'Only PDF files are allowed.',
            'Ni faili za PDF pekee zinazoruhusiwa.',
          ),
        );
      }

      // Read bytes ONCE here.
      final Uint8List bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception(
          _tr(
            'The selected PDF is empty.',
            'PDF iliyochaguliwa haina data.',
          ),
        );
      }

      if (bytes.length > _maxFileSize) {
        throw Exception(
          _tr(
            'The PDF is too large. Maximum allowed size is 10 MB.',
            'PDF ni kubwa sana. Ukubwa wa juu unaoruhusiwa ni MB 10.',
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _idPdf = file;
        _idPdfBytes = bytes;
      });
    } catch (e) {
      _message(_cleanError(e));
    }
  }

  // ============================================================
  // UPLOAD PDF (with progress + cached bytes)
  // ============================================================

  Future<String> _uploadPdf({
    required String uid,
    required Uint8List bytes,
  }) async {
    final Reference storageRef = FirebaseStorage.instance
        .ref()
        .child('identity_documents')
        .child(uid)
        .child('national_id.pdf');

    final SettableMetadata metadata = SettableMetadata(
      contentType: 'application/pdf',
      customMetadata: <String, String>{
        'uid': uid,
        'documentType': 'national_id',
      },
    );

    final UploadTask task = storageRef.putData(bytes, metadata);

    // Progress reporting.
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.state == TaskState.running) {
        final int total = snapshot.totalBytes;
        final int transferred =
        total > 0 ? snapshot.bytesTransferred : 0;

        final int percent =
        total > 0 ? (transferred * 100 ~/ total) : 0;

        if (mounted) {
          setState(() {
            _progress = percent;
          });
        }
      }
    });

    final TaskSnapshot snapshot = await task;

    return snapshot.ref.getDownloadURL();
  }

  // ============================================================
  // SUBMIT
  // ============================================================

  Future<void> _submit() async {
    if (_uploading) return;

    if (_idPdf == null || _idPdfBytes == null) {
      _message(
        _tr(
          'Please select the PDF containing both sides of your ID.',
          'Tafadhali chagua PDF yenye upande wa mbele na nyuma wa ID yako.',
        ),
      );
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _message(
        _tr(
          'Your session has expired. Please register again.',
          'Kipindi chako kimeisha. Tafadhali jisajili tena.',
        ),
      );
      return;
    }

    setState(() {
      _uploading = true;
      _progress = 0;
    });

    try {
      // Bytes are already in memory — no re-reading the file.
      final String idPdfUrl = await _uploadPdf(
        uid: user.uid,
        bytes: _idPdfBytes!,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'idPdfUrl': idPdfUrl,
        'idUploaded': true,
        'idVerified': false,
        'idUploadedAt': FieldValue.serverTimestamp(),
        'registrationStage': 'fingerprint_setup',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const FingerprintSetupPage(),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'unauthorized':
        case 'permission-denied':
          message = _tr(
            'You do not have permission to upload these documents.',
            'Huna ruhusa ya kupakia nyaraka hizi.',
          );
          break;

        case 'canceled':
          message = _tr(
            'The upload was cancelled.',
            'Upakiaji umeghairiwa.',
          );
          break;

        case 'retry-limit-exceeded':
        case 'storage/retry-limit-exceeded':
          message = _tr(
            'Upload timed out. Check your internet connection and try again.',
            'Upakiaji umechukua muda mrefu. Angalia intaneti yako na ujaribu tena.',
          );
          break;

        case 'quota-exceeded':
          message = _tr(
            'Storage quota has been exceeded.',
            'Kikomo cha hifadhi kimefikiwa.',
          );
          break;

        default:
          message = _tr(
            'Upload failed: ${e.message ?? e.code}',
            'Upakiaji umeshindikana: ${e.message ?? e.code}',
          );
      }

      _message(message);
    } catch (e) {
      if (!mounted) return;

      _message(
        _tr(
          'ID upload failed. Please try again.',
          'Upakiaji wa ID umeshindikana. Tafadhali jaribu tena.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = 0;
        });
      }
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // ERROR CLEANUP
  // ============================================================

  String _cleanError(Object error) {
    final String message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }

    return message;
  }

  // ============================================================
  // FILE SIZE DISPLAY
  // ============================================================

  String _fileSizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ============================================================
  // FILE CARD
  // ============================================================

  Widget _fileCard({
    required String title,
    required IconData icon,
  }) {
    final bool hasFile = _idPdf != null && _idPdfBytes != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _green, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!hasFile)
                    Text(
                      _tr('PDF not selected', 'PDF haijachaguliwa'),
                      style: TextStyle(color: _muted, fontSize: 13),
                    )
                  else ...[
                    Text(
                      _idPdf!.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _fileSizeText(_idPdfBytes!.length),
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _uploading ? null : _selectPdf,
              child: Text(
                hasFile
                    ? _tr('Change', 'Badilisha')
                    : _tr('Choose', 'Chagua'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(
          _tr(
            'Identity Verification',
            'Uthibitishaji wa Kitambulisho',
          ),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.badge_outlined,
                            size: 52,
                            color: _green,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        _tr('Upload your ID', 'Pakia kitambulisho chako'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: _text,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        _tr(
                          'Upload one PDF file containing both sides of your ID (front and back). Only PDF format is accepted.',
                          'Pakia faili moja ya PDF yenye upande wa mbele na nyuma wa kitambulisho chako. PDF pekee inakubaliwa.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, height: 1.5),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        _tr(
                          'Maximum file size: 10 MB.',
                          'Ukubwa wa juu: MB 10.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _green,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 24),

                      _fileCard(
                        title: _tr(
                          'ID document (front + back)',
                          'Hati ya ID (mbele + nyuma)',
                        ),
                        icon: Icons.picture_as_pdf_outlined,
                      ),

                      const SizedBox(height: 8),

                      if (_idPdf != null && _idPdfBytes != null &&
                          !_uploading)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                            Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.green
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _tr(
                                    'Your ID document is ready to upload.',
                                    'Hati yako ya ID iko tayari kupakiwa.',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ------------------------------------------------
                      // PROGRESS BAR (while uploading)
                      // ------------------------------------------------

                      if (_uploading) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _progress > 0
                              ? _progress / 100
                              : null,
                          backgroundColor:
                          Colors.grey.withValues(alpha: 0.2),
                          color: _green,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _progress > 0
                              ? _tr(
                            'Uploading... $_progress%',
                            'Inapakia... $_progress%',
                          )
                              : _tr(
                            'Uploading...',
                            'Inapakia...',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 13,
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _uploading ? null : _submit,
                          icon: _uploading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(
                            Icons.cloud_upload_outlined,
                          ),
                          label: Text(
                            _uploading
                                ? _tr(
                              'Uploading... $_progress%',
                              'Inapakia... $_progress%',
                            )
                                : _tr(
                              'Upload and continue',
                              'Pakia na endelea',
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: _green,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _tr(
                                  'Your identity documents are private and should only be accessible to authorized administrators.',
                                  'Nyaraka zako za utambulisho ni za siri na zinapaswa kufikiwa na wasimamizi walioidhinishwa pekee.',
                                ),
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        _tr(
                          'After uploading your ID, you will continue to fingerprint setup.',
                          'Baada ya kupakia ID yako, utaendelea kwenye usanidi wa alama ya kidole.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}