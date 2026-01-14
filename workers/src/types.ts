/**
 * MonitorWatch Types
 */

export interface Env {
    DB: D1Database;
    CONFIG: KVNamespace;
    GEMINI_API_KEY: string;
    API_SECRET_KEY: string;
    ENVIRONMENT: string;
}

export type CaptureMode = 'full' | 'screenshot' | 'audio' | 'metadata' | 'ignore';

export interface Activity {
    id: string;
    user_id: string;
    timestamp: string;
    local_date: string;      // YYYY-MM-DD in user's timezone
    local_hour: number;      // 0-23 in user's timezone
    app_bundle_id: string;
    app_name: string;
    window_title: string;
    ocr_text?: string;
    capture_mode: CaptureMode;
}

export interface Transcript {
    id: string;
    user_id: string;
    timestamp: string;
    local_date: string;      // YYYY-MM-DD in user's timezone
    local_hour: number;      // 0-23 in user's timezone
    text: string;
    source: string;
    duration_seconds: number;
}

export interface Note {
    id: string;
    user_id: string;
    date: string;
    note_number: number;
    content: string;
    version: number;
    created_at: string;
    updated_at: string;
}

export interface UserConfig {
    obsidian_vault_path: string;
    capture_modes: Record<string, CaptureMode>;
    url_patterns: Record<string, CaptureMode>;
    default_mode: CaptureMode;
    webhook_url?: string;
}

export interface ActivityPayload {
    timestamp: string;
    local_date?: string;     // YYYY-MM-DD in user's timezone (optional for backward compat)
    local_hour?: number;     // 0-23 in user's timezone (optional for backward compat)
    app_bundle_id: string;
    app_name: string;
    window_title: string;
    ocr_text?: string;
    capture_mode: CaptureMode;
    url?: string;
}

export interface TranscriptPayload {
    timestamp: string;
    local_date?: string;     // YYYY-MM-DD in user's timezone (optional for backward compat)
    local_hour?: number;     // 0-23 in user's timezone (optional for backward compat)
    text: string;
    source: string;
    duration_seconds: number;
}

export interface GenerateNoteRequest {
    date: string;
    force?: boolean;
}

export interface GenerateNoteResponse {
    success: boolean;
    note: string;
}

export interface AIConfig {
    provider: 'gemini' | 'openrouter';
    openRouterKey?: string;
    geminiKey?: string;
    models: {
        daily: string;   // e.g. "google/gemini-flash-1.5" or "anthropic/claude-3-haiku"
        meeting: string; // e.g. "anthropic/claude-3.5-sonnet"
    };
}

