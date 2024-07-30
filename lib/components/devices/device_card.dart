import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smmic/subcomponents/devices/battery_level.dart';
import 'package:smmic/subcomponents/devices/device_name.dart';
import 'package:smmic/subcomponents/devices/digital_display.dart';
import 'package:smmic/subcomponents/devices/gauge.dart';

class DeviceCard extends StatefulWidget {
  const DeviceCard({super.key, required this.deviceData});

  final Map<String, dynamic> deviceData;

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 25, right: 25, bottom: 15),
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.all(Radius.circular(15)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    spreadRadius: 0,
                    blurRadius: 4,
                    offset: Offset(0, 4)
                )
              ]
          ),
          height: 160,
          child: isSinkNode(widget.deviceData['id']) ? sinkNode(widget.deviceData) : sensorNode(widget.deviceData),
        ),
        Container(
          padding: const EdgeInsets.only(right: 37, top: 12),
          alignment: Alignment.topRight,
          child: RotatedBox(
            quarterTurns: 2,
            child: Icon(
              CupertinoIcons.arrow_down_left_circle,
              size: 20,
              color: Colors.black.withOpacity(0.25),
            ),
          ),
        )
      ],
    );
  }
}

bool isSinkNode(String id) {
  return id.substring(0, 2) == 'SI';
}

Widget sensorNode(Map<String, dynamic> data) {
  return Row(
    children: [
      Expanded(
        flex: 4,
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: DeviceName(deviceName: data['deviceName'])
            ),
            Expanded(
              flex: 1,
              child: BatteryLevel(batteryLevel: data['batteryLevel']),
            )
          ],
        ),
      ),
      Expanded(
          flex: 10,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    DigitalDisplay(
                      value: data['temperature'],
                      valueType: 'temperature',
                    ),
                    DigitalDisplay(
                      value: data['humidity'],
                      valueType: 'humidity',
                    )
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                    alignment: Alignment.center,
                    child: RadialGauge(
                        valueType: 'sm',
                        value: data['soilMoisture'] * 1.0,
                        limit: 100
                    )
                ),
              )
            ],
          )
      ),
    ],
  );
}

Widget sinkNode(Map<String, dynamic> data) {
  return Row(
    children: [
      Expanded(
        flex: 2,
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: DeviceName(deviceName: data['deviceName'])
            ),
            Expanded(
              flex: 1,
              child: BatteryLevel(batteryLevel: data['batteryLevel'])
            )
          ],
        ),
      ),
      Expanded(
        flex: 3,
        child: Container(),
      ),
    ],
  );
}