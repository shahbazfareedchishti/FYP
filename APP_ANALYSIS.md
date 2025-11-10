# Sound Detection App - Comprehensive Analysis

## 🎯 App Purpose & Domain

**Marine/Underwater Sound Classification System**

Your app is a **specialized sound detection and classification application** designed to identify and analyze marine/underwater acoustic signatures. It's specifically built to detect and classify three types of marine vessels:

1. **SpeedBoat** - High-speed surface vessels
2. **UUV (Unmanned Underwater Vehicle)** - Autonomous underwater vehicles
3. **KaiYuan** - Another type of marine vessel (likely a specific boat model/type)

## 🏗️ Architecture Overview

### **Tech Stack:**
- **Frontend**: Flutter (Dart)
- **Backend ML API**: HuggingFace Space (`shahbazfareedchishti-sound-detection.hf.space`)
- **Local Database**: SQLite (via sqflite)
- **Audio Recording**: `record` package
- **HTTP Client**: `http` package

### **Architecture Pattern:**
- **Service-Oriented**: Separation of concerns with dedicated services
- **State Management**: StatefulWidget with local state
- **Data Persistence**: Local SQLite database for user accounts and detection history

## 🔄 User Flow & Features

### **1. Authentication System**
```
Login Screen → Register Screen → Forgot Password
     ↓
Main Screen (if authenticated)
```

**Features:**
- User registration with username, email, password
- Login/logout functionality
- Session persistence (checks auth status on app start)
- Password reset flow (UI ready, backend TODO)

### **2. Main Detection Flow**
```
1. User taps detection button
2. App requests microphone permission
3. Records 3 seconds of audio (16kHz, mono, WAV)
4. Sends audio file to ML API
5. Receives classification results + SNR analysis
6. Displays results with confidence scores
7. Saves detection to local database (if logged in)
```

### **3. Sound Detection Process**

**Recording Specifications:**
- **Duration**: 3 seconds
- **Sample Rate**: 16,000 Hz
- **Format**: WAV (mono channel)
- **Permission**: Microphone access required

**ML API Integration:**
- **Endpoint**: `https://shahbazfareedchishti-sound-detection.hf.space/stream`
- **Method**: POST multipart/form-data
- **Input**: Audio WAV file
- **Output**: JSON with:
  - `predicted_class`: One of [SpeedBoat, UUV, KaiYuan]
  - `confidence`: Percentage (0-100)
  - `all_predictions`: Confidence scores for all classes
  - `snr_analysis`: Signal-to-Noise Ratio metrics
    - `snr_db`: SNR in decibels
    - `quality`: Quality rating (Excellent/Good/Fair/Poor/Very Poor)
    - `signal_spectrum`: Frequency spectrum of signal
    - `noise_spectrum`: Frequency spectrum of noise
    - `signal_percentage`: % of recording that's signal
    - `noise_percentage`: % of recording that's noise
    - `spectral_features`: Advanced audio features

### **4. Signal Analysis (SNR)**

**What is SNR?**
Signal-to-Noise Ratio measures the quality of the audio recording by comparing the strength of the target signal (marine vessel sound) to background noise.

**SNR Quality Levels:**
- **Excellent**: ≥25 dB
- **Good**: ≥20 dB
- **Fair**: ≥15 dB
- **Poor**: ≥10 dB
- **Very Poor**: <10 dB

**Visualization Features:**
- SNR meter with color-coded quality indicator
- Frequency spectrum plots (signal vs noise)
- Signal/Noise distribution charts
- Detailed metrics (duration, segments, spectral features)

### **5. Detection History (Logs)**
- Stores all detections in local SQLite database
- Shows: Sound class, confidence, timestamp
- User-specific (filtered by logged-in user)
- Chronological display (newest first)

### **6. Account Management**
- View account information
- Change password (UI ready, functionality TODO)

## 📊 Data Flow

```
┌─────────────┐
│   User      │
│  (Mobile)   │
└──────┬──────┘
       │
       │ 1. Tap Detect
       ▼
┌─────────────────────┐
│  SoundDetectionService│
│  - Record 3s audio    │
│  - Convert to WAV    │
└──────┬──────────────┘
       │
       │ 2. POST audio file
       ▼
┌──────────────────────┐
│  HuggingFace ML API  │
│  - Audio analysis    │
│  - Classification    │
│  - SNR calculation   │
└──────┬───────────────┘
       │
       │ 3. Return JSON
       ▼
┌──────────────────────┐
│  MainScreen          │
│  - Display results   │
│  - Show SNR analysis │
└──────┬───────────────┘
       │
       │ 4. Save to DB
       ▼
┌──────────────────────┐
│  DatabaseHelper      │
│  - SQLite storage    │
│  - User detections   │
└──────────────────────┘
```

