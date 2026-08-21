import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notes/note.dart';

class NoteService {
  final String uid;

  NoteService(this.uid);

  CollectionReference<Map<String, dynamic>> get _notesRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notes');

  /// Streams all notes, newest first.
  Stream<List<Note>> watchNotes() {
    return _notesRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => Note.fromFirestore(doc)).toList(),
        );
  }

  /// Adds a new note and returns its Firestore id.
  Future<String> addNote({
    required String title,
    String content = '',
    Mood? mood,
  }) async {
    final doc = await _notesRef.add(
      Note(
        id: '',
        title: title,
        content: content,
        mood: mood,
      ).toMap(),
    );
    return doc.id;
  }

  /// Updates an existing note in place.
  Future<void> updateNote(Note note) async {
    await _notesRef.doc(note.id).update(note.toMap());
  }

  /// Deletes a note.
  Future<void> deleteNote(String noteId) async {
    await _notesRef.doc(noteId).delete();
  }
}
