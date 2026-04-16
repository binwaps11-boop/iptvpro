# Jellyfin Architecture Notes - Extracted from Source Code

## TranscodingJob.cs - Session Management
- PlaySessionId: unique per session
- LiveStreamId: for live streams
- IsLiveOutput: flag for live vs VOD
- ActiveRequestCount: MULTI-DEVICE - tracks how many clients are reading from this job
- DeviceId: per-device tracking
- TranscodingThrottler: controls transcoding speed
- TranscodingSegmentCleaner: cleans old segments
- LastPingDate + PingTimeout: keepalive mechanism
- KillTimer: auto-kill when no clients connected
- Process: FFmpeg process reference
- BytesDownloaded/BytesTranscoded: progress tracking
- BitRate/Framerate: quality info

## Key Patterns for Our System:
1. **ActiveRequestCount**: When a client connects, increment. When disconnects, decrement. When 0, start kill timer.
2. **KillTimer**: Don't kill immediately when last client disconnects - wait PingTimeout ms
3. **TranscodingThrottler**: Slow down transcoding when buffer is full (save CPU)
4. **TranscodingSegmentCleaner**: Clean old HLS segments to save disk
5. **Process Lock**: Thread-safe process management
6. **FFmpeg graceful stop**: Send 'q' to stdin, wait 5s, then kill

## What We Need to Implement:
- ActiveRequestCount per channel session (not per device)
- KillTimer with configurable timeout
- Segment cleanup (keep only last N segments)
- Throttling when buffer ahead of all clients
- Graceful reconnect without killing the session

## ITranscodeManager.cs - Core Interface
Key methods:
- GetTranscodingJob(playSessionId): Find existing job by session
- GetTranscodingJob(path, type): Find by file path
- PingTranscodingJob(playSessionId, isUserPaused): Keep alive
- KillTranscodingJobs(deviceId, playSessionId, deleteFiles): Cleanup
- ReportTranscodingProgress(job, state, position, framerate, percent, bytesTranscoded, bitRate)
- StartFFMpeg(state, outputPath, commandLineArguments, userId, type, cancellationToken)
- OnTranscodeBeginRequest(path, type): Called when client starts reading

## Key Architecture Pattern:
1. Client requests stream → OnTranscodeBeginRequest → finds or creates TranscodingJob
2. Multiple clients can share same TranscodingJob (ActiveRequestCount++)
3. Client pings periodically → PingTranscodingJob keeps job alive
4. Client disconnects → ActiveRequestCount-- → if 0, start KillTimer
5. KillTimer expires → KillTranscodingJobs → stop FFmpeg process
6. Progress reported continuously → ReportTranscodingProgress

## What to Apply to Our System:
- Our hlsEngine.ts already has sessions Map but needs:
  1. ActiveRequestCount tracking per session
  2. KillTimer with configurable timeout (not immediate cleanup)
  3. Ping/heartbeat from clients
  4. Progress reporting (bitrate, framerate)
  5. Throttling when buffer is too far ahead
