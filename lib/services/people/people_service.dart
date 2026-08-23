import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/people/person.dart';
import '../../models/people/person_entry.dart';

class PeopleService {
  PeopleService(this._uid);

  final String _uid;

  CollectionReference get _peopleRef =>
      FirebaseFirestore.instance.collection('users/$_uid/people');

  CollectionReference _entriesRef(String personId) =>
      _peopleRef.doc(personId).collection('entries');

  // ── People CRUD ──

  Stream<List<Person>> watchPeople() {
    return _peopleRef.orderBy('createdAt', descending: false).snapshots().map(
        (snap) => snap.docs.map((doc) => Person.fromDoc(doc)).toList());
  }

  Future<Person?> getPerson(String id) async {
    final doc = await _peopleRef.doc(id).get();
    if (!doc.exists) return null;
    return Person.fromDoc(doc);
  }

  Future<String> addPerson(String name, {List<String> tags = const []}) async {
    final ref = await _peopleRef.add(Person(
      id: '',
      name: name,
      tags: tags,
    ).toMap());
    return ref.id;
  }

  Future<void> updatePerson(Person person) async {
    await _peopleRef.doc(person.id).update(person.toMap());
  }

  Future<void> deletePerson(String id) async {
    // Delete all entries first
    final entries = await _entriesRef(id).get();
    for (final doc in entries.docs) {
      await doc.reference.delete();
    }
    await _peopleRef.doc(id).delete();
  }

  // ── Entries CRUD ──

  Stream<List<PersonEntry>> watchEntries(String personId) {
    return _entriesRef(personId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => PersonEntry.fromDoc(doc)).toList());
  }

  Future<String> addEntry(
    String personId,
    String text, {
    String sourceType = 'manual',
  }) async {
    final ref = await _entriesRef(personId).add(PersonEntry(
      id: '',
      personId: personId,
      text: text,
      sourceType: sourceType,
    ).toMap());
    return ref.id;
  }

  Future<void> updateEntryAnalysis(
    String personId,
    String entryId, {
    String? patterns,
    String? redFlags,
    String? emotionalReflection,
    String? communicationStyle,
  }) async {
    await _entriesRef(personId).doc(entryId).update({
      'patterns': ?patterns,
      'redFlags': ?redFlags,
      'emotionalReflection': ?emotionalReflection,
      'communicationStyle': ?communicationStyle,
      'analyzed': true,
    });
  }

  Future<void> deleteEntry(String personId, String entryId) async {
    await _entriesRef(personId).doc(entryId).delete();
  }

  /// Get all unanalyzed entries for a person (for batch analysis).
  Future<List<PersonEntry>> getUnanalyzedEntries(String personId) async {
    final snap = await _entriesRef(personId)
        .where('analyzed', isEqualTo: false)
        .get();
    return snap.docs.map((doc) => PersonEntry.fromDoc(doc)).toList();
  }
}
