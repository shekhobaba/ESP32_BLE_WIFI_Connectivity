import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'package:location/location.dart' as location_handler;
import 'package:wifi_scan/wifi_scan.dart';



void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 BLE App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: BLEScannerScreen(),
    );
  }
}

class BLEScannerScreen extends StatefulWidget {
  @override
  _BLEScannerScreenState createState() => _BLEScannerScreenState();
}

class _BLEScannerScreenState extends State<BLEScannerScreen> {
  //FlutterBluePlus flutterBlue = FlutterBluePlus.instance;
  List<ScanResult> scanResults = [];
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await WiFiScan.instance.canStartScan(askPermissions: true);
    await WiFiScan.instance.canGetScannedResults(askPermissions: true);
  }

  void requestPermissions() async {
    Map<permission_handler.Permission, permission_handler.PermissionStatus> statuses = await [
      permission_handler.Permission.bluetoothScan,
      permission_handler.Permission.bluetoothConnect,
      permission_handler.Permission.location,
    ].request();

    if (statuses[permission_handler.Permission.bluetoothScan]!.isGranted &&
        statuses[permission_handler.Permission.bluetoothConnect]!.isGranted &&
        statuses[permission_handler.Permission.location]!.isGranted) {
      checkBluetoothState();
    } else {
      print("Bluetooth permissions are denied.");
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Permission Denied"),
            content: Text("Bluetooth and Location permissions are required to scan for devices."),
            actions: <Widget>[
              TextButton(
                child: Text("OK"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }


  void checkBluetoothState() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Bluetooth is Off"),
              content: Text("Please turn on Bluetooth to scan for devices."),
              actions: <Widget>[
                TextButton(
                  child: Text("Turn On"),
                  onPressed: () async {
                    await BluetoothAdapterState.on;
                    Navigator.of(context).pop();
                    startScan();
                  },
                ),
              ],
            );
          },
        );
      } else if (state == BluetoothAdapterState.on) {
        startScan();
      }
    });
  }

  void startScan() {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    FlutterBluePlus.startScan(timeout: Duration(seconds: 5)).then((value) {
      setState(() {
        isScanning = false;
      });
    });

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
    });

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        print('${r.device.platformName} found! rssi: ${r.rssi}');
      }
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceScreen(device: device),
        ),
      );
    } catch (e) {
      print("Error connecting to device: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ESP32 BLE Scanner'),
      ),
      body: isScanning
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (context, index) {
          var result = scanResults[index];
          return ListTile(
            title: Text(result.device.platformName.isEmpty ? "Unnamed Device" : result.device.platformName),
            subtitle: Text(result.device.remoteId.toString()),
            onTap: () => connectToDevice(result.device),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(isScanning ? Icons.stop : Icons.search),
        onPressed: isScanning ? stopScan : startScan,
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;



  DeviceScreen({required this.device});

  @override
  _DeviceScreenState createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  late BluetoothCharacteristic writeCharacteristic;
  late BluetoothCharacteristic notifyCharacteristic;
  bool isConnecting = true;
  bool isConnected = false;
  List<WiFiAccessPoint> wifiList = [];
  bool isScanningWifi = false;
  bool isConnectingToWiFi = false;

  @override
  void initState() {
    super.initState();
    connectToDevice();
  }

  void connectToDevice() async {
    try {
      await widget.device.connect();
      discoverServices();
    } catch (e) {
      print("Error connecting to device: $e");
      setState(() {
        isConnecting = false;
        isConnected = false;
      });
    }
  }

  void discoverServices() async {
    try {
      List<BluetoothService> services = await widget.device.discoverServices();
      bool foundWriteCharacteristic = false;

      String targetServiceUUID = "19B10010-E8F2-537E-4F6C-D104768A1214";
      String writeCharacteristicUUID = "216A";
      String notifyCharacteristicUUID = "183E";

      for (BluetoothService service in services) {
        if (service.uuid.toString().toUpperCase() == targetServiceUUID.toUpperCase()) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() == writeCharacteristicUUID.toUpperCase()) {
              writeCharacteristic = characteristic;
              foundWriteCharacteristic = true;
            } else if (characteristic.uuid.toString().toUpperCase() == notifyCharacteristicUUID.toUpperCase()) {
              notifyCharacteristic = characteristic;
              notifyCharacteristic.setNotifyValue(true);
              notifyCharacteristic.lastValueStream.listen((value) {
                print("Notify value: $value");
                String response = String.fromCharCodes(value);
                if (response == "Connected") {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text('Success'),
                        content: Text('Connected to WiFi successfully.'),
                        actions: <Widget>[
                          TextButton(
                            child: Text('OK'),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text('Error'),
                        content: Text('Failed to connect to WiFi.'),
                        actions: <Widget>[
                          TextButton(
                            child: Text('OK'),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                }
              });
            }
          }
        }
      }

      if (!foundWriteCharacteristic) {
        throw Exception("Write characteristic '216A' not found in service '19B10010-E8F2-537E-4F6C-D104768A1214'");
      }

      setState(() {
        isConnecting = false;
        isConnected = true;
      });
    } catch (e) {
      print("Error discovering services: $e");
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Connection Error'),
            content: Text('Failed to connect or discover services.'),
            actions: <Widget>[
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );

      setState(() {
        isConnecting = false;
        isConnected = false;
      });
    }
    listenForWifiConnectionResponse(); // Add this line here
  }

  Future<void> checkLocationService() async {
    location_handler.Location location = location_handler.Location();
    bool _serviceEnabled;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('Location Service Disabled'),
              content: Text('Please enable location services to scan for WiFi networks.'),
              actions: <Widget>[
                TextButton(
                  child: Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    }
  }


  void scanWifiNetworks() async {

    await checkLocationService();  // Add this line to check location service

    setState(() {
      isScanningWifi = true;
      //wifiList.clear();
    });

    bool scanStarted = await WiFiScan.instance.startScan();
    if (scanStarted) {
      await Future.delayed(Duration(seconds: 5)); // Wait for some time to complete scan
      List<WiFiAccessPoint> accessPoints = await WiFiScan.instance.getScannedResults();
      setState(() {
        wifiList = accessPoints;
        isScanningWifi = false;
      });
    } else {
      setState(() {
        isScanningWifi = false;
      });
    }
  }

  void sendWifiCredentials(String ssid, String password) async {
    setState(() {
      isConnectingToWiFi = true;
    });

    try {
      String credentials = "$ssid;$password";
      await writeCharacteristic.write(credentials.codeUnits);
      print("Sent WiFi credentials: $credentials");
    } catch (e) {
      print("Error sending WiFi credentials: $e");
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Error'),
            content: Text('Error sending WiFi credentials: $e'),
            actions: <Widget>[
              TextButton(
                child: Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void listenForWifiConnectionResponse() {
    notifyCharacteristic.lastValueStream.listen((value) {
      setState(() {
        isConnectingToWiFi = false;
      });
      String response = String.fromCharCodes(value);
      if (response == "Connected") {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('Success'),
              content: Text('Connected to WiFi successfully.'),
              actions: <Widget>[
                TextButton(
                  child: Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
      // else {
      //   showDialog(
      //     context: context,
      //     builder: (context) {
      //       return AlertDialog(
      //         title: Text('Error'),
      //         content: Text('Failed to connect to WiFi.'),
      //         actions: <Widget>[
      //           TextButton(
      //             child: Text('OK'),
      //             onPressed: () {
      //               Navigator.of(context).pop();
      //             },
      //           ),
      //         ],
      //       );
      //     },
      //   );
      // }
    });
  }


  void connectToWifi(String ssid) {
    TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enter Password'),
          content: TextField(
            controller: passwordController,
            decoration: InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Connect'),
              onPressed: () {
                String password = passwordController.text.trim();
                if (password.isNotEmpty) {
                  sendWifiCredentials(ssid, password);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect to WiFi'),
      ),
      body: isConnecting
          ? Center(child: CircularProgressIndicator())
          : isConnected
          ? Column(
        children: <Widget>[
          if (isConnectingToWiFi) ...[
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 20),
            Text('Connecting to WiFi...'),
          ] else ...[
            ElevatedButton(
              onPressed: isScanningWifi ? null : scanWifiNetworks,
              child: Text(isScanningWifi ? 'Scanning...' : 'Scan WiFi Networks'),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: wifiList.length,
                itemBuilder: (context, index) {
                  final wifi = wifiList[index];
                  return ListTile(
                    title: Text(wifi.ssid),
                    onTap: () => connectToWifi(wifi.ssid),
                  );
                },
              ),
            ),
          ],
        ],
      )
          : Center(child: Text("Failed to connect")),
    );
  }

}
