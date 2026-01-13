import { Env, GenerateNoteRequest, Note, Activity, Transcript } from '../types';
import { generateId, isValidDateString, isValidTimestamp, sanitizeString } from '../utils';
import { getActivitiesForDate } from './activity';
import { getTranscriptsForDate } from './transcript';
import { generateNoteWithAI, generateMeetingNoteWithAI } from '../ai';

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
): Promise<{ success: boolean; note: string }> {
    const { date, force } = payload;

    // Validate date format
    if (!date || !isValidDateString(date)) {
        throw new Error('Invalid date format. Expected YYYY-MM-DD');
    }

    // Check if note exists and force is not set
    if (!force) {
        const existing = await getNote(date, userId, env);
        if (existing) {
            return { success: true, note: existing.content };
        }
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

    // Generate note with AI
    const content = await generateNoteWithAI(activities, transcripts, date, env, aiConfig);

    // Upsert note
    const id = generateId();
    await env.DB.prepare(`
    INSERT INTO notes (id, user_id, date, content, version, updated_at)
    VALUES (?, ?, ?, ?, 1, datetime('now'))
    ON CONFLICT(user_id, date) DO UPDATE SET
      content = excluded.content,
      version = notes.version + 1,
      updated_at = datetime('now')
  `).bind(id, userId, date, content).run();

    return { success: true, note: content };
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
    const result = await env.DB.prepare(`
    SELECT * FROM notes WHERE user_id = ? AND date = ?
  `).bind(userId, date).first();

    return result as Note | null;
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
