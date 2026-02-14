import sqlite3
import os
import threading
from datetime import datetime, timedelta

class DatabaseHelper:
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(DatabaseHelper, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
            
        self.db_path = 'sound_detector.db'
        self._initialized = True
    
    def get_connection(self):
        if not hasattr(thread_local, 'db_connection'):
            thread_local.db_connection = self._init_database()
        return thread_local.db_connection
    
    @property
    def database(self):
        return self.get_connection()
    
    def init_db(self):
        conn = self._init_database()
        conn.close()
    
    def _init_database(self):
        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        
        cursor = conn.cursor()
        cursor.execute('PRAGMA user_version')
        current_version = cursor.fetchone()[0] or 0
        
        if current_version == 0:
            self._create_tables(conn)
            cursor.execute('PRAGMA user_version = 3')
        elif current_version < 3:
            self._upgrade_database(conn, current_version, 3)
            cursor.execute('PRAGMA user_version = 3')
        
        conn.commit()
        try:
            cursor.execute("PRAGMA table_info(sound_detections)")
            cols = [row[1] for row in cursor.fetchall()]
            if 'raw_data' not in cols:
                cursor.execute('ALTER TABLE sound_detections ADD COLUMN raw_data TEXT')
                conn.commit()
        except Exception:
            pass
        return conn
    
    def _create_tables(self, db):
        cursor = db.cursor()
        
        cursor.execute('''
            CREATE TABLE users(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL,  
                created_at TEXT NOT NULL,
                reset_token TEXT,
                reset_token_expiry TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE sound_detections(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                sound_class TEXT NOT NULL,
                confidence REAL NOT NULL,
                timestamp TEXT NOT NULL,
                raw_data TEXT,
                latitude REAL,
                longitude REAL,
                FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
            )
        ''')
        
        cursor.execute('CREATE INDEX idx_user_id ON sound_detections(user_id)')
        cursor.execute('CREATE INDEX idx_timestamp ON sound_detections(timestamp)')
    
    def _upgrade_database(self, db, old_version, new_version):
        cursor = db.cursor()
        
        if old_version < 2:
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS sound_detections(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    sound_class TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    timestamp TEXT NOT NULL,
                    raw_data TEXT,
                    latitude REAL,
                    longitude REAL,
                    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
                )
            ''')
        
        if old_version < 3:
            cursor.execute("PRAGMA table_info(users)")
            columns = [column[1] for column in cursor.fetchall()]
            
            if 'reset_token' not in columns:
                cursor.execute('ALTER TABLE users ADD COLUMN reset_token TEXT')
            if 'reset_token_expiry' not in columns:
                cursor.execute('ALTER TABLE users ADD COLUMN reset_token_expiry TEXT')

            cursor.execute("PRAGMA table_info(sound_detections)")
            sd_cols = [column[1] for column in cursor.fetchall()]
            if 'raw_data' not in sd_cols:
                cursor.execute('ALTER TABLE sound_detections ADD COLUMN raw_data TEXT')
    
    def register_user(self, username, email, password):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM users WHERE username = ? OR email = ?',
            (username, email)
        )
        existing_user = cursor.fetchone()
        
        if existing_user:
            raise Exception('Username or email already exists')
        
        cursor.execute(
            'INSERT INTO users (username, email, password, created_at) VALUES (?, ?, ?, ?)',
            (username, email, password, datetime.now().isoformat())
        )
        user_id = cursor.lastrowid
        conn.commit()
        return user_id
    
    def login_user(self, username, password):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM users WHERE username = ? AND password = ?',
            (username, password)
        )
        user = cursor.fetchone()
        
        return dict(user) if user else None
    
    def get_user_by_email(self, email):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM users WHERE email = ?',
            (email,)
        )
        user = cursor.fetchone()
        
        return dict(user) if user else None

    def get_user_by_id(self, user_id):
        conn = self.get_connection()
        cursor = conn.cursor()

        cursor.execute(
            'SELECT * FROM users WHERE id = ?',
            (user_id,)
        )
        user = cursor.fetchone()

        return dict(user) if user else None
    
    def set_password_reset_token(self, email, token):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        expiry = (datetime.now() + timedelta(hours=1)).isoformat()
        cursor.execute(
            'UPDATE users SET reset_token = ?, reset_token_expiry = ? WHERE email = ?',
            (token, expiry, email)
        )
        conn.commit()
    
    def get_user_by_reset_token(self, token):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM users WHERE reset_token = ?',
            (token,)
        )
        user = cursor.fetchone()
        
        if user:
            user_dict = dict(user)
            expiry_string = user_dict.get('reset_token_expiry')
            
            if expiry_string:
                try:
                    expiry = datetime.fromisoformat(expiry_string)
                    if expiry > datetime.now():
                        return user_dict
                except Exception as e:
                    print(f'Error parsing expiry date: {e}')
        
        return None
    
    def update_user_password(self, email, new_password):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'UPDATE users SET password = ?, reset_token = NULL, reset_token_expiry = NULL WHERE email = ?',
            (new_password, email)
        )
        conn.commit()
        return cursor.rowcount
    
    def insert_detection(self, user_id, sound_class, confidence):
        conn = self.get_connection()
        cursor = conn.cursor()

        cursor.execute(
            'INSERT INTO sound_detections (user_id, sound_class, confidence, timestamp, raw_data, latitude, longitude) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (user_id, sound_class, confidence, datetime.now().isoformat(), None, None, None)
        )
        detection_id = cursor.lastrowid
        conn.commit()
        return detection_id

    def insert_detection_with_raw(self, user_id, sound_class, confidence, raw_data):
        conn = self.get_connection()
        cursor = conn.cursor()
        cursor.execute(
            'INSERT INTO sound_detections (user_id, sound_class, confidence, timestamp, raw_data, latitude, longitude) VALUES (?, ?, ?, ?, ?, ?, ?)',
            (user_id, sound_class, confidence, datetime.now().isoformat(), raw_data, None, None)
        )
        detection_id = cursor.lastrowid
        conn.commit()
        return detection_id
    
    def get_user_detections(self, user_id):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM sound_detections WHERE user_id = ? ORDER BY timestamp DESC',
            (user_id,)
        )
        detections = cursor.fetchall()
        
        return [dict(detection) for detection in detections]
    
    def delete_user_detection(self, detection_id):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'DELETE FROM sound_detections WHERE id = ?',
            (detection_id,)
        )
        conn.commit()
        return cursor.rowcount
    
    # --- ADD THESE METHODS TO YOUR DatabaseHelper CLASS ---

    def get_user_by_username(self, username):
        """Check if a username already exists (used during profile update)"""
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM users WHERE username = ?',
            (username,)
        )
        user = cursor.fetchone()
        
        return dict(user) if user else None

    def update_user_profile(self, user_id, new_username, new_email):
        """Updates the username and email for a logged-in user"""
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'UPDATE users SET username = ?, email = ? WHERE id = ?',
            (new_username, new_email, user_id)
        )
        conn.commit()
        return cursor.rowcount

    def delete_user(self, user_id):
        """Permanently deletes a user account"""
        conn = self.get_connection()
        cursor = conn.cursor()
        
        # Note: Because of ON DELETE CASCADE in your table creation, 
        # deleting the user will automatically delete their sound_detections too.
        cursor.execute(
            'DELETE FROM users WHERE id = ?',
            (user_id,)
        )
        conn.commit()
        return cursor.rowcount
    
    def clear_user_detections(self, user_id):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'DELETE FROM sound_detections WHERE user_id = ?',
            (user_id,)
        )
        conn.commit()

thread_local = threading.local()