import 'package:smmic/constants/api.dart';
import 'package:smmic/providers/auth_provider.dart';
import 'package:smmic/utils/api.dart';
import 'package:smmic/utils/auth_utils.dart';
import 'package:smmic/utils/global_navigator.dart';
import 'package:smmic/utils/logs.dart';
import 'package:smmic/utils/shared_prefs.dart';

///Authentication services, contains all major authentication functions (`login`, `logout`, `create account`, `delete account`, `update account`)
class AuthService {

  // utils
  final ApiRoutes _apiRoutes = ApiRoutes();
  final ApiRequest _apiRequest = ApiRequest();
  final SharedPrefsUtils _sharedPrefsUtils = SharedPrefsUtils();
  final AuthUtils _authUtils = AuthUtils();
  final GlobalNavigator _globalNavigator = locator<GlobalNavigator>();
  final Logs _logs = Logs(tag: 'AuthServices');

  // providers
  final AuthProvider _authProvider = AuthProvider();

  Future<void> login({required String email, required String password}) async {
    _logs.info(message: 'Log in process started');
    final data = await _apiRequest.post(
        route: _apiRoutes.login,
        body: {
          'email': email,
          'password': password
        });

    if (data.containsKey('error')) {
      if (data['error'] == 400) {

      }
      //TODO: HANDLE ERROR SCENARIO
      _logs.warning(message: 'Data caught error key!');
      _logs.warning(message: data.toString());
      _globalNavigator.forceLoginDialog(origin: _logs.tag); // replace with a more specific dialog
    }

    Map<String, dynamic> body = data['data'];

    TokenStatus refreshStatus = await _authUtils.verifyToken(
        token: body['refresh'],
        refresh: true
    );
    TokenStatus accessStatus = await _authUtils.verifyToken(
        token: body['access']
    );

    if (refreshStatus != TokenStatus.valid) {
      //TODO: HANDLE ON LOGIN ERROR
      _globalNavigator.forceLoginDialog(origin: _logs.tag);
    }

    String? newAccess;

    if (accessStatus != TokenStatus.valid) {
      newAccess = await _authUtils.refreshAccessToken(refresh: body['access']);
      accessStatus = await _authUtils.verifyToken(token: newAccess);
    }

    await _sharedPrefsUtils.setTokens(tokens: {
      Tokens.refresh: body['refresh'],
      Tokens.access: newAccess ?? body['access']
    });
    await _sharedPrefsUtils.setLoginFromRefresh(refresh: body['refresh']);

    _authProvider.setAccess(access: body['access'], accessStatus: accessStatus);

    return;
  }

}