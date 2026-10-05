/// The RootSphere Family History Foundation's "Family History & Genealogy
/// Research Request Form", captured when someone posts an opportunity.
///
/// Sections A (requester), B (person — beyond the name/country already on
/// [OpportunitySubject]), C (research request), D (documents list),
/// E (desired output) and F (declaration). Stored as JSON on
/// `opportunity_subjects.research_request`, so it inherits that table's RLS:
/// only the requester, the claimer and platform admins can read it.
class ResearchRequest {
  const ResearchRequest({
    this.requesterName = '',
    this.requesterAddress = '',
    this.requesterPhone = '',
    this.requesterEmail = '',
    this.contactMethods = const <String>[],
    this.relationship = '',
    this.birthDate = '',
    this.birthPlace = '',
    this.marriage = '',
    this.death = '',
    this.spouses = '',
    this.parents = '',
    this.relatives = '',
    this.ethnicGroup = '',
    this.religion = '',
    this.researchQuestion = '',
    this.sourcesChecked = const <String>[],
    this.sourcesOther = '',
    this.documentsProvided = '',
    this.desiredOutputs = const <String>[],
    this.outputsOther = '',
    this.declarationAccepted = false,
    this.declaredAt,
  });

  static const List<String> contactMethodOptions = <String>[
    'Phone',
    'WhatsApp',
    'Email',
  ];

  static const List<String> sourceOptions = <String>[
    'Birth records',
    'Marriage records',
    'Death records',
    'Church records',
    'Cemetery records',
    'Family Bible',
    'Family photographs/documents',
    'Oral interviews',
    'Government records',
    'Military records',
    'School records',
    'Land/property records',
    'FamilySearch',
    'Ancestry',
    'MyHeritage',
  ];

  static const List<String> outputOptions = <String>[
    'Research report',
    'Family tree/pedigree',
    'Record search',
    'Document retrieval',
    'Oral-history research',
    'Lineage/relationship verification',
    'Biographical narrative',
    'Genealogical proof analysis',
    'Record transcription/translation',
  ];

  static const String declarationText =
      'I declare that the information I have provided is accurate to the '
      'best of my knowledge. I understand that genealogical research depends '
      'on the availability, accessibility, reliability, and survival of '
      'historical records and that RootSphere or the assigned researcher '
      'cannot guarantee that a requested ancestor, relationship, event, or '
      'record will be found.\n\n'
      'I authorize the assigned researcher to use the information and '
      'documents I provide solely as reasonably necessary to conduct the '
      'agreed research, subject to the Research Engagement Agreement and '
      'applicable privacy and data-protection requirements.';

  // A. Requester's information
  final String requesterName;
  final String requesterAddress;
  final String requesterPhone;
  final String requesterEmail;
  final List<String> contactMethods;
  final String relationship;

  // B. Person or family to be researched
  final String birthDate;
  final String birthPlace;
  final String marriage;
  final String death;
  final String spouses;
  final String parents;
  final String relatives;
  final String ethnicGroup;
  final String religion;

  // C. Research request
  final String researchQuestion;
  final List<String> sourcesChecked;
  final String sourcesOther;

  // D. Documents provided
  final String documentsProvided;

  // E. Desired research output
  final List<String> desiredOutputs;
  final String outputsOther;

  // F. Declaration and consent
  final bool declarationAccepted;
  final DateTime? declaredAt;

  bool get isEmpty => toJson().values.every(
    (v) =>
        v == null ||
        v == false ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'requesterName': requesterName,
    'requesterAddress': requesterAddress,
    'requesterPhone': requesterPhone,
    'requesterEmail': requesterEmail,
    'contactMethods': contactMethods,
    'relationship': relationship,
    'birthDate': birthDate,
    'birthPlace': birthPlace,
    'marriage': marriage,
    'death': death,
    'spouses': spouses,
    'parents': parents,
    'relatives': relatives,
    'ethnicGroup': ethnicGroup,
    'religion': religion,
    'researchQuestion': researchQuestion,
    'sourcesChecked': sourcesChecked,
    'sourcesOther': sourcesOther,
    'documentsProvided': documentsProvided,
    'desiredOutputs': desiredOutputs,
    'outputsOther': outputsOther,
    'declarationAccepted': declarationAccepted,
    'declaredAt': declaredAt?.toIso8601String(),
  };

  factory ResearchRequest.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ResearchRequest();
    String s(String key) => json[key] as String? ?? '';
    List<String> l(String key) => (json[key] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    return ResearchRequest(
      requesterName: s('requesterName'),
      requesterAddress: s('requesterAddress'),
      requesterPhone: s('requesterPhone'),
      requesterEmail: s('requesterEmail'),
      contactMethods: l('contactMethods'),
      relationship: s('relationship'),
      birthDate: s('birthDate'),
      birthPlace: s('birthPlace'),
      marriage: s('marriage'),
      death: s('death'),
      spouses: s('spouses'),
      parents: s('parents'),
      relatives: s('relatives'),
      ethnicGroup: s('ethnicGroup'),
      religion: s('religion'),
      researchQuestion: s('researchQuestion'),
      sourcesChecked: l('sourcesChecked'),
      sourcesOther: s('sourcesOther'),
      documentsProvided: s('documentsProvided'),
      desiredOutputs: l('desiredOutputs'),
      outputsOther: s('outputsOther'),
      declarationAccepted: json['declarationAccepted'] as bool? ?? false,
      declaredAt: DateTime.tryParse(json['declaredAt'] as String? ?? ''),
    );
  }
}

/// Human-friendly reference number for a research request, derived from
/// the opportunity id (the form's "RootSphere Reference No.").
String researchReferenceNumber(String opportunityId) {
  final String compact = opportunityId.replaceAll('-', '').toUpperCase();
  return 'RS-${compact.length > 8 ? compact.substring(0, 8) : compact}';
}
