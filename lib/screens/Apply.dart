import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class ApplyRescuerScreen extends StatefulWidget {
  const ApplyRescuerScreen({super.key});

  @override
  State<ApplyRescuerScreen> createState() => _ApplyRescuerScreenState();
}

class _ApplyRescuerScreenState extends State<ApplyRescuerScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _expCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isUploadingFile = false;

  // File Upload State
  PlatformFile? _selectedFile;
  String? _uploadedFileUrl;

  // Validation Patterns
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static final RegExp _phoneRegex = RegExp(
    r'^(\+?[0-9]{1,3}[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}$',
  );

  static final RegExp _nameRegex = RegExp(
    r"^[a-zA-Z]+(([',. -][a-zA-Z ])?[a-zA-Z]*)*$",
  );

  // ==================== VALIDATION METHODS ====================
  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    if (value.trim().length < 3) {
      return 'Name must be at least 3 characters';
    }
    if (value.trim().length > 50) {
      return 'Name must be less than 50 characters';
    }
    if (!_nameRegex.hasMatch(value.trim())) {
      return 'Please enter a valid name (letters only)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    if (!_emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    if (value.contains('..') || value.startsWith('.') || value.endsWith('.')) {
      return 'Invalid email format';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    String digitsOnly = value.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.length < 10) {
      return 'Phone number must be at least 10 digits';
    }
    if (digitsOnly.length > 15) {
      return 'Phone number is too long';
    }
    return null;
  }

  String? _validateExperience(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please describe your experience/skills';
    }
    if (value.trim().length < 20) {
      return 'Please provide more details (at least 20 characters)';
    }
    if (value.trim().length > 500) {
      return 'Description is too long (max 500 characters)';
    }
    return null;
  }

  // ==================== FILE PICKER ====================
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // Validate file size (max 5MB)
        if (file.size > 5 * 1024 * 1024) {
          _showMessage('File size must be less than 5MB', isError: true);
          return;
        }

        setState(() {
          _selectedFile = file;
          _uploadedFileUrl = null;
        });

        _showMessage('File selected: ${file.name}');
      }
    } catch (e) {
      _showMessage('Error selecting file: $e', isError: true);
    }
  }

  Future<String?> _uploadFileToStorage() async {
    if (_selectedFile == null) return null;

    setState(() => _isUploadingFile = true);

    try {
      final supabase = Supabase.instance.client;
      final fileBytes = _selectedFile!.bytes;
      final fileName = _selectedFile!.name;

      Uint8List? bytesToUpload;

      if (fileBytes != null) {
        bytesToUpload = fileBytes;
      } else if (!kIsWeb && _selectedFile!.path != null) {
        final file = File(_selectedFile!.path!);
        bytesToUpload = await file.readAsBytes();
      } else {
        throw 'Could not read file data';
      }

      final uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_${fileName.replaceAll(' ', '_')}';

      await supabase.storage.from('certificates').uploadBinary(
        uniqueFileName,
        bytesToUpload,
        fileOptions: const FileOptions(
          contentType: 'application/pdf',
          upsert: true,
        ),
      );

      final publicUrl =
      supabase.storage.from('certificates').getPublicUrl(uniqueFileName);

      debugPrint('✅ File uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      throw 'Failed to upload certificate: $e';
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  void _removeSelectedFile() {
    setState(() {
      _selectedFile = null;
      _uploadedFileUrl = null;
    });
  }

  // ==================== SUBMIT APPLICATION ====================
  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) {
      _showMessage('Please fix the errors in the form', isError: true);
      return;
    }

    // Certificate is optional but recommended
    if (_selectedFile == null) {
      final proceed = await _showConfirmDialog(
        'No Certificate',
        'You haven\'t uploaded a certificate. Applications with certificates are more likely to be approved.\n\nDo you want to continue without a certificate?',
      );
      if (!proceed) return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // Normalize inputs
      final String name = _nameCtrl.text.trim();
      final String email = _emailCtrl.text.trim().toLowerCase();
      final String phone = _phoneCtrl.text.trim();
      final String experience = _expCtrl.text.trim();

      // 1. Check if email already exists in applications
      final existingApp = await supabase
          .from('rescuer_applications')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (existingApp != null) {
        throw 'You have already submitted an application with this email.';
      }

      // 2. Check if phone already exists in applications
      final existingPhone = await supabase
          .from('rescuer_applications')
          .select()
          .eq('phone', phone)
          .maybeSingle();

      if (existingPhone != null) {
        throw 'An application with this phone number already exists.';
      }

      // 3. Check if email is already a registered user
      final existingUser = await supabase
          .from('profiles')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (existingUser != null) {
        throw 'This email is already registered as a user.';
      }

      // 4. Upload certificate if selected
      String? certificateUrl;
      String? certificateName;
      if (_selectedFile != null) {
        certificateUrl = await _uploadFileToStorage();
        certificateName = _selectedFile!.name;
      }

      // 5. Submit Application
      await supabase.from('rescuer_applications').insert({
        'name': _capitalizeWords(name),
        'email': email,
        'phone': phone,
        'experience': experience,
        'certificate_url': certificateUrl,
        'certificate_name': certificateName,
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('✅ Application submitted successfully');

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content:
        Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: RescueApp.primaryColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ??
        false;
  }

  String _capitalizeWords(String text) {
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Application Submitted!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your request has been sent to the Admin team. You will receive your login credentials via email once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (_selectedFile != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Certificate uploaded',
                      style: TextStyle(color: Colors.green[300], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, color: Colors.orangeAccent, size: 16),
                SizedBox(width: 6),
                Text(
                  'Review time: 24-48 hours',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: RescueApp.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Done',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _expCtrl.dispose();
    super.dispose();
  }

  // ==================== BUILD UI ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Apply as Rescuer',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              _buildHeaderSection(),
              const SizedBox(height: 24),

              const Text(
                'Fill out the form below. Our team will review your application and send you login details via email.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 30),

              // Form Fields
              _buildTextField(
                controller: _nameCtrl,
                label: 'Full Name',
                hint: 'Enter your first and last name',
                icon: Icons.person_outline,
                validator: _validateName,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]")),
                  LengthLimitingTextInputFormatter(50),
                ],
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _emailCtrl,
                label: 'Email Address',
                hint: 'example@email.com',
                icon: Icons.email_outlined,
                validator: _validateEmail,
                keyboardType: TextInputType.emailAddress,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  LengthLimitingTextInputFormatter(100),
                ],
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _phoneCtrl,
                label: 'Phone Number',
                hint: '+923001234567',
                icon: Icons.phone_outlined,
                validator: _validatePhone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
                  LengthLimitingTextInputFormatter(20),
                ],
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _expCtrl,
                label: 'Experience / Skills',
                hint:
                'Describe your relevant experience, certifications, or skills...',
                icon: Icons.work_outline,
                validator: _validateExperience,
                maxLines: 4,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(500),
                ],
              ),

              // Character counter for experience
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _expCtrl,
                    builder: (context, value, child) {
                      return Text(
                        '${value.text.length}/500',
                        style: TextStyle(
                          color: value.text.length > 500
                              ? Colors.red
                              : Colors.white38,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Certificate Upload Section
              _buildCertificateUploadSection(),

              const SizedBox(height: 30),

              // Submit Button
              _buildSubmitButton(),

              const SizedBox(height: 16),

              // Terms Text
              const Center(
                child: Text(
                  'By submitting, you agree to our Terms of Service\nand Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RescueApp.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RescueApp.primaryColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RescueApp.primaryColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volunteer_activism,
                color: RescueApp.primaryColor, size: 30),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Join the Rescue Team',
                  style: TextStyle(
                      color: RescueApp.primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Help save lives in your community',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificateUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            const Icon(Icons.upload_file,
                color: RescueApp.primaryColor, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Certificate / License',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Recommended',
                style: TextStyle(color: Colors.blue, fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Upload any relevant certificate or license (PDF only, max 5MB)',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // Upload Area
        if (_selectedFile == null)
          _buildUploadButton()
        else
          _buildSelectedFileCard(),

        const SizedBox(height: 12),

        // Accepted certificates info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Accepted Certificates:',
                style: TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildCertificateType('First Aid / CPR Certification'),
              _buildCertificateType('EMT / Paramedic License'),
              _buildCertificateType('Firefighting Certificate'),
              _buildCertificateType('Lifeguard Certification'),
              _buildCertificateType('Other Rescue Training Certificates'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCertificateType(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: Colors.blue, size: 14),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildUploadButton() {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: RescueApp.primaryColor.withOpacity(0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RescueApp.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                color: RescueApp.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tap to upload PDF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'First Aid, CPR, EMT, or other certifications',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileCard() {
    final fileName = _selectedFile!.name;
    final fileSize = (_selectedFile!.size / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          // PDF Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.picture_as_pdf,
              color: Colors.red,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),

          // File Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName.length > 25
                      ? '${fileName.substring(0, 22)}...pdf'
                      : fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Ready to upload • $fileSize KB',
                      style: const TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _pickFile,
                icon: const Icon(Icons.refresh, color: Colors.white54),
                tooltip: 'Change file',
              ),
              IconButton(
                onPressed: _removeSelectedFile,
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Remove',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: RescueApp.primaryColor,
          disabledBackgroundColor: RescueApp.primaryColor.withOpacity(0.5),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        onPressed:
        (_isLoading || _isUploadingFile) ? null : _submitApplication,
        child: (_isLoading || _isUploadingFile)
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Text(
              _isUploadingFile ? 'Uploading Certificate...' : 'Submitting...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send, color: Colors.white),
            SizedBox(width: 10),
            Text('Submit Application',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
        prefixIcon: Icon(icon, color: RescueApp.primaryColor),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RescueApp.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
        contentPadding:
        const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}