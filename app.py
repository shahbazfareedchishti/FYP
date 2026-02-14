import os
from flask import Flask, render_template, request, jsonify, redirect, url_for, session, flash, send_file
from models import DatabaseHelper
import json
from auth import AuthService
import secrets
from datetime import datetime
from sound_detector import detect_audio, extract_fft, detect_recorded_audio
from werkzeug.utils import secure_filename
import soundfile as sf
import tempfile
import numpy as np
import io
from pydub import AudioSegment
import librosa
import traceback
import signal
from functools import wraps, lru_cache

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)

db_helper = DatabaseHelper()
auth_service = AuthService(db_helper) 
db_helper.init_db()

UPLOAD_FOLDER = 'uploads'
AUDIO_CACHE_FOLDER = 'audio_cache'
ALLOWED_EXTENSIONS = {'wav', 'mp3', 'flac', 'ogg', 'm4a'}

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['AUDIO_CACHE_FOLDER'] = AUDIO_CACHE_FOLDER

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(AUDIO_CACHE_FOLDER, exist_ok=True)

def is_logged_in():
    return 'user_id' in session

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS



def save_audio_to_wav(audio_data, sample_rate, filename):
    audio_cache_path = os.path.join(app.config['AUDIO_CACHE_FOLDER'], filename)
    
    if len(audio_data) > 0:
        max_val = np.max(np.abs(audio_data))
        if max_val > 0:
            audio_normalized = audio_data / max_val * 0.9
        else:
            audio_normalized = audio_data
    else:
        audio_normalized = audio_data
    
    sf.write(audio_cache_path, audio_normalized, sample_rate, subtype='PCM_16')
    
    file_size_mb = os.path.getsize(audio_cache_path) / (1024 * 1024)
    
    return audio_cache_path, file_size_mb

def cleanup_old_audio_files(max_age_hours=1):
    try:
        now = datetime.now()
        for filename in os.listdir(app.config['AUDIO_CACHE_FOLDER']):
            filepath = os.path.join(app.config['AUDIO_CACHE_FOLDER'], filename)
            if os.path.isfile(filepath):
                file_modified = datetime.fromtimestamp(os.path.getmtime(filepath))
                age_hours = (now - file_modified).total_seconds() / 3600
                if age_hours > max_age_hours:
                    os.remove(filepath)
    except Exception as e:
        print(f"Error cleaning up old audio files: {e}")

@app.route('/')
def home():
    if is_logged_in():
        return redirect(url_for('main'))
    return redirect(url_for('login'))



@app.route('/login', methods=['GET', 'POST'])
def login():
    if is_logged_in():
        return redirect(url_for('main'))
    
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()

        if len(username) < 3:
            flash('Username must be at least 3 characters', 'error')
            return render_template('login.html')
        
        if len(password) < 6:
            flash('Password must be at least 6 characters', 'error')
            return render_template('login.html')
        
        if auth_service.login(username, password):
            session['user_id'] = auth_service.current_user_id
            session['username'] = auth_service.current_username
            return redirect(url_for('main'))
        else:
            flash('Invalid username or password', 'error')
    
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form.get('username')
        email = request.form.get('email')
        password = request.form.get('password')
        confirm_password = request.form.get('confirm_password')
        
        if password != confirm_password:
            flash('Passwords do not match')
        else:
            try:
                auth_service.register(username, email, password)
                flash('Registration successful! Please login.')
                return redirect(url_for('login'))
            except Exception as e:
                if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
                    return jsonify({'error': str(e)}), 400
                flash(str(e))
    
    return render_template('register.html')

@app.route('/forgot-password', methods=['GET', 'POST'])
def forgot_password():
    if request.method == 'POST':
        email = request.form.get('email')
        try:
            message = auth_service.request_password_reset(email)
            flash(message)
            return redirect(url_for('reset_password'))
        except Exception as e:
            flash(str(e))
    
    return render_template('forgot_password.html')

