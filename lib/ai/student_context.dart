import '../flm/flm_combo_service.dart';
import 'ask_fpt_models.dart';

class StudentContext {
  String? curriculum;
  ActiveContextProvenance curriculumProvenance = ActiveContextProvenance.none;
  String? major;
  int? cohort;
  int? currentSemester;
  SpecializationCombo? specialization;
  SpecializationProvenance specializationProvenance =
      SpecializationProvenance.none;
  String? pendingQuestion;
  String? pendingSpecializationCurriculum;

  bool get hasVerifiedCurriculum =>
      curriculum != null &&
      curriculum!.isNotEmpty &&
      curriculumProvenance != ActiveContextProvenance.none;

  void clearPending() {
    pendingQuestion = null;
    pendingSpecializationCurriculum = null;
  }

  void changeCurriculum(
    String? value,
    ActiveContextProvenance provenance, {
    String? resolvedMajor,
    int? resolvedCohort,
  }) {
    final next = value?.trim().toUpperCase();
    final changed = curriculum != null && curriculum != next;
    curriculum = next?.isEmpty == true ? null : next;
    curriculumProvenance = curriculum == null
        ? ActiveContextProvenance.none
        : provenance;
    major = resolvedMajor;
    cohort = resolvedCohort;
    if (changed || curriculum == null) {
      currentSemester = null;
      specialization = null;
      specializationProvenance = SpecializationProvenance.none;
      clearPending();
    }
  }
}
