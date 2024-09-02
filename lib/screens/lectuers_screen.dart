import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendance/screens/assignmentpage.dart';
import 'package:attendance/screens/lecturepage.dart';
import 'package:attendance/screens/professor_quiz_creation_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart'; // استيراد مكتبة مسح الباركود

class LecturesScreen extends StatefulWidget {
  const LecturesScreen({super.key, required this.title});
  final String title;

  @override
  State<LecturesScreen> createState() => _LecturesScreenState();
}

class _LecturesScreenState extends State<LecturesScreen> {
  int _selectedIndex = 0;
  bool _isLoading = false;
  String? _barcodeData;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      LecturePage(subjectName: widget.title),
      AssignmentPage(subjectName: widget.title),
      ProfessorQuizCreationPage(subjectName: widget.title),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);

    if (result != null && result.files.isNotEmpty) {
      String? filePath = result.files.single.path;
      String fileName = result.files.single.name;

      if (filePath != null) {
        setState(() {
          _isLoading = true;
        });

        try {
          Uint8List fileBytes = await File(filePath).readAsBytes();

          // تعديل اسم الملف بإضافة تاريخ ووقت التحميل أو معرف فريد
          String uniqueFileName =
              "${DateTime.now().millisecondsSinceEpoch}_$fileName";

          Reference storageRef =
              FirebaseStorage.instance.ref().child('uploads/$uniqueFileName');
          UploadTask uploadTask = storageRef.putData(fileBytes);

          await uploadTask.whenComplete(() async {
            String downloadURL = await storageRef.getDownloadURL();

            String subCollectionName =
                _selectedIndex == 0 ? 'lectures' : 'assignments';
            String subjectName = widget.title;

            await FirebaseFirestore.instance
                .collection('subjects')
                .doc(subjectName)
                .collection(subCollectionName)
                .add({
              'file_name': fileName,
              'file_url': downloadURL,
              'created_at': Timestamp.now(),
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم رفع الملف بنجاح')),
            );
          });
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل في رفع الملف: $e')),
          );
        } finally {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في تحديد الملف')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم اختيار أي ملف')),
      );
    }
  }

 Future<void> _scanBarcode() async {
  try {
    // بدء عملية مسح الباركود
    String barcodeScanRes = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666', 'إلغاء', true, ScanMode.BARCODE);

    if (barcodeScanRes != '-1') {
      // تم الحصول على البيانات من الباركود
      setState(() {
        _barcodeData = barcodeScanRes;
        _isLoading = true;
      });

      // طلب اسم الملف من المستخدم باستخدام نافذة منبثقة
      String? fileName = await _askForFileName(context);

      if (fileName != null && fileName.isNotEmpty) {
        try {
          Uint8List fileBytes;

          // تحويل النص إلى PDF
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              build: (pw.Context context) {
                return pw.Center(
                  child: pw.Text(_barcodeData!),
                );
              },
            ),
          );

          fileBytes = await pdf.save();

          Reference storageRef =
              FirebaseStorage.instance.ref().child('uploads/$fileName.pdf');
          UploadTask uploadTask = storageRef.putData(fileBytes);

          await uploadTask.whenComplete(() async {
            String downloadURL = await storageRef.getDownloadURL();

            String subCollectionName =
                _selectedIndex == 0 ? 'lectures' : 'assignments';
            String subjectName = widget.title;

            await FirebaseFirestore.instance
                .collection('subjects')
                .doc(subjectName)
                .collection(subCollectionName)
                .add({
              'file_name': '$fileName.pdf',
              'file_url': downloadURL,
              'created_at': Timestamp.now(),
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم رفع الملف من الباركود بنجاح')),
            );
          });
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل في رفع الملف من الباركود: $e')),
          );
        } finally {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        // المستخدم لم يُدخل اسمًا للملف
        setState(() {
          _isLoading = false;  // إيقاف اللودينج عند عدم إدخال اسم
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب إدخال اسم للملف')),
        );
      }
    } else {
      // فشل في قراءة الباركود أو تم الإلغاء
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل في قراءة الباركود')),
      );
    }
  } catch (e) {
    setState(() {
      _isLoading = false;  // إيقاف اللودينج عند حدوث خطأ
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('حدث خطأ أثناء مسح الباركود: $e')),
    );
  }
}

// دالة تطلب اسم الملف من المستخدم
Future<String?> _askForFileName(BuildContext context) async {
  TextEditingController fileNameController = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('أدخل اسم الملف'),
        content: TextField(
          controller: fileNameController,
          decoration: const InputDecoration(hintText: "أدخل اسم المحاضرة"),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('إلغاء'),
            onPressed: () {
              Navigator.of(context).pop();
                setState(() {
            _isLoading = false;
          });
            },
          ),
          TextButton(
            child: const Text('حفظ'),
            onPressed: () {
              Navigator.of(context).pop(fileNameController.text);
            },
          ),
        ],
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Expanded(
              child: _pages[_selectedIndex],
            ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(
              Icons.school,
              color: Colors.white,
            ),
            label: 'المحاضرات',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.assignment,
              color: Colors.white,
            ),
            label: 'التاسكات',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.quiz,
              color: Colors.white,
            ),
            label: 'الكويزات',
          ),
        ],
        selectedFontSize: 20,
        unselectedItemColor: Colors.black,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.white,
        onTap: _onItemTapped,
      ),

      floatingActionButton:
          _selectedIndex == 0 // تحقق من أن الفهرس هو 0 (المحاضرات)
              ? Padding(
               padding: EdgeInsets.fromLTRB(0.0, 0.0, 30.0, 0.0),
                child: Row(
                  children: [
                    FloatingActionButton.extended(
                      onPressed: _pickAndUploadFile,
                      label: const Text('إضافة محاضرة'),
                      icon: const Icon(Icons.add),
                      heroTag: 'uploadButton', // تعيين tag فريد
                    ),
                    const SizedBox(width: 50),
                    FloatingActionButton.extended(
                      onPressed: _scanBarcode,
                      label: const Text('مسح الباركود'),
                      icon: const Icon(Icons.qr_code_scanner),
                      heroTag: 'scanButton', // تعيين tag فريد
                    ),
                  ],
                ),
              )
              : _selectedIndex == 1 // تحقق من أن الفهرس هو 1 (التاسكات)
                  ? FloatingActionButton.extended(
                      onPressed: _pickAndUploadFile,
                      label: const Text('إضافة تاسك'),
                      icon: const Icon(Icons.add),
                      heroTag: 'uploadTaskButton', // تعيين tag فريد للتاسكات
                    )
                  : null,
    );
  }
}
