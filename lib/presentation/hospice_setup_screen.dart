import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'care_address_screen.dart';

// Hospice Data Model
class HospiceOrg {
  final String id;
  final String name;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final String county;
  final String coverageArea;
  final String? branchOf;
  final String? nurseLineNumber;

  const HospiceOrg({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.county,
    required this.coverageArea,
    this.branchOf,
    this.nurseLineNumber,
  });

  // Full location string shown in results
  String get locationLine => '$address, $city, $state $zipCode';
  String get countyLine => '$county County· $coverageArea';

  factory HospiceOrg.fromSupabase(Map<String, dynamic> row) {
    String readString(Object? value) => (value ?? '').toString().trim();

    final id = readString(row['agency_id']).isNotEmpty
        ? readString(row['agency_id'])
        : readString(row['hospice_agency_id']).isNotEmpty
        ? readString(row['hospice_agency_id'])
        : readString(row['id']);

    final address1 = readString(row['address_line1']);
    final address = [
      address1,
    ].where((s) => s.trim().isNotEmpty).join(', ').trim();

    final city = readString(row['city']);
    final state = readString(row['state']);
    final zip = readString(row['zip']);
    final county = readString(row['county']);

    return HospiceOrg(
      id: id,
      name: readString(row['name']),
      address: address,
      city: city,
      state: state,
      zipCode: zip,
      county: county,
      // Not represented in the DOCX hospice table; keep empty for display.
      coverageArea: '',
      branchOf: null,
      // Best-effort: use `phone` as nurse line when present.
      nurseLineNumber: readString(row['phone']).isEmpty
          ? null
          : readString(row['phone']),
    );
  }
}

class HomeCareProvider {
  final String id;
  final String name;
  final String city;
  final String state;
  final String zip;

  const HomeCareProvider({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.zip,
  });

  String get locationLine {
    final parts = <String>[];
    if (city.trim().isNotEmpty) parts.add(city.trim());
    final stateZip = [
      state.trim(),
      zip.trim(),
    ].where((s) => s.isNotEmpty).join(' ').trim();
    if (stateZip.isNotEmpty) parts.add(stateZip);
    return parts.join(', ');
  }

  factory HomeCareProvider.fromSupabase(Map<String, dynamic> row) {
    String readString(Object? value) => (value ?? '').toString().trim();
    final id = readString(row['homecare_provider_id']).isNotEmpty
        ? readString(row['homecare_provider_id'])
        : readString(row['home_care_provider_id']).isNotEmpty
        ? readString(row['home_care_provider_id'])
        : readString(row['provider_id']).isNotEmpty
        ? readString(row['provider_id'])
        : readString(row['id']);

    return HomeCareProvider(
      id: id,
      name: readString(row['name']),
      city: readString(row['city']),
      state: readString(row['state']),
      zip: readString(row['zip_code']).isNotEmpty
          ? readString(row['zip_code'])
          : readString(row['zip']),
    );
  }
}

//  Colors
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);
const _purple = Color(0xFF7A64A4);
const _deepPurple = Color(0xFF443C63);
const _mutedPurple = Color(0xFF6C648B);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);

class HospiceSetupScreen extends StatefulWidget {
  final String patientName;
  final String caregiverName;
  final String email;

  const HospiceSetupScreen({
    super.key,
    required this.patientName,
    required this.caregiverName,
    required this.email,
  });

  @override
  State<HospiceSetupScreen> createState() => _HospiceSetupScreenState();
}

