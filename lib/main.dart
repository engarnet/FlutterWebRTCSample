import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _myAddress = "";
  MediaStream? _localStream;
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  List<MediaDeviceInfo> _devices = [];

  var senders = <RTCRtpSender>[];
  RTCPeerConnection? _peerConnection;

  @override
  void initState() {
    super.initState();
    NetworkInterface.list().then((value) {
      final address = value
          .firstWhere(
              (conn) => conn.name.contains("wlan") || conn.name.contains("en"))
          .addresses
          .firstOrNull
          ?.address;
      setState(() {
        _myAddress = address ?? "";
      });
    });
    _renderer.initialize();
    loadDevices();
  }

  Future<void> loadDevices() async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      //Ask for runtime permissions if necessary.
      var status = await Permission.bluetooth.request();
      if (status.isPermanentlyDenied) {
        print('BLEpermdisabled');
      }

      status = await Permission.bluetoothConnect.request();
      if (status.isPermanentlyDenied) {
        print('ConnectPermdisabled');
      }
    }
    final devices = await navigator.mediaDevices.enumerateDevices();
    setState(() {
      _devices = devices;
    });
  }

  @override
  void deactivate() {
    super.deactivate();
    _renderer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          children: <Widget>[
            Row(
              children: [
                Text("my address: "),
                Text(_myAddress),
              ],
            ),
            TextButton(
              onPressed: () => _start(),
              child: Text("Start"),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                decoration: BoxDecoration(color: Colors.black54),
                child: RTCVideoView(_renderer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    final serverSocket = await ServerSocket.bind(_myAddress, 10001);
    serverSocket.listen((client) {
      client.listen(
        (Uint8List data) async {
          try {
            final remoteAddress = client.remoteAddress;
            final offer = String.fromCharCodes(data);

            final localStream = await navigator.mediaDevices.getUserMedia({
              'audio': true,
              'video': true,
            });

            await initPCs();

            final audioTracks = localStream.getAudioTracks();
            if (audioTracks.isNotEmpty) {
              final track = audioTracks.first;
              await _peerConnection?.addTrack(track, localStream);
            }

            final tracks = localStream.getVideoTracks();
            if (tracks.isNotEmpty) {
              final track = localStream.getVideoTracks().first;
              var rtpSender =
                  await _peerConnection?.addTrack(track, localStream);
              senders.add(rtpSender!);
              rtpSender.parameters.encodings?.forEach((item) {
                item.maxBitrate = 10000 * 1000 * 8;
                item.scaleResolutionDownBy = 2.0;
              });
            }

            await _peerConnection?.setRemoteDescription(RTCSessionDescription(offer, "offer"));
            var answer = await _peerConnection?.createAnswer();
            await _peerConnection?.setLocalDescription(answer!);

            final clientSocket =
                await Socket.connect(remoteAddress.address, 10002);
            clientSocket.write(answer?.sdp);
            clientSocket.close();
            serverSocket.close();
            setState(() {});
          } catch (e) {
            print(e.toString());
          }
        },
        // handle errors
        onError: (error) {
          print("client onError $error");
          client.close();
        },
        // handle the closing the connection
        onDone: () {
          print("client onDone");
          client.close();
        },
      );
    }, onDone: () {
      print("server onDone");
    }, onError: (e) {
      print("server onError $e");
    });
  }

  Future<void> initPCs() async {
    _peerConnection ??= await createPeerConnection({});

    _peerConnection?.onTrack = (event) {
      if (event.track.kind == 'video') {
        _renderer.srcObject = event.streams[0];
        setState(() {});
      }
    };

    _peerConnection?.onConnectionState = (state) {
      print('connectionState $state');
    };

    _peerConnection?.onIceConnectionState = (state) {
      print('iceConnectionState $state');
    };

    // await _peerConnection?.addTransceiver(
    //     kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
    //     init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv));
    // await _peerConnection?.addTransceiver(
    //     kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
    //     init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv));
  }
}
