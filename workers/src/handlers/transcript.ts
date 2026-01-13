import { Env, TranscriptPayload, Transcript } from '../types';
import { generateId, sanitizeString, isValidTimestamp } from '../utils';

// Max sizes to prevent abuse
const MAX_TEXT_LENGTH = 100_000; // 100KB max transcript
const MAX_SOURCE_LENGTH = 256;
const MAX_DURATION_SECONDS = 86400; // 24 hours max

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

    // Sanitize inputs
    const sanitizedPayload = {
        timestamp: payload.timestamp,
        text: sanitizeString(payload.text, MAX_TEXT_LENGTH),
        source: sanitizeString(payload.source, MAX_SOURCE_LENGTH),
        duration_seconds: Math.min(Math.max(0, duration), MAX_DURATION_SECONDS)
    };

    await env.DB.prepare(`
    INSERT INTO transcripts (id, user_id, timestamp, text, source, duration_seconds)
    VALUES (?, ?, ?, ?, ?, ?)
  `).bind(
        id,
        userId,
        sanitizedPayload.timestamp,
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
    const result = await env.DB.prepare(`
    SELECT * FROM transcripts 
    WHERE user_id = ? 
    AND date(timestamp) = date(?)
    ORDER BY timestamp ASC
  `).bind(userId, date).all();

    return result.results as unknown as Transcript[];
}
