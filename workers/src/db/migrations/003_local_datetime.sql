-- Migration 003: Add local datetime fields for timezone-correct filtering
-- Problem: SQLite's date() and strftime() use UTC, causing wrong hour/date filtering

-- Add local_date and local_hour to activities
ALTER TABLE activities ADD COLUMN local_date TEXT;
ALTER TABLE activities ADD COLUMN local_hour INTEGER;

-- Add local_date and local_hour to transcripts  
ALTER TABLE transcripts ADD COLUMN local_date TEXT;
ALTER TABLE transcripts ADD COLUMN local_hour INTEGER;

-- Create indexes for the new columns
CREATE INDEX IF NOT EXISTS idx_activities_local_date_hour ON activities(user_id, local_date, local_hour);
CREATE INDEX IF NOT EXISTS idx_transcripts_local_date_hour ON transcripts(user_id, local_date, local_hour);
