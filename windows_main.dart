import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const PiBluetoothWindowsApp());
}

class PiBluetoothWindowsApp extends StatelessWidget {
  const PiBluetoothWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'π-Bluetooth Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF00E5FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          elevation: 0,
        ),
      ),
      home: const DesktopHomeScreen(),
    );
  }
}

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  StreamSubscription? _scanSubscription;

  void _startScan() async {
    setState(() {
      scanResults.clear();
      isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
        });
      });
    } catch (e) {
      debugPrint("Bluetooth Scan Error: $e");
    }

    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() => isScanning = false);
      }
    });
  }

  void _stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    setState(() => isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text("π-Bluetooth Desktop",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Color(0xFF00E5FF))),
            SizedBox(width: 8),
            Icon(Icons.bluetooth, color: Color(0xFF00E5FF)),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF111827),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isScanning
                      ? "Scanning Windows Bluetooth..."
                      : "Ready to Scan Nearby Devices",
                  style: TextStyle(
                      color: isScanning ? Colors.greenAccent : Colors.white70,
                      fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isScanning ? Colors.redAccent : const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isScanning ? _stopScan : _startScan,
                  icon: Icon(isScanning ? Icons.stop : Icons.radar),
                  label: Text(isScanning ? "Stop Scan" : "Scan Devices"),
                ),
              ],
            ),
          ),
          Expanded(
            child: scanResults.isEmpty
                ? const Center(
                    child: Text(
                      "Make sure Windows Bluetooth is turned ON.\nClick 'Scan Devices' to find peers.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      final result = scanResults[index];
                      final deviceName = result.device.platformName.isNotEmpty
                          ? result.device.platformName
                          : "Unknown Device (${result.device.remoteId})";

                      return Card(
                        color: const Color(0xFF1F2937),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF00E5FF),
                            child: Text("π",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(deviceName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Signal: ${result.rssi} dBm",
                              style: const TextStyle(color: Colors.white54)),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DesktopChatScreen(
                                    device: result.device,
                                    deviceName: deviceName,
                                  ),
                                ),
                              );
                            },
                            child: const Text("Connect"),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class DesktopChatScreen extends StatefulWidget {
  final BluetoothDevice device;
  final String deviceName;

  const DesktopChatScreen(
      {super.key, required this.device, required this.deviceName});

  @override
  State<DesktopChatScreen> createState() => _DesktopChatScreenState();
}

class _DesktopChatScreenState extends State<DesktopChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _messages = [];
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() async {
    try {
      await widget.device.connect();
      setState(() => isConnected = true);
    } catch (e) {
      debugPrint("Connection error: $e");
    }
  }

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _messages.add("Me: ${_controller.text.trim()}");
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.deviceName} (${isConnected ? 'Connected' : 'Connecting...'})"),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_messages[index],
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: "Type message...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF00E5FF)),
                  onPressed: _send,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
