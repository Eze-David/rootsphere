import 'research_request.dart';

/// Structured details about the person an opportunity is researching —
/// name variants, country, photos, and supporting documents. Kept separate
/// from [CollaborationOpportunity] itself (and access-controlled server-side
/// via its own RLS) since it's only meant to be seen once someone has
/// actually claimed the work, not by anyone browsing the public board.
class OpportunitySubject {
  const OpportunitySubject({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.nickName = '',
    this.country = '',
    this.additionalInfo,
    this.photoUrls = const <String>[],
    this.documentUrls = const <String>[],
    this.request = const ResearchRequest(),
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String nickName;
  final String country;
  final String? additionalInfo;
  final List<String> photoUrls;
  final List<String> documentUrls;

  /// The rest of the Foundation's research request form.
  final ResearchRequest request;

  bool get isEmpty =>
      firstName.trim().isEmpty &&
      middleName.trim().isEmpty &&
      lastName.trim().isEmpty &&
      nickName.trim().isEmpty &&
      country.trim().isEmpty &&
      (additionalInfo ?? '').trim().isEmpty &&
      photoUrls.isEmpty &&
      documentUrls.isEmpty &&
      request.isEmpty;

  String get fullName => <String>[
    firstName,
    middleName,
    lastName,
  ].where((s) => s.trim().isNotEmpty).join(' ').trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'firstName': firstName,
    'middleName': middleName,
    'lastName': lastName,
    'nickName': nickName,
    'country': country,
    'additionalInfo': additionalInfo,
    'photoUrls': photoUrls,
    'documentUrls': documentUrls,
    'request': request.toJson(),
  };

  factory OpportunitySubject.fromJson(Map<String, dynamic> json) {
    return OpportunitySubject(
      firstName: json['firstName'] as String? ?? '',
      middleName: json['middleName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      nickName: json['nickName'] as String? ?? '',
      country: json['country'] as String? ?? '',
      additionalInfo: json['additionalInfo'] as String?,
      photoUrls: (json['photoUrls'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      documentUrls:
          (json['documentUrls'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(),
      request: ResearchRequest.fromJson(
        json['request'] as Map<String, dynamic>?,
      ),
    );
  }
}
