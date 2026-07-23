import '../entities/finder_submission.dart';
import '../entities/indexer_submission.dart';
import '../entities/opportunity.dart';
import '../entities/opportunity_subject.dart';

/// Persistence contract for the collaboration / opportunities board.
abstract class OpportunityRepository {
  /// All opportunities visible to the current user.
  Future<List<CollaborationOpportunity>> getOpportunities();

  /// Stream of opportunities for realtime UI updates.
  Stream<List<CollaborationOpportunity>> watchOpportunities();

  /// Creates a new open opportunity.
  Future<CollaborationOpportunity> createOpportunity({
    required String treeId,
    required String title,
    required String description,
    String? location,
    double? latitude,
    double? longitude,
    CollaborationRole requiredRole,
    bool forCompany = false,
  });

  /// Claims an open opportunity for the current user.
  Future<CollaborationOpportunity> claimOpportunity(String id);

  /// Submits result notes / URL for a claimed opportunity.
  Future<CollaborationOpportunity> submitResult(
    String id, {
    String? notes,
    String? url,
  });

  /// Saves the Finder-specific research submission for a claimed opportunity.
  Future<CollaborationOpportunity> saveFinderSubmission(
    String id,
    FinderSubmission submission,
  );

  /// Saves the Indexer-specific transcription submission for a claimed opportunity.
  Future<CollaborationOpportunity> saveIndexerSubmission(
    String id,
    IndexerSubmission submission,
  );

  /// Sends a claimed opportunity's submission to the company for review.
  Future<CollaborationOpportunity> submitForReview(String id);

  /// Company approves a submission, forwarding it to the requester for
  /// final verification.
  Future<CollaborationOpportunity> companyApprove(String id);

  /// Company rejects a submission back to the claimer with feedback on
  /// what needs fixing.
  Future<CollaborationOpportunity> companyReject(String id, String feedback);

  /// The requester's final verification of a company-approved submission,
  /// completing the workflow.
  Future<CollaborationOpportunity> verifyOpportunity(String id);

  /// Reopens a claimed opportunity so someone else can claim it.
  Future<CollaborationOpportunity> unclaimOpportunity(String id);

  /// The subject-person details for an opportunity (null if none were
  /// entered) — server-side RLS restricts this to the requester, the
  /// claimer, and platform admins, so it never reaches anyone just browsing
  /// the public board.
  Future<OpportunitySubject?> getSubject(String opportunityId);

  /// Creates or updates the subject-person details for an opportunity the
  /// current user requested.
  Future<void> saveSubject(String opportunityId, OpportunitySubject subject);
}
