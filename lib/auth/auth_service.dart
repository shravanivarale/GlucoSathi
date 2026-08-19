import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Currently signed-in user
  User? get currentUser => _auth.currentUser;

  // Stream that tells us when authentication state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register a new user
  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Login an existing user
  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }
}