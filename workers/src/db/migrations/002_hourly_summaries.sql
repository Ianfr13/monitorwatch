-- Migration: Add hourly summaries table for chunked processing

CREATE TABLE IF NOT EXISTS hourly_summaries (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  date TEXT NOT NULL,
  hour INTEGER NOT NULL,
  summary TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_hourly_summaries_user_date ON hourly_summaries(user_id, date);
CREATE UNIQUE INDEX IF NOT EXISTS idx_hourly_summaries_unique ON hourly_summaries(user_id, date, hour);