@app.route('/reset-password', methods=['GET', 'POST'])
def reset_password():
    if request.method == 'POST':
        token = request.form.get('token')
        new_password = request.form.get('new_password')
        confirm_password = request.form.get('confirm_password')
        
        if new_password != confirm_password:
            flash('Passwords do not match')
        else:
            if auth_service.reset_password(token, new_password):
                flash('Password reset successful! Please login.')
                return redirect(url_for('login'))
            else:
                flash('Invalid or expired reset token')
    
    return render_template('reset_password.html')

@app.route('/main')
def main():
    if not is_logged_in():
        return redirect(url_for('login'))
    return render_template('main.html')



@app.route('/snr-analysis', methods=['GET', 'POST'])
def snr_analysis():
    if not is_logged_in():
        return redirect(url_for('login'))

    if request.method == 'POST':
        try:
            if request.is_json:
                payload = request.get_json()
            else:
                payload_str = request.form.get('snr_data') or request.form.get('data')
                payload = json.loads(payload_str) if payload_str else {}

            snr_values = None
            time_bins = None
            total_duration = None

            if isinstance(payload, dict):
                if 'snr_values_over_time' in payload and 'time_bins' in payload:
                    snr_values = payload.get('snr_values_over_time')
                    time_bins = payload.get('time_bins')
                    total_duration = payload.get('total_duration')
                elif 'snr_over_time' in payload and 'time_bins' in payload:
                    snr_values = payload.get('snr_over_time')
                    time_bins = payload.get('time_bins')
                    total_duration = payload.get('total_duration')
                else:
                    sm = payload.get('snr_metrics') or payload.get('snr_analysis')
                    if isinstance(sm, dict):
                        snr_values = sm.get('snr_values_over_time') or sm.get('snr_over_time')
                        time_bins = sm.get('time_bins')
                        total_duration = sm.get('total_duration')

            if not snr_values or not time_bins:
                flash('No SNR time-series provided', 'error')
                return redirect(url_for('main'))

            snr_data = {
                'snr_over_time': snr_values,
                'time_bins': time_bins,
                'total_duration': total_duration
            }

            return render_template('snr_analysis.html', snr_data=snr_data)

        except Exception as e:
            flash('Error reading SNR data: ' + str(e), 'error')
            return redirect(url_for('main'))

    flash('SNR analysis requires real SNR data from audio processing', 'info')
    return redirect(url_for('main'))

