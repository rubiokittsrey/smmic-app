import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:smmic/models/device_data_models.dart';
import 'package:smmic/services/devices_services.dart';
import 'package:smmic/sqlitedb/db.dart';
import 'package:smmic/utils/device_utils.dart';
import 'package:smmic/utils/logs.dart';
import 'package:smmic/utils/shared_prefs.dart';

class DevicesProvider extends ChangeNotifier {
  // dependencies, helpers
  final Logs _logs = Logs(tag: 'DevicesProvider()');
  final DevicesServices _devicesServices = DevicesServices();
  final DeviceUtils _deviceUtils = DeviceUtils();
  final SharedPrefsUtils _sharedPrefsUtils = SharedPrefsUtils();

  late final BuildContext _internalContext;

  // sink node map
  Map<String, SinkNode> _sinkNodeMap = {}; // ignore: prefer_final_fields
  Map<String, SinkNode> get sinkNodeMap => _sinkNodeMap;

  // sensor node map
  Map<String, SensorNode> _sensorNodeMap = {}; // ignore: prefer_final_fields
  Map<String, SensorNode> get sensorNodeMap => _sensorNodeMap;

  // sink node state map
  Map<String, SinkNodeState> _sinkNodeStateMap = {}; // ignore: prefer_final_fields
  Map<String, SinkNodeState> get sinkNodeStateMap => _sinkNodeStateMap;

  // sensor node readings map
  Map<String, SensorNodeSnapshot> _sensorNodeSnapshotMap = {}; // ignore: prefer_final_fields
  Map<String, SensorNodeSnapshot> get sensorNodeSnapshotMap => _sensorNodeSnapshotMap;

  // sensor node chart data map
  Map<String, List<SensorNodeSnapshot>> _sensorNodeChartDataMap = {}; // ignore: prefer_final_fields
  Map<String, List<SensorNodeSnapshot>> get sensorNodeChartDataMap => _sensorNodeChartDataMap;

  Future<void> init({required bool isConnected, required BuildContext context}) async {
    // register context
    try {
      _internalContext = context;
    } on Exception catch (e) {
      _logs.warning(message: '$e');
    } on Error catch (e) {
      _logs.warning(message: '$e');
    }

    // set device list from the shared preferences
    // TODO: add cross checking with api to verify integrity
    await _setDeviceListFromSharedPrefs();

    // acquire user data and tokens from shared prefs
    Map<String, dynamic>? userData = await _sharedPrefsUtils.getUserData();
    Map<String, dynamic> tokens = await _sharedPrefsUtils.getTokens(access: true);

    if (userData == null) {
      _logs.warning(message: '.init() -> user data from shared prefs is null!');
      return;
    }

    // if connection sources are available,
    // attempt setting device list from the api
    if (isConnected) {
      await _setDeviceListFromApi(userData: userData, tokens: tokens);
    }

    // initially, load readings from the sqlite
    // TODO: add sink states to sqlite
    _initDevicesStates();
    await _loadReadingsFromSqlite();

    notifyListeners();

    if (isConnected) {
      _loadSinkReadingsFromApi();
      _loadSensorReadingsFromApi();
    }

    // set *updated* list to shared preferences
    await _setToSharedPrefs();
  }

  Future<void> _loadSinkReadingsFromApi() async {
    Map<String, List<Map<String, dynamic>>> readings = await _devicesServices.getSinkBatchSnapshots(_sinkNodeMap.keys.toList());
    for (String sinkId in readings.keys) {
      if (readings[sinkId]!.isEmpty) {
        continue;
      }
      if (_sinkNodeStateMap[sinkId] == null) {
        _logs.warning(
            message: 'sink node state data received for sink node'
                '$sinkId but no SinkNodeState object was present in _sinkNodeStateMap');
        _sinkNodeStateMap[sinkId] = SinkNodeState.fromJSON(readings[sinkId]!.first, sinkId);
      } else {
        int comparison = DateTime.parse(readings[sinkId]!.first['timestamp']).compareTo(_sinkNodeStateMap[sinkId]!.lastTransmission);
        _sinkNodeStateMap[sinkId]!.updateState(readings[sinkId]!.first);
        if (comparison == 1) {
          _sinkNodeStateMap[sinkId]!.updateState(readings[sinkId]!.first);
        }
      }
      notifyListeners();
    }
  }

