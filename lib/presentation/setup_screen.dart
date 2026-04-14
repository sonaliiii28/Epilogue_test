import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'hospice_setup_screen.dart';

class SetupInfoScreen extends StatefulWidget {
  const SetupInfoScreen({super.key});

  @override
  State<SetupInfoScreen> createState() => _SetupInfoScreenState();
}

class _SetupInfoScreenState extends State<SetupInfoScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final patientController = TextEditingController();
  final caregiverController = TextEditingController();
  final emailController = TextEditingController();

  bool _iAmThePatient = false;
  String _cachedCaregiverName = '';
  String _cachedCaregiverEmail = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  int? _focusedField; // track which field is focused for highlight

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    patientController.addListener(() {
      if (!_iAmThePatient) return;
      final next = patientController.text;
      if (caregiverController.text == next) return;
      caregiverController.text = next;
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    patientController.dispose();
    caregiverController.dispose();
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF74659A), Color(0xFFDFDBE5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Top row: back arrow
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () => context.go('/'),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new,
                              size: 16,
                              color: Color.fromARGB(255, 0, 0, 0),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 50),

                      // Title
                      Text(
                        'Who are you\ncaring for?',
                        style: GoogleFonts.nunito(
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 0, 0, 0),
                          height: 1.0,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        "We'll help coordinate care and keep\neveryone connected.",
                        style: GoogleFonts.nunito(
                          fontSize: 20,

                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 0, 0, 0),
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Step indicator pill
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.35),
                            ),
                          ),
                          child: Text(
                            'STEP 1 OF 3',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: const Color.fromARGB(255, 0, 0, 0),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Divider with ring motif
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: const Color.fromARGB(255, 0, 0, 0),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: _miniRing(),
                          ),
                          Expanded(
                            child: Divider(
                              color: const Color.fromARGB(255, 0, 0, 0),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Fields
                      _buildField(
                        index: 0,
                        label: "Patient's Full Name",
                        hint: 'Enter Full name',
                        controller: patientController,
                        icon: Icons.favorite_border_rounded,
                      ),

                      const SizedBox(height: 14),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                          ),
                        ),
                        child: CheckboxListTile(
                          value: _iAmThePatient,
                          onChanged: (val) {
                            final next = val ?? false;
                            setState(() {
                              _iAmThePatient = next;
                              if (_iAmThePatient) {
                                _cachedCaregiverName = caregiverController.text;
                                _cachedCaregiverEmail = emailController.text;
                                caregiverController.text =
                                    patientController.text;
                              } else {
                                caregiverController.text = _cachedCaregiverName;
                                emailController.text = _cachedCaregiverEmail;
                              }
                            });
                          },
                          activeColor: const Color(0xFF6B5B8E),
                          checkColor: Colors.white,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            'I am the patient',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color.fromARGB(255, 0, 0, 0),
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Use the same name and email for\ncaregiver details.',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color.fromARGB(255, 0, 0, 0),
                                height: 1.3,
                              ),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          dense: true,
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (!_iAmThePatient) ...[
                        _buildField(
                          index: 1,
                          label: 'Your Full Name',
                          hint: 'Your Full name',
                          controller: caregiverController,
                          icon: Icons.person_outline_rounded,
                        ),

                        const SizedBox(height: 20),
                      ],

                      _buildField(
                        index: 2,
                        label: _iAmThePatient
                            ? 'Your Email'
                            : 'Caregiver Email',
                        hint: 'name@example.com',
                        controller: emailController,
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),

                      const SizedBox(height: 44),

                      // Continue button
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B5B8E),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                          ),
                          onPressed: () {
                            if (_formKey.currentState!.validate()) {
                              final caregiverName = _iAmThePatient
                                  ? patientController.text
                                  : caregiverController.text;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => HospiceSetupScreen(
                                    patientName: patientController.text,
                                    caregiverName: caregiverName,
                                    email: emailController.text,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: GoogleFonts.nunito(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: const Color.fromARGB(
                                    255,
                                    255,
                                    255,
                                    255,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      const SizedBox(height: 40),
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

  Widget _buildField({
    required int index,
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    final isFocused = _focusedField == index;
    return Focus(
      onFocusChange: (focused) {
        setState(() => _focusedField = focused ? index : null);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: Colors.black,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isFocused ? 1.0 : 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFocused
                    ? const Color(0xFF7A64A4)
                    : const Color(0xFFD4CDDF),
                width: isFocused ? 2 : 1.5,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7A64A4).withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              readOnly: readOnly,
              textCapitalization: keyboardType == TextInputType.emailAddress
                  ? TextCapitalization.none
                  : TextCapitalization.words,
              inputFormatters: keyboardType == TextInputType.emailAddress
                  ? null
                  : [_CapitalizeWordsFormatter()],
              style: GoogleFonts.nunito(
                fontSize: 15,
                color: const Color(0xFF443C63),
                fontWeight: FontWeight.w500,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.nunito(
                  fontSize: 16,
                  color: const Color(0xFF7A7195),
                ),
                prefixIcon: Icon(
                  icon,
                  size: 20,
                  color: isFocused
                      ? const Color(0xFF7A64A4)
                      : const Color(0xFFB8B0CC),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniRing() {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color.fromARGB(255, 0, 0, 0),
                width: 1,
              ),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color.fromARGB(255, 0, 0, 0),
                width: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == ' ') {
        buffer.write(text[i]);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(text[i].toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(text[i]);
      }
    }

    final newText = buffer.toString();
    return newValue.copyWith(text: newText, selection: newValue.selection);
  }
}
