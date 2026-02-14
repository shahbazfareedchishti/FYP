import numpy as np
import librosa
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchaudio.transforms as T
import io
import warnings
import os
import traceback
import scipy.ndimage
import soundfile as sf
import base64
import datetime

warnings.filterwarnings('ignore')

TASNET_SR = 52734
TASNET_DURATION = 3.0
TASNET_N_SAMPLES = int(TASNET_SR * TASNET_DURATION)
TASNET_ENC_CHANNELS = 384
TASNET_BOTTLE_CHANNELS = 192
TASNET_NUM_LAYERS = 4
TASNET_KERNEL_SIZE = 3
TASNET_DILATION_BASE = 2
TASNET_EPS = 1e-9

class TasNetDenoiser(nn.Module):
    """
    TasNet denoiser architecture from task3_test1(2).py
    Replaces U-Net for time-domain audio denoising
    """
    def __init__(self, enc_channels=384, bottle_channels=192, num_layers=4):
        super().__init__()
        
        self.encoder = nn.Sequential(
            nn.Conv1d(1, enc_channels, kernel_size=16, stride=8, bias=False),
            nn.PReLU()
        )
        
        self.gln = nn.GroupNorm(1, enc_channels)
        
        self.separator = nn.ModuleList()
        for i in range(num_layers):
            dilation = 2 ** i
            self.separator.append(
                nn.Sequential(
                    nn.Conv1d(enc_channels, bottle_channels, 1),
                    nn.PReLU(),
                    nn.GroupNorm(1, bottle_channels),
                    nn.Conv1d(bottle_channels, bottle_channels,
                              kernel_size=3, padding=dilation, dilation=dilation,
                              groups=bottle_channels),
                    nn.PReLU(),
                    nn.GroupNorm(1, bottle_channels),
                    nn.Conv1d(bottle_channels, enc_channels, 1)
                )
            )
        
        self.lstm = nn.LSTM(enc_channels, enc_channels, bidirectional=True, batch_first=True)
        self.lstm_proj = nn.Linear(enc_channels*2, enc_channels)
        
        self.decoder = nn.ConvTranspose1d(enc_channels, 1, kernel_size=16, stride=8, bias=False)
        
        self.out_scale = nn.Parameter(torch.ones(1))
    
    def forward(self, x):
        """
        Forward pass for TasNet denoiser
        Args:
            x: Input audio tensor [batch_size, samples] or [batch_size, 1, samples]
        Returns:
            Denoised audio tensor [batch_size, samples]
        """
        if x.dim() == 2:
            x = x.unsqueeze(1)
        
        enc = self.encoder(x)
        latent = self.gln(enc)
        
        skip = 0
        for block in self.separator:
            res = block(latent)
            skip += res
            latent += res
        
        latent = latent.permute(0, 2, 1)
        lstm_out, _ = self.lstm(latent)
        latent = self.lstm_proj(lstm_out).permute(0, 2, 1)
        
        out = self.decoder(latent).squeeze(1)
        out = out * self.out_scale
        
        T = x.shape[-1]
        if out.shape[-1] != T:
            if out.shape[-1] > T:
                out = out[..., :T]
            else:
                out = F.pad(out, (0, T - out.shape[-1]))
        
        return out


class Discriminator(nn.Module):
    """
    PatchGAN-style discriminator for adversarial training
    From task3_test1(2).py
    """
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.utils.spectral_norm(nn.Conv1d(1, 64, 4, stride=2, padding=1)),
            nn.LeakyReLU(0.2, inplace=True),
            nn.utils.spectral_norm(nn.Conv1d(64, 128, 4, stride=2, padding=1)),
            nn.LeakyReLU(0.2, inplace=True),
            nn.utils.spectral_norm(nn.Conv1d(128, 256, 4, stride=2, padding=1)),
            nn.LeakyReLU(0.2, inplace=True),
            nn.utils.spectral_norm(nn.Conv1d(256, 1, 4, stride=1, padding=0)),
        )
    
    def forward(self, x):
        if x.dim() == 2:
            x = x.unsqueeze(1)
        return self.net(x)


def mr_stft_loss(est, target, device='cpu'):
    """
    Multi-Resolution STFT Loss
    From task3_test1(2).py
    """
    loss = 0.0
    fft_sizes = [512, 1024, 2048]
    
    for n_fft in fft_sizes:
        window = torch.hann_window(n_fft).to(device)
        
        def stft(x):
            return torch.stft(x, n_fft=n_fft, hop_length=n_fft//4,
                            window=window, return_complex=True)
        
        est_spec = stft(est)
        tgt_spec = stft(target)
        
        mag_est = est_spec.abs()
        mag_tgt = tgt_spec.abs()
        
        loss += F.l1_loss(mag_est, mag_tgt)
        
        loss += F.l1_loss(est_spec.angle(), tgt_spec.angle()) * 0.05
    
    return loss / len(fft_sizes)


def si_snr_loss(est, target, eps=1e-8):
    """
    Scale-Invariant Signal-to-Noise Ratio Loss
    From task3_test1(2).py
    """
    est = est - est.mean(dim=1, keepdim=True)
    target = target - target.mean(dim=1, keepdim=True)
    
    dot = (est * target).sum(dim=1, keepdim=True)
    target_pow = torch.clamp((target**2).sum(dim=1, keepdim=True), min=eps)
    proj = dot * target / target_pow
    
    noise = est - proj
    
    ratio = 10 * torch.log10((proj.norm(dim=1)**2 + eps) / (noise.norm(dim=1)**2 + eps))
    
    return -ratio.mean()


def gan_loss_D(disc_real, disc_fake):
    """
    Discriminator loss for GAN training
    From task3_test1(2).py
    """
    real_loss = F.relu(1 - disc_real).mean()
    fake_loss = F.relu(1 + disc_fake).mean()
    return real_loss + fake_loss


def gan_loss_G(disc_fake):
    """
    Generator loss for GAN training
    From task3_test1(2).py
    """
    return -disc_fake.mean()


class OldCRNN(nn.Module):
    def __init__(self, input_channels=1, num_classes=1, hidden_size=128):
        super(OldCRNN, self).__init__()
        self.conv1 = nn.Conv2d(input_channels, 32, kernel_size=3, padding=1)
        self.bn1 = nn.BatchNorm2d(32)
        self.pool1 = nn.MaxPool2d(kernel_size=2)
        self.conv2 = nn.Conv2d(32, 64, kernel_size=3, padding=1)
        self.bn2 = nn.BatchNorm2d(64)
        self.pool2 = nn.MaxPool2d(kernel_size=2)
        self.conv3 = nn.Conv2d(64, 128, kernel_size=3, padding=1)
        self.bn3 = nn.BatchNorm2d(128)
        self.pool3 = nn.MaxPool2d(kernel_size=2)
        self.dropout = nn.Dropout(0.3)
        self.cnn_output_size = self._calculate_cnn_output_size()
        self.rnn = nn.GRU(input_size=self.cnn_output_size, hidden_size=hidden_size, num_layers=2, batch_first=True, bidirectional=True, dropout=0.3)
        self.fc1 = nn.Linear(hidden_size * 2, 64)
        self.fc2 = nn.Linear(64, num_classes)
    
    def _calculate_cnn_output_size(self):
        dummy_input = torch.zeros(1, 1, 128, 311)
        with torch.no_grad():
            x = self._cnn_forward(dummy_input, feature_only=True)
        return x.shape[1] * x.shape[2]
    
    def _cnn_forward(self, x, feature_only=False):
        x = F.relu(self.bn1(self.conv1(x)))
        x = self.pool1(x)
        x = F.relu(self.bn2(self.conv2(x)))
        x = self.pool2(x)
        x = F.relu(self.bn3(self.conv3(x)))
        x = self.pool3(x)
        if feature_only: return x
        x = self.dropout(x)
        return x
    
    def forward(self, x):
        batch_size = x.size(0)
        x = self._cnn_forward(x)
        x = x.permute(0, 3, 1, 2)
        x = x.reshape(batch_size, x.size(1), -1)
        rnn_out, _ = self.rnn(x)
        rnn_out = rnn_out[:, -1, :]
        x = F.relu(self.fc1(rnn_out))
        x = self.dropout(x)
        x = self.fc2(x)
        return x


