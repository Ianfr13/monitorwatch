-- MonitorWatch D1 Schema

-- Activities table: stores all captured events
CREATE TABLE IF NOT EXISTS activities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  local_date TEXT,              -- YYYY-MM-DD in user's timezone
  local_hour INTEGER,           -- 0-23 in user's timezone
  app_bundle_id TEXT,
  app_name TEXT,
  window_title TEXT,
  ocr_text TEXT,
  capture_mode TEXT CHECK(capture_mode IN ('full', 'screenshot', 'audio', 'metadata', 'ignore')),
  created_at TEXT DEFAULT (datetime('now'))
);

-- Audio transcripts
CREATE TABLE IF NOT EXISTS transcripts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  local_date TEXT,              -- YYYY-MM-DD in user's timezone
  local_hour INTEGER,           -- 0-23 in user's timezone
  text TEXT,
  source TEXT,
  duration_seconds INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Generated notes
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  date TEXT NOT NULL,
  note_number INTEGER DEFAULT 1,
  content TEXT,
  version INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Hourly summaries (pre-processed by cron)
CREATE TABLE IF NOT EXISTS hourly_summaries (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  date TEXT NOT NULL,
  hour INTEGER NOT NULL,
  summary TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_activities_user_timestamp ON activities(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_activities_local_date_hour ON activities(user_id, local_date, local_hour);
CREATE INDEX IF NOT EXISTS idx_transcripts_user_timestamp ON transcripts(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_transcripts_local_date_hour ON transcripts(user_id, local_date, local_hour);
CREATE INDEX IF NOT EXISTS idx_notes_user_date ON notes(user_id, date);

-- Unique constraint for one note per user per day per number
CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_unique ON notes(user_id, date, note_number);

-- Indexes for hourly summaries
CREATE INDEX IF NOT EXISTS idx_hourly_summaries_user_date ON hourly_summaries(user_id, date);
CREATE UNIQUE INDEX IF NOT EXISTS idx_hourly_summaries_unique ON hourly_summaries(user_id, date, hour);
