import { Env, ActivityPayload, Activity } from '../types';
import { generateId, sanitizeString, isValidTimestamp, isValidCaptureMode } from '../utils';

// Max sizes to prevent abuse
const MAX_APP_NAME_LENGTH = 256;
const MAX_WINDOW_TITLE_LENGTH = 1024;
const MAX_OCR_TEXT_LENGTH = 50_000; // 50KB max OCR text
const MAX_BUNDLE_ID_LENGTH = 256;

export async function handleActivity(
    payload: ActivityPayload,
    userId: string,
    env: Env
): Promise<{ success: boolean; id: string }> {
    // Validate required fields
    if (!payload.timestamp || !isValidTimestamp(payload.timestamp)) {
        throw new Error('Invalid or missing timestamp');
    }
    
    if (!payload.capture_mode || !isValidCaptureMode(payload.capture_mode)) {
        throw new Error('Invalid capture mode');
    }

    const id = generateId();

    // Sanitize and truncate all string inputs
    const sanitizedPayload = {
        timestamp: payload.timestamp,
        app_bundle_id: sanitizeString(payload.app_bundle_id, MAX_BUNDLE_ID_LENGTH),
        app_name: sanitizeString(payload.app_name, MAX_APP_NAME_LENGTH),
        window_title: sanitizeString(payload.window_title, MAX_WINDOW_TITLE_LENGTH),
        ocr_text: payload.ocr_text ? sanitizeString(payload.ocr_text, MAX_OCR_TEXT_LENGTH) : null,
        capture_mode: payload.capture_mode
    };

    await env.DB.prepare(`
    INSERT INTO activities (id, user_id, timestamp, app_bundle_id, app_name, window_title, ocr_text, capture_mode)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
        id,
        userId,
        sanitizedPayload.timestamp,
        sanitizedPayload.app_bundle_id,
        sanitizedPayload.app_name,
        sanitizedPayload.window_title,
        sanitizedPayload.ocr_text,
        sanitizedPayload.capture_mode
    ).run();

    return { success: true, id };
}

export async function getActivitiesForDate(
    date: string,
    userId: string,
    env: Env
): Promise<Activity[]> {
    const result = await env.DB.prepare(`
    SELECT * FROM activities 
    WHERE user_id = ? 
    AND date(timestamp) = date(?)
    ORDER BY timestamp ASC
  `).bind(userId, date).all();

    return result.results as unknown as Activity[];
}