class NewCRNN(nn.Module):
    def __init__(self, input_channels=1, num_classes=3, hidden_size=128):
        super(NewCRNN, self).__init__()
        self.conv1 = nn.Conv2d(input_channels, 32, kernel_size=3, padding=1)
        self.bn1 = nn.BatchNorm2d(32)
        self.conv2 = nn.Conv2d(32, 32, kernel_size=3, padding=1)
        self.bn2 = nn.BatchNorm2d(32)
        self.pool1 = nn.MaxPool2d(kernel_size=2)
        self.conv3 = nn.Conv2d(32, 64, kernel_size=3, padding=1)
        self.bn3 = nn.BatchNorm2d(64)
        self.conv4 = nn.Conv2d(64, 64, kernel_size=3, padding=1)
        self.bn4 = nn.BatchNorm2d(64)
        self.pool2 = nn.MaxPool2d(kernel_size=2)
        self.conv5 = nn.Conv2d(64, 128, kernel_size=3, padding=1)
        self.bn5 = nn.BatchNorm2d(128)
        self.conv6 = nn.Conv2d(128, 128, kernel_size=3, padding=1)
        self.bn6 = nn.BatchNorm2d(128)
        self.pool3 = nn.MaxPool2d(kernel_size=(2, 2))
        self.conv7 = nn.Conv2d(128, 256, kernel_size=3, padding=1)
        self.bn7 = nn.BatchNorm2d(256)
        self.conv8 = nn.Conv2d(256, 256, kernel_size=3, padding=1)
        self.bn8 = nn.BatchNorm2d(256)
        self.pool4 = nn.MaxPool2d(kernel_size=(2, 2))
        self.dropout = nn.Dropout(0.5)
        self.cnn_output_size = self._calculate_cnn_output_size()
        self.rnn = nn.GRU(input_size=self.cnn_output_size, hidden_size=hidden_size, num_layers=2, batch_first=True, bidirectional=True, dropout=0.3)
        self.fc1 = nn.Linear(hidden_size * 2, 128)
        self.bn9 = nn.BatchNorm1d(128)
        self.fc2 = nn.Linear(128, 64)
        self.bn10 = nn.BatchNorm1d(64)
        self.fc3 = nn.Linear(64, num_classes)
    
    def _calculate_cnn_output_size(self):
        dummy_input = torch.zeros(1, 1, 128, 311)
        with torch.no_grad():
            x = self._cnn_forward(dummy_input, feature_only=True)
        return x.shape[1] * x.shape[2]
    
    def _cnn_forward(self, x, feature_only=False):
        x = F.relu(self.bn1(self.conv1(x)))
        x = F.relu(self.bn2(self.conv2(x)))
        x = self.pool1(x)
        x = F.relu(self.bn3(self.conv3(x)))
        x = F.relu(self.bn4(self.conv4(x)))
        x = self.pool2(x)
        x = F.relu(self.bn5(self.conv5(x)))
        x = F.relu(self.bn6(self.conv6(x)))
        x = self.pool3(x)
        x = F.relu(self.bn7(self.conv7(x)))
        x = F.relu(self.bn8(self.conv8(x)))
        x = self.pool4(x)
        if feature_only: return x
        x = self.dropout(x)
        return x
    
    def forward(self, x):
        batch_size = x.size(0)
        x = self._cnn_forward(x)
        x = x.permute(0, 3, 1, 2)
        x = x.reshape(batch_size, x.size(1), -1)
        rnn_out, _ = self.rnn(x)
        rnn_out = torch.mean(rnn_out, dim=1)
        x = F.relu(self.bn9(self.fc1(rnn_out)))
        x = self.dropout(x)
        x = F.relu(self.bn10(self.fc2(x)))
        x = self.dropout(x)
        x = self.fc3(x)
        return x