  Future<void> _loadSensorReadingsFromApi() async {
    Map<String, List<Map<String, dynamic>>> readings = await _devicesServices.getSensorBatchSnapshots(_sensorNodeMap.keys.toList());
    for (String sensorId in readings.keys) {
      List<SensorNodeSnapshot> seSnapshotObjList = [];
      if (readings[sensorId]!.isEmpty) {
        continue;
      }
      // set a new sensor node snapshot object
      // for sensor node snapshot
      for (Map<String, dynamic> reading in readings[sensorId]!) {
        // id not included in the response :(
        reading[SMSensorSnapshotKeys.deviceID.key] = sensorId;
        // create new snapshot obj
        SensorNodeSnapshot seSnapshotObj = SensorNodeSnapshot.fromJSON(reading);
        seSnapshotObjList.add(seSnapshotObj);
        // set new sensor snapshot obj in se snapshot map
        if (_sensorNodeSnapshotMap[sensorId] == null) {
          _sensorNodeSnapshotMap[sensorId] = seSnapshotObj;
        } else {
          int comparison = seSnapshotObj.timestamp.compareTo(_sensorNodeSnapshotMap[sensorId]!.timestamp);
          if (comparison == 1) {
            _sensorNodeSnapshotMap[sensorId] = seSnapshotObj;
          }
        }
        _updateSensorChartDataMap(seSnapshotObj);
      }
      DatabaseHelper.addReadings(seSnapshotObjList);
    }
  }

  void updateSinkState(Map<String, dynamic> data) {
    SinkNodeState? objExistence = _sinkNodeStateMap[data[SinkNodeSnapshotKeys.deviceID.key]];
    if (objExistence == null) {
      _logs.warning(
          message: 'received sink node state for ${data['device_id']}'
              'but no sink node state object present in DevicesProvider._sinkNodeStateMap');
    } else {
      _sinkNodeStateMap[data[SinkNodeSnapshotKeys.deviceID.key]]!.updateState(data);
    }
    notifyListeners();
  }

  /// Set current SinkNode and Sensor Node *objects* map
  /// to shared preferences as `List<String>`
  Future<bool> _setToSharedPrefs() async {
    List<String> sinkNodeIds = _sinkNodeMap.keys.toList();
    List<Map<String, dynamic>> sinkNodeMapList = [];
    for (String id in sinkNodeIds) {
      SinkNode skObj = _sinkNodeMap[id]!;
      Map<String, dynamic> skMap = {
        SinkNodeKeys.deviceID.key: skObj.deviceID,
        SinkNodeKeys.deviceName.key: skObj.deviceName,
        SinkNodeKeys.latitude.key: skObj.latitude,
        SinkNodeKeys.longitude.key: skObj.longitude,
        SinkNodeKeys.registeredSensorNodes.key: skObj.registeredSensorNodes
      };
      sinkNodeMapList.add(skMap);
    }
    await _sharedPrefsUtils.setSinkList(sinkList: sinkNodeMapList);

    List<String> sensorNodeIds = _sensorNodeMap.keys.toList();
    List<Map<String, dynamic>> sensorNodeMapList = [];
    for (String id in sensorNodeIds) {
      SensorNode seObj = _sensorNodeMap[id]!;
      Map<String, dynamic> seMap = {
        SensorNodeKeys.deviceID.key: seObj.deviceID,
        SensorNodeKeys.deviceName.key: seObj.deviceName,
        SensorNodeKeys.latitude.key: seObj.latitude,
        SensorNodeKeys.longitude.key: seObj.longitude,
        SensorNodeKeys.sinkNode.key: seObj.registeredSinkNode,
        SensorNodeKeys.interval.key: seObj.interval,
        SensorNodeKeys.soilThreshold.key: seObj.soilThreshold,
        SensorNodeKeys.temperatureThreshold.key: seObj.temperatureThreshold,
        SensorNodeKeys.humidityThreshold.key: seObj.humidityThreshold,
      };
      sensorNodeMapList.add(seMap);
    }
    await _sharedPrefsUtils.setSensorList(sensorList: sensorNodeMapList);

    return true;
  }

