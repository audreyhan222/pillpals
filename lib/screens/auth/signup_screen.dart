import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints.dart';
import '../../config/app_config.dart';
import '../../state/session_store.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<SessionStore>();
    try {
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      final res = await api.dio.post(ApiEndpoints.signup, data: {
        'email': _email.text.trim(),
        'password': _password.text,
      });
      final data = res.data as Map<String, dynamic>;
      final token = data['access_token'] as String?;
      if (token == null || token.isEmpty) throw Exception('Missing token');

      // Save user to Firestore (password is NOT stored — never store plain-text passwords)
      final userId = data['user_id'] as String? ?? token.split('.').first;
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'email': _email.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'patient', // default role, update as needed
      });

      await session.setToken(token);
      if (!mounted) return;
      context.go('/role');
    } on DioException catch (e) {
      setState(() => _error = e.response?.data.toString() ?? e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Get started',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password (min 6 chars)'),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Creating…' : 'Create account'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading ? null : () => context.go('/login'),
                child: const Text('I already have an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}