//! Media track management with real audio / video capture pipelines.
//!
//! # Feature flags
//!
//! | Feature   | Dependencies       | Enables                        |
//! |-----------|--------------------|--------------------------------|
//! | `audio`   | `cpal`, `opus`     | Microphone capture + opus codec |
//! | `video`   | `nokhwa`           | Camera capture                 |
//!
//! Both features imply `webrtc`.

// Top-level imports are in submodules; nothing needed here for re-exports.

// ============================================================================
// Audio capture (feature = "audio")
// ============================================================================

#[cfg(feature = "audio")]
mod audio {
    use std::sync::{Arc, Mutex};
    use std::time::{Duration, SystemTime};

    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use opus::{Application, Channels, Encoder};
    use tokio::task::JoinHandle;
    use tracing::{debug, error};
    use webrtc::media::Sample;
    use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
    use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;

    use crate::error::CallError;

    /// WebRTC Opus audio parameters per RFC 7587.
    const SAMPLE_RATE: u32 = 48_000;
    const CHANNELS: u16 = 1;
    const FRAME_DURATION_MS: u64 = 20;
    const SAMPLES_PER_FRAME: usize =
        (SAMPLE_RATE as usize * FRAME_DURATION_MS as usize) / 1000; // 960
    const MAX_PACKET_SIZE: usize = 4000;

    /// Manages microphone capture and Opus encoding for one call.
    ///
    /// Spawns a background tokio task that reads raw PCM from the cpal
    /// callback (via a bounded channel), encodes 20 ms frames with Opus,
    /// and writes them into a [`TrackLocalStaticSample`].
    pub struct AudioCapture {
        /// cpal input stream — dropping this stops capture.
        _stream: cpal::Stream,
        /// Handle to the background encoding task.
        _task: JoinHandle<()>,
        /// The audio track that receives encoded Opus packets.
        track: Arc<TrackLocalStaticSample>,
    }

    unsafe impl Send for AudioCapture {}
    unsafe impl Sync for AudioCapture {}

    impl AudioCapture {
        /// Open the default input device, create an Opus encoder, and
        /// capture audio into a new WebRTC track.
        pub fn try_new() -> Result<Self, CallError> {
            let host = cpal::default_host();
            let device = host
                .default_input_device()
                .ok_or_else(|| CallError::Media("no input device found".into()))?;

            let default_config = device
                .default_input_config()
                .map_err(|e| {
                    CallError::Media(format!("default_input_config: {e}"))
                })?;

            debug!(
                "AudioCapture: device={}, channels={:?}, sample_rate={:?}",
                device.name().unwrap_or_else(|_| "unknown".into()),
                default_config.channels(),
                default_config.sample_rate(),
            );

            let config = cpal::StreamConfig {
                channels: CHANNELS,
                sample_rate: cpal::SampleRate(SAMPLE_RATE),
                buffer_size: cpal::BufferSize::Default,
            };

            let encoder = Encoder::new(
                SAMPLE_RATE,
                Channels::Mono,
                Application::Voip,
            )
            .map_err(|e| {
                CallError::Media(format!("opus Encoder::new: {e}"))
            })?;

            let encoder = Arc::new(Mutex::new(encoder));

            // Bounded channel: cpal callback → tokio encoding task.
            let (pcm_tx, mut pcm_rx) =
                tokio::sync::mpsc::channel::<Vec<f32>>(4);

            // Create the WebRTC track.
            let track = Arc::new(TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: "audio/opus".to_owned(),
                    clock_rate: SAMPLE_RATE,
                    channels: CHANNELS,
                    ..Default::default()
                },
                "audio".to_owned(),
                "webrtc-rs".to_owned(),
            ));
            let track_clone = Arc::clone(&track);