  /// Load initial readings and chart data from the sqlite local storage
  // TODO: chart is fucked when loading from sqlite
  Future<bool> _loadReadingsFromSqlite() async {
    for (String seId in _sensorNodeMap.keys) {
      SensorNodeSnapshot? fromSQFLiteSnapshot = await DatabaseHelper.getSeReading(_sensorNodeMap[seId]!.deviceID);
      if (fromSQFLiteSnapshot != null) {
        _sensorNodeSnapshotMap[_sensorNodeMap[seId]!.deviceID] = fromSQFLiteSnapshot;
      }
      List<SensorNodeSnapshot>? fromSQFLiteChartData = await DatabaseHelper.chartReadings(_sensorNodeMap[seId]!.deviceID);
      if (fromSQFLiteChartData != null) {
        for (SensorNodeSnapshot snapshot in fromSQFLiteChartData) {
          _updateSensorChartDataMap(snapshot);
        }
      }
    }
    return true;
  }

  /// Set device list from the API
  Future<bool> _setDeviceListFromApi({required Map<String, dynamic> userData, required Map<String, dynamic> tokens}) async {
    List<Map<String, dynamic>>? devices = await _devicesServices.getDevices(userID: userData['UID'], token: tokens['access']);

    if (devices == null) {
      return false;
    }

    // acquire sink nodes and add to sinkNodeMap
    for (Map<String, dynamic> sinkMap in devices) {
      SinkNode incomingSk = _deviceUtils.sinkNodeMapToObject(sinkMap);
      if (_sinkNodeMap[incomingSk.deviceID] != null) {
        if (!(_sinkNodeMap[incomingSk.deviceID]!.toHash() == incomingSk.toHash())) {
          // TODO: version checking here, in the future
          _sinkNodeMap[incomingSk.deviceID]!.update(incomingSk);
        }
      } else {
        _sinkNodeMap[incomingSk.deviceID] = incomingSk;
      }
    }

    // acquire sensor nodes and add to sensorNodeMap
    for (Map<String, dynamic> sinkMap in devices) {
      List<Map<String, dynamic>> sensorMapList = sinkMap['sensor_nodes'];
      for (Map<String, dynamic> sensorMap in sensorMapList) {
        _logs.error(message: "sensor Map: $sensorMap");
        SensorNode incomingSe = _deviceUtils.sensorNodeMapToObject(sensorMap: sensorMap, sinkNodeID: sinkMap['device_id']);
        if (_sensorNodeMap[incomingSe.deviceID] != null) {
          if (!(_sensorNodeMap[incomingSe.deviceID]!.toHash() == incomingSe.toHash())) {
            _sensorNodeMap[incomingSe.deviceID]!.update(incomingSe);
          }
        } else {
          _logs.error(message: "oh diba: ${incomingSe.toString()}");
          _sensorNodeMap[incomingSe.deviceID] = incomingSe;
        }
      }
    }

    notifyListeners();
    return true;
  }

  /// Set device list from share preferences
  // TODO: add cross-checking with the API to verify integrity
  Future<bool> _setDeviceListFromSharedPrefs() async {
    List<Map<String, dynamic>> sinkList = await _sharedPrefsUtils.getSinkList();
    List<Map<String, dynamic>> sensorList = await _sharedPrefsUtils.getSensorList();

    // map sink nodes to objects and set to sink node map
    for (Map<String, dynamic> sinkMap in sinkList) {
      SinkNode sinkObj = _deviceUtils.sinkNodeMapToObject(sinkMap);
      _sinkNodeMap[sinkObj.deviceID] = sinkObj;
    }

    for (Map<String, dynamic> sensorMap in sensorList) {
      SinkNode? correspondingSk = _sinkNodeMap[sensorMap[SensorNodeKeys.sinkNode.key]];
      // check existence of corresponding sink node
      if (correspondingSk == null) {
        _logs.warning(
            message: 'sensor node${sensorMap[SensorNodeKeys.deviceID.key]}'
                'present in shared preferences, but corresponding SinkNode id does'
                'not exist in current _sinkNodeMap!');
        continue;
      }
      // map to object and set to sensor node map
      SensorNode sensorObj = _deviceUtils.sensorNodeMapToObject(sensorMap: sensorMap, sinkNodeID: sensorMap[SensorNodeKeys.sinkNode.key]);
      _sensorNodeMap[sensorObj.deviceID] = sensorObj;
    }

    return true;
  }

