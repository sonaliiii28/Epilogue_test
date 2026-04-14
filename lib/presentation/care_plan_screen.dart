import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';

const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);
const _purple = Color(0xFF7A64A4);
const _borderColor = Color(0xFFD4CDDF);

class CarePlanScreen extends StatefulWidget {
  const CarePlanScreen({super.key});

  @override
  State<CarePlanScreen> createState() => _CarePlanScreenState();
}

class _CarePlanScreenState extends State<CarePlanScreen> {
  final _supabaseService = SupabaseService();
  final _session = SessionManager();
  final _formKey = GlobalKey<FormState>();
  late Future<CarePlan?> _carePlanFuture;
  CarePlan? _loadedCarePlan;

  final _patientNameController = TextEditingController();
  final _primaryCaregiverNameController = TextEditingController();
  final _primaryCaregiverEmailController = TextEditingController();
  final _hospiceNameController = TextEditingController();
  final _patientAddressController = TextEditingController();
  bool _savingPatientDetails = false;

  final _medicationsSummaryController = TextEditingController();
  final _positioningTurningController = TextEditingController();
  final _transfersController = TextEditingController();
  final _mobilityController = TextEditingController();
  final _personalCareController = TextEditingController();
  final _otherInstructionsController = TextEditingController();
  final _hospiceInstructionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final careTeam = _session.currentCareTeam;
    final member = _session.currentMember;
    _patientNameController.text = careTeam?.patientFirstName ?? '';
    _primaryCaregiverNameController.text =
        careTeam?.primaryCaregiverName ?? member?.name ?? '';
    _primaryCaregiverEmailController.text =
        careTeam?.primaryCaregiverEmail ?? member?.email ?? '';
    _hospiceNameController.text = careTeam?.hospiceName ?? '';
    _patientAddressController.text = careTeam?.patientAddress ?? '';
    _carePlanFuture = _loadCarePlan();
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _primaryCaregiverNameController.dispose();
    _primaryCaregiverEmailController.dispose();
    _hospiceNameController.dispose();
    _patientAddressController.dispose();
    _medicationsSummaryController.dispose();
    _positioningTurningController.dispose();
    _transfersController.dispose();
    _mobilityController.dispose();
    _personalCareController.dispose();
    _otherInstructionsController.dispose();
    _hospiceInstructionsController.dispose();
    super.dispose();
  }

  Future<CarePlan?> _loadCarePlan() async {
    final careTeamId = _session.currentCareTeam?.id;
    if (careTeamId == null) {
      throw Exception('Not logged in');
    }
    final plan = await _supabaseService.getCarePlan(careTeamId);
    _loadedCarePlan = plan;
    if (plan != null) {
      _medicationsSummaryController.text = plan.medicationsSummary ?? '';
      _positioningTurningController.text = plan.positioningTurning ?? '';
      _transfersController.text = plan.transfers ?? '';
      _mobilityController.text = plan.mobility ?? '';
      _personalCareController.text = plan.personalCare ?? '';
      _otherInstructionsController.text = plan.otherInstructions ?? '';
      _hospiceInstructionsController.text = plan.hospiceInstructions ?? '';
    }
    return plan;
  }

  Future<void> _saveCarePlan() async {
    if (_formKey.currentState!.validate()) {
      final careTeamId = _session.currentCareTeam?.id;
      final memberId = _session.currentMember?.id;
      if (careTeamId == null || memberId == null) return;

      final existing = _loadedCarePlan;

      final plan = CarePlan(
        careTeamId: careTeamId,
        hospiceInstructions: _hospiceInstructionsController.text,
        medicationsSummary: existing?.medicationsSummary,
        positioningTurning: existing?.positioningTurning,
        transfers: existing?.transfers,
        mobility: existing?.mobility,
        personalCare: existing?.personalCare,
        otherInstructions: existing?.otherInstructions,
        updatedAt: DateTime.now(),
        updatedByMemberId: memberId,
      );
      await _supabaseService.updateCarePlan(plan);
      _loadedCarePlan = plan;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Care Plan Saved')));
      }
    }
  }

  Future<void> _savePatientDetails() async {
    if (_savingPatientDetails) return;
    final careTeamId = _session.currentCareTeam?.id;
    final member = _session.currentMember;
    if (careTeamId == null || member == null) return;

    setState(() => _savingPatientDetails = true);
    try {
      final updated = await _supabaseService.updateCareTeamPatientDetails(
        careTeamId: careTeamId,
        patientName: _patientNameController.text,
        primaryCaregiverName: _primaryCaregiverNameController.text,
        primaryCaregiverEmail: _primaryCaregiverEmailController.text,
        hospiceName: _hospiceNameController.text,
        patientAddress: _patientAddressController.text,
      );
      await _session.setSession(updated, member);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient Details Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save patient details: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingPatientDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF74659A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          "${SessionManager().currentCareTeam?.patientFirstName ?? 'Patient'}'s Care Plan",
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveCarePlan),
        ],
      ),
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
        child: FutureBuilder<CarePlan?>(
          future: _carePlanFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            return Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _patientDetailsCard(),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _hospiceInstructionsController,
                      'Hospice Instructions',
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        style: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
          floatingLabelStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
          border: const OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
    );
  }

  Widget _patientDetailsCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: _purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Patient Details',
                    style: GoogleFonts.nunito(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detailsField(
              controller: _patientNameController,
              label: 'Patient Name',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _detailsField(
              controller: _primaryCaregiverNameController,
              label: 'Primary Caregiver Name',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _detailsField(
              controller: _hospiceNameController,
              label: 'Hospice',
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _detailsField(
              controller: _patientAddressController,
              label: 'Address',
              maxLines: 2,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _detailsField(
              controller: _primaryCaregiverEmailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingPatientDetails ? null : _savePatientDetails,
                icon: _savingPatientDetails
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _savingPatientDetails ? 'Saving...' : 'Save Details',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
        floatingLabelStyle: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
