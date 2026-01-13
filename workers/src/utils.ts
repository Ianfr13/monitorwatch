/**
 * Utility Functions
 */

/**
 * Generate a unique ID (UUID v4 style using crypto for better randomness)
 */
export function generateId(): string {
    // Use crypto.randomUUID if available (Cloudflare Workers support it)
    if (typeof crypto !== 'undefined' && crypto.randomUUID) {
        return crypto.randomUUID();
    }
    // Fallback to manual generation
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        const v = c === 'x' ? r : (r & 0x3) | 0x8;
        return v.toString(16);
    });
}

/**
 * Get today's date in YYYY-MM-DD format
 */
export function getTodayDate(): string {
    return new Date().toISOString().split('T')[0];
}

/**
 * Truncate text to a maximum length
 */
export function truncate(text: string, maxLength: number): string {
    if (text.length <= maxLength) return text;
    return text.slice(0, maxLength - 3) + '...';
}

/**
 * Check if a URL matches a pattern (supports * wildcards)
 */
export function matchesPattern(url: string, pattern: string): boolean {
    const regex = new RegExp(
        '^' + pattern.replace(/\*/g, '.*').replace(/\?/g, '.') + '$',
        'i'
    );
    return regex.test(url);
}

/**
 * Sanitize string input: remove null bytes, trim, and truncate
 */
export function sanitizeString(input: string | undefined | null, maxLength: number): string {
    if (!input) return '';
    
    // Remove null bytes and other control characters (except newlines/tabs)
    const cleaned = input
        .replace(/\0/g, '')
        .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
        .trim();
    
    // Truncate to max length
    if (cleaned.length > maxLength) {
        return cleaned.slice(0, maxLength);
    }
    
    return cleaned;
}

/**
 * Validate ISO 8601 timestamp format
 */
export function isValidTimestamp(timestamp: string): boolean {
    if (!timestamp || typeof timestamp !== 'string') return false;
    
    // Must be ISO 8601 format
    const iso8601Regex = /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:?\d{2})?)?$/;
    if (!iso8601Regex.test(timestamp)) return false;
    
    // Must be a valid date
    const date = new Date(timestamp);
    if (isNaN(date.getTime())) return false;
    
    // Must not be in the future (with 5 min tolerance for clock skew)
    const fiveMinutesFromNow = Date.now() + 5 * 60 * 1000;
    if (date.getTime() > fiveMinutesFromNow) return false;
    
    // Must not be too old (1 year max)
    const oneYearAgo = Date.now() - 365 * 24 * 60 * 60 * 1000;
    if (date.getTime() < oneYearAgo) return false;
    
    return true;
}

/**
 * Validate capture mode
 */
export function isValidCaptureMode(mode: string): boolean {
    const validModes = ['full', 'screenshot', 'audio', 'metadata', 'ignore'];
    return validModes.includes(mode);
}

/**
 * Validate date string format (YYYY-MM-DD)
 */
export function isValidDateString(date: string): boolean {
    if (!date || typeof date !== 'string') return false;
    
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(date)) return false;
    
    const parsed = new Date(date);
    return !isNaN(parsed.getTime());
}
