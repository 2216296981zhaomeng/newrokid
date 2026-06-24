# Teleprompter WebSocket Protocol

Default client URL:

```text
wss://<baseUrl-host>/ai/glasses/teleprompter
```

The page owns the WebSocket code in:

`pages/smartIDBadge/glasses.vue`

Change `getTeleprompterSocketUrl`, `buildSessionStartPayload`, `buildAudioChunkPayload`, and `handleTeleprompterMessage` when wiring the backend.

## Client To Server

Session start:

```json
{
  "event": "session.start",
  "codec": "pcm",
  "sampleRate": 16000,
  "channels": 1,
  "bitsPerSample": 16
}
```

Audio chunk:

```json
{
  "event": "audio.chunk",
  "sequence": 1,
  "audio": "base64 pcm data",
  "bytes": 6400,
  "final": false,
  "codec": "pcm",
  "sampleRate": 16000,
  "channels": 1,
  "bitsPerSample": 16
}
```

Session stop:

```json
{
  "event": "session.stop"
}
```

## Server To Client

Any of these fields will be displayed on the glasses:

```json
{
  "event": "prompt.delta",
  "text": "请介绍小区配套和通勤距离"
}
```

Supported text fields:

- `prompt`
- `tips`
- `text`
- `content`
- `answer`