            // Background task: drain PCM channel, encode, write to track.
            let task = tokio::spawn(async move {
                let mut buffer: Vec<f32> =
                    Vec::with_capacity(SAMPLES_PER_FRAME);

                while let Some(chunk) = pcm_rx.recv().await {
                    buffer.extend_from_slice(&chunk);

                    while buffer.len() >= SAMPLES_PER_FRAME {
                        let frame: Vec<f32> =
                            buffer.drain(..SAMPLES_PER_FRAME).collect();

                        let i16_frame: Vec<i16> = frame
                            .iter()
                            .map(|&s| {
                                (s * 32767.0).clamp(-32768.0, 32767.0) as i16
                            })
                            .collect();

                        let encoded = match encoder.lock() {
                            Ok(mut enc) => enc
                                .encode_vec(&i16_frame, MAX_PACKET_SIZE)
                                .unwrap_or_else(|e| {
                                    error!("opus encode error: {e}");
                                    Vec::new()
                                }),
                            Err(_) => {
                                error!("opus encoder mutex poisoned");
                                break;
                            }
                        };

                        if !encoded.is_empty() {
                            let sample = Sample {
                                data: encoded.into(),
                                timestamp: SystemTime::now(),
                                duration: Duration::from_millis(
                                    FRAME_DURATION_MS,
                                ),
                                ..Default::default()
                            };
                            if let Err(e) =
                                track_clone.write_sample(&sample).await
                            {
                                error!("write_sample failed: {e}");
                            }
                        }
                    }
                }
                debug!("AudioCapture: encoding task exited");
            });

            let stream = device
                .build_input_stream(
                    &config,
                    move |data: &[f32], _info| {
                        let _ = pcm_tx.try_send(data.to_vec());
                    },
                    move |err| {
                        error!("cpal stream error: {err}");
                    },
                    None,
                )
                .map_err(|e| {
                    CallError::Media(format!("build_input_stream: {e}"))
                })?;

            stream
                .play()
                .map_err(|e| CallError::Media(format!("stream.play: {e}")))?;

            Ok(Self {
                _stream: stream,
                _task: task,
                track,
            })
        }

        /// Return the audio track for registration with peer connections.
        pub fn track(&self) -> Arc<TrackLocalStaticSample> {
            Arc::clone(&self.track)
        }
    }
}

// ============================================================================
// Video capture (feature = "video")
// ============================================================================

#[cfg(feature = "video")]
mod video {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::{Duration, SystemTime};

    use tracing::{debug, error};
    use webrtc::media::Sample;
    use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
    use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;

    use crate::error::CallError;

    const VIDEO_CLOCK_RATE: u32 = 90_000;

    #[cfg(feature = "vp8")]
    const MIME_TYPE: &str = "video/VP8";
    #[cfg(not(feature = "vp8"))]
    const MIME_TYPE: &str = "video/x-raw";

    pub struct VideoCapture {
        stop: Arc<AtomicBool>,
        _task: std::thread::JoinHandle<()>,
        track: Arc<TrackLocalStaticSample>,
    }

    unsafe impl Send for VideoCapture {}
    unsafe impl Sync for VideoCapture {}

    // ============================================================
    // Linux: direct v4l crate (YUYV -> I420 -> VP8)
    // ============================================================
    #[cfg(target_os = "linux")]
    impl VideoCapture {
        pub fn try_new() -> Result<Self, CallError> {
            use v4l::buffer::Type;
            use v4l::io::mmap::Stream as MmapStream;
            use v4l::io::traits::CaptureStream;
            use v4l::video::Capture;
            use v4l::{Format, FourCC};

            let stop = Arc::new(AtomicBool::new(false));
            let stop_clone = Arc::clone(&stop);

            let track = Arc::new(TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: MIME_TYPE.to_owned(),
                    clock_rate: VIDEO_CLOCK_RATE,
                    ..Default::default()
                },
                "video".to_owned(),
                "webrtc-rs".to_owned(),
            ));
            let track_clone = Arc::clone(&track);

