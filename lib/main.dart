import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:janus_client/janus_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client_example/conf.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Silent Party',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: TypedStreamingV2(),
    );
  }
}

class TypedStreamingV2 extends StatefulWidget {
  @override
  _StreamingState createState() => _StreamingState();
}

class _StreamingState extends State<TypedStreamingV2> {
  late JanusClient client;
  late WebSocketJanusTransport ws;
  late JanusSession session;
  late JanusStreamingPlugin plugin;
  Map<String, MediaStream> remoteAudioStreams = {};
  Map<String, RTCVideoRenderer> remoteAudioRenderers = {};
  TextEditingController _streamIdController = TextEditingController(text: '5001');
  int? selectedStreamId=5001;
  bool isPlaying = false;
  bool isMuted = false;

  initJanusClient() async {
    ws = WebSocketJanusTransport(url: servermap['janus_ws']);
    client = JanusClient(
      transport: ws,
      iceServers: [
        RTCIceServer(username: '', credential: '', urls: servermap['stun_url']),
        RTCIceServer(username: servermap['turn_user'], credential: servermap['turn_pass'], urls: servermap['turn_udp_url']),
        RTCIceServer(username: servermap['turn_user'], credential: servermap['turn_pass'], urls: servermap['turn_tsp_url']),
      ],
      isUnifiedPlan: true,
    );

    session = await client.createSession();
    plugin = await session.attach<JanusStreamingPlugin>();
  }

  playStream() async {
    await plugin.watchStream(selectedStreamId!);

    plugin.remoteTrack?.listen((event) async {
      if (event.track != null && event.flowing == true && event.track?.kind == 'audio') {
        MediaStream temp = await createLocalMediaStream(event.track!.id!);
        setState(() {
          remoteAudioRenderers.putIfAbsent(event.track!.id!, () => RTCVideoRenderer());
          remoteAudioStreams.putIfAbsent(event.track!.id!, () => temp);
        });
        await remoteAudioRenderers[event.track!.id!]?.initialize();
        await remoteAudioStreams[event.track!.id!]?.addTrack(event.track!);
        remoteAudioRenderers[event.track!.id!]?.srcObject = remoteAudioStreams[event.track!.id!];
        if (kIsWeb) {
          remoteAudioRenderers[event.track!.id!]?.muted = false;
        }
      }
    });

    plugin.typedMessages?.listen((event) async {
      Object data = event.event.plugindata?.data;
      if (data is StreamingPluginPreparingEvent) {
        await plugin.handleRemoteJsep(event.jsep);
        await plugin.startStream();
        setState(() {
          isPlaying = true;
        });
      }
    });
  }

  stopStream() async {
    await plugin.pauseStream();
    setState(() {
      isPlaying = false;
    });
  }

  @override
  void initState() {
    super.initState();
    initJanusClient();
  }

  cleanUpWebRTCStuff() {
    remoteAudioStreams.forEach((key, value) {
      stopAllTracksAndDispose(value);
    });
    remoteAudioRenderers.forEach((key, value) async {
      value.srcObject = null;
      await value.dispose();
    });
  }

  destroy() async {
    cleanUpWebRTCStuff();
    await plugin.stopStream();
    await plugin.dispose();
    session.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Silent Party',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _streamIdController,
                decoration: InputDecoration(
                  labelText: 'Stream ID',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                enabled: !isPlaying,
                onChanged: (value) {
                  setState(() {
                    selectedStreamId = int.tryParse(value);
                  });
                },
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                 if (selectedStreamId != null) {
                  if (isPlaying) {
                      await stopStream();
                
                    } else {
                      await playStream();
                    }
                  } else {
                    // Handle case where selectedStreamId is null
                    // For example, show a message to the user.
                    print("Stream ID is not valid");
                  }
              },
              child: Text(isPlaying ? "Stop" : "Play"),
            ),
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  isMuted = !isMuted;
                });
                var transceivers = await plugin.webRTCHandle?.peerConnection?.transceivers;
                transceivers?.forEach((element) {
                  if (element.receiver.track?.kind == 'audio') {
                    element.receiver.track?.enabled = !isMuted;
                  }
                });
              },
              child: Text(isMuted ? "Unmute" : "Mute"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    destroy();
    _streamIdController.dispose();
    super.dispose();
  }
}