  // set a new sensor snapshot data
  void setNewSensorSnapshot(var reading) {
    SensorNodeSnapshot? finalSnapshot;

    finalSnapshot = SensorNodeSnapshot.dynamicSerializer(data: reading);

    _logs.info2(message: finalSnapshot.toString());

    if (finalSnapshot == null) {
      return;
    }

    // check if new snapshot is newer than current snapshot
    // if there is already one
    if (_sensorNodeSnapshotMap[finalSnapshot.deviceID] != null) {
      int comparisonResult = finalSnapshot.timestamp.compareTo(_sensorNodeSnapshotMap[finalSnapshot.deviceID]!.timestamp);
      switch (comparisonResult) {
        case 0:
          _logs.warning(
              message: 'new sensor node snapshot has'
                  'the same date as current snapshot object in sensorSnapshotMap');
          break;
        case 1:
          _sensorNodeSnapshotMap[finalSnapshot.deviceID] = finalSnapshot;
          break;
        case -1:
          break;
      }
    } else {
      _sensorNodeSnapshotMap[finalSnapshot.deviceID] = finalSnapshot;
      _sensorStatesMap[finalSnapshot.deviceID]!.updateConnectionState(finalSnapshot.timestamp);
    }

    // update connection state
    // _sensorStatesMap[finalSnapshot.deviceID]!.updateState({
    //   SensorAlertKeys.alertCode.key : SMSensorAlertCodes.connectedState.code.toString(),
    //   SensorAlertKeys.timestamp.key : finalSnapshot.timestamp.toString(),
    // });

    _updateSensorChartDataMap(finalSnapshot);

    notifyListeners();

    // store data to sqlite database
    DatabaseHelper.readingsLimit(finalSnapshot.deviceID);
    DatabaseHelper.addReadings([finalSnapshot]);

    return;
  }

  // update the sensor chart data map with new data
  void _updateSensorChartDataMap(SensorNodeSnapshot newData) {
    List<SensorNodeSnapshot>? chartData = _sensorNodeChartDataMap[newData.deviceID];
    // chart data modified flag
    bool modified = false;
    if (chartData == null || chartData.isEmpty) {
      chartData = [newData];
      modified = true;
    } else {
      // uniqueness check
      bool isDup = chartData.any((x) => x.timestamp.compareTo(newData.timestamp) == 0);
      if (!isDup) {
        int index = -1;
        // reverse traversal to start from end of list (latest reading)
        for (int i = chartData.length - 1; i >= 0; i--) {
          if (newData.timestamp.isAfter(chartData[i].timestamp)) {
            index = i;
            break;
          }
        }
        if (chartData.length < DatabaseHelper.maxChartLength && index == -1) {
          chartData.insert(0, newData);
          modified = true;
        } else if (index > -1) {
          chartData.insert(index + 1, newData);
          chartData.length > DatabaseHelper.maxChartLength ? chartData.removeAt(0) : ();
          modified = true;
        }
      }
    }
    if (modified) {
      _sensorNodeChartDataMap[newData.deviceID] = chartData;
      notifyListeners();
    }
  }

  // soil moisture sensor states as map
  Map<String, SMSensorState> _sensorStatesMap = {}; // ignore: prefer_final_fields
  Map<String, SMSensorState> get sensorStatesMap => _sensorStatesMap;