            let handle = tokio::runtime::Handle::current();
            let task = std::thread::spawn(move || {
                let dev = match v4l::Device::new(0) {
                    Ok(d) => d,
                    Err(e) => {
                        error!("v4l Device::new(0): {e}");
                        return;
                    }
                };

                let dev_name = dev.query_caps().map(|c| c.card).unwrap_or_else(|_| "unknown".into());

                let fmt = Format::new(640, 480, FourCC::new(b"YUYV"));
                match dev.set_format(&fmt) {
                    Ok(f) => debug!(
                        "VideoCapture: device={name}, {w}x{h} {fcc:?}",
                        name = dev_name,
                        w = f.width,
                        h = f.height,
                        fcc = f.fourcc
                    ),
                    Err(e) => {
                        error!("v4l set_format(YUYV 640x480): {e}");
                        return;
                    }
                }

                let mut stream = match MmapStream::new(&dev, Type::VideoCapture) {
                    Ok(s) => s,
                    Err(e) => {
                        error!("v4l MmapStream: {e}");
                        return;
                    }
                };

                let expected_yuyv_size = 640 * 480 * 2;

                #[cfg(feature = "vp8")]
                let mut vp8_encoder: Option<(vpx_rs::Encoder<u8>, i64)> = {
                    use std::num::NonZero;
                    vpx_rs::EncoderConfig::<u8>::new(
                        vpx_rs::enc::CodecId::VP8,
                        640,
                        480,
                        vpx_rs::Timebase {
                            num: NonZero::new(1).unwrap(),
                            den: NonZero::new(30).unwrap(),
                        },
                        vpx_rs::RateControl::ConstantBitRate(1_000_000),
                    )
                    .ok()
                    .and_then(|config| vpx_rs::Encoder::<u8>::new(config).ok())
                    .map(|encoder| (encoder, 0))
                };

                let mut frame_count: u64 = 0;

                loop {
                    if stop_clone.load(Ordering::Relaxed) {
                        debug!("VideoCapture: stopping");
                        break;
                    }

                    let (buf, meta) = match stream.next() {
                        Ok(t) => t,
                        Err(e) => {
                            error!("v4l stream.next: {e}");
                            continue;
                        }
                    };

                    if meta.bytesused as usize != expected_yuyv_size {
                        continue;
                    }

                    frame_count += 1;
                    let frame_data = &buf[..expected_yuyv_size];

                    #[cfg(feature = "vp8")]
                    let data = {
                        if let Some((ref mut enc, ref mut fc)) = vp8_encoder {
                            let yuv = yuyv_to_i420(frame_data, 640, 480);
                            let img = vpx_rs::YUVImageData::<u8>::from_raw_data(
                                vpx_rs::ImageFormat::I420,
                                640,
                                480,
                                &yuv,
                            );
                            match img.and_then(|image| {
                                enc.encode(
                                    *fc,
                                    1,
                                    image,
                                    vpx_rs::EncodingDeadline::Realtime,
                                    vpx_rs::EncoderFrameFlags::empty(),
                                )
                                .map_err(|e| e.into())
                            }) {
                                Ok(packets) => {
                                    *fc += 1;
                                    let mut data = Vec::new();
                                    for p in packets {
                                        if let vpx_rs::Packet::CompressedFrame(f) = p {
                                            data.extend_from_slice(&f.data);
                                        }
                                    }
                                    data
                                }
                                Err(e) => {
                                    error!("VP8 encode: {e}");
                                    continue;
                                }
                            }
                        } else {
                            frame_data.to_vec()
                        }
                    };
                    #[cfg(not(feature = "vp8"))]
                    let data: Vec<u8> = frame_data.to_vec();

                    let sample = Sample {
                        data: data.into(),
                        timestamp: SystemTime::now(),
                        duration: Duration::from_secs_f64(1.0 / 30.0),
                        ..Default::default()
                    };

                    if frame_count <= 3 {
                        debug!(
                            "video write_sample #{count}: {len} bytes",
                            count = frame_count,
                            len = sample.data.len()
                        );
                    }

                    if let Err(e) = handle.block_on(track_clone.write_sample(&sample)) {
                        error!("video write_sample: {e}");
                    }
                }
            });