class YAMNetNonShipDetector:
    def __init__(self):
        print("[Task 0] Loading YAMNet for non-ship detection...")
        import tensorflow as tf
        import tensorflow_hub as hub
        
        self.model = hub.load('https://tfhub.dev/google/yamnet/1')
        
        class_map_path = self.model.class_map_path().numpy()
        self.class_names = {}
        with open(class_map_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            for line in lines[1:]:
                parts = line.strip().split(',')
                if len(parts) >= 3:
                    try:
                        class_id = int(parts[0])
                        class_name = parts[2].strip('"')
                        self.class_names[class_id] = class_name
                    except ValueError:
                        continue
        
        self.non_ship_classes = {
            'Speech', 'Conversation', 'Narration, monologue',
            'Male speech, man speaking', 'Female speech, woman speaking',
            'Child speech, kid speaking',
            'Music', 'Singing', 'Musical instrument',
            'Rain', 'Wind', 'Thunderstorm', 'Water', 'Stream', 'Waves',
            'Bird', 'Animal', 'Dog', 'Cat', 'Insect',
            'Laughter', 'Cough', 'Sneeze', 'Crying, sobbing',
            'Chewing, mastication', 'Walk, footsteps',
            'Traffic noise, roadway noise', 'Vehicle', 'Car', 'Bus',
            'Motorcycle', 'Train', 'Siren', 'Fire alarm', 'Alarm',
            'Clock', 'Door', 'Glass', 'Tools', 'Computer keyboard',
            'Silence', 'Noise', 'Inside, small room', 'Outside, urban',
        }
        
        self.ship_classes = {
            'Boat, Water vehicle', 'Ship', 'Motorboat, speedboat',
            'Sailboat, sailing ship', 'Rowboat', 'Submarine',
            'Engine', 'Motor', 'Mechanical fan', 'Power tool'
        }
        
        print(f"[Task 0] YAMNet loaded - knows {len(self.class_names)} sound classes")
        print(f"[Task 0] Non-ship detection configured for {len(self.non_ship_classes)} categories")
    
    def analyze(self, audio, sr=52734):
        try:
            audio_16k = librosa.resample(audio, orig_sr=sr, target_sr=16000)
            
            if audio_16k.dtype != np.float32:
                audio_16k = audio_16k.astype(np.float32)
            if np.max(np.abs(audio_16k)) > 1.0:
                audio_16k = audio_16k / np.max(np.abs(audio_16k))
            
            scores, embeddings, spectrogram = self.model(audio_16k)
            scores_np = scores.numpy()
            mean_scores = np.mean(scores_np, axis=0)
            
            top_indices = np.argsort(mean_scores)[::-1][:10]
            
            detected_classes = []
            for idx in top_indices:
                class_name = self.class_names.get(idx, f"Class_{idx}").lower()
                confidence = mean_scores[idx]
                detected_classes.append((class_name, confidence))
            
            print("YAMNet Top predictions:")
            for class_name, confidence in detected_classes[:5]:
                print(f"  - {class_name.title()}: {confidence:.3f}")
            
            SHIP_PATTERNS = [
                {'engine', 'motor', 'machine'},
                {'engine', 'motor', 'tools'},
                {'engine', 'motor', 'mechanical'},
                {'engine', 'motor', 'vehicle'},
                {'engine', 'motor', 'aircraft'},
                {'engine', 'motor', 'power tool'},

                {'machine', 'mechanical', 'tools'},
                {'machine', 'mechanical', 'motor'},
                {'machine', 'mechanical', 'engine'},
                {'machine', 'mechanical', 'wood'},
                {'machine', 'mechanical', 'power tool'},

                {'tools', 'drill', 'sawing'},
                {'tools', 'drill', 'machine'},
                {'tools', 'drill', 'mechanical'},
                {'tools', 'drill', 'wood'},
                {'tools', 'drill', 'motor'},

                {'wood', 'sawing', 'tools'},
                {'wood', 'sawing', 'machine'},
                {'wood', 'sawing', 'drill'},
                {'wood', 'sawing', 'mechanical'},

                {'power tool', 'electric shaver', 'machine'},
                {'power tool', 'electric shaver', 'motor'},
                {'power tool', 'electric shaver', 'tools'},
                {'power tool', 'hair dryer', 'machine'},
                {'power tool', 'hair dryer', 'electric shaver'},

                {'vehicle', 'engine', 'motor'},
                {'vehicle', 'aircraft', 'engine'},
                {'vehicle', 'aircraft engine', 'engine'},
                {'vehicle', 'tools', 'mechanical'},

                {'aircraft', 'aircraft engine', 'engine'},
                {'aircraft', 'fixed-wing aircraft', 'engine'},
                {'aircraft', 'fixed-wing aircraft', 'aircraft engine'},
                {'aircraft', 'engine', 'motor'},

                {'vacuum cleaner', 'motor', 'mechanical'},
                {'vacuum cleaner', 'motor', 'machine'},
                {'vacuum cleaner', 'motor', 'tools'},

                {'hair dryer', 'electric shaver', 'machine'},
                {'hair dryer', 'electric shaver', 'motor'},
                {'hair dryer', 'electric shaver', 'tools'},

                {'fixed-wing aircraft', 'aircraft', 'engine'},
                {'fixed-wing aircraft', 'aircraft', 'aircraft engine'},
                {'fixed-wing aircraft', 'engine', 'motor'},

                {'aircraft engine', 'engine', 'motor'},
                {'aircraft engine', 'engine', 'machine'},
                {'aircraft engine', 'engine', 'mechanical'},

                {'engine', 'tools', 'mechanical'},
                {'motor', 'tools', 'machine'},
                {'mechanical', 'tools', 'power tool'},
                {'machine', 'motor', 'drill'},

                {'sawing', 'drill', 'wood'},
                {'electric shaver', 'hair dryer', 'vacuum cleaner'},
                {'vehicle', 'aircraft', 'motor'},
                {'power tool', 'drill', 'sawing'},

                {'jet engine', 'aircraft', 'engine'},
                {'jet engine', 'fixed-wing aircraft', 'motor'},
                {'blender', 'motor', 'mechanical'},
                {'blender', 'electric shaver', 'machine'},
                {'mechanisms', 'mechanical', 'machine'},
                {'mechanisms', 'inside', 'wood'},
                {'rattle', 'engine', 'mechanical'},
                {'chink', 'tools', 'percussion'},
                {'mouse', 'rodents', 'inside'},
                {'mouse', 'rodents', 'wood'},
                
                {'buzz', 'electric shaver', 'hair dryer'},
                {'buzz', 'sawing', 'drill'},
                {'buzz', 'motor', 'noise'},
                {'buzz', 'cacophony', 'rattle'},

                {'insect', 'buzz', 'rodents'},
                {'insect', 'wood', 'inside'},
                {'insect', 'mouse', 'noise'},

                {'insect', 'buzz', 'cacophony'}
                            ]

            MECHANICAL_CLASSES = {
                'tools', 'power tool', 'sawing', 'engine', 'drill', 
                'motor', 'mechanical', 'machine', 'wood', 'electric shaver',
                'hair dryer', 'vehicle', 'aircraft', 'vacuum cleaner',
                'fixed-wing aircraft', 'aircraft engine',
                
                'rattle', 'cacophony', 'inside', 'glass', 'mechanisms',
                'mouse', 'blender', 'rodents', 'chink', 'percussion', 
                'jet engine', 'noise',

                'insect', 'buzz'
            }

            MECHANICAL_CLASSES = {
                'tools', 'power tool', 'sawing', 'engine', 'drill', 
                'motor', 'mechanical', 'machine', 'wood', 'electric shaver',
                'hair dryer', 'vehicle', 'aircraft', 'vacuum cleaner',
                'fixed-wing aircraft', 'aircraft engine',
                
                'rattle', 'cacophony', 
                'inside', 'glass', 'mechanisms',
                'mouse', 'blender', 'rodents',
                'chink', 'percussion', 'jet engine', 'noise'
            }
            
            present_classes = set()
            for class_name, _ in detected_classes:
                for mech_class in MECHANICAL_CLASSES:
                    if mech_class in class_name:
                        present_classes.add(mech_class)
                        break
            
            print(f"\nDetected mechanical classes: {list(present_classes)}")
            
            is_ship = False
            matched_pattern = None
            
            for i, pattern in enumerate(SHIP_PATTERNS[:5]):
                if pattern.issubset(present_classes):
                    is_ship = True
                    matched_pattern = f"Pattern {i+1}: {pattern}"
                    break
            
            if not is_ship and len(present_classes) >= 4:
                is_ship = True
                matched_pattern = f"Pattern 6: 4+ mechanical classes ({len(present_classes)})"
            
            confidence = min(0.95, 0.6 + (len(present_classes) * 0.1))
            
            result = {
                'is_ship': is_ship,
                'confidence': float(confidence),
                'detected_mechanical_classes': list(present_classes),
                'matched_pattern': matched_pattern,
                'top_classes': [(class_name.title(), float(conf)) for class_name, conf in detected_classes[:5]],
                'success': True,
            }
            
            if is_ship:
                print(f"SHIP DETECTED: {matched_pattern}")
                print(f"  Confidence: {confidence:.3f}")
            else:
                print(f"NOT A SHIP: Insufficient mechanical class combinations")
                print(f"  Detected only: {list(present_classes)}")
            
            return result
            
        except Exception as e:
            print(f"[Task 0] YAMNet error: {e}")
            return {
                'is_ship': False,
                'confidence': 0.0,
                'detected_mechanical_classes': [],
                'matched_pattern': None,
                'success': False,
            }

_yamnet_detector = None

def get_yamnet_detector():
    global _yamnet_detector
    if _yamnet_detector is None:
        _yamnet_detector = YAMNetNonShipDetector()
    return _yamnet_detector


def extract_logmel_spectrogram(audio, sr=52734, duration=3):
    """
    ORIGINAL FUNCTION: For Task 1 & 2 classification
    Output shape: (128, 309)
    """
    target_samples = sr * duration
    if len(audio) < target_samples:
        audio = np.pad(audio, (0, target_samples - len(audio)))
    elif len(audio) > target_samples:
        audio = audio[:target_samples]
    
    mel_spec = librosa.feature.melspectrogram(
        y=audio, sr=sr, n_fft=2048, hop_length=512, n_mels=128, fmax=sr, power=2.0
    )
    
    log_mel = librosa.power_to_db(mel_spec, ref=np.max)
    log_mel = (log_mel - log_mel.min()) / (log_mel.max() - log_mel.min() + 1e-8)
    
    expected_frames = 309 
    current_frames = log_mel.shape[1]
    
    if current_frames < expected_frames:
        pad_width = expected_frames - current_frames
        log_mel = np.pad(log_mel, ((0, 0), (0, pad_width)), mode='constant', constant_values=log_mel.min())
    elif current_frames > expected_frames:
        log_mel = log_mel[:, :expected_frames]
    
    return log_mel.astype(np.float32)


def extract_fft(audio, sr=52734, n_fft=2048):
    """
    Extract FFT for visualization - keep this as is for UI
    """
    try:
        if len(audio) == 0:
            return np.linspace(0, sr/2, int(n_fft/2)+1), np.full(int(n_fft/2)+1, -100.0)

        rms = np.sqrt(np.mean(audio**2))
        
        if rms < 0.001:
            freqs = np.fft.rfftfreq(n_fft, 1/sr)
            return freqs, np.full_like(freqs, -100.0)

        audio = audio / np.max(np.abs(audio))
        
        fft_values = np.fft.rfft(audio * np.hanning(len(audio)), n=n_fft)
        magnitude = np.abs(fft_values)

        ref_value = np.max(magnitude)
        
        if ref_value < 1e-9:
            magnitude_db = np.full_like(magnitude, -100.0)
        else:
            magnitude_db = 20 * np.log10(np.maximum(magnitude, 1e-6) / ref_value)

        magnitude_db = np.clip(magnitude_db, -100, 0)

        frequencies = np.fft.rfftfreq(n_fft, 1/sr)

        return frequencies, magnitude_db

    except Exception as e:
        print(f"Error in extract_fft: {e}")
        traceback.print_exc()
        freqs = np.linspace(0, sr/2, 1025)
        mags = np.full_like(freqs, -100.0)
        return freqs, mags


def load_old_model(model_path):
    model = OldCRNN(num_classes=1)
    checkpoint = torch.load(model_path, map_location='cpu')
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    return model


def load_new_model(model_path):
    model = NewCRNN(num_classes=3)
    try:
        checkpoint = torch.load(model_path, map_location='cpu', weights_only=True)
    except:
        checkpoint = torch.load(model_path, map_location='cpu', weights_only=False)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    return model


def load_tasnet_model(model_path):
    """
    Load TasNet denoiser model with robust error handling
    """
    print(f"[TasNet] Loading denoising model from: {model_path}")
    
    if not os.path.exists(model_path):
        print(f"[TasNet] ERROR: Model file not found at {model_path}")
        raise FileNotFoundError(f"TasNet model not found at {model_path}")
    
    model = TasNetDenoiser(
        enc_channels=TASNET_ENC_CHANNELS,
        bottle_channels=TASNET_BOTTLE_CHANNELS,
        num_layers=TASNET_NUM_LAYERS
    )
    
    try:
        checkpoint = torch.load(model_path, map_location='cpu')
        
        state_dict_loaded = False
        
        if 'G_state_dict' in checkpoint:
            model.load_state_dict(checkpoint['G_state_dict'])
            print(f"[TasNet] Loaded generator from adversarial training checkpoint")
            state_dict_loaded = True
            
        elif 'model_state_dict' in checkpoint:
            model.load_state_dict(checkpoint['model_state_dict'])
            print(f"[TasNet] Loaded from standard checkpoint")
            state_dict_loaded = True
            
        elif 'state_dict' in checkpoint:
            model.load_state_dict(checkpoint['state_dict'])
            print(f"[TasNet] Loaded from state_dict checkpoint")
            state_dict_loaded = True
            
        else:
            try:
                model.load_state_dict(checkpoint)
                print(f"[TasNet] Loaded checkpoint directly as state_dict")
                state_dict_loaded = True
            except:
                pass
        
        if not state_dict_loaded:
            print(f"[TasNet] WARNING: Could not load checkpoint. Creating fresh model.")
        
        model.eval()
        
        print(f"[TasNet] Verifying model with test input...")
        test_input = torch.randn(1, TASNET_N_SAMPLES)
        with torch.no_grad():
            test_output = model(test_input)
            print(f"[TasNet] Test input shape: {test_input.shape}")
            print(f"[TasNet] Test output shape: {test_output.shape}")
            print(f"[TasNet] Model verification successful")
        
        return model
        
    except Exception as e:
        print(f"[TasNet] ERROR loading model: {e}")
        print(f"[TasNet] Creating fresh model as fallback")
        traceback.print_exc()
        model.eval()
        return model


class MechanicalNoiseReducer:
    def __init__(self, sr=52734):
        self.sr = sr
        self.n_fft = 2048
        self.hop_length = 512
        
    def reduce_noise(self, audio, reduction_db=5):
        D = librosa.stft(audio, n_fft=self.n_fft, hop_length=self.hop_length)
        magnitude = np.abs(D)
        phase = np.angle(D)
        
        frame_energies = np.mean(magnitude**2, axis=0)
        quiet_fraction = 0.1
        n_quiet = max(1, int(magnitude.shape[1] * quiet_fraction))
        quiet_indices = np.argsort(frame_energies)[:n_quiet]
        
        noise_profile = np.median(magnitude[:, quiet_indices], axis=1, keepdims=True)
        freq_bins = librosa.fft_frequencies(sr=self.sr, n_fft=self.n_fft)
        freq_weights = np.ones_like(freq_bins)
        
        low_freq_mask = freq_bins < 100
        freq_weights[low_freq_mask] = 0.7
        mid_freq_mask = (freq_bins >= 100) & (freq_bins < 500)
        freq_weights[mid_freq_mask] = 0.8
        
        base_threshold = noise_profile * (10 ** (reduction_db / 20))
        threshold = base_threshold * freq_weights[:, np.newaxis]
        
        attenuation_factor = np.where(magnitude > threshold, 
                                     (magnitude - 0.3 * threshold) / (magnitude + 1e-10), 
                                     0.7)
        
        magnitude_reduced = magnitude * attenuation_factor
        D_reduced = magnitude_reduced * np.exp(1j * phase)
        audio_reduced = librosa.istft(D_reduced, hop_length=self.hop_length)
        
        if len(audio_reduced) < len(audio):
            audio_reduced = np.pad(audio_reduced, (0, len(audio) - len(audio_reduced)))
        elif len(audio_reduced) > len(audio):
            audio_reduced = audio_reduced[:len(audio)]
            
        metrics = self._calculate_metrics(audio, audio_reduced)
        return audio_reduced, metrics
    
    def _calculate_metrics(self, original, reduced):
        return {'preservation_score': 0.95}


def clean_audio_with_tasnet(audio, model_path, ship_type, sr=TASNET_SR):
    """
    Full-length TasNet denoising with comprehensive error handling.
    Returns cleaned audio AND its FFT data.
    """
    print(f"\n[TasNet] Starting denoising for {ship_type}")
    print(f"[TasNet] Audio length: {len(audio)} samples ({len(audio)/sr:.2f}s)")
    
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[TasNet] Using device: {device}")
    
    try:
        model = load_tasnet_model(model_path).to(device)
        
        print(f"[TasNet] Applying sliding window denoising...")
        cleaned_audio = sliding_window_tasnet_denoise(audio, model, sr)
        
        if len(cleaned_audio) > len(audio):
            cleaned_audio = cleaned_audio[:len(audio)]
            print(f"[TasNet] Trimmed output to match input length")
        elif len(cleaned_audio) < len(audio):
            cleaned_audio = np.pad(
                cleaned_audio,
                (0, len(audio) - len(cleaned_audio))
            )
            print(f"[TasNet] Padded output to match input length")
        
        orig_rms = np.sqrt(np.mean(audio**2) + 1e-9)
        clean_rms = np.sqrt(np.mean(cleaned_audio**2) + 1e-9)
        
        if clean_rms > 1e-9:
            cleaned_audio *= orig_rms / clean_rms
            print(f"[TasNet] RMS normalization: {orig_rms:.6f} → {clean_rms:.6f}")
        else:
            print(f"[TasNet] WARNING: Clean audio has near-zero RMS")
        
        snr_before = 10 * np.log10(np.mean(audio**2) / (np.mean((audio - np.mean(audio))**2) + 1e-9))
        snr_after = 10 * np.log10(np.mean(cleaned_audio**2) / (np.mean((cleaned_audio - np.mean(cleaned_audio))**2) + 1e-9))
        print(f"[TasNet] SNR before: {snr_before:.2f} dB, after: {snr_after:.2f} dB")
        
        print(f"[TasNet] Extracting FFT for cleaned audio...")
        freqs_cleaned, mags_cleaned = extract_fft(cleaned_audio, sr=sr, n_fft=2048)
        
        return cleaned_audio, (freqs_cleaned, mags_cleaned)
        
    except Exception as e:
        print(f"[TasNet] ERROR in denoising: {e}")
        traceback.print_exc()
        print(f"[TasNet] Returning original audio as fallback")
        freqs_original, mags_original = extract_fft(audio, sr=sr, n_fft=2048)
        return audio.copy(), (freqs_original, mags_original)


def sliding_window_tasnet_denoise(audio, model, sr=TASNET_SR, window_sec=3.0, overlap=0.5):
    """
    Apply TasNet denoising using sliding windows + overlap-add.
    Enhanced with better error handling and logging.
    """
    if len(audio) < sr * 0.5:
        print(f"[TasNet] Audio too short ({len(audio)/sr:.2f}s), returning original")
        return audio.copy()
    
    window_len = int(window_sec * sr)
    hop_len = int(window_len * (1 - overlap))
    
    if window_len <= 0:
        window_len = int(3.0 * sr)
        hop_len = int(window_len * 0.5)
    
    output = np.zeros(len(audio), dtype=np.float32)
    weight = np.zeros(len(audio), dtype=np.float32)
    
    window = np.hanning(window_len).astype(np.float32)
    
    device = next(model.parameters()).device
    
    print(f"[TasNet] Sliding window denoising: window={window_sec}s, overlap={overlap*100}%, total_frames={len(audio)}")
    
    num_segments = max(1, (len(audio) - window_len) // hop_len + 1)
    print(f"[TasNet] Processing {num_segments} segments")
    
    log_interval = max(1, num_segments // 5)
    
    for i, start in enumerate(range(0, len(audio), hop_len)):
        end = start + window_len
        
        if start >= len(audio):
            break
            
        segment = audio[start:min(end, len(audio))]
        
        if len(segment) < window_len:
            segment = np.pad(segment, (0, window_len - len(segment)))
        
        segment_tensor = torch.from_numpy(segment).float().to(device)
        
        try:
            with torch.no_grad():
                cleaned_segment = model(segment_tensor.unsqueeze(0)).squeeze(0).cpu().numpy()
        except Exception as e:
            print(f"[TasNet] Error processing segment {i}: {e}")
            cleaned_segment = segment
        
        cleaned_segment = cleaned_segment[:window_len]
        
        valid_len = min(window_len, len(audio) - start)
        
        output[start:start + valid_len] += (
            cleaned_segment[:valid_len] * window[:valid_len]
        )
        
        weight[start:start + valid_len] += window[:valid_len]
        
        if i % log_interval == 0 or i == num_segments - 1:
            print(f"[TasNet] Processed {i+1}/{num_segments} segments ({(i+1)/num_segments*100:.1f}%)")
    
    nonzero = weight > 1e-8
    if np.any(nonzero):
        output[nonzero] /= weight[nonzero]
    else:
        print(f"[TasNet] WARNING: No valid overlap regions, returning original")
        return audio.copy()
    
    orig_rms = np.sqrt(np.mean(audio**2) + 1e-9)
    clean_rms = np.sqrt(np.mean(output**2) + 1e-9)
    
    if clean_rms > 1e-9:
        output *= orig_rms / clean_rms
    
    print(f"[TasNet] Denoising complete. Output RMS: {np.sqrt(np.mean(output**2)):.6f}")
    
    return output

import os
import io
import uuid
import base64
import datetime
import traceback
import numpy as np
import torch
import torch.nn.functional as F
import librosa
import soundfile as sf

def detect_recorded_audio(audio_file):
    BASE_DIR = "C:/Users/shahbazfareed/Desktop/FinalSolution/models"
    OLD_MODEL_PATH = os.path.join(BASE_DIR, "task1.pth")
    NEW_MODEL_PATH = os.path.join(BASE_DIR, "task2.pth")
    
    TASNET_MODELS = {
        "SpeedBoat": os.path.join(BASE_DIR, "speedboat_tasnet_best_model.pth"),
        "KaiYuan": os.path.join(BASE_DIR, "kaiyuan_tasnet_best_model.pth"),
        "UUV": os.path.join(BASE_DIR, "uuv_tasnet_best_model.pth")
    }

    result = {
        'success': False,
        'predicted_class': 'Error',
        'confidence': 0.0,
        'total_duration': 0.0,
        'warning': None,
        'error': None,
        'fft_data_original': None,
        'segment_predictions': [],
        'processing_stage': 'unknown',
        'audio_cleaned_base64': None,
        'fft_data_cleaned': None,
        'cleaning_method': 'tasnet_denoising',
        'cleaning_attempted': False,
        'cleaning_success': False,
        'cleaning_error': None,
        'filename': 'recording.wav',
        'audio_original_base64': None,
        'voice_removed': False,
        'audio_original_id': None,
        'audio_cleaned_id': None,
    }

    try:
        if hasattr(audio_file, 'seek'): 
            audio_file.seek(0)
        
        if hasattr(audio_file, 'read'):
            file_content = io.BytesIO(audio_file.read())
        else:
            file_content = io.BytesIO(audio_file)

        raw_audio, sr = librosa.load(file_content, sr=TASNET_SR, mono=False)
        
        if raw_audio.ndim == 2:
            print(f"\n  Stereo recording detected: {raw_audio.shape[0]} channels")
            raw_audio = np.mean(raw_audio, axis=0)
            print("  Converted to mono by averaging channels")
        else:
            print(f"\n  Mono recording detected")

        trimmed_audio, _ = librosa.effects.trim(raw_audio, top_db=25)
        
        if len(trimmed_audio) < sr: 
            analysis_audio = raw_audio
            result['warning'] = "Recording was quiet (Low Energy)"
        else:
            analysis_audio = trimmed_audio
            
        audio_duration = len(analysis_audio) / sr
        result['total_duration'] = float(audio_duration)

        if audio_duration < 3.0:
            padding = int(3.0 * sr) - len(analysis_audio)
            analysis_audio = np.pad(analysis_audio, (0, padding), 'constant')
            audio_duration = 3.0
        
        print("\n" + "="*60)
        print("TASK 0: Ship Detection (Mechanical Pattern Analysis)")
        print("="*60)
        
        yamnet_detector = get_yamnet_detector()
        yamnet_audio = analysis_audio[:min(len(analysis_audio), int(3.0 * sr))]
        yamnet_result = yamnet_detector.analyze(yamnet_audio, sr)
        
        if not yamnet_result['success']:
            result['error'] = "YAMNet analysis failed"
            return result
        
        print(f"\nPattern Analysis Results:")
        print(f"  Is Ship: {yamnet_result['is_ship']}")
        if yamnet_result['matched_pattern']:
            print(f"  Matched Pattern: {yamnet_result['matched_pattern']}")
        print(f"  Detected Mechanical Classes: {yamnet_result['detected_mechanical_classes']}")
        print(f"  Confidence: {yamnet_result['confidence']:.3f}")
        
        if yamnet_result['is_ship']:
            print(f"\nTask 0 DECISION: SHIP detected by mechanical patterns")
            print("  Proceeding to Task 2 (Ship Type Identification)")
            result['processing_stage'] = 'task2_ship_type'
            
            reducer = MechanicalNoiseReducer(sr=sr)
            audio_reduced, _ = reducer.reduce_noise(analysis_audio)
            analysis_audio = audio_reduced if audio_reduced is not None else analysis_audio
            
            segment_len = min(len(analysis_audio), int(3.0 * sr))
            segment = analysis_audio[:segment_len]
            features = extract_logmel_spectrogram(segment, sr, duration=3.0)
            features_tensor = torch.FloatTensor(features).unsqueeze(0).unsqueeze(0)
            
            model_t2 = load_new_model(NEW_MODEL_PATH)
            with torch.no_grad():
                out_t2 = model_t2(features_tensor)
                prob_t2 = F.softmax(out_t2, dim=1)
                conf_t2, pred_t2 = torch.max(prob_t2, 1)
                
                ship_classes = ["SpeedBoat", "UUV", "KaiYuan"]
                ship_type = ship_classes[pred_t2.item()]
                ship_confidence = float(conf_t2.item())
            
            print(f"  Task 2 identified: {ship_type} (confidence: {ship_confidence:.3f})")
            
            original_audio_id = str(uuid.uuid4())
            original_filename = f"{original_audio_id}.wav"
            
            AUDIO_CACHE_DIR = "audio_cache"
            os.makedirs(AUDIO_CACHE_DIR, exist_ok=True)
            original_path = os.path.join(AUDIO_CACHE_DIR, original_filename)
            sf.write(original_path, analysis_audio, sr, format='WAV')
            
            result['audio_original_id'] = original_audio_id
            
            print(f"\n  Encoding original audio to base64...")
            original_audio_bytes = io.BytesIO()
            sf.write(original_audio_bytes, analysis_audio, sr, format='WAV')
            original_audio_bytes.seek(0)
            original_audio_base64 = base64.b64encode(original_audio_bytes.read()).decode('utf-8')
            result['audio_original_base64'] = original_audio_base64
            
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            result['filename'] = f"recording_{timestamp}.wav"
            
            # ===== TASNET AUDIO CLEANING =====
            # MODIFIED LOGIC: Intercept KaiYuan before cleaning
            if ship_type == "KaiYuan":
                print("\n" + "="*30)
                print("fix this part")
                print("="*30 + "\n")
                result['warning'] = "fix this part"  # Pass message to UI/Result
                result['processing_stage'] = 'task2_stopped_kaiyuan'
                
            elif ship_type in TASNET_MODELS:
                result['cleaning_attempted'] = True
                model_path = TASNET_MODELS[ship_type]
                
                if os.path.exists(model_path):
                    print(f"\n  [TasNet] Cleaning audio for {ship_type}...")
                    print(f"  [TasNet] Model path: {model_path}")
                    
                    try:
                        # Clean audio using TasNet
                        audio_cleaned, fft_cleaned_data = clean_audio_with_tasnet(
                            audio=analysis_audio,
                            model_path=model_path,
                            ship_type=ship_type,
                            sr=sr
                        )
                        
                        # Store FFT data for cleaned audio
                        if fft_cleaned_data:
                            freqs_cleaned, mags_cleaned = fft_cleaned_data
                            result['fft_data_cleaned'] = {
                                'frequencies': freqs_cleaned.tolist(),
                                'magnitude': mags_cleaned.tolist()
                            }
                        
                        # Check if denoising actually happened
                        if np.array_equal(audio_cleaned, analysis_audio):
                            print(f"  [TasNet] WARNING: Denoising returned original audio")
                            result['cleaning_success'] = False
                            result['warning'] = f"TasNet denoising returned original audio (model may not be trained)"
                        else:
                            # Save and encode cleaned audio (Standard success path)
                            cleaned_audio_id = str(uuid.uuid4())
                            cleaned_filename = f"{cleaned_audio_id}.wav"
                            cleaned_path = os.path.join(AUDIO_CACHE_DIR, cleaned_filename)
                            
                            sf.write(cleaned_path, audio_cleaned, sr, format='WAV')
                            result['audio_cleaned_id'] = cleaned_audio_id

                            print(f"  [TasNet] Encoding cleaned audio to base64...")
                            cleaned_audio_bytes = io.BytesIO()
                            sf.write(cleaned_audio_bytes, audio_cleaned, sr, format='WAV')
                            cleaned_audio_bytes.seek(0)
                            cleaned_audio_base64 = base64.b64encode(cleaned_audio_bytes.read()).decode('utf-8')
                            
                            result['audio_cleaned_base64'] = cleaned_audio_base64
                            result['cleaning_success'] = True
                            result['cleaning_method'] = f'tasnet_{ship_type.lower()}'
                            
                            print(f"  [TasNet] ✓ Cleaning successful")
                            
                    except Exception as e:
                        print(f"  [TasNet] ✗ Cleaning FAILED: {e}")
                        traceback.print_exc()
                        result['cleaning_error'] = str(e)
                        result['cleaning_success'] = False
                        result['warning'] = f"TasNet cleaning failed: {e}"
                else:
                    print(f"  [TasNet] ✗ Model file not found: {model_path}")
                    result['warning'] = f"No TasNet model file found for {ship_type}"
            else:
                print(f"  [TasNet] ✗ No TasNet model configured for {ship_type}")
                result['warning'] = f"No TasNet model configured for {ship_type}"
                
            result['success'] = True
            result['predicted_class'] = ship_type
            result['confidence'] = yamnet_result['confidence'] * ship_confidence
            
            frequencies, magnitude_db_original = extract_fft(analysis_audio, sr=sr, n_fft=2048)
            if len(frequencies) > 0:
                result['fft_data_original'] = {
                    'frequencies': frequencies.tolist(),
                    'magnitude': magnitude_db_original.tolist()
                }
            
            return result
            
        else:
            print(f"\nTask 0 DECISION: NOT A SHIP (no mechanical pattern match)")
            print("  Returning 'Unknown' immediately")
            
            original_audio_id = str(uuid.uuid4())
            AUDIO_CACHE_DIR = "audio_cache"
            os.makedirs(AUDIO_CACHE_DIR, exist_ok=True)
            original_path = os.path.join(AUDIO_CACHE_DIR, f"{original_audio_id}.wav")
            sf.write(original_path, analysis_audio, sr, format='WAV')
            result['audio_original_id'] = original_audio_id
            
            original_audio_bytes = io.BytesIO()
            sf.write(original_audio_bytes, analysis_audio, sr, format='WAV')
            original_audio_bytes.seek(0)
            original_audio_base64 = base64.b64encode(original_audio_bytes.read()).decode('utf-8')
            result['audio_original_base64'] = original_audio_base64
            
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            result['filename'] = f"recording_{timestamp}.wav"
            
            result['success'] = True
            result['predicted_class'] = 'Unknown'
            result['confidence'] = 0.7
            result['processing_stage'] = 'task0_not_ship'
            result['warning'] = 'No ship pattern detected'
            
            frequencies, magnitude_db_original = extract_fft(analysis_audio, sr=sr, n_fft=2048)
            if len(frequencies) > 0:
                result['fft_data_original'] = {
                    'frequencies': frequencies.tolist(),
                    'magnitude': magnitude_db_original.tolist()
                }
            
            return result

    except Exception as e:
        traceback.print_exc()
        result['error'] = str(e)
        return result

def detect_audio(audio_file):
    BASE_DIR = "C:/Users/shahbazfareed/Desktop/FinalSolution/models"
    OLD_MODEL_PATH = os.path.join(BASE_DIR, "task1.pth")
    NEW_MODEL_PATH = os.path.join(BASE_DIR, "task2.pth")
    
    TASNET_MODELS = {
        "SpeedBoat": os.path.join(BASE_DIR, "speedboat_tasnet_best_model.pth"),
        "KaiYuan": os.path.join(BASE_DIR, "kaiyuan_tasnet_best_model.pth"),
        "UUV": os.path.join(BASE_DIR, "uuv_tasnet_best_model.pth")
    }

    result = {
        'success': False,
        'predicted_class': 'Error',
        'confidence': 0.0,
        'total_duration': 0.0,
        'warning': None,
        'error': None,
        'fft_data_original': None,
        'segment_predictions': [],
        'processing_stage': 'unknown',
        'audio_cleaned_base64': None,
        'fft_data_cleaned': None,
        'cleaning_method': 'tasnet_denoising',
        'cleaning_attempted': False,
        'cleaning_success': False,
        'cleaning_error': None,
        'filename': 'recording.wav',
        'audio_original_base64': None,
        'voice_removed': False,
    }

    try:
        if hasattr(audio_file, 'seek'): 
            audio_file.seek(0)
        
        if hasattr(audio_file, 'read'):
            file_content = io.BytesIO(audio_file.read())
        else:
            file_content = io.BytesIO(audio_file)

        raw_audio, sr = librosa.load(file_content, sr=TASNET_SR, mono=False)
        
        if raw_audio.ndim == 2:
            print(f"\n  Stereo recording detected: {raw_audio.shape[0]} channels")
            raw_audio = np.mean(raw_audio, axis=0)
            print("  Converted to mono by averaging channels")
        else:
            print(f"\n  Mono recording detected")

        trimmed_audio, _ = librosa.effects.trim(raw_audio, top_db=25)
        
        if len(trimmed_audio) < sr: 
            analysis_audio = raw_audio
            result['warning'] = "Recording was quiet (Low Energy)"
        else:
            analysis_audio = trimmed_audio
            
        audio_duration = len(analysis_audio) / sr
        result['total_duration'] = float(audio_duration)

        if audio_duration < 3.0:
            padding = int(3.0 * sr) - len(analysis_audio)
            analysis_audio = np.pad(analysis_audio, (0, padding), 'constant')
            audio_duration = 3.0
        
        print("\n" + "="*60)
        print("TASK 0: Ship Detection (Mechanical Pattern Analysis)")
        print("="*60)
        
        yamnet_detector = get_yamnet_detector()
        yamnet_audio = analysis_audio[:min(len(analysis_audio), int(3.0 * sr))]
        yamnet_result = yamnet_detector.analyze(yamnet_audio, sr)
        
        if not yamnet_result['success']:
            result['error'] = "YAMNet analysis failed"
            return result
        
        print(f"\nPattern Analysis Results:")
        print(f"  Is Ship: {yamnet_result['is_ship']}")
        if yamnet_result['matched_pattern']:
            print(f"  Matched Pattern: {yamnet_result['matched_pattern']}")
        print(f"  Detected Mechanical Classes: {yamnet_result['detected_mechanical_classes']}")
        print(f"  Confidence: {yamnet_result['confidence']:.3f}")
        
        if yamnet_result['is_ship']:
            print(f"\nTask 0 DECISION: SHIP detected by mechanical patterns")
            print("  Proceeding to Task 2 (Ship Type Identification)")
            result['processing_stage'] = 'task2_ship_type'
            
            reducer = MechanicalNoiseReducer(sr=sr)
            audio_reduced, _ = reducer.reduce_noise(analysis_audio)
            analysis_audio = audio_reduced if audio_reduced is not None else analysis_audio
            
            segment_len = min(len(analysis_audio), int(3.0 * sr))
            segment = analysis_audio[:segment_len]
            features = extract_logmel_spectrogram(segment, sr, duration=3.0)
            features_tensor = torch.FloatTensor(features).unsqueeze(0).unsqueeze(0)
            
            model_t2 = load_new_model(NEW_MODEL_PATH)
            with torch.no_grad():
                out_t2 = model_t2(features_tensor)
                prob_t2 = F.softmax(out_t2, dim=1)
                conf_t2, pred_t2 = torch.max(prob_t2, 1)
                
                ship_classes = ["SpeedBoat", "UUV", "KaiYuan"]
                ship_type = ship_classes[pred_t2.item()]
                ship_confidence = float(conf_t2.item())
            
            print(f"  Task 2 identified: {ship_type} (confidence: {ship_confidence:.3f})")
            
            print(f"\n  Encoding original audio to base64...")
            original_audio_bytes = io.BytesIO()
            sf.write(original_audio_bytes, analysis_audio, sr, format='WAV')
            original_audio_bytes.seek(0)
            original_audio_base64 = base64.b64encode(original_audio_bytes.read()).decode('utf-8')
            result['audio_original_base64'] = original_audio_base64
            
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            result['filename'] = f"recording_{timestamp}.wav"
            
            if ship_type in TASNET_MODELS and os.path.exists(TASNET_MODELS[ship_type]):
                result['cleaning_attempted'] = True
                print(f"\n  Cleaning audio with TasNet for {ship_type}...")
                
                try:
                    audio_cleaned, fft_cleaned_data = clean_audio_with_tasnet(
                        audio=analysis_audio,
                        model_path=TASNET_MODELS[ship_type],
                        ship_type=ship_type,
                        sr=sr
                    )
                    
                    print(f"  Encoding cleaned audio to base64...")
                    cleaned_audio_bytes = io.BytesIO()
                    sf.write(cleaned_audio_bytes, audio_cleaned, sr, format='WAV')
                    cleaned_audio_bytes.seek(0)
                    cleaned_audio_base64 = base64.b64encode(cleaned_audio_bytes.read()).decode('utf-8')
                    
                    result['audio_cleaned_base64'] = cleaned_audio_base64
                    result['cleaning_success'] = True
                    result['cleaning_method'] = f'tasnet_{ship_type.lower()}'
                    
                    if fft_cleaned_data:
                        freqs_cleaned, mags_cleaned = fft_cleaned_data
                        result['fft_data_cleaned'] = {
                            'frequencies': freqs_cleaned.tolist(),
                            'magnitude': mags_cleaned.tolist()
                        }
                    
                    print(f"  ✓ TasNet cleaning successful")
                    
                except Exception as e:
                    print(f"  ✗ TasNet cleaning FAILED: {e}")
                    traceback.print_exc()
                    result['cleaning_error'] = str(e)
                    result['cleaning_success'] = False
                    result['warning'] = f"TasNet cleaning failed: {e}"
            else:
                print(f"  ✗ No TasNet model found for {ship_type}")
                print(f"  Looking for: {TASNET_MODELS.get(ship_type, 'Unknown')}")
                result['warning'] = f"No TasNet model available for {ship_type}"
            
            result['success'] = True
            result['predicted_class'] = ship_type
            result['confidence'] = yamnet_result['confidence'] * ship_confidence
            
            frequencies, magnitude_db_original = extract_fft(analysis_audio, sr=sr, n_fft=2048)
            if len(frequencies) > 0:
                result['fft_data_original'] = {
                    'frequencies': frequencies.tolist(),
                    'magnitude': magnitude_db_original.tolist()
                }
            
            return result
            
        else:
            print(f"\nTask 0 DECISION: NOT A SHIP (no mechanical pattern match)")
            print("  Returning 'Unknown' immediately")
            
            original_audio_bytes = io.BytesIO()
            sf.write(original_audio_bytes, analysis_audio, sr, format='WAV')
            original_audio_bytes.seek(0)
            original_audio_base64 = base64.b64encode(original_audio_bytes.read()).decode('utf-8')
            result['audio_original_base64'] = original_audio_base64
            
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            result['filename'] = f"recording_{timestamp}.wav"
            
            result['success'] = True
            result['predicted_class'] = 'Unknown'
            result['confidence'] = 0.7
            result['processing_stage'] = 'task0_not_ship'
            result['warning'] = 'No ship pattern detected'
            
            frequencies, magnitude_db_original = extract_fft(analysis_audio, sr=sr, n_fft=2048)
            if len(frequencies) > 0:
                result['fft_data_original'] = {
                    'frequencies': frequencies.tolist(),
                    'magnitude': magnitude_db_original.tolist()
                }
            
            return result

    except Exception as e:
        traceback.print_exc()
        result['error'] = str(e)
        return result


def voting_mechanism(segment_predictions, segment_confidences, audio_duration):
    if not segment_predictions:
        return "Unknown", 0.0
    
    print(f"\n=== VOTING MECHANISM ===")
    print(f"Segment predictions: {segment_predictions}")
    print(f"Segment confidences: {[f'{c:.4f}' for c in segment_confidences]}")
    
    from collections import defaultdict
    vote_counts = defaultdict(int)
    confidence_sums = defaultdict(float)
    
    for pred, conf in zip(segment_predictions, segment_confidences):
        vote_counts[pred] += 1
        confidence_sums[pred] += conf
    
    print(f"Vote counts: {dict(vote_counts)}")
    
    noise_segments = [(pred, conf) for pred, conf in zip(segment_predictions, segment_confidences) 
                      if pred == "Unknown" and conf > 0.8]
    
    if noise_segments:
        print(f"HIGH CONFIDENCE NOISE SEGMENTS DETECTED: {noise_segments}")
        
        if len(noise_segments) >= len(segment_predictions) / 2:
            print(f"Majority high-confidence noise -> FINAL: Unknown")
            avg_noise_conf = sum(conf for _, conf in noise_segments) / len(noise_segments)
            return "Unknown", float(avg_noise_conf)
    
    weighted_votes = {}
    for pred in vote_counts:
        avg_conf = confidence_sums[pred] / vote_counts[pred]
        weighted_votes[pred] = avg_conf * vote_counts[pred]
    
    print(f"Weighted votes: {weighted_votes}")
    
    if weighted_votes:
        final_prediction = max(weighted_votes, key=weighted_votes.get)
        
        winning_confidences = [conf for pred, conf in zip(segment_predictions, segment_confidences) 
                              if pred == final_prediction]
        final_confidence = sum(winning_confidences) / len(winning_confidences)
        
        print(f"FINAL PREDICTION: {final_prediction} (confidence={final_confidence:.4f})")
        return final_prediction, float(final_confidence)
    else:
        print(f"NO CLEAR WINNER -> DEFAULT: Unknown")
        return "Unknown", 0.0


def classify_segment(features_tensor, audio_duration, model_t1, model_t2):
    with torch.no_grad():
        print(f"DEBUG: Task 1 model output size check")
        
        out_t1 = model_t1(features_tensor)
        print(f"Task 1 raw output shape: {out_t1.shape}, values: {out_t1}")
        
        if out_t1.shape[1] == 1:
            ship_probability = torch.sigmoid(out_t1).item()
            print(f"Ship probability (sigmoid): {ship_probability:.4f}")
            
            SHIP_THRESHOLD = 0.99
            
            if ship_probability >= SHIP_THRESHOLD:
                print(f"Classified as SHIP (prob={ship_probability:.4f})")
                
                out_t2 = model_t2(features_tensor)
                print(f"Task 2 raw output shape: {out_t2.shape}, values: {out_t2}")
                
                prob_t2 = F.softmax(out_t2, dim=1)
                conf_t2, pred_t2 = torch.max(prob_t2, 1)
                
                ship_classes = ["SpeedBoat", "UUV", "KaiYuan"]
                ship_type = ship_classes[pred_t2.item()]
                ship_type_confidence = float(conf_t2.item())
                
                final_confidence = ship_probability * ship_type_confidence
                
                print(f"Ship type: {ship_type} (confidence={ship_type_confidence:.4f})")
                print(f"Final confidence: {final_confidence:.4f}")
                
                return ship_type, float(final_confidence)
            else:
                print(f"Classified as Unknown (ship_prob={ship_probability:.4f})")
                noise_confidence = 1.0 - ship_probability
                return "Unknown", float(noise_confidence)
                
        else:
            print(f"WARNING: Task 1 output has {out_t1.shape[1]} classes, expected 1 for binary")
            prob_t1 = F.softmax(out_t1, dim=1)
            print(f"Task 1 probabilities: {prob_t1}")
            
            conf_t1, pred_t1 = torch.max(prob_t1, 1)
            
            if pred_t1.item() == 1:
                print(f"Classified as SHIP (class 1, confidence={conf_t1.item():.4f})")
                
                out_t2 = model_t2(features_tensor)
                prob_t2 = F.softmax(out_t2, dim=1)
                conf_t2, pred_t2 = torch.max(prob_t2, 1)
                
                ship_classes = ["SpeedBoat", "UUV", "KaiYuan"]
                ship_type = ship_classes[pred_t2.item()]
                final_confidence = float(conf_t1.item() * conf_t2.item())
                
                return ship_type, final_confidence
            else:
                print(f"Classified as Unknown (class 0, confidence={conf_t1.item():.4f})")
                return "Unknown", float(conf_t1.item())