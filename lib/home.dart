import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:access_resources/database_helper.dart';
import 'package:access_resources/edit_image_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _images = [];

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _refreshImages();
  }

  Future<void> _refreshImages() async {
    final uid = currentUid;
    if (uid == null) return;
    
    final data = await _dbHelper.getImages(uid);
    setState(() {
      _images = data;
    });
  }

  Future<void> _saveEditedImage(Uint8List editedData) async {
    final uid = currentUid;
    if (uid == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final String fileName = 'edited_${DateTime.now().millisecondsSinceEpoch}.png';
    final String filePath = p.join(directory.path, fileName);
    final File file = File(filePath);
    await file.writeAsBytes(editedData);
    await _dbHelper.insertImage(filePath, uid);
    _refreshImages();
  }

  Future<void> _editAndSave(Uint8List originalData) async {
    final Uint8List? editedData = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditImageScreen(imageData: originalData),
      ),
    );

    if (editedData != null) {
      await _saveEditedImage(editedData);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image != null) {
      final bytes = await image.readAsBytes();
      await _editAndSave(bytes);
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  _pickImage(ImageSource.gallery);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _uploadImage(Map<String, dynamic> image) async {
    try {
      final file = File(image['path']);
      final fileName = p.basename(image['path']);
      final ref = FirebaseStorage.instance.ref().child('uploads/$fileName');

      // Upload to Firebase Storage
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Save to Firestore
      final docRef = await FirebaseFirestore.instance.collection('user_uploads').add({
        'url': downloadUrl,
        'path': image['path'],
        'uploaded_at': FieldValue.serverTimestamp(),
        'user_email': FirebaseAuth.instance.currentUser?.email,
        'userId': currentUid,
      });

      // Update Local SQLite
      await _dbHelper.updateUploadStatus(image['id'], 1, docRef.id);

      // Trigger Notification
      AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecond,
          channelKey: 'basic_channel',
          title: 'Upload Complete',
          body: 'Your image has been successfully uploaded to Firebase.',
        ),
      );

      _refreshImages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(Map<String, dynamic> image) async {
    final uid = currentUid;
    if (uid == null) return;

    try {
      // If uploaded, delete from Firebase
      if (image['uploaded'] == 1 && image['firestore_id'] != null) {
        // Delete from Storage
        final fileName = p.basename(image['path']);
        await FirebaseStorage.instance.ref().child('uploads/$fileName').delete();

        // Delete from Firestore
        await FirebaseFirestore.instance
            .collection('user_uploads')
            .doc(image['firestore_id'])
            .delete();
      }

      // Delete from Local SQLite
      await _dbHelper.deleteImage(image['id'], uid);

      // Delete Local File (optional but recommended)
      final file = File(image['path']);
      if (await file.exists()) {
        await file.delete();
      }

      _refreshImages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Touch Up Image Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Welcome!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('Signed in as: ${FirebaseAuth.instance.currentUser?.email}'),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/sign-in');
                    }
                  },
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _images.isEmpty
                ? const Center(child: Text('No images captured yet.'))
                : ListView.builder(
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      final image = _images[index];
                      final isUploaded = image['uploaded'] == 1;

                      return ListTile(
                        leading: SizedBox(
                          width: 50,
                          height: 50,
                          child: Image.file(
                            File(image['path']),
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: const Text('Captured on:'),
                        subtitle: Text(image['timestamp']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isUploaded)
                              IconButton(
                                icon: const Icon(Icons.cloud_upload, color: Colors.blue),
                                onPressed: () => _uploadImage(image),
                              ),
                            IconButton(
                              icon: Icon(
                                isUploaded ? Icons.delete_forever : Icons.delete,
                                color: isUploaded ? Colors.red : Colors.grey,
                              ),
                              onPressed: () => _deleteImage(image),
                            ),
                          ],
                        ),
                        onTap: () async {
                          final bytes = await File(image['path']).readAsBytes();
                          await _editAndSave(bytes);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showPicker,
        tooltip: 'Pick Image',
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