            Ok(Self { stop, _task: task, track })
        }

        pub fn track(&self) -> Arc<TrackLocalStaticSample> {
            Arc::clone(&self.track)
        }
    }

    /// Convert YUYV (packed 4:2:2) to I420 (planar 4:2:0).
    #[cfg(target_os = "linux")]
    fn yuyv_to_i420(yuyv: &[u8], width: usize, height: usize) -> Vec<u8> {
        let y_size = width * height;
        let uv_size = (width / 2) * (height / 2);
        let mut i420 = vec![0u8; y_size + 2 * uv_size];
        let (y_plane, rest) = i420.split_at_mut(y_size);
        let (u_plane, v_plane) = rest.split_at_mut(uv_size);

        for j in 0..height {
            let row = &yuyv[j * width * 2..];
            for i in 0..(width / 2) {
                let y0 = row[i * 4];
                let u0 = row[i * 4 + 1];
                let y1 = row[i * 4 + 2];
                let v0 = row[i * 4 + 3];

                y_plane[j * width + i * 2] = y0;
                y_plane[j * width + i * 2 + 1] = y1;

                if j % 2 == 0 {
                    let uv_idx = (j / 2) * (width / 2) + i;
                    u_plane[uv_idx] = u0;
                    v_plane[uv_idx] = v0;
                }
            }
        }

        i420
    }

    // ============================================================
    // Non-Linux: nokhwa fallback
    // ============================================================
    #[cfg(not(target_os = "linux"))]
    impl VideoCapture {
        pub fn try_new() -> Result<Self, CallError> {
            use nokhwa::pixel_format::RgbFormat;
            use nokhwa::query;
            use nokhwa::utils::{
                CameraFormat, FrameFormat, RequestedFormat, RequestedFormatType, Resolution,
            };

            let stop = Arc::new(AtomicBool::new(false));
            let stop_clone = Arc::clone(&stop);

            let track = Arc::new(TrackLocalStaticSample::new(
                RTCRtpCodecCapability {
                    mime_type: MIME_TYPE.to_owned(),
                    clock_rate: VIDEO_CLOCK_RATE,
                    ..Default::default()
                },
                "video".to_owned(),
                "webrtc-rs".to_owned(),
            ));
            let track_clone = Arc::clone(&track);

            let handle = tokio::runtime::Handle::current();
            let task = std::thread::spawn(move || {
                let cameras = match query(nokhwa::utils::ApiBackend::Auto) {
                    Ok(c) => c,
                    Err(e) => {
                        error!("camera query: {e}");
                        return;
                    }
                };

                let camera_info = match cameras.first() {
                    Some(ci) => ci,
                    None => {
                        error!("no camera found");
                        return;
                    }
                };

                let format = CameraFormat::new(Resolution::new(640, 480), FrameFormat::MJPEG, 30);
                let requested =
                    RequestedFormat::new::<RgbFormat>(RequestedFormatType::Exact(format));

                let mut camera =
                    match nokhwa::Camera::new(camera_info.index().clone(), requested) {
                        Ok(c) => c,
                        Err(e) => {
                            error!("Camera::new: {e}");
                            return;
                        }
                    };

                if let Err(e) = camera.open_stream() {
                    error!("open_stream: {e}");
                    return;
                }

                debug!("VideoCapture: camera={}", camera_info.human_name());

                #[cfg(feature = "vp8")]
                let mut vp8_encoder: Option<(vpx_rs::Encoder<u8>, i64)> = {
                    use std::num::NonZero;
                    vpx_rs::EncoderConfig::<u8>::new(
                        vpx_rs::enc::CodecId::VP8,
                        640,
                        480,
                        vpx_rs::Timebase {
                            num: NonZero::new(1).unwrap(),
                            den: NonZero::new(30).unwrap(),
                        },
                        vpx_rs::RateControl::ConstantBitRate(1_000_000),
                    )
                    .ok()
                    .and_then(|config| vpx_rs::Encoder::<u8>::new(config).ok())
                    .map(|encoder| (encoder, 0))
                };

                loop {
                    if stop_clone.load(Ordering::Relaxed) {
                        break;
                    }

                    std::thread::sleep(Duration::from_millis(33));

                    let frame = match camera.frame() {
                        Ok(f) => f,
                        Err(e) => {
                            error!("camera frame: {e}");
                            continue;
                        }
                    };

                    #[cfg(feature = "vp8")]
                    let data = {
                        if let Some((ref mut enc, ref mut fc)) = vp8_encoder {
                            let rgb = frame.buffer();
                            let yuv = rgb_to_i420(rgb, 640, 480);
                            let img = vpx_rs::YUVImageData::<u8>::from_raw_data(
                                vpx_rs::ImageFormat::I420,
                                640,
                                480,
                                &yuv,
                            );
                            match img.and_then(|image| {
                                enc.encode(
                                    *fc,
                                    1,
                                    image,
                                    vpx_rs::EncodingDeadline::Realtime,
                                    vpx_rs::EncoderFrameFlags::empty(),
                                )
                                .map_err(|e| e.into())
                            }) {
                                Ok(packets) => {
                                    *fc += 1;
                                    let mut data = Vec::new();
                                    for p in packets {
                                        if let vpx_rs::Packet::CompressedFrame(f) = p {
                                            data.extend_from_slice(&f.data);
                                        }
                                    }
                                    data
                                }
                                Err(e) => {
                                    error!("VP8 encode: {e}");
                                    continue;
                                }
                            }
                        } else {
                            frame.buffer().to_vec()
                        }
                    };
                    #[cfg(not(feature = "vp8"))]
                    let data: Vec<u8> = frame.buffer().to_vec();

                    let sample = Sample {
                        data: data.into(),
                        timestamp: SystemTime::now(),
                        duration: Duration::from_secs_f64(1.0 / 30.0),
                        ..Default::default()
                    };

                    if let Err(e) = handle.block_on(track_clone.write_sample(&sample)) {
                        error!("video write_sample: {e}");
                    }
                }
            });

            Ok(Self { stop, _task: task, track })
        }

        pub fn track(&self) -> Arc<TrackLocalStaticSample> {
            Arc::clone(&self.track)
        }
    }

    impl Drop for VideoCapture {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::Relaxed);
        }
    }

    /// Convert RGB24 to I420 (YUV 4:2:0 planar) for VP8 encoding.
    #[cfg(not(target_os = "linux"))]
    fn rgb_to_i420(rgb: &[u8], width: usize, height: usize) -> Vec<u8> {
        let y_size = width * height;
        let uv_size = (width / 2) * (height / 2);
        let mut yuv = vec![0u8; y_size + 2 * uv_size];
        let (y_plane, rest) = yuv.split_at_mut(y_size);
        let (u_plane, v_plane) = rest.split_at_mut(uv_size);

        for j in 0..height {
            for i in 0..width {
                let idx = (j * width + i) * 3;
                let r = rgb[idx] as f32;
                let g = rgb[idx + 1] as f32;
                let b = rgb[idx + 2] as f32;

                y_plane[j * width + i] = (0.299 * r + 0.587 * g + 0.114 * b) as u8;

                if i % 2 == 0 && j % 2 == 0 {
                    let u = (-0.169 * r - 0.331 * g + 0.500 * b + 128.0).clamp(0.0, 255.0) as u8;
                    let v = (0.500 * r - 0.419 * g - 0.081 * b + 128.0).clamp(0.0, 255.0) as u8;
                    let uv_idx = (j / 2) * (width / 2) + (i / 2);
                    u_plane[uv_idx] = u;
                    v_plane[uv_idx] = v;
                }
            }
        }

        yuv
    }
}

