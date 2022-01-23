import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uni_links/uni_links.dart';
import 'firebase_options.dart';

final FirebaseAuth auth = FirebaseAuth.instance;
const _pw = 'somEp1asswOrd';
late final DateFormat timeFmt = DateFormat('Hms');
UserCredential? userCred;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Firebase auth testing'),
        ),
        body: const Padding(
          padding: EdgeInsets.all(8),
          child: MainForm(),
        ),
      ),
    );
  }
}

class MainForm extends StatefulWidget {
  const MainForm({Key? key}) : super(key: key);

  @override
  State<MainForm> createState() => _MainFormState();
}

class _MainFormState extends State<MainForm> with WidgetsBindingObserver {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  String _emailError = '';
  User? _user;
  bool _handleCodeInApp = false;
  String _log = '';

  Future<void> _getInitialUri() async {
    final uri = await getInitialUri();
    _addLog('initial URI: $uri');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _getInitialUri();
    }
  }

  @override
  void initState() {
    super.initState();
    auth.authStateChanges().listen((User? u) async {
      _user = u;
      if (u != null) {
        _emailController.text = u.email!;
      }
      _addLog('auth user state change: $u');
    });
    _initDynamicLinks();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(labelText: 'Email', errorText: _emailError),
            readOnly: _user != null,
            keyboardType: TextInputType.emailAddress,
            validator: (String? value) {
              if (value!.isEmpty) return 'Enter e-mail';
              return null;
            },
          ),
          if (_user != null)
            Text(_user!.emailVerified ? 'Email is verified' : 'Email NOT verified')
          else if (kIsWeb)
            CheckboxListTile(
                title: const Text('register: handle code in app'),
                value: _handleCodeInApp,
                onChanged: (newValue) {
                  _handleCodeInApp = newValue!;
                  setState(() {});
                }),
          Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: ElevatedButton(
                    onPressed: _signUpDown, child: Text(_user == null ? 'Sign up' : 'Delete user')),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: ElevatedButton(
                    onPressed: _signInOut, child: Text(_user == null ? 'Sign in' : 'Sign out')),
              ),
            ],
          ),
          const Text(
            'Logs:',
            style: TextStyle(fontSize: 30),
          ),
          Row(
            children: [
              Flexible(child: Text(_log)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _signInOut() async {
    if (_user == null) {
      if (!_formKey.currentState!.validate()) {
        setState(() {});
        return;
      }
      _clearEror();
      try {
        userCred =
            await auth.signInWithEmailAndPassword(email: _emailController.text, password: _pw);
        _addLog('Logging in OK');
      } on FirebaseAuthException catch (e, st) {
        _onAuthError('Logging in', e, st);
      }
    } else {
      try {
        await auth.signOut();
        _addLog('Logging out OK');
      } on FirebaseAuthException catch (e, st) {
        _onAuthError('Logging out', e, st);
      }
    }
  }

  void _signUpDown() {
    if (_user == null) {
      _signUp();
    } else {
      _deleteUser();
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {});
      return;
    }
    _clearEror();
    final String email = _emailController.text;
    try {
      userCred = (await auth.createUserWithEmailAndPassword(email: email, password: _pw));
      if (userCred?.user == null) {
        _addLog('Register FAILED');
        return;
      }
      _addLog('Register OK');
      await userCred!.user!.sendEmailVerification(ActionCodeSettings(
        url: 'https://firebase-auth-demo.ga/dl?',
        dynamicLinkDomain: 'firebase-auth-demo.ga',
        androidPackageName: 'com.example.firebase_auth_bug_demo',
        androidInstallApp: true,
        androidMinimumVersion: '21',
        iOSBundleId: 'com.example.firebase_auth_bug_demo',
        handleCodeInApp: _handleCodeInApp,
      ));
      _addLog('Register email SENT');
    } on FirebaseAuthException catch (e, st) {
      _onAuthError('Register email sending', e, st);
    }
  }

  Future<void> _deleteUser() async {
    try {
      await _user!.delete();
    } on FirebaseAuthException catch (e, st) {
      if (e.code == 'requires-recent-login') {
        try {
          await _user!.reauthenticateWithCredential(userCred!.credential!);
          await _user!.delete();
          _addLog('Deleting user OK');
        } on FirebaseAuthException catch (e, st) {
          _onAuthError('reauthenticateWithCredential for delete', e, st);
          return;
        }
      }
      _onAuthError('Deleting user', e, st);
    }
  }

  void _clearEror() {
    _emailError = '';
  }

  void _onAuthError(String s, FirebaseAuthException e, StackTrace st) {
    _emailError = e.code;
    _onError(s, e, st);
  }

  void _onError(String s, dynamic e, StackTrace st) {
    print('error: $s; $e; $st');
    _addLog('$s FAILED');
  }

  _addLog(String newLine) {
    _log = '${timeFmt.format(DateTime.now())}: $newLine\n\n$_log';
    setState(() {});
  }

  Future<void> _initDynamicLinks() async {
    try {
      handleDynamicLink(await getInitialUri());
    } on Exception catch (e, st) {
      _onError('initial dynamic link', e, st);
    }
    if (!kIsWeb) {
      uriLinkStream.listen((Uri? uri) {
        handleDynamicLink(uri);
      }, onError: (e, st) {
        _onError('listening dynamic link', e, st);
      });
    }
  }

  Future<void> handleDynamicLink(Uri? deepLink) async {
    if (deepLink == null) {
      return;
    }
    String? link = deepLink.queryParameters['link'];
    if (link != null) {
      deepLink = Uri.parse(link);
    }
    String? actionCode = deepLink.queryParameters['oobCode'];
    if (actionCode != null) {
      try {
        await auth.checkActionCode(actionCode);
        await auth.applyActionCode(actionCode);
        await auth.currentUser?.reload();
        _user = auth.currentUser;
        _addLog('Action code OK');
      } on FirebaseAuthException catch (e, st) {
        _onError('Apply deep link action code and user reload $deepLink code: $actionCode', e, st);
        return;
      }
    }
  }
}
