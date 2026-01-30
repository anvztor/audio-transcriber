#!/usr/bin/env python3
"""
Semantic error correction module for audio transcription.
Handles homophonic errors, fuzzy matching, and user-specific vocabulary.
"""

import sys
import re
import json
from pathlib import Path
from difflib import SequenceMatcher

# User vocabulary file location
VOCAB_FILE = Path.home() / ".clawdbot" / "config" / "vocabulary.json"

# Default correction patterns (regex -> replacement)
# Ordered by specificity (more specific patterns first)
DEFAULT_CORRECTIONS = [
    # Clawdbot variations (most common)
    (r'\bcloud\s*boot\b', 'clawdbot'),
    (r'\bcloudboot\b', 'clawdbot'),
    (r'\bclowdbot\b', 'clawdbot'),
    (r'\bclawd\s*bot\b', 'clawdbot'),
    (r'\bcloud\s*bot\b', 'clawdbot'),

    # Processed variations
    (r'\bpro\s*system\b', 'processed'),
    (r'\bprocess\s*system\b', 'processed'),
    (r'\bprocess\s*ed\b', 'processed'),
    (r'\bprossed\b', 'processed'),
    (r'\bprosess\b', 'processed'),
    (r'\bprosed\b', 'processed'),

    # Directory name: anvz
    (r'\bAMVZ\b', 'anvz'),
    (r'\bamvz\b', 'anvz'),
    (r'\bAVZ\b', 'anvz'),
    (r'\bavz\b', 'anvz'),
    (r'\bAMZ\b', 'anvz'),
    (r'\bamz\b', 'anvz'),
    (r'\bANVZ\b', 'anvz'),

    # Chinese corrections
    (r'帮你', '帮我'),
]

# Known terms for fuzzy matching (term -> canonical form)
KNOWN_TERMS = {
    'clawdbot': 'clawdbot',
    'processed': 'processed',
    'anvz': 'anvz',
    'inbound': 'inbound',
    'outbound': 'outbound',
    'media': 'media',
}

# Fuzzy match threshold (0.0 - 1.0)
FUZZY_THRESHOLD = 0.75


def load_user_vocabulary():
    """Load user-specific vocabulary from config file."""
    if not VOCAB_FILE.exists():
        return {}, []

    try:
        with open(VOCAB_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            corrections = data.get('corrections', {})
            known_terms = data.get('known_terms', [])
            return corrections, known_terms
    except (json.JSONDecodeError, IOError):
        return {}, []


def fuzzy_match(word, known_terms, threshold=FUZZY_THRESHOLD):
    """
    Find best fuzzy match for a word in known terms.
    Returns (matched_term, similarity) or (None, 0) if no match.
    """
    best_match = None
    best_score = 0

    word_lower = word.lower()

    for term in known_terms:
        term_lower = term.lower()

        # Skip if word is already the term
        if word_lower == term_lower:
            return term, 1.0

        # Calculate similarity
        score = SequenceMatcher(None, word_lower, term_lower).ratio()

        if score > best_score and score >= threshold:
            best_score = score
            best_match = term

    return best_match, best_score


def apply_regex_corrections(text, patterns):
    """Apply regex-based corrections to text."""
    for pattern, replacement in patterns:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text


def apply_fuzzy_corrections(text, known_terms):
    """Apply fuzzy matching corrections for unknown words."""
    words = text.split()
    corrected_words = []

    for word in words:
        # Preserve punctuation
        prefix = ''
        suffix = ''
        clean_word = word

        # Extract leading/trailing punctuation
        while clean_word and not clean_word[0].isalnum():
            prefix += clean_word[0]
            clean_word = clean_word[1:]
        while clean_word and not clean_word[-1].isalnum():
            suffix = clean_word[-1] + suffix
            clean_word = clean_word[:-1]

        if clean_word:
            match, score = fuzzy_match(clean_word, known_terms)
            if match and score < 1.0:  # Only correct if not exact match
                clean_word = match

        corrected_words.append(prefix + clean_word + suffix)

    return ' '.join(corrected_words)


def correct_text(text):
    """
    Apply all corrections to text.
    1. Load user vocabulary
    2. Apply regex corrections (exact patterns)
    3. Apply fuzzy corrections (similar words)
    """
    if not text:
        return text

    # Load user vocabulary
    user_corrections, user_terms = load_user_vocabulary()

    # Combine default and user corrections
    all_patterns = DEFAULT_CORRECTIONS.copy()
    for pattern, replacement in user_corrections.items():
        all_patterns.append((pattern, replacement))

    # Combine known terms
    all_terms = list(KNOWN_TERMS.keys()) + user_terms

    # Apply corrections in order
    result = text

    # 1. Regex corrections (high confidence)
    result = apply_regex_corrections(result, all_patterns)

    # 2. Fuzzy corrections (lower confidence, only for unknown words)
    result = apply_fuzzy_corrections(result, all_terms)

    return result


def main():
    """Read from stdin, apply corrections, output to stdout."""
    text = sys.stdin.read().strip()
    corrected = correct_text(text)
    print(corrected)


if __name__ == '__main__':
    main()