// ============================================================================
// MediaManager (feature = "webrtc")
// ============================================================================

#[cfg(feature = "webrtc")]
mod manager {
    use std::sync::Arc;

    use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
    use webrtc::track::track_local::TrackLocal;

    use crate::connection::PeerConnection;
    use crate::error::CallError;

    #[cfg(feature = "audio")]
    use super::audio::AudioCapture;
    #[cfg(feature = "video")]
    use super::video::VideoCapture;

    /// Manages local media tracks for a WebRTC call.
    ///
    /// One [`MediaManager`] per [`CallManager`].  Media capture pipelines
    /// (microphone, camera) are lazily created on first use and then
    /// **shared** across all calls and peer connections — calling
    /// `create_local_audio_track()` a second time returns the same
    /// `Arc<Track>`.
    ///
    /// Capture stops automatically when the [`MediaManager`] (and hence
    /// the owning [`CallManager`]) are dropped.
    ///
    /// # Lifecycle
    ///
    /// ```text
    /// MediaManager::new()
    ///   → create_local_audio_track()   // opens mic, starts encoder task
    ///   → create_local_audio_track()   // returns existing track (no re-open)
    ///   → create_local_video_track()   // opens camera (same beat)
    ///   → add_tracks_to_connection()   // for each peer in each call
    ///   → (drop)                       // stops all captures
    /// ```
    pub struct MediaManager {
        #[cfg(feature = "audio")]
        audio_capture: Option<Arc<AudioCapture>>,

        #[cfg(feature = "video")]
        video_capture: Option<Arc<VideoCapture>>,

        /// External audio track (escape hatch when `audio` feature is
        /// disabled or the built-in pipeline is insufficient).
        external_audio: Option<Arc<dyn TrackLocal + Send + Sync>>,

        /// External video track (same escape hatch rationale).
        external_video: Option<Arc<dyn TrackLocal + Send + Sync>>,
    }

