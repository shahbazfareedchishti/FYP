import secrets
import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from models import DatabaseHelper
from datetime import datetime, timedelta

class AuthService:
    def __init__(self, db_helper=None):
        self.db_helper = db_helper if db_helper else DatabaseHelper()
        self._current_user_id = None
        self._current_username = None
    
    @property
    def current_user_id(self):
        return self._current_user_id
    
    @property
    def current_username(self):
        return self._current_username
    
    @property
    def is_logged_in(self):
        return self._current_user_id is not None
    
    def request_password_reset(self, email):
        try:
            user = self.db_helper.get_user_by_email(email)
            if user is None:
                raise Exception('No account found with this email')

            token = self._generate_random_token()
            self.db_helper.set_password_reset_token(email, token)
            
            print(f'Generated reset token for {email}: {token}')
            
            email_sent = self._send_password_reset_email(email, token)
            
            if email_sent:
                return 'Password reset instructions sent to your email'
            else:
                raise Exception('Failed to send reset email. Please try again.')
        except Exception as e:
            print(f'Error in request_password_reset: {e}')
            raise
    
    def _send_password_reset_email(self, email, token):
        try:
            print(f'Attempting to send email to: {email}')
            
            gmail_username = os.getenv('GMAIL_EMAIL')
            gmail_password = os.getenv('GMAIL_PASSWORD')
            
            print('Environment variables loaded successfully')
            print(f'Gmail Email: {gmail_username}')
            print(f'Gmail Password: {"***" if gmail_password else "NOT SET"}')

            if not gmail_username or not gmail_password:
                raise Exception('Gmail credentials are empty. Check your environment variables')

            message = MIMEMultipart('alternative')
            message['From'] = f'Sound Detector App <{gmail_username}>'
            message['To'] = email
            message['Subject'] = 'Password Reset Code - Sound Detector App'

            text = f'''Password Reset Request

Hello,

You requested to reset your password for Sound Detector App.

Your reset code is: {token}

To reset your password:
1. Open the Sound Detector App
2. Go to Reset Password screen
3. Enter this code: {token}
4. Create your new password

This code will expire in 1 hour.

If you didn't request this reset, please ignore this email.

Best regards,
MaritimeSoundDetector Team
(This is an automated message, please do not reply.)'''

            html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background-color: #f4f4f4; }}
        .container {{ max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }}
        .header {{ background: linear-gradient(135deg, #8C6EF2, #DE0E6F); padding: 30px 20px; text-align: center; color: white; }}
        .header h1 {{ margin: 0; font-size: 28px; font-weight: bold; }}
        .content {{ padding: 30px; }}
        .token-box {{ background: #f8f9fa; padding: 20px; border-radius: 8px; border: 2px dashed #8C6EF2; margin: 20px 0; text-align: center; }}
        .token {{ font-size: 24px; font-weight: bold; letter-spacing: 3px; color: #8C6EF2; margin: 10px 0; }}
        .warning {{ background: #fff3cd; border: 1px solid #ffeaa7; border-radius: 6px; padding: 15px; margin: 20px 0; }}
        .footer {{ margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; color: #666; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Sound Detector</h1>
            <p>Password Reset Code</p>
        </div>
        <div class="content">
            <h2>Hello,</h2>
            <p>You requested to reset your password for Sound Detector App.</p>
            
            <div class="token-box">
                <h3>Your Reset Code:</h3>
                <div class="token">{token}</div>
                <p>Enter this code in the app to reset your password</p>
            </div>
            
            <h4>Instructions:</h4>
            <ol>
                <li>Open the Sound Detector App</li>
                <li>Go to Reset Password screen</li>
                <li>Enter the code above</li>
                <li>Create your new password</li>
            </ol>
            
            <div class="warning">
                <strong>Important:</strong> 
                <ul>
                    <li>This code expires in 1 hour</li>
                    <li>Do not share this code with anyone</li>
                    <li>If you didn't request this reset, please ignore this email</li>
                </ul>
            </div>
            
            <div class="footer">
                <p>Best regards,<br><strong>Sound Detector Team</strong></p>
                <p><em>This is an automated message, please do not reply to this email.</em></p>
            </div>
        </div>
    </div>
</body>
</html>'''
            message.attach(MIMEText(text, 'plain'))
            message.attach(MIMEText(html, 'html'))

            print('Sending email via Gmail SMTP...')
            with smtplib.SMTP('smtp.gmail.com', 587) as server:
                server.starttls()
                server.login(gmail_username, gmail_password)
                server.send_message(message)
            
            print(f'Email sent successfully to: {email}')
            print(f'Reset token: {token}')
            
            return True
        except Exception as e:
            print(f'Gmail SMTP Email sending error: {e}')
            
            error_str = str(e)
            if '535' in error_str or 'Authentication' in error_str:
                raise Exception('Gmail authentication failed. Please verify your App Password is correct and 2FA is enabled.')
            elif 'Username and Password not accepted' in error_str:
                raise Exception('Gmail login failed. Please use an App Password instead of your regular password.')
            else:
                raise Exception(f'Failed to send email: {error_str}')
    
    def reset_password(self, token, new_password):
        user = self.db_helper.get_user_by_reset_token(token)
        if user:
            email = user['email']
            result = self.db_helper.update_user_password(email, new_password)
            return result > 0
        return False
    
    def _generate_random_token(self):
        return secrets.token_urlsafe(12).upper().replace('-', '').replace('_', '')[:12]
    
    def register(self, username, email, password):
        try:
            user_id = self.db_helper.register_user(username, email, password)
            return True
        except Exception as e:
            raise Exception(str(e))
    
    def login(self, username, password):
        user = self.db_helper.login_user(username, password)
        
        if user:
            self._current_user_id = user['id']
            self._current_username = user['username']
            return True
        
        return False
    
    def logout(self):
        self._current_user_id = None
        self._current_username = None