  void _initDevicesStates() {
    for (String sinkId in _sinkNodeMap.keys) {
      SinkNodeState sinkStateObj = SinkNodeState.initObj(sinkId);
      _sinkNodeStateMap[sinkId] = sinkStateObj;
    }
    for (String sensorId in _sensorNodeMap.keys) {
      SMSensorState smStateObj = SMSensorState.initObj(sensorId);
      _sensorStatesMap[sensorId] = smStateObj;
    }
  }

  void updateSMSensorState(Map<String, dynamic> alertMap) {
    SMSensorState? smSensorStateObj = _sensorStatesMap[alertMap[SensorAlertKeys.deviceID.key]];
    if (smSensorStateObj == null) {
      _logs.warning(
          message: 'setSMSensorState() -> received sensor alert for'
              '${alertMap[SensorAlertKeys.deviceID.key]} but not corresponding sensor state object'
              'in _sensorAlertsMap!');
    } else {
      _sensorStatesMap[alertMap[SensorAlertKeys.deviceID.key]]!.updateState(alertMap);
    }
  }

  Future<void> sinkNameChange(Map<String, dynamic> updatedSinkData) async {
    _logs.info(message: "sinkNameChange running....");

    if (_sinkNodeMap[updatedSinkData['deviceId']] == null) {
      //TODO: Error Handle
      return;
    }

    _logs.info(message: "getSKList running ....");
    List<Map<String, dynamic>>? _getSKList = await _sharedPrefsUtils.getSinkList();
    _logs.info(message: "sharedPrefsUtils : ${_sharedPrefsUtils.getSinkList()}");
    _logs.info(message: "_getSKList provider : $_getSKList");
    if (_getSKList == [] || _getSKList == null) {
      _logs.error(message: "Way sulod si _getSKList");
      return;
    } else {
      _logs.info(message: "updated sink data : $updatedSinkData");

      for (int i = 0; i < _getSKList.length; i++) {
        _logs.info(message: "for loop getSKList: ${_getSKList[i][SensorNodeKeys.deviceID.key].toString()}");

        if (_getSKList[i][SensorNodeKeys.deviceID.key] == updatedSinkData[SensorNodeKeys.deviceID.key]) {
          _logs.info(message: "Hello you have entered for loop");
          _getSKList.removeAt(i);
          _getSKList.insert(i, updatedSinkData);
        }
      }
    }
    _logs.info(message: '$_getSKList');
    bool success = await _sharedPrefsUtils.setSinkList(sinkList: _getSKList);
    if (success) {
      SinkNode updatedSink = SinkNode.fromJSON(updatedSinkData);
      _sinkNodeMap[updatedSink.deviceID] = updatedSink;
      notifyListeners();
    } else {
      _logs.error(message: "Sipyat");
    }
    notifyListeners();
  }

  Future<void> sensorNameChange(Map<String, dynamic> updatedData) async {
    _logs.info(message: "sensorNameChange : $updatedData");

    if (_sensorNodeMap[updatedData[SensorNodeKeys.deviceID.key]] == null) {
      ///TODO: Error Handle
      return;
    }

    List<Map<String, dynamic>>? getSNList = await _sharedPrefsUtils.getSensorList();

    if (getSNList == null || getSNList.isEmpty) {
      _logs.error(message: "getSNList is empty");
      return;
    } else {
      _logs.info(message: "sensorNameChange else statement running");
      for (int i = 0; i < getSNList.length; i++) {
        if (getSNList[i][SensorNodeKeys.deviceID.key] == updatedData[SensorNodeKeys.deviceID.key]) {
          getSNList.removeAt(i);
          getSNList.insert(i, updatedData);
        }
      }
    }
    bool success = await _sharedPrefsUtils.setSensorList(sensorList: getSNList);
    if (success) {
      debugPrint(updatedData.toString());
      SensorNode updatedSensor = SensorNode.fromJSON(updatedData);
      _sensorNodeMap[updatedSensor.deviceID] = updatedSensor;
      notifyListeners();
    } else {
      _logs.error(message: "err: sensor node dev provider sensorNameChange");
    }
    notifyListeners();
  }
}