@app.route('/play_cleaned', methods=['POST'])
def play_cleaned_audio():
    """Play cleaned audio directly in browser"""
    if not is_logged_in():
        return jsonify({'error': 'Not authenticated'}), 401
    
    if 'audio_data' not in request.json:
        return jsonify({'error': 'No audio data provided'}), 400
    
    try:
        import base64
        audio_base64 = request.json['audio_data']
        
        audio_bytes = base64.b64decode(audio_base64)
        
        from flask import Response
        return Response(
            audio_bytes,
            mimetype='audio/wav',
            headers={
                'Content-Disposition': 'inline; filename="cleaned_audio.wav"'
            }
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/detect', methods=['POST'])
def detect():
    if not is_logged_in():
        return jsonify({'success': False, 'error': 'Not authenticated'})
    
    if 'audio' not in request.files:
        return jsonify({'success': False, 'error': 'No audio file'})
    
    audio_file = request.files['audio']
    
    audio_bytes = audio_file.read()
    
    try:
        try:
            with tempfile.NamedTemporaryFile(suffix='.webm', delete=False) as tmp:
                tmp.write(audio_bytes)
                tmp_path = tmp.name
            
            audio, sr = librosa.load(tmp_path, sr=52734)
            os.unlink(tmp_path)
            
            wav_io = io.BytesIO()
            sf.write(wav_io, audio, sr, format='WAV')
            wav_io.seek(0)
            
            result = detect_audio(wav_io)
            
        except Exception as conv_error:
            print(f"Librosa conversion failed: {conv_error}")
            
            try:
                from pydub import AudioSegment
                
                audio_segment = AudioSegment.from_file(io.BytesIO(audio_bytes))
                
                wav_io = io.BytesIO()
                audio_segment.export(wav_io, format="wav")
                wav_io.seek(0)
                
                audio, sr = librosa.load(wav_io, sr=52734)
                
                final_io = io.BytesIO()
                sf.write(final_io, audio, sr, format='WAV')
                final_io.seek(0)
                
                result = detect_audio(final_io)
                
            except Exception as pydub_error:
                print(f"Pydub conversion failed: {pydub_error}")
                return jsonify({
                    'success': False, 
                    'error': f'Audio conversion failed. Please install ffmpeg: {str(pydub_error)}'
                })
        
    except Exception as e:
        print(f"Error in detect_audio: {e}")
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)})
    
    if result.get('success'):
        raw_data = {
            'predicted_class': result.get('predicted_class'),
            'confidence': result.get('confidence', 0.0),
            'total_duration': result.get('total_duration', 3.0),
            'timestamp': datetime.now().isoformat(),
            'snr_metrics': result.get('snr_metrics', {}) if result.get('snr_metrics') else None
        }
        
        if 'warning' in result:
            raw_data['warning'] = result.get('warning')
        
        try:
            db_helper.insert_detection_with_raw(
                user_id=session['user_id'],
                sound_class=result.get('predicted_class'),
                confidence=result.get('confidence', 0.0),
                raw_data=json.dumps(raw_data)
            )
        except Exception as e:
            print(f"Database error: {e}")
    
    response_result = {
        'success': result.get('success', False),
        'predicted_class': result.get('predicted_class'),
        'confidence': float(result.get('confidence', 0.0)),
        'total_duration': float(result.get('total_duration', 0.0)),
        'warning': result.get('warning'),
        'error': result.get('error'),
        'separation_applied': result.get('separation_applied', False),
        'fft_data_original': result.get('fft_data_original'),
        'snr_metrics': result.get('snr_metrics') if result.get('snr_metrics') else None,
        'spectrogram_url': result.get('spectrogram_url')
    }
    
    import math
    def clean_for_json(obj):
        if isinstance(obj, dict):
            return {k: clean_for_json(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [clean_for_json(v) for v in obj]
        elif isinstance(obj, float):
            if math.isinf(obj) or math.isnan(obj):
                return 0.0
            return obj
        else:
            return obj
    
    response_result = clean_for_json(response_result)
    
    return jsonify(response_result)

@app.route('/record', methods=['POST'])
def record():
    if not is_logged_in():
        return jsonify({'success': False, 'error': 'Not authenticated'})
    
    if 'audio' not in request.files:
        return jsonify({'success': False, 'error': 'No audio file'})
    
    audio_file = request.files['audio']
    
    if audio_file.filename == '':
        return jsonify({'success': False, 'error': 'No audio file selected'})
    
    try:
        import time
        start_time = time.time()
        
        audio_bytes = audio_file.read()
        
        if len(audio_bytes) > 10 * 1024 * 1024:
            return jsonify({'success': False, 'error': 'Audio file too large (max 10MB)'})
        
        with tempfile.NamedTemporaryFile(suffix='.webm', delete=False) as tmp:
            tmp.write(audio_bytes)
            tmp_path = tmp.name
        
        try:
            audio_original, sr = librosa.load(tmp_path, sr=52734)
        finally:
            try:
                os.unlink(tmp_path)
            except:
                pass
        
        audio_duration = len(audio_original) / sr
        if audio_duration < 3.0:
            return jsonify({'success': False, 'error': f'Audio too short ({audio_duration:.1f}s). Minimum 3 seconds required.'})
        
        MAX_PROCESSING_DURATION = 30
        if audio_duration > MAX_PROCESSING_DURATION:
            audio_original = audio_original[:int(MAX_PROCESSING_DURATION * sr)]
            audio_duration = MAX_PROCESSING_DURATION
            warning_msg = f"Processing only first 30 seconds of {audio_duration:.1f}s recording"
        else:
            warning_msg = None
        
        wav_io = io.BytesIO()
        sf.write(wav_io, audio_original, sr, format='WAV')
        wav_io.seek(0)
        
        result = detect_recorded_audio(wav_io)
        
        if not result['success']:
            return jsonify({'success': False, 'error': result.get('error', 'Detection failed')})
        
        response_data = {
            'success': True,
            'filename': result.get('filename', f'recording_{datetime.now().strftime("%Y%m%d_%H%M%S")}.wav'),
            'predicted_class': result['predicted_class'],
            'confidence': float(result['confidence']) * 100,
            'total_duration': float(result['total_duration']),
            'warning': warning_msg or result.get('warning'),
            'error': result.get('error'),
            'fft_original': result.get('fft_data_original'),
            'yamnet_has_speech': result.get('yamnet_has_speech', False),
            'voice_removed': result.get('voice_removed', False),
            'cleaning_success': result.get('cleaning_success', False),
            'cleaning_error': result.get('cleaning_error'),
            'processing_stage': result.get('processing_stage', 'unknown'),
            'segment_predictions': result.get('segment_predictions', []),
            'audio_original_base64': result.get('audio_original_base64'),
        }
        
        if result.get('audio_cleaned_base64'):
            response_data['audio_cleaned_base64'] = result['audio_cleaned_base64']
            response_data['cleaning_method'] = result.get('cleaning_method', 'tasnet_denoising')
            response_data['cleaning_success'] = result.get('cleaning_success', False)
            response_data['fft_data_cleaned'] = result.get('fft_data_cleaned')
            
            if 'tasnet' in response_data.get('cleaning_method', ''):
                response_data['processed_label'] = 'TasNet Denoised Audio'
            else:
                response_data['processed_label'] = 'Cleaned Audio'
        try:
            raw_data = {
                'predicted_class': result['predicted_class'],
                'confidence': float(result['confidence']),
                'total_duration': float(result['total_duration']),
                'timestamp': datetime.now().isoformat(),
                'recording_type': 'live',
                'filename': response_data['filename'],
                'segment_predictions': result.get('segment_predictions', []),
                'voice_removed': result.get('voice_removed', False),
                'processing_stage': result.get('processing_stage', 'unknown'),
                'cleaning_applied': result.get('cleaning_success', False),
                'cleaning_method': result.get('cleaning_method', 'none')
            }
            
            db_helper.insert_detection_with_raw(
                user_id=session['user_id'],
                sound_class=result['predicted_class'],
                confidence=float(result['confidence']),
                raw_data=json.dumps(raw_data)
            )
        except Exception as e:
            print(f"Database error for recording: {e}")
        
        total_time = time.time() - start_time
        print(f"Total processing time: {total_time:.2f} seconds")
        
        return jsonify(response_data)
        
    except Exception as e:
        print(f"Error in record endpoint: {e}")
        traceback.print_exc()
        return jsonify({'success': False, 'error': str(e)})

@app.route('/download_cleaned', methods=['POST'])
def download_cleaned():
    """Download cleaned audio file"""
    if not is_logged_in():
        return jsonify({'error': 'Not authenticated'}), 401
    
    if 'audio_data' not in request.json or 'filename' not in request.json:
        return jsonify({'error': 'Missing audio data or filename'}), 400
    
    try:
        import base64
        import tempfile
        
        audio_base64 = request.json['audio_data']
        filename = request.json['filename']
        
        audio_bytes = base64.b64decode(audio_base64)
        
        temp_file = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
        temp_file.write(audio_bytes)
        temp_file.close()
        
        return send_file(
            temp_file.name,
            mimetype='audio/wav',
            as_attachment=True,
            download_name=filename
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/upload', methods=['GET', 'POST'])
def upload():
    if not is_logged_in():
        return redirect(url_for('login'))
    
    if request.method == 'POST':
        if 'audioFile' not in request.files:
            flash('No file selected', 'error')
            return redirect(request.url)
        
        file = request.files['audioFile']
        if file.filename == '':
            flash('No file selected', 'error')
            return redirect(request.url)
        
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            
            file_content = file.read()
            file.seek(0)
            
            result = detect_audio(file_content)
            
            if result['success']:
                cleanup_old_audio_files()
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                
                import librosa
                from io import BytesIO
                
                audio_original, sr = librosa.load(BytesIO(file_content), sr=52734)
                original_filename = f'original_{timestamp}.wav'
                original_path, original_size = save_audio_to_wav(audio_original, sr, original_filename)
                
                processed_filename = None
                processed_path = None
                processed_size = None
                fft_processed = None
                is_separated = False
                processed_label = "Processed Audio"

                if result.get('separation_applied') and result.get('audio_separated') is not None:
                    is_separated = True
                    processed_label = "Separated Audio"
                    processed_filename = f'separated_{timestamp}.wav'
                    processed_audio = np.array(result['audio_separated'])
                    processed_path, processed_size = save_audio_to_wav(processed_audio, sr, processed_filename)
                    
                    freqs, mags = extract_fft(processed_audio, sr=sr)
                    fft_processed = {
                        'frequencies': freqs.tolist(),
                        'magnitude': mags.tolist()
                    }

                elif result.get('audio_reduced') is not None:
                    processed_filename = f'reduced_{timestamp}.wav'
                    processed_audio = result['audio_reduced']
                    processed_path, processed_size = save_audio_to_wav(processed_audio, sr, processed_filename)
                    
                    fft_processed = result.get('fft_data_reduced')

                template_data = {
                    'filename': filename,
                    'predicted_class': result['predicted_class'],
                    'confidence': result['confidence'],
                    'total_duration': result['total_duration'],
                    'warning': result.get('warning'),
                    'error': result.get('error'),
                    
                    'fft_original': result.get('fft_data_original'),
                    'fft_processed': fft_processed,
                    
                    'audio_original_url': url_for('serve_audio', filename=original_filename),
                    'audio_processed_url': url_for('serve_audio', filename=processed_filename) if processed_filename else None,
                    
                    'processed_label': processed_label,
                    'is_separated': is_separated,
                    'original_file_size': original_size,
                    'processed_file_size': processed_size
                }
                
                flash('Audio analyzed successfully!', 'success')
                return render_template('upload_audio.html', result=template_data, **template_data)
                    
            else:
                flash(f"Error: {result.get('error', 'Unknown error')}", 'error')
                return redirect(request.url)
        
        flash('Invalid file type', 'error')
        return redirect(request.url)
    
    else:
        return render_template('upload_audio.html')

@app.route('/audio/<filename>')
def serve_audio(filename):
    try:
        audio_path = os.path.join(app.config['AUDIO_CACHE_FOLDER'], filename)
        if os.path.exists(audio_path):
            return send_file(
                audio_path,
                mimetype='audio/wav',
                as_attachment=False,
                download_name=filename
            )
        else:
            return "Audio file not found", 404
    except Exception as e:
        return str(e), 500

@app.route('/download_audio/<filename>')
def download_audio(filename):
    if not is_logged_in():
        return redirect(url_for('login'))
    
    try:
        audio_path = os.path.join(app.config['AUDIO_CACHE_FOLDER'], filename)
        if os.path.exists(audio_path):
            return send_file(
                audio_path,
                as_attachment=True,
                download_name=filename
            )
        else:
            flash('Audio file not found', 'error')
            return redirect(url_for('upload'))
    except Exception as e:
        flash(f'Error downloading audio: {str(e)}', 'error')
        return redirect(url_for('upload'))

@app.template_filter('get_sound_icon')
def get_sound_icon(sound_class):
    icons = {
        'Speedboat': 'fas fa-ship',
        'SpeedBoat': 'fas fa-ship',
        'UUV': 'fas fa-satellite',
        'Kaiyuan': 'fas fa-anchor',
        'KaiYuan': 'fas fa-anchor',
        'Unknown': 'fas fa-volume-mute',
        'Unknown Ship': 'fas fa-question-circle',
        'Ship (type unknown)': 'fas fa-question-circle',
        'Ship': 'fas fa-ship',
        'Error': 'fas fa-exclamation-triangle'
    }
    return icons.get(sound_class, 'fas fa-question-circle')

@app.template_filter('format_datetime')
def format_datetime(value):
    if not value:
        return "N/A"
    
    try:
        if isinstance(value, datetime):
            return value.strftime("%b %d, %Y %I:%M %p")
        
        if isinstance(value, str):
            try:
                dt = datetime.fromisoformat(value)
                return dt.strftime("%b %d, %Y %I:%M %p")
            except:
                for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"]:
                    try:
                        dt = datetime.strptime(value, fmt)
                        return dt.strftime("%b %d, %Y %I:%M %p")
                    except:
                        continue
        
        return str(value)
    
    except Exception as e:
        print(f"Error formatting datetime {value}: {e}")
        return str(value)

@app.route('/logs')
def logs():
    if not is_logged_in():
        return redirect(url_for('login'))
    
    detections = db_helper.get_user_detections(session['user_id'])
    return render_template('logs.html', detections=detections)

@app.route('/manage-account')
def manage_account():
    if not is_logged_in():
        return redirect(url_for('login'))
    
    user = db_helper.get_user_by_id(session['user_id'])
    if user and isinstance(user.get('created_at'), str):
        try:
            user['created_at'] = datetime.fromisoformat(user['created_at'])
        except Exception:
            user['created_at'] = None
    
    detections = db_helper.get_user_detections(session['user_id'])
    detections_count = len(detections)
    
    return render_template('manage_account.html', 
                         user=user, 
                         detections_count=detections_count)

@app.route('/update-account', methods=['POST'])
def update_account():
    if not is_logged_in():
        return redirect(url_for('login'))
    
    username = request.form.get('username').strip()
    email = request.form.get('email').strip()
    current_password = request.form.get('current_password')
    new_password = request.form.get('new_password')
    confirm_password = request.form.get('confirm_password')
    
    user_id = session['user_id']
    user = db_helper.get_user_by_id(user_id)

    if not db_helper.login_user(user['username'], current_password):
        flash('Current password is incorrect. Changes not saved.', 'error')
        return redirect(url_for('manage_account'))
    
    try:
        details_changed = False
        if username != user['username'] or email != user['email']:
            
            if username != user['username']:
                existing_user = db_helper.get_user_by_username(username) 
                if existing_user and existing_user['id'] != user_id:
                    flash('That username is already taken.', 'error')
                    return redirect(url_for('manage_account'))

            if email != user['email']:
                existing_email = db_helper.get_user_by_email(email)
                if existing_email and existing_email['id'] != user_id:
                    flash('That email is already in use.', 'error')
                    return redirect(url_for('manage_account'))
            
            db_helper.update_user_profile(user_id, username, email)
            
            session['username'] = username
            details_changed = True

        password_changed = False
        if new_password:
            if new_password != confirm_password:
                flash('New passwords do not match.', 'error')
                return redirect(url_for('manage_account'))
            elif len(new_password) < 6:
                flash('New password must be at least 6 characters.', 'error')
                return redirect(url_for('manage_account'))
            else:
                db_helper.update_user_password(email, new_password)
                password_changed = True

        if details_changed and password_changed:
            flash('Profile and password updated successfully!', 'success')
        elif details_changed:
            flash('Profile details updated successfully!', 'success')
        elif password_changed:
            flash('Password updated successfully!', 'success')
        else:
            flash('No changes were made.', 'warning')

    except Exception as e:
        flash(f'An error occurred: {str(e)}', 'error')
        print(f"Update Error: {e}")

    return redirect(url_for('manage_account'))

@app.route('/delete-account', methods=['POST'])
def delete_account():
    if not is_logged_in():
        return redirect(url_for('login'))
    
    user_id = session['user_id']
    current_password = request.form.get('current_password', '').strip()
    
    if not current_password:
        flash('Please enter your current password to delete your account', 'error')
        return redirect(url_for('manage_account'))
    
    user = db_helper.get_user_by_id(user_id)
    if not user:
        flash('User not found', 'error')
        return redirect(url_for('manage_account'))
    
    if not db_helper.login_user(user['username'], current_password):
        flash('Current password is incorrect', 'error')
        return redirect(url_for('manage_account'))
    
    try:
        db_helper.clear_user_detections(user_id)
        db_helper.delete_user(user_id)
        auth_service.logout()
        session.clear()
        
        flash('Your account has been successfully deleted', 'success')
        return redirect(url_for('login'))
        
    except Exception as e:
        flash(f'Error deleting account: {str(e)}', 'error')
        return redirect(url_for('manage_account'))

@app.route('/logout')
def logout():
    auth_service.logout()
    session.clear()
    return redirect(url_for('login'))

if __name__ == '__main__':
    app.run(debug=True, port=5000)