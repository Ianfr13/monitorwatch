import { Env, TranscriptPayload, Transcript } from '../types';
import { generateId, sanitizeString, isValidTimestamp } from '../utils';

// Max sizes to prevent abuse
const MAX_TEXT_LENGTH = 100_000; // 100KB max transcript
const MAX_SOURCE_LENGTH = 256;
const MAX_DURATION_SECONDS = 86400; // 24 hours max

// Extract local date/hour from ISO timestamp if not provided
function extractLocalDateTime(timestamp: string, providedDate?: string, providedHour?: number): { localDate: string; localHour: number } {
    if (providedDate && providedHour !== undefined) {
        return { localDate: providedDate, localHour: providedHour };
    }
    
    const date = new Date(timestamp);
    const tzMatch = timestamp.match(/([+-])(\d{2}):(\d{2})$/);
    
    if (tzMatch) {
        const sign = tzMatch[1] === '+' ? 1 : -1;
        const tzHours = parseInt(tzMatch[2], 10);
        const tzMinutes = parseInt(tzMatch[3], 10);
        const offsetMinutes = sign * (tzHours * 60 + tzMinutes);
        
        const utcTime = date.getTime();
        const localTime = new Date(utcTime + offsetMinutes * 60 * 1000);
        
        return {
            localDate: localTime.toISOString().slice(0, 10),
            localHour: localTime.getUTCHours()
        };
    }
    
    return {
        localDate: date.toISOString().slice(0, 10),
        localHour: date.getUTCHours()
    };
}

export async function handleTranscript(
    payload: TranscriptPayload,
    userId: string,
    env: Env
): Promise<{ success: boolean; id: string }> {
    // Validate required fields
    if (!payload.timestamp || !isValidTimestamp(payload.timestamp)) {
        throw new Error('Invalid or missing timestamp');
    }
    
    // Validate duration
    const duration = Number(payload.duration_seconds) || 0;
    if (duration < 0 || duration > MAX_DURATION_SECONDS) {
        throw new Error('Invalid duration');
    }

    const id = generateId();
    
    // Extract local date/hour for timezone-correct filtering
    const { localDate, localHour } = extractLocalDateTime(
        payload.timestamp,
        payload.local_date,
        payload.local_hour
    );

    // Sanitize inputs
    const sanitizedPayload = {
        timestamp: payload.timestamp,
        local_date: localDate,
        local_hour: localHour,
        text: sanitizeString(payload.text, MAX_TEXT_LENGTH),
        source: sanitizeString(payload.source, MAX_SOURCE_LENGTH),
        duration_seconds: Math.min(Math.max(0, duration), MAX_DURATION_SECONDS)
    };

    await env.DB.prepare(`
    INSERT INTO transcripts (id, user_id, timestamp, local_date, local_hour, text, source, duration_seconds)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
        id,
        userId,
        sanitizedPayload.timestamp,
        sanitizedPayload.local_date,
        sanitizedPayload.local_hour,
        sanitizedPayload.text,
        sanitizedPayload.source,
        sanitizedPayload.duration_seconds
    ).run();

    return { success: true, id };
}

export async function getTranscriptsForDate(
    date: string,
    userId: string,
    env: Env
): Promise<Transcript[]> {
    // Use local_date for timezone-correct filtering
    const result = await env.DB.prepare(`
    SELECT * FROM transcripts 
    WHERE user_id = ? 
    AND (local_date = ? OR (local_date IS NULL AND date(timestamp) = date(?)))
    ORDER BY timestamp ASC
  `).bind(userId, date, date).all();

    return result.results as unknown as Transcript[];
}
