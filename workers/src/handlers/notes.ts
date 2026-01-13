import { Env, GenerateNoteRequest, Note, Activity, Transcript } from '../types';
import { generateId, isValidDateString, isValidTimestamp, sanitizeString } from '../utils';
import { getActivitiesForDate } from './activity';
import { getTranscriptsForDate } from './transcript';
import { generateNoteWithAI, generateMeetingNoteWithAI } from '../ai';
import { getHourlySummaries, processAllHoursForDate } from './summaries';

// Helper to get AI config from request headers
function getAIConfigFromRequest(request: Request) {
    const openRouterKey = request.headers.get('X-OpenRouter-Key');
    const language = request.headers.get('X-Note-Language') || 'en';
    
    if (openRouterKey) {
        return {
            provider: 'openrouter',
            openRouterKey: openRouterKey,
            model: 'google/gemini-2.0-flash-001',
            language: language
        };
    }
    return undefined;
}

export async function handleGenerateNote(
    payload: GenerateNoteRequest,
    userId: string,
    env: Env,
    request: Request
): Promise<{ success: boolean; note: string; noteNumber: number }> {
    const { date } = payload;

    // Validate date format
    if (!date || !isValidDateString(date)) {
        throw new Error('Invalid date format. Expected YYYY-MM-DD');
    }

    // Get activities and transcripts for the date
    const activities = await getActivitiesForDate(date, userId, env);
    const transcripts = await getTranscriptsForDate(date, userId, env);

    if (activities.length === 0 && transcripts.length === 0) {
        return { success: false, note: '' };
    }

    // Get AI config from request headers
    const aiConfig = getAIConfigFromRequest(request);
    
    if (!aiConfig?.openRouterKey) {
        throw new Error('OpenRouter API key not provided. Configure it in Settings.');
    }

    // Count existing notes for this date to get next note number
    const countResult = await env.DB.prepare(`
        SELECT COUNT(*) as count FROM notes WHERE user_id = ? AND date = ?
    `).bind(userId, date).first() as { count: number } | null;
    const noteNumber = (countResult?.count || 0) + 1;

    // Get pre-processed hourly summaries if available
    let hourlySummaries = await getHourlySummaries(userId, date, env);
    
    // If no summaries, process them now (slower but ensures data)
    if (hourlySummaries.length === 0 && aiConfig?.openRouterKey) {
        await processAllHoursForDate(userId, date, env, aiConfig.openRouterKey, aiConfig.model, aiConfig.language);
        hourlySummaries = await getHourlySummaries(userId, date, env);
    }

    // Generate note with AI using summaries or raw data
    const content = await generateNoteWithAI(activities, transcripts, date, env, aiConfig, noteNumber, hourlySummaries);

    // Insert new note with note_number
    const id = generateId();
    await env.DB.prepare(`
        INSERT INTO notes (id, user_id, date, note_number, content, version, updated_at)
        VALUES (?, ?, ?, ?, ?, 1, datetime('now'))
    `).bind(id, userId, date, noteNumber, content).run();

    return { success: true, note: content, noteNumber };
}

export async function handleGetNote(
    date: string,
    userId: string,
    env: Env
): Promise<{ note: Note | null }> {
    const note = await getNote(date, userId, env);
    return { note };
}

async function getNote(date: string, userId: string, env: Env): Promise<Note | null> {
    // Get the latest note for the date
    const result = await env.DB.prepare(`
        SELECT * FROM notes WHERE user_id = ? AND date = ?
        ORDER BY note_number DESC LIMIT 1
    `).bind(userId, date).first();

    return result as Note | null;
}

async function getNotesForDate(date: string, userId: string, env: Env): Promise<Note[]> {
    const result = await env.DB.prepare(`
        SELECT * FROM notes WHERE user_id = ? AND date = ?
        ORDER BY note_number ASC
    `).bind(userId, date).all();

    return (result.results || []) as unknown as Note[];
}

export async function handleGenerateMeetingNote(
    payload: { startTime: string; endTime: string; context: string },
    userId: string,
    env: Env,
    request: Request
): Promise<{ success: boolean; note: string; filename: string }> {
    const { startTime, endTime, context } = payload;

    // Validate timestamps
    if (!startTime || !isValidTimestamp(startTime)) {
        throw new Error('Invalid startTime format');
    }
    if (!endTime || !isValidTimestamp(endTime)) {
        throw new Error('Invalid endTime format');
    }
    
    // Validate time range (max 24 hours)
    const start = new Date(startTime);
    const end = new Date(endTime);
    if (end.getTime() - start.getTime() > 24 * 60 * 60 * 1000) {
        throw new Error('Time range cannot exceed 24 hours');
    }
    if (end.getTime() < start.getTime()) {
        throw new Error('endTime must be after startTime');
    }

    // Sanitize context
    const sanitizedContext = sanitizeString(context, 500);

    // Get data within range
    const activities = await getActivitiesRange(startTime, endTime, userId, env);
    const transcripts = await getTranscriptsRange(startTime, endTime, userId, env);

    // Get AI config from request headers
    const aiConfig = getAIConfigFromRequest(request);
    
    if (!aiConfig?.openRouterKey) {
        throw new Error('OpenRouter API key not provided. Configure it in Settings.');
    }

    // Generate specialized note
    const { content, title } = await generateMeetingNoteWithAI(activities, transcripts, sanitizedContext, startTime, env, aiConfig);

    // Format filename safe string
    const dateStr = new Date(startTime).toISOString().split('T')[0];
    const safeTitle = title.replace(/[^a-zA-Z0-9_\-\s]/g, '').trim();
    const filename = `Meetings/${dateStr} - ${safeTitle}.md`;

    return { success: true, note: content, filename };
}

async function getActivitiesRange(start: string, end: string, userId: string, env: Env): Promise<Activity[]> {
    const result = await env.DB.prepare(`
        SELECT * FROM activities 
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC
    `).bind(userId, start, end).all();
    return (result.results || []) as unknown as Activity[];
}

async function getTranscriptsRange(start: string, end: string, userId: string, env: Env): Promise<Transcript[]> {
    const result = await env.DB.prepare(`
        SELECT * FROM transcripts 
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp ASC
    `).bind(userId, start, end).all();
    return (result.results || []) as unknown as Transcript[];
}
