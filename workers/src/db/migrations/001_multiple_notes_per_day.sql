-- Migration: Support multiple notes per day
-- Run this on your D1 database to update the schema

-- Add note_number column to existing notes table
ALTER TABLE notes ADD COLUMN note_number INTEGER DEFAULT 1;

-- Update existing notes to have note_number = 1
UPDATE notes SET note_number = 1 WHERE note_number IS NULL;

-- Drop the old unique index
DROP INDEX IF EXISTS idx_notes_unique;

-- Create new unique index that includes note_number
CREATE UNIQUE INDEX idx_notes_unique ON notes(user_id, date, note_number);