## 🎨 UI/UX Features

### **Visual Design:**
- **Theme**: Dark navy background (`#001220`)
- **Primary Color**: Purple gradient (`#8C6EF2`)
- **Accent Colors**: 
  - SpeedBoat: Green (`#4CAF50`)
  - UUV: Blue (`#2196F3`)
  - KaiYuan: Orange (`#FF9800`)

### **Animations:**
- Pulsing detection button (scale animation)
- Animated wave bars during recording
- Smooth transitions between screens
- Loading indicators

### **Interactive Elements:**
- Large circular detection button (200x200)
- Drawer navigation menu
- Modal bottom sheets for detailed analysis
- Snackbar notifications with action buttons

## 🔬 Technical Implementation Details

### **Audio Processing:**
- **Format**: WAV (uncompressed for quality)
- **Sample Rate**: 16kHz (optimal for voice/marine sounds)
- **Channels**: Mono (reduces file size, sufficient for classification)
- **File Handling**: Temporary directory, auto-cleanup

### **API Communication:**
- Multipart file upload
- Error handling with fallback data
- Response validation
- Debug logging throughout

### **Database Schema:**
```sql
users:
  - id (PRIMARY KEY)
  - username (UNIQUE)
  - email (UNIQUE)
  - password (plain text - should be hashed!)
  - created_at

sound_detections:
  - id (PRIMARY KEY)
  - user_id (FOREIGN KEY)
  - sound_class (SpeedBoat/UUV/KaiYuan)
  - confidence (REAL)
  - timestamp
  - latitude (NULL - for future GPS)
  - longitude (NULL - for future GPS)
```

### **State Management:**
- Local state in StatefulWidget
- Service instances (SoundDetectionService, DatabaseHelper)
- Static auth state (AuthService)

## 🎯 Use Cases

### **Primary Use Case:**
Marine surveillance, underwater monitoring, or research application where users need to:
1. Record ambient sounds
2. Identify if marine vessels are present
3. Analyze signal quality
4. Track detection history

### **Potential Applications:**
- **Marine Research**: Studying underwater acoustic environments
- **Security/Monitoring**: Detecting vessels in restricted areas
- **Environmental Monitoring**: Tracking marine traffic
- **Educational**: Teaching sound classification concepts

## 🔍 Analysis Components

### **Currently Active:**
1. **SNR Analysis** (`snr.dart` + `snr_visualization.dart`)
   - Real-time signal quality assessment
   - Frequency spectrum visualization
   - Signal vs noise distribution

### **Available but Unused:**
1. **FFT Analysis** (`fft_analysis.dart`)
   - Fast Fourier Transform computation
   - Power spectrum analysis
   - Frequency peak detection
   - Ultra-sensitive peak detection algorithm

2. **FFT Display** (`fft_analysis_display.dart`)
   - Power spectrum visualization
   - Frequency peaks display
   - Spectrogram image support

3. **Mel Spectrogram Display** (`mel_spectrogram_display.dart`)
   - Advanced waveform visualization
   - Noise segment annotation
   - Audio waveform with timeline
   - Enhanced audio analysis display

## ⚠️ Security Considerations

1. **Password Storage**: Currently stored in plain text - **CRITICAL**: Should use hashing (bcrypt, Argon2)
2. **API Key**: No API key needed (public HuggingFace endpoint)
3. **Permissions**: Properly requests microphone permission
4. **Data Privacy**: Local storage only, no cloud sync

## 🚀 Potential Enhancements

1. **Real-time Streaming**: Continuous monitoring instead of 3-second clips
2. **GPS Integration**: Add location data to detections
3. **Offline Mode**: Local ML model for offline detection
4. **Export Data**: CSV/JSON export of detection history
5. **Advanced Filtering**: Filter logs by date, class, confidence
6. **Sound Visualization**: Real-time waveform during recording
7. **Multi-user Support**: Share detections across team
8. **Cloud Sync**: Backup detections to cloud

## 📝 Summary

Your app is a **professional-grade marine sound classification system** that:
- ✅ Records high-quality audio (16kHz WAV)
- ✅ Uses ML/AI for sound classification
- ✅ Provides detailed signal analysis (SNR)
- ✅ Maintains detection history
- ✅ Has beautiful, intuitive UI
- ✅ Includes comprehensive audio analysis tools (some unused)

The unused files (`fft_analysis.dart`, `fft_analysis_display.dart`, `mel_spectrogram_display.dart`) appear to be **alternative analysis methods** that could be integrated as additional visualization options or fallback analysis when the API is unavailable.

