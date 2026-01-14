import { Env, ActivityPayload, Activity } from '../types';
import { generateId, sanitizeString, isValidTimestamp, isValidCaptureMode } from '../utils';

// Max sizes to prevent abuse
const MAX_APP_NAME_LENGTH = 256;
const MAX_WINDOW_TITLE_LENGTH = 1024;
const MAX_OCR_TEXT_LENGTH = 50_000; // 50KB max OCR text
const MAX_BUNDLE_ID_LENGTH = 256;

// Extract local date/hour from ISO timestamp if not provided
// Falls back to parsing the timestamp's offset to compute local time
function extractLocalDateTime(timestamp: string, providedDate?: string, providedHour?: number): { localDate: string; localHour: number } {
    // If client provided local date/hour, use them
    if (providedDate && providedHour !== undefined) {
        return { localDate: providedDate, localHour: providedHour };
    }
    
    // Parse ISO timestamp and extract local time from it
    // Format: 2026-01-13T22:52:00.000-03:00
    const date = new Date(timestamp);
    
    // If timestamp has timezone offset, the Date object already represents the correct instant
    // We need to format it in the original timezone, not UTC
    // Try to extract timezone offset from the string
    const tzMatch = timestamp.match(/([+-])(\d{2}):(\d{2})$/);
    
    if (tzMatch) {
        // Has explicit timezone offset
        const sign = tzMatch[1] === '+' ? 1 : -1;
        const tzHours = parseInt(tzMatch[2], 10);
        const tzMinutes = parseInt(tzMatch[3], 10);
        const offsetMinutes = sign * (tzHours * 60 + tzMinutes);
        
        // Get UTC time and apply offset to get local time
        const utcTime = date.getTime();
        const localTime = new Date(utcTime + offsetMinutes * 60 * 1000);
        
        // Format as local date/hour (using UTC methods since we already applied offset)
        const localDate = localTime.toISOString().slice(0, 10);
        const localHour = localTime.getUTCHours();
        
        return { localDate, localHour };
    }
    
    // No timezone info - treat as UTC (less accurate but backward compatible)
    return {
        localDate: date.toISOString().slice(0, 10),
        localHour: date.getUTCHours()
    };
}

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
    
    // Extract local date/hour for timezone-correct filtering
    const { localDate, localHour } = extractLocalDateTime(
        payload.timestamp, 
        payload.local_date, 
        payload.local_hour
    );

    // Sanitize and truncate all string inputs
    const sanitizedPayload = {
        timestamp: payload.timestamp,
        local_date: localDate,
        local_hour: localHour,
        app_bundle_id: sanitizeString(payload.app_bundle_id, MAX_BUNDLE_ID_LENGTH),
        app_name: sanitizeString(payload.app_name, MAX_APP_NAME_LENGTH),
        window_title: sanitizeString(payload.window_title, MAX_WINDOW_TITLE_LENGTH),
        ocr_text: payload.ocr_text ? sanitizeString(payload.ocr_text, MAX_OCR_TEXT_LENGTH) : null,
        capture_mode: payload.capture_mode
    };

    await env.DB.prepare(`
    INSERT INTO activities (id, user_id, timestamp, local_date, local_hour, app_bundle_id, app_name, window_title, ocr_text, capture_mode)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
        id,
        userId,
        sanitizedPayload.timestamp,
        sanitizedPayload.local_date,
        sanitizedPayload.local_hour,
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
    // Use local_date for timezone-correct filtering
    // Falls back to UTC-based date() for backward compatibility with old data
    const result = await env.DB.prepare(`
    SELECT * FROM activities 
    WHERE user_id = ? 
    AND (local_date = ? OR (local_date IS NULL AND date(timestamp) = date(?)))
    ORDER BY timestamp ASC
  `).bind(userId, date, date).all();

    return result.results as unknown as Activity[];
}