    impl MediaManager {
        /// Create a new [`MediaManager`] with no captures or tracks
        /// allocated yet.
        pub fn new() -> Self {
            Self {
                #[cfg(feature = "audio")]
                audio_capture: None,
                #[cfg(feature = "video")]
                video_capture: None,
                external_audio: None,
                external_video: None,
            }
        }

        // ---------------------------------------------------------------
        // Audio
        // ---------------------------------------------------------------

        /// Create a local audio track by opening the default microphone.
        ///
        /// Requires the `audio` feature.  **Idempotent:** subsequent calls
        /// return the same track without re-opening the device.
        #[cfg(feature = "audio")]
        pub fn create_local_audio_track(
            &mut self,
        ) -> Result<Arc<TrackLocalStaticSample>, CallError> {
            if let Some(ref cap) = self.audio_capture {
                return Ok(cap.track());
            }
            let capture = AudioCapture::try_new()?;
            let track = capture.track();
            self.audio_capture = Some(Arc::new(capture));
            Ok(track)
        }

        /// Fallback: audio feature not enabled.
        #[cfg(not(feature = "audio"))]
        pub fn create_local_audio_track(
            &mut self,
        ) -> Result<Arc<TrackLocalStaticSample>, CallError> {
            Err(CallError::Media(
                "audio capture requires the 'audio' feature".into(),
            ))
        }

        /// Return a reference to the active audio track, if any.
        pub fn audio_track(
            &self,
        ) -> Option<Arc<dyn TrackLocal + Send + Sync>> {
            #[cfg(feature = "audio")]
            if let Some(ref cap) = self.audio_capture {
                return Some(cap.track());
            }
            self.external_audio.clone()
        }

        // ---------------------------------------------------------------
        // Video
        // ---------------------------------------------------------------

        /// Create a local video track by opening the default camera.
        ///
        /// Requires the `video` feature.  **Idempotent:** subsequent calls
        /// return the same track without re-opening the device.
        #[cfg(feature = "video")]
        pub fn create_local_video_track(
            &mut self,
        ) -> Result<Arc<TrackLocalStaticSample>, CallError> {
            if let Some(ref cap) = self.video_capture {
                return Ok(cap.track());
            }
            let capture = VideoCapture::try_new()?;
            let track = capture.track();
            self.video_capture = Some(Arc::new(capture));
            Ok(track)
        }

        /// Fallback: video feature not enabled.
        #[cfg(not(feature = "video"))]
        pub fn create_local_video_track(
            &mut self,
        ) -> Result<Arc<TrackLocalStaticSample>, CallError> {
            Err(CallError::Media(
                "video capture requires the 'video' feature".into(),
            ))
        }

        /// Return a reference to the active video track, if any.
        pub fn video_track(
            &self,
        ) -> Option<Arc<dyn TrackLocal + Send + Sync>> {
            #[cfg(feature = "video")]
            if let Some(ref cap) = self.video_capture {
                return Some(cap.track());
            }
            self.external_video.clone()
        }

        // ---------------------------------------------------------------
        // External tracks (escape hatches)
        // ---------------------------------------------------------------

        /// Inject an externally-created audio track.
        pub fn set_audio_track(
            &mut self,
            track: Arc<dyn TrackLocal + Send + Sync>,
        ) {
            self.external_audio = Some(track);
        }

        /// Inject an externally-created video track.
        pub fn set_video_track(
            &mut self,
            track: Arc<dyn TrackLocal + Send + Sync>,
        ) {
            self.external_video = Some(track);
        }

        // ---------------------------------------------------------------
        // Mesh wiring
        // ---------------------------------------------------------------

        /// Add all active local tracks to the given [`PeerConnection`].
        pub async fn add_tracks_to_connection(
            &self,
            conn: &PeerConnection,
        ) -> Result<(), CallError> {
            if let Some(ref t) = self.audio_track() {
                conn.add_local_track(Arc::clone(t)).await?;
            }
            if let Some(ref t) = self.video_track() {
                conn.add_local_track(Arc::clone(t)).await?;
            }
            Ok(())
        }
    }

    impl Default for MediaManager {
        fn default() -> Self {
            Self::new()
        }
    }
}

#[cfg(feature = "webrtc")]
pub use manager::MediaManager;

#[cfg(feature = "audio")]
pub use audio::AudioCapture;
#[cfg(feature = "video")]
pub use video::VideoCapture;