class _HospiceSetupScreenState extends State<HospiceSetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  static final SupabaseClient _client = Supabase.instance.client;

  HospiceOrg? _selectedHospice;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _homeCareController = TextEditingController();
  final _homeCareFocus = FocusNode();
  String _homeCareQuery = '';

  Timer? _hospiceDebounce;
  Timer? _homeCareDebounce;
  bool _loadingHospice = false;
  bool _loadingHomeCare = false;
  List<HospiceOrg> _hospiceSuggestions = [];
  List<HomeCareProvider> _homeCareSuggestions = [];
  final List<HomeCareProvider> _selectedHomeCareProviders = [];

  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _showResults = false;
  bool _showHomeCareResults = false;
  bool _isSubmitting = false;
  bool _showPasswordValidation = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  Future<void> _fetchHospiceSuggestions(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      if (!mounted) return;
      setState(() {
        _loadingHospice = false;
        _hospiceSuggestions = [];
        _showResults = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loadingHospice = true);

    try {
      final pattern = '%$q%';
      final response = await _client
          .from('hospice_agency_list')
          .select(
            'agency_id, name, phone, address_line1, city, state, zip, county',
          )
          .or('name.ilike.$pattern,city.ilike.$pattern,zip.ilike.$pattern')
          .limit(8);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final items = rows
          .map(HospiceOrg.fromSupabase)
          .where((h) => h.id.trim().isNotEmpty && h.name.trim().isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _hospiceSuggestions = items;
        _loadingHospice = false;
        _showResults = _searchFocus.hasFocus;
      });
    } catch (_) {
      // Best-effort fallback (some environments may not allow OR on all cols).
      try {
        final response = await _client
            .from('hospice_agency_list')
            .select(
              'agency_id, name, phone, address_line1, city, state, zip, county',
            )
            .ilike('name', '%$q%')
            .limit(8);

        final rows = (response as List).cast<Map<String, dynamic>>();
        final items = rows
            .map(HospiceOrg.fromSupabase)
            .where((h) => h.id.trim().isNotEmpty && h.name.trim().isNotEmpty)
            .toList();

        if (!mounted) return;
        setState(() {
          _hospiceSuggestions = items;
          _loadingHospice = false;
          _showResults = _searchFocus.hasFocus;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _hospiceSuggestions = [];
          _loadingHospice = false;
          _showResults = _searchFocus.hasFocus;
        });
      }
    }
  }

  Future<void> _fetchHomeCareSuggestions(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      if (!mounted) return;
      setState(() {
        _loadingHomeCare = false;
        _homeCareSuggestions = [];
        _showHomeCareResults = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loadingHomeCare = true);

    try {
      final response = await _client
          .from('homecare_provider_list')
          .select('*')
          .ilike('name', '%$q%')
          .limit(8);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final items = rows
          .map(HomeCareProvider.fromSupabase)
          .where((p) => p.id.trim().isNotEmpty && p.name.trim().isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _homeCareSuggestions = items;
        _loadingHomeCare = false;
        _showHomeCareResults = _homeCareFocus.hasFocus;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _homeCareSuggestions = [];
        _loadingHomeCare = false;
        _showHomeCareResults = _homeCareFocus.hasFocus;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();

    _searchFocus.addListener(() {
      if (!mounted) return;
      if (_searchFocus.hasFocus) {
        setState(() {
          _showResults = _searchQuery.trim().length >= 3;
          _showHomeCareResults = false;
        });
      } else {
        setState(() => _showResults = false);
      }
    });

    _homeCareFocus.addListener(() {
      if (!mounted) return;
      if (_homeCareFocus.hasFocus) {
        setState(() {
          _showHomeCareResults = _homeCareQuery.trim().length >= 3;
          _showResults = false;
        });
      } else {
        setState(() => _showHomeCareResults = false);
      }
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    _homeCareController.dispose();
    _homeCareFocus.dispose();
    _hospiceDebounce?.cancel();
    _homeCareDebounce?.cancel();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final password = (value ?? '').trim();
    if (password.isEmpty) return 'Password is required';
    if (password.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final confirm = (value ?? '').trim();
    if (confirm.isEmpty) return 'Enter password is required';
    if (confirm != _passwordController.text.trim()) {
      return "Password doesn't match";
    }
    return null;
  }

  void _onSearchChanged(String val) {
    final next = val;
    setState(() {
      _searchQuery = next;
      _showResults = next.trim().length >= 3;
      _hospiceSuggestions = [];
      _showHomeCareResults = false;
      if (_selectedHospice != null && next.trim() != _selectedHospice!.name) {
        _selectedHospice = null;
      }
    });

    _hospiceDebounce?.cancel();
    _hospiceDebounce = Timer(const Duration(milliseconds: 250), () {
      _fetchHospiceSuggestions(next);
    });
  }

  void _onHomeCareChanged(String val) {
    final next = val;
    setState(() {
      _homeCareQuery = next;
      _showHomeCareResults = next.trim().length >= 3;
      _homeCareSuggestions = [];
      _showResults = false;
    });

    _homeCareDebounce?.cancel();
    _homeCareDebounce = Timer(const Duration(milliseconds: 250), () {
      _fetchHomeCareSuggestions(next);
    });
  }

  void _selectHospice(HospiceOrg h) {
    setState(() {
      _selectedHospice = h;
      _showResults = false;
      _showHomeCareResults = false;
      _searchQuery = h.name;
      _searchCtrl.text = h.name;
      _hospiceSuggestions = [];
    });
    _searchFocus.unfocus();
  }

  void _clearSearch() {
    setState(() {
      _selectedHospice = null;
      _searchQuery = '';
      _showResults = false;
      _hospiceSuggestions = [];
    });
    _searchCtrl.clear();
    _searchFocus.requestFocus();
  }

  void _clearHomeCare() {
    setState(() {
      _homeCareQuery = '';
      _showHomeCareResults = false;
      _homeCareSuggestions = [];
    });
    _homeCareController.clear();
    _homeCareFocus.requestFocus();
  }

  void _addHomeCareProvider(HomeCareProvider provider) {
    if (_selectedHomeCareProviders.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can add up to 3 home care agencies',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final already = _selectedHomeCareProviders.any((p) => p.id == provider.id);
    if (already) {
      _clearHomeCare();
      _homeCareFocus.unfocus();
      return;
    }

    setState(() {
      _selectedHomeCareProviders.add(provider);
      _showHomeCareResults = false;
      _homeCareSuggestions = [];
      _homeCareQuery = '';
    });

    _homeCareController.clear();
    _homeCareFocus.unfocus();
  }

  void _removeHomeCareProvider(HomeCareProvider provider) {
    setState(() {
      _selectedHomeCareProviders.removeWhere((p) => p.id == provider.id);
    });
  }

  Future<void> _goNext() async {
    if (_isSubmitting) return;

    // TEMPORARY: Allow navigation regardless of email/password validity.
    // This bypasses Supabase signup and any form validation.
    setState(() {
      _isSubmitting = true;
      _showPasswordValidation = false;
    });

    if (!mounted) return;

    final email = widget.email;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CareAddressScreen(
          patientName: widget.patientName,
          caregiverName: widget.caregiverName,
          email: email,
          hospiceId: _selectedHospice?.id ?? '',
          hospiceName: _selectedHospice != null
              ? '${_selectedHospice!.name} ${_selectedHospice!.city}'
              : '',
          nurseLineNumber: _selectedHospice?.nurseLineNumber,
          homeCareProviderIds: _selectedHomeCareProviders
              .map((p) => p.id)
              .toList(),
          homeCareProviderNames: _selectedHomeCareProviders
              .map((p) => p.name)
              .toList(),
          password: _passwordController.text.trim().isEmpty
              ? null
              : _passwordController.text.trim(),
        ),
      ),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bg1, _bg2],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _showResults = false;
                          _showHomeCareResults = false;
                        });
                      },
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: _showPasswordValidation
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),

                              // Top bar: back arrow + centered step pill
                              Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: IconButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new,
                                        size: 18,
                                        color: Colors.black,
                                      ),
                                      splashRadius: 22,
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.28),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(
                                              0.38,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          'STEP 2 OF 3',
                                          style: GoogleFonts.nunito(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.8,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 48, height: 48),
                                ],
                              ),

                              const SizedBox(height: 26),

                              Text(
                                'Hospice',
                                style: GoogleFonts.nunito(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),

                              const SizedBox(height: 8),

                              if (_selectedHospice == null) ...[
                                // "Single autocomplete search field"
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _borderColor.withOpacity(0.7),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _searchCtrl,
                                    focusNode: _searchFocus,
                                    onChanged: _onSearchChanged,
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      color: _deepPurple,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Search hospice name, city, or zip...',
                                      hintStyle: GoogleFonts.nunito(
                                        fontSize: 16,
                                        color: const Color(0xFFB8B0CC),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      prefixIcon: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Icon(
                                          Icons.search_rounded,
                                          size: 22,
                                          color: _mutedPurple,
                                        ),
                                      ),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                size: 18,
                                                color: _mutedPurple,
                                              ),
                                              onPressed: _clearSearch,
                                            )
                                          : null,
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                    ),
                                  ),
                                ),

                                if (_showResults) ...[
                                  const SizedBox(height: 6),
                                  _buildResults(),
                                ],
                              ] else ...[
                                _selectedHospiceCard(),
                              ],

                              const SizedBox(height: 20),

                              Text(
                                'Home Care Agency (optional)',
                                style: GoogleFonts.nunito(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: const Color.fromARGB(255, 2, 2, 2),
                                ),
                              ),

                              const SizedBox(height: 8),

                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _borderColor.withOpacity(0.7),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _homeCareController,
                                  focusNode: _homeCareFocus,
                                  onChanged: _onHomeCareChanged,
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    color: _deepPurple,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _selectedHomeCareProviders.isEmpty
                                        ? 'Add a home care'
                                        : 'Add another',
                                    hintStyle: GoogleFonts.nunito(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFB8B0CC),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.home_work_outlined,
                                      color: _mutedPurple,
                                      size: 20,
                                    ),
                                    suffixIcon: _homeCareQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                              color: _mutedPurple,
                                            ),
                                            onPressed: _clearHomeCare,
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),

                              if (_showHomeCareResults) ...[
                                const SizedBox(height: 6),
                                _buildHomeCareResults(),
                              ],

                              if (_selectedHomeCareProviders.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                ..._selectedHomeCareProviders.map(
                                  _homeCareSelectedCard,
                                ),
                              ],

                              const SizedBox(height: 18),

                              Text(
                                'Create a new Password',
                                style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: const Color.fromARGB(255, 7, 7, 7),
                                ),
                              ),

                              const SizedBox(height: 8),

                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _borderColor.withOpacity(0.7),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  validator: _validatePassword,
                                  onChanged: (_) {
                                    if (_showPasswordValidation) {
                                      _formKey.currentState?.validate();
                                    }
                                  },
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    color: _deepPurple,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Create a secure password',
                                    hintStyle: GoogleFonts.nunito(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFB8B0CC),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: _mutedPurple,
                                      size: 20,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              Text(
                                'Re-enter Password',
                                style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: const Color.fromARGB(255, 7, 7, 7),
                                ),
                              ),

                              const SizedBox(height: 8),

                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _borderColor.withOpacity(0.7),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: true,
                                  validator: _validateConfirmPassword,
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    color: _deepPurple,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter password again',
                                    hintStyle: GoogleFonts.nunito(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFFB8B0CC),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: _mutedPurple,
                                      size: 20,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Continue button pinned at bottom
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: SizedBox(
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
                        onPressed: _isSubmitting ? null : _goNext,
                        child: Text(
                          'Continue',
                          style: GoogleFonts.nunito(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: const Color.fromARGB(255, 255, 255, 255),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // "Grouped autocomplete results (GPS-style)"
  Widget _buildResults() {
    if (_loadingHospice) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Searching…',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_hospiceSuggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_off_rounded, size: 20, color: _mutedPurple),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No hospice found. Try a different name, city, or zip.',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _hospiceSuggestions.map(_hospiceRow).toList(),
        ),
      ),
    );
  }

  Widget _hospiceRow(HospiceOrg h) {
    final isSelected = _selectedHospice?.id == h.id;
    return InkWell(
      onTap: () => _selectHospice(h),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: isSelected ? _purple.withOpacity(0.06) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: _borderColor.withOpacity(0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected ? _purple.withOpacity(0.12) : _cardBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.local_hospital_outlined,
                size: 18,
                color: isSelected ? _purple : _mutedPurple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.name.toUpperCase(),
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _deepPurple,
                    ),
                  ),
                  if (h.city.trim().isNotEmpty || h.state.trim().isNotEmpty)
                    Text(
                      [
                        h.city.trim(),
                        h.state.trim(),
                        h.zipCode.trim(),
                      ].where((s) => s.isNotEmpty).join(', '),
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: _mutedPurple,
                      ),
                    ),
                  const SizedBox(height: 2),
                  if (h.address.trim().isNotEmpty)
                    Text(
                      h.address,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: const Color(0xFFB0A8C8),
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, size: 18, color: _purple)
            else
              const Icon(Icons.chevron_right, size: 18, color: _mutedPurple),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCareResults() {
    if (_loadingHomeCare) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Searching…',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_homeCareSuggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_off_rounded, size: 20, color: _mutedPurple),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No home care agency found.',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _homeCareSuggestions.map(_homeCareRow).toList(),
        ),
      ),
    );
  }

  Widget _homeCareRow(HomeCareProvider provider) {
    final isSelected = _selectedHomeCareProviders.any(
      (p) => p.id == provider.id,
    );
    return InkWell(
      onTap: () => _addHomeCareProvider(provider),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: isSelected ? _purple.withOpacity(0.06) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: _borderColor.withOpacity(0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected ? _purple.withOpacity(0.12) : _cardBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isSelected ? Icons.check_rounded : Icons.add_rounded,
                size: 18,
                color: isSelected ? _purple : _mutedPurple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name.toUpperCase(),
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _deepPurple,
                    ),
                  ),
                  if (provider.locationLine.trim().isNotEmpty)
                    Text(
                      provider.locationLine,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: _mutedPurple,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.close, size: 16, color: _mutedPurple),
          ],
        ),
      ),
    );
  }

  Widget _homeCareSelectedCard(HomeCareProvider provider) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _selectionCard(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.home_work_outlined,
            size: 18,
            color: _mutedPurple,
          ),
        ),
        title: provider.name.toUpperCase(),
        subtitle: provider.locationLine.trim().isEmpty
            ? null
            : provider.locationLine.trim(),
        onRemove: () => _removeHomeCareProvider(provider),
      ),
    );
  }

  Widget _selectedHospiceCard() {
    final h = _selectedHospice!;
    final subtitleParts = <String>[];
    if (h.city.trim().isNotEmpty) subtitleParts.add(h.city.trim());
    if (h.state.trim().isNotEmpty) subtitleParts.add(h.state.trim());
    if (h.zipCode.trim().isNotEmpty) subtitleParts.add(h.zipCode.trim());

    return _selectionCard(
      leading: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: _cardBg),
        child: const Icon(Icons.check_rounded, size: 20, color: _purple),
      ),
      title: h.name.toUpperCase(),
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(', '),
      onRemove: _clearSearch,
    );
  }

  Widget _selectionCard({
    required Widget leading,
    required String title,
    required String? subtitle,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor.withOpacity(0.75), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _deepPurple,
                    letterSpacing: 0.4,
                  ),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _mutedPurple,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 18, color: _mutedPurple),
          ),
        ],
      ),
    );
  }
}
